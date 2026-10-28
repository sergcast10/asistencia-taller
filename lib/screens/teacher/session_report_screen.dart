import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/workshop.dart';
import '../../models/session.dart';
import '../../models/attendance_record.dart';
import '../../providers/attendance_provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/csv_exporter.dart';
import '../../widgets/stat_card.dart';
import '../../widgets/student_status_badge.dart';

class SessionReportScreen extends StatelessWidget {
  final Workshop workshop;
  final WorkshopSession session;

  const SessionReportScreen({
    super.key,
    required this.workshop,
    required this.session,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<AttendanceProvider>(
      builder: (context, provider, child) {
        // Obtenemos versiones actualizadas
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
            title: const Text('Auditoría y Acreditaciones'),
            actions: [
              IconButton(
                tooltip: 'Exportar Reporte CSV',
                icon: const Icon(Icons.download_rounded, color: AppTheme.primary),
                onPressed: () => _exportCsv(context, currentWorkshop, currentSession),
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Tarjeta de información del taller y sesión
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.slate200),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryLight,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.school_rounded, color: AppTheme.primary, size: 28),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              currentWorkshop.name,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.slate900,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${currentSession.title} • Docente: ${currentWorkshop.instructorName}',
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppTheme.slate600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppTheme.slate100,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${currentSession.date.day}/${currentSession.date.month}/${currentSession.date.year}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.slate700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                // Tarjetas métricas
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth > 700;
                    return GridView.count(
                      crossAxisCount: isWide ? 4 : 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      childAspectRatio: isWide ? 1.5 : 1.3,
                      children: [
                        StatCard(
                          title: 'Inscritos',
                          value: stats.totalStudents.toString(),
                          icon: Icons.people_alt_rounded,
                          color: AppTheme.slate800,
                          backgroundColor: AppTheme.slate100,
                        ),
                        StatCard(
                          title: 'Acreditados',
                          value: stats.accredited.toString(),
                          subtitle: 'Entrada y Salida OK',
                          icon: Icons.verified_rounded,
                          color: AppTheme.accreditedColor,
                          backgroundColor: AppTheme.accreditedBg,
                        ),
                        StatCard(
                          title: 'Incompletos',
                          value: stats.incomplete.toString(),
                          subtitle: 'Falta Entrada o Salida',
                          icon: Icons.warning_amber_rounded,
                          color: AppTheme.incompleteColor,
                          backgroundColor: AppTheme.incompleteBg,
                        ),
                        StatCard(
                          title: 'Inasistencias',
                          value: stats.absent.toString(),
                          subtitle: 'Sin registros',
                          icon: Icons.cancel_outlined,
                          color: AppTheme.absentColor,
                          backgroundColor: AppTheme.absentBg,
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 24),

                // Lista detallada de estudiantes
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Padrón Oficial y Estatus de Acreditación',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.slate900,
                      ),
                    ),
                    Text(
                      '${currentWorkshop.enrolledStudents.length} Alumnos',
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppTheme.slate600,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: currentWorkshop.enrolledStudents.length,
                  separatorBuilder: (_, index) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final student = currentWorkshop.enrolledStudents[index];
                    final record = currentSession.records[student.id];

                    final status = record?.status ?? AttendanceStatus.absent;

                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: status == AttendanceStatus.accredited
                              ? AppTheme.accreditedColor.withOpacity(0.3)
                              : AppTheme.slate200,
                        ),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: AppTheme.slate100,
                            child: Text(
                              student.fullName.isNotEmpty ? student.fullName[0].toUpperCase() : '?',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: AppTheme.slate800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  student.fullName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                    color: AppTheme.slate900,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Matrícula: ${student.enrollmentNumber} • ${student.email}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.slate600,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    _buildTimeTag(
                                      'Entrada:',
                                      record?.checkInTime,
                                      Icons.login_rounded,
                                      AppTheme.accreditedColor,
                                    ),
                                    const SizedBox(width: 14),
                                    _buildTimeTag(
                                      'Salida:',
                                      record?.checkOutTime,
                                      Icons.logout_rounded,
                                      AppTheme.primary,
                                    ),
                                    if (record?.isLocked == true) ...[
                                      const SizedBox(width: 10),
                                      const Text('🔒', style: TextStyle(fontSize: 12)),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          StudentStatusBadge(status: status),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTimeTag(String label, DateTime? time, IconData icon, Color color) {
    final text = time != null
        ? '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}'
        : 'Pendiente';

    final hasTime = time != null;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: hasTime ? color : AppTheme.slate600),
        const SizedBox(width: 4),
        Text(
          '$label $text',
          style: TextStyle(
            fontSize: 11,
            fontWeight: hasTime ? FontWeight.w700 : FontWeight.w500,
            color: hasTime ? AppTheme.slate800 : AppTheme.slate600,
          ),
        ),
      ],
    );
  }

  void _exportCsv(BuildContext context, Workshop workshop, WorkshopSession session) {
    final csvContent = CsvExporter.generateSessionCsv(
      workshop: workshop,
      session: session,
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.description_rounded, color: AppTheme.primary),
            SizedBox(width: 10),
            Text('Reporte CSV Generado'),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'El reporte oficial de acreditaciones está listo. Puedes copiarlo o guardarlo para importarlo a Excel:',
                style: TextStyle(fontSize: 13, color: AppTheme.slate700),
              ),
              const SizedBox(height: 12),
              Container(
                height: 180,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.slate100,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.slate200),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    csvContent,
                    style: const TextStyle(fontFamily: 'Consolas', fontSize: 11),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: const Text('Copiar al Portapapeles'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: csvContent));
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Reporte CSV copiado al portapapeles.'),
                  backgroundColor: AppTheme.accreditedColor,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
