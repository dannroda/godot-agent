# Progreso

El tablero de tareas vive en `compass/` (Scope Compass; ver `compass/AGENTS.md`). Acá queda el resumen por milestone: qué quedó, cómo probarlo y qué falta.

Binarios usados:
- 4.8-beta1 (desarrollo): `/opt/godot/versions/4.8-beta1/godot`
- 4.7.2: `godot` en el PATH
- 4.4.1 (mínimo): bajado solo para verificar

---

## M0 · Esqueleto y decisiones — listo para revisión (2026-10-21)

### Qué quedó

- `docs/decisions.md` con D1–D10: estructura, sin `class_name` (preload), raíz de composición, API verificada en 4.4.1/4.7.2/4.8-beta1, settings por proyecto, presets, test de ciclo, rastros aceptados en el export, docks/main screen en 4.8 y orden de export plugins.
- `addons/godot_agent/`:
  - `plugin.gd`: agrega y quita el dock **Agent**, el panel inferior **Agent Log** y la main screen **Agent** (por ahora vacíos).
  - `ui/editor_surfaces.gd`: usa `EditorDock` + `add_dock` donde existe (dock y panel en 4.7+, main screen en 4.8+) y la API vieja en 4.4–4.6. Evita dos problemas de 4.8-beta1: el `EditorDock` huérfano que deja `_has_main_screen` y el error de `grab_focus` al cerrar el editor con la main screen activa.
  - `export/agent_export_plugin.gd`: `skip()` de todo `res://addons/godot_agent/`. Se llama `!GodotAgentExcludeAddon` para correr antes que el plugin de GDScript (D10). En `_export_begin` quita el autoload de playtest huérfano con error claro y avisa si algún preset no tiene el filtro.
  - `export/export_presets_patcher.gd` + botón **Agregar a los presets** en el dock (con confirmación).
  - `playtest/playtest_autoload.gd` (alta/baja/limpieza) y `playtest/runtime/playtest_probe.gd` (solo el guard por ahora).
- `addons/godot_agent_dev/`: plugin solo de desarrollo (ciclo de habilitado y captura de pantalla).
- Tests:
  - `tests/run_all.gd`: runner mínimo de tests unitarios (`tests/unit/test_*.gd`), sale con 1 si algo falla.
  - `tests/plugin_cycle_check.gd`: 5 ciclos de habilitar/deshabilitar en un editor headless; falla con huérfanos o con errores en la salida.
  - `tests/export_check.gd`: 4 escenarios exportados con `--export-pack` e inspeccionados con `ZIPReader`.

### Verificación automática

```sh
G=/opt/godot/versions/4.8-beta1/godot   # o 4.7.2 / 4.4.1
$G --headless --path . --import
$G --headless --path . --script tests/run_all.gd
$G --headless --path . --script tests/plugin_cycle_check.gd
$G --headless --path . --script tests/export_check.gd
```

Resultado al cerrar M0, en 4.8-beta1, 4.7.2 y 4.4.1:

| Test | Resultado |
|---|---|
| `run_all.gd` | 5 tests, 17 checks, 0 fallos |
| `plugin_cycle_check.gd` | PASS: 5 ciclos, sin huérfanos nuevos ni errores |
| `export_check.gd` | PASS en los 4 escenarios: plugin on sin filtro, plugin off con filtro, plugin on con autoload huérfano y el control (plugin off sin filtro, que **tiene** que detectar el addon) |

Avisos que el test de export reporta pero acepta (D8): `uid_cache.bin` conserva rutas del addon y `project.binary` conserva `editor_plugins/enabled`.

### Prueba manual

1. Abrir el proyecto con 4.8-beta1: `/opt/godot/versions/4.8-beta1/godot -e --path .`
2. Ver arriba la pestaña **Agent** junto a 2D/3D/Script/Game/Asset Store: muestra "One-shot: todavía no hay una tarea en curso."
3. Ver el panel inferior **Agent Log** y el dock **Agent** a la derecha, como pestaña junto al Inspector. Con la columna angosta puede quedar detrás de las flechitas de scroll de las pestañas.
4. Project → Project Settings → Plugins: deshabilitar y habilitar *Godot Agent Harness* varias veces. No tiene que aparecer nada en Output y los tres paneles tienen que irse y volver.
5. Crear un preset de export (Project → Export → Add…, cualquier plataforma) y cerrar el diálogo. El dock **Agent** muestra el aviso "Los presets de export … no excluyen 'addons/godot_agent/*'". Tocar **Agregar a los presets**, confirmar y reiniciar el editor. En el diálogo de Export, pestaña Resources, el filtro de exclusión tiene que incluir `addons/godot_agent/*`.
6. Repetir 1–4 con 4.4.1 (la main screen usa la API vieja; el dock aparece como pestaña "Agent" al lado de Inspector y Nodo).

