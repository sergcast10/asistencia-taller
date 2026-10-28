import 'package:flutter/material.dart';
import '../models/attendance_record.dart';
import '../utils/app_theme.dart';

class StudentStatusBadge extends StatelessWidget {
  final AttendanceStatus status;

  const StudentStatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color text;
    IconData icon;
    String label;

    switch (status) {
      case AttendanceStatus.accredited:
        bg = AppTheme.accreditedBg;
        text = AppTheme.accreditedColor;
        icon = Icons.check_circle_rounded;
        label = 'Acreditado';
        break;
      case AttendanceStatus.incompleteEntryOnly:
        bg = AppTheme.incompleteBg;
        text = AppTheme.incompleteColor;
        icon = Icons.warning_rounded;
        label = 'Solo Entrada';
        break;
      case AttendanceStatus.incompleteExitOnly:
        bg = AppTheme.incompleteBg;
        text = AppTheme.incompleteColor;
        icon = Icons.warning_rounded;
        label = 'Solo Salida';
        break;
      case AttendanceStatus.absent:
        bg = AppTheme.absentBg;
        text = AppTheme.absentColor;
        icon = Icons.cancel_rounded;
        label = 'Inasistencia';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: text.withOpacity(0.3), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: text),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: text,
            ),
          ),
        ],
      ),
    );
  }
}
