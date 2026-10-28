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
    buffer.writeln('"REPORTE OFICIAL DE ASISTENCIA Y ACREDITACIÓN (POWERSYNC / SQLITE)"');
    buffer.writeln('"Taller:","${workshop.name}"');
    buffer.writeln('"Código:","${workshop.code}"');
    buffer.writeln('"Docente:","${workshop.instructorName}"');
    buffer.writeln('"Sesión:","${session.title}"');
    buffer.writeln('"Día y Fecha de Realización:","${session.formattedDateWithDay}"');
    buffer.writeln('"Horario de la Sesión:","Comenzó: ${session.startTimeLabel} hrs • Terminó: ${session.endTimeLabel} hrs"');
    buffer.writeln('"Evidencia de Ejecución:","${session.executionEvidenceSummary}"');
    buffer.writeln('"Tolerancia Configurada:","${session.toleranceMinutes} min • Ventana de Registro: ${session.registrationWindowMinutes} min"');
    buffer.writeln('"Seguridad:","Horas de Entrada y Salida selladas con inmutabilidad estricta contra edición"');
    buffer.writeln('');

    // Encabezados de columnas
    buffer.writeln('"Matrícula/Código","Nombre Completo","Correo Electrónico","Hora Entrada","Hora Salida","Puntualidad","Estado de Acreditación","Condición","Nota / Evidencia Docente","Auditoría Inmutable"');

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
          : (record.isLate ? 'RETARDO (+${record.lateMinutes} MIN)' : 'PUNTUAL (EN TOLERANCIA)');

      final noteStr = (record?.notes ?? 'SIN OBSERVACIONES').replaceAll('"', "'");

      String statusStr = 'INASISTENCIA';
      String condicionStr = 'NO CUMPLE ASISTENCIA';
      String lockStr = 'NO SELLADO';

      if (record != null) {
        if (record.isLocked) {
          lockStr = 'SELLADO POR SISTEMA (NO EDITABLE)';
        }

        if (record.status == AttendanceStatus.accredited) {
          statusStr = 'ACREDITADO';
          condicionStr = 'CUMPLE CON ENTRADA Y SALIDA';
        } else if (record.status == AttendanceStatus.incompleteEntryOnly) {
          statusStr = 'ASISTENCIA REGISTRADA (EN SALA)';
          condicionStr = 'ENTRADA REGISTRADA (PENDIENTE SALIDA)';
        } else if (record.status == AttendanceStatus.incompleteExitOnly) {
          statusStr = 'INCOMPLETO';
          condicionStr = 'SOLO REGISTRÓ SALIDA (FALTA ENTRADA)';
        }
      }

      buffer.writeln('"${student.enrollmentNumber}","${student.fullName}","${student.email}","$entryStr","$exitStr","$puntualidadStr","$statusStr","$condicionStr","$noteStr","$lockStr"');
    }

    return buffer.toString();
  }
}