Captura de referencia (4.8-beta1, main screen Agent activa): se genera con
`$G -e --path . -- --godot-agent-screenshot=/ruta/captura.png`.

### Pendiente / a decidir

- **Mockup de UI**: copiado en `docs/design/mockup/` y resumido por pantalla en `docs/design/README.md`, con las diferencias con la spec.
- ~~Todavía no se puede iniciar una sesión~~: resuelto en M1.
- Reportar a Godot los dos problemas de 4.8-beta1 que el addon esquiva (tarea en M7).
- `project.godot` del anfitrión quedó con `config/features=("4.4")` porque lo abrió el 4.4.1. Sirve para marcar el mínimo; el 4.8 lo actualiza si se guarda desde ahí.

---

## M1 · Transporte y ACP mínimo — listo para revisión (2026-10-21)

### Qué quedó

- **Transporte** (`transport/`):
  - `agent_process.gd`: `execute_with_pipe` + threads para stdout, stderr y salida;
  - `process_tree.gd`: mata el árbol de procesos (npx → node);
  - `command_resolver.gd`: encuentra `npx` aunque el editor se haya abierto desde el escritorio (fnm, nvm, volta…).
  - En 4.4 los pipes viejos no se cierran por un bug del motor (D11).
- **ACP** (`acp/acp_client.gd`):
  - JSON-RPC 2.0 por líneas, con `request()` usable con `await`;
  - handlers para requests y notificaciones entrantes;
  - `-32601` para lo desconocido;
  - las líneas que no son JSON se loguean y se ignoran.
- **Sesión** (`session/`):
  - `session_model.gd` (estado y señales): merge de chunks por `messageId`, thoughts, tool calls agrupados, plan, uso, modos, opciones y comandos;
  - `session_controller.gd` (comandos, D12): `initialize` → `session/new` → `session/prompt` → `session/cancel`, `set_config_option` y `set_mode`. Si el agente se cae, muestra un aviso con **Reintentar** y **Ver log**.
- **Perfiles** (`core/agent_profile.gd`, `core/harness_settings.gd`):
  - se guardan en EditorSettings `godot_agent/`;
  - perfil por defecto: Claude Code con `npx -y @agentclientprotocol/claude-agent-acp` (D13);
  - si hay `ANTHROPIC_API_KEY` en el entorno, se muestra un aviso;
  - mientras no llega el diálogo de Settings (M7), los perfiles se editan como JSON desde el botón de ajustes del dock.
- **Dock Agent**, según el mockup:
  - header con perfil, título de sesión, historial (deshabilitado hasta M7), nueva sesión y ajustes;
  - selector de 4 modos y línea de estado;
  - conversación: burbuja del usuario, Markdown del agente, pensamiento colapsado, grupos de tool calls con tarjeta de diff, plan y avisos con acciones;
  - composer:
    - chips de escena, selección y captura;
    - `/` autocompleta los comandos del agente y `@` los nodos y archivos;
    - medidor de contexto y selector de modelo;
    - Enviar/Detener, con **Ctrl+Enter** para enviar y **Esc** para cancelar.
- **Agent Log**: `hora · canal · mensaje` en mono, filtros por canal, modo raw con el JSON-RPC completo, Copiar y Limpiar. Guarda las últimas 2000 entradas.
- **Prompt de sistema** editable en `config/system_prompt.md` (D14).

### Verificación automática

```sh
$G --headless --path . --script tests/run_all.gd            # 23 tests, 134 checks
$G --headless --path . --script tests/acp_session_check.gd  # agente falso: streaming, cancel, caída (32 checks)
$G --headless --path . --script tests/plugin_cycle_check.gd
$G --headless --path . --script tests/export_check.gd
$G -e --path . -- --godot-agent-ui-test=ui_demo --godot-agent-ui-shot=/ruta/ui.png   # dock contra el agente falso, con captura
$G --headless --path . --script tests/claude_smoke_check.gd  # Claude Code real (gasta tokens)
```

