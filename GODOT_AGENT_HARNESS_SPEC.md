# Spec: Godot Agent Harness

Addon de editor para Godot 4, escrito 100% en GDScript. Conecta agentes de código (Claude Code primero; después Gemini CLI, Codex o un agente propio) al editor. Sirve tanto para tareas chicas (revisar un script) como para un one-shot completo (planificar, construir y playtestear un juego).

---

## 0. Cómo usar este documento (leer primero)

1. **Antes de diseñar o crear archivos, cargá las skills de Godot del proyecto**: `godot-architecture`, `godot-communication`, `godot-patterns` y `godot-code-review` (y `godot-data-driven` para settings y recursos).
   - Las skills mandan en estructura de carpetas, naming, uso de señales, autoloads, Resources y separación de responsabilidades.
   - Este spec manda en comportamiento, protocolos y restricciones.
   - Si chocan, seguí la skill para la forma y este spec para el qué, y anotá la decisión en `docs/decisions.md`.
2. Trabajá **por milestones** (sección 12). Al terminar cada uno:
   - corré las verificaciones de ese milestone,
   - escribí en `docs/progress.md` qué quedó, cómo probarlo a mano y qué quedó pendiente,
   - **pará y esperá confirmación** antes de seguir.
3. Si una restricción de la sección 2 te bloquea, frená y preguntá. No la rompas.
4. Los nombres de métodos ACP y MCP de este documento están verificados contra la documentación pública. Si el agente real responde algo distinto, gana el agente real: registralo en `docs/decisions.md` y adaptá.

---

## 1. Objetivo

Un cliente **ACP (Agent Client Protocol) nativo dentro del editor de Godot**:

- **Hacia el agente**: lanza el proceso del agente y le habla ACP por stdio.
- **Hacia el editor**: expone herramientas del editor (árbol de escena, errores, correr escenas, capturar el viewport, editar nodos con undo) mediante un **servidor MCP HTTP servido por el propio addon** en localhost. El agente se conecta a ese servidor.
- **Para el usuario**: una UI integrada en el editor con cuatro modos: Preguntar, Revisar, Construir y One-shot.

No hay daemon, ni server en Python, ni binarios nativos. El único proceso externo es el agente.

---

## 2. Restricciones duras

- **Solo GDScript.** Sin GDExtension, sin Rust, sin C#, sin Python.
  - Runtime externo permitido: el proceso del agente y lo que ese agente ya necesite (por ejemplo Node para el adapter de Claude).
  - Las herramientas de test también son GDScript (ver sección 13).
- **Versión de Godot**: el desarrollo es en 4.8 beta.
  - Mínimo soportado: 4.6 (antes 4.4; se subió para mantener tres versiones: 4.6, 4.7 y 4.8, docs/decisions.md D34).
  - Verificá la firma real de `OS.execute_with_pipe` en la versión mínima. Si algo requiere una versión mayor, documentalo.
- **Tipado estático** en todo el código (`var x: int`, retornos tipados, `class_name` donde la skill lo indique).
- **Plataformas**: Linux primero, pero nada de bash-isms. Paths con `ProjectSettings.globalize_path` y comandos configurables. Tiene que poder andar en Windows y macOS.
- **Solo editor.** Todo bajo `res://addons/godot_agent/`, scripts `@tool`. **Nada del addon llega a un juego exportado**: ni archivos, ni autoloads, ni entradas en `project.godot`.
  - **Archivos**: un `EditorExportPlugin` que en `_export_file` llama a `skip()` para todo lo que está bajo `res://addons/godot_agent/`.
  - **Red de seguridad para cuando el plugin está deshabilitado al exportar**: recomendar (en el README y con un aviso en Settings) agregar `addons/godot_agent/*` al filtro de exclusión de cada preset. Ofrecer un botón "Agregar a los presets" que edite `export_presets.cfg` previa confirmación.
  - **Autoload de playtest**: existe solo mientras corre un playtest pedido por el harness (ver `run_scene` en la sección 6). En `_export_begin`, si sigue registrado, mostrar un error claro y quitarlo. Verificá si quitarlo en ese punto afecta al export en curso y documentalo.
  - La UI del agente y el completado predictivo viven solo en el editor.
- **Red**: el servidor MCP escucha solo en `127.0.0.1` y exige un token aleatorio por sesión en el header `Authorization: Bearer <token>`.
  - Única excepción saliente: el endpoint del proveedor de completado que el usuario configure (sección 16). Por defecto es local.
- **Toda mutación del editor pasa por `EditorUndoRedoManager`**: nodos, propiedades, conexiones de señales. Ctrl+Z tiene que deshacer lo que hizo el agente, acción por acción.
- **La UI nunca toca el transporte directamente.** UI → SessionModel → AcpClient → AgentProcess.
- **Nada bloquea el hilo principal.** Leer el pipe y aceptar conexiones HTTP corre en `Thread`s o con polling no bloqueante en `_process`. Toda llamada a API del editor vuelve al hilo principal con `call_deferred`.

---

## 3. Arquitectura

```
Godot editor (hilo principal)
└─ EditorPlugin (plugin.gd)
   ├─ UI ─────────────── AgentDock · AgentMainScreen · AgentLogPanel · ReviewAnnotations
   │      ▲ señales
   ├─ SessionModel ───── estado de la conversación, tool calls, plan, modo, permisos pendientes
   │      ▲ eventos ACP          │ comandos
   ├─ AcpClient ──────── JSON-RPC 2.0, ids, requests pendientes, handlers client-side
   │      ▲ líneas JSON          │
   ├─ AgentProcess ───── OS.execute_with_pipe + lectura por frame (stdout/stderr) ⇄ proceso agente
   │
   ├─ McpServer ──────── TCPServer 127.0.0.1:<puerto> · HTTP mínimo · Streamable HTTP (JSON)
   │      └─ ToolRegistry ── tools godot.* (lectura, edición, ejecución)
   ├─ PermissionPolicy ─ matriz modo × grupo de herramienta → allow / ask / deny
   ├─ Checkpoints ────── git (rama/commit temporal) antes de tareas de One-shot
   ├─ QuotaMonitor ───── cuota del plan informada por el agente → avisos, pausa y reanudación
   └─ HarnessSettings ── perfiles de agentes, puerto, presupuestos (EditorSettings / ProjectSettings)
```

Componentes y responsabilidades (la ubicación exacta de archivos la define la skill de arquitectura):

| Componente | Responsabilidad | No hace |
|---|---|---|
| `AgentProcess` | Lanza el comando del perfil y lee stdout línea por línea y stderr desde el hilo principal, sin bloquear y sin threads (D35). Expone `send_line(String)`, la señal `line_received(String)`, `stderr_received(String)` y `exited(code)`. Mata el proceso al deshabilitar el plugin o cerrar el editor. | No parsea JSON |
| `AcpClient` | JSON-RPC 2.0 sobre líneas. Mapa id → callback. `request(method, params) -> Variant` usable con `await`. Despacha requests entrantes del agente a handlers registrados. | No conoce la UI |
| `SessionModel` | Fuente de verdad de la sesión: mensajes (con merge de chunks), tool calls por `toolCallId`, plan, modo actual, permisos pendientes, uso de tokens. Emite señales granulares. | No hace IO |
| `McpServer` | HTTP mínimo (POST `/mcp`), valida el token, rutea `initialize`, `tools/list` y `tools/call` al `ToolRegistry`. | No decide permisos |
| `ToolRegistry` + tools | Cada tool declara `name`, `description`, `inputSchema`, `group` y `func execute(args) -> Dictionary`. Las tools que mutan usan undo. | No hablan con el agente |
| `PermissionPolicy` | Decide allow / ask / deny según el modo y el grupo. En "ask" crea un pedido en el SessionModel y espera la respuesta de la UI. | — |

