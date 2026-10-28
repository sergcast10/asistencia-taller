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

    // Sincronizar automáticamente desde Supabase al iniciar
    syncAllActiveSessionsFromSupabase();
  }

  /// Sincroniza todas las sesiones del taller activo con Supabase
  Future<void> syncAllActiveSessionsFromSupabase() async {
    for (final w in _workshops) {
      _pushWorkshopToSupabaseAsync(w);
      for (final s in w.sessions) {
        _pushSessionToSupabaseAsync(w, s);
        await syncRecordsFromSupabase(workshopId: w.id, sessionId: s.id);
      }
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
    _pushWorkshopToSupabaseAsync(newWorkshop);
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
          fullName: fullName.trim().isNotEmpty ? fullName.trim() : existing.fullName,
          email: email.trim().isNotEmpty ? email.trim() : existing.email,
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

    final updated = Student(
      id: studentId,
      enrollmentNumber: enrollmentNumber.trim().toUpperCase(),
      fullName: fullName.trim(),
      email: email.trim().isNotEmpty
          ? email.trim()
          : '${enrollmentNumber.trim().toLowerCase()}@alumno.edu',
    );
    workshop.enrolledStudents[sIdx] = updated;
    await _persist();
    _pushStudentToSupabaseAsync(updated, workshopId);
    notifyListeners();
    return updated;
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
    session ??= workshop.sessions.where((s) => s.isQrActive).firstOrNull ??
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
    int toleranceMinutes = 15,
    int registrationWindowMinutes = 45,
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
      toleranceMinutes: toleranceMinutes,
      registrationWindowMinutes: registrationWindowMinutes,
      records: {},
    );

    _workshops[index].sessions.insert(0, newSession);
    await _persist();
    _pushWorkshopToSupabaseAsync(_workshops[index]);
    _pushSessionToSupabaseAsync(_workshops[index], newSession);
    return newSession;
  }

  // --- CONTROL DE FASES Y TIEMPOS DE SESIÓN (DOCENTE) ---

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
      _syncRecordToSupabaseAsync(record, student, session.id, workshop: workshop, session: session);

      final lateTag = record.isLate
          ? ' (⏱️ Registrado con retraso: +${record.lateMinutes} min respecto al inicio; tolerancia: ${session.toleranceMinutes} min)'
          : ' (✅ Puntual dentro de los ${session.toleranceMinutes} min de tolerancia)';

      return AttendanceProcessResult(
        success: true,
        title: record.isLate ? '🟠 Entrada con Retraso 🔒' : '🟢 Entrada Puntual Sellada 🔒',
        message:
            '¡Bienvenido(a), ${student.fullName}! Se registró tu entrada a las ${_formatTime(now)}$lateTag. Recuerda registrar tu salida al terminar para ACREDITAR.',
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
      _syncRecordToSupabaseAsync(record, student, session.id, workshop: workshop, session: session);

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
    final student = workshop.enrolledStudents.firstWhere((s) => s.id == studentId);

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

    final folio = 'EV-${now.day.toString().padLeft(2, '0')}${now.month.toString().padLeft(2, '0')}-${now.millisecondsSinceEpoch.toString().substring(9)}';
    final dateStr = '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year} ${_formatTime(now)}';
    final cleanInput = noteText.trim();
    record.notes = '[$folio • $dateStr • Docente: ${workshop.instructorName}] $cleanInput';

    if (markEntry && !record.hasCheckIn) {
      record.sealCheckIn(now);
    }
    if (markAccredited) {
      if (!record.hasCheckIn) record.sealCheckIn(now);
      if (!record.hasCheckOut) record.sealCheckOut(now);
    }

    await _persist();
    PowerSyncService().saveAttendanceRecord(record: record, workshopId: workshop.id);
    _syncRecordToSupabaseAsync(record, student, session.id, workshop: workshop, session: session);
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
    final student = workshop.enrolledStudents.firstWhere((s) => s.id == studentId);

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

    if (!record.hasCheckIn) record.sealCheckIn(now);
    if (!record.hasCheckOut) record.sealCheckOut(now);

    await _persist();
    PowerSyncService().saveAttendanceRecord(record: record, workshopId: workshop.id);
    _syncRecordToSupabaseAsync(record, student, session.id, workshop: workshop, session: session);
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
      final rec = session.records[student.id];
      if (rec != null && (rec.hasCheckIn || rec.hasCheckOut || rec.hasNotes)) {
        if (!rec.hasCheckIn) rec.sealCheckIn(now);
        if (!rec.hasCheckOut) rec.sealCheckOut(now);
        PowerSyncService().saveAttendanceRecord(record: rec, workshopId: workshop.id);
        _syncRecordToSupabaseAsync(rec, student, session.id, workshop: workshop, session: session);
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

  bool _isSameCalendarDay(DateTime a, DateTime b) {
    final la = a.toLocal();
    final lb = b.toLocal();
    return la.year == lb.year && la.month == lb.month && la.day == lb.day;
  }

  /// Sincronizar registros del inventario en vivo desde Supabase Cloud (incluye alumnos registrados hoy)
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

      // 1. Traer todos los registros de asistencia con los datos del estudiante
      final uri = Uri.parse(
        'https://qukqvrowgzdkqoccbfdb.supabase.co/rest/v1/attendance_records?select=*,students(*)&order=created_at.asc',
      );
      final req = await client.getUrl(uri);
      req.headers.set('apikey', 'sb_publishable_A-jiTpI9-hoDwOaln0_BWw_omLvRnRN');
      req.headers.set('Authorization', 'Bearer sb_publishable_A-jiTpI9-hoDwOaln0_BWw_omLvRnRN');
      final res = await req.close();
      final responseBody = await res.transform(utf8.decoder).join();
      client.close();

      if (res.statusCode == 200) {
        final List<dynamic> list = jsonDecode(responseBody);
        int updatedCount = 0;

        for (var item in list) {
          final recSessionId = item['session_id']?.toString() ?? '';
          final createdAtStr = item['created_at']?.toString() ?? item['check_in_time']?.toString();
          final createdAt = createdAtStr != null ? DateTime.tryParse(createdAtStr)?.toLocal() : null;

          // Aceptar si pertenece exactamente a esta sesión, o si fue registrado el día de hoy
          final isExactSession = recSessionId == sessionId;
          final isSameDayRecord = createdAt != null && _isSameCalendarDay(createdAt, session.date);

          if (!isExactSession && !isSameDayRecord) continue;

          final studentData = item['students'];
          String? sId = item['student_id']?.toString();

          if (studentData != null) {
            final enrollment = studentData['enrollment_number']?.toString().trim().toUpperCase();
            var existingStudent = workshop.enrolledStudents.where(
              (s) =>
                  (enrollment != null && s.enrollmentNumber.trim().toUpperCase() == enrollment) ||
                  s.id == sId,
            ).firstOrNull;

            if (existingStudent == null && enrollment != null && enrollment.isNotEmpty) {
              existingStudent = Student(
                id: sId ?? 'std_${_uuid.v4().substring(0, 8)}',
                fullName: (studentData['full_name'] ?? 'Alumno').toString().trim(),
                enrollmentNumber: enrollment,
                email: (studentData['email'] ?? '$enrollment@alumno.edu').toString().trim(),
              );
              workshop.enrolledStudents.add(existingStudent);
            } else if (existingStudent != null && studentData['full_name'] != null) {
              final cloudName = studentData['full_name'].toString().trim();
              if (cloudName.isNotEmpty && existingStudent.fullName == 'Alumno') {
                final idx = workshop.enrolledStudents.indexOf(existingStudent);
                existingStudent = Student(
                  id: existingStudent.id,
                  fullName: cloudName,
                  enrollmentNumber: existingStudent.enrollmentNumber,
                  email: existingStudent.email,
                );
                workshop.enrolledStudents[idx] = existingStudent;
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
              checkIn = DateTime.tryParse(item['check_in_time'].toString())?.toLocal();
            }
            if (item['check_out_time'] != null) {
              checkOut = DateTime.tryParse(item['check_out_time'].toString())?.toLocal();
            }

            final prevRec = session.records[sId];
            final rec = AttendanceRecord(
              id: item['id']?.toString() ?? prevRec?.id ?? 'rec_${_uuid.v4().substring(0, 8)}',
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

            // Calcular si entró con retraso respecto al inicio del pase si aún no estaba calculado
            if (!rec.isLate && rec.checkInTime != null && session.phaseStartedAt != null) {
              final diffMins = rec.checkInTime!.difference(session.phaseStartedAt!).inMinutes;
              if (diffMins > session.toleranceMinutes) {
                rec.isLate = true;
                rec.lateMinutes = diffMins;
              }
            }

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

  void _pushWorkshopToSupabaseAsync(Workshop workshop) {
    if (kIsWeb) return;
    try {
      HttpClient()
          .postUrl(Uri.parse('https://qukqvrowgzdkqoccbfdb.supabase.co/rest/v1/workshops?on_conflict=id'))
          .then((req) {
            req.headers.set('apikey', 'sb_publishable_A-jiTpI9-hoDwOaln0_BWw_omLvRnRN');
            req.headers.set('Authorization', 'Bearer sb_publishable_A-jiTpI9-hoDwOaln0_BWw_omLvRnRN');
            req.headers.set('Content-Type', 'application/json');
            req.headers.set('Prefer', 'resolution=merge-duplicates');
            req.write(jsonEncode({
              'id': workshop.id,
              'name': workshop.name,
              'code': workshop.code,
              'instructor_name': workshop.instructorName,
              'description': workshop.description,
            }));
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
          .postUrl(Uri.parse('https://qukqvrowgzdkqoccbfdb.supabase.co/rest/v1/workshop_sessions?on_conflict=id'))
          .then((req) {
            req.headers.set('apikey', 'sb_publishable_A-jiTpI9-hoDwOaln0_BWw_omLvRnRN');
            req.headers.set('Authorization', 'Bearer sb_publishable_A-jiTpI9-hoDwOaln0_BWw_omLvRnRN');
            req.headers.set('Content-Type', 'application/json');
            req.headers.set('Prefer', 'resolution=merge-duplicates');
            req.write(jsonEncode({
              'id': session.id,
              'workshop_id': workshop.id,
              'title': session.title,
              'current_phase': session.currentPhase.name,
              'is_active': session.isQrActive,
            }));
            return req.close();
          })
          .then((res) => res.drain())
          .catchError((_) {});
    } catch (_) {}
  }

  void _pushStudentToSupabaseAsync(Student student, String workshopId) {
    if (kIsWeb) return;
    try {
      HttpClient()
          .postUrl(Uri.parse('https://qukqvrowgzdkqoccbfdb.supabase.co/rest/v1/students?on_conflict=id'))
          .then((req) {
            req.headers.set('apikey', 'sb_publishable_A-jiTpI9-hoDwOaln0_BWw_omLvRnRN');
            req.headers.set('Authorization', 'Bearer sb_publishable_A-jiTpI9-hoDwOaln0_BWw_omLvRnRN');
            req.headers.set('Content-Type', 'application/json');
            req.headers.set('Prefer', 'resolution=merge-duplicates');
            req.write(jsonEncode({
              'id': student.id,
              'workshop_id': workshopId,
              'enrollment_number': student.enrollmentNumber.toUpperCase(),
              'full_name': student.fullName,
              'email': student.email,
            }));
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
        Uri.parse('https://qukqvrowgzdkqoccbfdb.supabase.co/rest/v1/attendance_records?on_conflict=id'),
      );
      req.headers.set('apikey', 'sb_publishable_A-jiTpI9-hoDwOaln0_BWw_omLvRnRN');
      req.headers.set('Authorization', 'Bearer sb_publishable_A-jiTpI9-hoDwOaln0_BWw_omLvRnRN');
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
