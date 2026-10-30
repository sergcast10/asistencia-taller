import 'dart:convert';

class Student {
  final String id;
  final String enrollmentNumber; // Matrícula / DNI / Código
  String fullName;
  String email;
  bool isSuspended; // 🚫 Indica si el alumno fue suspendido por conducta inapropiada
  String? suspensionReason; // Motivo o comportamiento reportado por el docente encargado
  DateTime? suspendedAt;
  String? boundDeviceId; // 📱 ID del celular actualmente vinculado al alumno
  String? previousDeviceId; // 🗑️ ID del celular viejo que fue borrado/reemplazado
  bool allowNewDevice; // 🔄 Autorización activa del docente para que el nuevo celular tome el lugar del viejo
  DateTime? deviceUpdatedAt;

  Student({
    required this.id,
    required this.enrollmentNumber,
    required this.fullName,
    required this.email,
    this.isSuspended = false,
    this.suspensionReason,
    this.suspendedAt,
    this.boundDeviceId,
    this.previousDeviceId,
    this.allowNewDevice = false,
    this.deviceUpdatedAt,
  });

  /// Codifica el correo junto con la vinculación del celular para sincronizar con Supabase sin alterar columnas SQL
  String encodeSupabaseEmail() {
    final cleanMail = email.split('||').first.trim();
    final parts = <String>[cleanMail];
    if (boundDeviceId != null && boundDeviceId!.trim().isNotEmpty) {
      parts.add('DEV:${boundDeviceId!.trim()}');
    }
    if (previousDeviceId != null && previousDeviceId!.trim().isNotEmpty) {
      parts.add('OLD_DEV:${previousDeviceId!.trim()}');
    }
    if (allowNewDevice) {
      parts.add('ALLOW_NEW_DEV:1');
    }
    return parts.join('||');
  }

  /// Aplica metadatos de dispositivo codificados desde el campo email de Supabase
  void applySupabaseEmailMeta(String? rawEmail) {
    if (rawEmail == null || rawEmail.isEmpty) return;
    if (!rawEmail.contains('||')) return;
    final segments = rawEmail.split('||');
    for (final seg in segments.skip(1)) {
      if (seg.startsWith('DEV:')) {
        final dev = seg.substring(4).trim();
        if (dev.isNotEmpty) {
          boundDeviceId = dev;
          allowNewDevice = false;
        }
      } else if (seg.startsWith('OLD_DEV:')) {
        final oldDev = seg.substring(8).trim();
        if (oldDev.isNotEmpty) {
          previousDeviceId = oldDev;
        }
      } else if (seg.startsWith('ALLOW_NEW_DEV:')) {
        final val = seg.substring(14).trim();
        if (val == '1' || val == 'true') {
          allowNewDevice = true;
          boundDeviceId = null;
        }
      }
    }
  }

  static String extractCleanEmail(String? rawEmail, String fallbackEnrollment) {
    if (rawEmail == null || rawEmail.trim().isEmpty) {
      return '${fallbackEnrollment.toLowerCase()}@alumno.edu';
    }
    final clean = rawEmail.split('||').first.trim();
    return clean.isNotEmpty
        ? clean
        : '${fallbackEnrollment.toLowerCase()}@alumno.edu';
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'enrollmentNumber': enrollmentNumber,
      'fullName': fullName,
      'email': email.split('||').first.trim(),
      'isSuspended': isSuspended,
      'suspensionReason': suspensionReason,
      'suspendedAt': suspendedAt?.toIso8601String(),
      'boundDeviceId': boundDeviceId,
      'previousDeviceId': previousDeviceId,
      'allowNewDevice': allowNewDevice,
      'deviceUpdatedAt': deviceUpdatedAt?.toIso8601String(),
    };
  }

  factory Student.fromMap(Map<String, dynamic> map) {
    final rawEmail = map['email']?.toString() ?? '';
    final enrollment = map['enrollmentNumber']?.toString() ?? '';
    final student = Student(
      id: map['id'] ?? '',
      enrollmentNumber: enrollment,
      fullName: map['fullName'] ?? '',
      email: extractCleanEmail(rawEmail, enrollment),
      isSuspended: map['isSuspended'] == true || map['isSuspended'] == 1,
      suspensionReason: map['suspensionReason'],
      suspendedAt: map['suspendedAt'] != null
          ? DateTime.tryParse(map['suspendedAt'].toString())
          : null,
      boundDeviceId: map['boundDeviceId']?.toString(),
      previousDeviceId: map['previousDeviceId']?.toString(),
      allowNewDevice:
          map['allowNewDevice'] == true || map['allowNewDevice'] == 1,
      deviceUpdatedAt: map['deviceUpdatedAt'] != null
          ? DateTime.tryParse(map['deviceUpdatedAt'].toString())
          : null,
    );
    student.applySupabaseEmailMeta(rawEmail);
    return student;
  }

  String toJson() => json.encode(toMap());
  factory Student.fromJson(String source) => Student.fromMap(json.decode(source));
}