---

## 4. ACP: qué implementar

Transporte: JSON-RPC 2.0, **un mensaje JSON por línea** en stdin/stdout del agente. El stderr del agente va al `AgentLogPanel`; nunca se parsea.

### 4.1 Cliente → agente

| Método | Uso |
|---|---|
| `initialize` | `protocolVersion: 1`, `clientInfo {name, title, version}`, `clientCapabilities { fs: { readTextFile: true, writeTextFile: true }, terminal: false }` (terminal en v1 = false). Guardar `agentCapabilities` (`loadSession`, `promptCapabilities {image, audio, embeddedContext}`, `mcpCapabilities {http, sse}`) y `authMethods`. |
| `authenticate` | Solo si `authMethods` no viene vacío y el agente lo exige. En v1 alcanza con mostrar en la UI que hace falta autenticarse y cómo. |
| `session/new` | `cwd`: ruta absoluta del proyecto (`ProjectSettings.globalize_path("res://")`). `mcpServers`: el server del addon (ver 4.3). |
| `session/prompt` | `sessionId` + `prompt: ContentBlock[]`: texto del usuario, más resource links o recursos embebidos para el contexto (escena actual, selección, script abierto), más una imagen si hay captura y `promptCapabilities.image` lo permite. La respuesta trae `stopReason`: `end_turn`, `max_tokens`, `max_turn_requests`, `refusal` o `cancelled`. |
| `session/cancel` | Notificación (sin id). Al cancelar, marcar los tool calls sin terminar como `cancelled` y responder los permisos pendientes con outcome `cancelled`. |
| `session/set_mode` | Opcional. Si el agente publica modos, mapearlos a los modos del harness. Si no, el modo vive solo del lado del cliente (PermissionPolicy). |
| `session/load` | Solo si `loadSession` es true. Sirve para reanudar sesiones desde el historial. |

### 4.2 Agente → cliente

**`session/update`** (notificación). Hay que manejar todas estas variantes de `sessionUpdate`:

- `agent_message_chunk`, `user_message_chunk` y `agent_thought_chunk`: concatenar en la entrada actual. Los thoughts se muestran colapsados.
- `tool_call` y `tool_call_update`, indexados por `toolCallId`. Campos:
  - `title`
  - `kind`: `read`, `edit`, `delete`, `move`, `search`, `execute`, `think`, `fetch`, `switch_mode` u `other`
  - `status`: `pending`, `in_progress`, `completed` o `failed`; `cancelled` local tras un cancel
  - `content[]` de tipo `content` (bloque de texto o imagen), `diff` (`path`, `oldText` que puede ser null, `newText`) o `terminal`; en v1 este último se muestra como "no soportado"
  - `locations[]` con `path` y `line`, para saltar al archivo y la línea
- `plan`: reemplazar el plan completo.
- `available_commands_update`: autocompletado de `/comandos` en el composer.
- `current_mode_update`, `config_option_update`, `session_info_update` y `usage_update`: reflejarlos en la UI. `usage_update` alimenta el medidor de contexto.
- `notice`, `compaction_update` y `compaction_summary_chunk`: solo si se declaran las capabilities correspondientes. En v1 se ignoran sin romper.
- **Cualquier variante desconocida se loguea y se ignora.** Nunca crashea.

**`session/request_permission`** (request; hay que responder):

- params: `sessionId`, `toolCall` (un ToolCallUpdate), `options[]` con `optionId`, `name` y `kind` (`allow_once`, `allow_always`, `reject_once` o `reject_always`).
- respuesta: `{ "outcome": { "outcome": "selected", "optionId": "<id>" } }` o `{ "outcome": { "outcome": "cancelled" } }`.
- Flujo: primero consultar `PermissionPolicy`.
  - Si la política resuelve sola (allow o deny según el modo), responder sin molestar al usuario.
  - Si dice "ask", mostrar la tarjeta de permiso y esperar.
  - "Siempre en esta sesión" queda en memoria de la sesión, nunca en disco.

**`fs/read_text_file` y `fs/write_text_file`**:

- Leer: si el archivo está abierto en el Script Editor con cambios sin guardar, devolver el **buffer del editor**, no el disco.
- Escribir: escribir a disco y después sincronizar con el editor (sección 8). Si el script está abierto, actualizar el buffer del `CodeEdit` en vez de pisarlo, preservando el undo del editor de texto si es posible.
- Rechazar rutas fuera del proyecto, salvo directorios extra configurados.

**`terminal/*`**: no se declara en v1 (`terminal: false`).

**Errores**: un request desconocido del agente se responde con el error JSON-RPC `-32601`.

### 4.3 Conectar el MCP del addon al agente

En `session/new`:

- Si `agentCapabilities.mcpCapabilities.http == true`, pasar:
  ```json
  { "type": "http", "name": "godot", "url": "http://127.0.0.1:<port>/mcp",
    "headers": [{ "name": "Authorization", "value": "Bearer <token>" }] }
  ```
- Si **no** soporta HTTP, el fallback es una entrada stdio. Implementá un **shim stdio→HTTP en GDScript** que corra con `godot --headless --script res://addons/godot_agent/.../mcp_stdio_shim.gd`: lee líneas de stdin, las reenvía por HTTP al server del editor y escribe las respuestas en stdout. Usá `OS.get_executable_path()` como `command` (ruta absoluta), el puerto y el token por `env`.

### 4.4 Perfiles de agentes

Cada perfil define `id`, `display_name`, `command`, `args[]`, `env{}` y `default: bool`. Perfil inicial:

- **Claude Code**: adapter ACP oficial publicado en npm como `@zed-industries/claude-agent-acp` (antes `@zed-industries/claude-code-acp`).
  - **Verificá con `npm view` el nombre del paquete y el binario antes de fijarlo como default.**
  - Por defecto, que no requiera API key si el usuario ya está logueado en Claude Code. Si hay una `ANTHROPIC_API_KEY` en el entorno, mostrar un aviso de que puede cambiar la facturación.

Dejá el resto de los perfiles (Gemini CLI, Codex, custom) como entradas editables sin hardcodear flags inciertos.

---

## 5. Servidor MCP del addon

- `TCPServer` en `127.0.0.1`. Puerto configurable; 0 significa aleatorio, y el puerto real se informa en la UI y en `session/new`.
- HTTP/1.1 mínimo, suficiente para Streamable HTTP con respuestas JSON:
  - `POST /mcp` con un body JSON-RPC; responder `Content-Type: application/json`. No hace falta SSE en v1.
  - Respetar `Content-Length`, no soportar chunked en requests y cerrar la conexión según `Connection`.
  - Si viene `Mcp-Session-Id`, devolverlo; si no, generar uno en `initialize`.
  - Notificaciones (sin id) → `202 Accepted` sin body.
  - Token inválido → `401`. Método o ruta incorrectos → `404` o `405`.
- Métodos MCP: `initialize` (devolver `protocolVersion` compatible con el que pide el cliente, `capabilities: { tools: {} }` y `serverInfo`), `notifications/initialized`, `tools/list`, `tools/call` y `ping`.
- Resultado de `tools/call`: `{ content: [ {type:"text", text} | {type:"image", data, mimeType} ], isError: bool }`.
- Cada request se ejecuta en el hilo principal. El thread de red encola, y `_process` despacha y responde.
- Toda llamada a una tool se registra en `AgentLogPanel` con nombre, duración y resultado resumido.

---

## 6. Herramientas `godot.*`

