import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/session.dart';
import '../models/workshop.dart';
import '../providers/attendance_provider.dart';
import '../utils/app_theme.dart';
import 'teacher/workshop_detail_screen.dart';

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
              IconButton(
                tooltip: 'Seguridad Anti-Hackeo y PIN Docente',
                icon: const Icon(
                  Icons.shield_rounded,
                  color: AppTheme.primary,
                ),
                onPressed: () =>
                    _showSecuritySettingsDialog(context, provider),
              ),
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
                            child: InkWell(
                              borderRadius: BorderRadius.circular(6),
                              onTap: () => _showEditWorkshopDialog(
                                context,
                                provider,
                                workshop,
                              ),
                              child: Row(
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
                                  const SizedBox(width: 6),
                                  const Icon(
                                    Icons.edit_rounded,
                                    size: 16,
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
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              size: 16,
                              color: AppTheme.absentColor,
                            ),
                            label: const Text(
                              'Borrar',
                              style: TextStyle(color: AppTheme.absentColor),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(
                                color: AppTheme.absentColor.withValues(
                                  alpha: 0.4,
                                ),
                              ),
                            ),
                            onPressed: () => _confirmDeleteWorkshopDialog(
                              context,
                              provider,
                              workshop,
                            ),
                          ),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.edit_rounded, size: 16),
                            label: const Text('Editar Taller'),
                            onPressed: () => _showEditWorkshopDialog(
                              context,
                              provider,
                              workshop,
                            ),
                          ),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.settings_rounded, size: 16),
                            label: const Text('Administrar Taller'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primary,
                              foregroundColor: Colors.white,
                            ),
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
                'Editar Datos del Taller',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
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
                  'Corrige el título, código, docente encargado o descripción del taller en caso de equivocación:',
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
            icon: const Icon(Icons.delete_forever_rounded, color: AppTheme.absentColor, size: 16),
            label: const Text('Eliminar Taller', style: TextStyle(color: AppTheme.absentColor)),
            onPressed: () {
              Navigator.pop(ctx);
              _confirmDeleteWorkshopDialog(context, provider, workshop);
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

  void _confirmDeleteWorkshopDialog(
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
    final List<DateTime> selectedDates = [now];
    final List<TextEditingController> sessionTitleCtrls = [
      TextEditingController(text: 'Sesión 1: Introducción y Teoría'),
    ];
    final List<TextEditingController> sessionStartCtrls = [
      TextEditingController(text: defaultStart),
    ];
    final List<TextEditingController> sessionEndCtrls = [
      TextEditingController(text: defaultEnd),
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
                    '📅 Preparar Sesiones (Cada sección tiene su propio título, día y horario):',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  ...List.generate(selectedDates.length, (idx) {
                    final d = selectedDates[idx];
                    final titleCtrl = sessionTitleCtrls[idx];
                    final sStartCtrl = sessionStartCtrls[idx];
                    final sEndCtrl = sessionEndCtrls[idx];
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
                                      sessionStartCtrls.removeAt(idx);
                                      sessionEndCtrls.removeAt(idx);
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
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: sStartCtrl,
                                  decoration: InputDecoration(
                                    isDense: true,
                                    labelText: 'Inicio Sesión ${idx + 1}',
                                    prefixIcon: const Icon(
                                      Icons.play_circle_outline,
                                      size: 17,
                                    ),
                                    suffixIcon: IconButton(
                                      tooltip: 'Elegir hora en reloj',
                                      icon: const Icon(
                                        Icons.access_time_rounded,
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
                                    labelText: 'Término Sesión ${idx + 1}',
                                    prefixIcon: const Icon(
                                      Icons.stop_circle_outlined,
                                      size: 17,
                                    ),
                                    suffixIcon: IconButton(
                                      tooltip: 'Elegir hora en reloj',
                                      icon: const Icon(
                                        Icons.access_time_rounded,
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
                              final prevStart = sessionStartCtrls.isNotEmpty
                                  ? sessionStartCtrls.last.text
                                  : defaultStart;
                              final prevEnd = sessionEndCtrls.isNotEmpty
                                  ? sessionEndCtrls.last.text
                                  : defaultEnd;
                              selectedDates.add(picked);
                              sessionTitleCtrls.add(
                                TextEditingController(
                                  text: suggestedTitleFor(selectedDates.length),
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
                              final baseStart = sessionStartCtrls.isNotEmpty
                                  ? sessionStartCtrls.first.text
                                  : defaultStart;
                              final baseEnd = sessionEndCtrls.isNotEmpty
                                  ? sessionEndCtrls.first.text
                                  : defaultEnd;
                              selectedDates.clear();
                              sessionTitleCtrls.clear();
                              sessionStartCtrls.clear();
                              sessionEndCtrls.clear();
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
                                sessionStartCtrls.add(
                                  TextEditingController(text: baseStart),
                                );
                                sessionEndCtrls.add(
                                  TextEditingController(text: baseEnd),
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
                  final startTimes = List.generate(selectedDates.length, (i) {
                    final s = sessionStartCtrls[i].text.trim();
                    return s.isNotEmpty ? s : defaultStart;
                  });
                  final endTimes = List.generate(selectedDates.length, (i) {
                    final e = sessionEndCtrls[i].text.trim();
                    return e.isNotEmpty ? e : defaultEnd;
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
                    initialSessionStartTimes: startTimes,
                    initialSessionEndTimes: endTimes,
                    initialStartTimeLabel: startTimes.first,
                    initialEndTimeLabel: endTimes.first,
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

  void _showSecuritySettingsDialog(
    BuildContext context,
    AttendanceProvider provider,
  ) {
    final pinCtrl = TextEditingController(text: provider.teacherPin);
    bool requirePin = provider.isPinRequiredForSensitiveActions;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.shield_rounded, color: AppTheme.primary),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Blindaje de Seguridad y PIN Docente',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF10B981)),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '🛡️ 6 Capas de Seguridad Activas:',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF065F46),
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          '• Firma Criptográfica HMAC-SHA256 en cada código QR.\n'
                          '• Rotación dinámica cada 15 seg (impide mandar fotos del QR por WhatsApp).\n'
                          '• Bloqueo de 1 Alumno por Celular (un alumno no puede registrar a otro compañero desde su teléfono).\n'
                          '• Vínculo 1 Celular por Alumno: si cambia de celular, el docente le da acceso al nuevo y el viejo se borra automáticamente.\n'
                          '• Sellado Inmutable de Entrada y Salida (nadie puede alterar la hora registrada).\n'
                          '• PIN Docente para proteger borrado y desbloqueo de celulares.',
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.4,
                            color: Color(0xFF047857),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: pinCtrl,
                    decoration: const InputDecoration(
                      labelText: 'PIN de Seguridad del Docente',
                      hintText: 'Ej. 1234',
                      prefixIcon: Icon(Icons.lock_rounded),
                      helperText:
                          'Este PIN también sirve si deseas autorizar en persona el cambio de celular en el teléfono de un alumno.',
                    ),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text(
                      'Exigir PIN Docente antes de borrar talleres o registros',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    value: requirePin,
                    onChanged: (v) => setDialogState(() => requirePin = v),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cerrar'),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.save_rounded, size: 16),
              label: const Text('Guardar PIN de Seguridad'),
              onPressed: () async {
                await provider.updateTeacherSecuritySettings(
                  newPin: pinCtrl.text.trim(),
                  requirePinForSensitiveActions: requirePin,
                );
                if (ctx.mounted) Navigator.pop(ctx);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        '🛡️ Configuración de seguridad y PIN Docente actualizados.',
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

  void _confirmClearData(BuildContext context, AttendanceProvider provider) {
    final pinInputCtrl = TextEditingController();
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
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '¿Estás seguro de que deseas eliminar todos los talleres y listas de asistencia? La base de datos local quedará completamente limpia.',
              style: TextStyle(fontSize: 13),
            ),
            if (provider.isPinRequiredForSensitiveActions) ...[
              const SizedBox(height: 12),
              TextField(
                controller: pinInputCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Ingresa tu PIN Docente para confirmar',
                  prefixIcon: Icon(Icons.lock_outline_rounded),
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
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.absentColor,
            ),
            onPressed: () {
              if (provider.isPinRequiredForSensitiveActions &&
                  !provider.verifyTeacherPin(pinInputCtrl.text)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('⛔ PIN Docente incorrecto. Acción bloqueada.'),
                    backgroundColor: AppTheme.absentColor,
                  ),
                );
                return;
              }
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
