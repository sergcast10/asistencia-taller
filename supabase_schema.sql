-- ==============================================================
-- ESQUEMA DE BASE DE DATOS SUPABASE PARA ASISTENCIA Y ACREDITACIÓN
-- Copia y pega este script en el "SQL Editor" de tu proyecto de Supabase
-- ==============================================================

-- 1. Tabla de Talleres
CREATE TABLE IF NOT EXISTS workshops (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  code TEXT NOT NULL,
  instructor_name TEXT NOT NULL,
  description TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Tabla de Sesiones del Taller
CREATE TABLE IF NOT EXISTS workshop_sessions (
  id TEXT PRIMARY KEY,
  workshop_id TEXT REFERENCES workshops(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  current_phase TEXT NOT NULL DEFAULT 'entry', -- 'entry', 'exit', 'inactive'
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. Tabla de Estudiantes
CREATE TABLE IF NOT EXISTS students (
  id TEXT PRIMARY KEY,
  workshop_id TEXT REFERENCES workshops(id) ON DELETE CASCADE,
  enrollment_number TEXT NOT NULL,
  full_name TEXT NOT NULL,
  email TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(workshop_id, enrollment_number)
);

-- 4. Tabla de Registros de Asistencia Inmutables
CREATE TABLE IF NOT EXISTS attendance_records (
  id TEXT PRIMARY KEY,
  student_id TEXT REFERENCES students(id) ON DELETE CASCADE,
  session_id TEXT REFERENCES workshop_sessions(id) ON DELETE CASCADE,
  check_in_time TIMESTAMPTZ,
  check_out_time TIMESTAMPTZ,
  is_locked BOOLEAN DEFAULT TRUE,
  status TEXT DEFAULT 'pending', -- 'accredited', 'incompleteEntryOnly', 'incompleteExitOnly', 'pending'
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(student_id, session_id)
);

-- Habilitar Row Level Security (RLS) con acceso público de lectura/escritura para la app y alumnos
ALTER TABLE workshops ENABLE ROW LEVEL SECURITY;
ALTER TABLE workshop_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE students ENABLE ROW LEVEL SECURITY;
ALTER TABLE attendance_records ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Acceso público lectura workshops" ON workshops FOR SELECT USING (true);
CREATE POLICY "Acceso público insercion workshops" ON workshops FOR ALL USING (true);

CREATE POLICY "Acceso público lectura workshop_sessions" ON workshop_sessions FOR SELECT USING (true);
CREATE POLICY "Acceso público modificacion workshop_sessions" ON workshop_sessions FOR ALL USING (true);

CREATE POLICY "Acceso público lectura students" ON students FOR SELECT USING (true);
CREATE POLICY "Acceso público insercion students" ON students FOR ALL USING (true);

CREATE POLICY "Acceso público lectura attendance_records" ON attendance_records FOR SELECT USING (true);
CREATE POLICY "Acceso público modificacion attendance_records" ON attendance_records FOR ALL USING (true);

-- Habilitar Sincronización en Tiempo Real (Realtime) para que el celular del docente reciba los registros en vivo
ALTER PUBLICATION supabase_realtime ADD TABLE attendance_records;
ALTER PUBLICATION supabase_realtime ADD TABLE students;
ALTER PUBLICATION supabase_realtime ADD TABLE workshop_sessions;
