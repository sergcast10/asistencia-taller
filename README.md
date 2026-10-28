# Sistema de Asistencia y Acreditación de Talleres con QR Dinámico (Flutter + PowerSync)

Aplicación multiplataforma (Windows Desktop, Web, Android e iOS) desarrollada en Flutter para la gestión de asistencia en talleres académicos (ej. *Taller de Pavimentación*), con validación estricta de doble registro (Entrada y Salida), protección criptográfica antifraude en tiempo real y **base de datos Local-First con PowerSync (SQLite)** con sellado inmutable de horas.

---

## 🚀 Características Principales

### 1. Regla de Acreditación Estricta (Doble Check Obligatorio)
- **🟢 Acreditado**: El estudiante registró tanto su **Entrada** al inicio como su **Salida** al finalizar la sesión.
- **🟡 Incompleto (Solo Entrada)**: Registró asistencia al ingresar pero se retiró antes del cierre.
- **🟡 Incompleto (Solo Salida)**: Llegó al final sin haber registrado la entrada a tiempo.
- **🔴 Inasistencia**: No cuenta con ningún registro en la sesión.

### 2. Base de Datos Local-First con PowerSync (SQLite) y Horas Inmutables 🔒
- **Arquitectura Local-First**: Opera 100% desconectado de internet en talleres o naves industriales donde no llega la señal de WiFi.
- **Sellado Inmutable de Horas**: Una vez que se registra la hora de Entrada o Salida, el campo queda **permanentemente bloqueado** (`is_locked = 1`). 
- **Prevención de Conflictos**: Nadie (ni el docente ni los alumnos) puede alterar retroactivamente las marcas de tiempo oficiales. Si se intenta reescribir, el sistema rechaza la operación y mantiene el registro original.
- **Listo para Sincronizar en la Nube**: PowerSync permite conectar en cualquier momento a un backend en la nube (PostgreSQL, Supabase o PowerSync Cloud) para respaldar los datos en cuanto el dispositivo detecta conexión.

### 3. QR Dinámico Antifraude (Anti-fotos y Anti-WhatsApp)
- **Rotación TOTP de 15 segundos**: El código QR proyectado por el docente cambia automáticamente cada 15 segundos mediante un algoritmo HMAC-SHA256 con firma temporal.
- **Protección contra fotos compartidas**: Si un alumno toma una foto a la pantalla o la envía por chat a un compañero ausente, el token expirará en segundos y será **rechazado de inmediato** con alerta de código caducado.
- **Fases controladas por el docente**:
  - `🟢 Pase de Entrada`: Solo acepta registros de ingreso.
  - `🟡 Taller en Curso`: El QR se pausa para evitar escaneos extemporáneos.
  - `🔵 Pase de Salida`: Solo acepta registros de egreso.
  - `⚪ Finalizar Sesión`: Cierra la sesión y consolida los estados finales.

### 4. Flujo del Estudiante: Sin Credenciales Físicas (100% Celular)
- **Cero Plásticos ni Papel**: El alumno no necesita ningún carnet o credencial física.
- **Escaneo y Envío de Número de Control**:
  1. El alumno abre la app en su teléfono y pulsa **"Escanear QR y Registrar Asistencia"**.
  2. Apunta la cámara al QR dinámico que el docente proyecta.
  3. La app detecta el taller y le pide su **Número de Control / Matrícula** (ej. `21010482`).
  4. El número de control queda **guardado en la memoria de su teléfono** para que en los siguientes escaneos ya esté precargado automáticamente.
  5. Pulsa **`[Enviar Asistencia al Sistema]`**: la asistencia se sella con hora inmutable 🔒 y queda registrada tanto en su celular como en la lista del docente.
- **Auto-Matriculación**: Si el docente no tenía al alumno previamente capturado en la lista, el sistema lo inscribe automáticamente al recibir su primer escaneo con su número de control y nombre.

### 5. Simulador de Pruebas Integrado (Testeo Inmediato)
- Permite probar el flujo completo en computadoras sin cámara web o sin dispositivos móviles secundarios:
  - Selecciona cualquier alumno del taller.
  - Simula escaneos de Entrada y Salida.
  - Cuenta con un interruptor para **"Simular foto vieja (>30s)"** y comprobar el rechazo del sistema antifraude.

### 6. Auditoría y Exportación de Reportes
- Conteo y métricas en tiempo real (Inscritos, Acreditados, Incompletos, Ausentes).
- Generación de reportes tabulares con hora exacta de entrada y salida selladas 🔒.
- Exportación oficial en formato **CSV compatible con Excel** con columna de sello de integridad.

---

## 💻 Cómo Ejecutar la Aplicación

Puedes ejecutar la aplicación directamente en tu entorno Windows con cualquiera de los siguientes comandos desde la terminal del proyecto:

### Opción 1: Ejecutar en Windows Desktop
```bash
flutter run -d windows
```

### Opción 2: Ejecutar en el Navegador (Chrome / Edge)
```bash
flutter run -d chrome
```

### Opción 3: Ejecutar en Dispositivo Móvil o Emulador Android
```bash
flutter run -d android
```

---

## 🧪 Pruebas Automatizadas
El proyecto cuenta con 11 pruebas unitarias y de integración que verifican:
- Reglas de acreditación (Doble Check).
- Inmutabilidad estricta de marcas de tiempo (impedimento de alteración).
- Seguridad criptográfica TOTP y rechazo de códigos QR expirados.

```bash
flutter test
```
Todas las pruebas pasan con 100% de éxito.
