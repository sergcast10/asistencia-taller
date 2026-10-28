import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/workshop.dart';
import '../models/student.dart';
import '../models/session.dart';
import '../models/attendance_record.dart';
import '../services/storage_service.dart';
import '../services/qr_service.dart';
import '../database/powersync_service.dart';

class AttendanceProcessResult {
  final bool success;
  final String title;
  final String message;
  final AttendanceStatus? status;
  final Student? student;

  AttendanceProcessResult({
    required this.success,
    required this.title,
    required this.message,
    this.status,
    this.student,
  });
}

class AttendanceProvider extends ChangeNotifier {
  List<Workshop> _workshops = [];
  bool _isLoading = true;
  String _webBaseUrl = '';
  final Uuid _uuid = const Uuid();

  static const String defaultPublicUrl =
      'https://sergcast10.github.io/asistencia-taller/';

  List<Workshop> get workshops => _workshops;
  bool get isLoading => _isLoading;
  String get webBaseUrl => _webBaseUrl;

  AttendanceProvider() {
    loadData();
  }

  Future<void> loadData() async {
    _isLoading = true;
    notifyListeners();

    // Cargar URL base web guardada o usar la de GitHub Pages por defecto
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('system_web_base_url') ?? '';
    if (saved.isEmpty || saved.contains('mitaller.web.app') || saved.contains('supabase.co/storage')) {
      _webBaseUrl = defaultPublicUrl;
      await prefs.setString('system_web_base_url', _webBaseUrl);
    } else {
      _webBaseUrl = saved;
    }
    if (_webBaseUrl.isEmpty && kIsWeb) {
      _webBaseUrl = Uri.base.origin;
    }

    // Inicializar PowerSync SQLite
    await PowerSyncService().initialize();

    _workshops = await StorageService.loadWorkshops();
    _isLoading = false;
    notifyListeners();
  }

  Future<void> setWebBaseUrl(String url) async {
    _webBaseUrl = url.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('system_web_base_url', _webBaseUrl);
    notifyListeners();
  }

  Future<void> _persist() async {
    await StorageService.saveWorkshops(_workshops);
    // Persistir en SQLite via PowerSync
    for (var w in _workshops) {
      await PowerSyncService().persistWorkshop(w);
    }
    notifyListeners();
  }

  // --- GESTIÓN DE TALLERES Y ALUMNOS ---

  Future<void> addWorkshop({
    required String name,
    required String code,
    required String instructorName,
    required String description,
  }) async {
    final newWorkshop = Workshop(
      id: 'ws_${_uuid.v4().substring(0, 8)}',
      name: name,
      code: code,
      instructorName: instructorName,
      description: description,
      enrolledStudents: [],
      sessions: [],
    );
    _workshops.insert(0, newWorkshop);
    await _persist();
  }

  Future<void> addStudentToWorkshop({
    required String workshopId,
    required String enrollmentNumber,
    required String fullName,
    required String email,
  }) async {
    final index = _workshops.indexWhere((w) => w.id == workshopId);
    if (index != -1) {
      final newStudent = Student(
        id: 'std_${_uuid.v4().substring(0, 8)}',
        enrollmentNumber: enrollmentNumber,
        fullName: fullName,
        email: email,
      );
      _workshops[index].enrolledStudents.add(newStudent);
      await _persist();
    }
  }

  Future<WorkshopSession?> createSession({
    required String workshopId,
    required String title,
    required DateTime date,
  }) async {
    final index = _workshops.indexWhere((w) => w.id == workshopId);
    if (index == -1) return null;

    final newSession = WorkshopSession(
      id: 'ses_${_uuid.v4().substring(0, 8)}',
      workshopId: workshopId,
      title: title,
      date: date,
      currentPhase: SessionPhase.pending,
      secretKey: 'KEY_${_uuid.v4().substring(0, 12)}',
      records: {},
    );

    _workshops[index].sessions.insert(0, newSession);
    await _persist();
    return newSession;
  }

  // --- CONTROL DE FASES DE SESIÓN (DOCENTE) ---

  Future<void> updateSessionPhase({
    required String workshopId,
    required String sessionId,
    required SessionPhase newPhase,
  }) async {
    final workshop = _workshops.firstWhere((w) => w.id == workshopId);
    final session = workshop.sessions.firstWhere((s) => s.id == sessionId);

    session.currentPhase = newPhase;
    session.phaseStartedAt = DateTime.now();

    await _persist();
  }

  // --- REGISTRO DE ASISTENCIA MEDIANTE ESCANEO QR ---

