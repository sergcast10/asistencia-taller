import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/attendance_record.dart';
import '../models/session.dart';
import '../models/student.dart';
import '../models/workshop.dart';
import '../utils/app_theme.dart';
import '../utils/pdf_exporter.dart';

class SessionEvidenceDialog {
  static String _fmtShort(DateTime? dt) {
    if (dt == null) return 'Sin registro';
    final l = dt.toLocal();
    return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}:${l.second.toString().padLeft(2, '0')} hrs';
  }

  /// Muestra la Evidencia Oficial de la Sesión y la Lista de Alumnos con diseño profesional de tarjetas y lista estructurada + botón de Descarga PDF
  static void showSessionEvidence({
    required BuildContext context,
    required Workshop workshop,
    required WorkshopSession session,
  }) {
    final cumplieron = <Student>[];
    final faltoSalida = <Student>[];
    final noEntraron = <Student>[];

    for (final s in workshop.enrolledStudents) {
      final rec = session.records[s.id];
      final st = rec?.status ?? AttendanceStatus.absent;
      if (st == AttendanceStatus.accredited) {
        cumplieron.add(s);
      } else if (st == AttendanceStatus.incompleteEntryOnly ||
          st == AttendanceStatus.incompleteExitOnly) {
        faltoSalida.add(s);
      } else {
        noEntraron.add(s);
      }
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
        contentPadding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.primaryLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.verified_rounded,
                color: AppTheme.primary,
                size: 22,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Acta y Evidencia Oficial de Sesión',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.slate900,
                    ),
                  ),
                  Text(
                    '${workshop.name} (${workshop.code})',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.slate600,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 580,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. FICHA INSTITUCIONAL DE LA SESIÓN (LISTA DE METADATOS)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.slate50,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.slate200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '1. DATOS OFICIALES DE LA SESIÓN Y HORARIO',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.primary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildInfoRow(
                        Icons.class_rounded,
                        'Sesión / Sección:',
                        session.title,
                      ),
                      _buildInfoRow(
                        Icons.calendar_today_rounded,
                        'Día de Realización:',
                        session.formattedDateWithDay,
                      ),
                      _buildInfoRow(
                        Icons.access_time_filled_rounded,
                        'Horario Establecido:',
                        'Comenzó ${session.startTimeLabel} hrs ➔ Terminó ${session.endTimeLabel} hrs',
                      ),
                      _buildInfoRow(
                        Icons.verified_user_rounded,
                        'Sello de Ejecución:',
                        session.executionEvidenceSummary,
                      ),
                      _buildInfoRow(
                        Icons.person_rounded,
                        'Docente Responsable:',
                        workshop.instructorName.isNotEmpty
                            ? workshop.instructorName
                            : 'Docente Titular',
                      ),
                      _buildInfoRow(
                        Icons.timer_outlined,
                        'Tolerancia Puntual:',
                        '${session.toleranceMinutes} minutos',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // 2. TARJETAS RESUMEN DE CUMPLIMIENTO
                Row(
                  children: [
                    Expanded(
                      child: _buildSummaryChip(
                        title: 'Cumplieron',
                        count: cumplieron.length,
                        subtitle: 'Entrada + Salida',
                        color: AppTheme.accreditedColor,
                        bg: AppTheme.accreditedBg,
                        icon: Icons.check_circle_rounded,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildSummaryChip(
                        title: 'Faltó Salida',
                        count: faltoSalida.length,
                        subtitle: 'Solo Entrada',
                        color: AppTheme.incompleteColor,
                        bg: AppTheme.incompleteBg,
                        icon: Icons.warning_amber_rounded,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildSummaryChip(
                        title: 'No Entraron',
                        count: noEntraron.length,
                        subtitle: 'Sin registro',
                        color: AppTheme.absentColor,
                        bg: AppTheme.absentBg,
                        icon: Icons.cancel_rounded,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // 3. LISTA ESTRUCTURADA DE ALUMNOS Y SU CUMPLIMIENTO
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '2. LISTA DE ALUMNOS (${workshop.enrolledStudents.length} INSCRITOS)',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (workshop.enrolledStudents.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.slate200),
                    ),
                    child: const Text(
                      'Aún no hay alumnos inscritos en el padrón de este taller.',
                      style: TextStyle(fontSize: 12, color: AppTheme.slate600),
                    ),
                  )
                else
                  ...List.generate(workshop.enrolledStudents.length, (idx) {
                    final student = workshop.enrolledStudents[idx];
                    final rec = session.records[student.id];
                    final st = rec?.status ?? AttendanceStatus.absent;

                    String statusLabel;
                    Color statusColor;
                    Color statusBg;
                    IconData statusIcon;

                    if (st == AttendanceStatus.accredited) {
                      statusLabel = 'CUMPLIÓ (Entrada y Salida OK)';
                      statusColor = AppTheme.accreditedColor;
                      statusBg = AppTheme.accreditedBg;
                      statusIcon = Icons.check_circle_rounded;
                    } else if (st == AttendanceStatus.incompleteEntryOnly) {
                      statusLabel = 'LE FALTÓ LA SALIDA (Solo Entrada)';
                      statusColor = AppTheme.incompleteColor;
                      statusBg = AppTheme.incompleteBg;
                      statusIcon = Icons.warning_amber_rounded;
                    } else if (st == AttendanceStatus.incompleteExitOnly) {
                      statusLabel = 'LE FALTÓ LA ENTRADA';
                      statusColor = AppTheme.incompleteColor;
                      statusBg = AppTheme.incompleteBg;
                      statusIcon = Icons.warning_amber_rounded;
                    } else {
                      statusLabel = 'NO ENTRÓ A LA SESIÓN';
                      statusColor = AppTheme.absentColor;
                      statusBg = AppTheme.absentBg;
                      statusIcon = Icons.cancel_rounded;
                    }

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: st == AttendanceStatus.accredited
                              ? AppTheme.accreditedColor.withValues(alpha: 0.35)
                              : AppTheme.slate200,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 26,
                                height: 26,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: statusBg,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '${idx + 1}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: statusColor,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      student.fullName,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                        color: AppTheme.slate900,
                                      ),
                                    ),
                                    Text(
                                      'Matrícula: ${student.enrollmentNumber}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: AppTheme.slate600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: statusBg,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      statusIcon,
                                      size: 13,
                                      color: statusColor,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      statusLabel,
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        color: statusColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.slate50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.login_rounded,
                                  size: 13,
                                  color: AppTheme.accreditedColor,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    'Entrada: ${_fmtShort(rec?.checkInTime)}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.slate800,
                                    ),
                                  ),
                                ),
                                const Icon(
                                  Icons.logout_rounded,
                                  size: 13,
                                  color: AppTheme.primary,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    'Salida: ${_fmtShort(rec?.checkOutTime)}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.slate800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (rec?.hasNotes == true) ...[
                            const SizedBox(height: 6),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF5F3FF),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '📌 Evidencia: ${rec!.notes}',
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF4C1D95),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  }),
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
            icon: const Icon(Icons.picture_as_pdf_rounded, size: 17),
            label: const Text('Descargar / Enviar PDF de Evidencia'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              PdfExporter.downloadOrShareSessionPdf(
                context: context,
                workshop: workshop,
                session: session,
              );
            },
          ),
        ],
      ),
    );
  }

  /// Muestra el Comprobante Individual de Evidencia del Alumno con diseño de tarjeta estructurada y descarga PDF
  static void showStudentEvidence({
    required BuildContext context,
    required Workshop workshop,
    required WorkshopSession session,
    required Student student,
    required AttendanceRecord record,
  }) {
    final isAccredited = record.status == AttendanceStatus.accredited;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F3FF),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.verified_user_rounded,
                color: Color(0xFF7C3AED),
                size: 22,
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Comprobante Oficial de Evidencia del Alumno',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.slate50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.slate200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildInfoRow(
                        Icons.person_rounded,
                        'Alumno:',
                        student.fullName,
                      ),
                      _buildInfoRow(
                        Icons.badge_rounded,
                        'Matrícula / Control:',
                        student.enrollmentNumber,
                      ),
                      _buildInfoRow(
                        Icons.school_rounded,
                        'Taller:',
                        '${workshop.name} (${workshop.code})',
                      ),
                      _buildInfoRow(
                        Icons.class_rounded,
                        'Sesión:',
                        session.title,
                      ),
                      _buildInfoRow(
                        Icons.calendar_today_rounded,
                        'Día de Realización:',
                        session.formattedDateWithDay,
                      ),
                      _buildInfoRow(
                        Icons.access_time_filled_rounded,
                        'Horario de Sesión:',
                        '${session.startTimeLabel} hrs ➔ ${session.endTimeLabel} hrs',
                      ),
                      _buildInfoRow(
                        Icons.login_rounded,
                        'Hora Entrada:',
                        _fmtShort(record.checkInTime),
                      ),
                      _buildInfoRow(
                        Icons.logout_rounded,
                        'Hora Salida:',
                        _fmtShort(record.checkOutTime),
                      ),
                      _buildInfoRow(
                        Icons.check_circle_rounded,
                        'Estatus al Cierre:',
                        isAccredited
                            ? 'CUMPLIÓ (Acreditado con Entrada y Salida)'
                            : 'Asistencia Registrada en Sala',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F3FF),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFC4B5FD)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Circunstancia / Evidencia Registrada:',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF4C1D95),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        record.notes ?? 'Asistencia validada por el docente.',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF5B21B6),
                        ),
                      ),
                    ],
                  ),
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
          OutlinedButton.icon(
            icon: const Icon(Icons.copy_rounded, size: 15),
            label: const Text('Copiar'),
            onPressed: () {
              final text =
                  'EVIDENCIA OFICIAL (${workshop.name} - ${session.title})\n'
                  'Alumno: ${student.fullName} (${student.enrollmentNumber})\n'
                  'Fecha: ${session.formattedDateWithDay}\n'
                  'Evidencia: ${record.notes ?? "Asistencia validada"}';
              Clipboard.setData(ClipboardData(text: text));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('📋 Evidencia copiada al portapapeles.'),
                  backgroundColor: AppTheme.accreditedColor,
                ),
              );
            },
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.picture_as_pdf_rounded, size: 16),
            label: const Text('Descargar / Enviar PDF'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              PdfExporter.downloadOrShareStudentPdf(
                context: context,
                workshop: workshop,
                session: session,
                student: student,
                record: record,
              );
            },
          ),
        ],
      ),
    );
  }

  static Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: AppTheme.primary),
          const SizedBox(width: 8),
          SizedBox(
            width: 135,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: AppTheme.slate700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: AppTheme.slate900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _buildSummaryChip({
    required String title,
    required int count,
    required String subtitle,
    required Color color,
    required Color bg,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

