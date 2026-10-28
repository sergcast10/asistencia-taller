import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/attendance_provider.dart';
import 'screens/home_screen.dart';
import 'screens/student/student_web_attendance_screen.dart';
import 'utils/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AttendanceApp());
}

class AttendanceApp extends StatelessWidget {
  const AttendanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Si el alumno escaneó el código QR con la cámara de su celular,
    // la URL contendrá ?qr=... o ?data=... (soporta rutas directas y rutas hash #/...)
    final uri = Uri.base;
    String? qrParam = uri.queryParameters['qr'] ?? uri.queryParameters['data'] ?? uri.queryParameters['token'];

    if (qrParam == null && uri.fragment.isNotEmpty) {
      try {
        final fragUri = Uri.parse('http://dummy/${uri.fragment}');
        qrParam = fragUri.queryParameters['qr'] ?? fragUri.queryParameters['data'] ?? fragUri.queryParameters['token'];
      } catch (_) {}
    }

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AttendanceProvider()),
      ],
      child: MaterialApp(
        title: 'Asistencia y Acreditación de Talleres',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: qrParam != null && qrParam.isNotEmpty
            ? StudentWebAttendanceScreen(qrToken: qrParam)
            : const HomeScreen(),
      ),
    );
  }
}

