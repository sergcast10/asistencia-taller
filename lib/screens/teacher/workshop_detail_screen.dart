import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/workshop.dart';
import '../../models/session.dart';
import '../../models/student.dart';
import '../../models/attendance_record.dart';
import '../../providers/attendance_provider.dart';
import '../../utils/app_theme.dart';
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
    await provider.syncAllActiveSessionsFromSupabase();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  WorkshopSession? _getCurrentOrTodaySession(Workshop workshop) {
    if (workshop.sessions.isEmpty) return null;
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
            title: Text(workshop.name),
            actions: [
              IconButton(
                tooltip: 'Sincronizar Alumnos y Asistencias con Supabase',
                icon: const Icon(Icons.cloud_sync_rounded, color: AppTheme.primary),
                onPressed: () async {
                  await _syncWorkshopData();
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('☁️ Padrón de alumnos y asistencias sincronizado.'),
                      backgroundColor: AppTheme.accreditedColor,
                    ),
                  );
                },
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
                      'Registrados Hoy: ${stats.registeredTodayCount}',
                      AppTheme.primary,
                      AppTheme.primaryLight,
                    ),
                    _buildPill(
                      'Acreditados: ${stats.accredited}',
                      AppTheme.accreditedColor,
                      AppTheme.accreditedBg,
                    ),
                    _buildPill(
                      'En Sala: ${stats.incomplete}',
                      AppTheme.incompleteColor,
                      AppTheme.incompleteBg,
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
                      icon: const Icon(Icons.edit_calendar_rounded, size: 15),
                      label: const Text('Editar Día / Hora'),
                      onPressed: () => _showCreateSessionDialog(
                        context,
                        provider,
                        workshop,
                        existingSession: session,
                      ),
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.receipt_long_rounded, size: 15),
                      label: const Text('Evidencia Sesión'),
                      onPressed: () => _showSessionScheduleEvidenceDialog(
                        context,
                        workshop,
                        session,
                        stats,
                      ),
                    ),
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

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: status == AttendanceStatus.accredited
                      ? AppTheme.accreditedColor.withValues(alpha: 0.45)
                      : AppTheme.slate200,
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
                        backgroundColor: status == AttendanceStatus.accredited
                            ? AppTheme.accreditedBg
                            : AppTheme.primaryLight,
                        child: Text(
                          student.fullName.isNotEmpty
                              ? student.fullName[0].toUpperCase()
                              : '?',
                          style: TextStyle(
                            color: status == AttendanceStatus.accredited
                                ? AppTheme.accreditedColor
                                : AppTheme.primary,
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
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15,
                                      color: AppTheme.slate900,
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
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      StudentStatusBadge(status: status),
                    ],
                  ),

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

                  // BOTONES DE ACCIÓN DIRECTA PARA EL MAESTRO EN LA TARJETA DEL ESTUDIANTE (EJ. JUAN TORRES)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
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
                      if (status != AttendanceStatus.accredited)
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
    final existingRec =
        (student != null && currentSession != null)
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
                  if (student == null && workshop.enrolledStudents.isNotEmpty) ...[
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
                      labelText:
                          'Observaciones adicionales de la evidencia (Opcional)',
                      hintText:
                          'Ej. El alumno avisó al inicio de la sesión que extravió su celular...',
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
                  final rec = await provider
                      .registerOrEditStudentWithoutPhone(
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
    final receiptText =
        '=== COMPROBANTE OFICIAL DE EVIDENCIA Y ASISTENCIA ===\n'
        'Taller: ${workshop.name} (${workshop.code})\n'
        'Sesión: ${session.title}\n'
        'Docente: ${workshop.instructorName}\n'
        'Alumno: ${student.fullName}\n'
        'Matrícula / Control: ${student.enrollmentNumber}\n'
        'Estatus Hoy: ${record.status == AttendanceStatus.accredited ? "ACREDITADO" : "ASISTENCIA EN SALA"}\n'
        'Circunstancia / Evidencia: ${record.notes ?? "Sin nota"}';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.verified_rounded, color: Color(0xFF7C3AED)),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Comprobante de Evidencia del Alumno',
                style: TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
        content: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F3FF),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFC4B5FD)),
          ),
          child: SelectableText(
            receiptText,
            style: const TextStyle(
              fontSize: 12,
              fontFamily: 'Consolas',
              color: Color(0xFF4C1D95),
              height: 1.4,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: const Text('Copiar Evidencia para el Alumno'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF7C3AED),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: receiptText));
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    '📋 Comprobante de evidencia copiado al portapapeles.',
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

  void _showCreateSessionDialog(
    BuildContext context,
    AttendanceProvider provider,
    Workshop workshop, {
    WorkshopSession? existingSession,
  }) {
    final now = DateTime.now();
    final defaultStart =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final endDt = now.add(const Duration(hours: 2));
    final defaultEnd =
        '${endDt.hour.toString().padLeft(2, '0')}:${endDt.minute.toString().padLeft(2, '0')}';

    final titleController = TextEditingController(
      text:
          existingSession?.title ??
          'Sesión ${workshop.sessions.length + 1}: Práctica y Evaluación',
    );
    final startCtrl = TextEditingController(
      text: existingSession?.startTimeLabel ?? defaultStart,
    );
    final endCtrl = TextEditingController(
      text: existingSession?.endTimeLabel ?? defaultEnd,
    );
    final tolCtrl = TextEditingController(
      text: '${existingSession?.toleranceMinutes ?? 15}',
    );
    DateTime selectedDate = existingSession?.date ?? now;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final dateLabel =
              '${selectedDate.day.toString().padLeft(2, '0')}/${selectedDate.month.toString().padLeft(2, '0')}/${selectedDate.year}';

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
                        ? 'Editar Día y Horario de Sesión'
                        : 'Crear Nueva Sesión con Evidencia de Horario',
                    style: const TextStyle(fontSize: 16),
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
                      color: AppTheme.primaryLight,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'Establece el día en que se realizará la sesión, la hora en que comienza y a qué hora termina para que quede evidencia oficial.',
                      style: TextStyle(fontSize: 11, color: AppTheme.slate800),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '1. Título o sección del taller:',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.title_rounded),
                      hintText: 'Ej. Sesión 1: Práctica y Evaluación',
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    '2. Día / Fecha en que se realizará la sesión:',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_month_rounded),
                    label: Text('📅 Fecha seleccionada: $dateLabel (Cambiar)'),
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: selectedDate,
                        firstDate: DateTime(2024),
                        lastDate: DateTime(2030),
                      );
                      if (picked != null) {
                        setDialogState(() {
                          selectedDate = picked;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    '3. Evidencia de Hora de Inicio y Hora de Término:',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: startCtrl,
                          decoration: InputDecoration(
                            labelText: 'Hora de Inicio',
                            hintText: '09:00',
                            prefixIcon: const Icon(Icons.play_circle_outline),
                            suffixIcon: IconButton(
                              tooltip: 'Seleccionar en reloj',
                              icon: const Icon(Icons.schedule_rounded, size: 18),
                              onPressed: () async {
                                final t = await showTimePicker(
                                  context: ctx,
                                  initialTime: TimeOfDay.now(),
                                );
                                if (t != null) {
                                  setDialogState(() {
                                    startCtrl.text =
                                        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
                                  });
                                }
                              },
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: endCtrl,
                          decoration: InputDecoration(
                            labelText: 'Hora de Término',
                            hintText: '11:00',
                            prefixIcon: const Icon(Icons.stop_circle_outlined),
                            suffixIcon: IconButton(
                              tooltip: 'Seleccionar en reloj',
                              icon: const Icon(Icons.schedule_rounded, size: 18),
                              onPressed: () async {
                                final t = await showTimePicker(
                                  context: ctx,
                                  initialTime: TimeOfDay.fromDateTime(
                                    DateTime.now().add(const Duration(hours: 2)),
                                  ),
                                );
                                if (t != null) {
                                  setDialogState(() {
                                    endCtrl.text =
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
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.save_rounded, size: 18),
                label: Text(
                  existingSession != null
                      ? 'Guardar Día y Horario'
                      : 'Crear Sesión con Horario',
                ),
                onPressed: () {
                  final title = titleController.text.trim();
                  if (title.isEmpty) return;
                  final startStr = startCtrl.text.trim().isNotEmpty
                      ? startCtrl.text.trim()
                      : defaultStart;
                  final endStr = endCtrl.text.trim().isNotEmpty
                      ? endCtrl.text.trim()
                      : defaultEnd;
                  final tol = int.tryParse(tolCtrl.text.trim()) ?? 15;

                  if (existingSession != null) {
                    provider.updateSessionSchedule(
                      workshopId: workshop.id,
                      sessionId: existingSession.id,
                      title: title,
                      date: selectedDate,
                      startTimeLabel: startStr,
                      endTimeLabel: endStr,
                      toleranceMinutes: tol,
                    );
                  } else {
                    provider.createSession(
                      workshopId: workshop.id,
                      title: title,
                      date: selectedDate,
                      startTimeLabel: startStr,
                      endTimeLabel: endStr,
                      toleranceMinutes: tol,
                    );
                  }
                  Navigator.pop(ctx);
                },
              ),
            ],
          );
        },
      ),
    );
  }

  void _showSessionScheduleEvidenceDialog(
    BuildContext context,
    Workshop workshop,
    WorkshopSession session,
    SessionStatistics stats,
  ) {
    final text =
        '=== ACTA Y EVIDENCIA OFICIAL DE SESIÓN DE TALLER ===\n'
        'Taller: ${workshop.name} (${workshop.code})\n'
        'Docente Responsable: ${workshop.instructorName}\n'
        'Sesión / Sección: ${session.title}\n'
        'Día de Realización: ${session.formattedDateWithDay}\n'
        'Hora en que Comenzó: ${session.startTimeLabel} hrs\n'
        'Hora en que Terminó: ${session.endTimeLabel} hrs\n'
        'Sello del Sistema: ${session.executionEvidenceSummary}\n'
        'Tolerancia de Puntualidad: ${session.toleranceMinutes} minutos\n'
        '----------------------------------------------------\n'
        'Alumnos Inscritos: ${stats.totalStudents}\n'
        'Asistencias Registradas Hoy: ${stats.registeredTodayCount}\n'
        'Alumnos Acreditados: ${stats.accredited}\n'
        'Notas / Evidencias de Alumnos: ${stats.notesCount}\n'
        '====================================================';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.verified_rounded, color: AppTheme.primary),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Evidencia de Día y Horario de Sesión',
                style: TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
        content: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.slate50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.slate200),
          ),
          child: SelectableText(
            text,
            style: const TextStyle(
              fontSize: 12,
              fontFamily: 'Consolas',
              color: AppTheme.slate900,
              height: 1.4,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: const Text('Copiar Acta de Evidencia'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: text));
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    '📋 Evidencia de día y horario de la sesión copiada al portapapeles.',
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
}
