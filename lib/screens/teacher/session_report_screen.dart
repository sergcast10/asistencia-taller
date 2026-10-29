import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/workshop.dart';
import '../../models/session.dart';
import '../../models/student.dart';
import '../../models/attendance_record.dart';
import '../../providers/attendance_provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/csv_exporter.dart';
import '../../widgets/stat_card.dart';
import '../../widgets/student_status_badge.dart';

class SessionReportScreen extends StatefulWidget {
  final Workshop workshop;
  final WorkshopSession session;

  const SessionReportScreen({
    super.key,
    required this.workshop,
    required this.session,
  });

  @override
  State<SessionReportScreen> createState() => _SessionReportScreenState();
}

class _SessionReportScreenState extends State<SessionReportScreen> {
  Timer? _syncTimer;
  bool _isSyncing = false;
  String _selectedFilter = 'all'; // 'all', 'cumplieron', 'falto_salida', 'no_entraron'

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncFromCloud(silent: true);
    });
    _syncTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      _syncFromCloud(silent: true);
    });
  }

  Future<void> _syncFromCloud({bool silent = false}) async {
    if (!mounted || _isSyncing) return;
    _isSyncing = true;
    try {
      final provider = context.read<AttendanceProvider>();
      final count = await provider.syncRecordsFromSupabase(
        workshopId: widget.workshop.id,
        sessionId: widget.session.id,
      );
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ Sincronizados $count registros del día de hoy desde Supabase.',
            ),
            backgroundColor: AppTheme.accreditedColor,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } finally {
      _isSyncing = false;
    }
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AttendanceProvider>(
      builder: (context, provider, child) {
        final currentWorkshop = provider.workshops.firstWhere(
          (w) => w.id == widget.workshop.id,
          orElse: () => widget.workshop,
        );
        final currentSession = currentWorkshop.sessions.firstWhere(
          (s) => s.id == widget.session.id,
          orElse: () => widget.session,
        );

        final stats = provider.getSessionStats(currentWorkshop, currentSession);

        return Scaffold(
          appBar: AppBar(
            title: const Text('Auditoría y Acreditaciones'),
            actions: [
              IconButton(
                tooltip: 'Sincronizar Asistencias de Hoy',
                icon: const Icon(
                  Icons.cloud_sync_rounded,
                  color: AppTheme.accreditedColor,
                ),
                onPressed: () => _syncFromCloud(silent: false),
              ),
              IconButton(
                tooltip: 'Exportar Reporte CSV',
                icon: const Icon(
                  Icons.download_rounded,
                  color: AppTheme.primary,
                ),
                onPressed: () =>
                    _exportCsv(context, currentWorkshop, currentSession),
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryLight,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.school_rounded,
                              color: AppTheme.primary,
                              size: 28,
                            ),
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
                                const SizedBox(height: 4),
                                Text(
                                  '📅 ${currentSession.formattedDateWithDay} • 🕒 Inicio: ${currentSession.startTimeLabel} hrs ➔ Término: ${currentSession.endTimeLabel} hrs',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF065F46),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
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
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.slate100,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.timer_outlined,
                              size: 16,
                              color: AppTheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Tolerancia puntual: ${currentSession.toleranceMinutes} min • Ventana de registro: ${currentSession.registrationWindowMinutes} min',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.slate700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                // Tarjetas métricas actualizadas
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth > 700;
                    return GridView.count(
                      crossAxisCount: isWide ? 4 : 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      childAspectRatio: isWide ? 1.5 : 1.25,
                      children: [
                        StatCard(
                          title: 'Registrados Hoy',
                          value: stats.registeredTodayCount.toString(),
                          subtitle: 'Padrón: ${stats.totalStudents} alumnos',
                          icon: Icons.how_to_reg_rounded,
                          color: AppTheme.primary,
                          backgroundColor: AppTheme.primaryLight,
                        ),
                        StatCard(
                          title: 'Acreditados Hoy',
                          value: stats.accredited.toString(),
                          subtitle: 'Entrada y Salida OK',
                          icon: Icons.verified_rounded,
                          color: AppTheme.accreditedColor,
                          backgroundColor: AppTheme.accreditedBg,
                        ),
                        StatCard(
                          title: 'En Sala / Retraso',
                          value: stats.incomplete.toString(),
                          subtitle: '${stats.lateCount} con retardo',
                          icon: Icons.warning_amber_rounded,
                          color: AppTheme.incompleteColor,
                          backgroundColor: AppTheme.incompleteBg,
                        ),
                        StatCard(
                          title: 'Notas / Evidencias',
                          value: stats.notesCount.toString(),
                          subtitle: '${stats.absent} sin registro',
                          icon: Icons.assignment_turned_in_rounded,
                          color: const Color(0xFF7C3AED),
                          backgroundColor: const Color(0xFFF5F3FF),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 20),

                // Barra rápida para acreditar a los registrados del día de hoy
                if (stats.incomplete > 0) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF10B981)),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.verified_rounded,
                          color: Color(0xFF059669),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Hay ${stats.incomplete} alumno(s) con asistencia registrada hoy pendientes de sello de salida.',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF065F46),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.accreditedColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                          ),
                          onPressed: () async {
                            final count = await provider
                                .accreditAllRegisteredInSession(
                                  workshopId: currentWorkshop.id,
                                  sessionId: currentSession.id,
                                );
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '🎓 Se acreditaron $count alumnos registrados el día de hoy.',
                                  ),
                                  backgroundColor: AppTheme.accreditedColor,
                                ),
                              );
                            }
                          },
                          child: const Text(
                            'Acreditar Hoy',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                // BANNER DE LISTA DE ALUMNOS AL FINALIZAR / CERRAR LA SESIÓN DEL DÍA
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.slate200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryLight,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.fact_check_rounded,
                              color: AppTheme.primary,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Lista de Alumnos al Cierre de la Sesión de este Día',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.slate900,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Revisa quiénes cumplieron (Entrada + Salida), a quiénes les faltó registrar la salida y quiénes no entraron a la sesión.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.slate600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ChoiceChip(
                            label: Text(
                              '📋 Todos (${currentWorkshop.enrolledStudents.length})',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            selected: _selectedFilter == 'all',
                            onSelected: (_) =>
                                setState(() => _selectedFilter = 'all'),
                          ),
                          ChoiceChip(
                            label: Text(
                              '✅ Cumplieron (${stats.accredited})',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            selectedColor: AppTheme.accreditedBg,
                            selected: _selectedFilter == 'cumplieron',
                            onSelected: (_) =>
                                setState(() => _selectedFilter = 'cumplieron'),
                          ),
                          ChoiceChip(
                            label: Text(
                              '⚠️ Les Faltó Salida (${stats.incomplete})',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            selectedColor: AppTheme.incompleteBg,
                            selected: _selectedFilter == 'falto_salida',
                            onSelected: (_) => setState(
                              () => _selectedFilter = 'falto_salida',
                            ),
                          ),
                          ChoiceChip(
                            label: Text(
                              '❌ No Entraron (${stats.absent})',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            selectedColor: AppTheme.absentBg,
                            selected: _selectedFilter == 'no_entraron',
                            onSelected: (_) =>
                                setState(() => _selectedFilter = 'no_entraron'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ElevatedButton.icon(
                            icon: const Icon(
                              Icons.assignment_turned_in_rounded,
                              size: 16,
                            ),
                            label: const Text(
                              '📋 Ver Acta de Cierre (Cumplieron / Faltó Salida / No Entraron)',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            onPressed: () => _showClosingSummaryDialog(
                              context,
                              currentWorkshop,
                              currentSession,
                              stats,
                            ),
                          ),
                          ElevatedButton.icon(
                            icon: const Icon(
                              Icons.phonelink_erase_rounded,
                              size: 15,
                            ),
                            label: const Text(
                              '📵 Integrar / Sin Celular',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF7C3AED),
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () => _showEditOrNoPhoneDialog(
                              context,
                              provider,
                              currentWorkshop,
                              currentSession,
                              student: null,
                              defaultNoPhoneMode: true,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                if (currentWorkshop.enrolledStudents.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.slate200),
                    ),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.cloud_download_outlined,
                          size: 40,
                          color: AppTheme.slate600,
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Sincronizando registros desde Supabase...',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: AppTheme.slate800,
                          ),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Actualizar Padrón Ahora'),
                          onPressed: () => _syncFromCloud(silent: false),
                        ),
                      ],
                    ),
                  )
                else
                  Builder(
                    builder: (context) {
                      final filteredStudents =
                          currentWorkshop.enrolledStudents.where((student) {
                            final st =
                                currentSession.records[student.id]?.status ??
                                AttendanceStatus.absent;
                            if (_selectedFilter == 'cumplieron') {
                              return st == AttendanceStatus.accredited;
                            }
                            if (_selectedFilter == 'falto_salida') {
                              return st ==
                                      AttendanceStatus.incompleteEntryOnly ||
                                  st == AttendanceStatus.incompleteExitOnly;
                            }
                            if (_selectedFilter == 'no_entraron') {
                              return st == AttendanceStatus.absent;
                            }
                            return true;
                          }).toList();

                      if (filteredStudents.isEmpty) {
                        return Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppTheme.slate200),
                          ),
                          child: const Center(
                            child: Text(
                              'No hay alumnos en esta categoría para esta sesión.',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.slate600,
                              ),
                            ),
                          ),
                        );
                      }

                      return ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: filteredStudents.length,
                        separatorBuilder: (_, index) =>
                            const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final student = filteredStudents[index];
                          final record = currentSession.records[student.id];
                          final status =
                              record?.status ?? AttendanceStatus.absent;

                          // Texto claro de diagnóstico al cerrar la sesión
                          String closingDiagText;
                          Color closingDiagColor;
                          Color closingDiagBg;
                          IconData closingDiagIcon;

                          if (status == AttendanceStatus.accredited) {
                            closingDiagText =
                                '✅ CUMPLIÓ AL CERRAR LA SESIÓN (Entrada y Salida completas)';
                            closingDiagColor = AppTheme.accreditedColor;
                            closingDiagBg = AppTheme.accreditedBg;
                            closingDiagIcon = Icons.check_circle_rounded;
                          } else if (status ==
                              AttendanceStatus.incompleteEntryOnly) {
                            closingDiagText =
                                '⚠️ LE FALTÓ LA SALIDA AL CERRAR LA SESIÓN (Solo registró Entrada)';
                            closingDiagColor = AppTheme.incompleteColor;
                            closingDiagBg = AppTheme.incompleteBg;
                            closingDiagIcon = Icons.warning_amber_rounded;
                          } else if (status ==
                              AttendanceStatus.incompleteExitOnly) {
                            closingDiagText =
                                '⚠️ LE FALTÓ LA ENTRADA (Solo registró Salida)';
                            closingDiagColor = AppTheme.incompleteColor;
                            closingDiagBg = AppTheme.incompleteBg;
                            closingDiagIcon = Icons.warning_amber_rounded;
                          } else {
                            closingDiagText =
                                '❌ NO ENTRÓ A LA SESIÓN DE ESTE DÍA (Sin Entrada ni Salida)';
                            closingDiagColor = AppTheme.absentColor;
                            closingDiagBg = AppTheme.absentBg;
                            closingDiagIcon = Icons.cancel_rounded;
                          }

                          return Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: status == AttendanceStatus.accredited
                                    ? AppTheme.accreditedColor.withValues(
                                        alpha: 0.4,
                                      )
                                    : AppTheme.slate200,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Cinta superior con diagnóstico claro de cierre
                                Container(
                                  width: double.infinity,
                                  margin: const EdgeInsets.only(bottom: 10),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: closingDiagBg,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        closingDiagIcon,
                                        size: 16,
                                        color: closingDiagColor,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          closingDiagText,
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                            color: closingDiagColor,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 20,
                                      backgroundColor:
                                          status == AttendanceStatus.accredited
                                          ? AppTheme.accreditedBg
                                          : AppTheme.slate100,
                                      child: Text(
                                        student.fullName.isNotEmpty
                                            ? student.fullName[0].toUpperCase()
                                            : '?',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          color:
                                              status ==
                                                  AttendanceStatus.accredited
                                              ? AppTheme.accreditedColor
                                              : AppTheme.slate800,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Flexible(
                                                child: Text(
                                                  student.fullName,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: 14,
                                                    color: AppTheme.slate900,
                                                  ),
                                                ),
                                              ),
                                              if (record?.hasCheckIn ==
                                                  true) ...[
                                                const SizedBox(width: 8),
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 7,
                                                        vertical: 2,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: record!.isLate
                                                        ? const Color(
                                                            0xFFFEF3C7,
                                                          )
                                                        : const Color(
                                                            0xFFECFDF5,
                                                          ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          10,
                                                        ),
                                                  ),
                                                  child: Text(
                                                    record.isLate
                                                        ? '⏱️ Retraso +${record.lateMinutes}m'
                                                        : '🟢 Puntual',
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      color: record.isLate
                                                          ? const Color(
                                                              0xFFB45309,
                                                            )
                                                          : const Color(
                                                              0xFF059669,
                                                            ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ],
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
                                          Wrap(
                                            spacing: 14,
                                            runSpacing: 4,
                                            children: [
                                              _buildTimeTag(
                                                'Entrada:',
                                                record?.checkInTime,
                                                Icons.login_rounded,
                                                AppTheme.accreditedColor,
                                              ),
                                              _buildTimeTag(
                                                'Salida:',
                                                record?.checkOutTime,
                                                Icons.logout_rounded,
                                                AppTheme.primary,
                                              ),
                                              if (record?.isLocked == true)
                                                const Text(
                                                  '🔒 Sellado',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: AppTheme.slate600,
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        StudentStatusBadge(status: status),
                                        if (status !=
                                            AttendanceStatus.accredited)
                                          TextButton(
                                            style: TextButton.styleFrom(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 2,
                                                  ),
                                              minimumSize: Size.zero,
                                              tapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                            ),
                                            onPressed: () {
                                              provider.accreditStudentDirectly(
                                                workshopId: currentWorkshop.id,
                                                sessionId: currentSession.id,
                                                studentId: student.id,
                                              );
                                            },
                                            child: Text(
                                              status ==
                                                      AttendanceStatus
                                                          .incompleteEntryOnly
                                                  ? '✅ Dar Salida'
                                                  : '🎓 Acreditar',
                                              style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                            if (record?.hasNotes == true) ...[
                              const SizedBox(height: 10),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF5F3FF),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: const Color(0xFFC4B5FD),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.verified_user_rounded,
                                      size: 16,
                                      color: Color(0xFF6D28D9),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Evidencia Docente: ${record!.notes}',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF4C1D95),
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      tooltip:
                                          'Copiar Evidencia para el Alumno',
                                      icon: const Icon(
                                        Icons.copy_rounded,
                                        size: 15,
                                        color: Color(0xFF6D28D9),
                                      ),
                                      onPressed: () {
                                        Clipboard.setData(
                                          ClipboardData(
                                            text:
                                                'EVIDENCIA OFICIAL DE TALLER (${currentWorkshop.name}) - Alumno: ${student.fullName} (${student.enrollmentNumber}) -> ${record.notes}',
                                          ),
                                        );
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                  '📋 Evidencia del alumno copiada al portapapeles.',
                                                ),
                                                backgroundColor:
                                                    AppTheme.accreditedColor,
                                              ),
                                            );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                ElevatedButton.icon(
                                  icon: const Icon(
                                    Icons.phonelink_erase_rounded,
                                    size: 14,
                                  ),
                                  label: const Text(
                                    '📵 Sin Celular / Dar Asistencia',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF7C3AED),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    minimumSize: Size.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  onPressed: () => _showEditOrNoPhoneDialog(
                                    context,
                                    provider,
                                    currentWorkshop,
                                    currentSession,
                                    student: student,
                                    defaultNoPhoneMode: true,
                                  ),
                                ),
                                OutlinedButton.icon(
                                  icon: const Icon(
                                    Icons.edit_note_rounded,
                                    size: 15,
                                  ),
                                  label: const Text(
                                    '✏️ Editar Alumno / Evidencia',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    minimumSize: Size.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  onPressed: () => _showEditOrNoPhoneDialog(
                                    context,
                                    provider,
                                    currentWorkshop,
                                    currentSession,
                                    student: student,
                                    defaultNoPhoneMode: false,
                                  ),
                                ),
                                if (status != AttendanceStatus.accredited)
                                  ElevatedButton.icon(
                                    icon: const Icon(
                                      Icons.school_rounded,
                                      size: 14,
                                    ),
                                    label: const Text(
                                      '🎓 Acreditar Hoy',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppTheme.accreditedColor,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      minimumSize: Size.zero,
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    onPressed: () {
                                      provider.accreditStudentDirectly(
                                        workshopId: currentWorkshop.id,
                                        sessionId: currentSession.id,
                                        studentId: student.id,
                                      );
                                    },
                                  ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
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

  void _showClosingSummaryDialog(
    BuildContext context,
    Workshop workshop,
    WorkshopSession session,
    SessionStatistics stats,
  ) {
    final cumplieron = <Student>[];
    final faltoSalida = <Student>[];
    final noEntraron = <Student>[];

    for (final s in workshop.enrolledStudents) {
      final rec = session.records[s.id];
      final st = rec?.status ?? AttendanceStatus.absent;
      if (st == AttendanceStatus.accredited) {
        cumplieron.add(s);
      } else if (st == AttendanceStatus.incompleteEntryOnly ||
          st == AttendanceStatus.incompleteExitOnly) {
        faltoSalida.add(s);
      } else {
        noEntraron.add(s);
      }
    }

    String fmtTime(DateTime? dt) {
      if (dt == null) return '--:--';
      final l = dt.toLocal();
      return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}:${l.second.toString().padLeft(2, '0')}';
    }

    final sb = StringBuffer();
    sb.writeln('=== LISTA DE ALUMNOS AL CIERRE DE LA SESIÓN DEL DÍA ===');
    sb.writeln('Taller: ${workshop.name} (${workshop.code})');
    sb.writeln('Sesión: ${session.title}');
    sb.writeln('Día de Realización: ${session.formattedDateWithDay}');
    sb.writeln(
      'Horario: Comenzó ${session.startTimeLabel} hrs ➔ Terminó ${session.endTimeLabel} hrs',
    );
    sb.writeln('-------------------------------------------------------');
    sb.writeln(
      '✅ CUMPLIERON AL CERRAR LA SESIÓN (${cumplieron.length} alumnos):',
    );
    if (cumplieron.isEmpty) {
      sb.writeln('   (Ningún alumno en esta categoría)');
    } else {
      for (final s in cumplieron) {
        final r = session.records[s.id];
        sb.writeln(
          '   • ${s.fullName} (${s.enrollmentNumber}) — Entrada: ${fmtTime(r?.checkInTime)} | Salida: ${fmtTime(r?.checkOutTime)} [CUMPLIÓ]',
        );
      }
    }
    sb.writeln('');
    sb.writeln(
      '⚠️ LES FALTÓ LA SALIDA AL CERRAR LA SESIÓN (${faltoSalida.length} alumnos):',
    );
    if (faltoSalida.isEmpty) {
      sb.writeln('   (Ningún alumno con salida pendiente)');
    } else {
      for (final s in faltoSalida) {
        final r = session.records[s.id];
        sb.writeln(
          '   • ${s.fullName} (${s.enrollmentNumber}) — Entrada: ${fmtTime(r?.checkInTime)} | Salida: FALTÓ SALIDA',
        );
      }
    }
    sb.writeln('');
    sb.writeln(
      '❌ NO ENTRARON A LA SESIÓN DE ESTE DÍA (${noEntraron.length} alumnos):',
    );
    if (noEntraron.isEmpty) {
      sb.writeln('   (Todos los alumnos inscritos entraron hoy)');
    } else {
      for (final s in noEntraron) {
        sb.writeln(
          '   • ${s.fullName} (${s.enrollmentNumber}) — SIN ENTRADA NI SALIDA [NO ENTRÓ]',
        );
      }
    }
    sb.writeln('=======================================================');

    final fullText = sb.toString();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.fact_check_rounded, color: AppTheme.primary),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Lista de Alumnos al Cierre de la Sesión',
                style: TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 540,
          child: SingleChildScrollView(
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.slate50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.slate200),
              ),
              child: SelectableText(
                fullText,
                style: const TextStyle(
                  fontSize: 12,
                  fontFamily: 'Consolas',
                  color: AppTheme.slate900,
                  height: 1.4,
                ),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.download_rounded, size: 16),
            label: const Text('Exportar Excel / CSV'),
            onPressed: () {
              Navigator.pop(ctx);
              _exportCsv(context, workshop, session);
            },
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: const Text('Copiar Lista de Cierre'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: fullText));
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    '📋 Lista de cierre de sesión copiada al portapapeles.',
                  ),
                  backgroundColor: AppTheme.accreditedColor,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showEditOrNoPhoneDialog(
    BuildContext context,
    AttendanceProvider provider,
    Workshop workshop,
    WorkshopSession session, {
    Student? student,
    bool defaultNoPhoneMode = true,
  }) {
    final existingRec =
        student != null ? session.records[student.id] : null;
    final nameCtrl = TextEditingController(text: student?.fullName ?? '');
    final matCtrl = TextEditingController(
      text: student?.enrollmentNumber ?? '',
    );
    final emailCtrl = TextEditingController(text: student?.email ?? '');
    final extraCtrl = TextEditingController();

    final reasons = <String>[
      '📵 Sin celular en este momento (Autorizado por docente)',
      '🏠 Olvido de celular en domicilio',
      '🔍 Extravío o pérdida de celular',
      '🔋 Celular descargado / sin batería',
      '🌐 Sin datos móviles / sin conexión a internet',
      '🆕 Integración presencial al taller hoy',
    ];
    String selectedReason = reasons.first;
    bool grantAttendance = true;
    bool grantAccredited = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(
                defaultNoPhoneMode
                    ? Icons.phonelink_erase_rounded
                    : Icons.edit_note_rounded,
                color: const Color(0xFF7C3AED),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  student != null
                      ? 'Editar / Asistencia sin Celular: ${student.fullName}'
                      : 'Integrar Alumno / Asistencia sin Celular',
                  style: const TextStyle(fontSize: 15),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F3FF),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFC4B5FD)),
                  ),
                  child: const Text(
                    'Permite editar o integrar al alumno y darle su asistencia directamente cuando no trae celular (por olvido, extravío o falta de dispositivo), guardando evidencia del día.',
                    style: TextStyle(fontSize: 11, color: Color(0xFF4C1D95)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nombre Completo del Alumno',
                    prefixIcon: Icon(Icons.person_rounded),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: matCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Matrícula / Número de Control',
                    prefixIcon: Icon(Icons.badge_rounded),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: emailCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Correo Electrónico (Opcional)',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                ),
                if (existingRec?.hasNotes == true) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Evidencia actual: ${existingRec!.notes}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF6D28D9),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                const Text(
                  'Circunstancia / Motivo del Día:',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: reasons.map((r) {
                    return ChoiceChip(
                      label: Text(r, style: const TextStyle(fontSize: 11)),
                      selected: selectedReason == r,
                      onSelected: (_) =>
                          setDialogState(() => selectedReason = r),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: extraCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Detalle adicional de la circunstancia (Opcional)',
                  ),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: grantAttendance,
                  title: const Text(
                    'Registrar Asistencia y Evidencia del Día',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                  onChanged: (v) =>
                      setDialogState(() => grantAttendance = v ?? true),
                ),
                if (grantAttendance)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: grantAccredited,
                    title: const Text(
                      'Dejar ACREDITADO Hoy (Entrada + Salida OK)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onChanged: (v) =>
                        setDialogState(() => grantAccredited = v ?? true),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.verified_user_rounded, size: 17),
              label: const Text('Guardar y Dar Asistencia'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7C3AED),
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                final name = nameCtrl.text.trim();
                final mat = matCtrl.text.trim();
                final email = emailCtrl.text.trim();
                if (name.isEmpty || mat.isEmpty) return;

                Navigator.pop(ctx);
                if (grantAttendance) {
                  await provider.registerOrEditStudentWithoutPhone(
                    workshopId: workshop.id,
                    sessionId: session.id,
                    studentId: student?.id,
                    enrollmentNumber: mat,
                    fullName: name,
                    email: email,
                    circumstanceReason: selectedReason,
                    extraDetails: extraCtrl.text.trim(),
                    markEntry: true,
                    markAccredited: grantAccredited,
                  );
                } else if (student != null) {
                  await provider.updateStudentInWorkshop(
                    workshopId: workshop.id,
                    studentId: student.id,
                    enrollmentNumber: mat,
                    fullName: name,
                    email: email,
                  );
                } else {
                  await provider.addStudentToWorkshop(
                    workshopId: workshop.id,
                    enrollmentNumber: mat,
                    fullName: name,
                    email: email,
                  );
                }
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      '✅ Asistencia y evidencia actualizada para $name ($mat).',
                    ),
                    backgroundColor: AppTheme.accreditedColor,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeTag(
    String label,
    DateTime? time,
    IconData icon,
    Color color,
  ) {
    final local = time?.toLocal();
    final text = local != null
        ? '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}:${local.second.toString().padLeft(2, '0')}'
        : 'Pendiente';

    final hasTime = local != null;

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

  void _exportCsv(
    BuildContext context,
    Workshop workshop,
    WorkshopSession session,
  ) {
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
                'El reporte oficial de acreditaciones, puntualidad y notas de evidencia está listo:',
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
                    style: const TextStyle(
                      fontFamily: 'Consolas',
                      fontSize: 11,
                    ),
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
