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
import '../../widgets/dynamic_qr_display.dart';
import '../../widgets/simulated_scanner_dialog.dart';
import '../../widgets/student_status_badge.dart';
import 'session_report_screen.dart';
import 'teacher_qr_scanner_screen.dart';

class LiveSessionScreen extends StatefulWidget {
  final Workshop workshop;
  final WorkshopSession session;

  const LiveSessionScreen({
    super.key,
    required this.workshop,
    required this.session,
  });

  @override
  State<LiveSessionScreen> createState() => _LiveSessionScreenState();
}

class _LiveSessionScreenState extends State<LiveSessionScreen> {
  Timer? _liveTimer;
  int _ticks = 0;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncNow();
    });
    _liveTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _ticks++;
      // Actualizar cronómetro de tolerancia y cierre cada segundo
      setState(() {});

      // Verificar si se agotó la ventana de registro configurada por el docente
      final provider = context.read<AttendanceProvider>();
      final w = provider.workshops.firstWhere(
        (x) => x.id == widget.workshop.id,
        orElse: () => widget.workshop,
      );
      final s = w.sessions.firstWhere(
        (x) => x.id == widget.session.id,
        orElse: () => widget.session,
      );

      if (s.currentPhase == SessionPhase.entry &&
          s.isRegistrationWindowExpired) {
        provider.updateSessionPhase(
          workshopId: w.id,
          sessionId: s.id,
          newPhase: SessionPhase.inProgress,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                '⏰ Se agotó el tiempo límite de registro configurado por el docente. El pase de entrada se ha pausado automáticamente.',
              ),
              backgroundColor: AppTheme.incompleteColor,
              duration: Duration(seconds: 4),
            ),
          );
        }
      }

      // Sincronizar con Supabase cada 3 segundos automáticamente
      if (_ticks % 3 == 0 && !_isSyncing) {
        _syncNow(silent: true);
      }
    });
  }

  Future<void> _syncNow({bool silent = false}) async {
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
              '✅ Sincronizados $count registros del día de hoy desde Supabase',
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
    _liveTimer?.cancel();
    super.dispose();
  }

  static String _formatCountdown(int totalSeconds) {
    final mins = totalSeconds ~/ 60;
    final secs = totalSeconds % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  static String _formatShort(DateTime dt) {
    final local = dt.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
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
                tooltip: 'Sincronizar con Supabase Cloud',
                icon: const Icon(
                  Icons.cloud_sync_rounded,
                  color: AppTheme.accreditedColor,
                ),
                onPressed: () => _syncNow(silent: false),
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
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppTheme.slate600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // BARRA DE CONTROL DE FASES Y TIEMPO DE TOLERANCIA DEL DOCENTE
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
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Expanded(
                            child: Text(
                              'Control del Pase de Asistencia y Tolerancia',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.slate800,
                              ),
                            ),
                          ),
                          TextButton.icon(
                            icon: const Icon(Icons.timer_outlined, size: 16),
                            label: Text(
                              'Tolerancia: ${currentSession.toleranceMinutes}m • Cierre: ${currentSession.registrationWindowMinutes}m',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            onPressed: () => _showTimingsConfigDialog(
                              context,
                              provider,
                              currentWorkshop,
                              currentSession,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          // Botón 1: Pase de Entrada
                          ElevatedButton.icon(
                            icon: const Icon(Icons.login_rounded, size: 18),
                            label: const Text('1. Habilitar ENTRADA'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  currentSession.currentPhase ==
                                      SessionPhase.entry
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
                            icon: const Icon(
                              Icons.pause_circle_rounded,
                              size: 18,
                            ),
                            label: const Text('2. Pausar Pase (Clase)'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  currentSession.currentPhase ==
                                      SessionPhase.inProgress
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
                              backgroundColor:
                                  currentSession.currentPhase ==
                                      SessionPhase.exit
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

                      // Cronómetro en vivo de Tolerancia (ej. 15 min) y Cierre de Registro
                      const SizedBox(height: 14),
                      _buildToleranceAndTimerBanner(
                        context,
                        provider,
                        currentWorkshop,
                        currentSession,
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
                    padding: const EdgeInsets.all(32),
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
                          size: 56,
                          color: AppTheme.slate600,
                        ),
                        const SizedBox(height: 12),
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
                        const SizedBox(height: 6),
                        Text(
                          currentSession.currentPhase == SessionPhase.finished
                              ? 'Todos los registros han sido cerrados. Consulta la pantalla de Auditoría para ver o exportar el reporte.'
                              : 'Presiona "1. Habilitar ENTRADA" al iniciar o "3. Habilitar SALIDA" al finalizar para proyectar el código QR.',
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

                // MARCADOR Y ACCIONES DEL DOCENTE EN TIEMPO REAL
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    const Text(
                      'Asistencias y Acreditados de Hoy',
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
                          icon: const Icon(Icons.note_add_rounded, size: 17),
                          label: const Text('📝 Tomar Nota / Evidencia'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFD97706),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                          ),
                          onPressed: () => _showGeneralIncidentDialog(
                            context,
                            provider,
                            currentWorkshop,
                            currentSession,
                          ),
                        ),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.badge_rounded, size: 16),
                          label: const Text('⚡ Pase por Matrícula'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                          ),
                          onPressed: () => _showManualControlDialog(
                            context,
                            provider,
                            currentWorkshop,
                            currentSession,
                          ),
                        ),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.verified_rounded, size: 16),
                          label: const Text('🎓 Acreditar Registrados Hoy'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.accreditedColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
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
                                    count > 0
                                        ? '🎓 Se acreditaron $count alumnos registrados el día de hoy.'
                                        : 'No hay alumnos con entrada pendiente por acreditar.',
                                  ),
                                  backgroundColor: AppTheme.accreditedColor,
                                ),
                              );
                            }
                          },
                        ),
                        ElevatedButton.icon(
                          icon: const Icon(
                            Icons.qr_code_scanner_rounded,
                            size: 17,
                          ),
                          label: const Text('📷 Escanear QR'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.slate800,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
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
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Resumen rápido en tarjetas (Registrados Hoy, Acreditados Hoy, Retardos, Notas)
                Row(
                  children: [
                    Expanded(
                      child: _buildMiniIndicator(
                        'Registrados Hoy',
                        '${stats.registeredTodayCount} Alumnos',
                        Icons.how_to_reg_rounded,
                        AppTheme.primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildMiniIndicator(
                        'Acreditados Hoy',
                        '${stats.accredited} Alumnos',
                        Icons.verified_rounded,
                        AppTheme.accreditedColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _buildMiniIndicator(
                        'Con Retraso (+${currentSession.toleranceMinutes}m)',
                        '${stats.lateCount} Alumnos',
                        Icons.access_time_filled_rounded,
                        const Color(0xFFD97706),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildMiniIndicator(
                        'Con Nota / Evidencia',
                        '${stats.notesCount} Alumnos',
                        Icons.assignment_late_rounded,
                        const Color(0xFF7C3AED),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // Lista de alumnos con su estado, retardo y nota de evidencia en esta sesión
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.slate200),
                  ),
                  child: currentWorkshop.enrolledStudents.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(28),
                          child: Column(
                            children: [
                              const Icon(
                                Icons.people_outline_rounded,
                                size: 42,
                                color: AppTheme.slate600,
                              ),
                              const SizedBox(height: 10),
                              const Text(
                                'Aún no hay alumnos registrados en esta sesión',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                  color: AppTheme.slate800,
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'En cuanto un alumno escanee el QR desde su celular o lo registres por matrícula/nota, aparecerá aquí automáticamente.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.slate600,
                                ),
                              ),
                              const SizedBox(height: 14),
                              OutlinedButton.icon(
                                icon: const Icon(Icons.cloud_sync_rounded),
                                label: const Text(
                                  'Buscar Registros en Supabase Ahora',
                                ),
                                onPressed: () => _syncNow(silent: false),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: currentWorkshop.enrolledStudents.length,
                          separatorBuilder: (_, index) => const Divider(
                            height: 1,
                            color: AppTheme.slate200,
                          ),
                          itemBuilder: (context, index) {
                            final student =
                                currentWorkshop.enrolledStudents[index];
                            final record = currentSession.records[student.id];
                            final status =
                                record?.status ?? AttendanceStatus.absent;

                            return InkWell(
                              onTap: () => _showStudentActionSheet(
                                context,
                                provider,
                                currentWorkshop,
                                currentSession,
                                student,
                                record,
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        CircleAvatar(
                                          backgroundColor:
                                              status ==
                                                  AttendanceStatus.accredited
                                              ? AppTheme.accreditedBg
                                              : AppTheme.slate100,
                                          child: Text(
                                            student.fullName.isNotEmpty
                                                ? student.fullName[0]
                                                      .toUpperCase()
                                                : '?',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w800,
                                              color:
                                                  status ==
                                                      AttendanceStatus
                                                          .accredited
                                                  ? AppTheme.accreditedColor
                                                  : AppTheme.slate800,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
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
                                                        fontWeight:
                                                            FontWeight.w800,
                                                        fontSize: 14,
                                                        color:
                                                            AppTheme.slate900,
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
                                              const SizedBox(height: 3),
                                              Text(
                                                'Mat: ${student.enrollmentNumber} • Ent: ${record?.checkInTime != null ? _formatShort(record!.checkInTime!) : "--:--"} • Sal: ${record?.checkOutTime != null ? _formatShort(record!.checkOutTime!) : "--:--"}${record?.isLocked == true ? " 🔒" : ""}',
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  color: AppTheme.slate600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        IconButton(
                                          tooltip:
                                              'Tomar Nota / Evidencia del Alumno',
                                          icon: Icon(
                                            record?.hasNotes == true
                                                ? Icons.assignment_turned_in_rounded
                                                : Icons.note_add_outlined,
                                            color: record?.hasNotes == true
                                                ? const Color(0xFF7C3AED)
                                                : AppTheme.slate600,
                                            size: 20,
                                          ),
                                          onPressed: () =>
                                              _showStudentNoteDialog(
                                                context,
                                                provider,
                                                currentWorkshop,
                                                currentSession,
                                                student,
                                                record,
                                              ),
                                        ),
                                        StudentStatusBadge(status: status),
                                      ],
                                    ),
                                    if (record?.hasNotes == true) ...[
                                      const SizedBox(height: 8),
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 8,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF5F3FF),
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          border: Border.all(
                                            color: const Color(0xFFC4B5FD),
                                          ),
                                        ),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
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
                                          ],
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
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

  Widget _buildToleranceAndTimerBanner(
    BuildContext context,
    AttendanceProvider provider,
    Workshop workshop,
    WorkshopSession session,
  ) {
    final isEntry = session.currentPhase == SessionPhase.entry;
    final isActive = session.isQrActive;
    final pastTol = session.isPastTolerance;
    final tolSec = session.remainingToleranceSeconds;
    final winSec = session.remainingWindowSeconds;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: !isActive
            ? AppTheme.slate100
            : (pastTol ? const Color(0xFFFEF3C7) : const Color(0xFFECFDF5)),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: !isActive
              ? AppTheme.slate200
              : (pastTol ? const Color(0xFFF59E0B) : const Color(0xFF10B981)),
        ),
      ),
      child: Row(
        children: [
          Icon(
            !isActive
                ? Icons.timer_off_outlined
                : (pastTol
                      ? Icons.warning_amber_rounded
                      : Icons.check_circle_outline_rounded),
            color: !isActive
                ? AppTheme.slate600
                : (pastTol
                      ? const Color(0xFFB45309)
                      : const Color(0xFF059669)),
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  !isActive
                      ? 'Configuración lista: ${session.toleranceMinutes} min de tolerancia puntual • ${session.registrationWindowMinutes} min de ventana total'
                      : (isEntry
                            ? (pastTol
                                  ? '🟠 Tolerancia de ${session.toleranceMinutes} min agotada • Registros actuales entran con RETRASO'
                                  : '🟢 Tolerancia Puntual Activa (${session.toleranceMinutes} min): Restan ${_formatCountdown(tolSec)}')
                            : '🔵 Pase de Salida Activo'),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: !isActive
                        ? AppTheme.slate800
                        : (pastTol
                              ? const Color(0xFF92400E)
                              : const Color(0xFF065F46)),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  !isActive
                      ? 'Al activar "1. Habilitar ENTRADA" iniciará la cuenta regresiva automáticamente.'
                      : '⏳ Tiempo límite para cierre automático de registro: ${_formatCountdown(winSec)}',
                  style: TextStyle(
                    fontSize: 11,
                    color: !isActive
                        ? AppTheme.slate600
                        : AppTheme.slate700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.tune_rounded, size: 15),
            label: const Text('Ajustar', style: TextStyle(fontSize: 11)),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            ),
            onPressed: () =>
                _showTimingsConfigDialog(context, provider, workshop, session),
          ),
        ],
      ),
    );
  }

  void _showTimingsConfigDialog(
    BuildContext context,
    AttendanceProvider provider,
    Workshop workshop,
    WorkshopSession session,
  ) {
    final tolCtrl = TextEditingController(
      text: session.toleranceMinutes.toString(),
    );
    final winCtrl = TextEditingController(
      text: session.registrationWindowMinutes.toString(),
    );
    bool resetClock = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Row(
              children: [
                Icon(Icons.timer_rounded, color: AppTheme.primary),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Tiempo de Registro y Tolerancia',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Configura cuántos minutos tienen de tolerancia para llegar puntual (ej. 15 min) y el tiempo total antes de que se cierre el registro:',
                    style: TextStyle(fontSize: 13, color: AppTheme.slate600),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '1. Tiempo de Tolerancia Puntual (Minutos):',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [5, 10, 15, 20, 30].map((m) {
                      final isSelected = tolCtrl.text.trim() == m.toString();
                      return ChoiceChip(
                        label: Text('$m min'),
                        selected: isSelected,
                        onSelected: (_) {
                          setDialogState(() {
                            tolCtrl.text = m.toString();
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: tolCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Minutos de tolerancia (Antes de marcar retraso)',
                      suffixText: 'minutos',
                      prefixIcon: Icon(Icons.access_time_rounded),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '2. Tiempo Total para Cierre de Registro (Minutos):',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [15, 30, 45, 60, 90].map((m) {
                      final isSelected = winCtrl.text.trim() == m.toString();
                      return ChoiceChip(
                        label: Text('$m min'),
                        selected: isSelected,
                        onSelected: (_) {
                          setDialogState(() {
                            winCtrl.text = m.toString();
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: winCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Duración total abierta para registrarse',
                      suffixText: 'minutos',
                      prefixIcon: Icon(Icons.lock_clock_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: resetClock,
                    title: const Text(
                      'Reiniciar el reloj desde este momento',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onChanged: (v) {
                      setDialogState(() {
                        resetClock = v ?? true;
                      });
                    },
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
                label: const Text('Guardar Tiempos'),
                onPressed: () async {
                  final tol = int.tryParse(tolCtrl.text.trim()) ?? 15;
                  final win = int.tryParse(winCtrl.text.trim()) ?? 45;
                  await provider.updateSessionTimings(
                    workshopId: workshop.id,
                    sessionId: session.id,
                    toleranceMinutes: tol,
                    registrationWindowMinutes: win < tol ? tol + 15 : win,
                    resetClock: resetClock,
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          '⏱️ Tolerancia fijada en $tol min y ventana de registro en ${win < tol ? tol + 15 : win} min.',
                        ),
                        backgroundColor: AppTheme.accreditedColor,
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

  /// Diálogo general para tomar nota y dar evidencia a cualquier alumno (inscrito o nuevo)
  void _showGeneralIncidentDialog(
    BuildContext context,
    AttendanceProvider provider,
    Workshop workshop,
    WorkshopSession session,
  ) {
    final controlCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    bool markEntry = true;
    bool markAccredited = false;
    String selectedPreset = '';

    final presets = [
      'Celular sin batería / apagado',
      'Sin conexión a internet / datos móviles',
      'Cámara dañada / no escanea QR',
      'Retraso justificado (avisó al docente)',
      'Permiso académico / situación médica',
    ];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Row(
              children: [
                Icon(Icons.assignment_turned_in_rounded, color: Color(0xFFD97706)),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Nota Docente y Evidencia para Alumno',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Si un alumno tuvo un problema para registrarse o justificó una situación, regístralo aquí para generar su folio de evidencia oficial:',
                    style: TextStyle(fontSize: 12, color: AppTheme.slate600),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: controlCtrl,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Matrícula / Número de Control',
                      hintText: 'Ej. 16100182',
                      prefixIcon: Icon(Icons.pin_rounded),
                    ),
                    onChanged: (val) {
                      final clean = val.trim().toUpperCase();
                      final match = workshop.enrolledStudents
                          .cast<Student?>()
                          .firstWhere(
                            (s) =>
                                s != null &&
                                s.enrollmentNumber.trim().toUpperCase() ==
                                    clean,
                            orElse: () => null,
                          );
                      if (match != null && nameCtrl.text.isEmpty) {
                        nameCtrl.text = match.fullName;
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: nameCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Nombre Completo del Alumno',
                      hintText: 'Ej. Juan Torres',
                      prefixIcon: Icon(Icons.person_rounded),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Motivo rápido (toca para seleccionar):',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: presets.map((p) {
                      final isSel = selectedPreset == p;
                      return ActionChip(
                        backgroundColor: isSel
                            ? const Color(0xFFFEF3C7)
                            : AppTheme.slate100,
                        label: Text(
                          p,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: isSel
                                ? FontWeight.w800
                                : FontWeight.w600,
                          ),
                        ),
                        onPressed: () {
                          setDialogState(() {
                            selectedPreset = p;
                            noteCtrl.text = p;
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: noteCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Descripción de la situación / Nota de Evidencia',
                      hintText:
                          'Escribe el detalle de la situación para respaldo del alumno...',
                      prefixIcon: Icon(Icons.notes_rounded),
                    ),
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: markEntry,
                    title: const Text(
                      'Validar y sellar su Entrada con esta nota',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onChanged: (v) =>
                        setDialogState(() => markEntry = v ?? true),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: markAccredited,
                    title: const Text(
                      'Dejar ACREDITADO al alumno en esta sesión',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onChanged: (v) =>
                        setDialogState(() => markAccredited = v ?? false),
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
                icon: const Icon(Icons.verified_user_rounded, size: 18),
                label: const Text('Guardar y Generar Evidencia'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD97706),
                  foregroundColor: Colors.white,
                ),
                onPressed: () async {
                  final control = controlCtrl.text.trim().toUpperCase();
                  final name = nameCtrl.text.trim();
                  final note = noteCtrl.text.trim();

                  if (control.isEmpty || note.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Ingresa la matrícula del alumno y el motivo/nota de la situación.',
                        ),
                      ),
                    );
                    return;
                  }

                  Student? targetStudent = workshop.enrolledStudents
                      .cast<Student?>()
                      .firstWhere(
                        (s) =>
                            s != null &&
                            s.enrollmentNumber.trim().toUpperCase() == control,
                        orElse: () => null,
                      );

                  if (targetStudent == null) {
                    await provider.addStudentToWorkshop(
                      workshopId: workshop.id,
                      fullName: name.isEmpty ? 'Alumno $control' : name,
                      enrollmentNumber: control,
                      email: '${control.toLowerCase()}@alumno.edu',
                    );
                    final updatedW = provider.workshops.firstWhere(
                      (w) => w.id == workshop.id,
                    );
                    targetStudent = updatedW.enrolledStudents.firstWhere(
                      (s) => s.enrollmentNumber.trim().toUpperCase() == control,
                    );
                  }

                  final savedRec = await provider.saveStudentIncidentNote(
                    workshopId: workshop.id,
                    sessionId: session.id,
                    studentId: targetStudent.id,
                    noteText: note,
                    markEntry: markEntry,
                    markAccredited: markAccredited,
                  );

                  if (ctx.mounted) Navigator.pop(ctx);
                  if (context.mounted) {
                    _showEvidenceReceiptDialog(
                      context,
                      workshop,
                      session,
                      targetStudent,
                      savedRec,
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

  /// Diálogo de nota para un alumno específico de la lista
  void _showStudentNoteDialog(
    BuildContext context,
    AttendanceProvider provider,
    Workshop workshop,
    WorkshopSession session,
    Student student,
    AttendanceRecord? record,
  ) {
    final noteCtrl = TextEditingController(text: '');
    bool markEntry = true;
    bool markAccredited = record?.isAccredited ?? false;

    final presets = [
      'Celular sin batería / apagado',
      'Sin conexión a internet / datos móviles',
      'Cámara dañada / no escanea QR',
      'Retraso justificado (avisó al docente)',
      'Permiso académico / situación médica',
    ];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                const Icon(
                  Icons.assignment_turned_in_rounded,
                  color: Color(0xFF7C3AED),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Nota / Evidencia: ${student.fullName}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Matrícula: ${student.enrollmentNumber}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.slate600,
                    ),
                  ),
                  if (record?.hasNotes == true) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F3FF),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFC4B5FD)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Nota registrada actualmente:',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF6D28D9),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            record!.notes!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF4C1D95),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  const Text(
                    'Selecciona motivo rápido o escribe la situación:',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: presets.map((p) {
                      return ActionChip(
                        backgroundColor: AppTheme.slate100,
                        label: Text(p, style: const TextStyle(fontSize: 11)),
                        onPressed: () {
                          setDialogState(() {
                            noteCtrl.text = p;
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: noteCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Situación reportada por el alumno',
                      hintText:
                          'Ej. Su celular se apagó al entrar; estuvo presente toda la sesión.',
                      prefixIcon: Icon(Icons.edit_note_rounded),
                    ),
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: markEntry,
                    title: const Text(
                      'Sellar Entrada del alumno automáticamente',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onChanged: (v) =>
                        setDialogState(() => markEntry = v ?? true),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: markAccredited,
                    title: const Text(
                      'Acreditar al alumno con esta evidencia',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onChanged: (v) =>
                        setDialogState(() => markAccredited = v ?? false),
                  ),
                ],
              ),
            ),
            actions: [
              if (record?.hasNotes == true)
                TextButton.icon(
                  icon: const Icon(Icons.receipt_long_rounded, size: 16),
                  label: const Text('Ver Comprobante'),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _showEvidenceReceiptDialog(
                      context,
                      workshop,
                      session,
                      student,
                      record!,
                    );
                  },
                ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.save_rounded, size: 18),
                label: const Text('Guardar Evidencia'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C3AED),
                  foregroundColor: Colors.white,
                ),
                onPressed: () async {
                  final text = noteCtrl.text.trim();
                  if (text.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Escribe o selecciona el motivo de la nota.'),
                      ),
                    );
                    return;
                  }
                  final saved = await provider.saveStudentIncidentNote(
                    workshopId: workshop.id,
                    sessionId: session.id,
                    studentId: student.id,
                    noteText: text,
                    markEntry: markEntry,
                    markAccredited: markAccredited,
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (context.mounted) {
                    _showEvidenceReceiptDialog(
                      context,
                      workshop,
                      session,
                      student,
                      saved,
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

  /// Muestra la tarjeta de comprobante de evidencia oficial para el alumno
  void _showEvidenceReceiptDialog(
    BuildContext context,
    Workshop workshop,
    WorkshopSession session,
    Student student,
    AttendanceRecord record,
  ) {
    final receiptText =
        '=== COMPROBANTE DE EVIDENCIA Y ASISTENCIA ===\n'
        'Taller: ${workshop.name} (${workshop.code})\n'
        'Sesión: ${session.title}\n'
        'Docente: ${workshop.instructorName}\n'
        'Alumno: ${student.fullName}\n'
        'Matrícula: ${student.enrollmentNumber}\n'
        'Estatus: ${record.statusLabel}\n'
        'Evidencia: ${record.notes ?? "Registrada"}\n'
        '=============================================';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.verified_user_rounded, color: Color(0xFF059669)),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Evidencia Oficial para el Alumno',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        content: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFECFDF5),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF10B981), width: 1.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '✅ EVIDENCIA GUARDADA EN NUBE Y SISTEMA',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF065F46),
                ),
              ),
              const Divider(height: 16),
              Text(
                'Alumno: ${student.fullName}',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
              Text(
                'Matrícula: ${student.enrollmentNumber}',
                style: const TextStyle(fontSize: 13),
              ),
              Text(
                'Taller: ${workshop.name} • Docente: ${workshop.instructorName}',
                style: const TextStyle(fontSize: 12, color: AppTheme.slate700),
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  record.notes ?? '',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.slate900,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                '💡 El alumno también puede ver esta evidencia directamente en su celular al ingresar su matrícula en el enlace del taller.',
                style: TextStyle(fontSize: 11, color: Color(0xFF065F46)),
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: const Text('Copiar Comprobante'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: receiptText));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('📋 Comprobante de evidencia copiado.'),
                  backgroundColor: AppTheme.accreditedColor,
                ),
              );
            },
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Listo'),
          ),
        ],
      ),
    );
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
        border: Border.all(color: color.withValues(alpha: 0.3)),
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

  Widget _buildMiniIndicator(
    String title,
    String val,
    IconData icon,
    Color color,
  ) {
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
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppTheme.slate600,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  val,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.slate900,
                  ),
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
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Row(
              children: [
                Icon(Icons.badge_rounded, color: AppTheme.primary),
                SizedBox(width: 10),
                Text(
                  'Pase por Matrícula',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
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
                    hintText: 'Ej. 16100182',
                    prefixIcon: Icon(Icons.pin_rounded),
                  ),
                  onChanged: (val) {
                    final clean = val.trim().toUpperCase();
                    final match = workshop.enrolledStudents
                        .cast<Student?>()
                        .firstWhere(
                          (s) =>
                              s != null &&
                              s.enrollmentNumber.trim().toUpperCase() == clean,
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.accreditedBg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.check_circle_rounded,
                          size: 18,
                          color: AppTheme.accreditedColor,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Alumno reconocido: $matchedName',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.accreditedColor,
                            ),
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
                      hintText: 'Ej. Juan Torres',
                      prefixIcon: Icon(Icons.person_rounded),
                    ),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.check_rounded, size: 18),
                label: Text(
                  session.currentPhase == SessionPhase.exit
                      ? 'Sellar Salida'
                      : 'Sellar Entrada',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: session.currentPhase == SessionPhase.exit
                      ? AppTheme.primary
                      : AppTheme.accreditedColor,
                ),
                onPressed: () async {
                  final control = controlCtrl.text.trim();
                  final name = nameCtrl.text.trim();

                  if (control.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Ingresa la matrícula del alumno.'),
                      ),
                    );
                    return;
                  }

                  Student? targetStudent = workshop.enrolledStudents
                      .cast<Student?>()
                      .firstWhere(
                        (s) =>
                            s != null &&
                            s.enrollmentNumber.trim().toUpperCase() ==
                                control.toUpperCase(),
                        orElse: () => null,
                      );

                  if (targetStudent == null) {
                    if (name.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Ingresa el nombre del alumno para inscribirlo.',
                          ),
                        ),
                      );
                      return;
                    }
                    await provider.addStudentToWorkshop(
                      workshopId: workshop.id,
                      fullName: name,
                      enrollmentNumber: control,
                      email: '${control.toLowerCase()}@alumno.edu',
                    );
                    final updatedW = provider.workshops.firstWhere(
                      (w) => w.id == workshop.id,
                    );
                    targetStudent = updatedW.enrolledStudents.firstWhere(
                      (s) =>
                          s.enrollmentNumber.trim().toUpperCase() ==
                          control.toUpperCase(),
                    );
                  }

                  final activePhase =
                      session.currentPhase == SessionPhase.exit
                      ? SessionPhase.exit
                      : SessionPhase.entry;

                  final res = provider.registerDirectAttendance(
                    workshopId: workshop.id,
                    sessionId: session.id,
                    studentId: targetStudent.id,
                    phase: activePhase,
                  );

                  if (ctx.mounted) Navigator.pop(ctx);

                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('${res.title}: ${res.message}'),
                        backgroundColor: res.success
                            ? AppTheme.accreditedColor
                            : AppTheme.absentColor,
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
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
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
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppTheme.primary,
                        fontSize: 18,
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
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          'Matrícula: ${student.enrollmentNumber}',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppTheme.slate600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  StudentStatusBadge(
                    status: record?.status ?? AttendanceStatus.absent,
                  ),
                ],
              ),
              const SizedBox(height: 16),

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
                        const Text(
                          '🟢 Entrada',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.slate600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          record?.checkInTime != null
                              ? '${_formatShort(record!.checkInTime!)} 🔒'
                              : 'Sin sellar',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: record?.checkInTime != null
                                ? AppTheme.accreditedColor
                                : AppTheme.slate600,
                          ),
                        ),
                      ],
                    ),
                    Container(height: 30, width: 1, color: AppTheme.slate200),
                    Column(
                      children: [
                        const Text(
                          '🔴 Salida',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.slate600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          record?.checkOutTime != null
                              ? '${_formatShort(record!.checkOutTime!)} 🔒'
                              : 'Sin sellar',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: record?.checkOutTime != null
                                ? AppTheme.primary
                                : AppTheme.slate600,
                          ),
                        ),
                      ],
                    ),
                    Container(height: 30, width: 1, color: AppTheme.slate200),
                    Column(
                      children: [
                        const Text(
                          '⏱️ Puntualidad',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.slate600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          record?.hasCheckIn != true
                              ? '--'
                              : (record!.isLate
                                    ? 'Retraso +${record.lateMinutes}m'
                                    : 'Puntual'),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: record?.isLate == true
                                ? const Color(0xFFB45309)
                                : AppTheme.accreditedColor,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              if (record?.hasNotes == true) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F3FF),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFC4B5FD)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '📋 Evidencia / Nota del Docente:',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF6D28D9),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        record!.notes!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF4C1D95),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),

              // Botón para Tomar Nota / Evidencia para el Alumno
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.note_add_rounded),
                  label: Text(
                    record?.hasNotes == true
                        ? '📝 Editar Nota / Ver Comprobante de Evidencia'
                        : '📝 Tomar Nota / Generar Evidencia de Situación',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7C3AED),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _showStudentNoteDialog(
                      context,
                      provider,
                      workshop,
                      session,
                      student,
                      record,
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),

              // Botón para Acreditar Directamente Hoy
              if (record?.isAccredited != true) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.verified_rounded),
                    label: const Text(
                      '🎓 Acreditar Alumno Hoy (Entrada + Salida OK)',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accreditedColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    onPressed: () async {
                      await provider.accreditStudentDirectly(
                        workshopId: workshop.id,
                        sessionId: session.id,
                        studentId: student.id,
                      );
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              '🎓 ${student.fullName} ha sido ACREDITADO exitosamente.',
                            ),
                            backgroundColor: AppTheme.accreditedColor,
                          ),
                        );
                      }
                    },
                  ),
                ),
                const SizedBox(height: 8),
              ],

              // Botones de acción manual individual
              if (record?.hasCheckIn != true) ...[
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.login_rounded),
                    label: const Text('Sellar Solo Entrada Ahora 🔒'),
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
                const SizedBox(height: 8),
              ],
              if (record?.hasCheckOut != true) ...[
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.logout_rounded),
                    label: const Text('Sellar Solo Salida Ahora 🔒'),
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
                const SizedBox(height: 8),
              ],
              if (record != null &&
                  (record.hasCheckIn ||
                      record.hasCheckOut ||
                      record.hasNotes)) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.restart_alt_rounded),
                    label: const Text(
                      '🔄 Reabrir / Desbloquear Registro de Alumno',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.incompleteColor,
                      foregroundColor: AppTheme.slate900,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (dCtx) => AlertDialog(
                          title: const Text('¿Desbloquear alumno?'),
                          content: Text(
                            'Esto eliminará el sello actual de ${student.fullName} (${student.enrollmentNumber}) en esta sesión tanto en la app como en la nube, permitiéndole escanear nuevamente.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(dCtx, false),
                              child: const Text('Cancelar'),
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.incompleteColor,
                              ),
                              onPressed: () => Navigator.pop(dCtx, true),
                              child: const Text('Sí, Desbloquear'),
                            ),
                          ],
                        ),
                      );

                      if (confirm == true) {
                        await provider.resetStudentAttendance(
                          workshopId: workshop.id,
                          sessionId: session.id,
                          studentId: student.id,
                        );
                        if (context.mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '🔓 Registro de ${student.fullName} desbloqueado con éxito.',
                              ),
                              backgroundColor: AppTheme.accreditedColor,
                            ),
                          );
                        }
                      }
                    },
                  ),
                ),
                const SizedBox(height: 8),
              ],
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cerrar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