Todo pasa en 4.4.1, 4.7.2 y 4.8-beta1. Contra Claude Code real, "hola" recibió: "¡Hola! Estoy dentro del editor de Godot, en el proyecto **agent-harness**, en modo Construir. ¿Qué querés hacer?" (`stopReason: end_turn`). No queda ningún proceso del adapter vivo después de `stop()`.

### Prueba manual

1. Abrir el editor: `$G -e --path .`. En el dock **Agent** (pestaña junto a Inspector) aparece "Sin sesión", con el comando del perfil y el botón **Iniciar sesión**.
2. Tocar **Iniciar sesión**. La línea de estado pasa a "conectando…" y después a "● Claude Code · listo". La primera vez, npx puede tardar en bajar el adapter.
3. Escribir "hola" y mandar con Ctrl+Enter. La respuesta llega en streaming y el medidor muestra el contexto usado.
4. Pedir algo largo ("explicame este proyecto en detalle") y tocar **Detener** o Esc. Aparece "Turno cancelado." y se puede seguir conversando.
5. En **Agent Log**, probar los filtros de canal, el modo raw y Copiar.
6. Probar `/` (comandos del agente) y `@` (nodos y archivos) en el composer, y el selector de modelo.
7. Matar el proceso del adapter desde una terminal (`pkill -f claude-agent-acp`). Aparece un aviso de error con **Reintentar** y **Ver log**.

### Pendiente

- ~~Permisos, `fs/*` y la sincronización con el editor~~: hechos en M2.
- Historial de sesiones y Settings completos: M7.

## M2 · Permisos, fs/* y sincronización con el editor

### Qué hay

- **Permisos** (`session/permission_policy.gd`):
  - matriz modo × grupo (read, diagnostics, edit_scene, edit_files, run, shell, project; los kinds desconocidos van a "other", que siempre pregunta) con los defaults de la spec §7;
  - overrides por proyecto en `config/project_config.gd` (Resource, D5).
- **Pedidos de permiso**:
  - `session/request_permission` consulta la política. allow y deny se responden solos (deny deja un aviso en el chat); ask muestra una tarjeta con las opciones del agente y el diff;
  - "Siempre en esta sesión" queda en memoria y al agente se le responde allow_once;
  - un permiso de edición concedido preautoriza el `fs/write_text_file` que le sigue al mismo archivo, así no hay doble tarjeta;
  - todo queda en el canal `perm` del log.
- **fs/\*** (`acp/fs_handler.gd`):
  - leer devuelve el buffer del Script Editor si tiene cambios sin guardar, con soporte de line y limit;
  - escribir pasa por la política;
  - se rechazan rutas fuera del proyecto (salvo `extra_fs_roots`) y escrituras en `.godot/` o `.git/`.
- **Sincronización con el editor** (`editor/editor_sync.gd`, D15):
  - scripts abiertos: se recargan sin diálogo, con un paso de undo y sin mover el cursor;
  - conflicto si el usuario tenía cambios: ver diff, usar la del agente o mantener la mía;
  - aviso con "Recargar escena" para escenas abiertas;
  - aviso para `.uid` e `.import`.
- **Dock**:
  - tool calls con salida de texto plegada, miniaturas de imagen y recursos;
  - tarjetas de permiso;
  - "+ contexto" para agregar el script actual, archivos del proyecto o una captura.

### Verificación automática

```sh
$G --headless --path . --script tests/run_all.gd            # 35 tests, 229 checks
$G --headless --path . --script tests/acp_session_check.gd  # 53 checks (incluye permisos en Construir y Preguntar)
$G -e --path . -- --godot-agent-sync-test                   # editor: watcher, conflicto, fs/write, undo, sin diálogos
$G -e --path . -- --godot-agent-ui-test=ui_demo             # dock + "+ contexto"
$G -e --path . -- --godot-agent-claude-edit-test            # Claude Code real (gasta tokens)
```

Todo pasa en 4.4.1, 4.7.2 y 4.8-beta1. La prueba de ciclo del plugin puede dar un falso positivo de crecimiento de objetos si corre con el editor todavía escaneando (por ejemplo, justo después de `export_check`); repetida, crece entre 3 y 5 objetos.

Con Claude Code real (`--godot-agent-claude-edit-test`, en 4.8 y 4.4.1):
- **Construir**: pidió permiso para `Edit tests/tmp/claude_target.gd`, con diff. Se aceptó, el archivo y el buffer abierto pasaron a `var speed := 2`, el buffer quedó sin cambios pendientes y no apareció ningún diálogo al volver el foco.
- **Preguntar**: Claude no intentó editar ("la sesión está en modo Preguntar (y en modo plan)…") y el archivo no cambió. El auto-deny de un pedido real en Preguntar lo cubre `acp_session_check` con el agente falso.

