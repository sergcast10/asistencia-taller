import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/student.dart';
import '../../models/attendance_record.dart';
import '../../providers/attendance_provider.dart';
import '../../utils/app_theme.dart';
import '../../widgets/student_status_badge.dart';
import 'student_scanner_screen.dart';

class StudentPortalScreen extends StatefulWidget {
  const StudentPortalScreen({super.key});

  @override
  State<StudentPortalScreen> createState() => _StudentPortalScreenState();
}

class _StudentPortalScreenState extends State<StudentPortalScreen> {
  final TextEditingController _enrollmentController = TextEditingController();
  Student? _currentStudent;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _lookupStudent();
    });
  }

  void _lookupStudent() {
    final provider = context.read<AttendanceProvider>();
    final code = _enrollmentController.text.trim().toLowerCase();

    Student? found;
    for (var w in provider.workshops) {
      for (var s in w.enrolledStudents) {
        if (s.enrollmentNumber.toLowerCase() == code) {
          found = s;
          break;
        }
      }
      if (found != null) break;
    }

    setState(() {
      _currentStudent = found;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AttendanceProvider>(
      builder: (context, provider, child) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Portal del Estudiante'),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Identificación del Alumno
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.slate200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Identifícate con tu Matrícula o Código:',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.slate800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _enrollmentController,
                              decoration: const InputDecoration(
                                prefixIcon: Icon(Icons.badge_rounded, color: AppTheme.primary),
                                hintText: 'Ej. 2026-PAV-001',
                              ),
                              onSubmitted: (_) => _lookupStudent(),
                            ),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton(
                            onPressed: _lookupStudent,
                            child: const Text('Buscar'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                if (_currentStudent != null) ...[
                  // Perfil del Alumno
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryLight,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.primary.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 26,
                          backgroundColor: AppTheme.primary,
                          child: Text(
                            _currentStudent!.fullName[0],
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _currentStudent!.fullName,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.slate900,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Matrícula: ${_currentStudent!.enrollmentNumber} • ${_currentStudent!.email}',
                                style: const TextStyle(fontSize: 12, color: AppTheme.slate600),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // BOTÓN DESTACADO PARA ESCANEAR
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.qr_code_scanner_rounded, size: 24),
                      label: const Text(
                        'Escanear QR de Asistencia del Docente',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => StudentScannerScreen(initialStudent: _currentStudent),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Resumen de Puntos de Asistencia del Alumno
                  _buildStudentPointsBanner(provider, _currentStudent!),
                  const SizedBox(height: 24),

                  // Mis Talleres y Sesiones
                  const Text(
                    'Mis Talleres y Estatus de Acreditación',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.slate900,
                    ),
                  ),
                  const SizedBox(height: 12),

                  ..._buildEnrolledWorkshopsList(provider, _currentStudent!),
                ] else ...[
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(40),
                      child: Column(
                        children: [
                          const Icon(Icons.person_search_rounded, size: 56, color: AppTheme.slate600),
                          const SizedBox(height: 12),
                          const Text(
                            'Ingresa tu matrícula para consultar tus talleres y registrar asistencias.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 14, color: AppTheme.slate700),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildEnrolledWorkshopsList(AttendanceProvider provider, Student student) {
    final enrolledWorkshops = provider.workshops.where(
      (w) => w.enrolledStudents.any((s) => s.id == student.id || s.enrollmentNumber == student.enrollmentNumber),
    ).toList();

    if (enrolledWorkshops.isEmpty) {
      return [
        const Center(
          child: Text('No te encuentras inscrito en ningún taller activo actualmente.'),
        ),
      ];
    }

    return enrolledWorkshops.map((w) {
      return Card(
        margin: const EdgeInsets.only(bottom: 16),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      w.name,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.slate900),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.slate100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      w.code,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.slate700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Docente: ${w.instructorName}',
                style: const TextStyle(fontSize: 12, color: AppTheme.slate600),
              ),
              const Divider(height: 20),

              const Text(
                'Sesiones:',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.slate800),
              ),
              const SizedBox(height: 8),

              ...w.sessions.map((s) {
                final rec = s.records[student.id];
                final status = rec?.status ?? AttendanceStatus.absent;

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.slate50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.slate200),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s.title,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.slate900),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Entrada: ${rec?.checkInTime != null ? _formatTime(rec!.checkInTime!) : "Pendiente"} | Salida: ${rec?.checkOutTime != null ? _formatTime(rec!.checkOutTime!) : "Pendiente"}',
                              style: const TextStyle(fontSize: 11, color: AppTheme.slate600),
                            ),
                          ],
                        ),
                      ),
                      StudentStatusBadge(status: status),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      );
    }).toList();
  }

  Widget _buildStudentPointsBanner(AttendanceProvider provider, Student student) {
    int accreditedPoints = 0;
    int totalSessions = 0;

    final enrolledWorkshops = provider.workshops.where(
      (w) => w.enrolledStudents.any((s) => s.id == student.id || s.enrollmentNumber == student.enrollmentNumber),
    );

    for (var w in enrolledWorkshops) {
      for (var s in w.sessions) {
        totalSessions++;
        final rec = s.records[student.id];
        if (rec != null && rec.status == AttendanceStatus.accredited) {
          accreditedPoints++;
        }
      }
    }

    final double ratio = totalSessions == 0 ? 0.0 : (accreditedPoints / totalSessions);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.slate200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.stars_rounded, color: AppTheme.incompleteColor, size: 24),
                  SizedBox(width: 8),
                  Text(
                    'Puntos de Acreditación',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppTheme.slate900),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.accreditedBg,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$accreditedPoints / $totalSessions Pts',
                  style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.accreditedColor, fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 8,
              backgroundColor: AppTheme.slate100,
              valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.accreditedColor),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            totalSessions == 0
                ? 'No hay sesiones registradas en tus talleres aún.'
                : 'Tienes $accreditedPoints punto(s) de asistencia acreditados al 100% (Entrada y Salida selladas).',
            style: const TextStyle(fontSize: 12, color: AppTheme.slate600),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
