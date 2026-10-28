import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:powersync/powersync.dart';
import 'powersync_schema.dart';
import '../models/workshop.dart';
import '../models/attendance_record.dart';

class PowerSyncService {
  static final PowerSyncService _instance = PowerSyncService._internal();
  factory PowerSyncService() => _instance;
  PowerSyncService._internal();

  PowerSyncDatabase? _db;
  bool _isInitialized = false;

  PowerSyncDatabase get db {
    if (_db == null) {
      throw StateError('PowerSyncDatabase no ha sido inicializado. Llama a initialize() primero.');
    }
    return _db!;
  }

  bool get isInitialized => _isInitialized;

  /// Inicializa la base de datos local SQLite con el esquema de PowerSync
  Future<void> initialize() async {
    if (_isInitialized) return;

    if (kIsWeb) {
      // En Web, la persistencia inmutable se realiza mediante StorageService (localStorage/SharedPreferences)
      // para evitar que el navegador intente compilar WebAssembly (sqlite3.wasm) sin los headers MIME correspondientes.
      _isInitialized = false;
      return;
    }

    try {
      final dir = await getApplicationDocumentsDirectory();
      final dbPath = '${dir.path}/asistencia_taller_powersync.db';

      _db = PowerSyncDatabase(
        schema: schema,
        path: dbPath,
      );

      await _db!.initialize();
      _isInitialized = true;
    } catch (e) {
      debugPrint('Aviso: Inicializando PowerSync en modo compatible: $e');
      _isInitialized = false;
    }
  }

  // --- REGISTRO Y REGLA DE INMUTABILIDAD ---

  /// Guarda o actualiza un registro de asistencia en SQLite respetando el sellado temporal
  Future<bool> saveAttendanceRecord({
    required AttendanceRecord record,
    required String workshopId,
  }) async {
    if (!_isInitialized || _db == null) return true;

    try {
      // Verificar si ya existe un registro sellado en SQLite
      final existing = await _db!.execute(
        'SELECT * FROM attendance_records WHERE student_id = ? AND session_id = ?',
        [record.studentId, record.sessionId],
      );

      if (existing.isNotEmpty) {
        final row = existing.first;
        final existingCheckIn = row['check_in_time'] as String?;
        final existingCheckOut = row['check_out_time'] as String?;

        // Si ya tenía entrada y se intenta cambiar, no se altera
        final sealedCheckIn = existingCheckIn ?? record.checkInTime?.toIso8601String();
        // Si ya tenía salida y se intenta cambiar, no se altera
        final sealedCheckOut = existingCheckOut ?? record.checkOutTime?.toIso8601String();

        await _db!.execute(
          '''
          UPDATE attendance_records 
          SET check_in_time = ?, check_out_time = ?, is_locked = 1, status = ?, notes = ?
          WHERE student_id = ? AND session_id = ?
          ''',
          [
            sealedCheckIn,
            sealedCheckOut,
            record.status.name,
            record.notes,
            record.studentId,
            record.sessionId,
          ],
        );
      } else {
        await _db!.execute(
          '''
          INSERT INTO attendance_records (id, student_id, session_id, check_in_time, check_out_time, is_locked, status, notes)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?)
          ''',
          [
            record.id,
            record.studentId,
            record.sessionId,
            record.checkInTime?.toIso8601String(),
            record.checkOutTime?.toIso8601String(),
            record.isLocked ? 1 : 0,
            record.status.name,
            record.notes,
          ],
        );
      }
      return true;
    } catch (e) {
      debugPrint('Error al guardar en PowerSync SQLite: $e');
      return false;
    }
  }

  /// Guarda un taller y sus alumnos en SQLite local
  Future<void> persistWorkshop(Workshop workshop) async {
    if (!_isInitialized || _db == null) return;

    try {
      await _db!.writeTransaction((tx) async {
        // Taller
        await tx.execute(
          '''
          INSERT OR REPLACE INTO workshops (id, name, code, instructor_name, description)
          VALUES (?, ?, ?, ?, ?)
          ''',
          [workshop.id, workshop.name, workshop.code, workshop.instructorName, workshop.description],
        );

        // Alumnos
        for (var student in workshop.enrolledStudents) {
          await tx.execute(
            '''
            INSERT OR REPLACE INTO students (id, workshop_id, enrollment_number, full_name, email)
            VALUES (?, ?, ?, ?, ?)
            ''',
            [student.id, workshop.id, student.enrollmentNumber, student.fullName, student.email],
          );
        }

        // Sesiones
        for (var session in workshop.sessions) {
          await tx.execute(
            '''
            INSERT OR REPLACE INTO sessions (id, workshop_id, title, date, current_phase, secret_key)
            VALUES (?, ?, ?, ?, ?, ?)
            ''',
            [session.id, workshop.id, session.title, session.date.toIso8601String(), session.currentPhase.name, session.secretKey],
          );

          // Registros
          for (var entry in session.records.entries) {
            final rec = entry.value;
            await tx.execute(
              '''
              INSERT OR REPLACE INTO attendance_records (id, student_id, session_id, check_in_time, check_out_time, is_locked, status, notes)
              VALUES (?, ?, ?, ?, ?, ?, ?, ?)
              ''',
              [rec.id, rec.studentId, rec.sessionId, rec.checkInTime?.toIso8601String(), rec.checkOutTime?.toIso8601String(), rec.isLocked ? 1 : 0, rec.status.name, rec.notes],
            );
          }
        }
      });
    } catch (e) {
      debugPrint('Error al persistir taller en PowerSync: $e');
    }
  }

  /// Conector para sincronización con la nube (Supabase / Postgres / PowerSync Cloud)
  /// El docente puede pasar la lista 100% offline y cuando se configure el conector,
  /// sincronizará automáticamente sin fricción.
  Future<void> connectToCloudBackend(PowerSyncBackendConnector connector) async {
    if (_db != null && _isInitialized) {
      await _db!.connect(connector: connector);
    }
  }
}
