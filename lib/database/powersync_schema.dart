import 'package:powersync/powersync.dart';

/// Esquema de Base de Datos SQLite Local-First administrado por PowerSync
const schema = Schema([
  Table('workshops', [
    Column.text('name'),
    Column.text('code'),
    Column.text('instructor_name'),
    Column.text('description'),
  ]),
  Table('students', [
    Column.text('workshop_id'),
    Column.text('enrollment_number'),
    Column.text('full_name'),
    Column.text('email'),
  ]),
  Table('sessions', [
    Column.text('workshop_id'),
    Column.text('title'),
    Column.text('date'),
    Column.text('current_phase'),
    Column.text('secret_key'),
  ]),
  Table('attendance_records', [
    Column.text('student_id'),
    Column.text('session_id'),
    // CAMPOS DE AUDITORÍA E INMUTABILIDAD ESTRICTA
    Column.text('check_in_time'),   // 🔒 Hora de Entrada sellada (No editable)
    Column.text('check_out_time'),  // 🔒 Hora de Salida sellada (No editable)
    Column.integer('is_locked'),    // 1 = Registro sellado permanentemente
    Column.text('status'),          // accredited, incompleteEntryOnly, incompleteExitOnly, absent
    Column.text('notes'),
  ]),
]);
