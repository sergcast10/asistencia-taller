import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../models/session.dart';

class QrValidationResult {
  final bool isValid;
  final String? errorMessage;
  final String? sessionId;
  final String? workshopId;
  final SessionPhase? phase;

  QrValidationResult({
    required this.isValid,
    this.errorMessage,
    this.sessionId,
    this.workshopId,
    this.phase,
  });
}

class QrService {
  // Intervalo de rotación del código QR en segundos (15s es ideal para proyección)
  static const int rotationIntervalSeconds = 15;

  /// Obtiene el índice de ventana temporal actual
  static int getCurrentWindow({DateTime? now}) {
    final time = now ?? DateTime.now();
    return time.millisecondsSinceEpoch ~/ (rotationIntervalSeconds * 1000);
  }

  /// Retorna los segundos restantes antes de que cambie el QR actual
  static int getSecondsUntilNextWindow({DateTime? now}) {
    final time = now ?? DateTime.now();
    final currentMs = time.millisecondsSinceEpoch;
    final intervalMs = rotationIntervalSeconds * 1000;
    final remainingMs = intervalMs - (currentMs % intervalMs);
    return (remainingMs / 1000).ceil();
  }

  /// Extrae la carga útil JSON ya sea que el QR contenga JSON puro o una URL web (?qr=...)
  static String extractPayload(String rawContent) {
    final trimmed = rawContent.trim();
    if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
      return trimmed;
    }

    try {
      final uri = Uri.parse(trimmed);
      if (uri.queryParameters.containsKey('qr')) {
        return uri.queryParameters['qr']!;
      }
      if (uri.queryParameters.containsKey('data')) {
        return uri.queryParameters['data']!;
      }
      if (uri.queryParameters.containsKey('session') &&
          uri.queryParameters.containsKey('token')) {
        final s = uri.queryParameters['session'] ?? '';
        final w = uri.queryParameters['workshop'] ?? '';
        final p = uri.queryParameters['phase'] ?? 'entry';
        final token = uri.queryParameters['token'] ?? '';
        final parts = token.split('_');
        final window = parts.length > 1 ? int.tryParse(parts[1]) : null;
        final sig = parts.length > 2 ? parts.sublist(2).join('_') : '';
        return jsonEncode({
          's': s,
          'w': w,
          'p': p,
          if (window != null) 't': window,
          'sig': sig,
        });
      }
      if (uri.queryParameters.containsKey('token')) {
        return uri.queryParameters['token']!;
      }
    } catch (_) {}