### Prueba manual

1. Abrir un script en el Script Editor e iniciar sesión en modo **Construir**.
2. Pedir "cambiá X por Y en <script>". Aparece una tarjeta de permiso con el diff. Al tocar **Permitir una vez**, el script abierto se actualiza en el lugar, el cursor no salta y un Ctrl+Z deshace el cambio.
3. Escribir algo en el script sin guardar y pedir otra edición. Aparece un aviso de conflicto con **Ver diff**, **Usar la del agente** y **Mantener la mía**.
4. Pasar a **Preguntar** y pedir una edición. No hay tarjeta: el pedido se deniega solo (con aviso) o el agente directamente no lo intenta.
5. **+ contexto** → Archivo del proyecto… → elegir un archivo. Aparece como chip y viaja como link en el próximo mensaje.

### Pendiente

- La política ya está lista para las tools `godot.*` (M3) con `SessionController.authorize`.
- El undo de tool calls (botón oculto) llega con M4.

## M3 · Server MCP y tools de lectura

### Qué hay

- **Server MCP** (`mcp/mcp_server.gd`, D16):
  - HTTP/1.1 en 127.0.0.1 con token Bearer y `POST /mcp` (Streamable HTTP sin SSE), sesiones con `Mcp-Session-Id`;
  - 401, 403, 404, 405 y 202 según la spec;
  - el puerto se configura en EditorSettings `godot_agent/mcp/port` (0 = aleatorio) y la URL queda en el canal `mcp` del Agent Log.
- **Registro de tools** (`mcp/tool_registry.gd`):
  - valida argumentos y aplica la política de permisos del modo actual (ask con `permission_timeout_s`);
  - recorta la salida a `max_output_chars` y las imágenes a `max_image_side`;
  - loguea nombre, argumentos, duración y resumen.
- **Tools** (8):
  - `project_info`, `list_files`, `scene_tree`, `get_node`, `editor_state` (read);
  - `get_errors`, `validate_scripts`, `capture_editor_viewport` (diagnostics, D18).
- **session/new** pasa el server como entrada http si el agente lo soporta y, si no, el shim stdio (D17).
- El prompt de sistema pide verificar con `validate_scripts` y `get_errors` después de editar scripts.

### Verificación automática

```sh
$G --headless --path . --script tests/run_all.gd     # 52 tests, 317 checks (parser HTTP, server por HTTP real, registro, diagnóstico)
$G -e --path . -- --godot-agent-mcp-test             # cada tool por HTTP contra tests/fixtures/main_fixture.tscn + shim stdio
$G -e --path . -- --godot-agent-claude-mcp-test      # Claude Code real (gasta tokens)
```

Todo pasa en 4.4.1, 4.7.2 y 4.8-beta1, junto con las suites anteriores: `acp_session_check`, `export_check`, cycle, sync y ui.

La prueba de ciclo ahora espera a que termine el escaneo del editor y toma la línea base después del primer ciclo: el editor crea nodos sueltos propios al restaurar pestañas. También falla si queda huérfano un nodo con un script del addon (4.5+).

Con Claude Code real (`--godot-agent-claude-mcp-test`, 4.8): el adapter anunció MCP por HTTP y Claude Code 2.1.303 hizo initialize con MCP 2025-06-18. A "¿Cuántos nodos tiene la escena res://tests/fixtures/main_fixture.tscn?" respondió con `mcp__godot__scene_tree`: "tiene **5 nodos**: Main (Node2D), Player (CharacterBody2D)… Sprite… Enemies… Timer…".

### Prueba manual

1. Abrir el editor e iniciar sesión. En **Agent Log**, canal `mcp`, aparece "server MCP escuchando en http://127.0.0.1:<puerto>/mcp" y, al conectarse Claude, "initialize de claude-code …".
2. Abrir una escena y preguntar "¿qué nodos tiene la escena abierta?". El agente usa `godot.scene_tree` (en violeta en el dock) y responde con el árbol.
3. Seleccionar un nodo y preguntar "¿qué tengo seleccionado?" (`godot.editor_state`).
4. Romper un script y pedir "validá los scripts". `godot.validate_scripts` devuelve el archivo y la línea.

### Pendiente

- Tools de edición de escena (con undo) y checkpoints: M4.