  AttendanceProcessResult processQrScan({
    required String qrRawContent,
    required String studentEnrollmentNumber,
    String? studentFullName,
    String? studentEmail,
  }) {
    // 1. Decodificar la sesión
    final dummySessionResult = _findSessionFromQr(qrRawContent);
    if (dummySessionResult == null) {
      return AttendanceProcessResult(
        success: false,
        title: 'Error de Lectura',
        message: 'No se pudo identificar ninguna sesión activa en el código QR proporcionado.',
      );
    }

    final Workshop workshop = dummySessionResult.workshop;
    final WorkshopSession session = dummySessionResult.session;

    // 2. Validar criptográficamente y por ventana temporal
    final validation = QrService.validateQrData(
      qrRawContent: qrRawContent,
      currentSession: session,
    );

    if (!validation.isValid) {
      return AttendanceProcessResult(
        success: false,
        title: 'Validación Rechazada',
        message: validation.errorMessage ?? 'Código inválido o expirado.',
      );
    }

    // 3. Buscar al estudiante en la lista de inscritos
    Student? student = workshop.enrolledStudents.cast<Student?>().firstWhere(
      (s) =>
          s != null &&
          s.enrollmentNumber.trim().toLowerCase() ==
              studentEnrollmentNumber.trim().toLowerCase(),
      orElse: () => null,
    );

    // Auto-inscribir al estudiante si escanea por primera vez desde su celular
    if (student == null) {
      if (studentFullName != null && studentFullName.trim().isNotEmpty) {
        student = Student(
          id: 'std_${_uuid.v4().substring(0, 8)}',
          enrollmentNumber: studentEnrollmentNumber.trim(),
          fullName: studentFullName.trim(),
          email: studentEmail?.trim().isNotEmpty == true
              ? studentEmail!.trim()
              : '${studentEnrollmentNumber.trim().toLowerCase()}@alumno.edu',
        );
        workshop.enrolledStudents.add(student);
        _persist();
      } else {
        return AttendanceProcessResult(
          success: false,
          title: 'Estudiante No Inscrito',
          message:
              'La matrícula "$studentEnrollmentNumber" no se encuentra registrada en la lista oficial de este taller (${workshop.name}).',
        );
      }
    }

    // 4. Procesar el registro según la fase
    return _applyAttendance(
      workshop: workshop,
      session: session,
      student: student,
      phase: session.currentPhase,
    );
  }

  /// Registro directo (manual o desde simulador de pruebas)
  AttendanceProcessResult registerDirectAttendance({
    required String workshopId,
    required String sessionId,
    required String studentId,
    required SessionPhase phase,
  }) {
    final workshop = _workshops.firstWhere((w) => w.id == workshopId);
    final session = workshop.sessions.firstWhere((s) => s.id == sessionId);
    final student = workshop.enrolledStudents.firstWhere(
      (s) => s.id == studentId,
    );

    return _applyAttendance(
      workshop: workshop,
      session: session,
      student: student,
      phase: phase,
    );
  }

  AttendanceProcessResult _applyAttendance({
    required Workshop workshop,
    required WorkshopSession session,
    required Student student,
    required SessionPhase phase,
  }) {
    final now = DateTime.now();
    var record = session.records[student.id];

    if (record == null) {
      record = AttendanceRecord(
        id: 'rec_${_uuid.v4().substring(0, 8)}',
        studentId: student.id,
        sessionId: session.id,
      );
      session.records[student.id] = record;
    }

    if (phase == SessionPhase.entry) {
      if (record.hasCheckIn) {
        return AttendanceProcessResult(
          success: true,
          title: 'Entrada Ya Sellada 🔒',
          message:
              'La hora de entrada de ${student.fullName} fue sellada a las ${_formatTime(record.checkInTime!)} y es INMUTABLE. No puede ser alterada para garantizar la transparencia.',
          status: record.status,
          student: student,
        );
      }

      record.sealCheckIn(now);
      _persist();
      PowerSyncService().saveAttendanceRecord(
        record: record,
        workshopId: workshop.id,
      );
      _syncRecordToSupabaseAsync(record, student, session.id);

      return AttendanceProcessResult(
        success: true,
        title: '🟢 Entrada Sellada 🔒',
        message:
            '¡Bienvenido(a), ${student.fullName}! Se registró tu entrada a las ${_formatTime(now)} (Hora oficial inmutable). Recuerda que para ACREDITAR debes registrar tu salida al terminar.',
        status: record.status,
        student: student,
      );
    } else if (phase == SessionPhase.exit) {
      if (record.hasCheckOut) {
        return AttendanceProcessResult(
          success: true,
          title: 'Salida Ya Sellada 🔒',
          message:
              'La hora de salida de ${student.fullName} ya fue sellada a las ${_formatTime(record.checkOutTime!)} y está BLOQUEADA permanentemente.',
          status: record.status,
          student: student,
        );
      }

      record.sealCheckOut(now);
      _persist();
      PowerSyncService().saveAttendanceRecord(
        record: record,
        workshopId: workshop.id,
      );
      _syncRecordToSupabaseAsync(record, student, session.id);

      if (record.hasCheckIn) {
        return AttendanceProcessResult(
          success: true,
          title: '🎉 ¡Asistencia ACREDITADA! 🔒',
          message:
              'Excelente, ${student.fullName}. Registraste tu ENTRADA (${_formatTime(record.checkInTime!)}) y tu SALIDA (${_formatTime(now)}). Ambas horas están selladas e inmutables. Acreditación 100% aprobada.',
          status: AttendanceStatus.accredited,
          student: student,
        );
      } else {
        return AttendanceProcessResult(
          success: true,
          title: '⚠️ Salida Sellada con Advertencia 🔒',
          message:
              'Se selló tu hora de salida (${_formatTime(now)}), pero NO cuentas con registro de entrada previo. La sesión quedará computada como INCOMPLETA.',
          status: AttendanceStatus.incompleteExitOnly,
          student: student,
        );
      }
    } else {
      return AttendanceProcessResult(
        success: false,
        title: 'Pase Inactivo',
        message: 'El docente no tiene activo el pase de lista en este momento.',
      );
    }
  }

