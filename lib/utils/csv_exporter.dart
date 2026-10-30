import '../models/workshop.dart';
import '../models/session.dart';
import '../models/attendance_record.dart';

class CsvExporter {
  static String generateSessionCsv({
    required Workshop workshop,
    required WorkshopSession session,
  }) {
    final buffer = StringBuffer();

    // Encabezado del reporte
    buffer.writeln(
      '"REPORTE OFICIAL DE ASISTENCIA Y ACREDITACIÓN (POWERSYNC / SQLITE)"',
    );
    buffer.writeln('"Taller:","${workshop.name}"');
    buffer.writeln('"Código:","${workshop.code}"');
    buffer.writeln('"Docente:","${workshop.instructorName}"');
    buffer.writeln('"Sesión:","${session.title}"');
    buffer.writeln(
      '"Día y Fecha de Realización:","${session.formattedDateWithDay}"',
    );
    buffer.writeln(
      '"Horario de la Sesión:","Comenzó: ${session.startTimeLabel} hrs • Terminó: ${session.endTimeLabel} hrs"',
    );
    buffer.writeln(
      '"Evidencia de Ejecución:","${session.executionEvidenceSummary}"',
    );
    buffer.writeln(
      '"Tolerancia Configurada:","${session.toleranceMinutes} min • Ventana de Registro: ${session.registrationWindowMinutes} min"',
    );
    buffer.writeln(
      '"Seguridad:","Horas de Entrada y Salida selladas con inmutabilidad estricta contra edición"',
    );
    buffer.writeln('');

    // Encabezados de columnas
    buffer.writeln(
      '"Matrícula/Código","Nombre Completo","Correo Electrónico","Hora Entrada","Hora Salida","Puntualidad","Estado de Acreditación","Condición","Nota / Evidencia Docente","Auditoría Inmutable"',
    );

    for (var student in workshop.enrolledStudents) {
      final record = session.records[student.id];

      final entryStr = record?.checkInTime != null
          ? '${record!.checkInTime!.hour.toString().padLeft(2, '0')}:${record.checkInTime!.minute.toString().padLeft(2, '0')}:${record.checkInTime!.second.toString().padLeft(2, '0')}'
          : 'SIN REGISTRO';

      final exitStr = record?.checkOutTime != null
          ? '${record!.checkOutTime!.hour.toString().padLeft(2, '0')}:${record.checkOutTime!.minute.toString().padLeft(2, '0')}:${record.checkOutTime!.second.toString().padLeft(2, '0')}'
          : 'SIN REGISTRO';

      final puntualidadStr = record == null || !record.hasCheckIn
          ? 'SIN ENTRADA'
          : (record.isLate
                ? 'RETARDO (+${record.lateMinutes} MIN)'
                : 'PUNTUAL (EN TOLERANCIA)');

      final isSuspended =
          student.isSuspended || (record?.isSuspended == true);
      final suspensionReason =
          record?.suspensionReason ??
          student.suspensionReason ??
          'CONDUCTA INAPROPIADA';

      final noteStr = isSuspended
          ? 'SUSPENDIDO POR CONDUCTA: ${suspensionReason.replaceAll('"', "'")}'
          : (record?.notes ?? 'SIN OBSERVACIONES').replaceAll('"', "'");

      String statusStr = 'NO ENTRÓ (AUSENTE)';
      String condicionStr =
          'NO ENTRÓ A LA SESIÓN DE ESTE DÍA (SIN ENTRADA NI SALIDA)';
      String lockStr = 'NO SELLADO';

      if (isSuspended) {
        statusStr = 'SUSPENDIDO POR CONDUCTA';
        condicionStr = 'SUSPENDIDO POR EL DOCENTE ENCARGADO: ${suspensionReason.replaceAll('"', "'")}';
        lockStr = 'SELLADO DISCIPLINARIO';
      } else if (record != null) {
        if (record.isLocked) {
          lockStr = 'SELLADO POR SISTEMA (NO EDITABLE)';
        }

        if (record.status == AttendanceStatus.accredited) {
          statusStr = 'CUMPLIÓ (ACREDITADO)';
          condicionStr = 'CUMPLIÓ AL CERRAR LA SESIÓN (ENTRADA Y SALIDA OK)';
        } else if (record.status == AttendanceStatus.incompleteEntryOnly) {
          statusStr = 'LE FALTÓ LA SALIDA';
          condicionStr =
              'LE FALTÓ LA SALIDA AL CERRAR LA SESIÓN (SOLO ENTRADA)';
        } else if (record.status == AttendanceStatus.incompleteExitOnly) {
          statusStr = 'INCOMPLETO';
          condicionStr = 'SOLO REGISTRÓ SALIDA (LE FALTÓ ENTRADA)';
        }
      }

      buffer.writeln(
        '"${student.enrollmentNumber}","${student.fullName}","${student.email}","$entryStr","$exitStr","$puntualidadStr","$statusStr","$condicionStr","$noteStr","$lockStr"',
      );
    }

    return buffer.toString();
  }
}