Agrupadas para que `PermissionPolicy` pueda decidir. Los argumentos usan rutas `res://` y NodePaths relativos a la raíz de la escena.

| Tool | Grupo | Args | Devuelve |
|---|---|---|---|
| `project_info` | read | — | Versión de Godot, nombre del proyecto, escena principal, autoloads, input map resumido, plugins activos |
| `list_files` | read | `path`, `pattern?`, `recursive?` | Rutas con tipo de recurso |
| `scene_tree` | read | `scene?` (default: escena abierta), `depth?` | Árbol con nombre, tipo, script, grupos y propiedades no default (compacto) |
| `get_node` | read | `scene?`, `node_path` | Propiedades, señales conectadas, script |
| `editor_state` | read | — | Escena actual, escenas abiertas, selección, script abierto con línea del cursor |
| `class_info` | read | class, member?, inherited?, description? | API de una clase en la versión del editor (ClassDB + caché de docs del editor); built-ins, @GlobalScope y class_name |
| `search_api` | read | query, kind?, class? | Busca clases y miembros por nombre o capacidad |
| `get_errors` | diagnostics | `since?` | Errores y warnings de scripts y del panel Output o Debugger desde una marca |
| `validate_scripts` | diagnostics | `paths?` | Parseo de los scripts indicados (o todos), con errores por línea. Usar la recarga o el parse del editor; si no alcanza, `godot --headless --check-only` como subproceso |
| `capture_editor_viewport` | diagnostics | `which: "2d"\|"3d"` | PNG en base64 como content de imagen |
| `add_node` | edit_scene | `parent`, `type`, `name`, `properties?` | NodePath creado y nombre del paso de undo |
| `add_nodes` | edit_scene | parent, nodes[{name, type\|scene, properties?, script?, groups?, children?}], scene? | Subárbol entero en un paso de undo (m4-08) |
| `duplicate_node` | edit_scene | node_path, new_name?, new_parent?, scene? | Duplica con hijos, script, grupos y conexiones internas |
| `set_properties` | edit_scene | `node_path`, `properties` | Valores anteriores y nuevos |
| `remove_node` / `reparent_node` / `rename_node` | edit_scene | — | Con undo |
| `connect_signal` | edit_scene | `from`, `signal`, `to`, `method` | Con undo y conexión persistente |
| `instantiate_scene` | edit_scene | `parent`, `scene_path`, `name?` | Con undo |
| `project_settings` | read | prefix? | Settings con valor y default |
| `set_project_setting` | project | name, value | Con undo global; guarda project.godot (m4-09) |
| `set_input_action` / `remove_input_action` | project | action, events[], deadzone?, append? | Eventos como "Space", "Ctrl+S", "mouse:left", "joy_button:a", "joy_axis:left_x:-" |
| `set_autoload` / `remove_autoload` | project | name, path, enabled? | Con undo global |
| `tilemap_get` | read | node_path, rect? | TileSet (fuentes, física, terrenos) y mapa ASCII con leyenda (m4-11) |
| `tileset_add_atlas` / `tileset_add_scenes` | edit_scene | node_path, texture/scenes, tile_size?, collision? | Fuentes del TileSet con undo |
| `tilemap_set_cells` / `tilemap_paint_terrain` / `tilemap_clear` | edit_scene | node_path, cells?, rect?, source_id?, atlas?, terrain? | Un paso de undo por llamada (tile_map_data antes/después) |
| `animation_get` | read | node_path, animation? | Animaciones y pistas con keys; o los SpriteFrames (m4-12) |
| `animation_create` / `animation_set_track` / `animation_remove` | edit_scene | node_path, name/animation, track, keys | Undo cambiando la animación por una copia editada |
| `sprite_frames_set` | edit_scene | node_path, animation, frames? \| sheet?, fps?, loop? | SpriteFrames desde imágenes o una hoja |
| `get_resource` | read | path | Tipo, script, uid y propiedades no default con sub-recursos |
| `create_resource` / `set_resource_properties` | edit_files | path, type, properties | `.tres` por el editor, con undo al cambiar (m4-13) |
| `move_file` / `copy_file` / `delete_file` | edit_files | from, to / path | Con referencias al día y uid; borrar se niega si algo lo usa (m4-10) |
| `create_scene` | edit_files | `path`, `root_type`, `root_name` | Crea y guarda el `.tscn` |
| `open_scene` / `save_scene` | edit_scene | `path` | — |
| `attach_script` | edit_files | `node_path`, `script_path` | Crea el script si no existe |
| `run_scene` | run | `scene?`, `seconds`, `inputs?` | Corre la escena, espera N segundos o la salida y devuelve errores y Output capturados. Ver nota |
| `capture_game_frame` | run | — | Frame del juego corriendo, como imagen |
| `stop_scene` | run | — | — |
| `game_tree` / `game_get` | read | path, depth / properties | Árbol vivo y propiedades del juego corriendo (m4-07, D54) |
| `game_set` / `game_call` | run | path, properties / method, args | Cambia propiedades o llama métodos en vivo |
| `game_wait` | run | path, condition \| signal, timeout | Espera una Expression sobre el nodo, una señal o N segundos |
| `game_input` | run | steps | Teclas, acciones, clicks, movimiento y joystick en vivo |

**Notas de implementación:**

- **Scripts**: el agente edita archivos con sus propias herramientas o con `fs/write_text_file`. No dupliques un `write_file` en MCP.
- **`run_scene`**:
  - Usar `EditorInterface.play_custom_scene` o `play_current_scene` y `stop_playing_scene`.
  - Para capturar frames y simular input hace falta código dentro del juego: un `EditorDebuggerPlugin` en el editor y un **autoload de playtest** en el juego. Hablan por el canal del debugger (`EngineDebugger` / `EditorDebuggerSession`, con prefijo `godot_agent:`).
  - El juego que se lanza desde el editor es un proceso aparte que lee `project.godot` del disco, así que el autoload tiene que estar registrado mientras se juega. **Ciclo de vida, para que nunca llegue a un export:**
    1. **Alta**: en `EditorPlugin._build()`, que se llama justo antes de ejecutar el proyecto, y **solo si el run lo pidió el harness** (un flag interno que pone `run_scene`). Los runs manuales del usuario no lo llevan, salvo que se active una opción en Settings.
    2. **Baja**: al terminar la sesión de debug (señal de stop de `EditorDebuggerSession`) o tras `stop_playing_scene`.
    3. **Limpieza**: en `_enter_tree` del plugin, si quedó registrado por un crash del editor, se quita.
    4. **Guard en el script**: si no está corriendo desde el editor (`OS.has_feature("editor")`; verificá en 4.4 y 4.8 si existe un tag más preciso como `editor_runtime`) o si `EngineDebugger.is_active()` es false, se libera sin hacer nada.
    5. **Aislado**: un script chico sin `preload` ni referencias a clases `@tool` del addon, para que cargarlo en el juego no arrastre código de editor.
  - `inputs` es una lista de pasos `{t: segundos, action: "ui_accept", pressed: bool}` que el autoload reproduce con `Input.parse_input_event`.
- **Límites de salida**: el texto se trunca a un máximo configurable (por ejemplo 20k caracteres) con aviso de truncado. Las imágenes se reescalan a un máximo de 1280 px.
- **Errores de tool**: devolver `isError: true` con un mensaje accionable. Nunca dejar una excepción sin respuesta.

---

## 7. Modos y permisos

