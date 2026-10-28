import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/session.dart';
import '../providers/attendance_provider.dart';
import '../utils/app_theme.dart';
import 'teacher/workshop_detail_screen.dart';
import 'teacher/live_session_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  Widget build(BuildContext context) {
    return Consumer<AttendanceProvider>(
      builder: (context, provider, child) {
        return Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryLight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.qr_code_scanner_rounded,
                    color: AppTheme.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Asistencia de Talleres',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                    Text(
                      'Acreditación Doble Check (Entrada y Salida)',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.slate600,
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              if (provider.workshops.isNotEmpty)
                IconButton(
                  tooltip: 'Limpiar todos los datos',
                  icon: const Icon(
                    Icons.delete_sweep_rounded,
                    color: AppTheme.slate600,
                  ),
                  onPressed: () => _confirmClearData(context, provider),
                ),
              const SizedBox(width: 8),
            ],
          ),
          body: provider.isLoading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: _buildTeacherView(context, provider),
                ),
        );
      },
    );
  }

  Widget _buildTeacherView(BuildContext context, AttendanceProvider provider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            const Text(
              'Talleres Disponibles',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppTheme.slate900,
              ),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('Nuevo Taller'),
              onPressed: () => _showCreateWorkshopDialog(context, provider),
            ),
          ],
        ),
        const SizedBox(height: 14),

        if (provider.workshops.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.slate200),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryLight,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.school_rounded,
                    size: 40,
                    color: AppTheme.primary,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'No hay talleres registrados todavía',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.slate900,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Crea tu primer taller para matricular a tus alumnos y comenzar a pasar lista con código QR dinámico.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: AppTheme.slate600),
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Crear Primer Taller'),
                  onPressed: () => _showCreateWorkshopDialog(context, provider),
                ),
              ],
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: provider.workshops.length,
            separatorBuilder: (_, index) => const SizedBox(height: 14),
            itemBuilder: (context, index) {
              final workshop = provider.workshops[index];
              final hasActiveSession = workshop.sessions.any(
                (s) => s.isQrActive,
              );
              final activeSession = workshop.sessions
                  .cast<dynamic>()
                  .firstWhere(
                    (s) => s.isQrActive,
                    orElse: () => workshop.sessions.isNotEmpty
                        ? workshop.sessions.first
                        : null,
                  );

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
                              workshop.name,
                              style: const TextStyle(
                                fontSize: 17,
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
                              color: AppTheme.primaryLight,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              workshop.code,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Docente a cargo: ${workshop.instructorName}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppTheme.slate700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        workshop.description,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.slate600,
                        ),
                      ),
                      const SizedBox(height: 14),
                      if (activeSession != null) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppTheme.slate50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppTheme.slate200),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '📌 ${activeSession.title}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.slate900,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '📅 Día: ${activeSession.formattedDateWithDay} • 🕒 Inicio: ${activeSession.startTimeLabel} hrs ➔ Término: ${activeSession.endTimeLabel} hrs',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF065F46),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          _buildBadge(
                            Icons.people_alt_rounded,
                            '${workshop.enrolledStudents.length} Alumnos',
                          ),
                          _buildBadge(
                            Icons.event_note_rounded,
                            '${workshop.sessions.length} Sesiones',
                          ),
                          if (hasActiveSession) _buildActiveBadge(),
                        ],
                      ),
                      const Divider(height: 24),
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        alignment: WrapAlignment.end,
                        children: [
                          OutlinedButton.icon(
                            icon: const Icon(Icons.settings_rounded, size: 16),
                            label: const Text('Administrar Taller'),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => WorkshopDetailScreen(
                                    workshopId: workshop.id,
                                  ),
                                ),
                              );
                            },
                          ),
                          if (activeSession != null)
                            ElevatedButton.icon(
                              icon: const Icon(
                                Icons.qr_code_scanner_rounded,
                                size: 16,
                              ),
                              label: const Text('Abrir Pase de Lista'),
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => LiveSessionScreen(
                                      workshop: workshop,
                                      session: activeSession,
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
          ),
      ],
    );
  }

  Widget _buildBadge(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.slate100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.slate700),
          const SizedBox(width: 5),
          Text(
            text,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppTheme.slate700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.accreditedBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppTheme.accreditedColor.withValues(alpha: 0.3),
        ),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.wifi_tethering_rounded,
            size: 14,
            color: AppTheme.accreditedColor,
          ),
          SizedBox(width: 5),
          Text(
            'Pase en Vivo Activo',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppTheme.accreditedColor,
            ),
          ),
        ],
      ),
    );
  }

  void _showCreateWorkshopDialog(
    BuildContext context,
    AttendanceProvider provider,
  ) {
    final now = DateTime.now();
    final defaultStart =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final endDt = now.add(const Duration(hours: 2));
    final defaultEnd =
        '${endDt.hour.toString().padLeft(2, '0')}:${endDt.minute.toString().padLeft(2, '0')}';

    final nameCtrl = TextEditingController();
    final codeCtrl = TextEditingController();
    final instructorCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final startCtrl = TextEditingController(text: defaultStart);
    final endCtrl = TextEditingController(text: defaultEnd);
    final List<DateTime> selectedDates = [now];
    final List<TextEditingController> sessionTitleCtrls = [
      TextEditingController(text: 'Sesión 1: Introducción y Teoría'),
    ];

    String suggestedTitleFor(int sessionNumber) {
      const suggestions = [
        'Introducción y Teoría',
        'Práctica Guiada',
        'Desarrollo de Proyecto',
        'Evaluación y Cierre',
      ];
      final topic = suggestions[(sessionNumber - 1) % suggestions.length];
      return 'Sesión $sessionNumber: $topic';
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Crear Nuevo Taller y Preparar Sesiones'),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nombre del Taller',
                      hintText: 'Ej. Taller de Pavimentación',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: codeCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Código del Taller',
                      hintText: 'Ej. PAV-2026',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: instructorCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Docente Responsable',
                      hintText: 'Ej. Ing. Carlos Méndez',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: descCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Descripción',
                      hintText: 'Objetivo y contenidos del taller...',
                    ),
                  ),
                  const Divider(height: 24),
                  const Text(
                    '📅 Preparar Sesiones (Escribe el título y elige la fecha de cada sesión):',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  ...List.generate(selectedDates.length, (idx) {
                    final d = selectedDates[idx];
                    final titleCtrl = sessionTitleCtrls[idx];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(10),
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
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              TextButton.icon(
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
                                    setDialogState(() {
                                      selectedDates[idx] = picked;
                                    });
                                  }
                                },
                              ),
                              if (selectedDates.length > 1)
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
                                      selectedDates.removeAt(idx);
                                      sessionTitleCtrls.removeAt(idx);
                                    });
                                  },
                                ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: titleCtrl,
                            decoration: InputDecoration(
                              isDense: true,
                              labelText: 'Título de la Sesión ${idx + 1}',
                              hintText:
                                  'Ej. Sesión ${idx + 1}: Tema específico de este día',
                              prefixIcon: const Icon(
                                Icons.edit_note_rounded,
                                size: 18,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.add_circle_outline, size: 15),
                        label: Text(
                          '➕ Agregar Sesión ${selectedDates.length + 1}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: ctx,
                            initialDate: selectedDates.last.add(
                              const Duration(days: 1),
                            ),
                            firstDate: DateTime(2024),
                            lastDate: DateTime(2030),
                          );
                          if (picked != null) {
                            setDialogState(() {
                              selectedDates.add(picked);
                              sessionTitleCtrls.add(
                                TextEditingController(
                                  text: suggestedTitleFor(selectedDates.length),
                                ),
                              );
                            });
                          }
                        },
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.date_range_rounded, size: 15),
                        label: const Text(
                          '📆 Rango de Días (Preparar 1 Sesión por Día)',
                          style: TextStyle(fontSize: 11),
                        ),
                        onPressed: () async {
                          final range = await showDateRangePicker(
                            context: ctx,
                            firstDate: DateTime(2024),
                            lastDate: DateTime(2030),
                            initialDateRange: DateTimeRange(
                              start: selectedDates.first,
                              end: selectedDates.first.add(
                                const Duration(days: 2),
                              ),
                            ),
                          );
                          if (range != null) {
                            setDialogState(() {
                              selectedDates.clear();
                              sessionTitleCtrls.clear();
                              var cur = range.start;
                              int safety = 0;
                              while (!cur.isAfter(range.end) && safety < 15) {
                                selectedDates.add(cur);
                                sessionTitleCtrls.add(
                                  TextEditingController(
                                    text: suggestedTitleFor(
                                      selectedDates.length,
                                    ),
                                  ),
                                );
                                cur = cur.add(const Duration(days: 1));
                                safety++;
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
                          controller: startCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Hora de Inicio',
                            prefixIcon: Icon(Icons.play_circle_outline),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: endCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Hora de Término',
                            prefixIcon: Icon(Icons.stop_circle_outlined),
                          ),
                        ),
                      ),
                    ],
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
            ElevatedButton(
              onPressed: () {
                if (nameCtrl.text.trim().isNotEmpty &&
                    codeCtrl.text.trim().isNotEmpty) {
                  final titles = List.generate(selectedDates.length, (i) {
                    final t = sessionTitleCtrls[i].text.trim();
                    return t.isNotEmpty ? t : suggestedTitleFor(i + 1);
                  });
                  provider.addWorkshop(
                    name: nameCtrl.text.trim(),
                    code: codeCtrl.text.trim(),
                    instructorName: instructorCtrl.text.trim(),
                    description: descCtrl.text.trim(),
                    initialSessionTitle: titles.first,
                    initialSessionDate: selectedDates.first,
                    initialSessionDates: selectedDates,
                    initialSessionTitles: titles,
                    initialStartTimeLabel: startCtrl.text.trim(),
                    initialEndTimeLabel: endCtrl.text.trim(),
                  );
                  Navigator.pop(ctx);
                }
              },
              child: Text(
                selectedDates.length > 1
                    ? 'Guardar Taller y ${selectedDates.length} Sesiones'
                    : 'Guardar Taller y Sesión',
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmClearData(BuildContext context, AttendanceProvider provider) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppTheme.absentColor),
            SizedBox(width: 8),
            Text('Limpiar Registros'),
          ],
        ),
        content: const Text(
          '¿Estás seguro de que deseas eliminar todos los talleres y listas de asistencia? La base de datos local quedará completamente limpia.',
          style: TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.absentColor,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              provider.clearAllData();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Todos los datos han sido eliminados.'),
                ),
              );
            },
            child: const Text('Eliminar Todo'),
          ),
        ],
      ),
    );
  }
}
