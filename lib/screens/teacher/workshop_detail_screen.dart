import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/workshop.dart';
import '../../providers/attendance_provider.dart';
import '../../utils/app_theme.dart';
import 'live_session_screen.dart';
import 'session_report_screen.dart';

class WorkshopDetailScreen extends StatefulWidget {
  final String workshopId;

  const WorkshopDetailScreen({super.key, required this.workshopId});

  @override
  State<WorkshopDetailScreen> createState() => _WorkshopDetailScreenState();
}

class _WorkshopDetailScreenState extends State<WorkshopDetailScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AttendanceProvider>(
      builder: (context, provider, child) {
        final workshop = provider.workshops.firstWhere(
          (w) => w.id == widget.workshopId,
          orElse: () => Workshop(
            id: '',
            name: 'No encontrado',
            code: '',
            instructorName: '',
            description: '',
          ),
        );

        if (workshop.id.isEmpty) {
          return const Scaffold(
            body: Center(child: Text('Taller no encontrado')),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(workshop.name),
            bottom: TabBar(
              controller: _tabController,
              labelColor: AppTheme.primary,
              unselectedLabelColor: AppTheme.slate600,
              indicatorColor: AppTheme.primary,
              tabs: [
                Tab(icon: const Icon(Icons.calendar_month_rounded), text: 'Sesiones (${workshop.sessions.length})'),
                Tab(icon: const Icon(Icons.people_outline_rounded), text: 'Alumnos (${workshop.enrolledStudents.length})'),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tabController,
            children: [
              // PESTAÑA 1: SESIONES
              _buildSessionsTab(context, provider, workshop),
              // PESTAÑA 2: ALUMNOS
              _buildStudentsTab(context, provider, workshop),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            icon: Icon(_tabController.index == 0 ? Icons.add_alarm_rounded : Icons.person_add_rounded),
            label: Text(_tabController.index == 0 ? 'Nueva Sesión' : 'Inscribir Alumno'),
            backgroundColor: AppTheme.primary,
            foregroundColor: Colors.white,
            onPressed: () {
              if (_tabController.index == 0) {
                _showCreateSessionDialog(context, provider, workshop);
              } else {
                _showAddStudentDialog(context, provider, workshop);
              }
            },
          ),
        );
      },
    );
  }

  Widget _buildSessionsTab(BuildContext context, AttendanceProvider provider, Workshop workshop) {
    if (workshop.sessions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.event_busy_rounded, size: 48, color: AppTheme.slate600),
            const SizedBox(height: 12),
            const Text(
              'No hay sesiones programadas en este taller.',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.slate700),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.add_rounded),
              label: const Text('Crear Primera Sesión'),
              onPressed: () => _showCreateSessionDialog(context, provider, workshop),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: workshop.sessions.length,
      separatorBuilder: (_, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final session = workshop.sessions[index];
        final stats = provider.getSessionStats(workshop, session);

        return Card(
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
                        session.title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.slate900,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: session.isQrActive ? AppTheme.accreditedBg : AppTheme.slate100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        session.phaseLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: session.isQrActive ? AppTheme.accreditedColor : AppTheme.slate700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Fecha: ${session.date.day}/${session.date.month}/${session.date.year}',
                  style: const TextStyle(fontSize: 12, color: AppTheme.slate600),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _buildPill('Acreditados: ${stats.accredited}', AppTheme.accreditedColor, AppTheme.accreditedBg),
                    const SizedBox(width: 8),
                    _buildPill('Incompletos: ${stats.incomplete}', AppTheme.incompleteColor, AppTheme.incompleteBg),
                    const SizedBox(width: 8),
                    _buildPill('Inasistencias: ${stats.absent}', AppTheme.absentColor, AppTheme.absentBg),
                  ],
                ),
                const Divider(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.bar_chart_rounded, size: 16),
                      label: const Text('Auditoría'),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => SessionReportScreen(
                              workshop: workshop,
                              session: session,
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.qr_code_scanner_rounded, size: 16),
                      label: const Text('Pase en Vivo (QR)'),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => LiveSessionScreen(
                              workshop: workshop,
                              session: session,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStudentsTab(BuildContext context, AttendanceProvider provider, Workshop workshop) {
    if (workshop.enrolledStudents.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.people_alt_outlined, size: 48, color: AppTheme.slate600),
            const SizedBox(height: 12),
            const Text(
              'No hay alumnos inscritos en este taller.',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.slate700),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.person_add_rounded),
              label: const Text('Inscribir Primer Alumno'),
              onPressed: () => _showAddStudentDialog(context, provider, workshop),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: workshop.enrolledStudents.length,
      separatorBuilder: (_, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final student = workshop.enrolledStudents[index];

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.slate200),
          ),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: AppTheme.primaryLight,
                child: Text(
                  student.fullName.isNotEmpty ? student.fullName[0] : '?',
                  style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      student.fullName,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppTheme.slate900),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Matrícula: ${student.enrollmentNumber} • ${student.email}',
                      style: const TextStyle(fontSize: 12, color: AppTheme.slate600),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.slate100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Inscrito Oficial',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.slate700),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPill(String text, Color textCol, Color bgCol) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgCol,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: textCol),
      ),
    );
  }

  void _showCreateSessionDialog(BuildContext context, AttendanceProvider provider, Workshop workshop) {
    final titleController = TextEditingController(text: 'Sesión ${workshop.sessions.length + 1}: Práctica y Evaluación');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Crear Nueva Sesión'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Título o tema de la sesión:'),
            const SizedBox(height: 8),
            TextField(
              controller: titleController,
              decoration: const InputDecoration(hintText: 'Ej. Sesión 3: Pruebas de Calidad'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () {
              if (titleController.text.trim().isNotEmpty) {
                provider.createSession(
                  workshopId: workshop.id,
                  title: titleController.text.trim(),
                  date: DateTime.now(),
                );
                Navigator.pop(ctx);
              }
            },
            child: const Text('Crear Sesión'),
          ),
        ],
      ),
    );
  }

  void _showAddStudentDialog(BuildContext context, AttendanceProvider provider, Workshop workshop) {
    final nameCtrl = TextEditingController();
    final matCtrl = TextEditingController();
    final emailCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Inscribir Alumno al Taller'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Nombre Completo', hintText: 'Ej. Juan Carlos Ramos'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: matCtrl,
                decoration: const InputDecoration(labelText: 'Matrícula o Código', hintText: 'Ej. 2026-PAV-099'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: emailCtrl,
                decoration: const InputDecoration(labelText: 'Correo Electrónico', hintText: 'alumno@universidad.edu'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () {
              if (nameCtrl.text.trim().isNotEmpty && matCtrl.text.trim().isNotEmpty) {
                provider.addStudentToWorkshop(
                  workshopId: workshop.id,
                  enrollmentNumber: matCtrl.text.trim(),
                  fullName: nameCtrl.text.trim(),
                  email: emailCtrl.text.trim().isNotEmpty ? emailCtrl.text.trim() : '${matCtrl.text.trim().toLowerCase()}@universidad.edu',
                );
                Navigator.pop(ctx);
              }
            },
            child: const Text('Inscribir Alumno'),
          ),
        ],
      ),
    );
  }
}