| Grupo | Preguntar | Revisar | Construir | One-shot |
|---|---|---|---|---|
| read | allow | allow | allow | allow |
| diagnostics | allow | allow | allow | allow |
| edit_scene | deny | deny | ask | allow |
| edit_files (incluye `fs/write_text_file` y Edit/Write del agente) | deny | deny | ask | allow |
| run | deny | ask | ask | allow |
| shell / execute del agente | deny | deny | ask | ask |
| project settings / export / addons | deny | deny | ask | allow (D49) |

- Los permisos del agente (`session/request_permission`) se mapean a grupos según el `kind` del tool call: `read`/`search` → read; `edit`/`delete`/`move` → edit_files; `execute` → shell; el resto → ask.
- Las tools MCP del addon aplican la misma política del lado del server. En "ask", la tool espera la respuesta de la UI con un timeout configurable; si vence, devuelve deny con mensaje.
- **Revisar** es solo lectura de verdad: los hallazgos salen como texto estructurado del agente. Pedile en el prompt de sistema del modo que use el formato de 9.4.
- La matriz es configurable en Settings. Los valores de arriba son los defaults.

---

## 8. Sincronización editor ↔ disco (crítico)

1. Después de cualquier escritura de archivo por el agente (detectada por `fs/write_text_file`, por un tool call `edit` completado con `diff` o por un watcher de mtime en `res://`):
   - `EditorInterface.get_resource_filesystem().update_file(path)`, o `scan()` si son varios.
   - Si el script está abierto en el Script Editor, recargarlo sin perder la posición del cursor y sin el diálogo de "archivo modificado externamente" cuando el usuario no tenía cambios.
   - Si el usuario **sí** tenía cambios sin guardar, no pisar: marcar conflicto en la UI y ofrecer ver diff, usar la versión del agente o mantener la propia.
2. Escenas **abiertas**: el agente no debe editarlas en disco.
   - Si llega una escritura a un `.tscn` abierto, avisar en la UI y recargar la escena sólo si el usuario acepta.
   - El prompt de sistema le indica al agente usar las tools `edit_scene` para escenas abiertas.
3. Archivos `.uid` y `.import`: el agente no los crea ni los edita. Ponelo en el prompt de sistema y avisá en el log si ocurre.
4. **Prompt de sistema del harness**: un texto corto que se agrega como contexto en el primer `session/prompt` de cada sesión. Explica las tools `godot.*`, las reglas 2 y 3, el modo actual y que respete el `CLAUDE.md` del proyecto si existe. Va en un archivo editable del addon, no hardcodeado.

---

## 9. UI

Existe un mockup de referencia con 4 pantallas. Respetá la estructura; los estilos salen del theme del editor (`EditorInterface.get_editor_theme()`), con **un solo color de acento** para todo lo que es del agente (default ámbar `#f0a85a`, configurable).

### 9.1 Dock "Agent" (`add_control_to_dock`, por defecto a la derecha junto al Inspector)

- **Header**: selector de perfil de agente, título de sesión, botones de historial, nueva sesión y ajustes (`aria`/tooltip en los botones de icono).
- **Selector de modo**: Preguntar, Revisar, Construir, One-shot.
- **Medidor de cuota del plan** (sección 10.1): barras de ventana actual y semanal, con porcentaje y tiempo hasta el reinicio. Si el agente no informa cuota, se oculta y queda solo el medidor de contexto del composer.
- **Lista de mensajes** (virtualizada o con un límite razonable de nodos):
  - Burbuja del usuario.
  - Texto del agente en `RichTextLabel`, con un conversor Markdown→BBCode propio y mínimo: párrafos, **negrita**, *itálica*, `code`, bloques de código, listas y links.
  - **Grupo de tool calls** colapsable: estado (✓, ✗, spinner), nombre, resumen y "↶ undo" cuando aplica.
  - **Tarjeta de diff**: ruta, +N/−M, primeras líneas y botón "Abrir en Script".
  - **Tarjeta de permiso**: título, descripción del tool call y las opciones que mandó el agente como botones.
  - Plan colapsable.
- **Composer**:
  - Chips de contexto: escena actual y selección actual (se agregan solos y se pueden quitar), más "+ contexto".
  - `TextEdit` con `@` para autocompletar nodos y archivos, y `/` para comandos del agente.
  - Botones para mencionar, adjuntar una captura del viewport y abrir comandos.
  - Medidor de contexto (a partir de `usage_update`), selector de modelo si el agente expone opciones, y botón enviar o detener.
- **Atajos**: Ctrl+Enter envía, Esc cancela el turno.

### 9.2 Pantalla principal "Agent" (`_has_main_screen`) para One-shot

- **Barra superior**: objetivo, estado y fase, presupuestos (cuota de la ventana, tiempo, tokens, playtests) con barras, la regla de cuota activa en una línea ("se pausa al 90 % en el próximo checkpoint") y botones Pausar y Detener. En estado "Limitado" muestra la cuenta regresiva hasta el reinicio.
- **Tres columnas**:
  - Plan con estados; el usuario puede editarlo y el texto editado se manda como mensaje.
  - Actividad con timestamps y un input "Guiar al agente" que manda un `session/prompt` adicional al terminar el turno actual.
  - Último playtest (captura), verificaciones (checklist que el agente reporta) y checkpoints con "Volver acá".
- **Barra inferior**: resumen de cambios (archivos y +/−), "Revisar cambios" (abre la lista de diffs) y "Aceptar todo".

### 9.3 Panel inferior "Agent Log" (`add_control_to_bottom_panel`)

Log en monoespaciado con columnas `hora · canal (acp | mcp | fs | perm | proc | quota | cmp) · mensaje`, filtros por canal y botón para copiar. Los mensajes JSON-RPC completos se ven con un modo "raw" activable.

### 9.4 Revisión en el Script Editor

- Los hallazgos del modo Revisar vienen en un bloque JSON del agente: `{"findings":[{"path","line","severity":"bug|order|perf|style","title","body","suggestion?"}]}`. Parsearlo de forma tolerante.
- Para cada hallazgo:
  - Marcar la línea en el `CodeEdit` (color de fondo y gutter con un color por severidad).
  - Mostrar la tarjeta con "Aplicar arreglo" (cambia a Construir y pide ese arreglo puntual), "Preguntar" y "Descartar".
- Lista de hallazgos en el dock, y botón "Exportar a CLAUDE.md" (agrega una sección con las convenciones derivadas, previa confirmación).

### 9.5 Settings

Dentro de un diálogo propio o una sección en Project Settings:

- Perfiles de agentes (CRUD).
- Matriz de permisos.
- Puerto MCP y regeneración del token.
- Presupuestos default de One-shot.
- **Cuota y límites**: umbral de aviso, umbral de pausa del One-shot (o nunca) y comportamiento al reiniciarse la ventana (retomar solo o esperar confirmación).
- Checkpoints on/off.
- Ubicación del dock.
- Color de acento.

---

## 10. One-shot: el loop

1. El usuario escribe el objetivo y elige presupuestos (tiempo, tokens, máximo de playtests).
2. Si checkpoints está activo: `git` disponible y repo limpio, o con un commit WIP previo y confirmación. Crear la rama `agent/<timestamp>`.
3. El harness manda un prompt inicial con:
   - el objetivo,
   - el modo One-shot,
   - la instrucción de producir un plan (`plan`) y de reportar verificaciones en un bloque `{"checks":[{"label","status":"pass|fail|pending"}]}`,
   - la instrucción de usar `run_scene`, `capture_game_frame` y `get_errors` después de cada tarea.
4. Antes de cada tarea del plan (detectada cuando una entrada pasa a `in_progress`), crear un checkpoint: commit en la rama con mensaje `cpN: <tarea>`.
5. **Presupuestos**:
   - Al 80% de cualquier presupuesto, avisar en la UI.
   - Al 100%, mandar `session/cancel` y luego un prompt de cierre que pida un reporte final.
