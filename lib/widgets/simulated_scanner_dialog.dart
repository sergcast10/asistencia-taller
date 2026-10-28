import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/workshop.dart';
import '../models/session.dart';
import '../models/student.dart';
import '../providers/attendance_provider.dart';
import '../services/qr_service.dart';
import '../utils/app_theme.dart';

class SimulatedScannerDialog extends StatefulWidget {
  final Workshop workshop;
  final WorkshopSession session;

  const SimulatedScannerDialog({
    super.key,
    required this.workshop,
    required this.session,
  });

  @override
  State<SimulatedScannerDialog> createState() => _SimulatedScannerDialogState();
}

class _SimulatedScannerDialogState extends State<SimulatedScannerDialog> {
  Student? _selectedStudent;
  bool _simulateExpiredToken = false;
  AttendanceProcessResult? _lastResult;

  @override
  void initState() {
    super.initState();
    if (widget.workshop.enrolledStudents.isNotEmpty) {
      _selectedStudent = widget.workshop.enrolledStudents.first;
    }
  }

  void _executeScan() {
    if (_selectedStudent == null) return;

    final provider = context.read<AttendanceProvider>();

    if (!widget.session.isQrActive) {
      setState(() {
        _lastResult = AttendanceProcessResult(
          success: false,
          title: 'Pase Inactivo',
          message: 'Primero activa la fase de Entrada o Salida con los botones del docente.',
        );
      });
      return;
    }

    // Generar el QR actual (o uno expirado si se activó la opción para probar el antifraude)
    final now = _simulateExpiredToken
        ? DateTime.now().subtract(
            const Duration(seconds: 45),
          ) // QR viejo de hace 45s
        : DateTime.now();

    final qrData = QrService.generateDynamicQrData(
      sessionId: widget.session.id,
      workshopId: widget.workshop.id,
      phase: widget.session.currentPhase,
      secretKey: widget.session.secretKey,
      now: now,
    );

    final result = provider.processQrScan(
      qrRawContent: qrData,
      studentEnrollmentNumber: _selectedStudent!.enrollmentNumber,
    );

    setState(() {
      _lastResult = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 480,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.qr_code_scanner_rounded,
                    color: AppTheme.primary,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Simulador de Escaneo de Alumnos',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.slate900,
                        ),
                      ),
                      Text(
                        'Prueba inmediata sin necesidad de cámara externa',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.slate600,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(height: 28),

            // Selector de Alumno
            const Text(
              'Selecciona al Estudiante:',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: AppTheme.slate800,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.slate200),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<Student>(
                  isExpanded: true,
                  value: _selectedStudent,
                  items: widget.workshop.enrolledStudents.map((s) {
                    final rec = widget.session.records[s.id];
                    String tag = '[Sin registro]';
                    if (rec != null) {
                      if (rec.hasCheckIn && rec.hasCheckOut) {
                        tag = '[🟢 Acreditado]';
                      } else if (rec.hasCheckIn) {
                        tag = '[🟡 Solo Entrada]';
                      } else if (rec.hasCheckOut) {
                        tag = '[🟡 Solo Salida]';
                      }
                    }
                    return DropdownMenuItem(
                      value: s,
                      child: Text(
                        '${s.fullName} ($tag) - ${s.enrollmentNumber}',
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    setState(() {
                      _selectedStudent = val;
                      _lastResult = null;
                    });
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Toggle para probar rechazo de token expirado (Antifraude)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _simulateExpiredToken
                    ? AppTheme.absentBg
                    : AppTheme.slate100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _simulateExpiredToken
                      ? AppTheme.absentColor.withValues(alpha: 0.4)
                      : AppTheme.slate200,
                ),
              ),
              child: Row(
                children: [
                  Checkbox(
                    value: _simulateExpiredToken,
                    activeColor: AppTheme.absentColor,
                    onChanged: (val) {
                      setState(() {
                        _simulateExpiredToken = val ?? false;
                      });
                    },
                  ),
                  Expanded(
                    child: Text(
                      'Simular foto enviada hace >30s (Probar rechazo por antifraude)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _simulateExpiredToken
                            ? AppTheme.absentColor
                            : AppTheme.slate700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Botón de Escaneo
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.flash_on_rounded),
                label: Text(
                  widget.session.currentPhase == SessionPhase.entry
                      ? 'Simular Escaneo de ENTRADA'
                      : widget.session.currentPhase == SessionPhase.exit
                      ? 'Simular Escaneo de SALIDA'
                      : 'Pase Inactivo (Activa Entrada o Salida)',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: widget.session.isQrActive
                      ? (widget.session.currentPhase == SessionPhase.entry
                            ? AppTheme.accreditedColor
                            : AppTheme.primary)
                      : AppTheme.slate600,
                ),
                onPressed: widget.session.isQrActive ? _executeScan : null,
              ),
            ),

            if (_lastResult != null) ...[
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _lastResult!.success
                      ? (_lastResult!.status != null &&
                                _lastResult!.status!.name == 'accredited'
                            ? AppTheme.accreditedBg
                            : AppTheme.primaryLight)
                      : AppTheme.absentBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _lastResult!.success
                        ? (_lastResult!.status != null &&
                                  _lastResult!.status!.name == 'accredited'
                              ? AppTheme.accreditedColor
                              : AppTheme.primary)
                        : AppTheme.absentColor,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _lastResult!.success
                              ? Icons.check_circle_rounded
                              : Icons.error_rounded,
                          color: _lastResult!.success
                              ? (_lastResult!.status != null &&
                                        _lastResult!.status!.name ==
                                            'accredited'
                                    ? AppTheme.accreditedColor
                                    : AppTheme.primary)
                              : AppTheme.absentColor,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _lastResult!.title,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                            color: _lastResult!.success
                                ? (_lastResult!.status != null &&
                                          _lastResult!.status!.name ==
                                              'accredited'
                                      ? AppTheme.accreditedColor
                                      : AppTheme.primary)
                                : AppTheme.absentColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _lastResult!.message,
                      style: const TextStyle(fontSize: 12, height: 1.3),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
