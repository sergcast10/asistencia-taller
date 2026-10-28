import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/student.dart';
import '../../providers/attendance_provider.dart';
import '../../services/qr_service.dart';
import '../../utils/app_theme.dart';

class StudentScannerScreen extends StatefulWidget {
  final Student? initialStudent;

  const StudentScannerScreen({super.key, this.initialStudent});

  @override
  State<StudentScannerScreen> createState() => _StudentScannerScreenState();
}

class _StudentScannerScreenState extends State<StudentScannerScreen> {
  final MobileScannerController _scannerController = MobileScannerController();
  bool _isProcessing = false;

  final TextEditingController _controlNumberController = TextEditingController();
  final TextEditingController _fullNameController = TextEditingController();
  final TextEditingController _manualQrController = TextEditingController();

  String _savedControlNumber = '';
  String _savedFullName = '';

  @override
  void initState() {
    super.initState();
    _loadSavedStudentData();
  }

  Future<void> _loadSavedStudentData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _savedControlNumber = widget.initialStudent?.enrollmentNumber ??
          prefs.getString('student_saved_control_number') ??
          '';
      _savedFullName = widget.initialStudent?.fullName ??
          prefs.getString('student_saved_full_name') ??
          '';

      _controlNumberController.text = _savedControlNumber;
      _fullNameController.text = _savedFullName;
    });
  }

  Future<void> _saveStudentData(String controlNumber, String fullName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('student_saved_control_number', controlNumber.trim());
    await prefs.setString('student_saved_full_name', fullName.trim());
    setState(() {
      _savedControlNumber = controlNumber.trim();
      _savedFullName = fullName.trim();
    });
  }

  @override
  void dispose() {
    _scannerController.dispose();
    _controlNumberController.dispose();
    _fullNameController.dispose();
    _manualQrController.dispose();
    super.dispose();
  }

  void _handleQrDetection(String rawValue) {
    if (_isProcessing) return;
    _isProcessing = true;

    // Pausar cámara mientras se procesa
    _scannerController.stop();

    // Si el estudiante ya se registró una vez en este celular,
    // NO es necesario volver a registrarse: procesa su asistencia directamente.
    if (_savedControlNumber.isNotEmpty) {
      _processAttendance(rawValue, _savedControlNumber, _savedFullName);
    } else {
      // Primera vez: solicita su número de control
      _showControlNumberPromptDialog(rawValue);
    }
  }

  Future<void> _clearSavedStudentData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('student_saved_control_number');
    await prefs.remove('student_saved_full_name');
    setState(() {
      _savedControlNumber = '';
      _savedFullName = '';
      _controlNumberController.clear();
      _fullNameController.clear();
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Datos desvinculados de este teléfono.')),
      );
    }
  }

  void _showControlNumberPromptDialog(String qrContent) {
    // Intentar interpretar información preliminar del QR para mostrar al alumno
    String detectedPhaseName = 'Pase de Asistencia';
    bool isEntry = true;
    try {
      final payload = QrService.extractPayload(qrContent);
      if (payload.contains('"p"')) {
        final decoded = jsonDecode(payload);
        final p = decoded['p'] as String?;
        if (p == 'entry') {
          detectedPhaseName = 'Pase de ENTRADA';
          isEntry = true;
        } else if (p == 'exit') {
          detectedPhaseName = 'Pase de SALIDA';
          isEntry = false;
        }
      }
    } catch (_) {}

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isEntry ? AppTheme.accreditedBg : AppTheme.primaryLight,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      isEntry ? Icons.login_rounded : Icons.logout_rounded,
                      color: isEntry ? AppTheme.accreditedColor : AppTheme.primary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Código QR Detectado',
                          style: TextStyle(fontSize: 12, color: AppTheme.slate600, fontWeight: FontWeight.w600),
                        ),
                        Text(
                          detectedPhaseName,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: isEntry ? AppTheme.accreditedColor : AppTheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _resumeScanning();
                    },
                  ),
                ],
              ),
              const Divider(height: 24),
              const Text(
                'Ingresa tu Número de Control para registrar y enviar tu asistencia:',
                style: TextStyle(fontSize: 13, color: AppTheme.slate700),
              ),
              const SizedBox(height: 14),

              // Campo de Número de Control / Matrícula
              TextField(
                controller: _controlNumberController,
                autofocus: _controlNumberController.text.isEmpty,
                decoration: InputDecoration(
                  labelText: 'Número de Control / Matrícula *',
                  hintText: 'Ej. 21010482 o PAV-101',
                  prefixIcon: const Icon(Icons.badge_rounded, color: AppTheme.primary),
                  helperText: 'Se guardará en este celular para futuros escaneos.',
                ),
              ),
              const SizedBox(height: 14),

              // Campo de Nombre Completo
              TextField(
                controller: _fullNameController,
                decoration: const InputDecoration(
                  labelText: 'Nombre Completo (Opcional)',
                  hintText: 'Ej. Juan Carlos Pérez',
                  prefixIcon: Icon(Icons.person_rounded, color: AppTheme.slate600),
                ),
              ),
              const SizedBox(height: 20),

              // Botón para Enviar Asistencia
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.send_rounded, size: 20),
                  label: const Text(
                    'Enviar Asistencia al Sistema',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isEntry ? AppTheme.accreditedColor : AppTheme.primary,
                  ),
                  onPressed: () async {
                    final controlNumber = _controlNumberController.text.trim();
                    final fullName = _fullNameController.text.trim();

                    if (controlNumber.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Por favor escribe tu Número de Control.'),
                          backgroundColor: AppTheme.absentColor,
                        ),
                      );
                      return;
                    }

                    // Guardar en el celular del estudiante
                    await _saveStudentData(controlNumber, fullName);

                    if (!ctx.mounted) return;
                    Navigator.pop(ctx); // Cierra modal
                    _processAttendance(qrContent, controlNumber, fullName);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _processAttendance(String qrContent, String controlNumber, String fullName) {
    final provider = context.read<AttendanceProvider>();
    final result = provider.processQrScan(
      qrRawContent: qrContent,
      studentEnrollmentNumber: controlNumber,
      studentFullName: fullName.isNotEmpty ? fullName : 'Alumno $controlNumber',
    );

    _showResultDialog(result, controlNumber);
  }

  void _showResultDialog(AttendanceProcessResult result, String controlNumber) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(
              result.success
                  ? (result.status != null && result.status!.name == 'accredited'
                      ? Icons.verified_rounded
                      : Icons.check_circle_rounded)
                  : Icons.warning_amber_rounded,
              color: result.success
                  ? (result.status != null && result.status!.name == 'accredited'
                      ? AppTheme.accreditedColor
                      : AppTheme.primary)
                  : AppTheme.absentColor,
              size: 28,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                result.title,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              result.message,
              style: const TextStyle(fontSize: 14, height: 1.4, color: AppTheme.slate800),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.slate100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.phone_android_rounded, size: 20, color: AppTheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'No. Control: $controlNumber',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                        ),
                        const Text(
                          'Asistencia guardada y sellada 🔒',
                          style: TextStyle(fontSize: 11, color: AppTheme.slate600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: result.success ? AppTheme.primary : AppTheme.slate700,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _resumeScanning();
            },
            child: const Text('Aceptar'),
          ),
        ],
      ),
    );
  }

  void _resumeScanning() {
    _isProcessing = false;
    _scannerController.start();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Escanear QR de Asistencia'),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            onPressed: () => _scannerController.toggleTorch(),
          ),
          IconButton(
            icon: const Icon(Icons.flip_camera_ios),
            onPressed: () => _scannerController.switchCamera(),
          ),
        ],
      ),
      body: Column(
        children: [
          // Banner recordatorio de control number
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            color: AppTheme.primaryLight,
            child: Row(
              children: [
                const Icon(Icons.badge_rounded, color: AppTheme.primary, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _savedControlNumber.isNotEmpty
                            ? 'No. Control registrado: $_savedControlNumber'
                            : 'Escanea el QR para enviar tu asistencia',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.slate900),
                      ),
                      Text(
                        _savedControlNumber.isNotEmpty
                            ? 'Asistencia automática activa en cada escaneo.'
                            : 'Tu asistencia quedará guardada en este celular y en el sistema del docente.',
                        style: const TextStyle(fontSize: 11, color: AppTheme.slate600),
                      ),
                    ],
                  ),
                ),
                if (_savedControlNumber.isNotEmpty)
                  TextButton(
                    onPressed: _clearSavedStudentData,
                    child: const Text('Cambiar', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
          ),

          // Lector de cámara QR
          Expanded(
            flex: 3,
            child: Stack(
              alignment: Alignment.center,
              children: [
                MobileScanner(
                  controller: _scannerController,
                  onDetect: (capture) {
                    final List<Barcode> barcodes = capture.barcodes;
                    for (final barcode in barcodes) {
                      if (barcode.rawValue != null) {
                        _handleQrDetection(barcode.rawValue!);
                        break;
                      }
                    }
                  },
                ),
                // Guía visual cuadrada para encuadrar el QR
                Container(
                  width: 260,
                  height: 260,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white, width: 3),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Pie de página con botón para ingresar código manual en pruebas
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Row(
                  children: [
                    Icon(Icons.info_outline_rounded, size: 18, color: AppTheme.primary),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Apunta al código QR dinámico proyectado por el docente. Al escanearlo podrás confirmar tu Número de Control.',
                        style: TextStyle(fontSize: 12, color: AppTheme.slate700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.keyboard_alt_rounded, size: 16),
                  label: const Text('Ingresar Código QR manualmente (Pruebas)'),
                  onPressed: () => _showManualInputDialog(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showManualInputDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ingreso Manual de Código QR'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Pega o escribe el contenido del QR dinámico para validar:',
              style: TextStyle(fontSize: 12, color: AppTheme.slate600),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _manualQrController,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: '{"s":"ses_...","p":"entry",...}',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () {
              final text = _manualQrController.text.trim();
              Navigator.pop(ctx);
              if (text.isNotEmpty) {
                _handleQrDetection(text);
              }
            },
            child: const Text('Validar'),
          ),
        ],
      ),
    );
  }
}
