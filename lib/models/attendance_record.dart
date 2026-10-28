import 'dart:convert';

enum AttendanceStatus {
  accredited,        // Entrada y Salida registradas -> ACREDITADO
  incompleteEntryOnly,// Solo Entrada -> INCOMPLETO
  incompleteExitOnly, // Solo Salida -> INCOMPLETO
  absent             // Ninguna -> INASISTENCIA
}

class AttendanceRecord {
  final String id;
  final String studentId;
  final String sessionId;
  DateTime? checkInTime;
  DateTime? checkOutTime;
  bool isLocked; // 🔒 Si está sellado, ningún usuario ni docente puede modificar la hora
  String? notes;

  AttendanceRecord({
    required this.id,
    required this.studentId,
    required this.sessionId,
    this.checkInTime,
    this.checkOutTime,
    this.isLocked = false,
    this.notes,
  });

  bool get hasCheckIn => checkInTime != null;
  bool get hasCheckOut => checkOutTime != null;

  /// Sellar hora de Entrada (Regla: Inmutable una vez colocada)
  bool sealCheckIn(DateTime time) {
    if (hasCheckIn) {
      // Ya fue sellada previamente, se rechaza cualquier modificación
      return false;
    }
    checkInTime = time;
    isLocked = true;
    return true;
  }

  /// Sellar hora de Salida (Regla: Inmutable una vez colocada)
  bool sealCheckOut(DateTime time) {
    if (hasCheckOut) {
      // Ya fue sellada previamente, se rechaza cualquier modificación
      return false;
    }
    checkOutTime = time;
    isLocked = true;
    return true;
  }

  AttendanceStatus get status {
    if (hasCheckIn && hasCheckOut) {
      return AttendanceStatus.accredited;
    } else if (hasCheckIn && !hasCheckOut) {
      return AttendanceStatus.incompleteEntryOnly;
    } else if (!hasCheckIn && hasCheckOut) {
      return AttendanceStatus.incompleteExitOnly;
    } else {
      return AttendanceStatus.absent;
    }
  }

  String get statusLabel {
    switch (status) {
      case AttendanceStatus.accredited:
        return 'Acreditado';
      case AttendanceStatus.incompleteEntryOnly:
        return 'Incompleto (Falta Salida)';
      case AttendanceStatus.incompleteExitOnly:
        return 'Incompleto (Falta Entrada)';
      case AttendanceStatus.absent:
        return 'Inasistencia';
    }
  }

  bool get isAccredited => status == AttendanceStatus.accredited;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'studentId': studentId,
      'sessionId': sessionId,
      'checkInTime': checkInTime?.toIso8601String(),
      'checkOutTime': checkOutTime?.toIso8601String(),
      'isLocked': isLocked ? 1 : 0,
      'notes': notes,
    };
  }

  factory AttendanceRecord.fromMap(Map<String, dynamic> map) {
    return AttendanceRecord(
      id: map['id'] ?? '',
      studentId: map['studentId'] ?? '',
      sessionId: map['sessionId'] ?? '',
      checkInTime: map['checkInTime'] != null ? DateTime.parse(map['checkInTime']) : null,
      checkOutTime: map['checkOutTime'] != null ? DateTime.parse(map['checkOutTime']) : null,
      isLocked: (map['isLocked'] == 1 || map['isLocked'] == true),
      notes: map['notes'],
    );
  }

  String toJson() => json.encode(toMap());
  factory AttendanceRecord.fromJson(String source) => AttendanceRecord.fromMap(json.decode(source));
}
