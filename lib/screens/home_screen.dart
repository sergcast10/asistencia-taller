import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
                  child: const Icon(Icons.qr_code_scanner_rounded, color: AppTheme.primary, size: 22),
                ),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Asistencia de Talleres',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                    ),
                    Text(
                      'Acreditación Doble Check (Entrada y Salida)',
                      style: TextStyle(fontSize: 11, color: AppTheme.slate600, fontWeight: FontWeight.normal),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              if (provider.workshops.isNotEmpty)
                IconButton(
                  tooltip: 'Limpiar todos los datos',
                  icon: const Icon(Icons.delete_sweep_rounded, color: AppTheme.slate600),
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
                  child: const Icon(Icons.school_rounded, size: 40, color: AppTheme.primary),
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
              final hasActiveSession = workshop.sessions.any((s) => s.isQrActive);
              final activeSession = workshop.sessions.cast<dynamic>().firstWhere(
                    (s) => s.isQrActive,
                    orElse: () => workshop.sessions.isNotEmpty ? workshop.sessions.first : null,
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
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
                        style: const TextStyle(fontSize: 13, color: AppTheme.slate700, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        workshop.description,
                        style: const TextStyle(fontSize: 12, color: AppTheme.slate600),
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          _buildBadge(Icons.people_alt_rounded, '${workshop.enrolledStudents.length} Alumnos'),
                          _buildBadge(Icons.event_note_rounded, '${workshop.sessions.length} Sesiones'),
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
                                  builder: (_) => WorkshopDetailScreen(workshopId: workshop.id),
                                ),
                              );
                            },
                          ),
                          if (activeSession != null)
                            ElevatedButton.icon(
                              icon: const Icon(Icons.qr_code_scanner_rounded, size: 16),
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
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.slate700),
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
        border: Border.all(color: AppTheme.accreditedColor.withOpacity(0.3)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.wifi_tethering_rounded, size: 14, color: AppTheme.accreditedColor),
          SizedBox(width: 5),
          Text(
            'Pase en Vivo Activo',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.accreditedColor),
          ),
        ],
      ),
    );
  }

  void _showCreateWorkshopDialog(BuildContext context, AttendanceProvider provider) {
    final nameCtrl = TextEditingController();
    final codeCtrl = TextEditingController();
    final instructorCtrl = TextEditingController();
    final descCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Crear Nuevo Taller'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Nombre del Taller', hintText: 'Ej. Taller de Pavimentación'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: codeCtrl,
                decoration: const InputDecoration(labelText: 'Código del Taller', hintText: 'Ej. PAV-2026'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: instructorCtrl,
                decoration: const InputDecoration(labelText: 'Docente Responsable', hintText: 'Ej. Ing. Carlos Méndez'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: descCtrl,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Descripción', hintText: 'Objetivo y contenidos del taller...'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () {
              if (nameCtrl.text.trim().isNotEmpty && codeCtrl.text.trim().isNotEmpty) {
                provider.addWorkshop(
                  name: nameCtrl.text.trim(),
                  code: codeCtrl.text.trim(),
                  instructorName: instructorCtrl.text.trim(),
                  description: descCtrl.text.trim(),
                );
                Navigator.pop(ctx);
              }
            },
            child: const Text('Guardar Taller'),
          ),
        ],
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.absentColor),
            onPressed: () {
              Navigator.pop(ctx);
              provider.clearAllData();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Todos los datos han sido eliminados.')),
              );
            },
            child: const Text('Eliminar Todo'),
          ),
        ],
      ),
    );
  }
}
