import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/attendance_record.dart';
import '../../providers/attendance_provider.dart';
import '../../services/qr_service.dart';
import '../../utils/app_theme.dart';

class StudentWebAttendanceScreen extends StatefulWidget {
  final String qrToken;

  const StudentWebAttendanceScreen({super.key, required this.qrToken});

  @override
  State<StudentWebAttendanceScreen> createState() =>
      _StudentWebAttendanceScreenState();
}

class _StudentWebAttendanceScreenState
    extends State<StudentWebAttendanceScreen> {
  bool _isLoading = true;
  bool _isAutoSubmitted = false;

  String _savedControlNumber = '';
  String _savedFullName = '';

  final _controlNumberController = TextEditingController();
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  AttendanceProcessResult? _attendanceResult;
  String? _preliminaryPhase;

  @override
  void initState() {
    super.initState();
    _parsePreliminaryPayload();
    _checkSavedStudentAndProcess();
  }

  @override
  void dispose() {
    _controlNumberController.dispose();
    _fullNameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  void _parsePreliminaryPayload() {
    try {
      final payloadStr = QrService.extractPayload(widget.qrToken);
      if (payloadStr.startsWith('{')) {
        final map = jsonDecode(payloadStr);
        _preliminaryPhase = map['p'] as String?;
      }
    } catch (_) {}
  }

  Future<void> _checkSavedStudentAndProcess() async {
    final prefs = await SharedPreferences.getInstance();
    final savedControl = prefs.getString('student_saved_control_number') ?? '';
    final savedName = prefs.getString('student_saved_full_name') ?? '';
    final savedEmail = prefs.getString('student_saved_email') ?? '';

    if (!mounted) return;

    setState(() {
      _savedControlNumber = savedControl;
      _savedFullName = savedName;
      _controlNumberController.text = savedControl;
      _fullNameController.text = savedName;
      _emailController.text = savedEmail;
    });

    // Esperar a que el provider termine de inicializarse
    final provider = context.read<AttendanceProvider>();
    if (provider.isLoading) {
      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
    }

    // SI YA ESTÁ REGISTRADO EN ESTE CELULAR: Procesar automáticamente en 1 segundo
    if (savedControl.isNotEmpty && !_isAutoSubmitted) {
      _isAutoSubmitted = true;
      _executeAttendanceRegistration(
        controlNumber: savedControl,
        fullName: savedName,
        email: savedEmail,
      );
    } else {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _executeAttendanceRegistration({
    required String controlNumber,
    required String fullName,
    String? email,
  }) {
    final provider = context.read<AttendanceProvider>();
    final result = provider.processQrScan(
      qrRawContent: widget.qrToken,
      studentEnrollmentNumber: controlNumber.trim(),
      studentFullName: fullName.trim().isNotEmpty
          ? fullName.trim()
          : 'Alumno $controlNumber',
      studentEmail: email?.trim(),
    );

    setState(() {
      _attendanceResult = result;
      _isLoading = false;
    });
  }

  Future<void> _handleFirstTimeSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    final control = _controlNumberController.text.trim();
    final name = _fullNameController.text.trim();
    final email = _emailController.text.trim();

    setState(() => _isLoading = true);

    // Guardar en este teléfono para futuros escaneos automáticos
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('student_saved_control_number', control);
    await prefs.setString('student_saved_full_name', name);
    if (email.isNotEmpty) {
      await prefs.setString('student_saved_email', email);
    }

    setState(() {
      _savedControlNumber = control;
      _savedFullName = name;
    });

    _executeAttendanceRegistration(
      controlNumber: control,
      fullName: name,
      email: email,
    );
  }

  Future<void> _handleResetSavedData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('student_saved_control_number');
    await prefs.remove('student_saved_full_name');
    await prefs.remove('student_saved_email');

    setState(() {
      _savedControlNumber = '';
      _savedFullName = '';
      _controlNumberController.clear();
      _fullNameController.clear();
      _emailController.clear();
      _attendanceResult = null;
      _isLoading = false;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Datos desvinculados de este celular. Ahora puedes registrar a otro alumno.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.slate100,
      appBar: AppBar(
        title: const Text('Registro de Asistencia'),
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: _isLoading
                ? _buildLoadingCard()
                : _attendanceResult != null
                ? _buildResultCard(_attendanceResult!)
                : _buildRegistrationFormCard(),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingCard() {
    return Container(
      padding: const EdgeInsets.all(36),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 20),
          const Text(
            'Validando código QR dinámico...',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppTheme.slate800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _savedControlNumber.isNotEmpty
                ? 'Identificado: $_savedFullName ($_savedControlNumber)'
                : 'Conectando con el sistema...',
            style: const TextStyle(fontSize: 13, color: AppTheme.slate600),
          ),
        ],
      ),
    );
  }

  Widget _buildRegistrationFormCard() {
    final isEntry = _preliminaryPhase != 'exit';

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.slate200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Encabezado de la fase detectada
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isEntry
                        ? AppTheme.accreditedBg
                        : AppTheme.primaryLight,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    isEntry ? Icons.login_rounded : Icons.logout_rounded,
                    color: isEntry
                        ? AppTheme.accreditedColor
                        : AppTheme.primary,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isEntry ? 'PASE DE ENTRADA' : 'PASE DE SALIDA',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: isEntry
                              ? AppTheme.accreditedColor
                              : AppTheme.primary,
                        ),
                      ),
                      const Text(
                        'Registro de Asistencia Oficial',
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
            const Divider(height: 28),

            // Tarjeta informativa sobre el registro único
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.primaryLight.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppTheme.primary.withValues(alpha: 0.2),
                ),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.phone_android_rounded,
                    color: AppTheme.primary,
                    size: 20,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Registro Único en este Celular:\nIngresa tus datos una sola vez. Tu celular los recordará para que en la salida o próximas clases tu asistencia se registre en 1 segundo de forma automática.',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: AppTheme.slate800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Campo: Número de Control
            const Text(
              'Número de Control / Matrícula *',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppTheme.slate800,
              ),
            ),
            const SizedBox(height: 6),
            TextFormField(
              controller: _controlNumberController,
              decoration: const InputDecoration(
                hintText: 'Ej. 21010482 o PAV-101',
                prefixIcon: Icon(Icons.badge_rounded, color: AppTheme.primary),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'El Número de Control es obligatorio.';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Campo: Nombre Completo
            const Text(
              'Nombre Completo *',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppTheme.slate800,
              ),
            ),
            const SizedBox(height: 6),
            TextFormField(
              controller: _fullNameController,
              decoration: const InputDecoration(
                hintText: 'Ej. Juan Carlos Pérez Morales',
                prefixIcon: Icon(
                  Icons.person_rounded,
                  color: AppTheme.slate600,
                ),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'Por favor escribe tu nombre completo.';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Campo: Correo Institucional
            const Text(
              'Correo Institucional (Opcional)',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppTheme.slate800,
              ),
            ),
            const SizedBox(height: 6),
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                hintText: 'Ej. alumno@itpav.edu.mx',
                prefixIcon: Icon(
                  Icons.alternate_email_rounded,
                  color: AppTheme.slate600,
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Botón de Envío
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.check_circle_rounded, size: 22),
                label: const Text(
                  'Confirmar y Enviar Asistencia 🔒',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isEntry
                      ? AppTheme.accreditedColor
                      : AppTheme.primary,
                ),
                onPressed: _handleFirstTimeSubmit,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard(AttendanceProcessResult result) {
    final isSuccess = result.success;
    final isAccredited = result.status == AttendanceStatus.accredited;
    final cardColor = isSuccess
        ? (isAccredited ? AppTheme.accreditedColor : AppTheme.primary)
        : AppTheme.absentColor;

    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cardColor.withValues(alpha: 0.3), width: 2),
        boxShadow: [
          BoxShadow(
            color: cardColor.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Icono principal de estado
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isSuccess ? AppTheme.accreditedBg : AppTheme.absentBg,
              shape: BoxShape.circle,
            ),
            child: Icon(
              isSuccess
                  ? (isAccredited
                        ? Icons.verified_rounded
                        : Icons.task_alt_rounded)
                  : Icons.warning_rounded,
              size: 54,
              color: isSuccess
                  ? AppTheme.accreditedColor
                  : AppTheme.absentColor,
            ),
          ),
          const SizedBox(height: 20),

          // Título del resultado
          Text(
            result.title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: cardColor,
            ),
          ),
          const SizedBox(height: 12),

          // Mensaje explicativo
          Text(
            result.message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              height: 1.45,
              color: AppTheme.slate700,
            ),
          ),
          const SizedBox(height: 20),

          // Tarjeta de Identidad y Sellado
          if (result.student != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.slate50,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.slate200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.phone_android_rounded,
                        size: 20,
                        color: AppTheme.primary,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Celular Vinculado al Alumno',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.slate600,
                        ),
                      ),
                      const Spacer(),
                      const Icon(
                        Icons.lock_rounded,
                        size: 14,
                        color: AppTheme.slate600,
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        'Sellado Inmutable',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.slate600,
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 16),
                  Text(
                    result.student!.fullName,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.slate900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'No. Control: ${result.student!.enrollmentNumber}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.slate700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],

          // Tarjeta informativa antifraude
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.slate100,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.security_rounded,
                  size: 18,
                  color: AppTheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isSuccess
                        ? 'Tu asistencia quedó registrada en este teléfono y en la consola oficial del docente.'
                        : 'Si el código expiró, apunta de nuevo al proyector para escanear el QR actual.',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.slate600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Enlace discreto para cambiar número de control si se equivocó
          TextButton.icon(
            icon: const Icon(Icons.switch_account_rounded, size: 16),
            label: const Text(
              '¿No eres tú? Cambiar datos guardados en este celular',
              style: TextStyle(fontSize: 12),
            ),
            onPressed: _handleResetSavedData,
          ),
        ],
      ),
    );
  }
}
