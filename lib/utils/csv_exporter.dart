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
    buffer.writeln('"Fecha:","${session.date.year}-${session.date.month.toString().padLeft(2, '0')}-${session.date.day.toString().padLeft(2, '0')}"');
    buffer.writeln('"Seguridad:","Horas de Entrada y Salida selladas con inmutabilidad estricta contra edición"');
    buffer.writeln('');

    // Encabezados de columnas
    buffer.writeln('"Matrícula/Código","Nombre Completo","Correo Electrónico","Hora Entrada","Hora Salida","Estado de Acreditación","Condición","Auditoría Inmutable"');

    for (var student in workshop.enrolledStudents) {
      final record = session.records[student.id];

      final entryStr = record?.checkInTime != null
          ? '${record!.checkInTime!.hour.toString().padLeft(2, '0')}:${record.checkInTime!.minute.toString().padLeft(2, '0')}:${record.checkInTime!.second.toString().padLeft(2, '0')}'
          : 'SIN REGISTRO';

      final exitStr = record?.checkOutTime != null
          ? '${record!.checkOutTime!.hour.toString().padLeft(2, '0')}:${record.checkOutTime!.minute.toString().padLeft(2, '0')}:${record.checkOutTime!.second.toString().padLeft(2, '0')}'
          : 'SIN REGISTRO';

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
          statusStr = 'INCOMPLETO';
          condicionStr = 'SOLO REGISTRÓ ENTRADA (FALTA SALIDA)';
        } else if (record.status == AttendanceStatus.incompleteExitOnly) {
          statusStr = 'INCOMPLETO';
          condicionStr = 'SOLO REGISTRÓ SALIDA (FALTA ENTRADA)';
        }
      }

      buffer.writeln('"${student.enrollmentNumber}","${student.fullName}","${student.email}","$entryStr","$exitStr","$statusStr","$condicionStr","$lockStr"');
    }

    return buffer.toString();
  }
}
