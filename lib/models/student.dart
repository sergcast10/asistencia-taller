import 'dart:convert';

class Student {
  final String id;
  final String enrollmentNumber; // Matrícula / DNI / Código
  final String fullName;
  final String email;
  bool isSuspended; // 🚫 Indica si el alumno fue suspendido por conducta inapropiada
  String? suspensionReason; // Motivo o comportamiento reportado por el docente encargado
  DateTime? suspendedAt;

  Student({
    required this.id,
    required this.enrollmentNumber,
    required this.fullName,
    required this.email,
    this.isSuspended = false,
    this.suspensionReason,
    this.suspendedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'enrollmentNumber': enrollmentNumber,
      'fullName': fullName,
      'email': email,
      'isSuspended': isSuspended,
      'suspensionReason': suspensionReason,
      'suspendedAt': suspendedAt?.toIso8601String(),
    };
  }

  factory Student.fromMap(Map<String, dynamic> map) {
    return Student(
      id: map['id'] ?? '',
      enrollmentNumber: map['enrollmentNumber'] ?? '',
      fullName: map['fullName'] ?? '',
      email: map['email'] ?? '',
      isSuspended: map['isSuspended'] == true || map['isSuspended'] == 1,
      suspensionReason: map['suspensionReason'],
      suspendedAt: map['suspendedAt'] != null
          ? DateTime.tryParse(map['suspendedAt'].toString())
          : null,
    );
  }

  String toJson() => json.encode(toMap());
  factory Student.fromJson(String source) => Student.fromMap(json.decode(source));
}
