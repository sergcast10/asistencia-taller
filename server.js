const http = require('http');
const fs = require('fs');
const path = require('path');
const url = require('url');
const crypto = require('crypto');

const PORT = process.env.PORT || 8080;
const DB_PATH = path.join(__dirname, 'data', 'database.json');
const PUBLIC_DIR = path.join(__dirname, 'public');

// --- GESTIÓN DE BASE DE DATOS LOCAL ---
function loadDB() {
  try {
    if (!fs.existsSync(DB_PATH)) {
      const initial = { workshops: [], activeSession: null, tunnelUrl: '' };
      fs.writeFileSync(DB_PATH, JSON.stringify(initial, null, 2), 'utf-8');
      return initial;
    }
    const raw = fs.readFileSync(DB_PATH, 'utf-8');
    return JSON.parse(raw);
  } catch (err) {
    console.error('Error leyendo base de datos:', err);
    return { workshops: [], activeSession: null, tunnelUrl: '' };
  }
}

function saveDB(db) {
  try {
    fs.writeFileSync(DB_PATH, JSON.stringify(db, null, 2), 'utf-8');
  } catch (err) {
    console.error('Error guardando base de datos:', err);
  }
}

// Helper para parsear JSON body en requests POST/PUT
function parseBody(req) {
  return new Promise((resolve, reject) => {
    let body = '';
    req.on('data', chunk => { body += chunk.toString(); });
    req.on('end', () => {
      try {
        resolve(body ? JSON.parse(body) : {});
      } catch (e) {
        resolve({});
      }
    });
    req.on('error', reject);
  });
}

// Formatear hora local HH:MM:SS
function formatTime(isoStr) {
  if (!isoStr) return '';
  const d = new Date(isoStr);
  return d.toLocaleTimeString('es-MX', { hour12: false });
}

// Generación de token dinámico QR (ventana de 15 segundos)
function generateDynamicToken(secret, sessionId, phase) {
  const windowTime = Math.floor(Date.now() / 15000);
  const data = `${sessionId}:${phase}:${windowTime}`;
  const hmac = crypto.createHmac('sha256', secret || 'default_secret').update(data).digest('hex').substring(0, 16);
  return `${phase}_${windowTime}_${hmac}`;
}

// Validación de token dinámico (acepta ventana actual y ventana anterior por lag)
function validateDynamicToken(token, secret, sessionId, expectedPhase) {
  if (!token) return false;
  const currentWindow = Math.floor(Date.now() / 15000);
  const windows = [currentWindow, currentWindow - 1, currentWindow + 1];
  for (const w of windows) {
    const data = `${sessionId}:${expectedPhase}:${w}`;
    const hmac = crypto.createHmac('sha256', secret || 'default_secret').update(data).digest('hex').substring(0, 16);
    const expectedToken = `${expectedPhase}_${w}_${hmac}`;
    if (token === expectedToken) return true;
  }
  return false;
}

// MIME types para archivos estáticos
const MIME_TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon'
};

