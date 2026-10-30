import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../../models/workshop.dart';
import '../../models/session.dart';
import '../../models/student.dart';
import '../../models/attendance_record.dart';
import '../../providers/attendance_provider.dart';
import '../../utils/app_theme.dart';

class TeacherQrScannerScreen extends StatefulWidget {
  final Workshop workshop;
  final WorkshopSession session;

  const TeacherQrScannerScreen({
    super.key,
    required this.workshop,
    required this.session,
  });

  @override
  State<TeacherQrScannerScreen> createState() => _TeacherQrScannerScreenState();
}

class _TeacherQrScannerScreenState extends State<TeacherQrScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
  );

  bool _isProcessing = false;
  String? _lastScannedCode;
  DateTime? _lastScannedTime;

  AttendanceProcessResult? _latestResult;
  int _scannedInThisSessionCount = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isProcessing) return;

    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final String? rawValue = barcodes.first.rawValue;
    if (rawValue == null || rawValue.trim().isEmpty) return;

    final cleanCode = rawValue.trim();

    // Evitar leer el mismo código repetidamente en menos de 2 segundos
    if (_lastScannedCode == cleanCode &&
        _lastScannedTime != null &&
        DateTime.now().difference(_lastScannedTime!).inSeconds < 2) {
      return;
    }

    _lastScannedCode = cleanCode;
    _lastScannedTime = DateTime.now();

    _handleStudentQrScanned(cleanCode);
  }

  void _handleStudentQrScanned(String rawCode) {
    setState(() => _isProcessing = true);

    // 1. Extraer número de control del QR / Código de barras
    final controlNumber = _extractControlNumber(rawCode);

    final provider = context.read<AttendanceProvider>();
    final currentWorkshop = provider.workshops.firstWhere(
      (w) => w.id == widget.workshop.id,
      orElse: () => widget.workshop,
    );
    final currentSession = currentWorkshop.sessions.firstWhere(
      (s) => s.id == widget.session.id,
      orElse: () => widget.session,
    );

    // 2. Buscar si el alumno ya está inscrito en este taller
    Student? matchedStudent = currentWorkshop.enrolledStudents
        .cast<Student?>()
        .firstWhere(
          (s) =>
              s != null &&
              s.enrollmentNumber.trim().toUpperCase() ==
                  controlNumber.toUpperCase(),
          orElse: () => null,
        );

    if (matchedStudent != null) {
      // Alumno ya registrado -> Sellar asistencia de inmediato
      final result = provider.registerDirectAttendance(
        workshopId: currentWorkshop.id,
        sessionId: currentSession.id,
        studentId: matchedStudent.id,
        phase: currentSession.currentPhase,
      );

      setState(() {
        _latestResult = result;
        _scannedInThisSessionCount++;
      });

      // Reanudar escaneo automáticamente tras 1.8 segundos
      Future.delayed(const Duration(milliseconds: 1800), () {
        if (mounted) {
          setState(() {
            _isProcessing = false;
            _latestResult = null;
          });
        }
      });
    } else {
      // Alumno nuevo (no está en la lista del taller) -> Solicitar nombre en diálogo rápido
      _showEnrollNewStudentDialog(controlNumber);
    }
  }

  String _extractControlNumber(String raw) {
    // Si es JSON: {"control": "...", "id": "..."}
    try {
      if (raw.startsWith('{') && raw.endsWith('}')) {
        final map = jsonDecode(raw);
        if (map['enrollmentNumber'] != null) {
          return map['enrollmentNumber'].toString().trim();
        }
        if (map['controlNumber'] != null) {
          return map['controlNumber'].toString().trim();
        }
        if (map['control'] != null) {
          return map['control'].toString().trim();
        }
        if (map['id'] != null) {
          return map['id'].toString().trim();
        }
        if (map['matricula'] != null) {
          return map['matricula'].toString().trim();
        }
      }
    } catch (_) {}

    // Si es una URL: ?control=... o ?id=...
    try {
      if (raw.startsWith('http://') || raw.startsWith('https://')) {
        final uri = Uri.parse(raw);
        final param =
            uri.queryParameters['control'] ??
            uri.queryParameters['matricula'] ??
            uri.queryParameters['id'] ??
            uri.queryParameters['student'];
        if (param != null && param.isNotEmpty) return param.trim();
      }
    } catch (_) {}

    // Texto plano (ej. "21280001")
    return raw.trim();
  }

  void _showEnrollNewStudentDialog(String detectedControl) {
    final nameCtrl = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.person_add_rounded, color: AppTheme.primary),
            SizedBox(width: 10),
            Text(
              'Alumno Nuevo',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
          ],
        ),
        content: Column(
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
                'Matrícula escaneada: $detectedControl',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: AppTheme.primary,
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Esta matrícula no está en la lista. Escribe su nombre completo una sola vez para inscribirlo(a):',
              style: TextStyle(fontSize: 13, color: AppTheme.slate600),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: nameCtrl,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nombre y Apellidos',
                hintText: 'Ej. María Fernanda López',
                prefixIcon: Icon(Icons.badge_rounded),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => _isProcessing = false);
            },
            child: const Text('Ignorar'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;

              final provider = context.read<AttendanceProvider>();
              await provider.addStudentToWorkshop(
                workshopId: widget.workshop.id,
                fullName: name,
                enrollmentNumber: detectedControl,
                email: '${detectedControl.toLowerCase()}@alumno.edu',
              );

              final student = provider.workshops
                  .firstWhere((w) => w.id == widget.workshop.id)
                  .enrolledStudents
                  .firstWhere(
                    (s) =>
                        s.enrollmentNumber.trim().toUpperCase() ==
                        detectedControl.toUpperCase(),
                  );

              final result = provider.registerDirectAttendance(
                workshopId: widget.workshop.id,
                sessionId: widget.session.id,
                studentId: student.id,
                phase: widget.session.currentPhase,
              );

              if (ctx.mounted) Navigator.pop(ctx);

              setState(() {
                _latestResult = result;
                _scannedInThisSessionCount++;
              });

              Future.delayed(const Duration(milliseconds: 1800), () {
                if (mounted) {
                  setState(() {
                    _isProcessing = false;
                    _latestResult = null;
                  });
                }
              });
            },
            child: const Text('Inscribir y Sellar'),
          ),
        ],
      ),
    );
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

        final isEntry = currentSession.currentPhase == SessionPhase.entry;

        return Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Lector de Asistencia (Docente)',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  '${currentWorkshop.name} • ${isEntry ? "🟢 ENTRADA" : "🔴 SALIDA"}',
                  style: TextStyle(
                    fontSize: 11,
                    color: isEntry ? AppTheme.accreditedColor : Colors.amber,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.flash_on_rounded),
                onPressed: () => _controller.toggleTorch(),
              ),
              IconButton(
                icon: const Icon(Icons.cameraswitch_rounded),
                onPressed: () => _controller.switchCamera(),
              ),
            ],
          ),
          body: Stack(
            children: [
              // CÁMARA ESCÁNER
              MobileScanner(controller: _controller, onDetect: _onDetect),

              // RECUADRO GUÍA DE ENFOQUE
              Center(
                child: Container(
                  width: 260,
                  height: 260,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: isEntry ? AppTheme.accreditedColor : Colors.amber,
                      width: 3,
                    ),
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
              ),

              // NOTA SUPERIOR
              Positioned(
                top: 20,
                left: 20,
                right: 20,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isEntry ? Icons.login_rounded : Icons.logout_rounded,
                        color: isEntry
                            ? AppTheme.accreditedColor
                            : Colors.amber,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Apunta al QR o Credencial del Alumno (${isEntry ? "Entrada" : "Salida"})',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // TARJETA DE CONFIRMACIÓN AL ESCANEAR
              if (_latestResult != null)
                Positioned(
                  bottom: 110,
                  left: 20,
                  right: 20,
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 20,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color:
                                _latestResult!.status ==
                                    AttendanceStatus.accredited
                                ? AppTheme.accreditedBg
                                : AppTheme.primaryLight,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _latestResult!.status == AttendanceStatus.accredited
                                ? Icons.verified_rounded
                                : Icons.check_circle_rounded,
                            color:
                                _latestResult!.status ==
                                    AttendanceStatus.accredited
                                ? AppTheme.accreditedColor
                                : AppTheme.primary,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _latestResult!.title,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.slate900,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _latestResult!.student?.fullName ?? 'Alumno',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.slate800,
                                ),
                              ),
                              Text(
                                'Mat: ${_latestResult!.student?.enrollmentNumber ?? ""} 🔒 Sellado',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.slate600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // BARRA INFERIOR DE CONTROLES DEL DOCENTE
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.85),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Contador en vivo
                      Row(
                        children: [
                          const Icon(
                            Icons.people_alt_rounded,
                            color: Colors.white70,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Sellados: $_scannedInThisSessionCount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),

                      // Botón para alternar Fase (Entrada <-> Salida) sin salir de la cámara
                      ElevatedButton.icon(
                        icon: Icon(
                          isEntry
                              ? Icons.arrow_forward_rounded
                              : Icons.arrow_back_rounded,
                          size: 16,
                        ),
                        label: Text(
                          isEntry ? 'Cambiar a Salida' : 'Cambiar a Entrada',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isEntry
                              ? Colors.amber[800]
                              : AppTheme.accreditedColor,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                        ),
                        onPressed: () {
                          provider.updateSessionPhase(
                            workshopId: currentWorkshop.id,
                            sessionId: currentSession.id,
                            newPhase: isEntry
                                ? SessionPhase.exit
                                : SessionPhase.entry,
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
