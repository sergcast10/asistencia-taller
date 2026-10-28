import 'dart:convert';

class Student {
  final String id;
  final String enrollmentNumber; // Matrícula / DNI / Código
  final String fullName;
  final String email;

  Student({
    required this.id,
    required this.enrollmentNumber,
    required this.fullName,
    required this.email,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'enrollmentNumber': enrollmentNumber,
      'fullName': fullName,
      'email': email,
    };
  }

  factory Student.fromMap(Map<String, dynamic> map) {
    return Student(
      id: map['id'] ?? '',
      enrollmentNumber: map['enrollmentNumber'] ?? '',
      fullName: map['fullName'] ?? '',
      email: map['email'] ?? '',
    );
  }

  String toJson() => json.encode(toMap());
  factory Student.fromJson(String source) => Student.fromMap(json.decode(source));
}
