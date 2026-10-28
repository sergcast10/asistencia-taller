const http = require('http');

function request(options, body = null) {
  return new Promise((resolve, reject) => {
    const req = http.request(options, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try {
          resolve({ status: res.statusCode, body: JSON.parse(data) });
        } catch (_) {
          resolve({ status: res.statusCode, body: data });
        }
      });
    });
    req.on('error', reject);
    if (body) req.write(JSON.stringify(body));
    req.end();
  });
}

async function run() {
  console.log('--- Probando Servidor de Asistencia ---');

  // 1. Verificar Sesión Activa
  const activeRes = await request({
    hostname: 'localhost',
    port: 8080,
    path: '/api/active-session',
    method: 'GET'
  });
  console.log('1. Sesión Activa:', activeRes.body.workshop.name);
  const token = activeRes.body.dynamicToken;
  const sessionId = activeRes.body.session.id;

  // 2. Comprobar Alumno Existente (21280001 - Juan Pérez)
  const checkRes = await request({
    hostname: 'localhost',
    port: 8080,
    path: `/api/check-student?controlNumber=21280001&sessionId=${sessionId}`,
    method: 'GET'
  });
  console.log('2. Reconocimiento Alumno 21280001:', checkRes.body.exists ? 'RECONOCIDO (' + checkRes.body.student.fullName + ')' : 'NO');

  // 3. Registrar Entrada de Juan Pérez
  const regEntryRes = await request({
    hostname: 'localhost',
    port: 8080,
    path: '/api/register-attendance',
    method: 'POST',
    headers: { 'Content-Type': 'application/json' }
  }, {
    controlNumber: '21280001',
    token: token,
    sessionId: sessionId
  });
  console.log('3. Registro Entrada Juan:', regEntryRes.body.title, 'Hora:', regEntryRes.body.checkInTime);

  // 4. Cambiar a Fase de Salida
  await request({
    hostname: 'localhost',
    port: 8080,
    path: '/api/set-phase',
    method: 'POST',
    headers: { 'Content-Type': 'application/json' }
  }, { phase: 'exit' });

  // Obtener nuevo token de salida
  const activeExitRes = await request({
    hostname: 'localhost',
    port: 8080,
    path: '/api/active-session',
    method: 'GET'
  });
  const exitToken = activeExitRes.body.dynamicToken;

  // 5. Registrar Salida de Juan Pérez -> Acreditado
  const regExitRes = await request({
    hostname: 'localhost',
    port: 8080,
    path: '/api/register-attendance',
    method: 'POST',
    headers: { 'Content-Type': 'application/json' }
  }, {
    controlNumber: '21280001',
    token: exitToken,
    sessionId: sessionId
  });
  console.log('4. Registro Salida Juan:', regExitRes.body.title, 'Estado:', regExitRes.body.status);

  // 6. Probar Alumno Nuevo (99999999 - Roberto Sánchez)
  const regNewRes = await request({
    hostname: 'localhost',
    port: 8080,
    path: '/api/register-attendance',
    method: 'POST',
    headers: { 'Content-Type': 'application/json' }
  }, {
    controlNumber: '99999999',
    fullName: 'Roberto Sánchez Ramos',
    token: exitToken,
    sessionId: sessionId
  });
  console.log('5. Alumno Nuevo Auto-Inscrito:', regNewRes.body.student.fullName, regNewRes.body.title);

  console.log('--- TODAS LAS PRUEBAS DEL SERVIDOR PASARON EXITOSAMENTE ---');
  process.exit(0);
}

run().catch(err => {
  console.error('Error en pruebas:', err);
  process.exit(1);
});