6. **"Volver acá"**: confirmar, luego `git reset --hard cpN` dentro de la rama del agente (nunca en la rama del usuario), `scan()` del filesystem y recarga de las escenas abiertas.
7. "Aceptar todo" deja la rama lista para que el usuario haga merge. **El harness nunca hace merge ni push solo.**

Todos los comandos git se ejecutan con `OS.execute` y argumentos en array (sin shell). Si git no está disponible, los checkpoints se desactivan con un aviso.

### 10.1 Cuota del plan

Un componente `QuotaMonitor` sigue el consumo del plan del usuario (por ejemplo una suscripción de Claude) y lo expone al `SessionModel`. Funciona en todos los modos, pero solo el One-shot pausa y retoma solo.

**Fuentes de datos, en orden:**
1. **`usage_update` de ACP**: guardar el payload crudo de cada actualización y mapear los campos de cuota (uso de la ventana, uso semanal, hora de reinicio) si existen. Los nombres de campo reales salen de la verificación del M1, no de suposiciones.
2. **Avisos y errores de límite**: un error JSON-RPC en `session/prompt`, un `notice` o un mensaje del agente que indique que se alcanzó el límite, con la hora de reinicio si la informa. El parseo es tolerante, con patrones en un archivo editable del addon.
3. **Sin datos de cuota**: mostrar solo los tokens de la sesión y ocultar las barras de cuota, con un tooltip que diga que el agente no la informa.

**Prohibido**: estimar porcentajes de cuota a partir de tokens, consultar endpoints no documentados o leer archivos internos o credenciales del agente. Si no hay dato, la UI dice "desconocido".

**Estados**: `normal`, `aviso` (pasó el umbral de aviso), `pausa_programada` (pasó el umbral de pausa, termina la tarea actual), `limitado` (límite alcanzado, esperando reinicio) y `desconocido`.

**Reglas en One-shot:**
- **Umbral de aviso** (default 75 %): banner en la pantalla Agent y entrada en el canal `quota`.
- **Umbral de pausa** (default 90 %): no corta el turno en curso. Cuando la tarea actual termina y se crea su checkpoint, el harness no manda la siguiente y pasa a "Pausado por cuota".
- **Límite alcanzado a mitad de turno**: marcar los tool calls pendientes como `cancelled`, crear un checkpoint del estado actual (`cpN-quota`) y pasar a "Limitado".
- **Reinicio**:
  - Con hora de reinicio conocida: un timer hasta esa hora.
  - Sin hora: reintentos con backoff (5, 10, 20 y luego cada 60 min), cada uno con un prompt mínimo de reanudación.
- **Reanudar**: según Settings, automáticamente o con confirmación. Se manda un `session/prompt` del tipo "continuá con el plan desde la tarea X; el estado está en el checkpoint cpN". Si la sesión se perdió, usar `session/load` si existe; si no, abrir una sesión nueva con un resumen del plan, los checks y los checkpoints.
- Los presupuestos propios del One-shot (tiempo, tokens, playtests) siguen aplicando aparte. El tiempo en "Limitado" no cuenta contra el presupuesto de tiempo.

**Fuera de One-shot** (dock): solo avisos. En "Limitado", el botón enviar se deshabilita y muestra la cuenta regresiva.

---

## 11. Settings y persistencia

- **Por usuario** (perfiles de agentes, ubicación del dock, color, umbrales de cuota): `EditorSettings`, con el prefijo `godot_agent/`. La cuota es del plan del usuario, no del proyecto.
- **Por proyecto** (matriz de permisos y presupuestos): un `Resource` en `res://addons/godot_agent/` o en `ProjectSettings` con el prefijo `godot_agent/`. Que lo decida la skill de data-driven.
- **Historial de sesiones**: `user://godot_agent/sessions/<id>.json` con los eventos ACP normalizados, para reabrir y mostrar. Si el agente soporta `session/load`, usarlo para reanudar de verdad.
- **Secretos**: no se guardan. El token MCP se regenera en cada arranque del editor.

---

## 12. Milestones

Cada milestone termina con verificaciones automáticas (sección 13), instrucciones de prueba manual en `docs/progress.md` y una pausa para confirmación.

**M0: esqueleto y decisiones**
- Cargar las skills y proponer la estructura de carpetas y la lista de clases en `docs/decisions.md`.
- `plugin.cfg`, `plugin.gd` que agrega y quita el dock vacío, el panel inferior y la main screen sin errores ni leaks al deshabilitar.
- `EditorExportPlugin` que excluye el addon, chequeo de autoload huérfano en `_export_begin` y botón "Agregar a los presets".
- Test headless de export (`tests/export_check.gd`): exporta un preset de prueba como `.zip` con `--export-pack`, lo abre con `ZIPReader` y falla si encuentra cualquier archivo de `addons/godot_agent/` o el autoload de playtest en el `project.binary`.
- ✅ Habilitar y deshabilitar el plugin 5 veces seguidas sin errores en Output. El test de export pasa con el plugin habilitado y también deshabilitado (con el filtro del preset).

**M1: transporte y ACP mínimo**
- `AgentProcess` + `AcpClient` + `SessionModel`, más el agente falso (sección 13).
- `initialize` → `session/new` → `session/prompt` con streaming de `agent_message_chunk` al dock, y `session/cancel`.
- Agent Log con canales.
- `QuotaMonitor` en modo observación: loguear crudo en el canal `quota` cada `usage_update` y cualquier aviso o error de límite.
- **Verificación con el adapter real de Claude Code**: documentar en `docs/decisions.md` qué reporta realmente (cuota del plan con hora de reinicio, solo tokens de la sesión, o nada) y cómo se ve un error de límite. El diseño de la sección 10.1 se ajusta a eso.
- ✅ Contra el agente falso: un prompt, una respuesta en streaming y una cancelación limpia. Contra Claude Code real: "hola" recibe respuesta y la verificación de cuota está documentada.

**M2: tool calls, diffs y permisos**
- Render de `tool_call`/`tool_call_update` (los tres tipos de content), tarjeta de diff y `plan`.
- `session/request_permission` con la tarjeta y `PermissionPolicy` con la matriz default.
- `fs/read_text_file` (con buffer del editor) y `fs/write_text_file` con la sincronización de la sección 8.
- ✅ Pedirle a Claude Code que edite un script abierto: el diff se muestra, el permiso se pide en Construir y se auto-deniega en Preguntar, y el editor muestra el cambio sin diálogos ni pérdida de buffer.

**M3: servidor MCP y tools de lectura**
- `McpServer` con token, `initialize`, `tools/list` y `tools/call`.
- Tools de los grupos read y diagnostics, y el fallback del shim stdio.
- ✅ Claude Code lista las tools `godot.*` y responde "¿cuántos nodos tiene Main.tscn?" usando `scene_tree`. Tests del parser HTTP con requests partidos y concatenados.

**M4: tools de edición y ejecución**
- Grupos edit_scene, edit_files y run, con undo en todo.
- `run_scene` con captura de errores, autoload de playtest con el ciclo de vida de la sección 6, `capture_game_frame` e `inputs` simulados.
- ✅ Pedirle "agregá un Label WaveLabel al HUD y conectá la señal X": aparece en el árbol, Ctrl+Z lo deshace en pasos y `run_scene` devuelve errores reales cuando se rompe un script a propósito.
- ✅ Después de un `run_scene`, de un run manual del usuario y de matar el editor a mitad de un playtest y reabrirlo, el autoload no queda en `project.godot` y el test de export del M0 sigue pasando.

