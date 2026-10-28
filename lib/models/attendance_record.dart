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
  String? notes; // 📝 Nota o evidencia de situación tomada por el docente o alumno
  bool isLate; // ⏱️ Indica si registró entrada con retraso
  int lateMinutes; // Minutos de retraso respecto al inicio del pase

  AttendanceRecord({
    required this.id,
    required this.studentId,
    required this.sessionId,
    this.checkInTime,
    this.checkOutTime,
    this.isLocked = false,
    this.notes,
    this.isLate = false,
    this.lateMinutes = 0,
  });

  bool get hasCheckIn => checkInTime != null;
  bool get hasCheckOut => checkOutTime != null;
  bool get hasNotes => notes != null && notes!.trim().isNotEmpty;

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

  /// Codifica estatus + retardo + nota de evidencia en el campo status de Supabase
  String encodeSupabaseStatus() {
    final parts = <String>[status.name];
    if (isLate || lateMinutes > 0) {
      parts.add('LATE:$lateMinutes');
    }
    if (hasNotes) {
      final cleanNote = notes!.replaceAll('||', ' - ').trim();
      parts.add('NOTE:$cleanNote');
    }
    return parts.join('||');
  }

  /// Decodifica estatus, retardo y nota de evidencia provenientes de Supabase
  void applySupabaseStatus(String? rawStatus, {String? explicitNotes}) {
    if (explicitNotes != null && explicitNotes.trim().isNotEmpty) {
      notes = explicitNotes.trim();
    }
    if (rawStatus == null || rawStatus.isEmpty) return;

    final segments = rawStatus.split('||');
    final baseStatus = segments.first.trim();

    for (final seg in segments.skip(1)) {
      if (seg.startsWith('LATE:')) {
        final mins = int.tryParse(seg.substring(5).trim()) ?? 0;
        lateMinutes = mins;
        isLate = mins > 0;
      } else if (seg.startsWith('NOTE:')) {
        final noteText = seg.substring(5).trim();
        if (noteText.isNotEmpty) {
          notes = noteText;
        }
      }
    }

    // Si en la nube fue marcado como accredited pero solo tenía checkIn, sincronizar checkOut
    if (baseStatus == 'accredited' && checkInTime != null && checkOutTime == null) {
      checkOutTime = checkInTime;
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'studentId': studentId,
      'sessionId': sessionId,
      'checkInTime': checkInTime?.toIso8601String(),
      'checkOutTime': checkOutTime?.toIso8601String(),
      'isLocked': isLocked ? 1 : 0,
      'notes': notes,
      'isLate': isLate,
      'lateMinutes': lateMinutes,
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
      isLate: map['isLate'] == true || map['isLate'] == 1,
      lateMinutes: map['lateMinutes'] is int ? map['lateMinutes'] : 0,
    );
  }

  String toJson() => json.encode(toMap());
  factory AttendanceRecord.fromJson(String source) => AttendanceRecord.fromMap(json.decode(source));
}
