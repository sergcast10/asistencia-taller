import 'dart:convert';
import 'attendance_record.dart';

enum SessionPhase {
  pending,    // Aún no inicia
  entry,      // Docente activó PASE DE ENTRADA (QR dinámico activo)
  inProgress, // Clase en curso (QR inactivo para evitar trampas)
  exit,       // Docente activó PASE DE SALIDA (QR dinámico activo)
  finished    // Sesión finalizada y consolidada
}

class WorkshopSession {
  final String id;
  final String workshopId;
  String title;
  DateTime date;
  String impartedDaysLabel; // Evidencia de la(s) fecha(s) de los días en que se impartirá la sesión
  String startTimeLabel; // Hora programada/establecida de inicio (ej. "09:00")
  String endTimeLabel;   // Hora programada/establecida de término (ej. "11:00")
  DateTime? actualStartedAt; // Evidencia exacta de cuándo comenzó la sesión
  DateTime? actualEndedAt;   // Evidencia exacta de a qué hora terminó la sesión
  SessionPhase currentPhase;
  DateTime? phaseStartedAt;
  final String secretKey;
  int toleranceMinutes; // Minutos de tolerancia puntual (ej. 15 min)
  int registrationWindowMinutes; // Tiempo límite total para registrarse (ej. 45 min)
  Map<String, AttendanceRecord> records; // studentId -> AttendanceRecord

  WorkshopSession({
    required this.id,
    required this.workshopId,
    required this.title,
    required this.date,
    String? impartedDaysLabel,
    String? startTimeLabel,
    String? endTimeLabel,
    this.actualStartedAt,
    this.actualEndedAt,
    this.currentPhase = SessionPhase.pending,
    this.phaseStartedAt,
    required this.secretKey,
    this.toleranceMinutes = 15,
    this.registrationWindowMinutes = 45,
    Map<String, AttendanceRecord>? records,
  }) : impartedDaysLabel = (impartedDaysLabel != null && impartedDaysLabel.trim().isNotEmpty)
           ? impartedDaysLabel.trim()
           : formatSingleDateWithDay(date),
       startTimeLabel = (startTimeLabel != null && startTimeLabel.trim().isNotEmpty)
           ? startTimeLabel.trim()
           : _defaultStartFromDate(date),
       endTimeLabel = (endTimeLabel != null && endTimeLabel.trim().isNotEmpty)
           ? endTimeLabel.trim()
           : _defaultEndFromDate(date),
       records = records ?? {};

  static String _defaultStartFromDate(DateTime d) {
    final l = d.toLocal();
    return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }

  static String _defaultEndFromDate(DateTime d) {
    final l = d.toLocal().add(const Duration(hours: 2));
    return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }

  static const List<String> dayNames = [
    'Lunes',
    'Martes',
    'Miércoles',
    'Jueves',
    'Viernes',
    'Sábado',
    'Domingo',
  ];

  static String formatSingleDateWithDay(DateTime dt) {
    final l = dt.toLocal();
    final dayName = dayNames[(l.weekday - 1).clamp(0, 6)];
    return '$dayName ${l.day.toString().padLeft(2, '0')}/${l.month.toString().padLeft(2, '0')}/${l.year}';
  }

  /// Devuelve las fechas de los días en que se impartirá la sesión (ej. "Miércoles 28/10/2026, Jueves 29/10/2026")
  String get formattedDateWithDay {
    if (impartedDaysLabel.trim().isNotEmpty) {
      return impartedDaysLabel.trim();
    }
    return formatSingleDateWithDay(date);
  }

  /// Fecha corta DD/MM/YYYY
  String get formattedShortDate {
    final l = date.toLocal();
    return '${l.day.toString().padLeft(2, '0')}/${l.month.toString().padLeft(2, '0')}/${l.year}';
  }

  /// Horario de inicio y término (ej. "09:00 hrs a 11:00 hrs")
  String get scheduleRangeLabel => '$startTimeLabel hrs a $endTimeLabel hrs';

  /// Evidencia detallada de cuándo comenzó y a qué hora terminó
  String get executionEvidenceSummary {
    String fmtTime(DateTime dt) {
      final l = dt.toLocal();
      return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}:${l.second.toString().padLeft(2, '0')}';
    }

