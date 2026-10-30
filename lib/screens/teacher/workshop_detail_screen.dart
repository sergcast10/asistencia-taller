import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/workshop.dart';
import '../../models/session.dart';
import '../../models/student.dart';
import '../../models/attendance_record.dart';
import '../../providers/attendance_provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/pdf_exporter.dart';
import '../../widgets/session_evidence_dialog.dart';
import '../../widgets/student_status_badge.dart';
import 'live_session_screen.dart';
import 'session_report_screen.dart';

class WorkshopDetailScreen extends StatefulWidget {
  final String workshopId;

  const WorkshopDetailScreen({super.key, required this.workshopId});

  @override
  State<WorkshopDetailScreen> createState() => _WorkshopDetailScreenState();
}

class _WorkshopDetailScreenState extends State<WorkshopDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String? _selectedSessionIdForStudents;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncWorkshopData();
    });
  }

  Future<void> _syncWorkshopData() async {
    if (!mounted) return;
    final provider = context.read<AttendanceProvider>();
    await provider.syncWorkshopSessionsFromSupabase(widget.workshopId);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  WorkshopSession? _getCurrentOrTodaySession(Workshop workshop) {
    if (workshop.sessions.isEmpty) return null;
    if (_selectedSessionIdForStudents != null) {
      final found = workshop.sessions
          .where((s) => s.id == _selectedSessionIdForStudents)
          .firstOrNull;
      if (found != null) return found;
    }
    final active = workshop.sessions.where((s) => s.isQrActive).firstOrNull;
    return active ?? workshop.sessions.first;
  }

  String _formatShortTime(DateTime dt) {
    final l = dt.toLocal();
    return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
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
            title: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _showEditWorkshopDialog(context, provider, workshop),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        workshop.name,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(
                      Icons.edit_rounded,
                      size: 17,
                      color: AppTheme.primary,
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              IconButton(
                tooltip: 'Editar Título y Datos del Taller',
                icon: const Icon(
                  Icons.edit_note_rounded,
                  color: AppTheme.primary,
                ),
                onPressed: () =>
                    _showEditWorkshopDialog(context, provider, workshop),
              ),
              IconButton(
                tooltip: 'Sincronizar Alumnos y Asistencias con Supabase',
                icon: const Icon(
                  Icons.cloud_sync_rounded,
                  color: AppTheme.primary,
                ),
                onPressed: () async {
                  await _syncWorkshopData();
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        '☁️ Padrón de alumnos y asistencias sincronizado.',
                      ),
                      backgroundColor: AppTheme.accreditedColor,
                    ),
                  );
                },
              ),
              IconButton(
                tooltip: 'Eliminar este Taller',
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: AppTheme.absentColor,
                ),
                onPressed: () =>
                    _confirmDeleteWorkshop(context, provider, workshop),
              ),
              const SizedBox(width: 6),
            ],
            bottom: TabBar(
              controller: _tabController,
              labelColor: AppTheme.primary,
              unselectedLabelColor: AppTheme.slate600,
              indicatorColor: AppTheme.primary,
              tabs: [
                Tab(
                  icon: const Icon(Icons.calendar_month_rounded),
                  text: 'Sesiones (${workshop.sessions.length})',
                ),
                Tab(
                  icon: const Icon(Icons.people_outline_rounded),
                  text: 'Alumnos (${workshop.enrolledStudents.length})',
                ),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tabController,
            children: [
              // PESTAÑA 1: SESIONES
              _buildSessionsTab(context, provider, workshop),
              // PESTAÑA 2: ALUMNOS (EDICIÓN, INTEGRACIÓN Y ASISTENCIA SIN CELULAR)
              _buildStudentsTab(context, provider, workshop),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            icon: Icon(
              _tabController.index == 0
                  ? Icons.add_alarm_rounded
                  : Icons.phonelink_erase_rounded,
            ),
            label: Text(
              _tabController.index == 0
                  ? 'Nueva Sesión'
                  : 'Integrar / Sin Celular',
            ),
            backgroundColor: _tabController.index == 0
                ? AppTheme.primary
                : const Color(0xFF7C3AED),
            foregroundColor: Colors.white,
            onPressed: () {
              if (_tabController.index == 0) {
                _showCreateSessionDialog(context, provider, workshop);
              } else {
                _showEditOrNoPhoneAttendanceDialog(
                  context,
                  provider,
                  workshop,
                  student: null,
                  defaultNoPhoneMode: true,
                );
              }
            },
          ),
        );
      },
    );
  }

  Widget _buildSessionsTab(
    BuildContext context,
    AttendanceProvider provider,
    Workshop workshop,
  ) {
    if (workshop.sessions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.event_busy_rounded,
              size: 48,
              color: AppTheme.slate600,
            ),
            const SizedBox(height: 12),
            const Text(
              'No hay sesiones programadas en este taller.',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppTheme.slate700,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.add_rounded),
              label: const Text('Crear Primera Sesión'),
              onPressed: () =>
                  _showCreateSessionDialog(context, provider, workshop),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 90),
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.primaryLight,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.primary.withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.edit_note_rounded,
                color: AppTheme.primary,
                size: 22,
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  '¿Quieres colocar el título y día de cada sesión (Sesión 1, 2, 3...)?',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.slate900,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                icon: const Icon(Icons.tune_rounded, size: 15),
                label: const Text(
                  'Preparar / Editar Títulos',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                ),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () =>
                    _showPrepareAllSessionsDialog(context, provider, workshop),
              ),
            ],
          ),
        ),
        ...List.generate(workshop.sessions.length, (index) {
          final session = workshop.sessions[index];
          final stats = provider.getSessionStats(workshop, session);

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => _showCreateSessionDialog(
                              context,
                              provider,
                              workshop,
                              existingSession: session,
                            ),
                            child: Row(
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
                                const SizedBox(width: 6),
                                const Icon(
                                  Icons.edit_rounded,
                                  size: 15,
                                  color: AppTheme.primary,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: session.isQrActive
                                ? AppTheme.accreditedBg
                                : AppTheme.slate100,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            session.phaseLabel,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: session.isQrActive
                                  ? AppTheme.accreditedColor
                                  : AppTheme.slate700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          tooltip: 'Eliminar esta sesión',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            size: 18,
                            color: AppTheme.slate600,
                          ),
                          onPressed: () {
                            provider.deleteSession(
                              workshopId: workshop.id,
                              sessionId: session.id,
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.slate50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.slate200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.calendar_today_rounded,
                                size: 14,
                                color: AppTheme.primary,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Día de realización: ${session.formattedDateWithDay}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.slate900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(
                                Icons.access_time_filled_rounded,
                                size: 14,
                                color: Color(0xFF059669),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Horario de Sesión: Comenzó ${session.startTimeLabel} hrs  ➔  Terminó ${session.endTimeLabel} hrs',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF065F46),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${session.executionEvidenceSummary} • Tolerancia: ${session.toleranceMinutes} min',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.slate600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _buildPill(
                          '✅ Cumplieron: ${stats.accredited}',
                          AppTheme.accreditedColor,
                          AppTheme.accreditedBg,
                        ),
                        _buildPill(
                          '⚠️ Faltó Salida: ${stats.incomplete}',
                          AppTheme.incompleteColor,
                          AppTheme.incompleteBg,
                        ),
                        _buildPill(
                          '❌ No Entraron: ${stats.absent}',
                          AppTheme.absentColor,
                          AppTheme.absentBg,
                        ),
                        _buildPill(
                          'Evidencias: ${stats.notesCount}',
                          const Color(0xFF6D28D9),
                          const Color(0xFFF5F3FF),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.end,
                      children: [
                        OutlinedButton.icon(
                          icon: const Icon(
                            Icons.edit_calendar_rounded,
                            size: 15,
                          ),
                          label: const Text('Editar Título / Día / Hora'),
                          onPressed: () => _showCreateSessionDialog(
                            context,
                            provider,
                            workshop,
                            existingSession: session,
                          ),
                        ),
                        OutlinedButton.icon(
                          icon: const Icon(
                            Icons.receipt_long_rounded,
                            size: 15,
                          ),
                          label: const Text('Evidencia / PDF'),
                          onPressed: () => _showSessionScheduleEvidenceDialog(
                            context,
                            workshop,
                            session,
                            stats,
                          ),
                        ),
                        OutlinedButton.icon(
                          icon: const Icon(
                            Icons.picture_as_pdf_rounded,
                            size: 15,
                            color: Color(0xFFDC2626),
                          ),
                          label: const Text('Descargar PDF'),
                          onPressed: () =>
                              PdfExporter.downloadOrShareSessionPdf(
                                context: context,
                                workshop: workshop,
                                session: session,
                              ),
                        ),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.fact_check_rounded, size: 16),
                          label: const Text('📋 Lista de Cierre / Asistidos'),
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
                        ElevatedButton.icon(
                          icon: const Icon(
                            Icons.qr_code_scanner_rounded,
                            size: 16,
                          ),
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
            ),
          );
        }),
      ],
    );
  }

  Widget _buildStudentsTab(
    BuildContext context,
    AttendanceProvider provider,
    Workshop workshop,
  ) {
    final currentSession = _getCurrentOrTodaySession(workshop);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 90),
      children: [
        // BANNER DE INTEGRACIÓN Y ASISTENCIA SIN CELULAR (OLVIDO / EXTRAVÍO)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F3FF),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFC4B5FD)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF7C3AED),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.phonelink_erase_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Control de Estudiantes, Edición y Registro sin Celular',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF4C1D95),
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Si un alumno no trae celular (por olvido, extravío o falta de dispositivo) o desea integrarse hoy al taller, puedes registrarlo o editarlo aquí para darle su asistencia con evidencia oficial.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF5B21B6),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  ElevatedButton.icon(
                    icon: const Icon(Icons.phonelink_erase_rounded, size: 17),
                    label: const Text(
                      '📵 Integrar / Dar Asistencia sin Celular',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7C3AED),
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => _showEditOrNoPhoneAttendanceDialog(
                      context,
                      provider,
                      workshop,
                      student: null,
                      defaultNoPhoneMode: true,
                    ),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.person_add_alt_1_rounded, size: 17),
                    label: const Text('➕ Inscribir Alumno al Padrón'),
                    onPressed: () =>
                        _showAddStudentDialog(context, provider, workshop),
                  ),
                  if (workshop.enrolledStudents.isNotEmpty) ...[
                    OutlinedButton.icon(
                      icon: const Icon(
                        Icons.phonelink_setup_rounded,
                        size: 17,
                        color: Color(0xFF0284C7),
                      ),
                      label: const Text(
                        '📱 Autorizar Nuevo Celular (Borrar Viejo)',
                        style: TextStyle(color: Color(0xFF0284C7)),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFF7DD3FC)),
                        backgroundColor: const Color(0xFFF0F9FF),
                      ),
                      onPressed: () => _showAuthorizeNewPhoneDialog(
                        context,
                        provider,
                        workshop,
                        student: null,
                      ),
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(
                        Icons.gavel_rounded,
                        size: 17,
                        color: Color(0xFFB91C1C),
                      ),
                      label: const Text(
                        '🚫 Suspender por Conducta',
                        style: TextStyle(color: Color(0xFFB91C1C)),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFFCA5A5)),
                        backgroundColor: const Color(0xFFFEF2F2),
                      ),
                      onPressed: () => _showSuspendStudentDialog(
                        context,
                        provider,
                        workshop,
                        student: null,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Padrón de Estudiantes (${workshop.enrolledStudents.length})',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppTheme.slate900,
              ),
            ),
            if (currentSession != null)
              Text(
                'Sesión activa: ${currentSession.title}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.slate600,
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),

        if (workshop.sessions.length > 1)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppTheme.primary.withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.event_note_rounded,
                  size: 20,
                  color: AppTheme.primary,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Asistencia de la Sesión:',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.slate800,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: currentSession?.id,
                      items: workshop.sessions.map((s) {
                        return DropdownMenuItem<String>(
                          value: s.id,
                          child: Text(
                            '${s.title} (${s.formattedShortDate})',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.primary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: (newId) {
                        if (newId != null) {
                          setState(() {
                            _selectedSessionIdForStudents = newId;
                          });
                        }
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),

        if (workshop.enrolledStudents.isEmpty)
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.slate200),
            ),
            child: Column(
              children: [
                const Icon(
                  Icons.people_alt_outlined,
                  size: 48,
                  color: AppTheme.slate600,
                ),
                const SizedBox(height: 12),
                const Text(
                  'No hay alumnos inscritos en este taller todavía.',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.slate700,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Puedes inscribir un alumno o registrarlo directamente sin celular si olvidó o extravió su dispositivo.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: AppTheme.slate600),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  icon: const Icon(Icons.phonelink_erase_rounded),
                  label: const Text(
                    'Integrar Alumno y Dar Asistencia sin Celular',
                  ),
                  onPressed: () => _showEditOrNoPhoneAttendanceDialog(
                    context,
                    provider,
                    workshop,
                    student: null,
                    defaultNoPhoneMode: true,
                  ),
                ),
              ],
            ),
          )
        else
          ...workshop.enrolledStudents.map((student) {
            final record = currentSession?.records[student.id];
            final status = record?.status ?? AttendanceStatus.absent;
            final isStudentSuspended =
                student.isSuspended || (record?.isSuspended == true);
            final suspensionReasonText =
                record?.suspensionReason ??
                student.suspensionReason ??
                'Comportamiento inapropiado reportado por el docente encargado.';

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isStudentSuspended
                    ? const Color(0xFFFFFBFB)
                    : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isStudentSuspended
                      ? const Color(0xFFFCA5A5)
                      : (status == AttendanceStatus.accredited
                            ? AppTheme.accreditedColor.withValues(alpha: 0.45)
                            : AppTheme.slate200),
                  width: isStudentSuspended ? 1.5 : 1.0,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: isStudentSuspended
                            ? const Color(0xFFFEE2E2)
                            : (status == AttendanceStatus.accredited
                                  ? AppTheme.accreditedBg
                                  : AppTheme.primaryLight),
                        child: Text(
                          student.fullName.isNotEmpty
                              ? student.fullName[0].toUpperCase()
                              : '?',
                          style: TextStyle(
                            color: isStudentSuspended
                                ? const Color(0xFFB91C1C)
                                : (status == AttendanceStatus.accredited
                                      ? AppTheme.accreditedColor
                                      : AppTheme.primary),
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    student.fullName,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15,
                                      color: isStudentSuspended
                                          ? const Color(0xFF991B1B)
                                          : AppTheme.slate900,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                InkWell(
                                  borderRadius: BorderRadius.circular(8),
                                  onTap: () =>
                                      _showEditOrNoPhoneAttendanceDialog(
                                        context,
                                        provider,
                                        workshop,
                                        student: student,
                                        defaultNoPhoneMode: false,
                                      ),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 7,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppTheme.slate100,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: AppTheme.slate200,
                                      ),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.edit_rounded,
                                          size: 12,
                                          color: AppTheme.primary,
                                        ),
                                        SizedBox(width: 4),
                                        Text(
                                          'Editar',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: AppTheme.primary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Matrícula / Control: ${student.enrollmentNumber} • ${student.email}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.slate600,
                              ),
                            ),
                            if (currentSession != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Hoy (${currentSession.title}): Entrada ${record?.checkInTime != null ? _formatShortTime(record!.checkInTime!) : "--:--"} • Salida ${record?.checkOutTime != null ? _formatShortTime(record!.checkOutTime!) : "--:--"}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.slate700,
                                ),
                              ),
                            ],
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(
                                  student.allowNewDevice
                                      ? Icons.phonelink_setup_rounded
                                      : Icons.smartphone_rounded,
                                  size: 13,
                                  color: student.allowNewDevice
                                      ? const Color(0xFF0284C7)
                                      : (student.boundDeviceId != null &&
                                                student
                                                    .boundDeviceId!
                                                    .isNotEmpty
                                            ? AppTheme.accreditedColor
                                            : AppTheme.slate600),
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    student.allowNewDevice
                                        ? '🔄 Nuevo celular autorizado por docente (Celular viejo ${student.previousDeviceId ?? ""} borrado • Esperando escaneo del nuevo)'
                                        : (student.boundDeviceId != null &&
                                                  student
                                                      .boundDeviceId!
                                                      .isNotEmpty
                                              ? '📱 Celular vinculado: ${student.boundDeviceId}${student.previousDeviceId != null && student.previousDeviceId!.isNotEmpty ? " (Anterior borrado: ${student.previousDeviceId})" : ""}'
                                              : '📱 Celular: Se vinculará automáticamente al escanear el QR'),
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: student.allowNewDevice
                                          ? const Color(0xFF0369A1)
                                          : (student.boundDeviceId != null &&
                                                    student
                                                        .boundDeviceId!
                                                        .isNotEmpty
                                                ? const Color(0xFF065F46)
                                                : AppTheme.slate600),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      StudentStatusBadge(
                        status: status,
                        isSuspended: isStudentSuspended,
                      ),
                    ],
                  ),

                  // Si el alumno fue SUSPENDIDO por comportamiento inapropiado
                  if (isStudentSuspended) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFFCA5A5)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.gavel_rounded,
                            size: 17,
                            color: Color(0xFFB91C1C),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '🚫 SUSPENDIDO POR CONDUCTA INAPROPIADA (Docente: ${workshop.instructorName})',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF991B1B),
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  'Razón del comportamiento: $suspensionReasonText',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF7F1D1D),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Si el alumno tiene nota de evidencia / circunstancia del día
                  if (record?.hasNotes == true) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F3FF),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFC4B5FD)),
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
                              'Evidencia del Día / Circunstancia: ${record!.notes}',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF4C1D95),
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Ver / Copiar Comprobante de Evidencia',
                            icon: const Icon(
                              Icons.receipt_long_rounded,
                              size: 18,
                              color: Color(0xFF6D28D9),
                            ),
                            onPressed: () => _showEvidenceReceiptDialog(
                              context,
                              workshop,
                              currentSession!,
                              student,
                              record,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const Divider(height: 20),

                  // BOTONES DE ACCIÓN DIRECTA PARA EL MAESTRO EN LA TARJETA DEL ESTUDIANTE
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (!isStudentSuspended)
                        ElevatedButton.icon(
                          icon: const Icon(
                            Icons.phonelink_erase_rounded,
                            size: 15,
                          ),
                          label: const Text(
                            '📵 Sin Celular / Dar Asistencia',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF7C3AED),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: () => _showEditOrNoPhoneAttendanceDialog(
                            context,
                            provider,
                            workshop,
                            student: student,
                            defaultNoPhoneMode: true,
                          ),
                        ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.edit_note_rounded, size: 16),
                        label: const Text(
                          '✏️ Editar Datos / Evidencia',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () => _showEditOrNoPhoneAttendanceDialog(
                          context,
                          provider,
                          workshop,
                          student: student,
                          defaultNoPhoneMode: false,
                        ),
                      ),
                      if (!isStudentSuspended &&
                          status != AttendanceStatus.accredited)
                        ElevatedButton.icon(
                          icon: const Icon(Icons.school_rounded, size: 15),
                          label: const Text(
                            '🎓 Acreditar Hoy',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.accreditedColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: () async {
                            var targetSession = _getCurrentOrTodaySession(
                              workshop,
                            );
                            targetSession ??= await provider.createSession(
                              workshopId: workshop.id,
                              title: 'Sesión 1: Práctica y Evaluación',
                              date: DateTime.now(),
                            );
                            if (targetSession == null) return;
                            await provider.accreditStudentDirectly(
                              workshopId: workshop.id,
                              sessionId: targetSession.id,
                              studentId: student.id,
                            );
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  '🎓 Asistencia acreditada hoy para ${student.fullName}.',
                                ),
                                backgroundColor: AppTheme.accreditedColor,
                              ),
                            );
                          },
                        ),
                      OutlinedButton.icon(
                        icon: const Icon(
                          Icons.phonelink_setup_rounded,
                          size: 15,
                          color: Color(0xFF0284C7),
                        ),
                        label: const Text(
                          '📱 Nuevo Celular (Borrar Viejo)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0284C7),
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFF7DD3FC)),
                          backgroundColor: const Color(0xFFF0F9FF),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () => _showAuthorizeNewPhoneDialog(
                          context,
                          provider,
                          workshop,
                          student: student,
                        ),
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(
                          Icons.gavel_rounded,
                          size: 15,
                          color: Color(0xFFB91C1C),
                        ),
                        label: Text(
                          isStudentSuspended
                              ? '✏️ Editar Razón Suspensión'
                              : '🚫 Suspender por Conducta',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFB91C1C),
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFFFCA5A5)),
                          backgroundColor: const Color(0xFFFEF2F2),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () => _showSuspendStudentDialog(
                          context,
                          provider,
                          workshop,
                          student: student,
                        ),
                      ),
                      if (isStudentSuspended)
                        OutlinedButton.icon(
                          icon: const Icon(
                            Icons.check_circle_outline_rounded,
                            size: 15,
                            color: AppTheme.accreditedColor,
                          ),
                          label: const Text(
                            '✅ Levantar Suspensión',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.accreditedColor,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                              color: AppTheme.accreditedColor.withValues(
                                alpha: 0.4,
                              ),
                            ),
                            backgroundColor: AppTheme.accreditedBg,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: () async {
                            await provider.liftStudentSuspension(
                              workshopId: workshop.id,
                              sessionId: currentSession?.id,
                              studentId: student.id,
                            );
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  '✅ Suspensión levantada para ${student.fullName}.',
                                ),
                                backgroundColor: AppTheme.accreditedColor,
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  /// Modal integral para:
  /// 1) Editar a un estudiante existente (como Juan Torres) o integrar a un nuevo alumno.
  /// 2) Otorgarle la asistencia directamente cuando NO tiene celular (por olvido, extravío, batería agotada, etc.).
  /// 3) Generar la evidencia oficial del día y de la circunstancia que pasó.
  void _showEditOrNoPhoneAttendanceDialog(
    BuildContext context,
    AttendanceProvider provider,
    Workshop workshop, {
    Student? student,
    bool defaultNoPhoneMode = true,
  }) {
    final currentSession = _getCurrentOrTodaySession(workshop);
    final existingRec = (student != null && currentSession != null)
        ? currentSession.records[student.id]
        : null;

    final nameCtrl = TextEditingController(text: student?.fullName ?? '');
    final matCtrl = TextEditingController(
      text: student?.enrollmentNumber ?? '',
    );
    final emailCtrl = TextEditingController(text: student?.email ?? '');

    String rawExistingNote = existingRec?.notes ?? '';
    if (rawExistingNote.contains('] ')) {
      rawExistingNote = rawExistingNote.split('] ').sublist(1).join('] ');
    }
    final extraNoteCtrl = TextEditingController(text: rawExistingNote);

    final reasons = <String>[
      '📵 Sin celular en este momento (Autorizado por docente)',
      '🏠 Olvido de celular en domicilio',
      '🔍 Extravío o robo de teléfono celular',
      '🔋 Celular descargado / sin batería',
      '🌐 Sin datos móviles / sin conexión a internet',
      '🆕 Integración presencial de alumno al taller hoy',
    ];

    String selectedReason = reasons.first;
    bool grantAttendanceToday =
        defaultNoPhoneMode || (existingRec?.hasCheckIn ?? false);
    bool grantFullAccreditation = true;

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
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
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
                      'Aquí puedes editar los datos del alumno, integrarlo al taller y otorgarle su asistencia aunque no tenga celular (por extravío, olvido o falla), dejando evidencia oficial del día y de la circunstancia.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF4C1D95)),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Selector rápido de alumno inscrito si se abrió desde el botón general
                  if (student == null &&
                      workshop.enrolledStudents.isNotEmpty) ...[
                    const Text(
                      'Seleccionar alumno inscrito (o escribe uno nuevo abajo):',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.slate800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: workshop.enrolledStudents.map((s) {
                        final isSelected =
                            matCtrl.text.trim().toUpperCase() ==
                            s.enrollmentNumber.trim().toUpperCase();
                        return ChoiceChip(
                          label: Text(
                            '${s.fullName} (${s.enrollmentNumber})',
                            style: const TextStyle(fontSize: 11),
                          ),
                          selected: isSelected,
                          onSelected: (_) {
                            setDialogState(() {
                              nameCtrl.text = s.fullName;
                              matCtrl.text = s.enrollmentNumber;
                              emailCtrl.text = s.email;
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 14),
                  ],

                  const Text(
                    '1. Datos del Estudiante (Editables):',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.slate800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nombre Completo del Alumno',
                      prefixIcon: Icon(Icons.person_rounded),
                      hintText: 'Ej. Juan Torres',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: matCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Número de Control / Matrícula',
                      prefixIcon: Icon(Icons.badge_rounded),
                      hintText: 'Ej. 16100182',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: emailCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Correo Electrónico (Opcional)',
                      prefixIcon: Icon(Icons.email_outlined),
                      hintText: 'alumno@institucion.edu.mx',
                    ),
                  ),
                  const SizedBox(height: 16),

                  const Text(
                    '2. Circunstancia del Día (Sin Celular / Extravío / Olvido / Integración):',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.slate800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: reasons.map((r) {
                      final selected = selectedReason == r;
                      return ChoiceChip(
                        label: Text(r, style: const TextStyle(fontSize: 11)),
                        selected: selected,
                        selectedColor: const Color(0xFFEDE9FE),
                        onSelected: (_) {
                          setDialogState(() {
                            selectedReason = r;
                            grantAttendanceToday = true;
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: extraNoteCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Observaciones adicionales de la evidencia (Opcional)',
                      hintText: 'Ej. El alumno avisó al inicio de la sesión que extravió su celular...',
                    ),
                  ),
                  const SizedBox(height: 12),

                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text(
                      'Otorgar Asistencia del Día de Hoy y Guardar Evidencia',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: const Text(
                      'Registra la asistencia sin necesidad de que el alumno escanee el QR',
                      style: TextStyle(fontSize: 11),
                    ),
                    value: grantAttendanceToday,
                    onChanged: (v) =>
                        setDialogState(() => grantAttendanceToday = v),
                  ),
                  if (grantAttendanceToday)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: const Text(
                        'Acreditar Sesión Completa Hoy (Entrada + Salida OK)',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: const Text(
                        'El alumno queda como ACREDITADO hoy con su folio de evidencia',
                        style: TextStyle(fontSize: 11),
                      ),
                      value: grantFullAccreditation,
                      onChanged: (v) =>
                          setDialogState(() => grantFullAccreditation = v),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.verified_user_rounded, size: 18),
              label: Text(
                grantAttendanceToday
                    ? 'Guardar, Dar Asistencia y Generar Evidencia'
                    : 'Guardar Cambios del Alumno',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7C3AED),
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                final name = nameCtrl.text.trim();
                final mat = matCtrl.text.trim();
                final email = emailCtrl.text.trim();

                if (name.isEmpty || mat.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Por favor ingresa el Nombre y Número de Control / Matrícula.',
                      ),
                      backgroundColor: AppTheme.absentColor,
                    ),
                  );
                  return;
                }

                Navigator.pop(ctx);

                if (grantAttendanceToday) {
                  final rec = await provider.registerOrEditStudentWithoutPhone(
                    workshopId: workshop.id,
                    sessionId: currentSession?.id,
                    studentId: student?.id,
                    enrollmentNumber: mat,
                    fullName: name,
                    email: email,
                    circumstanceReason: selectedReason,
                    extraDetails: extraNoteCtrl.text.trim(),
                    markEntry: true,
                    markAccredited: grantFullAccreditation,
                  );

                  if (!context.mounted) return;
                  final updatedSession = _getCurrentOrTodaySession(workshop);
                  final updatedStudent = workshop.enrolledStudents
                      .where(
                        (s) =>
                            s.id == student?.id ||
                            s.enrollmentNumber.toUpperCase() ==
                                mat.toUpperCase(),
                      )
                      .firstOrNull;

                  if (rec != null &&
                      updatedSession != null &&
                      updatedStudent != null) {
                    _showEvidenceReceiptDialog(
                      context,
                      workshop,
                      updatedSession,
                      updatedStudent,
                      rec,
                    );
                  }
                } else {
                  if (student != null) {
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
                        '✅ Datos de $name ($mat) actualizados correctamente.',
                      ),
                      backgroundColor: AppTheme.accreditedColor,
                    ),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showEvidenceReceiptDialog(
    BuildContext context,
    Workshop workshop,
    WorkshopSession session,
    Student student,
    AttendanceRecord record,
  ) {
    SessionEvidenceDialog.showStudentEvidence(
      context: context,
      workshop: workshop,
      session: session,
      student: student,
      record: record,
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
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: textCol,
        ),
      ),
    );
  }

  /// Permite al docente preparar y colocar el título, fecha y horario de CADA sesión existente (Sesión 1, Sesión 2, Sesión 3...) en una sola vista
  void _showPrepareAllSessionsDialog(
    BuildContext context,
    AttendanceProvider provider,
    Workshop workshop,
  ) {
    final now = DateTime.now();
    final tomorrow = now.add(const Duration(days: 1));
    final dayAfterTomorrow = now.add(const Duration(days: 2));

    bool isSameDay(DateTime a, DateTime b) =>
        a.year == b.year && a.month == b.month && a.day == b.day;

    final List<WorkshopSession> sessionsRef = List.of(workshop.sessions);
    final List<TextEditingController> titleCtrls = sessionsRef
        .map((s) => TextEditingController(text: s.title))
        .toList();
    final List<DateTime> dates = sessionsRef.map((s) => s.date).toList();
    final List<TextEditingController> startCtrls = sessionsRef
        .map((s) => TextEditingController(text: s.startTimeLabel))
        .toList();
    final List<TextEditingController> endCtrls = sessionsRef
        .map((s) => TextEditingController(text: s.endTimeLabel))
        .toList();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.edit_note_rounded, color: AppTheme.primary),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Preparar Títulos, Días y Horarios de Cada Sesión',
                  style: TextStyle(fontSize: 15),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryLight,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'Aquí puedes escribir el título personalizado de cada sesión (Sesión 1, Sesión 2, Sesión 3...), así como elegir su fecha individual y horario.',
                      style: TextStyle(fontSize: 11, color: AppTheme.slate800),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...List.generate(titleCtrls.length, (idx) {
                    final d = dates[idx];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.slate50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.slate200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryLight,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'Sesión ${idx + 1}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.primary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '📅 ${WorkshopSession.formatSingleDateWithDay(d)}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.slate900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: titleCtrls[idx],
                            decoration: InputDecoration(
                              isDense: true,
                              labelText:
                                  'Título o Tema de la Sesión ${idx + 1}',
                              hintText:
                                  'Ej. Sesión ${idx + 1}: Introducción / Práctica...',
                              prefixIcon: const Icon(
                                Icons.title_rounded,
                                size: 18,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              ChoiceChip(
                                label: const Text(
                                  'Hoy',
                                  style: TextStyle(fontSize: 11),
                                ),
                                selected: isSameDay(d, now),
                                onSelected: (_) =>
                                    setDialogState(() => dates[idx] = now),
                              ),
                              ChoiceChip(
                                label: const Text(
                                  'Mañana',
                                  style: TextStyle(fontSize: 11),
                                ),
                                selected: isSameDay(d, tomorrow),
                                onSelected: (_) =>
                                    setDialogState(() => dates[idx] = tomorrow),
                              ),
                              ChoiceChip(
                                label: const Text(
                                  'Pasado Mañana',
                                  style: TextStyle(fontSize: 11),
                                ),
                                selected: isSameDay(d, dayAfterTomorrow),
                                onSelected: (_) => setDialogState(
                                  () => dates[idx] = dayAfterTomorrow,
                                ),
                              ),
                              OutlinedButton.icon(
                                icon: const Icon(
                                  Icons.edit_calendar_rounded,
                                  size: 14,
                                ),
                                label: const Text(
                                  'Cambiar Día',
                                  style: TextStyle(fontSize: 11),
                                ),
                                onPressed: () async {
                                  final picked = await showDatePicker(
                                    context: ctx,
                                    initialDate: d,
                                    firstDate: DateTime(2024),
                                    lastDate: DateTime(2030),
                                  );
                                  if (picked != null) {
                                    setDialogState(() => dates[idx] = picked);
                                  }
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: startCtrls[idx],
                                  decoration: InputDecoration(
                                    isDense: true,
                                    labelText: 'Hora Inicio Sesión ${idx + 1}',
                                    prefixIcon: const Icon(
                                      Icons.play_circle_outline,
                                      size: 17,
                                    ),
                                    suffixIcon: IconButton(
                                      tooltip: 'Elegir hora de inicio en reloj',
                                      icon: const Icon(
                                        Icons.access_time_rounded,
                                        size: 16,
                                      ),
                                      onPressed: () async {
                                        final t = await showTimePicker(
                                          context: ctx,
                                          initialTime: TimeOfDay.now(),
                                        );
                                        if (t != null) {
                                          setDialogState(() {
                                            startCtrls[idx].text =
                                                '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
                                          });
                                        }
                                      },
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: endCtrls[idx],
                                  decoration: InputDecoration(
                                    isDense: true,
                                    labelText: 'Hora Término Sesión ${idx + 1}',
                                    prefixIcon: const Icon(
                                      Icons.stop_circle_outlined,
                                      size: 17,
                                    ),
                                    suffixIcon: IconButton(
                                      tooltip:
                                          'Elegir hora de término en reloj',
                                      icon: const Icon(
                                        Icons.access_time_rounded,
                                        size: 16,
                                      ),
                                      onPressed: () async {
                                        final t = await showTimePicker(
                                          context: ctx,
                                          initialTime: TimeOfDay.fromDateTime(
                                            DateTime.now().add(
                                              const Duration(hours: 2),
                                            ),
                                          ),
                                        );
                                        if (t != null) {
                                          setDialogState(() {
                                            endCtrls[idx].text =
                                                '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
                                          });
                                        }
                                      },
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.save_rounded, size: 18),
              label: const Text('Guardar Todos los Títulos y Días'),
              onPressed: () async {
                for (int i = 0; i < sessionsRef.length; i++) {
                  final s = sessionsRef[i];
                  final newTitle = titleCtrls[i].text.trim().isNotEmpty
                      ? titleCtrls[i].text.trim()
                      : 'Sesión ${i + 1}';
                  final newDate = dates[i];
                  final newStart = startCtrls[i].text.trim().isNotEmpty
                      ? startCtrls[i].text.trim()
                      : s.startTimeLabel;
                  final newEnd = endCtrls[i].text.trim().isNotEmpty
                      ? endCtrls[i].text.trim()
                      : s.endTimeLabel;

                  await provider.updateSessionSchedule(
                    workshopId: workshop.id,
                    sessionId: s.id,
                    title: newTitle,
                    date: newDate,
                    impartedDaysLabel: WorkshopSession.formatSingleDateWithDay(
                      newDate,
                    ),
                    startTimeLabel: newStart,
                    endTimeLabel: newEnd,
                    toleranceMinutes: s.toleranceMinutes,
                  );
                }
                if (ctx.mounted) Navigator.pop(ctx);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        '✅ Títulos, fechas y horarios de las sesiones actualizados.',
                      ),
                      backgroundColor: AppTheme.accreditedColor,
                    ),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showCreateSessionDialog(
    BuildContext context,
    AttendanceProvider provider,
    Workshop workshop, {
    WorkshopSession? existingSession,
  }) {
    final now = DateTime.now();
    final tomorrow = now.add(const Duration(days: 1));
    final dayAfterTomorrow = now.add(const Duration(days: 2));

    final defaultStart =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final endDt = now.add(const Duration(hours: 2));
    final defaultEnd =
        '${endDt.hour.toString().padLeft(2, '0')}:${endDt.minute.toString().padLeft(2, '0')}';

    final nextSessionNumber = workshop.sessions.length + 1;

    String suggestedTitleFor(int sessionNum) {
      const topics = [
        'Introducción y Teoría',
        'Práctica Guiada',
        'Desarrollo de Proyecto',
        'Evaluación y Cierre',
      ];
      final t = topics[(sessionNum - 1) % topics.length];
      return 'Sesión $sessionNum: $t';
    }

    final tolCtrl = TextEditingController(
      text: '${existingSession?.toleranceMinutes ?? 15}',
    );

    // Cada sesión tiene SU PROPIO título editable, SU PROPIO día único y SU PROPIO horario (inicio y término)
    DateTime selectedDate = existingSession?.date ?? now;
    final List<DateTime> sessionDates = [selectedDate];
    final List<TextEditingController> sessionTitleCtrls = [
      TextEditingController(
        text: existingSession?.title ?? suggestedTitleFor(nextSessionNumber),
      ),
    ];
    final List<TextEditingController> sessionStartCtrls = [
      TextEditingController(
        text: existingSession?.startTimeLabel ?? defaultStart,
      ),
    ];
    final List<TextEditingController> sessionEndCtrls = [
      TextEditingController(text: existingSession?.endTimeLabel ?? defaultEnd),
    ];

    bool isSameDay(DateTime a, DateTime b) =>
        a.year == b.year && a.month == b.month && a.day == b.day;

    Future<void> pickTimeForCtrl(
      BuildContext ctx,
      TextEditingController ctrl,
      void Function(void Function()) setDialogState,
    ) async {
      final parts = ctrl.text.trim().split(':');
      final initialHour = parts.isNotEmpty
          ? (int.tryParse(parts[0]) ?? now.hour)
          : now.hour;
      final initialMinute = parts.length > 1
          ? (int.tryParse(parts[1]) ?? 0)
          : 0;
      final picked = await showTimePicker(
        context: ctx,
        initialTime: TimeOfDay(
          hour: initialHour.clamp(0, 23),
          minute: initialMinute.clamp(0, 59),
        ),
      );
      if (picked != null) {
        setDialogState(() {
          ctrl.text =
              '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
        });
      }
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: Row(
              children: [
                const Icon(
                  Icons.event_available_rounded,
                  color: AppTheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    existingSession != null
                        ? 'Editar Título, Día y Horario de Sesión'
                        : 'Preparar Nueva(s) Sesión(es) (Título, Día y Horario)',
                    style: const TextStyle(fontSize: 15),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 500,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryLight,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        existingSession != null
                            ? 'Escribe el título personalizado de esta sesión, selecciona la fecha en que se impartirá y su hora de inicio y término.'
                            : 'Cada sección/sesión cuenta con su propio título personalizado, su propia fecha y su propia hora de inicio y término.',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.slate800,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      existingSession != null
                          ? '1. 📝 Título, Fecha y Horario de esta Sesión:'
                          : '1. 📝 Preparar Título, Fecha y Horario Individual de cada Sesión:',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Lista de sesiones a crear o la sesión única que se está editando
                    ...List.generate(
                      existingSession != null ? 1 : sessionDates.length,
                      (idx) {
                        final d = existingSession != null
                            ? selectedDate
                            : sessionDates[idx];
                        final sessionNum = nextSessionNumber + idx;
                        final sessionNumLabel = existingSession != null
                            ? 'Sesión actual'
                            : 'Sesión $sessionNum';
                        final sStartCtrl = sessionStartCtrls[idx];
                        final sEndCtrl = sessionEndCtrls[idx];

                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.slate50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppTheme.slate200),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppTheme.primaryLight,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      sessionNumLabel,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        color: AppTheme.primary,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      '📅 ${WorkshopSession.formatSingleDateWithDay(d)}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                        color: AppTheme.slate900,
                                      ),
                                    ),
                                  ),
                                  if (existingSession == null &&
                                      sessionDates.length > 1)
                                    IconButton(
                                      tooltip: 'Quitar esta sesión',
                                      visualDensity: VisualDensity.compact,
                                      icon: const Icon(
                                        Icons.close_rounded,
                                        size: 16,
                                        color: AppTheme.absentColor,
                                      ),
                                      onPressed: () {
                                        setDialogState(() {
                                          sessionDates.removeAt(idx);
                                          sessionTitleCtrls.removeAt(idx);
                                          sessionStartCtrls.removeAt(idx);
                                          sessionEndCtrls.removeAt(idx);
                                          selectedDate = sessionDates.first;
                                        });
                                      },
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: sessionTitleCtrls[idx],
                                decoration: InputDecoration(
                                  isDense: true,
                                  labelText: existingSession != null
                                      ? 'Título de esta Sesión'
                                      : 'Título de la Sesión $sessionNum',
                                  hintText:
                                      'Ej. Sesión $sessionNum: Tema de este día',
                                  prefixIcon: const Icon(
                                    Icons.edit_note_rounded,
                                    size: 18,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  ChoiceChip(
                                    label: const Text(
                                      'Hoy',
                                      style: TextStyle(fontSize: 11),
                                    ),
                                    selected: isSameDay(d, now),
                                    onSelected: (_) {
                                      setDialogState(() {
                                        if (existingSession != null) {
                                          selectedDate = now;
                                        } else {
                                          sessionDates[idx] = now;
                                          selectedDate = sessionDates.first;
                                        }
                                      });
                                    },
                                  ),
                                  ChoiceChip(
                                    label: const Text(
                                      'Mañana',
                                      style: TextStyle(fontSize: 11),
                                    ),
                                    selected: isSameDay(d, tomorrow),
                                    onSelected: (_) {
                                      setDialogState(() {
                                        if (existingSession != null) {
                                          selectedDate = tomorrow;
                                        } else {
                                          sessionDates[idx] = tomorrow;
                                          selectedDate = sessionDates.first;
                                        }
                                      });
                                    },
                                  ),
                                  ChoiceChip(
                                    label: const Text(
                                      'Pasado Mañana',
                                      style: TextStyle(fontSize: 11),
                                    ),
                                    selected: isSameDay(d, dayAfterTomorrow),
                                    onSelected: (_) {
                                      setDialogState(() {
                                        if (existingSession != null) {
                                          selectedDate = dayAfterTomorrow;
                                        } else {
                                          sessionDates[idx] = dayAfterTomorrow;
                                          selectedDate = sessionDates.first;
                                        }
                                      });
                                    },
                                  ),
                                  OutlinedButton.icon(
                                    icon: const Icon(
                                      Icons.edit_calendar_rounded,
                                      size: 14,
                                    ),
                                    label: const Text(
                                      'Elegir en Calendario',
                                      style: TextStyle(fontSize: 11),
                                    ),
                                    onPressed: () async {
                                      final picked = await showDatePicker(
                                        context: ctx,
                                        initialDate: d,
                                        firstDate: DateTime(2024),
                                        lastDate: DateTime(2030),
                                      );
                                      if (picked != null) {
                                        setDialogState(() {
                                          if (existingSession != null) {
                                            selectedDate = picked;
                                          } else {
                                            sessionDates[idx] = picked;
                                            selectedDate = sessionDates.first;
                                          }
                                        });
                                      }
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: sStartCtrl,
                                      decoration: InputDecoration(
                                        isDense: true,
                                        labelText: existingSession != null
                                            ? 'Hora de Inicio'
                                            : 'Inicio Sesión $sessionNum',
                                        hintText: '09:00',
                                        prefixIcon: const Icon(
                                          Icons.play_circle_outline,
                                          size: 17,
                                        ),
                                        suffixIcon: IconButton(
                                          tooltip: 'Seleccionar en reloj',
                                          icon: const Icon(
                                            Icons.schedule_rounded,
                                            size: 16,
                                          ),
                                          onPressed: () => pickTimeForCtrl(
                                            ctx,
                                            sStartCtrl,
                                            setDialogState,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: TextField(
                                      controller: sEndCtrl,
                                      decoration: InputDecoration(
                                        isDense: true,
                                        labelText: existingSession != null
                                            ? 'Hora de Término'
                                            : 'Término Sesión $sessionNum',
                                        hintText: '11:00',
                                        prefixIcon: const Icon(
                                          Icons.stop_circle_outlined,
                                          size: 17,
                                        ),
                                        suffixIcon: IconButton(
                                          tooltip: 'Seleccionar en reloj',
                                          icon: const Icon(
                                            Icons.schedule_rounded,
                                            size: 16,
                                          ),
                                          onPressed: () => pickTimeForCtrl(
                                            ctx,
                                            sEndCtrl,
                                            setDialogState,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),

                    if (existingSession == null) ...[
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          OutlinedButton.icon(
                            icon: const Icon(
                              Icons.add_circle_outline,
                              size: 15,
                            ),
                            label: Text(
                              '➕ Agregar Otra Sesión (Sesión ${nextSessionNumber + sessionDates.length})',
                              style: const TextStyle(fontSize: 11),
                            ),
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: ctx,
                                initialDate: sessionDates.last.add(
                                  const Duration(days: 1),
                                ),
                                firstDate: DateTime(2024),
                                lastDate: DateTime(2030),
                              );
                              if (picked != null) {
                                setDialogState(() {
                                  final prevStart = sessionStartCtrls.isNotEmpty
                                      ? sessionStartCtrls.last.text
                                      : defaultStart;
                                  final prevEnd = sessionEndCtrls.isNotEmpty
                                      ? sessionEndCtrls.last.text
                                      : defaultEnd;
                                  sessionDates.add(picked);
                                  sessionTitleCtrls.add(
                                    TextEditingController(
                                      text: suggestedTitleFor(
                                        nextSessionNumber +
                                            sessionDates.length -
                                            1,
                                      ),
                                    ),
                                  );
                                  sessionStartCtrls.add(
                                    TextEditingController(text: prevStart),
                                  );
                                  sessionEndCtrls.add(
                                    TextEditingController(text: prevEnd),
                                  );
                                });
                              }
                            },
                          ),
                          OutlinedButton.icon(
                            icon: const Icon(
                              Icons.date_range_rounded,
                              size: 15,
                            ),
                            label: const Text(
                              '📆 Rango de Días (1 Sesión por Día)',
                              style: TextStyle(fontSize: 11),
                            ),
                            onPressed: () async {
                              final range = await showDateRangePicker(
                                context: ctx,
                                firstDate: DateTime(2024),
                                lastDate: DateTime(2030),
                                initialDateRange: DateTimeRange(
                                  start: sessionDates.first,
                                  end: sessionDates.first.add(
                                    const Duration(days: 2),
                                  ),
                                ),
                              );
                              if (range != null) {
                                setDialogState(() {
                                  final baseStart = sessionStartCtrls.isNotEmpty
                                      ? sessionStartCtrls.first.text
                                      : defaultStart;
                                  final baseEnd = sessionEndCtrls.isNotEmpty
                                      ? sessionEndCtrls.first.text
                                      : defaultEnd;
                                  sessionDates.clear();
                                  sessionTitleCtrls.clear();
                                  sessionStartCtrls.clear();
                                  sessionEndCtrls.clear();
                                  var cur = range.start;
                                  int safety = 0;
                                  while (!cur.isAfter(range.end) &&
                                      safety < 15) {
                                    sessionDates.add(cur);
                                    sessionTitleCtrls.add(
                                      TextEditingController(
                                        text: suggestedTitleFor(
                                          nextSessionNumber +
                                              sessionDates.length -
                                              1,
                                        ),
                                      ),
                                    );
                                    sessionStartCtrls.add(
                                      TextEditingController(text: baseStart),
                                    );
                                    sessionEndCtrls.add(
                                      TextEditingController(text: baseEnd),
                                    );
                                    cur = cur.add(const Duration(days: 1));
                                    safety++;
                                  }
                                  selectedDate = sessionDates.first;
                                });
                              }
                            },
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: tolCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Tiempo de tolerancia puntual (minutos)',
                        prefixIcon: Icon(Icons.timer_outlined),
                        hintText: '15',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.save_rounded, size: 18),
                label: Text(
                  existingSession != null
                      ? 'Guardar Título, Día y Horario'
                      : (sessionDates.length > 1
                            ? 'Crear ${sessionDates.length} Sesiones Preparadas'
                            : 'Crear Sesión'),
                ),
                onPressed: () async {
                  final tol = int.tryParse(tolCtrl.text.trim()) ?? 15;

                  if (existingSession != null) {
                    final customTitle = sessionTitleCtrls.first.text.trim();
                    final startStr =
                        sessionStartCtrls.first.text.trim().isNotEmpty
                        ? sessionStartCtrls.first.text.trim()
                        : defaultStart;
                    final endStr = sessionEndCtrls.first.text.trim().isNotEmpty
                        ? sessionEndCtrls.first.text.trim()
                        : defaultEnd;
                    await provider.updateSessionSchedule(
                      workshopId: workshop.id,
                      sessionId: existingSession.id,
                      title: customTitle.isNotEmpty
                          ? customTitle
                          : existingSession.title,
                      date: selectedDate,
                      impartedDaysLabel:
                          WorkshopSession.formatSingleDateWithDay(selectedDate),
                      startTimeLabel: startStr,
                      endTimeLabel: endStr,
                      toleranceMinutes: tol,
                    );
                  } else {
                    for (int i = 0; i < sessionDates.length; i++) {
                      final d = sessionDates[i];
                      final singleDayStr =
                          WorkshopSession.formatSingleDateWithDay(d);
                      final customTitle = sessionTitleCtrls[i].text.trim();
                      final sessionTitle = customTitle.isNotEmpty
                          ? customTitle
                          : suggestedTitleFor(nextSessionNumber + i);
                      final startStr =
                          sessionStartCtrls[i].text.trim().isNotEmpty
                          ? sessionStartCtrls[i].text.trim()
                          : defaultStart;
                      final endStr = sessionEndCtrls[i].text.trim().isNotEmpty
                          ? sessionEndCtrls[i].text.trim()
                          : defaultEnd;
                      await provider.createSession(
                        workshopId: workshop.id,
                        title: sessionTitle,
                        date: d,
                        impartedDaysLabel: singleDayStr,
                        startTimeLabel: startStr,
                        endTimeLabel: endStr,
                        toleranceMinutes: tol,
                      );
                    }
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                },
              ),
            ],
          );
        },
      ),
    );
  }

  /// Permite editar el título, código, docente encargado y descripción del taller si el usuario se equivocó
  void _showEditWorkshopDialog(
    BuildContext context,
    AttendanceProvider provider,
    Workshop workshop,
  ) {
    final nameCtrl = TextEditingController(text: workshop.name);
    final codeCtrl = TextEditingController(text: workshop.code);
    final instructorCtrl = TextEditingController(text: workshop.instructorName);
    final descCtrl = TextEditingController(text: workshop.description);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.edit_note_rounded, color: AppTheme.primary),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Editar Título y Datos del Taller',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Si te equivocaste en el título del taller o en alguno de sus datos, puedes corregirlo aquí:',
                  style: TextStyle(fontSize: 12, color: AppTheme.slate600),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Título / Nombre del Taller',
                    prefixIcon: Icon(Icons.title_rounded),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: codeCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Código / Clave del Taller',
                    prefixIcon: Icon(Icons.qr_code_rounded),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: instructorCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Docente Encargado',
                    prefixIcon: Icon(Icons.person_rounded),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: descCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Descripción / Objetivo',
                    prefixIcon: Icon(Icons.description_outlined),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(
              Icons.delete_forever_rounded,
              color: AppTheme.absentColor,
              size: 16,
            ),
            label: const Text(
              'Eliminar Taller',
              style: TextStyle(color: AppTheme.absentColor),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _confirmDeleteWorkshop(context, provider, workshop);
            },
          ),
          const Spacer(),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.save_rounded, size: 16),
            label: const Text('Guardar Cambios'),
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              await provider.updateWorkshop(
                workshopId: workshop.id,
                name: nameCtrl.text.trim(),
                code: codeCtrl.text.trim(),
                instructorName: instructorCtrl.text.trim(),
                description: descCtrl.text.trim(),
              );
              if (ctx.mounted) Navigator.pop(ctx);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      '✅ Taller actualizado a "${nameCtrl.text.trim()}".',
                    ),
                    backgroundColor: AppTheme.accreditedColor,
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  void _confirmDeleteWorkshop(
    BuildContext context,
    AttendanceProvider provider,
    Workshop workshop,
  ) {
    final pinCtrl = TextEditingController();
    final bool isPinRequired = provider.isPinRequiredForSensitiveActions;
    String? pinError;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: AppTheme.absentColor, size: 28),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  '¿Eliminar este Taller?',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Estás a punto de eliminar permanentemente el taller "${workshop.name}" (${workshop.code}).',
                style: const TextStyle(fontSize: 13, color: AppTheme.slate800),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFCA5A5)),
                ),
                child: const Text(
                  '⚠️ Esta acción borrará todas sus sesiones y registros de asistencia tanto en la app como en la nube.',
                  style: TextStyle(
                    fontSize: 11,
                    color: Color(0xFF991B1B),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (isPinRequired) ...[
                const SizedBox(height: 14),
                const Text(
                  'Ingresa tu PIN Docente para confirmar (Por defecto: 1234):',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: pinCtrl,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'PIN Docente',
                    prefixIcon: const Icon(Icons.lock_rounded),
                    errorText: pinError,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.delete_forever_rounded, size: 18),
              label: const Text('Sí, Eliminar Taller'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.absentColor,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                if (isPinRequired) {
                  final inputPin = pinCtrl.text.trim();
                  if (!provider.verifyTeacherPin(inputPin)) {
                    setDialogState(() {
                      pinError = 'PIN incorrecto. Ingresa tu PIN de seguridad.';
                    });
                    return;
                  }
                }

                Navigator.pop(ctx);
                await provider.deleteWorkshop(workshop.id);

                if (context.mounted) {
                  Navigator.pop(context); // Regresa a la pantalla principal
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        '🗑️ Taller "${workshop.name}" eliminado correctamente.',
                      ),
                      backgroundColor: AppTheme.absentColor,
                    ),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Modal disciplinario para que el docente encargado pueda suspender a un alumno por comportamiento inapropiado y registrar la razón exacta
  void _showSuspendStudentDialog(
    BuildContext context,
    AttendanceProvider provider,
    Workshop workshop, {
    Student? student,
  }) {
    final currentSession = _getCurrentOrTodaySession(workshop);
    Student? selectedStudent =
        student ??
        (workshop.enrolledStudents.isNotEmpty
            ? workshop.enrolledStudents.first
            : null);

    final behaviorReasons = <String>[
      '🚫 Falta de respeto o conducta inapropiada hacia docente o compañeros',
      '⚠️ Incumplimiento de normas de seguridad o uso indebido de equipo',
      '🔊 Interrupción reiterada de la sesión del taller',
      '🚶 Abandono injustificado o desorden durante la práctica',
      '📵 Uso inapropiado de dispositivos o distracción grave en clase',
    ];

    String chosenCategory = behaviorReasons.first;
    final detailCtrl = TextEditingController(
      text: selectedStudent?.suspensionReason ?? '',
    );

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.gavel_rounded, color: Color(0xFFB91C1C)),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Suspender Alumno por Conducta Inapropiada',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF991B1B),
                  ),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFCA5A5)),
                    ),
                    child: Text(
                      'Docente encargado: ${workshop.instructorName}\nAl suspender al alumno por comportamiento inapropiado, su asistencia no será acreditada y la razón quedará asentada en el acta de cierre y en el PDF de evidencia.',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF7F1D1D),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (student == null &&
                      workshop.enrolledStudents.isNotEmpty) ...[
                    const Text(
                      '1. Selecciona al alumno a suspender:',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: workshop.enrolledStudents.map((s) {
                        final isSel = selectedStudent?.id == s.id;
                        return ChoiceChip(
                          label: Text(
                            '${s.fullName} (${s.enrollmentNumber})',
                            style: const TextStyle(fontSize: 11),
                          ),
                          selected: isSel,
                          selectedColor: const Color(0xFFFEE2E2),
                          onSelected: (_) {
                            setDialogState(() {
                              selectedStudent = s;
                              detailCtrl.text = s.suspensionReason ?? '';
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                  ] else if (selectedStudent != null) ...[
                    Text(
                      'Alumno: ${selectedStudent!.fullName} (${selectedStudent!.enrollmentNumber})',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.slate900,
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  const Text(
                    'Motivo / Tipo de conducta inapropiada:',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.slate800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: behaviorReasons.map((r) {
                      final sel = chosenCategory == r;
                      return ChoiceChip(
                        label: Text(r, style: const TextStyle(fontSize: 11)),
                        selected: sel,
                        selectedColor: const Color(0xFFFEE2E2),
                        onSelected: (_) {
                          setDialogState(() => chosenCategory = r);
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: detailCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Describe la razón exacta de su comportamiento (Obligatorio para evidencia)',
                      hintText: 'Ej. El alumno realizó comentarios inapropiados e interrumpió la práctica de laboratorio pese a las advertencias del docente...',
                      prefixIcon: Icon(
                        Icons.report_problem_rounded,
                        color: Color(0xFFB91C1C),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.gavel_rounded, size: 17),
              label: const Text('Aplicar Suspensión y Guardar Evidencia'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFB91C1C),
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                if (selectedStudent == null) return;
                final extraText = detailCtrl.text.trim();
                await provider.suspendStudentForBehavior(
                  workshopId: workshop.id,
                  sessionId: currentSession?.id,
                  studentId: selectedStudent!.id,
                  behaviorReason: chosenCategory,
                  extraDetails: extraText,
                );
                if (ctx.mounted) Navigator.pop(ctx);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        '🚫 Alumno ${selectedStudent!.fullName} suspendido por conducta inapropiada.',
                      ),
                      backgroundColor: const Color(0xFFB91C1C),
                    ),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showSessionScheduleEvidenceDialog(
    BuildContext context,
    Workshop workshop,
    WorkshopSession session,
    SessionStatistics stats,
  ) {
    SessionEvidenceDialog.showSessionEvidence(
      context: context,
      workshop: workshop,
      session: session,
    );
  }

  void _showAddStudentDialog(
    BuildContext context,
    AttendanceProvider provider,
    Workshop workshop,
  ) {
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
                decoration: const InputDecoration(
                  labelText: 'Nombre Completo',
                  hintText: 'Ej. Juan Torres',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: matCtrl,
                decoration: const InputDecoration(
                  labelText: 'Matrícula o Número de Control',
                  hintText: 'Ej. 16100182',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: emailCtrl,
                decoration: const InputDecoration(
                  labelText: 'Correo Electrónico',
                  hintText: 'alumno@universidad.edu',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              if (nameCtrl.text.trim().isNotEmpty &&
                  matCtrl.text.trim().isNotEmpty) {
                provider.addStudentToWorkshop(
                  workshopId: workshop.id,
                  enrollmentNumber: matCtrl.text.trim(),
                  fullName: nameCtrl.text.trim(),
                  email: emailCtrl.text.trim().isNotEmpty
                      ? emailCtrl.text.trim()
                      : '${matCtrl.text.trim().toLowerCase()}@universidad.edu',
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

  /// Modal para que el docente autorice a un alumno el uso de su NUEVO CELULAR y borre/desvincule automáticamente el CELULAR VIEJO
  void _showAuthorizeNewPhoneDialog(
    BuildContext context,
    AttendanceProvider provider,
    Workshop workshop, {
    Student? student,
  }) {
    final currentSession = _getCurrentOrTodaySession(workshop);
    Student? selectedStudent =
        student ??
        (workshop.enrolledStudents.isNotEmpty
            ? workshop.enrolledStudents.first
            : null);

    final newDeviceCtrl = TextEditingController();
    final reasonCtrl = TextEditingController(
      text: 'El alumno cambió de teléfono celular y solicitó actualizar su acceso.',
    );
    bool grantAttendanceToday = true;
    bool grantFullAccreditation = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final currentOldPhone =
              selectedStudent?.boundDeviceId ??
              selectedStudent?.previousDeviceId ??
              'Sin ID previo registrado';

          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.phonelink_setup_rounded, color: Color(0xFF0284C7)),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Autorizar Nuevo Celular y Borrar Celular Viejo',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0369A1),
                    ),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 500,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0F9FF),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF7DD3FC)),
                      ),
                      child: const Text(
                        '🔒 Si el alumno estrenó o cambió de celular, aquí puedes darle acceso con su nuevo dispositivo. El celular viejo quedará borrado y bloqueado permanentemente, y el nuevo celular tomará su lugar.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF0C4A6E),
                          height: 1.35,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    if (student == null &&
                        workshop.enrolledStudents.isNotEmpty) ...[
                      const Text(
                        '1. Selecciona al alumno que cambió de celular:',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: workshop.enrolledStudents.map((s) {
                          final isSel = selectedStudent?.id == s.id;
                          return ChoiceChip(
                            label: Text(
                              '${s.fullName} (${s.enrollmentNumber})',
                              style: const TextStyle(fontSize: 11),
                            ),
                            selected: isSel,
                            selectedColor: const Color(0xFFE0F2FE),
                            onSelected: (_) {
                              setDialogState(() {
                                selectedStudent = s;
                              });
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 12),
                    ] else if (selectedStudent != null) ...[
                      Text(
                        'Alumno: ${selectedStudent!.fullName} (${selectedStudent!.enrollmentNumber})',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.slate900,
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],

                    // Tarjeta mostrando el celular viejo que será eliminado
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFFCA5A5)),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.phonelink_erase_rounded,
                            color: Color(0xFFB91C1C),
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '🗑️ Celular Anterior que se Borrará:',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF991B1B),
                                  ),
                                ),
                                Text(
                                  currentOldPhone,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF7F1D1D),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    const Text(
                      '📱 ID del Nuevo Celular (Opcional):',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.slate800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: newDeviceCtrl,
                      decoration: const InputDecoration(
                        isDense: true,
                        labelText: 'Dejar vacío para vincular automáticamente al escanear QR',
                        hintText: 'O escribe el ID que muestra su nuevo celular (Ej. CEL-8F4A2C)',
                        prefixIcon: Icon(
                          Icons.smartphone_rounded,
                          color: Color(0xFF0284C7),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: reasonCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        isDense: true,
                        labelText: 'Motivo del cambio de celular (Evidencia)',
                        prefixIcon: Icon(Icons.notes_rounded),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: const Text(
                        'Otorgar también su asistencia del día de hoy',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: const Text(
                        'Registra su asistencia hoy y deja constancia del cambio de celular',
                        style: TextStyle(fontSize: 11),
                      ),
                      value: grantAttendanceToday,
                      onChanged: (v) =>
                          setDialogState(() => grantAttendanceToday = v),
                    ),
                    if (grantAttendanceToday)
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: const Text(
                          'Acreditar Sesión Completa Hoy (Entrada + Salida OK)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        value: grantFullAccreditation,
                        onChanged: (v) =>
                            setDialogState(() => grantFullAccreditation = v),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              ElevatedButton.icon(
                icon: const Icon(
                  Icons.published_with_changes_rounded,
                  size: 18,
                ),
                label: const Text('Borrar Viejo y Dar Acceso al Nuevo Celular'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0284C7),
                  foregroundColor: Colors.white,
                ),
                onPressed: () async {
                  if (selectedStudent == null) return;
                  await provider.authorizeNewStudentDevice(
                    workshopId: workshop.id,
                    sessionId: currentSession?.id,
                    studentId: selectedStudent!.id,
                    newDeviceId: newDeviceCtrl.text.trim(),
                    reason: reasonCtrl.text.trim(),
                    grantAttendanceToday: grantAttendanceToday,
                    grantFullAccreditation: grantFullAccreditation,
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          '📱 Celular viejo borrado para ${selectedStudent!.fullName}. Su nuevo celular ya tiene acceso autorizado.',
                        ),
                        backgroundColor: const Color(0xFF0284C7),
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
}
