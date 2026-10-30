import 'dart:convert';
import 'student.dart';
import 'session.dart';

class Workshop {
  final String id;
  String name;
  String code;
  String instructorName;
  String description;
  String eventType; // 'workshop' (Taller) o 'conference' (Conferencia / Pase Único)
  final List<Student> enrolledStudents;
  final List<WorkshopSession> sessions;

  bool get isConference => eventType == 'conference';
  String get eventTypeLabel => isConference ? 'Conferencia' : 'Taller';

  Workshop({
    required this.id,
    required this.name,
    required this.code,
    required this.instructorName,
    required this.description,
    this.eventType = 'workshop',
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
      'eventType': eventType,
      'enrolledStudents': enrolledStudents.map((s) => s.toMap()).toList(),
      'sessions': sessions.map((s) => s.toMap()).toList(),
    };
  }

  factory Workshop.fromMap(Map<String, dynamic> map) {
    final rawType = map['eventType']?.toString();
    final nameLower = (map['name']?.toString() ?? '').toLowerCase();
    final descLower = (map['description']?.toString() ?? '').toLowerCase();

    // Deducir tipo si no venía explícito pero el nombre o descripción lo señalan
    String resolvedType = 'workshop';
    if (rawType != null && rawType.isNotEmpty) {
      resolvedType = rawType;
    } else if (nameLower.contains('conferencia') ||
        nameLower.contains('ponencia') ||
        nameLower.contains('magna') ||
        descLower.contains('conferencia') ||
        descLower.contains('[tipo:conferencia]')) {
      resolvedType = 'conference';
    }

    return Workshop(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      code: map['code'] ?? '',
      instructorName: map['instructorName'] ?? '',
      description: map['description'] ?? '',
      eventType: resolvedType,
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