**M5: Revisar y Script Editor**
- Modo Revisar, parseo de findings, anotaciones en el `CodeEdit`, tarjetas y lista de hallazgos.
- "Aplicar arreglo" y "Exportar a CLAUDE.md".
- ✅ Revisar una carpeta con 3 bugs sembrados: aparecen anotados en las líneas correctas.

**M6: One-shot**
- Pantalla principal completa, checkpoints git, presupuestos, checks y "Guiar al agente".
- Reglas de cuota de la sección 10.1 completas, con los umbrales de Settings.
- ✅ Con el agente falso simulando la cuota al 90 % y después un error de límite con hora de reinicio: el One-shot pausa al terminar la tarea, crea `cpN-quota`, muestra la cuenta regresiva y retoma solo (o con confirmación) desde la tarea correcta.
- ✅ Con un proyecto vacío de prueba: "Pong de 2 jugadores con puntaje". El loop completa al menos un playtest con captura, crea checkpoints y "Volver acá" restaura correctamente.

**M7: pulido**
- Settings completos, historial de sesiones, Markdown→BBCode robusto y rendimiento con sesiones largas (más de 500 entradas).
- README de uso.

**M8: completado predictivo (sección 16)**

Es independiente de ACP. Se puede adelantar y desarrollar en paralelo desde M0, porque solo comparte settings y log. Se divide en tres etapas, con pausa al final de cada una:

- **M8a: núcleo sin IA.**
  - `CompletionController`, `GhostTextRenderer` de una línea, Tab para aceptar y Esc para descartar.
  - `ProjectContext` (sección 16.4) indexado en segundo plano.
  - Proveedor local con tres fuentes: reglas de contexto, recuperación de líneas e historial de sesión, más el ranker (sección 16.2).
  - ✅ En un script adjunto a un nodo, `@onready var ` sugiere nodos hijos reales con tipo y ruta. `func _` sugiere los virtuales de la clase base con firma. Una línea repetida en el proyecto se sugiere al tipear su comienzo. Tab sin sugerencia sigue indentando y el popup nativo no se rompe. **p95 menor a 10 ms por consulta** en un proyecto de 200 scripts (medido y logueado).
- **M8b: calidad local.**
  - Predicción de la línea siguiente y de bloques cortos por recuperación, ghost text multilínea y aceptación por palabra.
  - Modelo n-gram, adaptación de identificadores, post-procesado completo (sección 16.6) y caché.
  - Set de evaluación (sección 16.9).
  - ✅ El set de evaluación reporta resultados por fuente, y el n-gram mejora la línea base de solo reglas y recuperación.
- **M8c: LLM opcional.**
  - Proveedor Ollama y modo híbrido. Después llama.cpp, Codestral, OpenAI-compatible y Gemini (experimental).
  - Métricas en el log e indicador en el Script Editor.
  - ✅ Cambiar de proveedor y de modo desde Settings sin reiniciar el editor. En modo híbrido, la sugerencia local nunca se demora por el LLM. Las latencias p50 de cada fuente se ven en el log.

---

## 13. Testing (sin dependencias externas)

- **Agente falso en GDScript**: `tests/fake_agent.gd`, que corre con `godot --headless --script`.
  - Lee líneas de stdin con `OS.read_string_from_stdin()` y responde ACP según un guion en JSON (`tests/scripts/*.json`).
  - Emite chunks, tool calls con diff, pedidos de permiso, plan, errores, `usage_update` con cuota simulada y errores de límite con hora de reinicio.
  - Es la base de los tests de M1, M2 y M5, y permite trabajar sin gastar tokens.
- **Tests unitarios**: scripts `@tool` o un runner propio mínimo con `godot --headless --script tests/run_all.gd`, que sale con código 1 si algo falla. Cubren:
  - framing de líneas JSON,
  - correlación de ids,
  - merge de chunks,
  - parser HTTP (requests partidos, concatenados, con `Content-Length` incorrecto),
  - matriz de permisos,
  - Markdown→BBCode,
  - parseo tolerante de findings y checks.
- **Proyecto de prueba**: `tests/sandbox_project/`, separado, para los one-shots. Nunca correr One-shot sobre el proyecto del addon.
- Si las skills recomiendan un framework de test en particular, consultá antes de agregarlo.

---

## 14. Fuera de alcance en v1

- Terminal embebida o PTY (`terminal: true`).
- Múltiples sesiones simultáneas visibles; alcanza con una activa más el historial.
- Edición colaborativa o remota y cualquier red fuera de localhost.
- Merge o push automáticos.
- Soporte para la build mono más allá de "no romperse".

---

## 15. Criterios generales de calidad

- Deshabilitar el plugin libera todo: procesos hijos muertos, threads con `wait_to_finish()`, server cerrado, autoload de debug removido y docks quitados.
- Ninguna acción del agente deja el editor en un estado que el usuario no pueda deshacer o revertir (undo, o checkpoint en One-shot).
- Errores de transporte (el agente se cae, JSON inválido, puerto ocupado) se muestran en la UI con una acción concreta ("Reintentar", "Cambiar puerto", "Ver log"), nunca solo en Output.
- El código pasa la skill `godot-code-review` sin hallazgos de severidad alta antes de cerrar cada milestone.

---

## 16. Completado predictivo (ghost text)

Sugerencias inline mientras se escribe en el Script Editor, al estilo JetBrains o Copilot. Es **un módulo hermano dentro del mismo addon**: comparte Settings, Agent Log y color de acento, pero **no usa ACP ni el agente**.

Hay dos familias de proveedores detrás de la misma interfaz:

- **Local sin IA (default)**: reglas con el contexto de Godot, recuperación de líneas del proyecto, un modelo n-gram e historial de sesión. Es instantáneo, offline y determinista. Completa muy bien lo que ya existe en el proyecto o en el motor, pero no inventa lógica nueva.
- **LLM (opcional)**: modelos FIM locales o remotos, para escribir código nuevo. Se puede usar solo o en modo híbrido.

La prioridad es la **latencia percibida**:
- Local: la sugerencia aparece en menos de ~30 ms desde la última tecla.
- LLM: aparece en menos de ~400 ms desde que el usuario deja de tipear, o no aparece.

### 16.1 Arquitectura

```
CodeEdit (Script Editor)
  ├─ CompletionController ── escucha cambios y caret, debounce, cancelación, aceptación
  │     ├─ ProjectContext ── índice del proyecto (16.4), compartido por todos los proveedores
  │     ├─ CompletionProvider (interfaz)
  │     │     ├─ LocalProvider ── ContextRules · LineRetrieval · NGramModel · SessionHistory → Ranker
  │     │     └─ LlmProvider ──── Ollama · llama.cpp · Codestral · OpenAI-compatible · Gemini (exp.)
  │     ├─ PostProcessor ── recorte, indentación, solapamiento con el suffix
  │     └─ SuggestionCache ── LRU por hash de prefix
  └─ GhostTextRenderer ── dibuja la sugerencia sobre el CodeEdit
```

- Un `CompletionController` por cada `CodeEdit` abierto. Se engancha y desengancha con `ScriptEditor.editor_script_changed` y al abrir y cerrar scripts.
- `CompletionProvider` es una interfaz chica:
  - `func complete(req: CompletionRequest) -> CompletionResult` (con `await`; el local resuelve en el mismo frame)
  - `func cancel() -> void`
  - `func describe() -> Dictionary` (nombre, local o remoto, usa IA o no)
