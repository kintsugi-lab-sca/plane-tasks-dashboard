# MyTasks — kanban y gantt de Plane en la barra de menús de macOS

App nativa de barra de menús (macOS 14+) que muestra tus tareas de una instancia
[Plane](https://plane.so) self-hosted en un tablero kanban o un cronograma
(gantt): panel desplegable
anclado a la derecha de la pantalla, ventana de tablero independiente,
notificaciones de cambios, atajo de teclado global y edición de tareas sin salir
del panel. SwiftPM puro, sin dependencias externas.

## Características

- **Kanban por estados** con drag & drop entre columnas y orden por prioridad.
  Las cards muestran asignados (iniciales; círculo punteado si está sin asignar),
  módulo, ciclo, fechas, etiquetas y si hay descripción.
- **Cronograma (gantt)** conmutable desde la cabecera: barras por tarea con el color
  del estado, hitos, línea de "hoy", bandeja de tareas sin fechas y zoom continuo
  (pinch o ⌘+scroll, con presets día/semana/mes/trimestre). Arrastra una barra
  (o estira su borde) para reprogramar las fechas.
- **Edición desde la card**: estado (incluidos Done/Cancelled para cerrar tareas),
  prioridad, etiquetas y asignados, con actualización optimista y rollback si la API falla.
- **Detalle de tarea** en popover: descripción y comentarios renderizados en HTML.
- **Creación rápida** desde la cabecera del panel: título + prioridad + etiquetas;
  la tarea nace asignada a ti y en el módulo filtrado.
- **Filtros**: proyecto, módulo, ciclo, "solo mías", prioridad y búsqueda
  instantánea client-side.
- **Notificaciones nativas** de tareas nuevas asignadas a ti, cambios de estado
  hechos por otros y avisos de vencimiento (hoy y mañana); clic para abrir la
  tarea en Plane.
- **Atajo global** para mostrar/ocultar el panel (sin permisos de accesibilidad).
- **4 temas** (sistema, kintsugi, midnight, hacker) con colores personalizables,
  contador en el icono de la barra (todas / urgentes / vencidas) y arranque al
  iniciar sesión.

## Requisitos

- macOS 14 o superior.
- Una instancia de Plane (self-hosted o cloud) y un token de API.
- Para compilar: Swift 6 — bastan las Command Line Tools (`xcode-select --install`).
- Para los tests: Xcode.app instalado (las CLT no incluyen el framework Swift Testing;
  `make test` ya apunta al toolchain de Xcode vía `DEVELOPER_DIR`).

## Instalación

```sh
git clone git@github.com:kintsugi-lab-sca/plane-tasks-dashboard.git
cd plane-tasks-dashboard
make install   # compila en release, empaqueta MyTasks.app y la copia a /Applications
open /Applications/MyTasks.app
```

La app es `LSUIElement`: no aparece en el Dock, solo en la barra de menús.

### Firma de código (recomendado antes del primer `make install`)

El empaquetado firma con una identidad self-signed llamada **"MyTasks Dev"** si
existe en el llavero; si no, cae a firma ad-hoc. Con firma ad-hoc **cada rebuild
cambia la identidad de la app** y macOS vuelve a pedir los permisos de Keychain
y notificaciones, y el login item se desactiva. Para evitarlo, crea la identidad
una sola vez:

1. Abre **Acceso a Llaveros** → menú *Acceso a Llaveros → Asistente para
   Certificados → Crear un certificado…*
2. Nombre: `MyTasks Dev` · Tipo de identidad: *Raíz autofirmada* ·
   Tipo de certificado: **Firma de código**.
3. Crear. Debe quedar en el llavero de *inicio de sesión* (login).

Verifica que `security find-identity -v -p codesigning` la lista. A partir de ahí
`make install` la usará automáticamente y los permisos sobreviven a los rebuilds.

## Configuración inicial

1. Lanza la app y haz clic en su icono de la barra de menús para abrir el panel.
2. Abre **Ajustes** con el botón del engranaje (⚙) de la cabecera del panel.
3. En la sección **Conexión** rellena los tres campos:
   - **URL base** — la raíz de tu instancia de Plane, p. ej. `https://plane.miempresa.com`
     (sin `/api` ni barra final).
   - **Workspace slug** — el identificador del workspace tal y como aparece en la
     URL de Plane (`https://plane.miempresa.com/<slug>/…`).
   - **API token** — un *Personal Access Token* de Plane. Se genera en tu
     instancia: avatar → *Settings* → *API tokens*. Pulsa **Guardar**: el token se
     almacena en el **Keychain de macOS** (servicio `com.kintsugi-lab.mytasks`),
     nunca en ficheros ni UserDefaults.
4. En **Proyectos visibles**, pulsa *Cargar proyectos* y marca los que quieras
   en el tablero. El refresco solo consulta los proyectos visibles (Plane limita
   a 60 peticiones/min).

### Todos los ajustes

| Sección | Opciones |
|---|---|
| Conexión | URL base, workspace slug, API token (Keychain) |
| Apariencia | Tema (sistema / kintsugi / midnight / hacker), colores de acento/fondo/superficie/card, tamaño de letra |
| Visualización | Solo tareas asignadas a mí · contador del icono (todas / solo urgentes / oculto) · atajo global (⌥ Espacio, ⌘⌥ Espacio, ⌃⌥ T, ⌘⇧ K o desactivado) · intervalo de refresco (1–60 min, por defecto 5) · abrir al iniciar sesión |
| Notificaciones | Notificar cambios en tareas, con botón de prueba (requiere permiso del sistema) |
| Proyectos visibles | Selección de proyectos que se cargan y muestran |

## Uso

- **Panel**: clic en el icono de la barra (o el atajo global). Se ancla al borde
  derecho de la pantalla y se cierra al perder el foco o con el atajo.
- **Ventana de tablero**: botón de ventana en la cabecera del panel; es
  redimensionable y soporta pantalla completa nativa.
- **Crear tarea**: botón `+` de la cabecera → título, y opcionalmente prioridad
  (⚑) y etiquetas con los botones junto al campo. Enter crea, Esc cancela.
- **Editar una tarea**: clic en el tag de estado para moverla (incluye Done y
  Cancelled), clic derecho en la card para estado/prioridad/etiquetas/asignados,
  o arrástrala entre columnas. Clic en la card abre el detalle con descripción y
  comentarios; desde ahí también se abre en Plane.
- **Aviso "solo mías"**: las tareas creadas por integraciones sin asignado no
  aparecen con el filtro activo; la cabecera avisa y permite desactivarlo al vuelo.

## Desarrollo

```sh
make run       # build debug + lanzar desde terminal (sin bundle)
make test      # suite Swift Testing (requiere Xcode.app)
make app       # release + dist/MyTasks.app firmada
make install   # make app + copiar a /Applications
make clean     # borra .build y dist
```

Tras reinstalar, relanza con `pkill -x MyTasks && open /Applications/MyTasks.app`
(LaunchServices puede reabrir una copia vieja si ejecutaste el bundle desde otra ruta).

Detalles a tener en cuenta:

- **`make run` ejecuta el binario suelto, sin bundle**: las notificaciones y el
  login item no funcionan ahí (requieren bundle), y UserDefaults usa el dominio
  `MyTasks` en lugar de `com.kintsugi-lab.mytasks` — los ajustes de debug y de la
  app instalada no se comparten.
- **Icono**: `swift scripts/make_icon.swift <png>` regenera `Resources/MyTasks.icns`
  a partir de un PNG cuadrado.
- **Probar notificaciones sin UI**: `MYTASKS_NOTIF_TEST=1` al lanzar la app
  escribe el diagnóstico en `/tmp/mytasks-notif-test.txt`.
- **Estructura** (`Sources/MyTasks/`): `AppState` (estado observable y cachés),
  `PlaneClient` (REST v1 de Plane con paginación por cursor), `Models`,
  `RefreshDiff` (difs notificables, lógica pura testeada), `AppWindows` (chrome
  AppKit: status item, panel, ventanas), `HotKey` (Carbon), `Theme`, `Settings`,
  `Notifications` y `Views/`. Los tests viven en `Tests/MyTasksTests/`.
- **Gotcha de macOS 26**: los menús de las cards usan `NSMenu` de AppKit
  construido on-demand (`ClosureMenuItem`) en lugar de `Menu` de SwiftUI inline —
  con muchas cards en un `LazyVStack`, `Menu` mete al view graph en un bucle
  infinito de invalidación (CPU al 100 % y freeze).

## Limitaciones conocidas

- El filtro por asignado se hace en cliente: la API v1 de Plane no filtra por
  asignado, así que se cruza con `users/me`.
- La pertenencia a módulos/ciclos se resuelve con peticiones extra
  (`module-issues` / `cycle-issues`): el work item no trae esos campos.
- Rate limit de Plane: 60 req/min; con muchos proyectos visibles conviene subir
  el intervalo de refresco.
