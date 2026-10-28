import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:asistencia_taller/models/attendance_record.dart';
import 'package:asistencia_taller/models/session.dart';
import 'package:asistencia_taller/services/qr_service.dart';
import 'package:asistencia_taller/providers/attendance_provider.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  group('Reglas de Negocio de Acreditación (Doble Check)', () {
    test('Estudiante con Entrada y Salida -> ACREDITADO', () {
      final record = AttendanceRecord(
        id: 'rec_1',
        studentId: 'std_1',
        sessionId: 'ses_1',
        checkInTime: DateTime(2026, 10, 26, 8, 0, 0),
        checkOutTime: DateTime(2026, 10, 26, 12, 0, 0),
      );

      expect(record.status, AttendanceStatus.accredited);
      expect(record.isAccredited, isTrue);
      expect(record.statusLabel, 'Acreditado');
    });

    test('Estudiante con SOLO Entrada -> INCOMPLETO (No Acreditado)', () {
      final record = AttendanceRecord(
        id: 'rec_2',
        studentId: 'std_2',
        sessionId: 'ses_1',
        checkInTime: DateTime(2026, 10, 26, 8, 5, 0),
        checkOutTime: null,
      );

      expect(record.status, AttendanceStatus.incompleteEntryOnly);
      expect(record.isAccredited, isFalse);
      expect(record.statusLabel, 'Incompleto (Falta Salida)');
    });

    test('Estudiante con SOLO Salida -> INCOMPLETO (No Acreditado)', () {
      final record = AttendanceRecord(
        id: 'rec_3',
        studentId: 'std_3',
        sessionId: 'ses_1',
        checkInTime: null,
        checkOutTime: DateTime(2026, 10, 26, 12, 1, 0),
      );

      expect(record.status, AttendanceStatus.incompleteExitOnly);
      expect(record.isAccredited, isFalse);
      expect(record.statusLabel, 'Incompleto (Falta Entrada)');
    });

    test('Estudiante sin ningún registro -> INASISTENCIA', () {
      final record = AttendanceRecord(
        id: 'rec_4',
        studentId: 'std_4',
        sessionId: 'ses_1',
      );

      expect(record.status, AttendanceStatus.absent);
      expect(record.isAccredited, isFalse);
      expect(record.statusLabel, 'Inasistencia');
    });
  });

  group('Inmutabilidad de Horas y Sellado Anticonflicto (PowerSync / SQLite)', () {
    test('Sellar Entrada fija la hora e impide cualquier sobreescritura posterior', () {
      final record = AttendanceRecord(
        id: 'rec_lock_1',
        studentId: 'std_1',
        sessionId: 'ses_1',
      );

      final officialTime = DateTime(2026, 10, 26, 8, 2, 15);
      final firstSeal = record.sealCheckIn(officialTime);

      expect(firstSeal, isTrue);
      expect(record.checkInTime, officialTime);
      expect(record.isLocked, isTrue);

      // Intento fraudulento o accidental de alterar la hora después
      final tamperedTime = DateTime(2026, 10, 26, 8, 0, 0);
      final secondSeal = record.sealCheckIn(tamperedTime);

      // Debe ser RECHAZADO y conservar la hora original oficial
      expect(secondSeal, isFalse);
      expect(record.checkInTime, officialTime);
    });

    test('Sellar Salida fija la hora e impide alteraciones posteriores', () {
      final record = AttendanceRecord(
        id: 'rec_lock_2',
        studentId: 'std_1',
        sessionId: 'ses_1',
        checkInTime: DateTime(2026, 10, 26, 8, 0, 0),
      );

      final officialExit = DateTime(2026, 10, 26, 12, 0, 30);
      final firstSeal = record.sealCheckOut(officialExit);

      expect(firstSeal, isTrue);
      expect(record.checkOutTime, officialExit);
      expect(record.isLocked, isTrue);

      // Intento de reescribir la hora de salida
      final tamperedExit = DateTime(2026, 10, 26, 13, 0, 0);
      final secondSeal = record.sealCheckOut(tamperedExit);

      expect(secondSeal, isFalse);
      expect(record.checkOutTime, officialExit);
    });
  });

  group('Seguridad Antifraude de Códigos QR Dinámicos', () {
    final session = WorkshopSession(
      id: 'ses_test',
      workshopId: 'ws_test',
      title: 'Sesión de Prueba Antifraude',
      date: DateTime.now(),
      currentPhase: SessionPhase.entry,
      secretKey: 'CLAVE_SECRETA_TEST',
    );

    test('QR generado en tiempo real es VÁLIDO', () {
      final qrString = QrService.generateDynamicQrData(
        sessionId: session.id,
        workshopId: session.workshopId,
        phase: SessionPhase.entry,
        secretKey: session.secretKey,
      );

      final result = QrService.validateQrData(
        qrRawContent: qrString,
        currentSession: session,
      );

      expect(result.isValid, isTrue);
      expect(result.sessionId, session.id);
      expect(result.phase, SessionPhase.entry);
    });

    test('QR tomado de una foto de hace más de 30 segundos es RECHAZADO', () {
      final oldTime = DateTime.now().subtract(const Duration(seconds: 45));
      final oldQrString = QrService.generateDynamicQrData(
        sessionId: session.id,
        workshopId: session.workshopId,
        phase: SessionPhase.entry,
        secretKey: session.secretKey,
        now: oldTime,
      );

      final result = QrService.validateQrData(
        qrRawContent: oldQrString,
        currentSession: session,
      );

      expect(result.isValid, isFalse);
      expect(result.errorMessage, contains('EXPIRADO'));
    });

    test('QR con firma adulterada es RECHAZADO', () {
      final tamperedQr = '{"s":"ses_test","w":"ws_test","p":"entry","t":${QrService.getCurrentWindow()},"sig":"FIRMA_FALSA"}';

      final result = QrService.validateQrData(
        qrRawContent: tamperedQr,
        currentSession: session,
      );

      expect(result.isValid, isFalse);
      expect(result.errorMessage, contains('inválida'));
    });

    test('QR de Entrada es RECHAZADO si el docente ya cambió a Salida', () {
      final qrEntry = QrService.generateDynamicQrData(
        sessionId: session.id,
        workshopId: session.workshopId,
        phase: SessionPhase.entry,
        secretKey: session.secretKey,
      );

      // El docente cambia a fase de salida
      session.currentPhase = SessionPhase.exit;

      final result = QrService.validateQrData(
        qrRawContent: qrEntry,
        currentSession: session,
      );

      expect(result.isValid, isFalse);
      expect(result.errorMessage, contains('pertenece a la fase'));
    });
  });

  group('Envío de Asistencia con Número de Control desde el Celular', () {
    test('Alumno escanea QR y envía su Número de Control con auto-inscripción', () async {
      final provider = AttendanceProvider();
      await provider.addWorkshop(
        name: 'Taller de Pavimentación',
        code: 'PAV-01',
        instructorName: 'Ing. Carlos Méndez',
        description: 'Práctica vial',
      );

      final workshop = provider.workshops.first;
      final session = await provider.createSession(
        workshopId: workshop.id,
        title: 'Sesión 1: Práctica',
        date: DateTime.now(),
      );

      // Docente habilita Entrada
      await provider.updateSessionPhase(
        workshopId: workshop.id,
        sessionId: session!.id,
        newPhase: SessionPhase.entry,
      );

      // Alumno escanea QR y envía su número de control y nombre desde su celular
      final qrContent = QrService.generateDynamicQrData(
        sessionId: session.id,
        workshopId: workshop.id,
        phase: SessionPhase.entry,
        secretKey: session.secretKey,
      );

      final result = provider.processQrScan(
        qrRawContent: qrContent,
        studentEnrollmentNumber: '21010482',
        studentFullName: 'Juan Pérez',
      );

      expect(result.success, isTrue);
      expect(result.student?.enrollmentNumber, '21010482');
      expect(result.student?.fullName, 'Juan Pérez');
      expect(session.records[result.student!.id]?.hasCheckIn, isTrue);
      expect(session.records[result.student!.id]?.isLocked, isTrue);
    });

    test('Opción 1: QR con URL Web completa es decodificado y validado con éxito', () async {
      final session = WorkshopSession(
        id: 'ses_url_test',
        workshopId: 'ws_test',
        title: 'Sesión Web URL',
        date: DateTime.now(),
        currentPhase: SessionPhase.entry,
        secretKey: 'CLAVE_SECRETA_URL',
      );

      // Generar QR con URL web para cámara nativa del celular
      const webDomain = 'https://asistencia-taller.web.app';
      final qrWebUrl = QrService.generateDynamicQrData(
        sessionId: session.id,
        workshopId: session.workshopId,
        phase: SessionPhase.entry,
        secretKey: session.secretKey,
        webBaseUrl: webDomain,
      );

      expect(qrWebUrl, startsWith('https://asistencia-taller.web.app?qr='));

      // Validar que QrService extraiga correctamente la carga útil desde la URL
      final validation = QrService.validateQrData(
        qrRawContent: qrWebUrl,
        currentSession: session,
      );

      expect(validation.isValid, isTrue);
      expect(validation.sessionId, session.id);
      expect(validation.phase, SessionPhase.entry);
    });

    test('Flujo Automático sin re-registro: Entrada con formulario inicial y Salida automática acreditada', () async {
      final provider = AttendanceProvider();
      await provider.addWorkshop(
        name: 'Taller de Pavimentación',
        code: 'PAV-01',
        instructorName: 'Ing. Carlos Méndez',
        description: 'Práctica vial',
      );

      final workshop = provider.workshops.first;
      final session = await provider.createSession(
        workshopId: workshop.id,
        title: 'Sesión Completa',
        date: DateTime.now(),
      );

      // 1. Docente habilita Entrada
      await provider.updateSessionPhase(
        workshopId: workshop.id,
        sessionId: session!.id,
        newPhase: SessionPhase.entry,
      );

      // Alumno escanea por primera vez: llena datos y se guarda en SharedPreferences del celular
      final prefs = await SharedPreferences.getInstance();
      const studentControl = '21010482';
      const studentName = 'Juan Pérez';
      await prefs.setString('student_saved_control_number', studentControl);
      await prefs.setString('student_saved_full_name', studentName);

      final qrEntry = QrService.generateDynamicQrData(
        sessionId: session.id,
        workshopId: workshop.id,
        phase: SessionPhase.entry,
        secretKey: session.secretKey,
        webBaseUrl: 'https://asistencia.app',
      );

      final entryResult = provider.processQrScan(
        qrRawContent: qrEntry,
        studentEnrollmentNumber: prefs.getString('student_saved_control_number')!,
        studentFullName: prefs.getString('student_saved_full_name')!,
      );

      expect(entryResult.success, isTrue);
      expect(session.records[entryResult.student!.id]?.hasCheckIn, isTrue);
      expect(session.records[entryResult.student!.id]?.hasCheckOut, isFalse);
      expect(session.records[entryResult.student!.id]?.status, AttendanceStatus.incompleteEntryOnly);

      // 2. Al final de la clase, docente habilita Salida
      await provider.updateSessionPhase(
        workshopId: workshop.id,
        sessionId: session.id,
        newPhase: SessionPhase.exit,
      );

      // Alumno vuelve a escanear el QR: el celular lee los datos guardados automáticamente (SIN formulario)
      final savedControl = prefs.getString('student_saved_control_number')!;
      final savedName = prefs.getString('student_saved_full_name')!;

      final qrExit = QrService.generateDynamicQrData(
        sessionId: session.id,
        workshopId: workshop.id,
        phase: SessionPhase.exit,
        secretKey: session.secretKey,
        webBaseUrl: 'https://asistencia.app',
      );

      final exitResult = provider.processQrScan(
        qrRawContent: qrExit,
        studentEnrollmentNumber: savedControl,
        studentFullName: savedName,
      );

      // Debe quedar ACREDITADO 100% con ambas horas selladas inmutables
      expect(exitResult.success, isTrue);
      expect(exitResult.status, AttendanceStatus.accredited);
      expect(session.records[exitResult.student!.id]?.hasCheckIn, isTrue);
      expect(session.records[exitResult.student!.id]?.hasCheckOut, isTrue);
      expect(session.records[exitResult.student!.id]?.isAccredited, isTrue);
      expect(session.records[exitResult.student!.id]?.isLocked, isTrue);
    });
  });
}