const server = http.createServer(async (req, res) => {
  // Configurar CORS para permitir escaneos y llamadas desde cualquier origen
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  if (req.method === 'OPTIONS') {
    res.writeHead(204);
    res.end();
    return;
  }

  const parsedUrl = new URL(req.url, `http://${req.headers.host || 'localhost:8080'}`);
  const pathname = parsedUrl.pathname;
  const query = Object.fromEntries(parsedUrl.searchParams.entries());

  // -------------------------------------------------------------
  // RUTAS DE LA API REST
  // -------------------------------------------------------------

  // 1. Estado y configuración del Túnel
  if (pathname === '/api/tunnel' && req.method === 'GET') {
    const db = loadDB();
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ tunnelUrl: db.tunnelUrl || '' }));
    return;
  }

  if (pathname === '/api/tunnel' && req.method === 'POST') {
    const body = await parseBody(req);
    const db = loadDB();
    db.tunnelUrl = (body.url || '').trim();
    saveDB(db);
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ success: true, tunnelUrl: db.tunnelUrl }));
    return;
  }

  // 2. Sesión Activa actual del Docente y generación del Token QR dinámico
  if (pathname === '/api/active-session' && req.method === 'GET') {
    const db = loadDB();
    if (!db.activeSession) {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ active: false }));
      return;
    }

    const workshop = db.workshops.find(w => w.id === db.activeSession.workshopId);
    if (!workshop) {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ active: false }));
      return;
    }

    const session = workshop.sessions.find(s => s.id === db.activeSession.sessionId);
    if (!session) {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ active: false }));
      return;
    }

    // Generar token dinámico actual
    const dynamicToken = generateDynamicToken(session.qrSecret, session.id, session.currentPhase);
    
    // Calcular estadísticas
    const enrolled = workshop.enrolledStudents || [];
    const records = session.records || {};
    let accreditedCount = 0;
    let entryCount = 0;
    let exitCount = 0;

    const studentListWithRecords = enrolled.map(std => {
      const rec = records[std.id] || null;
      if (rec && rec.checkInTime) entryCount++;
      if (rec && rec.checkOutTime) exitCount++;
      if (rec && rec.status === 'accredited') accreditedCount++;
      return {
        ...std,
        record: rec
      };
    });

    // URL completa para el QR usando el túnel HTTPS si existe, o localhost
    const baseUrl = db.tunnelUrl ? db.tunnelUrl.replace(/\/$/, '') : `http://${req.headers.host}`;
    const qrAttendanceUrl = `${baseUrl}/?session=${session.id}&token=${dynamicToken}&phase=${session.currentPhase}`;

    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      active: true,
      workshop: {
        id: workshop.id,
        name: workshop.name,
        code: workshop.code,
        instructorName: workshop.instructorName
      },
      session: {
        id: session.id,
        title: session.title,
        currentPhase: session.currentPhase,
        date: session.date
      },
      dynamicToken,
      qrAttendanceUrl,
      tunnelUrl: db.tunnelUrl || '',
      stats: {
        totalEnrolled: enrolled.length,
        entryCount,
        exitCount,
        accreditedCount
      },
      students: studentListWithRecords
    }));
    return;
  }

  // 3. Cambiar fase de la sesión activa (entrada / salida / pausado)
  if (pathname === '/api/set-phase' && req.method === 'POST') {
    const body = await parseBody(req);
    const db = loadDB();
    if (!db.activeSession) {
      res.writeHead(400, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'No hay sesión activa' }));
      return;
    }

    const workshop = db.workshops.find(w => w.id === db.activeSession.workshopId);
    const session = workshop ? workshop.sessions.find(s => s.id === db.activeSession.sessionId) : null;
    if (!session) {
      res.writeHead(404, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'Sesión no encontrada' }));
      return;
    }

    if (body.phase && ['entry', 'exit', 'inactive'].includes(body.phase)) {
      session.currentPhase = body.phase;
      saveDB(db);
    }

    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ success: true, phase: session.currentPhase }));
    return;
  }

  // 4. Crear nuevo taller
  if (pathname === '/api/workshops' && req.method === 'POST') {
    const body = await parseBody(req);
    const db = loadDB();
    const newWs = {
      id: 'ws_' + Date.now().toString(36),
      name: body.name || 'Nuevo Taller',
      code: body.code || 'TAL-001',
      instructorName: body.instructorName || 'Docente Responsable',
      description: body.description || '',
      enrolledStudents: [],
      sessions: [
        {
          id: 'ses_' + Date.now().toString(36),
          title: 'Sesión 1',
          date: new Date().toISOString(),
          currentPhase: 'entry',
          qrSecret: 'sec_' + crypto.randomBytes(6).toString('hex'),
          records: {}
        }
      ]
    };
    db.workshops.unshift(newWs);
    db.activeSession = {
      workshopId: newWs.id,
      sessionId: newWs.sessions[0].id
    };
    saveDB(db);
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ success: true, workshop: newWs }));
    return;
  }

  // 5. Consulta inteligente de alumno por Número de Control
  // Permite saber si el alumno ya está inscrito y si ya tiene entrada o salida
  if (pathname === '/api/check-student' && req.method === 'GET') {
    const controlNumber = (query.controlNumber || '').toString().trim().toUpperCase();
    const sessionId = (query.sessionId || '').toString().trim();

    if (!controlNumber) {
      res.writeHead(400, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'Número de Control requerido' }));
      return;
    }

    const db = loadDB();
    // Buscar en el taller de la sesión solicitada o de la sesión activa
    let targetWorkshop = null;
    let targetSession = null;

    if (sessionId) {
      for (const w of db.workshops) {
        const s = w.sessions.find(ses => ses.id === sessionId);
        if (s) {
          targetWorkshop = w;
          targetSession = s;
          break;
        }
      }
    } else if (db.activeSession) {
      targetWorkshop = db.workshops.find(w => w.id === db.activeSession.workshopId);
      targetSession = targetWorkshop ? targetWorkshop.sessions.find(s => s.id === db.activeSession.sessionId) : null;
    }

    if (!targetWorkshop || !targetSession) {
      res.writeHead(404, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'Sesión no activa' }));
      return;
    }

    // Buscar si el alumno ya está en el taller
    const student = (targetWorkshop.enrolledStudents || []).find(
      s => s.enrollmentNumber.trim().toUpperCase() === controlNumber
    );

    if (student) {
      const record = targetSession.records[student.id] || null;
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({
        exists: true,
        student: {
          id: student.id,
          fullName: student.fullName,
          enrollmentNumber: student.enrollmentNumber,
          email: student.email || ''
        },
        workshopName: targetWorkshop.name,
        sessionTitle: targetSession.title,
        currentPhase: targetSession.currentPhase,
        record: record ? {
          hasCheckIn: !!record.checkInTime,
          checkInTime: record.checkInTime ? formatTime(record.checkInTime) : null,
          hasCheckOut: !!record.checkOutTime,
          checkOutTime: record.checkOutTime ? formatTime(record.checkOutTime) : null,
          status: record.status
        } : null
      }));
      return;
    } else {
      // El alumno no está registrado aún
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({
        exists: false,
        workshopName: targetWorkshop.name,
        sessionTitle: targetSession.title,
        currentPhase: targetSession.currentPhase
      }));
      return;
    }
  }

  // 6. REGISTRO DE ASISTENCIA (AUTOMÁTICO / FORMULARIO)
  // Sella entrada o salida con timestamp inmutable y doble check de acreditación
  if (pathname === '/api/register-attendance' && req.method === 'POST') {
    const body = await parseBody(req);
    const controlNumber = (body.controlNumber || '').toString().trim().toUpperCase();
    const fullName = (body.fullName || '').toString().trim();
    const email = (body.email || '').toString().trim();
    const token = (body.token || '').toString().trim();
    const sessionId = (body.sessionId || '').toString().trim();

    if (!controlNumber) {
      res.writeHead(400, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ success: false, message: 'El Número de Control es obligatorio.' }));
      return;
    }

    const db = loadDB();
    let workshop = null;
    let session = null;

    if (sessionId) {
      for (const w of db.workshops) {
        const s = w.sessions.find(ses => ses.id === sessionId);
        if (s) {
          workshop = w;
          session = s;
          break;
        }
      }
    } else if (db.activeSession) {
      workshop = db.workshops.find(w => w.id === db.activeSession.workshopId);
      session = workshop ? workshop.sessions.find(s => s.id === db.activeSession.sessionId) : null;
    }

    if (!workshop || !session) {
      res.writeHead(400, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ success: false, message: 'La sesión no existe o no está activa.' }));
      return;
    }

    const currentPhase = session.currentPhase;
    if (currentPhase === 'inactive') {
      res.writeHead(400, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ success: false, message: 'El pase de lista no está activo en este momento.' }));
      return;
    }

    // Validar token dinámico para evitar trampas/capturas de pantalla pasadas
    const isValidToken = validateDynamicToken(token, session.qrSecret, session.id, currentPhase);
    if (!isValidToken && token) {
      // Si el token es inválido o caducó
      res.writeHead(400, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({
        success: false,
        message: 'El código QR dinámico ha expirado. Por favor, vuelve a escanear el código QR que se proyecta en la pantalla.'
      }));
      return;
    }

    // 1. Obtener o crear estudiante
    let student = (workshop.enrolledStudents || []).find(
      s => s.enrollmentNumber.trim().toUpperCase() === controlNumber
    );

    if (!student) {
      // Alumno nuevo: requiere nombre
      if (!fullName) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({
          success: false,
          needsRegistration: true,
          message: 'Es tu primera vez en este taller. Por favor ingresa tu Nombre Completo para registrarte.'
        }));
        return;
      }

      student = {
        id: 'std_' + Date.now().toString(36) + Math.random().toString(36).substring(2, 6),
        fullName: fullName,
        enrollmentNumber: controlNumber,
        email: email || ''
      };
      workshop.enrolledStudents.push(student);
    }

    // 2. Procesar registro inmutable de asistencia
    session.records = session.records || {};
    let record = session.records[student.id];
    const nowIso = new Date().toISOString();
    const formattedNow = formatTime(nowIso);

    if (!record) {
      record = {
        id: 'rec_' + Date.now().toString(36),
        studentId: student.id,
        sessionId: session.id,
        checkInTime: null,
        checkOutTime: null,
        isLocked: true,
        status: 'pending'
      };
      session.records[student.id] = record;
    }

    let resultTitle = '';
    let resultMessage = '';
    let finalStatus = record.status;

    if (currentPhase === 'entry') {
      if (record.checkInTime) {
        // Ya tenía entrada sellada
        resultTitle = 'Entrada Ya Sellada 🔒';
        resultMessage = `Hola, ${student.fullName}. Tu entrada ya fue sellada a las ${formatTime(record.checkInTime)} y es inmutable. Recuerda escanear a la salida para ACREDITAR.`;
      } else {
        record.checkInTime = nowIso;
        record.status = 'incompleteEntryOnly';
        finalStatus = record.status;
        resultTitle = '🟢 Entrada Sellada con Éxito 🔒';
        resultMessage = `¡Excelente, ${student.fullName}! Se registró tu ENTRADA oficial a las ${formattedNow} hrs. Guarda este celular para escanear a la salida.`;
      }
    } else if (currentPhase === 'exit') {
      if (record.checkOutTime) {
        // Ya tenía salida sellada
        resultTitle = 'Salida Ya Sellada 🔒';
        resultMessage = `Hola, ${student.fullName}. Tu salida ya fue sellada a las ${formatTime(record.checkOutTime)}.`;
      } else {
        record.checkOutTime = nowIso;
        if (record.checkInTime) {
          // TIENE ENTRADA Y SALIDA -> ACREDITADO 100%
          record.status = 'accredited';
          finalStatus = 'accredited';
          resultTitle = '🎉 ¡TALLER ACREDITADO! 🔒';
          resultMessage = `¡Felicidades, ${student.fullName}! Se selló tu SALIDA a las ${formattedNow} hrs. Cumpliste con ENTRADA (${formatTime(record.checkInTime)}) y SALIDA. Tu asistencia está 100% Acreditada.`;
        } else {
          // Solo salida sin entrada previa
          record.status = 'incompleteExitOnly';
          finalStatus = 'incompleteExitOnly';
          resultTitle = '⚠️ Salida Registrada Sin Entrada 🔒';
          resultMessage = `Se selló tu salida a las ${formattedNow} hrs, pero no cuentas con registro de entrada. La sesión queda como Incompleta.`;
        }
      }
    }

    // Persistir cambios
    saveDB(db);

    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      success: true,
      title: resultTitle,
      message: resultMessage,
      status: finalStatus,
      student: {
        fullName: student.fullName,
        enrollmentNumber: student.enrollmentNumber
      },
      checkInTime: record.checkInTime ? formatTime(record.checkInTime) : null,
      checkOutTime: record.checkOutTime ? formatTime(record.checkOutTime) : null
    }));
    return;
  }

  // -------------------------------------------------------------
  // SERVICIO DE ARCHIVOS ESTÁTICOS (WEB UI)
  // -------------------------------------------------------------
  let filePath = path.join(PUBLIC_DIR, pathname === '/' ? 'index.html' : pathname);
  if (pathname === '/docente') {
    filePath = path.join(PUBLIC_DIR, 'docente.html');
  }

  const ext = path.extname(filePath).toLowerCase();
  const contentType = MIME_TYPES[ext] || 'application/octet-stream';

  fs.readFile(filePath, (err, content) => {
    if (err) {
      if (err.code === 'ENOENT') {
        // Fallback a index.html para soportar rutas del cliente
        fs.readFile(path.join(PUBLIC_DIR, 'index.html'), (err2, fallbackContent) => {
          if (err2) {
            res.writeHead(404, { 'Content-Type': 'text/plain' });
            res.end('404 Not Found');
          } else {
            res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
            res.end(fallbackContent);
          }
        });
      } else {
        res.writeHead(500, { 'Content-Type': 'text/plain' });
        res.end(`Error del servidor: ${err.code}`);
      }
    } else {
      res.writeHead(200, { 'Content-Type': contentType });
      res.end(content);
    }
  });
});

server.listen(PORT, () => {
  console.log(`=====================================================`);
  console.log(` Servidor de Asistencia y Acreditación Activo`);
  console.log(` Puerto local: http://localhost:${PORT}`);
  console.log(` Panel Docente: http://localhost:${PORT}/docente`);
  console.log(` Portal Alumnos: http://localhost:${PORT}/`);
  console.log(`=====================================================`);
});
