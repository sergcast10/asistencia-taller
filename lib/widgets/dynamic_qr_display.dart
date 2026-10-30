import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/session.dart';
import '../models/workshop.dart';
import '../providers/attendance_provider.dart';
import '../services/qr_service.dart';
import '../utils/app_theme.dart';

class DynamicQrDisplay extends StatefulWidget {
  final WorkshopSession session;
  final String workshopId;

  const DynamicQrDisplay({
    super.key,
    required this.session,
    required this.workshopId,
  });

  @override
  State<DynamicQrDisplay> createState() => _DynamicQrDisplayState();
}

class _DynamicQrDisplayState extends State<DynamicQrDisplay> {
  Timer? _ticker;
  int _secondsLeft = QrService.rotationIntervalSeconds;
  String _currentQrData = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshQr();
      _startTicker();
    });
  }

  @override
  void didUpdateWidget(covariant DynamicQrDisplay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.currentPhase != widget.session.currentPhase ||
        oldWidget.session.id != widget.session.id) {
      _refreshQr();
    }
  }

  void _refreshQr() {
    if (!mounted) return;
    final provider = context.read<AttendanceProvider>();
    final workshop = provider.workshops.cast<Workshop?>().firstWhere(
      (w) => w?.id == widget.workshopId,
      orElse: () => null,
    );
    final isConf = workshop?.isConference ?? false;

    setState(() {
      _secondsLeft = QrService.getSecondsUntilNextWindow();
      _currentQrData = QrService.generateDynamicQrData(
        sessionId: widget.session.id,
        workshopId: widget.workshopId,
        phase: widget.session.currentPhase,
        secretKey: widget.session.secretKey,
        webBaseUrl: provider.webBaseUrl.isNotEmpty ? provider.webBaseUrl : null,
        toleranceMinutes: widget.session.toleranceMinutes,
        registrationWindowMinutes: widget.session.registrationWindowMinutes,
        phaseStartedAt: widget.session.phaseStartedAt,
        isConference: isConf,
      );
    });
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      final remaining = QrService.getSecondsUntilNextWindow();
      if (remaining >= _secondsLeft && _secondsLeft <= 1) {
        // Nueva ventana
        _refreshQr();
      } else {
        setState(() {
          _secondsLeft = remaining;
        });
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AttendanceProvider>();
    final workshop = provider.workshops.cast<Workshop?>().firstWhere(
      (w) => w?.id == widget.workshopId,
      orElse: () => null,
    );
    final isConf = workshop?.isConference ?? false;

    final isEntry = widget.session.currentPhase == SessionPhase.entry;
    final phaseColor = isConf
        ? const Color(0xFF7C3AED)
        : (isEntry ? AppTheme.accreditedColor : AppTheme.primary);
    final phaseBg = isConf
        ? const Color(0xFFF5F3FF)
        : (isEntry ? AppTheme.accreditedBg : AppTheme.primaryLight);
    final phaseTitle = isConf
        ? '🎤 PASE ÚNICO DE CONFERENCIA'
        : (isEntry ? 'PASE DE ENTRADA' : 'PASE DE SALIDA');

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: phaseColor.withValues(alpha: 0.3), width: 2),
        boxShadow: [
          BoxShadow(
            color: phaseColor.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Encabezado de la fase
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: phaseBg,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: phaseColor.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isEntry ? Icons.login_rounded : Icons.logout_rounded,
                  color: phaseColor,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  phaseTitle,
                  style: TextStyle(
                    color: phaseColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Código QR Dinámico
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.slate200),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: QrImageView(
              data: _currentQrData,
              version: QrVersions.auto,
              size: 240.0,
              eyeStyle: QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: AppTheme.slate900,
              ),
              dataModuleStyle: QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: AppTheme.slate900,
              ),
            ),
          ),
          const SizedBox(height: 18),

          // Contador de rotación con barra de progreso
          Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.lock_clock_rounded, size: 16, color: phaseColor),
                  const SizedBox(width: 6),
                  Text(
                    'Código dinámico activo • Rota en $_secondsLeft s',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.slate800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: 200,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: _secondsLeft / QrService.rotationIntervalSeconds,
                    backgroundColor: AppTheme.slate200,
                    valueColor: AlwaysStoppedAnimation<Color>(phaseColor),
                    minHeight: 6,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          const SizedBox(height: 14),

          // Estado del Enlace Web para Alumnos
          Consumer<AttendanceProvider>(
            builder: (context, provider, _) {
              final hasUrl = provider.webBaseUrl.isNotEmpty;
              return Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.shield_outlined,
                        size: 14,
                        color: AppTheme.slate600,
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'Seguridad antifraude (15s)',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.slate600,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 12),
                      InkWell(
                        onTap: () => _showWebUrlConfigDialog(context, provider),
                        borderRadius: BorderRadius.circular(6),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.settings_outlined,
                                size: 14,
                                color: AppTheme.primary,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'Configurar enlace',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (!hasUrl)
                    InkWell(
                      onTap: () => _showWebUrlConfigDialog(context, provider),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF3C7),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFF59E0B)),
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              color: Color(0xFFB45309),
                              size: 18,
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '⚠️ Falta enlace web. Toca aquí para ingresar la URL y que los celulares abran el formulario al escanear.',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF92400E),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Icon(
                              Icons.arrow_forward_ios_rounded,
                              color: Color(0xFFB45309),
                              size: 12,
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      alignment: WrapAlignment.center,
                      children: [
                        InkWell(
                          onTap: () =>
                              _showWebUrlConfigDialog(context, provider),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFECFDF5),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: const Color(0xFF10B981)
                                    .withValues(alpha: 0.4),
                              ),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.check_circle_rounded,
                                  color: Color(0xFF059669),
                                  size: 14,
                                ),
                                SizedBox(width: 6),
                                Text(
                                  'Portal Web Activo',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF065F46),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                SizedBox(width: 6),
                                Icon(
                                  Icons.edit_rounded,
                                  color: Color(0xFF059669),
                                  size: 12,
                                ),
                              ],
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: () {
                            Clipboard.setData(
                              ClipboardData(text: _currentQrData),
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  '📋 Enlace de asistencia copiado al portapapeles.',
                                ),
                                backgroundColor: AppTheme.accreditedColor,
                                duration: Duration(seconds: 2),
                              ),
                            );
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.slate100,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppTheme.slate200),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.copy_rounded,
                                  color: AppTheme.primary,
                                  size: 13,
                                ),
                                SizedBox(width: 5),
                                Text(
                                  'Copiar enlace',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  void _showWebUrlConfigDialog(
    BuildContext context,
    AttendanceProvider provider,
  ) {
    final controller = TextEditingController(text: provider.webBaseUrl);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Row(
          children: [
            Icon(Icons.link_rounded, color: AppTheme.primary),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Enlace para Alumnos',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                labelText: 'Dirección Web del Portal',
                hintText: 'https://...',
                prefixIcon: const Icon(Icons.public_rounded),
                suffixIcon: IconButton(
                  tooltip: 'Copiar enlace',
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  onPressed: () {
                    Clipboard.setData(
                      ClipboardData(text: controller.text.trim()),
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('📋 Enlace copiado.'),
                        backgroundColor: AppTheme.accreditedColor,
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(
                  Icons.cloud_done_rounded,
                  size: 16,
                  color: AppTheme.primary,
                ),
                label: const Text(
                  'Restaurar Portal Oficial en la Nube',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
                onPressed: () {
                  controller.text =
                      'https://sergcast10.github.io/asistencia-taller';
                },
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              await provider.setWebBaseUrl(controller.text.trim());
              _refreshQr();
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }
}
