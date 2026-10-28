const { spawn } = require('child_process');
const http = require('http');
const path = require('path');

console.log('=====================================================');
console.log('   INICIANDO SISTEMA DE ASISTENCIA CON TÚNEL HTTPS   ');
console.log('=====================================================');

// 1. Iniciar Servidor Node.js
const serverProcess = spawn('node', ['server.js'], {
  cwd: __dirname,
  stdio: 'inherit'
});

serverProcess.on('error', (err) => {
  console.error('Error iniciando server.js:', err);
});

// Esperar 1 segundo y levantar el túnel de Cloudflare
setTimeout(() => {
  const cloudflaredPath = path.join(__dirname, 'cloudflared.exe');
  console.log('Levantando Túnel Cloudflare para acceso global...');

  const tunnelProcess = spawn(cloudflaredPath, ['tunnel', '--url', 'http://localhost:8080']);

  let tunnelFound = false;

  function checkOutput(data) {
    const text = data.toString();
    const match = text.match(/https:\/\/[a-zA-Z0-9-]+\.trycloudflare\.com/);
    if (match && !tunnelFound) {
      tunnelFound = true;
      const publicUrl = match[0];
      console.log('\n=====================================================');
      console.log('  ¡TÚNEL HTTPS GLOBAL LISTO Y ACTIVO!');
      console.log('  Enlace Público:', publicUrl);
      console.log('  Panel Docente:  http://localhost:8080/docente');
      console.log('=====================================================\n');

      // Notificar a server.js sobre la nueva URL del túnel
      const req = http.request('http://localhost:8080/api/tunnel', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' }
      }, (res) => {
        // Abrir navegador en el panel docente
        spawn('cmd', ['/c', 'start', 'http://localhost:8080/docente'], { detached: true });
      });
      req.write(JSON.stringify({ url: publicUrl }));
      req.end();
    }
  }

  tunnelProcess.stdout.on('data', checkOutput);
  tunnelProcess.stderr.on('data', checkOutput);

  tunnelProcess.on('error', (err) => {
    console.error('Aviso: Cloudflared no se pudo iniciar automáticamente. Usando modo red local.', err.message);
    spawn('cmd', ['/c', 'start', 'http://localhost:8080/docente'], { detached: true });
  });

}, 1200);

process.on('SIGINT', () => {
  console.log('\nCerrando servicios...');
  process.exit();
});
