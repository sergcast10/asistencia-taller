import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/attendance_record.dart';
import '../models/session.dart';
import '../models/student.dart';
import '../models/workshop.dart';
import '../utils/app_theme.dart';

class PdfExporter {
  /// Limpia emojis para que la fuente estándar PDF (Helvetica) renderice todos los textos y acentos españoles de forma impecable
  static String _cleanForPdf(String input) {
    return input
        .replaceAll('➔', '->')
        .replaceAll('•', '|')
        .replaceAll(
          RegExp(
            r'[^\x00-\x7F\xA0-\xFF¡¿ÁÉÍÓÚáéíóúÑñÜü«»°]',
          ),
          '',
        )
        .trim();
  }

  static String _fmtTime(DateTime? dt) {
    if (dt == null) return 'Sin registro';
    final l = dt.toLocal();
    return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}:${l.second.toString().padLeft(2, '0')} hrs';
  }

  /// Genera los bytes del PDF oficial de evidencia de la sesión y lista de alumnos al cierre
  static Future<Uint8List> generateSessionEvidencePdfBytes({
    required Workshop workshop,
    required WorkshopSession session,
  }) async {
    final doc = pw.Document(
      title: _cleanForPdf('Evidencia ${workshop.name} - ${session.title}'),
      author: _cleanForPdf(workshop.instructorName),
    );

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

    final now = DateTime.now();
    final emittedStr =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} hrs';

    final primaryPdf = PdfColor.fromInt(0xFF1E3A8A);
    final primaryLightPdf = PdfColor.fromInt(0xFFEFF6FF);
    final greenPdf = PdfColor.fromInt(0xFF065F46);
    final greenBgPdf = PdfColor.fromInt(0xFFD1FAE5);
    final amberPdf = PdfColor.fromInt(0xFF92400E);
    final amberBgPdf = PdfColor.fromInt(0xFFFEF3C7);
    final redPdf = PdfColor.fromInt(0xFF991B1B);
    final redBgPdf = PdfColor.fromInt(0xFFFEE2E2);
    final slateBorder = PdfColor.fromInt(0xFFCBD5E1);
    final slateHeader = PdfColor.fromInt(0xFFF1F5F9);
    final slateText = PdfColor.fromInt(0xFF334155);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(14),
              decoration: pw.BoxDecoration(
                color: primaryPdf,
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'ACTA OFICIAL DE EVIDENCIA Y ASISTENCIA DE TALLER',
                        style: pw.TextStyle(
                          color: PdfColors.white,
                          fontSize: 13,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 3),
                      pw.Text(
                        _cleanForPdf(
                          'Taller: ${workshop.name} (${workshop.code})',
                        ),
                        style: const pw.TextStyle(
                          color: PdfColors.white,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        'FOLIO DE EVIDENCIA',
                        style: pw.TextStyle(
                          color: PdfColors.white,
                          fontSize: 8,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.Text(
                        _cleanForPdf(session.id.toUpperCase()),
                        style: const pw.TextStyle(
                          color: PdfColors.white,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 10),
          ],
        ),
        footer: (context) => pw.Container(
          margin: const pw.EdgeInsets.only(top: 10),
          padding: const pw.EdgeInsets.only(top: 6),
          decoration: pw.BoxDecoration(
            border: pw.Border(top: pw.BorderSide(color: slateBorder)),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                _cleanForPdf(
                  'Evidencia generada el $emittedStr | ${workshop.name}',
                ),
                style: pw.TextStyle(fontSize: 8, color: slateText),
              ),
              pw.Text(
                'Página ${context.pageNumber} de ${context.pagesCount}',
                style: pw.TextStyle(fontSize: 8, color: slateText),
              ),
            ],
          ),
        ),
        build: (context) => [
          // FICHA TÉCNICA DE LA SESIÓN Y EVIDENCIA DE DÍA / HORARIO
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: primaryLightPdf,
              borderRadius: pw.BorderRadius.circular(6),
              border: pw.Border.all(color: slateBorder),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  _cleanForPdf('1. DATOS DE LA SESIÓN Y EVIDENCIA DE HORARIO'),
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                    color: primaryPdf,
                  ),
                ),
                pw.SizedBox(height: 6),
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          _pdfInfoLine(
                            'Sesión / Sección:',
                            _cleanForPdf(session.title),
                          ),
                          _pdfInfoLine(
                            'Día de Realización:',
                            _cleanForPdf(session.formattedDateWithDay),
                          ),
                          _pdfInfoLine(
                            'Docente Responsable:',
                            _cleanForPdf(
                              workshop.instructorName.isNotEmpty
                                  ? workshop.instructorName
                                  : 'Docente Titular',
                            ),
                          ),
                        ],
                      ),
                    ),
                    pw.SizedBox(width: 14),
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          _pdfInfoLine(
                            'Hora de Inicio y Término:',
                            _cleanForPdf(
                              'Comenzó ${session.startTimeLabel} hrs -> Terminó ${session.endTimeLabel} hrs',
                            ),
                          ),
                          _pdfInfoLine(
                            'Sello del Sistema:',
                            _cleanForPdf(session.executionEvidenceSummary),
                          ),
                          _pdfInfoLine(
                            'Tolerancia Configurada:',
                            '${session.toleranceMinutes} minutos',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 12),

          // RESUMEN NUMÉRICO DE CUMPLIMIENTO AL CIERRE DE LA SESIÓN
          pw.Row(
            children: [
              pw.Expanded(
                child: _pdfStatBox(
                  title: 'TOTAL PADRÓN',
                  value: '${workshop.enrolledStudents.length}',
                  subtitle: 'Alumnos inscritos',
                  textColor: primaryPdf,
                  bgColor: slateHeader,
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: _pdfStatBox(
                  title: 'CUMPLIERON',
                  value: '${cumplieron.length}',
                  subtitle: 'Entrada y Salida OK',
                  textColor: greenPdf,
                  bgColor: greenBgPdf,
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: _pdfStatBox(
                  title: 'LES FALTÓ SALIDA',
                  value: '${faltoSalida.length}',
                  subtitle: 'Solo Entrada',
                  textColor: amberPdf,
                  bgColor: amberBgPdf,
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: _pdfStatBox(
                  title: 'NO ENTRARON',
                  value: '${noEntraron.length}',
                  subtitle: 'Sin asistencia hoy',
                  textColor: redPdf,
                  bgColor: redBgPdf,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 14),

          // TABLA GENERAL DE ALUMNOS AL CIERRE DE LA SESIÓN
          pw.Text(
            '2. LISTA OFICIAL DE ALUMNOS Y CUMPLIMIENTO AL CIERRE DE LA SESIÓN',
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
              color: primaryPdf,
            ),
          ),
          pw.SizedBox(height: 6),
          if (workshop.enrolledStudents.isEmpty)
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(14),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: slateBorder),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Text(
                'No hay alumnos registrados en el padrón de este taller.',
                style: const pw.TextStyle(fontSize: 9),
              ),
            )
          else
            pw.Table(
              border: pw.TableBorder.all(color: slateBorder, width: 0.7),
              columnWidths: {
                0: const pw.FixedColumnWidth(22),
                1: const pw.FixedColumnWidth(64),
                2: const pw.FlexColumnWidth(2.2),
                3: const pw.FixedColumnWidth(62),
                4: const pw.FixedColumnWidth(62),
                5: const pw.FlexColumnWidth(1.9),
                6: const pw.FlexColumnWidth(2.0),
              },
              children: [
                pw.TableRow(
                  decoration: pw.BoxDecoration(color: slateHeader),
                  children: [
                    _pdfTableHeaderCell('#'),
                    _pdfTableHeaderCell('Matrícula'),
                    _pdfTableHeaderCell('Nombre del Alumno'),
                    _pdfTableHeaderCell('Entrada'),
                    _pdfTableHeaderCell('Salida'),
                    _pdfTableHeaderCell('Estado al Cierre'),
                    _pdfTableHeaderCell('Evidencia / Observación'),
                  ],
                ),
                ...List.generate(workshop.enrolledStudents.length, (idx) {
                  final st = workshop.enrolledStudents[idx];
                  final rec = session.records[st.id];
                  final status = rec?.status ?? AttendanceStatus.absent;

                  String statusLabel;
                  PdfColor statusColor;
                  PdfColor rowBadgeBg;

                  if (status == AttendanceStatus.accredited) {
                    statusLabel = 'CUMPLIÓ (Entrada y Salida)';
                    statusColor = greenPdf;
                    rowBadgeBg = greenBgPdf;
                  } else if (status == AttendanceStatus.incompleteEntryOnly) {
                    statusLabel = 'LE FALTÓ LA SALIDA';
                    statusColor = amberPdf;
                    rowBadgeBg = amberBgPdf;
                  } else if (status == AttendanceStatus.incompleteExitOnly) {
                    statusLabel = 'SOLO SALIDA (Faltó Entrada)';
                    statusColor = amberPdf;
                    rowBadgeBg = amberBgPdf;
                  } else {
                    statusLabel = 'NO ENTRÓ A LA SESIÓN';
                    statusColor = redPdf;
                    rowBadgeBg = redBgPdf;
                  }

                  final noteClean =
                      (rec?.notes != null && rec!.notes!.trim().isNotEmpty)
                      ? _cleanForPdf(rec.notes!)
                      : (rec?.isLate == true
                            ? 'Retardo (+${rec!.lateMinutes} min)'
                            : (status == AttendanceStatus.accredited
                                  ? 'Asistencia completa'
                                  : '-'));

                  return pw.TableRow(
                    verticalAlignment: pw.TableCellVerticalAlignment.middle,
                    children: [
                      _pdfTableCell('${idx + 1}', alignCenter: true),
                      _pdfTableCell(_cleanForPdf(st.enrollmentNumber)),
                      _pdfTableCell(_cleanForPdf(st.fullName), isBold: true),
                      _pdfTableCell(
                        _fmtTime(rec?.checkInTime),
                        alignCenter: true,
                      ),
                      _pdfTableCell(
                        _fmtTime(rec?.checkOutTime),
                        alignCenter: true,
                      ),
                      pw.Container(
                        padding: const pw.EdgeInsets.all(4),
                        color: rowBadgeBg,
                        child: pw.Text(
                          statusLabel,
                          style: pw.TextStyle(
                            fontSize: 7.5,
                            fontWeight: pw.FontWeight.bold,
                            color: statusColor,
                          ),
                        ),
                      ),
                      _pdfTableCell(noteClean),
                    ],
                  );
                }),
              ],
            ),

          pw.SizedBox(height: 24),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
            children: [
              pw.Column(
                children: [
                  pw.Container(
                    width: 180,
                    height: 1,
                    color: slateText,
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    _cleanForPdf(
                      workshop.instructorName.isNotEmpty
                          ? workshop.instructorName
                          : 'Docente Responsable',
                    ),
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    'Firma del Docente Responsable',
                    style: pw.TextStyle(fontSize: 8, color: slateText),
                  ),
                ],
              ),
              pw.Column(
                children: [
                  pw.Container(
                    width: 180,
                    height: 1,
                    color: slateText,
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'Sello de Coordinación Académica',
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    _cleanForPdf('Fecha: ${session.formattedDateWithDay}'),
                    style: pw.TextStyle(fontSize: 8, color: slateText),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );

    return doc.save();
  }

  /// Genera los bytes del PDF individual de comprobante de evidencia de un alumno (ej. asistencia sin celular, extravío u olvido)
  static Future<Uint8List> generateStudentEvidencePdfBytes({
    required Workshop workshop,
    required WorkshopSession session,
    required Student student,
    required AttendanceRecord record,
  }) async {
    final doc = pw.Document(
      title: _cleanForPdf('Evidencia Alumno ${student.fullName}'),
    );

    final primaryPdf = PdfColor.fromInt(0xFF4C1D95);
    final lightPurple = PdfColor.fromInt(0xFFF5F3FF);
    final borderCol = PdfColor.fromInt(0xFFC4B5FD);

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(16),
              decoration: pw.BoxDecoration(
                color: primaryPdf,
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'COMPROBANTE OFICIAL DE EVIDENCIA Y ASISTENCIA INDIVIDUAL',
                    style: pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 13,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    _cleanForPdf(
                      'Taller: ${workshop.name} (${workshop.code}) | ${session.title}',
                    ),
                    style: const pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 16),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(16),
              decoration: pw.BoxDecoration(
                color: lightPurple,
                borderRadius: pw.BorderRadius.circular(8),
                border: pw.Border.all(color: borderCol),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _pdfInfoLine('Alumno:', _cleanForPdf(student.fullName)),
                  _pdfInfoLine(
                    'Matrícula / Control:',
                    _cleanForPdf(student.enrollmentNumber),
                  ),
                  _pdfInfoLine('Correo:', _cleanForPdf(student.email)),
                  pw.Divider(color: borderCol),
                  _pdfInfoLine('Sesión:', _cleanForPdf(session.title)),
                  _pdfInfoLine(
                    'Día de Realización:',
                    _cleanForPdf(session.formattedDateWithDay),
                  ),
                  _pdfInfoLine(
                    'Horario de la Sesión:',
                    _cleanForPdf(
                      'Comenzó ${session.startTimeLabel} hrs -> Terminó ${session.endTimeLabel} hrs',
                    ),
                  ),
                  _pdfInfoLine(
                    'Hora de Entrada Registrada:',
                    _fmtTime(record.checkInTime),
                  ),
                  _pdfInfoLine(
                    'Hora de Salida Registrada:',
                    _fmtTime(record.checkOutTime),
                  ),
                  _pdfInfoLine(
                    'Estado al Cierre:',
                    record.status == AttendanceStatus.accredited
                        ? 'CUMPLIÓ (ACREDITADO CON ENTRADA Y SALIDA)'
                        : 'ASISTENCIA EN SALA REGISTRADA',
                  ),
                  pw.Divider(color: borderCol),
                  pw.Text(
                    'Evidencia de la Circunstancia / Observación Oficial:',
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                      color: primaryPdf,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    _cleanForPdf(
                      record.notes ?? 'Asistencia validada por el docente.',
                    ),
                    style: const pw.TextStyle(fontSize: 10),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    return doc.save();
  }

  /// Guarda el PDF en la carpeta de Descargas (si aplica) y abre el diálogo nativo para descargar, imprimir o compartir el PDF como evidencia
  static Future<void> downloadOrShareSessionPdf({
    required BuildContext context,
    required Workshop workshop,
    required WorkshopSession session,
  }) async {
    try {
      final bytes = await generateSessionEvidencePdfBytes(
        workshop: workshop,
        session: session,
      );
      final safeCode = workshop.code.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final fileName =
          'Evidencia_${safeCode}_${session.date.day}_${session.date.month}_${session.date.year}.pdf';

      String? savedPath;
      if (!kIsWeb) {
        try {
          final downloadDir = Directory('/storage/emulated/0/Download');
          if (await downloadDir.exists()) {
            final file = File('${downloadDir.path}/$fileName');
            await file.writeAsBytes(bytes);
            savedPath = file.path;
          } else {
            final dir = await getApplicationDocumentsDirectory();
            final file = File('${dir.path}/$fileName');
            await file.writeAsBytes(bytes);
            savedPath = file.path;
          }
        } catch (_) {}
      }

      if (context.mounted && savedPath != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('📄 PDF guardado en: $savedPath'),
            backgroundColor: AppTheme.accreditedColor,
            duration: const Duration(seconds: 3),
          ),
        );
      }

      await Printing.sharePdf(bytes: bytes, filename: fileName);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al generar el PDF: $e'),
            backgroundColor: AppTheme.absentColor,
          ),
        );
      }
    }
  }

  /// Guarda y comparte el PDF de evidencia individual de un alumno
  static Future<void> downloadOrShareStudentPdf({
    required BuildContext context,
    required Workshop workshop,
    required WorkshopSession session,
    required Student student,
    required AttendanceRecord record,
  }) async {
    try {
      final bytes = await generateStudentEvidencePdfBytes(
        workshop: workshop,
        session: session,
        student: student,
        record: record,
      );
      final fileName =
          'Evidencia_Alumno_${student.enrollmentNumber}_${session.date.day}_${session.date.month}.pdf';

      if (!kIsWeb) {
        try {
          final downloadDir = Directory('/storage/emulated/0/Download');
          if (await downloadDir.exists()) {
            final file = File('${downloadDir.path}/$fileName');
            await file.writeAsBytes(bytes);
          }
        } catch (_) {}
      }

      await Printing.sharePdf(bytes: bytes, filename: fileName);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al generar PDF del alumno: $e'),
            backgroundColor: AppTheme.absentColor,
          ),
        );
      }
    }
  }

  static pw.Widget _pdfInfoLine(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 3),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 115,
            child: pw.Text(
              label,
              style: pw.TextStyle(
                fontSize: 8.5,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              value,
              style: const pw.TextStyle(fontSize: 8.5),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _pdfStatBox({
    required String title,
    required String value,
    required String subtitle,
    required PdfColor textColor,
    required PdfColor bgColor,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      decoration: pw.BoxDecoration(
        color: bgColor,
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title,
            style: pw.TextStyle(
              fontSize: 7.5,
              fontWeight: pw.FontWeight.bold,
              color: textColor,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 15,
              fontWeight: pw.FontWeight.bold,
              color: textColor,
            ),
          ),
          pw.Text(
            subtitle,
            style: pw.TextStyle(fontSize: 7, color: textColor),
          ),
        ],
      ),
    );
  }

  static pw.Widget _pdfTableHeaderCell(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(5),
      child: pw.Text(
        text,
        style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
      ),
    );
  }

  static pw.Widget _pdfTableCell(
    String text, {
    bool isBold = false,
    bool alignCenter = false,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(5),
      child: pw.Text(
        text,
        textAlign: alignCenter ? pw.TextAlign.center : pw.TextAlign.left,
        style: pw.TextStyle(
          fontSize: 8,
          fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }
}

