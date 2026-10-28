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
  final String title;
  final DateTime date;
  SessionPhase currentPhase;
  DateTime? phaseStartedAt;
  final String secretKey;
  Map<String, AttendanceRecord> records; // studentId -> AttendanceRecord

  WorkshopSession({
    required this.id,
    required this.workshopId,
    required this.title,
    required this.date,
    this.currentPhase = SessionPhase.pending,
    this.phaseStartedAt,
    required this.secretKey,
    Map<String, AttendanceRecord>? records,
  }) : records = records ?? {};

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
        return 'Concluido';
    }
  }

  bool get isQrActive => currentPhase == SessionPhase.entry || currentPhase == SessionPhase.exit;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'workshopId': workshopId,
      'title': title,
      'date': date.toIso8601String(),
      'currentPhase': currentPhase.name,
      'phaseStartedAt': phaseStartedAt?.toIso8601String(),
      'secretKey': secretKey,
      'records': records.map((key, value) => MapEntry(key, value.toMap())),
    };
  }

  factory WorkshopSession.fromMap(Map<String, dynamic> map) {
    var rawRecords = map['records'] as Map<String, dynamic>? ?? {};
    Map<String, AttendanceRecord> parsedRecords = {};
    rawRecords.forEach((k, v) {
      parsedRecords[k] = AttendanceRecord.fromMap(Map<String, dynamic>.from(v));
    });

    return WorkshopSession(
      id: map['id'] ?? '',
      workshopId: map['workshopId'] ?? '',
      title: map['title'] ?? '',
      date: map['date'] != null ? DateTime.parse(map['date']) : DateTime.now(),
      currentPhase: SessionPhase.values.firstWhere(
        (e) => e.name == map['currentPhase'],
        orElse: () => SessionPhase.pending,
      ),
      phaseStartedAt: map['phaseStartedAt'] != null ? DateTime.parse(map['phaseStartedAt']) : null,
      secretKey: map['secretKey'] ?? 'SECRET_DEFAULT',
      records: parsedRecords,
    );
  }

  String toJson() => json.encode(toMap());
  factory WorkshopSession.fromJson(String source) => WorkshopSession.fromMap(json.decode(source));
}