    final startStr = actualStartedAt != null
        ? '${fmtTime(actualStartedAt!)} hrs (Sellado)'
        : '$startTimeLabel hrs (Programado)';
    final endStr = actualEndedAt != null
        ? '${fmtTime(actualEndedAt!)} hrs (Concluido)'
        : '$endTimeLabel hrs (Término previsto)';
    return 'Inicio: $startStr • Término: $endStr';
  }

  /// Minutos transcurridos desde que el docente activó la fase actual
  int get elapsedMinutes {
    if (phaseStartedAt == null) return 0;
    final diff = DateTime.now().difference(phaseStartedAt!).inMinutes;
    return diff < 0 ? 0 : diff;
  }

  /// Segundos restantes de tolerancia puntual
  int get remainingToleranceSeconds {
    if (phaseStartedAt == null) return toleranceMinutes * 60;
    final elapsedSec = DateTime.now().difference(phaseStartedAt!).inSeconds;
    final rem = (toleranceMinutes * 60) - elapsedSec;
    return rem > 0 ? rem : 0;
  }

  /// Segundos restantes antes de que cierre la ventana de registro
  int get remainingWindowSeconds {
    if (phaseStartedAt == null) return registrationWindowMinutes * 60;
    final elapsedSec = DateTime.now().difference(phaseStartedAt!).inSeconds;
    final rem = (registrationWindowMinutes * 60) - elapsedSec;
    return rem > 0 ? rem : 0;
  }

  /// Indica si ya pasaron los minutos de tolerancia puntual
  bool get isPastTolerance =>
      phaseStartedAt != null && remainingToleranceSeconds <= 0;

  /// Indica si ya se agotó el tiempo total de registro configurado por el docente
  bool get isRegistrationWindowExpired =>
      phaseStartedAt != null &&
      registrationWindowMinutes > 0 &&
      remainingWindowSeconds <= 0;

  String get phaseLabel {
    switch (currentPhase) {
      case SessionPhase.pending:
        return 'Pendiente de inicio';
      case SessionPhase.entry:
        return '🟢 Pase de Entrada Activo';
      case SessionPhase.inProgress:
        return '🟡 Taller en Desarrollo';
      case SessionPhase.exit:
        return '🔵 Pase de Salida Activo';
      case SessionPhase.finished:
        return '🏁 Sesión Concluida';
    }
  }

  bool get isQrActive => currentPhase == SessionPhase.entry || currentPhase == SessionPhase.exit;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'workshopId': workshopId,
      'title': title,
      'date': date.toIso8601String(),
      'impartedDaysLabel': impartedDaysLabel,
      'startTimeLabel': startTimeLabel,
      'endTimeLabel': endTimeLabel,
      'actualStartedAt': actualStartedAt?.toIso8601String(),
      'actualEndedAt': actualEndedAt?.toIso8601String(),
      'currentPhase': currentPhase.name,
      'phaseStartedAt': phaseStartedAt?.toIso8601String(),
      'secretKey': secretKey,
      'toleranceMinutes': toleranceMinutes,
      'registrationWindowMinutes': registrationWindowMinutes,
      'records': records.map((key, value) => MapEntry(key, value.toMap())),
    };
  }

  factory WorkshopSession.fromMap(Map<String, dynamic> map) {
    var rawRecords = map['records'] as Map<String, dynamic>? ?? {};
    Map<String, AttendanceRecord> parsedRecords = {};
    rawRecords.forEach((k, v) {
      parsedRecords[k] = AttendanceRecord.fromMap(Map<String, dynamic>.from(v));
    });

    final parsedDate = map['date'] != null ? DateTime.parse(map['date']) : DateTime.now();

    return WorkshopSession(
      id: map['id'] ?? '',
      workshopId: map['workshopId'] ?? '',
      title: map['title'] ?? '',
      date: parsedDate,
      impartedDaysLabel: map['impartedDaysLabel']?.toString(),
      startTimeLabel: map['startTimeLabel']?.toString(),
      endTimeLabel: map['endTimeLabel']?.toString(),
      actualStartedAt: map['actualStartedAt'] != null
          ? DateTime.tryParse(map['actualStartedAt'].toString())
          : null,
      actualEndedAt: map['actualEndedAt'] != null
          ? DateTime.tryParse(map['actualEndedAt'].toString())
          : null,
      currentPhase: SessionPhase.values.firstWhere(
        (e) => e.name == map['currentPhase'],
        orElse: () => SessionPhase.pending,
      ),
      phaseStartedAt: map['phaseStartedAt'] != null ? DateTime.parse(map['phaseStartedAt']) : null,
      secretKey: map['secretKey'] ?? 'SECRET_DEFAULT',
      toleranceMinutes: map['toleranceMinutes'] is int ? map['toleranceMinutes'] : 15,
      registrationWindowMinutes: map['registrationWindowMinutes'] is int ? map['registrationWindowMinutes'] : 45,
      records: parsedRecords,
    );
  }

  String toJson() => json.encode(toMap());
  factory WorkshopSession.fromJson(String source) => WorkshopSession.fromMap(json.decode(source));
}