    return trimmed;
  }

  /// Genera la carga útil encriptada que se codificará en el código QR
  /// Si se especifica [webBaseUrl], genera una URL web limpia y corta
  /// para que la cámara del celular del alumno la abra automáticamente en el navegador.
  static String generateDynamicQrData({
    required String sessionId,
    required String workshopId,
    required SessionPhase phase,
    required String secretKey,
    String? webBaseUrl,
    DateTime? now,
    int? toleranceMinutes,
    int? registrationWindowMinutes,
    DateTime? phaseStartedAt,
  }) {
    final window = getCurrentWindow(now: now);
    final rawData = '$sessionId:${phase.name}:$window';

    // Firma HMAC-SHA256
    final hmac = Hmac(sha256, utf8.encode(secretKey));
    final signature = hmac.convert(utf8.encode(rawData)).toString().substring(0, 12);

    final payload = <String, dynamic>{
      's': sessionId,
      'w': workshopId,
      'p': phase.name,
      't': window,
      'sig': signature,
      if (toleranceMinutes != null) 'tol': toleranceMinutes,
      if (registrationWindowMinutes != null) 'win': registrationWindowMinutes,
      if (phaseStartedAt != null) 'start': phaseStartedAt.millisecondsSinceEpoch,
    };

    final jsonStr = jsonEncode(payload);

    if (webBaseUrl != null && webBaseUrl.trim().isNotEmpty) {
      final cleanBase = webBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
      final dynamicToken = '${phase.name}_${window}_$signature';
      final separator = cleanBase.contains('?') ? '&' : '?';
      final extraParams = StringBuffer();
      if (toleranceMinutes != null && toleranceMinutes != 15) {
        extraParams.write('&tol=$toleranceMinutes');
      }
      if (registrationWindowMinutes != null && registrationWindowMinutes != 45) {
        extraParams.write('&win=$registrationWindowMinutes');
      }
      if (phaseStartedAt != null) {
        extraParams.write('&start=${phaseStartedAt.millisecondsSinceEpoch}');
      }
      return '$cleanBase${separator}session=$sessionId&workshop=$workshopId&phase=${phase.name}&token=$dynamicToken$extraParams';
    }

    return jsonStr;
  }

  /// Valida la lectura de un código QR contra la sesión activa
  static QrValidationResult validateQrData({
    required String qrRawContent,
    required WorkshopSession currentSession,
  }) {
    try {
      final payloadStr = extractPayload(qrRawContent);
      final Map<String, dynamic> data = jsonDecode(payloadStr);
      final sessionId = data['s'] as String?;
      final workshopId = data['w'] as String?;
      final phaseName = data['p'] as String?;
      final window = data['t'] as int?;
      final signature = data['sig'] as String?;

      if (sessionId == null || phaseName == null || window == null || signature == null) {
        return QrValidationResult(
          isValid: false,
          errorMessage: 'Formato de QR no reconocido por el sistema de asistencia.',
        );
      }

      // 1. Validar que corresponda a la sesión actual
      if (sessionId != currentSession.id) {
        return QrValidationResult(
          isValid: false,
          errorMessage: 'El código corresponde a otra sesión o taller distinto.',
        );
      }

      // 2. Validar que el docente tenga activo el pase de lista
      if (!currentSession.isQrActive) {
        return QrValidationResult(
          isValid: false,
          errorMessage: 'El docente tiene el pase de lista pausado o cerrado en este momento.',
        );
      }

      // 3. Validar fase (Entrada vs Salida)
      if (phaseName != currentSession.currentPhase.name) {
        return QrValidationResult(
          isValid: false,
          errorMessage: 'El código pertenece a la fase "${phaseName == "entry" ? "Entrada" : "Salida"}", pero el docente tiene activa la fase "${currentSession.currentPhase == SessionPhase.entry ? "Entrada" : "Salida"}".',
        );
      }

      // 4. Validar expiración temporal (Tolerancia de máximo 1 intervalo = 15-30s para compensar latencia)
      final currentWindow = getCurrentWindow();
      final windowDiff = (currentWindow - window).abs();

      if (windowDiff > 1) {
        return QrValidationResult(
          isValid: false,
          errorMessage: '¡CÓDIGO EXPIRADO! Han pasado más de 15 segundos desde que este código se generó. Por seguridad, no se admiten fotos ni códigos reutilizados. Escanea el QR activo en la pantalla del docente.',
        );
      }

      // 5. Validar firma criptográfica
      final rawData = '$sessionId:$phaseName:$window';
      final hmac = Hmac(sha256, utf8.encode(currentSession.secretKey));
      final expectedSignature = hmac.convert(utf8.encode(rawData)).toString().substring(0, 12);

      if (signature != expectedSignature) {
        return QrValidationResult(
          isValid: false,
          errorMessage: 'Firma de seguridad inválida o código adulterado.',
        );
      }

      final phase = SessionPhase.values.firstWhere(
        (e) => e.name == phaseName,
        orElse: () => SessionPhase.pending,
      );

      return QrValidationResult(
        isValid: true,
        sessionId: sessionId,
        workshopId: workshopId,
        phase: phase,
      );
    } catch (e) {
      return QrValidationResult(
        isValid: false,
        errorMessage: 'Error al interpretar el código: ${e.toString()}',
      );
    }
  }
}
