import 'dart:convert';
import 'student.dart';
import 'session.dart';

class Workshop {
  final String id;
  final String name;
  final String code;
  final String instructorName;
  final String description;
  final List<Student> enrolledStudents;
  final List<WorkshopSession> sessions;

  Workshop({
    required this.id,
    required this.name,
    required this.code,
    required this.instructorName,
    required this.description,
    List<Student>? enrolledStudents,
    List<WorkshopSession>? sessions,
  })  : enrolledStudents = enrolledStudents ?? [],
        sessions = sessions ?? [];

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'code': code,
      'instructorName': instructorName,
      'description': description,
      'enrolledStudents': enrolledStudents.map((s) => s.toMap()).toList(),
      'sessions': sessions.map((s) => s.toMap()).toList(),
    };
  }

  factory Workshop.fromMap(Map<String, dynamic> map) {
    return Workshop(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      code: map['code'] ?? '',
      instructorName: map['instructorName'] ?? '',
      description: map['description'] ?? '',
      enrolledStudents: (map['enrolledStudents'] as List<dynamic>? ?? [])
          .map((item) => Student.fromMap(Map<String, dynamic>.from(item)))
          .toList(),
      sessions: (map['sessions'] as List<dynamic>? ?? [])
          .map((item) => WorkshopSession.fromMap(Map<String, dynamic>.from(item)))
          .toList(),
    );
  }

  String toJson() => json.encode(toMap());
  factory Workshop.fromJson(String source) => Workshop.fromMap(json.decode(source));
}
