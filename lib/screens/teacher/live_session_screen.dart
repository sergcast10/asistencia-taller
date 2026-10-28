import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/workshop.dart';
import '../../models/session.dart';
import '../../models/student.dart';
import '../../models/attendance_record.dart';
import '../../providers/attendance_provider.dart';
import '../../utils/app_theme.dart';
import '../../widgets/dynamic_qr_display.dart';
import '../../widgets/simulated_scanner_dialog.dart';
import '../../widgets/student_status_badge.dart';
import 'session_report_screen.dart';
import 'teacher_qr_scanner_screen.dart';

class LiveSessionScreen extends StatelessWidget {
  final Workshop workshop;
  final WorkshopSession session;

  const LiveSessionScreen({
    super.key,
    required this.workshop,
    required this.session,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<AttendanceProvider>(
      builder: (context, provider, child) {
        final currentWorkshop = provider.workshops.firstWhere(
          (w) => w.id == workshop.id,
          orElse: () => workshop,
        );
        final currentSession = currentWorkshop.sessions.firstWhere(
          (s) => s.id == session.id,
          orElse: () => session,
        );

        final stats = provider.getSessionStats(currentWorkshop, currentSession);

        return Scaffold(
          appBar: AppBar(
            title: Text(currentWorkshop.name),
            actions: [
              TextButton.icon(
                icon: const Icon(Icons.assessment_rounded, size: 18),
                label: const Text('Auditoría'),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SessionReportScreen(
                        workshop: currentWorkshop,
                        session: currentSession,
                      ),
                    ),
                  );
                },
              ),
              IconButton(
                tooltip: 'Probar / Simular Escaneo',
                icon: const Icon(Icons.bolt_rounded, color: AppTheme.primary),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (_) => SimulatedScannerDialog(
                      workshop: currentWorkshop,
                      session: currentSession,
                    ),
                  );
                },
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Encabezado de la sesión
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
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
                          Expanded(
                            child: Text(
                              currentSession.title,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.slate900,
                              ),
                            ),
                          ),
                          _buildPhaseChip(currentSession.currentPhase),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Docente: ${currentWorkshop.instructorName} • Código: ${currentWorkshop.code}',
                        style: const TextStyle(fontSize: 13, color: AppTheme.slate600),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // BARRA DE CONTROL DE FASES (Botones del Docente)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.slate200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Control del Pase de Asistencia por el Docente',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.slate800,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 10,
                        children: [
                          // Botón 1: Pase de Entrada
                          ElevatedButton.icon(
                            icon: const Icon(Icons.login_rounded, size: 18),
                            label: const Text('1. Habilitar ENTRADA'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: currentSession.currentPhase == SessionPhase.entry
                                  ? AppTheme.accreditedColor
                                  : AppTheme.slate700,
                            ),
                            onPressed: () {
                              provider.updateSessionPhase(
                                workshopId: currentWorkshop.id,
                                sessionId: currentSession.id,
                                newPhase: SessionPhase.entry,
                              );
                            },
                          ),

                          // Botón 2: Pausar / Iniciar Taller
                          ElevatedButton.icon(
                            icon: const Icon(Icons.pause_circle_rounded, size: 18),
                            label: const Text('2. Pausar Pase (Clase)'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: currentSession.currentPhase == SessionPhase.inProgress
                                  ? AppTheme.incompleteColor
                                  : AppTheme.slate700,
                            ),
                            onPressed: () {
                              provider.updateSessionPhase(
                                workshopId: currentWorkshop.id,
                                sessionId: currentSession.id,
                                newPhase: SessionPhase.inProgress,
                              );
                            },
                          ),

                          // Botón 3: Pase de Salida
                          ElevatedButton.icon(
                            icon: const Icon(Icons.logout_rounded, size: 18),
                            label: const Text('3. Habilitar SALIDA'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: currentSession.currentPhase == SessionPhase.exit
                                  ? AppTheme.primary
                                  : AppTheme.slate700,
                            ),
                            onPressed: () {
                              provider.updateSessionPhase(
                                workshopId: currentWorkshop.id,
                                sessionId: currentSession.id,
                                newPhase: SessionPhase.exit,
                              );
                            },
                          ),

                          // Botón 4: Concluir Sesión
                          OutlinedButton.icon(
                            icon: const Icon(Icons.done_all_rounded, size: 18),
                            label: const Text('Finalizar Sesión'),
                            onPressed: () {
                              provider.updateSessionPhase(
                                workshopId: currentWorkshop.id,
                                sessionId: currentSession.id,
                                newPhase: SessionPhase.finished,
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // PANEL CENTRAL: QR DINÁMICO O ESTADO PAUSADO
                if (currentSession.isQrActive) ...[
                  DynamicQrDisplay(
                    session: currentSession,
                    workshopId: currentWorkshop.id,
                  ),
                ] else ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(36),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppTheme.slate200),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          currentSession.currentPhase == SessionPhase.finished
                              ? Icons.task_alt_rounded
                              : Icons.qr_code_2_rounded,
                          size: 64,
                          color: AppTheme.slate600,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          currentSession.currentPhase == SessionPhase.finished
                              ? 'Sesión Concluida y Consolidada'
                              : 'Pase de Lista Inactivo',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.slate800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          currentSession.currentPhase == SessionPhase.finished
                              ? 'Todos los registros han sido cerrados. Consulta la pantalla de Auditoría para ver el reporte de acreditación.'
                              : 'Presiona "Habilitar ENTRADA" al iniciar o "Habilitar SALIDA" al finalizar para mostrar el código QR dinámico.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppTheme.slate600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 24),

                // MARCADOR EN TIEMPO REAL
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    const Text(
                      'Monitoreo en Tiempo Real',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.slate900,
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ElevatedButton.icon(
                          icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                          label: const Text('📷 Escanear QR Alumnos'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.accreditedColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                          ),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => TeacherQrScannerScreen(
                                  workshop: currentWorkshop,
                                  session: currentSession,
                                ),
                              ),
                            );
                          },
                        ),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.badge_rounded, size: 16),
                          label: const Text('⚡ Pase por Matrícula'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          ),
                          onPressed: () => _showManualControlDialog(context, provider, currentWorkshop, currentSession),
                        ),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.flash_on_rounded, size: 16),
                          label: const Text('Simulador'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryLight,
                            foregroundColor: AppTheme.primary,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          ),
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (_) => SimulatedScannerDialog(
                                workshop: currentWorkshop,
                                session: currentSession,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Resumen rápido en tarjetas
                Row(
                  children: [
                    Expanded(
                      child: _buildMiniIndicator(
                        'Entradas',
                        '${stats.entriesCount} / ${stats.totalStudents}',
                        Icons.login_rounded,
                        AppTheme.accreditedColor,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildMiniIndicator(
                        'Salidas',
                        '${stats.exitsCount} / ${stats.totalStudents}',
                        Icons.logout_rounded,
                        AppTheme.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildMiniIndicator(
                        'Acreditados',
                        '${stats.accredited} Alumnos',
                        Icons.verified_rounded,
                        AppTheme.accreditedColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Lista de alumnos con su estado en esta sesión
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.slate200),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: currentWorkshop.enrolledStudents.length,
                    separatorBuilder: (_, index) => const Divider(height: 1, color: AppTheme.slate200),
                    itemBuilder: (context, index) {
                      final student = currentWorkshop.enrolledStudents[index];
                      final record = currentSession.records[student.id];
                      final status = record?.status ?? AttendanceStatus.absent;

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppTheme.slate100,
                          child: Text(
                            student.fullName.isNotEmpty ? student.fullName[0] : '?',
                            style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.slate800),
                          ),
                        ),
                        title: Text(
                          student.fullName,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                        ),
                        subtitle: Text(
                          'Mat: ${student.enrollmentNumber} | Ent: ${record?.checkInTime != null ? _formatShort(record!.checkInTime!) : "--:--"} | Sal: ${record?.checkOutTime != null ? _formatShort(record!.checkOutTime!) : "--:--"}${record?.isLocked == true ? " 🔒" : ""}',
                          style: const TextStyle(fontSize: 12, color: AppTheme.slate600),
                        ),
                        trailing: StudentStatusBadge(status: status),
                        onTap: () => _showStudentActionSheet(context, provider, currentWorkshop, currentSession, student, record),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static String _formatShort(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildPhaseChip(SessionPhase phase) {
    Color color;
    Color bg;
    String label;

    switch (phase) {
      case SessionPhase.entry:
        color = AppTheme.accreditedColor;
        bg = AppTheme.accreditedBg;
        label = '🟢 Entrada Activa';
        break;
      case SessionPhase.exit:
        color = AppTheme.primary;
        bg = AppTheme.primaryLight;
        label = '🔵 Salida Activa';
        break;
      case SessionPhase.inProgress:
        color = AppTheme.incompleteColor;
        bg = AppTheme.incompleteBg;
        label = '🟡 Taller en Curso';
        break;
      case SessionPhase.finished:
        color = AppTheme.slate700;
        bg = AppTheme.slate200;
        label = 'Concluido';
        break;
      default:
        color = AppTheme.slate600;
        bg = AppTheme.slate100;
        label = 'Pendiente';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildMiniIndicator(String title, String val, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.slate200),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 10, color: AppTheme.slate600, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  val,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppTheme.slate900),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showManualControlDialog(
    BuildContext context,
    AttendanceProvider provider,
    Workshop workshop,
    WorkshopSession session,
  ) {
    final controlCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    bool isKnownStudent = false;
    String matchedName = '';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(
              children: [
                Icon(Icons.badge_rounded, color: AppTheme.primary),
                SizedBox(width: 10),
                Text('Pase por Matrícula', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'El alumno o el docente escribe la matrícula y el sistema sella su asistencia inmediatamente.',
                  style: TextStyle(fontSize: 13, color: AppTheme.slate600),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controlCtrl,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Número de Control / Matrícula',
                    hintText: 'Ej. 21280001',
                    prefixIcon: Icon(Icons.pin_rounded),
                  ),
                  onChanged: (val) {
                    final clean = val.trim().toUpperCase();
                    final match = workshop.enrolledStudents.cast<Student?>().firstWhere(
                      (s) => s != null && s.enrollmentNumber.trim().toUpperCase() == clean,
                      orElse: () => null,
                    );
                    setDialogState(() {
                      if (match != null) {
                        isKnownStudent = true;
                        matchedName = match.fullName;
                      } else {
                        isKnownStudent = false;
                        matchedName = '';
                      }
                    });
                  },
                ),
                const SizedBox(height: 12),
                if (isKnownStudent)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.accreditedBg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle_rounded, size: 18, color: AppTheme.accreditedColor),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Alumno reconocido: $matchedName',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.accreditedColor),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  TextField(
                    controller: nameCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Nombre Completo (si es alumno nuevo)',
                      hintText: 'Ej. Juan Carlos Pérez',
                      prefixIcon: Icon(Icons.person_rounded),
                    ),
                  ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
              ElevatedButton.icon(
                icon: const Icon(Icons.check_rounded, size: 18),
                label: Text(
                  session.currentPhase == SessionPhase.exit ? 'Sellar Salida' : 'Sellar Entrada',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: session.currentPhase == SessionPhase.exit ? AppTheme.primary : AppTheme.accreditedColor,
                ),
                onPressed: () async {
                  final control = controlCtrl.text.trim();
                  final name = nameCtrl.text.trim();

                  if (control.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Ingresa la matrícula del alumno.')),
                    );
                    return;
                  }

                  // Si el alumno no estaba en la lista, auto-inscribirlo
                  Student? targetStudent = workshop.enrolledStudents.cast<Student?>().firstWhere(
                    (s) => s != null && s.enrollmentNumber.trim().toUpperCase() == control.toUpperCase(),
                    orElse: () => null,
                  );

                  if (targetStudent == null) {
                    if (name.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Ingresa el nombre del alumno para inscribirlo.')),
                      );
                      return;
                    }
                    await provider.addStudentToWorkshop(
                      workshopId: workshop.id,
                      fullName: name,
                      enrollmentNumber: control,
                      email: '${control.toLowerCase()}@alumno.edu',
                    );
                    targetStudent = workshop.enrolledStudents.firstWhere(
                      (s) => s.enrollmentNumber.trim().toUpperCase() == control.toUpperCase(),
                    );
                  }

                  // Sellar asistencia según la fase
                  final res = provider.registerDirectAttendance(
                    workshopId: workshop.id,
                    sessionId: session.id,
                    studentId: targetStudent.id,
                    phase: session.currentPhase,
                  );

                  if (ctx.mounted) Navigator.pop(ctx);

                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('${res.title}: ${res.message}'),
                        backgroundColor: res.success ? AppTheme.accreditedColor : AppTheme.absentColor,
                        duration: const Duration(seconds: 3),
                      ),
                    );
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }

  void _showStudentActionSheet(
    BuildContext context,
    AttendanceProvider provider,
    Workshop workshop,
    WorkshopSession session,
    Student student,
    AttendanceRecord? record,
  ) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: AppTheme.primaryLight,
                  child: Text(
                    student.fullName.isNotEmpty ? student.fullName[0] : '?',
                    style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.primary, fontSize: 18),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(student.fullName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                      Text('Matrícula: ${student.enrollmentNumber}', style: const TextStyle(fontSize: 13, color: AppTheme.slate600)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Estado actual
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.slate100,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(
                    children: [
                      const Text('🟢 Entrada', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.slate600)),
                      const SizedBox(height: 4),
                      Text(
                        record?.checkInTime != null ? '${_formatShort(record!.checkInTime!)} 🔒' : 'Sin sellar',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: record?.checkInTime != null ? AppTheme.accreditedColor : AppTheme.slate600,
                        ),
                      ),
                    ],
                  ),
                  Container(height: 30, width: 1, color: AppTheme.slate200),
                  Column(
                    children: [
                      const Text('🔴 Salida', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.slate600)),
                      const SizedBox(height: 4),
                      Text(
                        record?.checkOutTime != null ? '${_formatShort(record!.checkOutTime!)} 🔒' : 'Sin sellar',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: record?.checkOutTime != null ? AppTheme.primary : AppTheme.slate600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Botones de acción manual
            if (record?.hasCheckIn != true)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.login_rounded),
                  label: const Text('Sellar Entrada Oficial Ahora 🔒'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accreditedColor,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () {
                    provider.registerDirectAttendance(
                      workshopId: workshop.id,
                      sessionId: session.id,
                      studentId: student.id,
                      phase: SessionPhase.entry,
                    );
                    Navigator.pop(ctx);
                  },
                ),
              ),
            if (record?.hasCheckIn != true && record?.hasCheckOut != true)
              const SizedBox(height: 10),
            if (record?.hasCheckOut != true)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Sellar Salida Oficial Ahora 🔒'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () {
                    provider.registerDirectAttendance(
                      workshopId: workshop.id,
                      sessionId: session.id,
                      studentId: student.id,
                      phase: SessionPhase.exit,
                    );
                    Navigator.pop(ctx);
                  },
                ),
              ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cerrar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
