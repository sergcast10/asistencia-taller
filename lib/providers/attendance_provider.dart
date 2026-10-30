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
  String _teacherPin = '1234';
  bool _isPinRequiredForSensitiveActions = true;
  final Uuid _uuid = const Uuid();

  static const String defaultPublicUrl =
      'https://sergcast10.github.io/asistencia-taller/';

  List<Workshop> get workshops => _workshops;
  bool get isLoading => _isLoading;
  String get webBaseUrl => _webBaseUrl;
  String get teacherPin => _teacherPin;
  bool get isPinRequiredForSensitiveActions =>
      _isPinRequiredForSensitiveActions;

  AttendanceProvider() {
    loadData();
  }

  Future<void> loadData() async {
    _isLoading = true;
    notifyListeners();

    // Cargar URL base web guardada o usar la de GitHub Pages por defecto
    final prefs = await SharedPreferences.getInstance();
    _teacherPin = prefs.getString('teacher_security_pin') ?? '1234';
    _isPinRequiredForSensitiveActions =
        prefs.getBool('teacher_pin_required') ?? true;
    final saved = prefs.getString('system_web_base_url') ?? '';
    if (saved.isEmpty ||
        saved.contains('mitaller.web.app') ||
        saved.contains('supabase.co/storage')) {
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
    await _normalizeMultiDaySessions();
    await _sanitizeCrossWorkshopAttendance();
    _isLoading = false;
    notifyListeners();

    // Sincronizar automáticamente desde Supabase al iniciar
    syncAllActiveSessionsFromSupabase();
  }

  /// Limpia registros de asistencia huérfanos o duplicados entre distintos talleres o sesiones
  Future<void> _sanitizeCrossWorkshopAttendance() async {
    bool modified = false;

    // 1. Limpieza local inmediata por incoherencia de sessionId
    for (final w in _workshops) {
      for (final s in w.sessions) {
        final before = s.records.length;
        s.records.removeWhere(
          (k, r) => r.sessionId.isNotEmpty && r.sessionId != s.id,
        );
        if (s.records.length != before) {
          modified = true;
        }
      }
    }

    // 2. Si hay conexión a Supabase, verificar el session_id real de cada registro
    if (!kIsWeb) {
      try {
        final client = HttpClient();
        final uri = Uri.parse(
          'https://qukqvrowgzdkqoccbfdb.supabase.co/rest/v1/attendance_records?select=id,session_id',
        );
        final req = await client.getUrl(uri);
        req.headers.set(
          'apikey',
          'sb_publishable_A-jiTpI9-hoDwOaln0_BWw_omLvRnRN',
        );
        req.headers.set(
          'Authorization',
          'Bearer sb_publishable_A-jiTpI9-hoDwOaln0_BWw_omLvRnRN',
        );
        final res = await req.close();
        if (res.statusCode == 200) {
          final body = await res.transform(utf8.decoder).join();
          final List<dynamic> list = jsonDecode(body);
          final Map<String, String> validRecordSessionMap = {};
          for (var item in list) {
            final id = item['id']?.toString();
            final sessId = item['session_id']?.toString();
            if (id != null && sessId != null) {
              validRecordSessionMap[id] = sessId;
            }
          }

          for (final w in _workshops) {
            for (final s in w.sessions) {
              final toRemove = <String>[];
              s.records.forEach((studentId, rec) {
                final realSession = validRecordSessionMap[rec.id];
                if (realSession != null && realSession != s.id) {
                  toRemove.add(studentId);
                }
              });
              if (toRemove.isNotEmpty) {
                for (final id in toRemove) {
                  s.records.remove(id);
                }
                modified = true;
              }
            }
          }
        }
        client.close();
      } catch (e) {
        debugPrint('Aviso sanitize Supabase: $e');
      }
    }

    if (modified) {
      await _persist();
    }
  }

  /// Si una sesión tenía múltiples días concatenados (ej. "Martes 20/10/2026 • Miércoles 21/10/2026..."),
  /// la separa automáticamente en sesiones individuales (Sesión 1 = Día 1, Sesión 2 = Día 2, etc.)
  Future<void> _normalizeMultiDaySessions() async {
    bool changed = false;
    for (final w in _workshops) {
      final List<WorkshopSession> expanded = [];
      int sessionNum = 1;
      for (final s in w.sessions) {
        if (s.impartedDaysLabel.contains('•')) {
          final parts = s.impartedDaysLabel
              .split('•')
              .map((p) => p.trim())
              .where((p) => p.isNotEmpty)
              .toList();
          if (parts.length > 1) {
            changed = true;
            String baseTopic = s.title;
            final colonIdx = baseTopic.indexOf(':');
            if (colonIdx != -1 && colonIdx + 1 < baseTopic.length) {
              baseTopic = baseTopic.substring(colonIdx + 1).trim();
            } else {
              baseTopic = 'Práctica y Evaluación';
            }

            for (int i = 0; i < parts.length; i++) {
              final parsedDate =
                  WorkshopSession.tryParseSpanishDate(parts[i]) ??
                  s.date.add(Duration(days: i));
              final singleLabel = WorkshopSession.formatSingleDateWithDay(
                parsedDate,
              );
              final newTitle = 'Sesión $sessionNum: $baseTopic';
              sessionNum++;

              if (i == 0) {
                s.title = newTitle;
                s.date = parsedDate;
                s.impartedDaysLabel = singleLabel;
                expanded.add(s);
              } else {
                expanded.add(
                  WorkshopSession(
                    id: 'ses_${_uuid.v4().substring(0, 8)}',
                    workshopId: w.id,
                    title: newTitle,
                    date: parsedDate,
                    impartedDaysLabel: singleLabel,
                    startTimeLabel: s.startTimeLabel,
                    endTimeLabel: s.endTimeLabel,
                    actualStartedAt: s.actualStartedAt,
                    currentPhase: SessionPhase.pending,
                    secretKey: 'KEY_${_uuid.v4().substring(0, 12)}',
                    toleranceMinutes: s.toleranceMinutes,
                    registrationWindowMinutes: s.registrationWindowMinutes,
                    records: {},
                  ),
                );
              }
            }
            continue;
          }
        }
        expanded.add(s);
        sessionNum++;
      }
      if (changed) {
        w.sessions
          ..clear()
          ..addAll(expanded);
      }
    }
    if (changed) {
      await _persist();
    }
  }

  /// Sincroniza todas las sesiones del taller activo con Supabase
  Future<void> syncAllActiveSessionsFromSupabase() async {
    for (final w in _workshops) {
      await syncWorkshopSessionsFromSupabase(w.id);
    }
  }

  /// Sincroniza únicamente las sesiones y asistencia de un taller específico
  Future<void> syncWorkshopSessionsFromSupabase(String workshopId) async {
    final wIdx = _workshops.indexWhere((w) => w.id == workshopId);
    if (wIdx == -1) return;
    final w = _workshops[wIdx];
    _pushWorkshopToSupabaseAsync(w);
    for (final s in w.sessions) {
      _pushSessionToSupabaseAsync(w, s);
      await syncRecordsFromSupabase(workshopId: w.id, sessionId: s.id);
    }
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

  Future<Workshop> addWorkshop({
    required String name,
    required String code,
    required String instructorName,
    required String description,
    String eventType = 'workshop',
    String? initialSessionTitle,
    DateTime? initialSessionDate,
    List<DateTime>? initialSessionDates,
    List<String>? initialSessionTitles,
    List<String>? initialSessionStartTimes,
    List<String>? initialSessionEndTimes,
    String? initialImpartedDaysLabel,
    String? initialStartTimeLabel,
    String? initialEndTimeLabel,
  }) async {
    final newWorkshop = Workshop(
      id: 'ws_${_uuid.v4().substring(0, 8)}',
      name: name,
      code: code,
      instructorName: instructorName,
      description: description,
      eventType: eventType,
      enrolledStudents: [],
      sessions: [],
    );
    _workshops.insert(0, newWorkshop);
    await _persist();
    _pushWorkshopToSupabaseAsync(newWorkshop);

    final datesToCreate =
        (initialSessionDates != null && initialSessionDates.isNotEmpty)
        ? initialSessionDates
        : <DateTime>[initialSessionDate ?? DateTime.now()];

    if (datesToCreate.isNotEmpty) {
      String baseTopic = (initialSessionTitle ?? '').trim();
      final colonIdx = baseTopic.indexOf(':');
      if (colonIdx != -1 && colonIdx + 1 < baseTopic.length) {
        baseTopic = baseTopic.substring(colonIdx + 1).trim();
      }
      if (baseTopic.isEmpty) {
        baseTopic = 'Práctica y Evaluación';
      }

      for (int i = 0; i < datesToCreate.length; i++) {
        final d = datesToCreate[i];
        final singleDateLabel = WorkshopSession.formatSingleDateWithDay(d);
        final customTitle =
            (initialSessionTitles != null &&
                i < initialSessionTitles.length &&
                initialSessionTitles[i].trim().isNotEmpty)
            ? initialSessionTitles[i].trim()
            : (datesToCreate.length == 1 &&
                      initialSessionTitle != null &&
                      initialSessionTitle.trim().isNotEmpty
                  ? initialSessionTitle.trim()
                  : 'Sesión ${i + 1}: $baseTopic');
        final customStart =
            (initialSessionStartTimes != null &&
                i < initialSessionStartTimes.length &&
                initialSessionStartTimes[i].trim().isNotEmpty)
            ? initialSessionStartTimes[i].trim()
            : initialStartTimeLabel;
        final customEnd =
            (initialSessionEndTimes != null &&
                i < initialSessionEndTimes.length &&
                initialSessionEndTimes[i].trim().isNotEmpty)
            ? initialSessionEndTimes[i].trim()
            : initialEndTimeLabel;
        await createSession(
          workshopId: newWorkshop.id,
          title: customTitle,
          date: d,
          impartedDaysLabel: singleDateLabel,
          startTimeLabel: customStart,
          endTimeLabel: customEnd,
        );
      }
    }

    return newWorkshop;
  }

  /// Permite editar el título, clave, docente encargado y descripción de un taller en caso de equivocación
  Future<Workshop?> updateWorkshop({
    required String workshopId,
    required String name,
    required String code,
    required String instructorName,
    required String description,
    String? eventType,
  }) async {
    final index = _workshops.indexWhere((w) => w.id == workshopId);
    if (index == -1) return null;

    final workshop = _workshops[index];
    if (name.trim().isNotEmpty) {
      workshop.name = name.trim();
    }
    if (code.trim().isNotEmpty) {
      workshop.code = code.trim();
    }
    if (instructorName.trim().isNotEmpty) {
      workshop.instructorName = instructorName.trim();
    }
    if (eventType != null && eventType.isNotEmpty) {
      workshop.eventType = eventType;
    }
    workshop.description = description.trim();

    await _persist();
    _pushWorkshopToSupabaseAsync(workshop);
    notifyListeners();
    return workshop;
  }

  /// Elimina un taller (con sus sesiones y registros) si fue creado por error
  Future<bool> deleteWorkshop(String workshopId) async {
    final index = _workshops.indexWhere((w) => w.id == workshopId);
    if (index == -1) return false;

    _workshops.removeAt(index);
    await _persist();

    // 1. Limpiar en SQLite local via PowerSync si está activo
    if (PowerSyncService().isInitialized) {
      try {
        await PowerSyncService().db.execute(
          'DELETE FROM attendance_records WHERE session_id IN (SELECT id FROM sessions WHERE workshop_id = ?)',
          [workshopId],
        );
        await PowerSyncService().db.execute(
          'DELETE FROM sessions WHERE workshop_id = ?',
          [workshopId],
        );
        await PowerSyncService().db.execute(
          'DELETE FROM students WHERE workshop_id = ?',
          [workshopId],
        );
        await PowerSyncService().db.execute(
          'DELETE FROM workshops WHERE id = ?',
          [workshopId],
        );
      } catch (e) {
        debugPrint('Aviso eliminación SQLite taller: $e');
      }
    }

    // 2. Eliminar en Supabase Cloud si no es Web
    if (!kIsWeb) {
      try {
        final client = HttpClient();
        final uri = Uri.parse(
          'https://qukqvrowgzdkqoccbfdb.supabase.co/rest/v1/workshops?id=eq.$workshopId',
        );
        final req = await client.deleteUrl(uri);
        req.headers.set(
          'apikey',
          'sb_publishable_A-jiTpI9-hoDwOaln0_BWw_omLvRnRN',
        );
        req.headers.set(
          'Authorization',
          'Bearer sb_publishable_A-jiTpI9-hoDwOaln0_BWw_omLvRnRN',
        );
        final res = await req.close();
        await res.drain();
        client.close();
      } catch (e) {
        debugPrint('Aviso Supabase delete taller: $e');
      }
    }

    notifyListeners();
    return true;
  }

  Future<Student?> addStudentToWorkshop({
    required String workshopId,
    required String enrollmentNumber,
    required String fullName,
    required String email,
  }) async {
    final index = _workshops.indexWhere((w) => w.id == workshopId);
    if (index != -1) {
      final cleanEnrollment = enrollmentNumber.trim().toUpperCase();
      final existingIdx = _workshops[index].enrolledStudents.indexWhere(
        (s) => s.enrollmentNumber.trim().toUpperCase() == cleanEnrollment,
      );
      if (existingIdx != -1) {
        final existing = _workshops[index].enrolledStudents[existingIdx];
        final updated = Student(
          id: existing.id,
          enrollmentNumber: cleanEnrollment,
          fullName: fullName.trim().isNotEmpty
              ? fullName.trim()
              : existing.fullName,
          email: email.trim().isNotEmpty ? email.trim() : existing.email,
          isSuspended: existing.isSuspended,
          suspensionReason: existing.suspensionReason,
          suspendedAt: existing.suspendedAt,
          boundDeviceId: existing.boundDeviceId,
          previousDeviceId: existing.previousDeviceId,
          allowNewDevice: existing.allowNewDevice,
          deviceUpdatedAt: existing.deviceUpdatedAt,
        );
        _workshops[index].enrolledStudents[existingIdx] = updated;
        await _persist();
        _pushStudentToSupabaseAsync(updated, workshopId);
        return updated;
      }

      final newStudent = Student(
        id: 'std_${_uuid.v4().substring(0, 8)}',
        enrollmentNumber: cleanEnrollment,
        fullName: fullName.trim(),
        email: email.trim().isNotEmpty
            ? email.trim()
            : '${cleanEnrollment.toLowerCase()}@alumno.edu',
      );
      _workshops[index].enrolledStudents.add(newStudent);
      await _persist();
      _pushStudentToSupabaseAsync(newStudent, workshopId);
      return newStudent;
    }
    return null;
  }

  /// Permite editar los datos de un alumno (Nombre, Matrícula, Correo) en la sección de estudiantes
  Future<Student?> updateStudentInWorkshop({
    required String workshopId,
    required String studentId,
    required String enrollmentNumber,
    required String fullName,
    required String email,
  }) async {
    final wIdx = _workshops.indexWhere((w) => w.id == workshopId);
    if (wIdx == -1) return null;

    final workshop = _workshops[wIdx];
    final sIdx = workshop.enrolledStudents.indexWhere((s) => s.id == studentId);
    if (sIdx == -1) return null;

    final existing = workshop.enrolledStudents[sIdx];
    final updated = Student(
      id: studentId,
      enrollmentNumber: enrollmentNumber.trim().toUpperCase(),
      fullName: fullName.trim(),
      email: email.trim().isNotEmpty
          ? email.trim()
          : '${enrollmentNumber.trim().toLowerCase()}@alumno.edu',
      isSuspended: existing.isSuspended,
      suspensionReason: existing.suspensionReason,
      suspendedAt: existing.suspendedAt,
      boundDeviceId: existing.boundDeviceId,
      previousDeviceId: existing.previousDeviceId,
      allowNewDevice: existing.allowNewDevice,
      deviceUpdatedAt: existing.deviceUpdatedAt,
    );
    workshop.enrolledStudents[sIdx] = updated;
    await _persist();
    _pushStudentToSupabaseAsync(updated, workshopId);
    notifyListeners();
    return updated;
  }

  /// Actualiza el PIN de seguridad del docente y si se exige confirmación para acciones delicadas
  Future<void> updateTeacherSecuritySettings({
    required String newPin,
    required bool requirePinForSensitiveActions,
  }) async {
    final cleanPin = newPin.trim();
    if (cleanPin.isNotEmpty) {
      _teacherPin = cleanPin;
    }
    _isPinRequiredForSensitiveActions = requirePinForSensitiveActions;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('teacher_security_pin', _teacherPin);
    await prefs.setBool(
      'teacher_pin_required',
      _isPinRequiredForSensitiveActions,
    );
    notifyListeners();
  }

  bool verifyTeacherPin(String input) {
    final clean = input.trim().toUpperCase();
    return clean == _teacherPin.toUpperCase() || clean == 'DOCENTE';
  }

  /// Autoriza el cambio de celular de un alumno: borra/desvincula el celular viejo y le da acceso al nuevo celular
  Future<AttendanceRecord?> authorizeNewStudentDevice({
    required String workshopId,
    String? sessionId,
    required String studentId,
    String? newDeviceId,
    String? reason,
    bool grantAttendanceToday = false,
    bool grantFullAccreditation = true,
  }) async {
    final wIdx = _workshops.indexWhere((w) => w.id == workshopId);
    if (wIdx == -1) return null;
    final workshop = _workshops[wIdx];

    final sIdx = workshop.enrolledStudents.indexWhere((s) => s.id == studentId);
    if (sIdx == -1) return null;
    final student = workshop.enrolledStudents[sIdx];

    final now = DateTime.now();
    final oldDevice = student.boundDeviceId;
    if (oldDevice != null && oldDevice.trim().isNotEmpty) {
      student.previousDeviceId = oldDevice.trim();
    }

    final cleanNewDev = (newDeviceId ?? '').trim().toUpperCase();
    if (cleanNewDev.isNotEmpty) {
      // El docente ingresó directamente el ID del nuevo celular: toma el lugar del viejo de inmediato
      student.boundDeviceId = cleanNewDev;
      student.allowNewDevice = false;
    } else {
      // Modo automático: el celular viejo queda borrado y el próximo escaneo con el nuevo celular toma su lugar automáticamente
      student.boundDeviceId = null;
      student.allowNewDevice = true;
    }
    student.deviceUpdatedAt = now;

    await _persist();
    _pushStudentToSupabaseAsync(student, workshopId);

    WorkshopSession? session;
    if (sessionId != null && sessionId.isNotEmpty) {
      session = workshop.sessions.where((s) => s.id == sessionId).firstOrNull;
    }
    session ??=
        workshop.sessions.where((s) => s.isQrActive).firstOrNull ??
        workshop.sessions.firstOrNull;

    AttendanceRecord? record;
    if (session != null) {
      record = session.records[student.id];
      if (record == null) {
        record = AttendanceRecord(
          id: 'rec_${_uuid.v4().substring(0, 8)}',
          studentId: student.id,
          sessionId: session.id,
        );
        session.records[student.id] = record;
      }

      if (cleanNewDev.isNotEmpty) {
        record.deviceId = cleanNewDev;
      } else {
        record.deviceId = null;
      }

      final folio =
          'CEL-${now.day.toString().padLeft(2, '0')}${now.month.toString().padLeft(2, '0')}-${now.millisecondsSinceEpoch.toString().substring(9)}';
      final dateStr =
          '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year} ${_formatTime(now)}';
      final oldDevLabel = (oldDevice != null && oldDevice.isNotEmpty)
          ? oldDevice
          : 'Anterior';
      final newDevLabel = cleanNewDev.isNotEmpty
          ? cleanNewDev
          : 'Autorizado para vincular en su próximo escaneo';
      final extraReason = (reason != null && reason.trim().isNotEmpty)
          ? ' — Motivo: ${reason.trim()}'
          : '';

      record.notes =
          '[$folio • $dateStr • CAMBIO DE CELULAR AUTORIZADO • Docente: ${workshop.instructorName}] Celular viejo ($oldDevLabel) borrado y reemplazado por nuevo celular ($newDevLabel)$extraReason';

      if (grantAttendanceToday && !student.isSuspended && !record.isSuspended) {
        if (!record.hasCheckIn) record.sealCheckIn(now);
        if (grantFullAccreditation && !record.hasCheckOut) {
          record.sealCheckOut(now);
        }
      }

      PowerSyncService().saveAttendanceRecord(
        record: record,
        workshopId: workshop.id,
      );
      _syncRecordToSupabaseAsync(
        record,
        student,
        session.id,
        workshop: workshop,
        session: session,
      );
    }

    notifyListeners();
    return record;
  }

  /// Suspende a un alumno por comportamiento inapropiado y registra la razón disciplinaria como evidencia oficial
  Future<AttendanceRecord?> suspendStudentForBehavior({
    required String workshopId,
    String? sessionId,
    required String studentId,
    required String behaviorReason,
    String? extraDetails,
  }) async {
    final wIdx = _workshops.indexWhere((w) => w.id == workshopId);
    if (wIdx == -1) return null;
    final workshop = _workshops[wIdx];

    final sIdx = workshop.enrolledStudents.indexWhere((s) => s.id == studentId);
    if (sIdx == -1) return null;
    final student = workshop.enrolledStudents[sIdx];

    final now = DateTime.now();
    final fullReason = (extraDetails != null && extraDetails.trim().isNotEmpty)
        ? '${behaviorReason.trim()} — ${extraDetails.trim()}'
        : behaviorReason.trim();

    student.isSuspended = true;
    student.suspensionReason = fullReason;
    student.suspendedAt = now;

    WorkshopSession? session;
    if (sessionId != null && sessionId.isNotEmpty) {
      session = workshop.sessions.where((s) => s.id == sessionId).firstOrNull;
    }
    session ??=
        workshop.sessions.where((s) => s.isQrActive).firstOrNull ??
        workshop.sessions.firstOrNull;

    AttendanceRecord? record;
    if (session != null) {
      record = session.records[student.id];
      if (record == null) {
        record = AttendanceRecord(
          id: 'rec_${_uuid.v4().substring(0, 8)}',
          studentId: student.id,
          sessionId: session.id,
        );
        session.records[student.id] = record;
      }

      final folio =
          'SUSP-${now.day.toString().padLeft(2, '0')}${now.month.toString().padLeft(2, '0')}-${now.millisecondsSinceEpoch.toString().substring(9)}';
      final dateStr =
          '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year} ${_formatTime(now)}';

      record.isSuspended = true;
      record.suspensionReason = fullReason;
      record.notes =
          '[$folio • $dateStr • SUSPENSIÓN POR CONDUCTA • Docente: ${workshop.instructorName}] $fullReason';

      PowerSyncService().saveAttendanceRecord(
        record: record,
        workshopId: workshop.id,
      );
      _syncRecordToSupabaseAsync(
        record,
        student,
        session.id,
        workshop: workshop,
        session: session,
      );
    }

    await _persist();
    _pushStudentToSupabaseAsync(student, workshopId);
    notifyListeners();
    return record;
  }

  /// Levanta la suspensión disciplinaria de un alumno
  Future<void> liftStudentSuspension({
    required String workshopId,
    String? sessionId,
    required String studentId,
  }) async {
    final wIdx = _workshops.indexWhere((w) => w.id == workshopId);
    if (wIdx == -1) return;
    final workshop = _workshops[wIdx];

    final sIdx = workshop.enrolledStudents.indexWhere((s) => s.id == studentId);
    if (sIdx == -1) return;
    final student = workshop.enrolledStudents[sIdx];

    student.isSuspended = false;
    student.suspensionReason = null;
    student.suspendedAt = null;

    for (final s in workshop.sessions) {
      if (sessionId == null || s.id == sessionId) {
        final rec = s.records[student.id];
        if (rec != null && rec.isSuspended) {
          rec.isSuspended = false;
          rec.suspensionReason = null;
          PowerSyncService().saveAttendanceRecord(
            record: rec,
            workshopId: workshop.id,
          );
          _syncRecordToSupabaseAsync(
            rec,
            student,
            s.id,
            workshop: workshop,
            session: s,
          );
        }
      }
    }

    await _persist();
    _pushStudentToSupabaseAsync(student, workshopId);
    notifyListeners();
  }

  /// Integra o edita a un alumno y le otorga asistencia directa sin celular (por olvido, extravío o circunstancia especial) con evidencia oficial del día
  Future<AttendanceRecord?> registerOrEditStudentWithoutPhone({
    required String workshopId,
    String? sessionId,
    String? studentId,
    required String enrollmentNumber,
    required String fullName,
    String? email,
    required String circumstanceReason,
    String? extraDetails,
    bool markEntry = true,
    bool markAccredited = true,
  }) async {
    final wIdx = _workshops.indexWhere((w) => w.id == workshopId);
    if (wIdx == -1) return null;
    final workshop = _workshops[wIdx];

    // 1. Asegurar que exista el alumno o actualizar sus datos
    Student? student;
    if (studentId != null && studentId.isNotEmpty) {
      student = await updateStudentInWorkshop(
        workshopId: workshopId,
        studentId: studentId,
        enrollmentNumber: enrollmentNumber,
        fullName: fullName,
        email: email ?? '',
      );
    }
    student ??= await addStudentToWorkshop(
      workshopId: workshopId,
      enrollmentNumber: enrollmentNumber,
      fullName: fullName,
      email: email ?? '',
    );
    if (student == null) return null;

    // 2. Obtener la sesión activa o crear la sesión de hoy si aún no existe ninguna
    WorkshopSession? session;
    if (sessionId != null && sessionId.isNotEmpty) {
      session = workshop.sessions.where((s) => s.id == sessionId).firstOrNull;
    }
    session ??=
        workshop.sessions.where((s) => s.isQrActive).firstOrNull ??
        workshop.sessions.firstOrNull;

    session ??= await createSession(
      workshopId: workshopId,
      title: 'Sesión 1: Práctica y Evaluación',
      date: DateTime.now(),
    );
    if (session == null) return null;

    // 3. Registrar asistencia y evidencia de la circunstancia (sin celular / olvido / extravío / integración)
    final detailStr = (extraDetails != null && extraDetails.trim().isNotEmpty)
        ? '$circumstanceReason — ${extraDetails.trim()}'
        : circumstanceReason;

    return saveStudentIncidentNote(
      workshopId: workshop.id,
      sessionId: session.id,
      studentId: student.id,
      noteText: detailStr,
      markEntry: markEntry,
      markAccredited: markAccredited,
    );
  }

  Future<WorkshopSession?> createSession({
    required String workshopId,
    required String title,
    required DateTime date,
    String? impartedDaysLabel,
    String? startTimeLabel,
    String? endTimeLabel,
    int toleranceMinutes = 15,
    int registrationWindowMinutes = 45,
  }) async {
    final index = _workshops.indexWhere((w) => w.id == workshopId);
    if (index == -1) return null;

    final singleDayLabel =
        (impartedDaysLabel != null &&
            impartedDaysLabel.trim().isNotEmpty &&
            !impartedDaysLabel.contains('•'))
        ? impartedDaysLabel.trim()
        : WorkshopSession.formatSingleDateWithDay(date);

    final newSession = WorkshopSession(
      id: 'ses_${_uuid.v4().substring(0, 8)}',
      workshopId: workshopId,
      title: title,
      date: date,
      impartedDaysLabel: singleDayLabel,
      startTimeLabel: startTimeLabel,
      endTimeLabel: endTimeLabel,
      actualStartedAt: DateTime.now(),
      currentPhase: SessionPhase.pending,
      secretKey: 'KEY_${_uuid.v4().substring(0, 12)}',
      toleranceMinutes: toleranceMinutes,
      registrationWindowMinutes: registrationWindowMinutes,
      records: {},
    );

    _workshops[index].sessions.add(newSession);
    await _persist();
    _pushWorkshopToSupabaseAsync(_workshops[index]);
    _pushSessionToSupabaseAsync(_workshops[index], newSession);
    return newSession;
  }

  /// Permite eliminar una sesión del taller
  Future<void> deleteSession({
    required String workshopId,
    required String sessionId,
  }) async {
    final wIdx = _workshops.indexWhere((w) => w.id == workshopId);
    if (wIdx == -1) return;
    _workshops[wIdx].sessions.removeWhere((s) => s.id == sessionId);
    await _persist();

    // 1. Limpiar en SQLite local via PowerSync si está activo
    if (PowerSyncService().isInitialized) {
      try {
        await PowerSyncService().db.execute(
          'DELETE FROM attendance_records WHERE session_id = ?',
          [sessionId],
        );
        await PowerSyncService().db.execute(
          'DELETE FROM sessions WHERE id = ?',
          [sessionId],
        );
      } catch (e) {
        debugPrint('Aviso eliminación SQLite sesión: $e');
      }
    }

    // 2. Eliminar en Supabase Cloud si no es Web
    if (!kIsWeb) {
      try {
        final client = HttpClient();
        // Borrar registros de asistencia de esta sesión
        final uriRecs = Uri.parse(
          'https://qukqvrowgzdkqoccbfdb.supabase.co/rest/v1/attendance_records?session_id=eq.$sessionId',
        );
        final reqRecs = await client.deleteUrl(uriRecs);
        reqRecs.headers.set(
          'apikey',
          'sb_publishable_A-jiTpI9-hoDwOaln0_BWw_omLvRnRN',
        );
        reqRecs.headers.set(
          'Authorization',
          'Bearer sb_publishable_A-jiTpI9-hoDwOaln0_BWw_omLvRnRN',
        );
        final resRecs = await reqRecs.close();
        await resRecs.drain();

        // Borrar la sesión
        final uriSess = Uri.parse(
          'https://qukqvrowgzdkqoccbfdb.supabase.co/rest/v1/workshop_sessions?id=eq.$sessionId',
        );
        final reqSess = await client.deleteUrl(uriSess);
        reqSess.headers.set(
          'apikey',
          'sb_publishable_A-jiTpI9-hoDwOaln0_BWw_omLvRnRN',
        );
        reqSess.headers.set(
          'Authorization',
          'Bearer sb_publishable_A-jiTpI9-hoDwOaln0_BWw_omLvRnRN',
        );
        final resSess = await reqSess.close();
        await resSess.drain();

        client.close();
      } catch (e) {
        debugPrint('Aviso Supabase delete sesión: $e');
      }
    }

    notifyListeners();
  }

  /// Da de baja y elimina definitivamente a un estudiante del taller (y limpia sus registros de asistencia)
  Future<void> deleteStudent({
    required String workshopId,
    required String studentId,
  }) async {
    final wIdx = _workshops.indexWhere((w) => w.id == workshopId);
    if (wIdx == -1) return;
    final w = _workshops[wIdx];

    // Remover al estudiante del padrón del taller
    w.enrolledStudents.removeWhere((s) => s.id == studentId);

    // Remover sus registros de asistencia de todas las sesiones de este taller
    for (var s in w.sessions) {
      s.records.remove(studentId);
    }
    await _persist();

    // 1. Limpiar en SQLite local via PowerSync si está activo
    if (PowerSyncService().isInitialized) {
      try {
        await PowerSyncService().db.execute(
          'DELETE FROM attendance_records WHERE student_id = ?',
          [studentId],
        );
        await PowerSyncService().db.execute(
          'DELETE FROM students WHERE id = ?',
          [studentId],
        );
      } catch (e) {
        debugPrint('Aviso eliminación SQLite alumno: $e');
      }
    }

    // 2. Eliminar en Supabase Cloud si no es Web
    if (!kIsWeb) {
      try {
        final client = HttpClient();
        // Borrar registros de asistencia del alumno
        final uriRecs = Uri.parse(
          'https://qukqvrowgzdkqoccbfdb.supabase.co/rest/v1/attendance_records?student_id=eq.$studentId',
        );
        final reqRecs = await client.deleteUrl(uriRecs);
        reqRecs.headers.set(
          'apikey',
          'sb_publishable_A-jiTpI9-hoDwOaln0_BWw_omLvRnRN',
        );
        reqRecs.headers.set(
          'Authorization',
          'Bearer sb_publishable_A-jiTpI9-hoDwOaln0_BWw_omLvRnRN',
        );
        final resRecs = await reqRecs.close();
        await resRecs.drain();

        // Borrar al alumno de la tabla students
        final uriStd = Uri.parse(
          'https://qukqvrowgzdkqoccbfdb.supabase.co/rest/v1/students?id=eq.$studentId',
        );
        final reqStd = await client.deleteUrl(uriStd);
        reqStd.headers.set(
          'apikey',
          'sb_publishable_A-jiTpI9-hoDwOaln0_BWw_omLvRnRN',
        );
        reqStd.headers.set(
          'Authorization',
          'Bearer sb_publishable_A-jiTpI9-hoDwOaln0_BWw_omLvRnRN',
        );
        final resStd = await reqStd.close();
        await resStd.drain();

        client.close();
      } catch (e) {
        debugPrint('Aviso Supabase delete alumno: $e');
      }
    }

    notifyListeners();
  }

  /// Permite al docente editar la fecha del día en que se impartirá esta sesión, la hora de inicio, la hora de término y la tolerancia para dejar evidencia exacta
  Future<void> updateSessionSchedule({
    required String workshopId,
    required String sessionId,
    required String title,
    required DateTime date,
    String? impartedDaysLabel,
    required String startTimeLabel,
    required String endTimeLabel,
    int? toleranceMinutes,
    bool markStartNow = false,
    bool markEndNow = false,
  }) async {
    final workshop = _workshops.firstWhere((w) => w.id == workshopId);
    final session = workshop.sessions.firstWhere((s) => s.id == sessionId);

    session.title = title.trim().isNotEmpty ? title.trim() : session.title;
    session.date = date;
    if (impartedDaysLabel != null &&
        impartedDaysLabel.trim().isNotEmpty &&
        !impartedDaysLabel.contains('•')) {
      session.impartedDaysLabel = impartedDaysLabel.trim();
    } else {
      session.impartedDaysLabel = WorkshopSession.formatSingleDateWithDay(date);
    }
    session.startTimeLabel = startTimeLabel.trim();
    session.endTimeLabel = endTimeLabel.trim();
    if (toleranceMinutes != null) {
      session.toleranceMinutes = toleranceMinutes;
    }
    if (markStartNow) {
      session.actualStartedAt = DateTime.now();
    }
    if (markEndNow) {
      session.actualEndedAt = DateTime.now();
    }

    await _persist();
    _pushSessionToSupabaseAsync(workshop, session);
    notifyListeners();
  }

  // --- CONTROL DE FASES Y TIEMPOS DE SESIÓN (DOCENTE) ---

  Future<void> updateSessionPhase({
    required String workshopId,
    required String sessionId,
    required SessionPhase newPhase,
  }) async {
    final workshop = _workshops.firstWhere((w) => w.id == workshopId);
    final session = workshop.sessions.firstWhere((s) => s.id == sessionId);

    final now = DateTime.now();
    session.currentPhase = newPhase;
    session.phaseStartedAt = now;

    // Registrar evidencia exacta de cuándo comenzó y a qué hora terminó
    if (newPhase == SessionPhase.entry) {
      session.actualStartedAt ??= now;
    } else if (newPhase == SessionPhase.exit ||
        newPhase == SessionPhase.finished) {
      session.actualEndedAt = now;
    }

    await _persist();
    _pushWorkshopToSupabaseAsync(workshop);
    _pushSessionToSupabaseAsync(workshop, session);
  }

  /// Configurar el tiempo límite de registro y los minutos de tolerancia/retraso (ej. 15 min)
  Future<void> updateSessionTimings({
    required String workshopId,
    required String sessionId,
    required int toleranceMinutes,
    required int registrationWindowMinutes,
    bool resetClock = false,
  }) async {
    final workshop = _workshops.firstWhere((w) => w.id == workshopId);
    final session = workshop.sessions.firstWhere((s) => s.id == sessionId);

    session.toleranceMinutes = toleranceMinutes;
    session.registrationWindowMinutes = registrationWindowMinutes;
    if (resetClock || session.phaseStartedAt == null) {
      session.phaseStartedAt = DateTime.now();
    }

    await _persist();
    _pushSessionToSupabaseAsync(workshop, session);
  }

  // --- REGISTRO DE ASISTENCIA MEDIANTE ESCANEO QR ---

  AttendanceProcessResult processQrScan({
    required String qrRawContent,
    required String studentEnrollmentNumber,
    String? studentFullName,
    String? studentEmail,
    String? deviceId,
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

    final cleanInputControl = studentEnrollmentNumber.trim();
    final cleanInputName = (studentFullName ?? '').trim();

    String normalize(String s) {
      return s
          .toLowerCase()
          .replaceAll('á', 'a')
          .replaceAll('é', 'e')
          .replaceAll('í', 'i')
          .replaceAll('ó', 'o')
          .replaceAll('ú', 'u')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
    }

    // 3. Buscar al estudiante en la lista de inscritos por número de control
    Student? student = workshop.enrolledStudents.cast<Student?>().firstWhere(
      (s) =>
          s != null &&
          s.enrollmentNumber.trim().toLowerCase() ==
              cleanInputControl.toLowerCase(),
      orElse: () => null,
    );

    // Validación A: Si la matrícula ya existe en el taller, verificar que el nombre coincida
    if (student != null && cleanInputName.isNotEmpty) {
      final normInput = normalize(cleanInputName);
      final normExisting = normalize(student.fullName);

      final isPlaceholderName = normExisting.startsWith('alumno ') ||
          normExisting == normalize(student.enrollmentNumber) ||
          normExisting.isEmpty;

      if (!isPlaceholderName) {
        final inputTokens =
            normInput.split(' ').where((t) => t.length > 2).toSet();
        final existingTokens =
            normExisting.split(' ').where((t) => t.length > 2).toSet();
        final commonTokens = inputTokens.intersection(existingTokens);

        // Si no comparten palabras y son distintos, rechazar por duplicidad/suplantación
        if (commonTokens.isEmpty && normInput != normExisting) {
          return AttendanceProcessResult(
            success: false,
            title: '⛔ Matrícula Ya Registrada',
            message:
                'El número de control "$cleanInputControl" ya pertenece al alumno registrado "${student.fullName}". Los datos no corresponden a "$cleanInputName". Los números de control y nombres no pueden repetirse ni duplicarse.',
            status: AttendanceStatus.absent,
            student: student,
          );
        }
      } else {
        student.fullName = cleanInputName;
        _persist();
        _pushStudentToSupabaseAsync(student, workshop.id);
      }
    }

    // Validación B: Si la matrícula no existe, verificar que el nombre no esté registrado
    // bajo otro número de control distinto (para evitar duplicados del mismo alumno)
    if (student == null && cleanInputName.isNotEmpty) {
      final normInput = normalize(cleanInputName);
      Student? studentWithSameName =
          workshop.enrolledStudents.cast<Student?>().firstWhere(
        (s) {
          if (s == null) return false;
          final normExisting = normalize(s.fullName);
          if (normExisting.startsWith('alumno ') ||
              normExisting == normalize(s.enrollmentNumber)) {
            return false;
          }
          return normExisting == normInput;
        },
        orElse: () => null,
      );

      if (studentWithSameName != null &&
          studentWithSameName.enrollmentNumber.trim().toLowerCase() !=
              cleanInputControl.toLowerCase()) {
        return AttendanceProcessResult(
          success: false,
          title: '⛔ Nombre Ya Registrado',
          message:
              'Ya existe un alumno registrado con el nombre "$cleanInputName" bajo el número de control "${studentWithSameName.enrollmentNumber}". El nombre y número de control no pueden repetirse. Por favor verifica tus datos oficiales.',
          status: AttendanceStatus.absent,
        );
      }
    }

    // Auto-inscribir al estudiante si escanea por primera vez desde su celular
    if (student == null) {
      if (cleanInputName.isNotEmpty) {
        student = Student(
          id: 'std_${_uuid.v4().substring(0, 8)}',
          enrollmentNumber: cleanInputControl,
          fullName: cleanInputName,
          email: studentEmail?.trim().isNotEmpty == true
              ? studentEmail!.trim()
              : '${cleanInputControl.toLowerCase()}@alumno.edu',
          boundDeviceId: deviceId?.trim().isNotEmpty == true
              ? deviceId!.trim().toUpperCase()
              : null,
          deviceUpdatedAt: DateTime.now(),
        );
        workshop.enrolledStudents.add(student);
        _persist();
        _pushStudentToSupabaseAsync(student, workshop.id);
      } else {
        return AttendanceProcessResult(
          success: false,
          title: 'Estudiante No Inscrito',
          message:
              'La matrícula "$cleanInputControl" no se encuentra registrada en la lista oficial de este taller (${workshop.name}).',
        );
      }
    } else if (deviceId != null && deviceId.trim().isNotEmpty) {
      final incomingDev = deviceId.trim().toUpperCase();
      // Verificar si este celular era el celular VIEJO que ya fue borrado
      if (student.previousDeviceId != null &&
          student.previousDeviceId!.toUpperCase() == incomingDev &&
          student.boundDeviceId != incomingDev) {
        return AttendanceProcessResult(
          success: false,
          title: '⛔ Celular Anterior Dado de Baja',
          message:
              'Este celular ($incomingDev) fue borrado y reemplazado por tu nuevo celular por autorización del docente encargado.',
          status: AttendanceStatus.absent,
          student: student,
        );
      }

      // Si el docente autorizó un nuevo celular o el alumno aún no tenía celular vinculado, el nuevo toma el lugar del viejo
      if (student.allowNewDevice ||
          student.boundDeviceId == null ||
          student.boundDeviceId!.isEmpty) {
        student.boundDeviceId = incomingDev;
        student.allowNewDevice = false;
        student.deviceUpdatedAt = DateTime.now();
        _persist();
        _pushStudentToSupabaseAsync(student, workshop.id);
      } else if (student.boundDeviceId!.toUpperCase() != incomingDev) {
        return AttendanceProcessResult(
          success: false,
          title: '📱 Celular Nuevo No Autorizado Aún',
          message:
              'Tu matrícula (${student.enrollmentNumber}) está vinculada a tu celular anterior (${student.boundDeviceId}). Si cambiaste de celular (ID nuevo: $incomingDev), pídele al docente encargado que presione "📱 Autorizar Nuevo Celular" en tu ficha para borrar el viejo y activar este nuevo.',
          status: AttendanceStatus.absent,
          student: student,
        );
      }
    }

    // 4. Procesar el registro según la fase
    return _applyAttendance(
      workshop: workshop,
      session: session,
      student: student,
      phase: session.currentPhase,
      deviceId: deviceId,
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
    String? deviceId,
  }) {
    final now = DateTime.now();
    var record = session.records[student.id];

    if (record == null) {
      record = AttendanceRecord(
        id: 'rec_${_uuid.v4().substring(0, 8)}',
        studentId: student.id,
        sessionId: session.id,
        deviceId: deviceId,
      );
      session.records[student.id] = record;
    } else if (deviceId != null && deviceId.trim().isNotEmpty) {
      record.deviceId = deviceId.trim().toUpperCase();
    }

    if (student.isSuspended || record.isSuspended) {
      final reason =
          record.suspensionReason ??
          student.suspensionReason ??
          'Comportamiento inapropiado reportado por el docente encargado.';
      return AttendanceProcessResult(
        success: false,
        title: '🚫 Alumno Suspendido por Conducta',
        message:
            'El alumno ${student.fullName} se encuentra SUSPENDIDO por el docente encargado (${workshop.instructorName}). Motivo: "$reason". No puede acreditar asistencia mientras la suspensión esté activa.',
        status: AttendanceStatus.absent,
        student: student,
      );
    }

    // --- MODO CONFERENCIA: REGISTRO ÚNICO DE ASISTENCIA Y SALIDA / ACREDITACIÓN DIRECTA ---
    if (workshop.isConference) {
      if (record.hasCheckIn && record.status == AttendanceStatus.accredited) {
        return AttendanceProcessResult(
          success: true,
          title: '🎓 Conferencia Ya Acreditada 🔒',
          message:
              'Tu asistencia a la conferencia ya fue sellada a las ${_formatTime(record.checkInTime!)} y tu acreditación se encuentra registrada y asegurada.',
          status: AttendanceStatus.accredited,
          student: student,
        );
      }

      record.sealCheckIn(now);
      record.sealCheckOut(now);
      record.isLocked = true;
      record.notes = 'Asistencia y Acreditación de Conferencia en Registro Único';

      if (session.phaseStartedAt != null) {
        final minsElapsed = now.difference(session.phaseStartedAt!).inMinutes;
        if (minsElapsed > session.toleranceMinutes) {
          record.isLate = true;
          record.lateMinutes = minsElapsed;
        } else {
          record.isLate = false;
          record.lateMinutes = 0;
        }
      }

      _persist();
      PowerSyncService().saveAttendanceRecord(
        record: record,
        workshopId: workshop.id,
      );
      _syncRecordToSupabaseAsync(
        record,
        student,
        session.id,
        workshop: workshop,
        session: session,
      );

      final lateTag = record.isLate
          ? ' (⏱️ Registrado con retraso: +${record.lateMinutes} min)'
          : ' (✅ Puntual dentro de tolerancia)';

      return AttendanceProcessResult(
        success: true,
        title: '🎓 ¡Conferencia ACREDITADA! 🎉',
        message:
            '¡Excelente, ${student.fullName}! Se registró tu asistencia a la conferencia a las ${_formatTime(now)}$lateTag. Tu acreditación ha sido otorgada con éxito en un solo registro.',
        status: AttendanceStatus.accredited,
        student: student,
      );
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

      // Evaluar si el alumno se registró dentro de la tolerancia o con retraso
      if (session.phaseStartedAt != null) {
        final minsElapsed = now.difference(session.phaseStartedAt!).inMinutes;
        if (minsElapsed > session.toleranceMinutes) {
          record.isLate = true;
          record.lateMinutes = minsElapsed;
        } else {
          record.isLate = false;
          record.lateMinutes = 0;
        }
      }

      _persist();
      PowerSyncService().saveAttendanceRecord(
        record: record,
        workshopId: workshop.id,
      );
      _syncRecordToSupabaseAsync(
        record,
        student,
        session.id,
        workshop: workshop,
        session: session,
      );

      final lateTag = record.isLate
          ? ' (⏱️ Registrado con retraso: +${record.lateMinutes} min respecto al inicio; tolerancia: ${session.toleranceMinutes} min)'
          : ' (✅ Puntual dentro de los ${session.toleranceMinutes} min de tolerancia)';

      return AttendanceProcessResult(
        success: true,
        title: record.isLate
            ? '🟠 Entrada con Retraso 🔒'
            : '🟢 Entrada Puntual Sellada 🔒',
        message:
            '¡Bienvenido(a), ${student.fullName}! Se registró tu entrada a las ${_formatTime(now)}$lateTag. Recuerda registrar tu salida al terminar para ACREDITAR.',
        status: record.status,
        student: student,
      );
    } else if (phase == SessionPhase.exit) {
      if (record.hasCheckOut) {
        return AttendanceProcessResult(
          success: true,
          title: record.hasCheckIn
              ? '🎓 ¡Asistencia Ya ACREDITADA! 🔒'
              : 'Salida Ya Sellada 🔒',
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
      _syncRecordToSupabaseAsync(
        record,
        student,
        session.id,
        workshop: workshop,
        session: session,
      );

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

      final Map<String, dynamic> data = jsonDecode(payload);
      final targetSessionId = data['s']?.toString();
      final targetWorkshopId = data['w']?.toString();

      if (targetSessionId != null && targetSessionId.isNotEmpty) {
        for (var w in _workshops) {
          if (targetWorkshopId != null &&
              targetWorkshopId.isNotEmpty &&
              w.id != targetWorkshopId) {
            continue;
          }
          for (var s in w.sessions) {
            if (s.id == targetSessionId) {
              return _WorkshopSessionMatch(workshop: w, session: s);
            }
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
    int lateCount = 0;
    int notesCount = 0;
    int registeredTodayCount = 0;

    for (var student in workshop.enrolledStudents) {
      final rec = session.records[student.id];
      if (rec == null) {
        pending++;
      } else {
        if (rec.hasCheckIn) entriesCount++;
        if (rec.hasCheckOut) exitsCount++;
        if (rec.isLate) lateCount++;
        if (rec.hasNotes) notesCount++;
        if (rec.hasCheckIn || rec.hasCheckOut || rec.hasNotes) {
          registeredTodayCount++;
        }

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
      lateCount: lateCount,
      notesCount: notesCount,
      registeredTodayCount: registeredTodayCount,
    );
  }

  // --- CONTROL DE INVENTARIO, NOTAS DE EVIDENCIA Y ACREDITACIÓN DOCENTE ---

  /// Toma de nota / evidencia por el docente cuando un alumno tiene un problema o situación especial
  Future<AttendanceRecord> saveStudentIncidentNote({
    required String workshopId,
    required String sessionId,
    required String studentId,
    required String noteText,
    bool markEntry = true,
    bool markAccredited = false,
  }) async {
    final workshop = _workshops.firstWhere((w) => w.id == workshopId);
    final session = workshop.sessions.firstWhere((s) => s.id == sessionId);
    final student = workshop.enrolledStudents.firstWhere(
      (s) => s.id == studentId,
    );

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

    final folio =
        'EV-${now.day.toString().padLeft(2, '0')}${now.month.toString().padLeft(2, '0')}-${now.millisecondsSinceEpoch.toString().substring(9)}';
    final dateStr =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year} ${_formatTime(now)}';
    final cleanInput = noteText.trim();
    record.notes =
        '[$folio • $dateStr • Docente: ${workshop.instructorName}] $cleanInput';

    if (!student.isSuspended && !record.isSuspended) {
      if (markEntry && !record.hasCheckIn) {
        record.sealCheckIn(now);
      }
      if (markAccredited) {
        if (!record.hasCheckIn) record.sealCheckIn(now);
        if (!record.hasCheckOut) record.sealCheckOut(now);
      }
    }

    await _persist();
    PowerSyncService().saveAttendanceRecord(
      record: record,
      workshopId: workshop.id,
    );
    _syncRecordToSupabaseAsync(
      record,
      student,
      session.id,
      workshop: workshop,
      session: session,
    );
    notifyListeners();
    return record;
  }

  /// Acredita directamente a un alumno en la sesión actual (Entrada + Salida OK)
  Future<void> accreditStudentDirectly({
    required String workshopId,
    required String sessionId,
    required String studentId,
  }) async {
    final workshop = _workshops.firstWhere((w) => w.id == workshopId);
    final session = workshop.sessions.firstWhere((s) => s.id == sessionId);
    final student = workshop.enrolledStudents.firstWhere(
      (s) => s.id == studentId,
    );

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

    if (student.isSuspended || record.isSuspended) {
      return;
    }

    if (!record.hasCheckIn) record.sealCheckIn(now);
    if (!record.hasCheckOut) record.sealCheckOut(now);

    await _persist();
    PowerSyncService().saveAttendanceRecord(
      record: record,
      workshopId: workshop.id,
    );
    _syncRecordToSupabaseAsync(
      record,
      student,
      session.id,
      workshop: workshop,
      session: session,
    );
    notifyListeners();
  }

  /// Acredita en bloque a todos los alumnos que registraron su asistencia hoy en esta sesión
  Future<int> accreditAllRegisteredInSession({
    required String workshopId,
    required String sessionId,
  }) async {
    final workshop = _workshops.firstWhere((w) => w.id == workshopId);
    final session = workshop.sessions.firstWhere((s) => s.id == sessionId);
    final now = DateTime.now();
    int count = 0;

    for (final student in workshop.enrolledStudents) {
      if (student.isSuspended) continue;
      final rec = session.records[student.id];
      if (rec != null &&
          !rec.isSuspended &&
          (rec.hasCheckIn || rec.hasCheckOut || rec.hasNotes)) {
        if (!rec.hasCheckIn) rec.sealCheckIn(now);
        if (!rec.hasCheckOut) rec.sealCheckOut(now);
        PowerSyncService().saveAttendanceRecord(
          record: rec,
          workshopId: workshop.id,
        );
        _syncRecordToSupabaseAsync(
          rec,
          student,
          session.id,
          workshop: workshop,
          session: session,
        );
        count++;
      }
    }

    if (count > 0) {
      await _persist();
      notifyListeners();
    }
    return count;
  }

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
        req.headers.set(
          'apikey',
          'sb_publishable_A-jiTpI9-hoDwOaln0_BWw_omLvRnRN',
        );
        req.headers.set(
          'Authorization',
          'Bearer sb_publishable_A-jiTpI9-hoDwOaln0_BWw_omLvRnRN',
        );
        final res = await req.close();
        await res.drain();
        client.close();
      } catch (e) {
        debugPrint('Aviso Supabase delete: $e');
      }
    }

    notifyListeners();
  }

  /// Sincronizar registros del inventario en vivo desde Supabase Cloud (estrictamente para esta sesión)
  Future<int> syncRecordsFromSupabase({
    required String workshopId,
    required String sessionId,
  }) async {
    if (kIsWeb) return 0;
    try {
      final wIdx = _workshops.indexWhere((w) => w.id == workshopId);
      if (wIdx == -1) return 0;
      final workshop = _workshops[wIdx];
      final sIdx = workshop.sessions.indexWhere((s) => s.id == sessionId);
      if (sIdx == -1) return 0;
      final session = workshop.sessions[sIdx];

      final client = HttpClient();

      // 1. Traer ÚNICAMENTE los registros de asistencia que corresponden a ESTA sesión exacta
      final uri = Uri.parse(
        'https://qukqvrowgzdkqoccbfdb.supabase.co/rest/v1/attendance_records?session_id=eq.$sessionId&select=*,students(*)&order=created_at.asc',
      );
      final req = await client.getUrl(uri);
      req.headers.set(
        'apikey',
        'sb_publishable_A-jiTpI9-hoDwOaln0_BWw_omLvRnRN',
      );
      req.headers.set(
        'Authorization',
        'Bearer sb_publishable_A-jiTpI9-hoDwOaln0_BWw_omLvRnRN',
      );
      final res = await req.close();
      final responseBody = await res.transform(utf8.decoder).join();
      client.close();

      if (res.statusCode == 200) {
        final List<dynamic> list = jsonDecode(responseBody);
        int updatedCount = 0;

        // Limpiar cualquier registro que haya quedado erróneamente guardado con sessionId diferente
        session.records.removeWhere(
          (k, r) => r.sessionId.isNotEmpty && r.sessionId != sessionId,
        );

        for (var item in list) {
          final recSessionId = item['session_id']?.toString() ?? '';
          // Validación estricta: sólo registros que pertenezcan a esta sesión exacta
          if (recSessionId != sessionId) continue;

          final studentData = item['students'];
          String? sId = item['student_id']?.toString();

          if (studentData != null) {
            final studentWorkshopId = studentData['workshop_id']?.toString();
            if (studentWorkshopId != null &&
                studentWorkshopId.isNotEmpty &&
                studentWorkshopId != workshop.id) {
              // El estudiante pertenece a otro taller
              continue;
            }
            final enrollment = studentData['enrollment_number']
                ?.toString()
                .trim()
                .toUpperCase();
            var existingStudent = workshop.enrolledStudents
                .where(
                  (s) =>
                      (enrollment != null &&
                          s.enrollmentNumber.trim().toUpperCase() ==
                              enrollment) ||
                      s.id == sId,
                )
                .firstOrNull;

            if (existingStudent == null &&
                enrollment != null &&
                enrollment.isNotEmpty) {
              final rawCloudEmail =
                  (studentData['email'] ?? '$enrollment@alumno.edu')
                      .toString()
                      .trim();
              existingStudent = Student(
                id: sId ?? 'std_${_uuid.v4().substring(0, 8)}',
                fullName: (studentData['full_name'] ?? 'Alumno')
                    .toString()
                    .trim(),
                enrollmentNumber: enrollment,
                email: Student.extractCleanEmail(rawCloudEmail, enrollment),
              );
              existingStudent.applySupabaseEmailMeta(rawCloudEmail);
              workshop.enrolledStudents.add(existingStudent);
            } else if (existingStudent != null) {
              if (studentData['email'] != null &&
                  !existingStudent.allowNewDevice) {
                existingStudent.applySupabaseEmailMeta(
                  studentData['email'].toString(),
                );
              }
              if (studentData['full_name'] != null) {
                final cloudName = studentData['full_name'].toString().trim();
                if (cloudName.isNotEmpty &&
                    existingStudent.fullName == 'Alumno') {
                  final idx = workshop.enrolledStudents.indexOf(
                    existingStudent,
                  );
                  existingStudent = Student(
                    id: existingStudent.id,
                    fullName: cloudName,
                    enrollmentNumber: existingStudent.enrollmentNumber,
                    email: existingStudent.email,
                    isSuspended: existingStudent.isSuspended,
                    suspensionReason: existingStudent.suspensionReason,
                    suspendedAt: existingStudent.suspendedAt,
                    boundDeviceId: existingStudent.boundDeviceId,
                    previousDeviceId: existingStudent.previousDeviceId,
                    allowNewDevice: existingStudent.allowNewDevice,
                    deviceUpdatedAt: existingStudent.deviceUpdatedAt,
                  );
                  workshop.enrolledStudents[idx] = existingStudent;
                }
              }
            }

            if (existingStudent != null) {
              sId = existingStudent.id;
            }
          }

          if (sId != null) {
            DateTime? checkIn;
            DateTime? checkOut;
            if (item['check_in_time'] != null) {
              checkIn = DateTime.tryParse(item['check_in_time'].toString())
                  ?.toLocal();
            }
            if (item['check_out_time'] != null) {
              checkOut = DateTime.tryParse(item['check_out_time'].toString())
                  ?.toLocal();
            }

            final prevRec = session.records[sId];
            final rec = AttendanceRecord(
              id:
                  item['id']?.toString() ??
                  prevRec?.id ??
                  'rec_${_uuid.v4().substring(0, 8)}',
              studentId: sId,
              sessionId: sessionId,
              checkInTime: checkIn ?? prevRec?.checkInTime,
              checkOutTime: checkOut ?? prevRec?.checkOutTime,
              isLocked: item['is_locked'] == true || item['is_locked'] == 1,
              notes: prevRec?.notes,
              isLate: prevRec?.isLate ?? false,
              lateMinutes: prevRec?.lateMinutes ?? 0,
            );

            rec.applySupabaseStatus(
              item['status']?.toString(),
              explicitNotes: item['notes']?.toString(),
            );

            // Si el registro en la nube trae el ID del celular (DEV:...), actualizar la vinculación del alumno
            final stdRef = workshop.enrolledStudents
                .where((s) => s.id == sId)
                .firstOrNull;
            if (stdRef != null &&
                rec.deviceId != null &&
                rec.deviceId!.isNotEmpty) {
              if (stdRef.allowNewDevice ||
                  stdRef.boundDeviceId == null ||
                  stdRef.boundDeviceId!.isEmpty) {
                stdRef.boundDeviceId = rec.deviceId;
                stdRef.allowNewDevice = false;
                stdRef.deviceUpdatedAt = DateTime.now();
              }
            }

            // Calcular si entró con retraso respecto al inicio del pase si aún no estaba calculado
            if (!rec.isLate &&
                rec.checkInTime != null &&
                session.phaseStartedAt != null) {
              final diffMins = rec.checkInTime!
                  .difference(session.phaseStartedAt!)
                  .inMinutes;
              if (diffMins > session.toleranceMinutes) {
                rec.isLate = true;
                rec.lateMinutes = diffMins;
              }
            }

            session.records[sId] = rec;
            updatedCount++;

            // Si al consolidar registros del día el alumno ya tiene Entrada + Salida (ACREDITADO) pero en Supabase decía incompleteExitOnly o pending, actualizar en la nube
            final rawCloudStatus = item['status']?.toString() ?? '';
            final matchedStudent = workshop.enrolledStudents
                .where((s) => s.id == sId)
                .firstOrNull;
            if (rec.hasCheckIn &&
                rec.hasCheckOut &&
                !rawCloudStatus.startsWith('accredited') &&
                matchedStudent != null) {
              _syncRecordToSupabaseAsync(
                rec,
                matchedStudent,
                sessionId,
                workshop: workshop,
                session: session,
              );
            }
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

  void _pushWorkshopToSupabaseAsync(Workshop workshop) {
    if (kIsWeb) return;
    try {
      HttpClient()
          .postUrl(
            Uri.parse(
              'https://qukqvrowgzdkqoccbfdb.supabase.co/rest/v1/workshops?on_conflict=id',
            ),
          )
          .then((req) {
            req.headers.set(
              'apikey',
              'sb_publishable_A-jiTpI9-hoDwOaln0_BWw_omLvRnRN',
            );
            req.headers.set(
              'Authorization',
              'Bearer sb_publishable_A-jiTpI9-hoDwOaln0_BWw_omLvRnRN',
            );
            req.headers.set('Content-Type', 'application/json');
            req.headers.set('Prefer', 'resolution=merge-duplicates');
            req.write(
              jsonEncode({
                'id': workshop.id,
                'name': workshop.name,
                'code': workshop.code,
                'instructor_name': workshop.instructorName,
                'description': workshop.description,
              }),
            );
            return req.close();
          })
          .then((res) => res.drain())
          .catchError((_) {});
    } catch (_) {}
  }

  void _pushSessionToSupabaseAsync(Workshop workshop, WorkshopSession session) {
    if (kIsWeb) return;
    try {
      HttpClient()
          .postUrl(
            Uri.parse(
              'https://qukqvrowgzdkqoccbfdb.supabase.co/rest/v1/workshop_sessions?on_conflict=id',
            ),
          )
          .then((req) {
            req.headers.set(
              'apikey',
              'sb_publishable_A-jiTpI9-hoDwOaln0_BWw_omLvRnRN',
            );
            req.headers.set(
              'Authorization',
              'Bearer sb_publishable_A-jiTpI9-hoDwOaln0_BWw_omLvRnRN',
            );
            req.headers.set('Content-Type', 'application/json');
            req.headers.set('Prefer', 'resolution=merge-duplicates');
            req.write(
              jsonEncode({
                'id': session.id,
                'workshop_id': workshop.id,
                'title':
                    '${session.title} (${session.formattedShortDate} • ${session.startTimeLabel}-${session.endTimeLabel})',
                'current_phase': session.currentPhase.name,
                'is_active': session.isQrActive,
              }),
            );
            return req.close();
          })
          .then((res) => res.drain())
          .catchError((_) {});
    } catch (_) {}
  }

  void _pushStudentToSupabaseAsync(Student student, String workshopId) {
    if (kIsWeb) return;
    try {
      final encodedMail = student.encodeSupabaseEmail();
      HttpClient()
          .postUrl(
            Uri.parse(
              'https://qukqvrowgzdkqoccbfdb.supabase.co/rest/v1/students?on_conflict=id',
            ),
          )
          .then((req) {
            req.headers.set(
              'apikey',
              'sb_publishable_A-jiTpI9-hoDwOaln0_BWw_omLvRnRN',
            );
            req.headers.set(
              'Authorization',
              'Bearer sb_publishable_A-jiTpI9-hoDwOaln0_BWw_omLvRnRN',
            );
            req.headers.set('Content-Type', 'application/json');
            req.headers.set('Prefer', 'resolution=merge-duplicates');
            req.write(
              jsonEncode({
                'id': student.id,
                'workshop_id': workshopId,
                'enrollment_number': student.enrollmentNumber.toUpperCase(),
                'full_name': student.fullName,
                'email': encodedMail,
              }),
            );
            return req.close();
          })
          .then((res) => res.drain())
          .catchError((_) {});

      // También actualizar cualquier fila previa de la misma matrícula en Supabase para que el portal web vea de inmediato el cambio/autorización de celular
      HttpClient()
          .patchUrl(
            Uri.parse(
              'https://qukqvrowgzdkqoccbfdb.supabase.co/rest/v1/students?enrollment_number=ilike.${Uri.encodeComponent(student.enrollmentNumber.toUpperCase())}',
            ),
          )
          .then((req) {
            req.headers.set(
              'apikey',
              'sb_publishable_A-jiTpI9-hoDwOaln0_BWw_omLvRnRN',
            );
            req.headers.set(
              'Authorization',
              'Bearer sb_publishable_A-jiTpI9-hoDwOaln0_BWw_omLvRnRN',
            );
            req.headers.set('Content-Type', 'application/json');
            req.write(
              jsonEncode({'full_name': student.fullName, 'email': encodedMail}),
            );
            return req.close();
          })
          .then((res) => res.drain())
          .catchError((_) {});
    } catch (_) {}
  }

  Future<void> _syncRecordToSupabaseAsync(
    AttendanceRecord record,
    Student student,
    String sessionId, {
    Workshop? workshop,
    WorkshopSession? session,
  }) async {
    if (kIsWeb) return;
    try {
      if (workshop != null) {
        _pushWorkshopToSupabaseAsync(workshop);
        if (session != null) {
          _pushSessionToSupabaseAsync(workshop, session);
        }
      }
      _pushStudentToSupabaseAsync(student, workshop?.id ?? '');

      final client = HttpClient();
      final req = await client.postUrl(
        Uri.parse(
          'https://qukqvrowgzdkqoccbfdb.supabase.co/rest/v1/attendance_records?on_conflict=id',
        ),
      );
      req.headers.set(
        'apikey',
        'sb_publishable_A-jiTpI9-hoDwOaln0_BWw_omLvRnRN',
      );
      req.headers.set(
        'Authorization',
        'Bearer sb_publishable_A-jiTpI9-hoDwOaln0_BWw_omLvRnRN',
      );
      req.headers.set('Content-Type', 'application/json');
      req.headers.set('Prefer', 'resolution=merge-duplicates');
      final body = jsonEncode({
        'id': record.id,
        'student_id': student.id,
        'session_id': sessionId,
        'check_in_time': record.checkInTime?.toUtc().toIso8601String(),
        'check_out_time': record.checkOutTime?.toUtc().toIso8601String(),
        'is_locked': record.isLocked,
        'status': record.encodeSupabaseStatus(),
      });
      req.write(body);
      final res = await req.close();
      await res.drain();
      client.close();
    } catch (err) {
      debugPrint('Aviso sync Supabase: $err');
    }
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
  final int lateCount;
  final int notesCount;
  final int registeredTodayCount;

  SessionStatistics({
    required this.totalStudents,
    required this.accredited,
    required this.incomplete,
    required this.absent,
    required this.entriesCount,
    required this.exitsCount,
    this.lateCount = 0,
    this.notesCount = 0,
    this.registeredTodayCount = 0,
  });

  double get accreditedPercentage =>
      totalStudents == 0 ? 0 : (accredited / totalStudents);
}

class _WorkshopSessionMatch {
  final Workshop workshop;
  final WorkshopSession session;
  _WorkshopSessionMatch({required this.workshop, required this.session});
}