  // Helper para buscar sesión referenciada en el QR (acepta JSON o URL web con ?qr=...)
  _WorkshopSessionMatch? _findSessionFromQr(String qrRaw) {
    try {
      final payload = QrService.extractPayload(qrRaw);
      if (!payload.trim().startsWith('{')) return null;

      for (var w in _workshops) {
        for (var s in w.sessions) {
          if (payload.contains(s.id)) {
            return _WorkshopSessionMatch(workshop: w, session: s);
          }
        }
      }
    } catch (_) {}
    return null;
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  // Métricas para una sesión
  SessionStatistics getSessionStats(
    Workshop workshop,
    WorkshopSession session,
  ) {
    final totalEnrolled = workshop.enrolledStudents.length;
    int accredited = 0;
    int incomplete = 0;
    int pending = 0;
    int entriesCount = 0;
    int exitsCount = 0;

    for (var student in workshop.enrolledStudents) {
      final rec = session.records[student.id];
      if (rec == null) {
        pending++;
      } else {
        if (rec.hasCheckIn) entriesCount++;
        if (rec.hasCheckOut) exitsCount++;

        if (rec.status == AttendanceStatus.accredited) {
          accredited++;
        } else if (rec.status == AttendanceStatus.incompleteEntryOnly ||
            rec.status == AttendanceStatus.incompleteExitOnly) {
          incomplete++;
        } else {
          pending++;
        }
      }
    }

    return SessionStatistics(
      totalStudents: totalEnrolled,
      accredited: accredited,
      incomplete: incomplete,
      absent: pending,
      entriesCount: entriesCount,
      exitsCount: exitsCount,
    );
  }

  // --- CONTROL DE INVENTARIO Y REAPERTURA DOCENTE ---

  /// Permite al docente reiniciar/desbloquear la sesión de un alumno
  Future<void> resetStudentAttendance({
    required String workshopId,
    required String sessionId,
    required String studentId,
  }) async {
    final workshop = _workshops.firstWhere((w) => w.id == workshopId);
    final session = workshop.sessions.firstWhere((s) => s.id == sessionId);

    // 1. Eliminar registro de asistencia local en memoria y StorageService
    session.records.remove(studentId);
    await _persist();

    // 2. Eliminar en PowerSync SQLite local
    if (PowerSyncService().isInitialized) {
      try {
        await PowerSyncService().db.execute(
          'DELETE FROM attendance_records WHERE student_id = ? AND session_id = ?',
          [studentId, sessionId],
        );
      } catch (e) {
        debugPrint('Aviso eliminación SQLite: $e');
      }
    }

    // 3. Eliminar en Supabase Cloud REST para liberar al alumno en la nube
    if (!kIsWeb) {
      try {
        final client = HttpClient();
        final uri = Uri.parse(
          'https://qukqvrowgzdkqoccbfdb.supabase.co/rest/v1/attendance_records?session_id=eq.$sessionId&student_id=eq.$studentId',
        );
        final req = await client.deleteUrl(uri);
        req.headers.set('apikey', 'sb_publishable_A-jiTpI9-hoDwOaln0_BWw_omLvRnRN');
        req.headers.set('Authorization', 'Bearer sb_publishable_A-jiTpI9-hoDwOaln0_BWw_omLvRnRN');
        final res = await req.close();
        await res.drain();
        client.close();
      } catch (e) {
        debugPrint('Aviso Supabase delete: $e');
      }
    }

    notifyListeners();
  }

  /// Sincronizar registros del inventario en vivo desde Supabase Cloud
  Future<int> syncRecordsFromSupabase({
    required String workshopId,
    required String sessionId,
  }) async {
    if (kIsWeb) return 0;
    try {
      final client = HttpClient();
      final uri = Uri.parse(
        'https://qukqvrowgzdkqoccbfdb.supabase.co/rest/v1/attendance_records?session_id=eq.$sessionId&select=*,students(*)',
      );
      final req = await client.getUrl(uri);
      req.headers.set('apikey', 'sb_publishable_A-jiTpI9-hoDwOaln0_BWw_omLvRnRN');
      req.headers.set('Authorization', 'Bearer sb_publishable_A-jiTpI9-hoDwOaln0_BWw_omLvRnRN');
      final res = await req.close();
      final responseBody = await res.transform(utf8.decoder).join();
      client.close();

      if (res.statusCode == 200) {
        final List<dynamic> list = jsonDecode(responseBody);
        final workshop = _workshops.firstWhere((w) => w.id == workshopId);
        final session = workshop.sessions.firstWhere((s) => s.id == sessionId);

        int updatedCount = 0;
        for (var item in list) {
          final studentData = item['students'];
          String? sId = item['student_id'];
          if (studentData != null) {
            final enrollment = studentData['enrollment_number']?.toString().toUpperCase();
            var existingStudent = workshop.enrolledStudents.where(
              (s) => s.enrollmentNumber.toUpperCase() == enrollment || s.id == sId,
            ).firstOrNull;

            if (existingStudent == null && enrollment != null) {
              existingStudent = Student(
                id: sId ?? 'std_${_uuid.v4().substring(0, 8)}',
                fullName: studentData['full_name'] ?? 'Alumno',
                enrollmentNumber: enrollment,
                email: studentData['email'] ?? '',
              );
              workshop.enrolledStudents.add(existingStudent);
            }

            if (existingStudent != null) {
              sId = existingStudent.id;
            }
          }

          if (sId != null) {
            DateTime? checkIn;
            DateTime? checkOut;
            if (item['check_in_time'] != null) {
              checkIn = DateTime.tryParse(item['check_in_time']);
            }
            if (item['check_out_time'] != null) {
              checkOut = DateTime.tryParse(item['check_out_time']);
            }

            final rec = AttendanceRecord(
              id: item['id'] ?? 'rec_${_uuid.v4().substring(0, 8)}',
              studentId: sId,
              sessionId: sessionId,
              checkInTime: checkIn,
              checkOutTime: checkOut,
              isLocked: item['is_locked'] == true || item['is_locked'] == 1,
            );
            session.records[sId] = rec;
            updatedCount++;
          }
        }

        await _persist();
        notifyListeners();
        return updatedCount;
      }
    } catch (e) {
      debugPrint('Error sincronizando con Supabase: $e');
    }
    return 0;
  }

  void _syncRecordToSupabaseAsync(AttendanceRecord record, Student student, String sessionId) {
    if (kIsWeb) return;
    try {
      HttpClient().postUrl(Uri.parse('https://qukqvrowgzdkqoccbfdb.supabase.co/rest/v1/attendance_records?on_conflict=id'))
        .then((req) {
          req.headers.set('apikey', 'sb_publishable_A-jiTpI9-hoDwOaln0_BWw_omLvRnRN');
          req.headers.set('Authorization', 'Bearer sb_publishable_A-jiTpI9-hoDwOaln0_BWw_omLvRnRN');
          req.headers.set('Content-Type', 'application/json');
          req.headers.set('Prefer', 'resolution=merge-duplicates');
          final body = jsonEncode({
            'id': record.id,
            'student_id': student.id,
            'session_id': sessionId,
            'check_in_time': record.checkInTime?.toIso8601String(),
            'check_out_time': record.checkOutTime?.toIso8601String(),
            'is_locked': record.isLocked,
            'status': record.status.name,
          });
          req.write(body);
          return req.close();
        }).then((res) {
          res.drain();
        }).catchError((err) {
          debugPrint('Aviso sync Supabase: $err');
        });
    } catch (_) {}
  }

  Future<void> clearAllData() async {
    _workshops = [];
    await StorageService.clearAll();
    notifyListeners();
  }
}

class SessionStatistics {
  final int totalStudents;
  final int accredited;
  final int incomplete;
  final int absent;
  final int entriesCount;
  final int exitsCount;

  SessionStatistics({
    required this.totalStudents,
    required this.accredited,
    required this.incomplete,
    required this.absent,
    required this.entriesCount,
    required this.exitsCount,
  });

  double get accreditedPercentage =>
      totalStudents == 0 ? 0 : (accredited / totalStudents);
}

class _WorkshopSessionMatch {
  final Workshop workshop;
  final WorkshopSession session;
  _WorkshopSessionMatch({required this.workshop, required this.session});
}