- Cada `CompletionResult` lleva `text`, `score` y `source` (`rule`, `retrieval`, `ngram`, `history` o `llm`), para el ranking, el log y la evaluación.
- **Modos** (en Settings):
  - **Solo local** (default).
  - **Híbrido**: el local responde al instante. Si no hay candidato local por encima del umbral, se pide al LLM con su debounce. La respuesta del LLM solo se muestra si el usuario no tipeó nada desde el pedido y nunca reemplaza una sugerencia local que ya esté visible.
  - **Solo LLM**.

### 16.2 Proveedor local (sin IA)

Combina cuatro fuentes. Cada una devuelve candidatos (resto de la línea, o de un bloque corto) con un puntaje normalizado entre 0 y 1.

**a) ContextRules: reglas deterministas sobre `ProjectContext`.** Cuando una regla aplica, tiene prioridad alta. Reglas iniciales:

| Disparador | Sugerencia |
|---|---|
| `@onready var ` | `<nombre>: <Tipo> = $<Ruta>` para cada nodo hijo de las escenas donde está adjunto el script que todavía no esté declarado. El nombre es la versión snake_case del nodo. |
| `$` o `%` | Rutas de nodos válidas, con nodos `%` únicos primero. |
| Dentro de `Input.is_action_*("`, `Input.get_axis("` o `InputMap.` | Acciones del input map. |
| `func _` | Virtuales de la clase base con su firma tipada, sacada de `ClassDB` (por ejemplo `_physics_process(delta: float) -> void:`). Se excluyen los que ya están definidos. |
| `<señal>.connect(` | `_on_<señal>)` o `_on_<emisor>_<señal>)` según la convención detectada en el proyecto. |
| `func _on_` | Handlers de señales conectadas que todavía no tienen función, con los parámetros de la señal. |
| `add_to_group("`, `is_in_group("`, `get_nodes_in_group("` | Grupos usados en el proyecto. |
| `preload("` o `load("` | Rutas `res://`, filtradas por el tipo esperado cuando se puede inferir del lado izquierdo. |
| `extends ` | Clases del motor y `class_name` del proyecto. |

**b) LineRetrieval: recuperación desde el código del proyecto.**
- Índice de todas las líneas de los `.gd` del proyecto, sin indentación y con los espacios normalizados.
- Consulta: lo escrito en la línea actual (mínimo 3 caracteres). Candidatos: el resto de las líneas que empiezan igual.
- **Predicción de la línea siguiente**: si la línea actual está vacía y la anterior coincide con alguna del índice, sugerir la línea que la sigue en el corpus. Por ejemplo, después de `func _ready() -> void:`, la primera línea más común del proyecto.
- **Bloques cortos** (M8b): mismo mecanismo, hasta N líneas mientras el corpus siga coincidiendo y la indentación se mantenga dentro del bloque.
- **Puntaje**: frecuencia × cercanía (mismo archivo 3, misma carpeta 2, resto 1) × recencia de modificación del archivo fuente.
- **Adaptación de identificadores** (M8b): si lo escrito difiere de una línea del corpus en un solo identificador (`mana.chan…` contra `health.changed.connect(_on_health_changed)`), aplicar la misma sustitución al resto: `mana.changed.connect(_on_mana_changed)`.

**c) NGramModel: modelo estadístico de tokens.**
- Lexer GDScript simple: identificadores, keywords, operadores, strings, números y tokens de salto de línea, indent y dedent.
- 4-gramas con *stupid backoff*. Generación greedy hasta el fin de línea o hasta que la confianza baje del umbral.
- **Corpus**: el proyecto actual más carpetas extra configurables (otros proyectos propios). El addon no incluye ningún corpus de terceros.
- Se entrena en segundo plano con `WorkerThreadPool` y se actualiza por archivo en `filesystem_changed`.

**d) SessionHistory.** Líneas escritas y aceptadas en la sesión actual. Es la fuente con más peso por recencia, estilo fish shell.

**Ranker.**
- Une los candidatos, elimina duplicados y descarta los que contradicen el suffix.
- Solo muestra una sugerencia si el mejor puntaje supera el umbral y le saca un margen mínimo al segundo. Ante una duda, no mostrar nada.
- Ante un empate, prefiere el candidato más largo que siga siendo coherente con el bloque.
- **Presupuesto**: menos de 5 ms por consulta en el hilo principal. La indexación nunca corre en el hilo principal.

**Persistencia del índice**: opcional, en `user://godot_agent/completion_index/<hash del proyecto>`. Si reconstruirlo tarda menos de 1 s en un proyecto mediano, no hace falta persistirlo; documentá la medición.

### 16.3 Proveedores LLM (opcionales)

Verificá cada endpoint y formato contra su documentación actual antes de implementarlo, y registrá lo verificado en `docs/decisions.md`.

| Proveedor | Tipo | Endpoint (a verificar) | Notas |
|---|---|---|---|
| **Ollama** | local, FIM | `POST /api/generate` con `prompt` (prefix) + `suffix`, `raw: false`, `stream: false`, `options {num_predict, temperature, stop}` | Modelo sugerido: `qwen2.5-coder:1.5b` (rápido) o `:7b` (mejor). Comprobar que el modelo soporta FIM. Es el primer proveedor LLM a implementar. |
| **llama.cpp server** | local, FIM | `POST /infill` con `input_prefix`, `input_suffix` y `input_extra` (contexto de otros archivos) | Soporta contexto multi-archivo nativo, ideal para 16.4. |
| **Codestral (Mistral)** | remoto, FIM | `POST /v1/fim/completions` con `prompt` + `suffix` | Necesita API key. |
| **OpenAI-compatible** | local o remoto | `POST /v1/completions` con `prompt` y, si el server lo soporta, `suffix` | Para LM Studio, vLLM y similares. Si no hay `suffix`, usar los tokens FIM del modelo en crudo (plantilla configurable). |
| **Gemini** | remoto, sin FIM nativo | API de generación de contenido con un prompt instructivo ("completá en `<CURSOR>`, devolvé solo el código insertado") | **Experimental.** Más lento y menos preciso que un modelo FIM. Mostrarlo así en Settings. |

- Requests con `HTTPRequest` (un nodo por controller, reutilizado). `cancel_request()` al invalidar.
- **Plantillas FIM configurables por perfil** para modelos en crudo. Ejemplo Qwen2.5-Coder: `<|fim_prefix|>{prefix}<|fim_suffix|>{suffix}<|fim_middle|>`, con stop tokens correspondientes.
- **API keys**: nunca en el proyecto ni en `EditorSettings`. Se guarda el **nombre** de la variable de entorno (por ejemplo `MISTRAL_API_KEY`) y se lee con `OS.get_environment`.
- Un perfil remoto muestra en Settings un aviso explícito de que se envía código del proyecto a ese servicio.

### 16.4 ProjectContext

Es lo que diferencia este completado de uno genérico. Las reglas locales lo usan directamente y, si hay LLM, también va en el prompt. Se calcula en segundo plano, se cachea y se invalida por archivo en `EditorFileSystem.filesystem_changed` y `resources_reimported`.

Contenido:
- `extends` y `class_name` del script actual, y la **API resumida de la clase base del motor**: métodos virtuales con firma, señales y propiedades principales, obtenidos de `ClassDB`.
- **Firmas de las clases del proyecto** (`class_name` globales): funciones públicas, señales, `@export` y constantes. Se extraen parseando los scripts por líneas, sin cuerpos.
- Si el script está adjunto a nodos en escenas: **rutas de nodos hijos** válidas para `$Ruta` y `%Unico`, con su tipo. Se obtienen parseando los `.tscn` que referencian el script, o de la escena abierta si está cargada.
- **Autoloads** con sus firmas.
- **Acciones del input map**.
- **Grupos** usados en el proyecto, tanto en escenas como en código.
- **Señales conectadas** en escenas y en código, con sus handlers, para las reglas `func _on_`.

Para el LLM, el contexto local es:
- **Prefix**: hasta N caracteres antes del caret (default 6000), cortando en un límite de línea.
- **Suffix**: hasta M caracteres después (default 1500).

Formato de envío al LLM:
- llama.cpp: `input_extra` con un "archivo" virtual por bloque.
- Modelos con tokens repo-level: separadores de archivo del modelo.
- Resto: comentario de cabecera `# context: ...` antepuesto al prefix.

Presupuesto total de contexto para el LLM configurable (default ~2000 tokens estimados) con prioridad:
1. rutas de nodos del script actual,
2. clase base,
3. clases del proyecto referenciadas en el archivo,
4. autoloads,
5. input map,
6. resto.

### 16.5 Disparo, debounce y cancelación

- **Debounce**: local 30 ms (configurable entre 0 y 200), LLM 200 ms (configurable entre 75 y 1000).
- Se dispara cuando se cumplen todas estas condiciones:
  - el caret está al final de la línea, o solo hay espacios o cierres (`)`, `]`, `}`, `"`) a la derecha,
  - no hay selección activa,
  - el popup de autocompletado nativo **no** está abierto (`get_code_completion_selected_index() == -1` o el equivalente; verificar la API),
  - el archivo es GDScript (`.gd`); los shaders quedan fuera de v1.
- Se **invalida** (cancela la request en vuelo y oculta el ghost text) cuando:
  - se mueve el caret a otra línea,
  - se escribe algo que no coincide con el comienzo de la sugerencia,
  - se pulsa Esc o se pierde el foco.
- **Type-through**: si el usuario tipea exactamente los primeros caracteres de la sugerencia visible, se consume ese prefijo de la sugerencia sin pedir otra.
- Como máximo **una request LLM en vuelo por editor**, y respuestas viejas descartadas por número de secuencia.
- **Atajo para pedir sugerencia manualmente** (default Alt+\\), ignorando el debounce y la condición de fin de línea. En modo híbrido, este atajo fuerza el LLM.

### 16.6 Post-procesado

Se aplica a todas las fuentes, en este orden:

1. Quitar los tokens FIM residuales y el texto después de cualquier stop (solo LLM).
2. **Recortar al bloque**: cortar cuando una línea nueva queda con indentación menor que la línea del caret (el bloque terminó) o al llegar a un máximo de líneas (default 8).
3. **Solapamiento con el suffix**: si el final de la sugerencia repite el comienzo del suffix (por ejemplo `)` o `:`), quitar la parte repetida.
4. **Indentación**: normalizar a la configuración del editor (tabs o espacios y su tamaño).
5. **Descartar** sugerencias vacías, solo de espacios, o idénticas a la línea siguiente existente.
6. Opcional (activado por defecto): descartar si la sugerencia de una línea no compila como fragmento obvio, por ejemplo paréntesis desbalanceados en una línea que debería cerrarse sola.

### 16.7 Render y aceptación

- **Ghost text**: texto en color atenuado (color de comentario del theme con alpha), dibujado sobre el `CodeEdit`.
  - Conectarse a la señal `draw` del `CodeEdit` y usar `draw_string` en la posición que da `get_rect_at_line_column` (o equivalentes; verificá la API en 4.4 y 4.8).
  - Respetar la fuente y el tamaño del editor, el scroll horizontal y vertical, el wrap de líneas y el zoom.
  - Las sugerencias del LLM se distinguen de las locales con un matiz sutil (un pequeño marcador al final o un tono apenas distinto), configurable.
- **Multilínea**: Godot no permite insertar líneas virtuales. La primera línea va inline a la derecha del caret; las siguientes en una caja translúcida anclada debajo de la línea actual, que tapa visualmente el código siguiente sin modificarlo. Si eso queda mal en la práctica, alternativa: mostrar solo la primera línea más un indicador `+N` y documentar la decisión.
- **Teclas**:
  - **Tab**: acepta todo.
  - **Ctrl+→**: acepta la siguiente palabra.
  - **Esc**: descarta.
  - Interceptar las teclas **solo cuando hay sugerencia visible y el popup nativo está cerrado**; en cualquier otro caso Tab mantiene su comportamiento normal.
  - Primero intentar con la señal `gui_input` del `CodeEdit` y `accept_event()`. Si el `CodeEdit` igual procesa la tecla, fallback: `_input` en el `EditorPlugin`, verificando que el foco esté en ese `CodeEdit`, y marcar el input como manejado. Documentar qué funcionó.
- Aceptar inserta el texto en **una sola acción de undo** del editor de texto (`begin_complex_operation` / `end_complex_operation`). Lo aceptado alimenta `SessionHistory`.
- **Indicador en la barra del Script Editor**: estado del completado (activo, pensando, error o apagado) y modo (local, híbrido o LLM con su modelo). Un clic lo activa o desactiva. Atajo global de on/off.

### 16.8 Métricas y log

- Canal `cmp` en el Agent Log con: fuente, latencia, tamaño de entrada y salida, resultado (`shown`, `discarded:<motivo>`, `accepted`, `accepted_partial`, `cancelled`) y caché hit/miss.
- Contadores visibles en Settings, **por fuente**: latencia p50 y p95, tasa de aceptación y sugerencias mostradas en la sesión. Así se ve qué aporta cada fuente y si el LLM se justifica.
- **Nunca se loguea el contenido del código** salvo con el modo "raw" activado explícitamente.

### 16.9 Calidad y pruebas

- **Tests unitarios**: cada regla de `ContextRules`, LineRetrieval (prefijos, cercanía, adaptación de identificadores), lexer y n-gram, ranker (umbral y margen), post-procesador (con casos reales de salidas defectuosas), detección de solapamiento, type-through, plantillas FIM y debounce con reloj simulado.
- **Proyecto fixture**: `tests/completion_fixture/` con escenas y scripts chicos (nodos hijos, `%` únicos, input map, autoloads, señales) para probar las reglas sin depender del proyecto real.
- **Proveedor falso** (`tests/fake_completion_provider.gd`) con latencia y respuestas configurables, para probar la UI y el modo híbrido sin modelo.
- **Set de evaluación**: `tests/completion_eval/` con 30–50 recortes de GDScript reales (cortados en un punto, con la continuación esperada) y un script headless que corre cualquier combinación de fuentes o proveedores sobre el set.
  - Reporta exact match de la primera línea, similitud por tokens, cobertura (en qué porcentaje de casos se mostró algo), **tasa de falsos positivos** (sugerencias mostradas e incorrectas) y latencia.
  - Sirve para ajustar umbrales y pesos del ranker, y para comparar local contra LLM con números en vez de impresiones.
  - Para el completado local, una sugerencia incorrecta molesta más que ninguna: optimizar primero la precisión y después la cobertura.

### 16.10 Settings del completado

- On/off global y por proyecto. **Modo**: solo local (default), híbrido o solo LLM.
- **Local**: fuentes activas (reglas, recuperación, n-gram, historial), umbral y margen del ranker, carpetas de corpus extra, máximo de líneas por bloque, debounce local.
- **LLM**: perfil activo y perfiles (CRUD): tipo, URL, modelo, nombre de la variable de entorno de la key, plantilla FIM, stop tokens, temperatura (default 0.1–0.2) y máximo de tokens de salida (default 64–128). Debounce LLM, tamaño de prefix y suffix, presupuesto de contexto.
- Aceptación multilínea on/off.
- Exclusiones por ruta (por ejemplo `addons/`), además de lo que esté en `.gitignore` si es fácil de leer.
