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

### Cuota del plan (agregado al spec después de M1)

- `core/quota_monitor.gd` observa la cuota: loguea en el canal nuevo `quota` del Agent Log cada `usage_update`, el texto del agente que coincide con `config/quota_patterns.txt` y cada error de `session/prompt`.
- Qué reporta Claude Code: D22. Hay ventana de 5 horas y semanal, con utilización y hora de reinicio, en `_meta["_claude/rateLimit"]`.
- Prueba: `tests/unit/test_quota_monitor.gd`. Contra Claude Code real, `$G --headless --path . --script tests/claude_smoke_check.gd` imprime las líneas `[quota]`.
- Estados, medidor, pausa y reanudación: M6 (m6-06 a m6-08).

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

- Tools de edición de escena (con undo): M4. Checkpoints: M6.

## M4 · Tools de edición y ejecución

### Qué hay

- **Edición de escenas** (`mcp/tools/scene_edit_tools.gd`, D19):
  - `add_node`, `set_properties`, `remove_node`, `reparent_node`, `rename_node`, `connect_signal` (persistente), `instantiate_scene`, `open_scene`, `save_scene` (grupo edit_scene);
  - `create_scene` y `attach_script` (grupo edit_files);
  - una acción de undo `Agente: …` por tool call; los valores JSON se convierten con `value_coercion.gd`.
- **"↶ undo" en el dock**: los tool calls `godot.*` de edición muestran el botón. Deshace con la opción Undo del editor si la acción sigue siendo la última; si no, avisa por qué no.
- **Ejecución** (`mcp/tools/run_tools.gd`, grupo run):
  - `run_scene` corre la escena, reproduce `inputs` y espera `seconds` o a que el juego termine. Devuelve los errores (con la marca de `get_errors`) y el Output del juego. Si el juego se pausa en el debugger por un error, trae el motivo y la ubicación.
  - `capture_game_frame` devuelve el frame del juego.
  - `stop_scene` cierra el juego.
- **Autoload de playtest** con el ciclo de vida de D20: existe solo mientras arranca un juego lanzado por `run_scene`.

### Verificación automática

```sh
$G --headless --path . --script tests/run_all.gd                 # 58 tests, 353 checks (+ coerción de valores, run_tools)
$G -e --path . -- --godot-agent-edit-test                        # cada tool de edición, Ctrl+Z en pasos, permisos por modo, "↶ undo"
tests/run_in_xvfb.sh $G --godot-agent-run-test                   # run_scene/inputs/captura/stop, script roto, autoload fuera de project.godot
setsid -w tests/crash_check.sh $G                                # editor matado con el autoload registrado y con un run en curso + export_check
XRUN_TIMEOUT=480 tests/run_in_xvfb.sh $G --godot-agent-claude-scene-test   # Claude Code real (gasta tokens)
```

Todo pasa en 4.4.1, 4.7.2 y 4.8-beta1, junto con las suites anteriores (`acp_session_check`, `export_check`, cycle, sync, ui y mcp), ahora corridas en Xvfb (D21).

Con Claude Code real (4.8 y 4.4.1), a "agregá un Label llamado WaveLabel como hijo de HUD… y conectá la señal timeout de WaveTimer al método _on_wave_timer_timeout de WaveLabel" usó `editor_state`, `scene_tree`, `add_node`, `connect_signal`, `get_node` y `get_errors`. El primer Ctrl+Z deshizo solo la conexión y el siguiente sacó el Label; el `.tscn` en disco no se tocó.

### Prueba manual

1. Abrir una escena con un nodo HUD, iniciar sesión en Construir y pedir "agregá un Label WaveLabel al HUD y conectá la señal timeout del Timer". Aparece una tarjeta de permiso por cada tool `godot.add_node` / `godot.connect_signal`; al aceptar, el nodo aparece en el árbol.
2. Ctrl+Z en el editor deshace primero la conexión y después el nodo. Con el botón "↶ undo" del tool call pasa lo mismo, siempre que no haya cambios posteriores.
3. Romper un script de la escena (por ejemplo, llamar a un método sobre `null` en `_ready`) y pedir "corré la escena 3 segundos". `godot.run_scene` devuelve el error con archivo y línea, y el juego queda pausado en el debugger.
4. Pedir "capturá el juego" con una escena sana corriendo: `godot.capture_game_frame` muestra la imagen en el dock.
5. Después de cada run, `project.godot` no tiene `GodotAgentPlaytest` (`git diff project.godot`).

### Pendiente

- Repro mínimo del error de 4.7.2 con variables en el probe (D20), para m7-01.
- Cuota del plan (spec §10.1): observación en M1 (D22); estados y reglas en m6-06 a m6-08.

## M5 · Modo Revisar

### Qué hay

- **Parser tolerante** (`review/findings_parser.gd`): bloques `findings` y `checks` del texto del agente (D23).
- **Revisión vigente** (`review/review_store.gd`), que se llena al terminar cada turno de Revisar. Tiene contadores, alcance, descartar y los prompts de arreglo y pregunta.
- **Script Editor** (`review/review_annotations.gd`):
  - marca ● por severidad (bug ámbar, orden violeta, rendimiento azul, estilo gris) y fondo de la línea;
  - tarjeta bajo la línea con título, explicación, sugerencia y los botones Aplicar arreglo / Preguntar / Descartar;
  - banda "Revisión del agente · solo lectura" en la barra de estado.
- **Panel del dock** en modo Revisar (`ui/dock/review_panel.gd`):
  - "Revisión de <carpeta>/ · N archivos", aviso de solo lectura, contadores por severidad y lista `archivo:línea · título`, que abre la tarjeta;
  - **Exportar a CLAUDE.md** muestra una vista previa editable y agrega la sección al final de `res://CLAUDE.md`;
  - **Arreglar en modo Construir**.
- La tarjeta de diff del chat ya no ensancha el dock cuando el diff trae líneas largas: se desplaza en horizontal.

### Verificación automática

```sh
$G --headless --path . --script tests/run_all.gd                 # 71 tests, 427 checks (+ parser, revisión)
tests/run_in_xvfb.sh $G --godot-agent-review-test                # agente falso: 3 bugs sembrados, marcas, tarjeta, banda, acciones
XRUN_TIMEOUT=500 tests/run_in_xvfb.sh $G --godot-agent-claude-review-test   # Claude Code real (gasta tokens)
```

`tests/fixtures/review/` tiene tres bugs sembrados sin pistas en el código:
- movimiento sin `delta` (bug);
- setter exportado que usa un `@onready` antes de `_ready` (orden);
- `get_node` en `_process` (rendimiento).

Con el agente falso (`tests/scripts/review.json`), la prueba recorre todo:
- los 3 hallazgos en su línea, con marca, cursor, tarjeta y banda;
- Descartar;
- Preguntar, que no reemplaza la revisión;
- la vista previa de CLAUDE.md;
- Aplicar arreglo, que pasa a Construir y saca el hallazgo;
- Arreglar en modo Construir, que vacía la revisión.

Pasa en 4.4.1, 4.7.2 y 4.8-beta1, junto con `acp_session_check`, cycle y ui.

Con Claude Code real (4.8 y 4.4.1), los tres bugs quedaron anotados en su línea con la severidad esperada; en 4.8 agregó un cuarto hallazgo válido.

### Prueba manual

1. Iniciar sesión, pasar a **Revisar** y pedir "revisá tests/fixtures/review/". Al terminar el turno, el panel del dock muestra "Revisión de tests/fixtures/review/ · 3 archivos" con los contadores.
2. Clic en un hallazgo de la lista: se abre el script en esa línea, con la marca ● y la tarjeta abajo. La barra de estado del editor dice "Revisión del agente · solo lectura".
3. En la tarjeta, **Descartar** saca la marca; **Preguntar** manda la pregunta y la revisión sigue igual.
4. **Aplicar arreglo** cambia el modo a Construir y pide ese arreglo. Al aceptarlo y terminar el turno, el hallazgo desaparece.
5. **Exportar a CLAUDE.md**: aparece la vista previa; al aceptar, la sección queda al final de `CLAUDE.md`.

### Pendiente

- Conteos por archivo en la lista de scripts del Script Editor (D23).
- Seguir las ediciones para mover las marcas: hoy hay que volver a revisar.


## M6 · One-shot y cuota del plan

### Qué hay

- **Cuota del plan** (`core/quota_monitor.gd`, spec §10.1, D22):
  - estados normal / aviso / pausa programada / limitado / desconocido;
  - ventanas actual y semanal, leídas del `usage_update` del agente; el texto y el error de límite pasan a "limitado";
  - hora de reinicio exacta o, si no se conoce, backoff de 5, 10, 20 y cada 60 min;
  - umbrales en EditorSettings `godot_agent/quota/*`: aviso 75 %, pausa 90 % (o nunca), y al reiniciarse la ventana retomar solo o esperar confirmación.
- **Dock**: medidor de la ventana y la semana debajo del estado (oculto si el agente no informa la cuota), avisos en el chat y, en "limitado", el botón enviar bloqueado con la cuenta regresiva.
- **Checkpoints git** (`oneshot/git_checkpoints.gd`, D24):
  - rama `agent/<fecha>`, con WIP previo confirmado si había cambios;
  - `cpN: tarea` antes de cada tarea;
  - "Volver acá" limitado a la carpeta del proyecto y solo en la rama del agente;
  - resumen y diffs contra la base;
  - "Aceptar todo" sin merge ni push.
- **Loop One-shot** (`oneshot/oneshot_run.gd`):
  - prompt inicial con el objetivo, el plan, la verificación con `run_scene`/`capture_game_frame`/`get_errors` y el bloque `checks`;
  - auto-continuación mientras queden tareas;
  - "Guiar al agente" encolado para el fin del turno;
  - presupuestos de tiempo, tokens y playtests: aviso al 80 %, cierre con reporte al 100 %;
  - pausa por cuota en el próximo checkpoint, "Limitado" con `cpN-quota` y reanudación desde la tarea correcta.
- **Pantalla Agent** (`ui/main_screen/agent_main_screen.gd`, mockup pantalla 2):
  - formulario de inicio;
  - barra superior con fase, objetivo, barras de Cuota/Tiempo/Tokens/Playtests, la regla de cuota, la cuenta regresiva y Pausar/Retomar/Detener;
  - banner de cuota;
  - columnas Plan (editable), Actividad (con "Guiar al agente") y Último playtest / Verificaciones / Checkpoints ("Volver acá");
  - barra inferior con el resumen de cambios, "Revisar cambios" y "Aceptar todo".

  Elegir One-shot en el dock abre esta pantalla. Con un One-shot en curso, el composer del dock guía al agente.
- **Sandbox** (`tests/sandbox_project/`, `tests/make_sandbox.sh <dir> [--dev]`): proyecto aparte, fuera del repo, para correr One-shots. Nunca se corre uno sobre el proyecto del addon.

### Verificación automática

```sh
$G --headless --path . --script tests/run_all.gd                 # 78 tests, 509 checks (+ cuota, checkpoints git)
$G --headless --path . --script tests/acp_session_check.gd       # 70 checks (+ estados de cuota con el agente falso)
$G --headless --path . --script tests/oneshot_check.gd           # 34 checks: loop, pausa por cuota, límite, presupuestos, guía, sin plan
tests/run_in_xvfb.sh $G --godot-agent-ui-test=ui_quota           # dock: medidor y envío bloqueado en "limitado"
tests/run_in_xvfb.sh $G --godot-agent-oneshot-test               # pantalla Agent con el agente falso sobre un repo temporal
tests/make_sandbox.sh /tmp/sandbox --dev
XRUN_PROJECT=/tmp/sandbox XRUN_TIMEOUT=2900 tests/run_in_xvfb.sh $G --godot-agent-claude-oneshot-test   # Claude Code real (gasta tokens)
```

`oneshot_check` y `--godot-agent-oneshot-test` usan guiones del agente falso:
- cuota al 91 % a mitad de la tarea 1: la tarea termina, se crea el checkpoint de la tarea 2 y se pausa;
- la ventana se reinicia y retoma solo, con el prompt "Continuá con el plan desde la tarea «Puntaje y saque»; el estado está en el checkpoint cp3";
- el límite llega a mitad de turno: `cp4-quota`, "Limitado" con cuenta regresiva y, esta vez, espera confirmación;
- Retomar sigue desde `cp4-quota` y termina el plan.

La prueba de UI además revisa las barras, el banner, el resumen de cambios, el diff, "Volver acá" y "Aceptar todo".

Todo pasa en 4.4.1, 4.7.2 y 4.8-beta1, junto con el cycle test (5 ciclos sin huérfanos).

### One-shot con Claude Code real

`--godot-agent-claude-oneshot-test` en el sandbox, con 4.8-beta1 y el objetivo "Pong de 2 jugadores con puntaje: paletas con W/S y flechas arriba/abajo, pelota que rebota, puntaje arriba y saque desde el centro después de cada punto". Presupuestos: 25 min, 3M tokens, 5 playtests. La prueba pide un playtest con captura, al menos 3 checkpoints, escenas nuevas y que "Volver acá" al anteúltimo checkpoint deje el proyecto idéntico (sin diff ni archivos sin seguimiento).

| Corrida | Resultado | Playtests | Tokens | Tiempo | Checkpoints |
|---|---|---|---|---|---|
| 1 | falla: pocos checkpoints | 5 | 121k | 7,2 min | 1 |
| 2 | pasa, pero termina a mitad de camino | 2 | 104k | 6,7 min | 3 |
| 3 | pasa: todos los checks en `pass` | 4 | 114k | 6,6 min | 5 |

Lo que salió de las corridas:
- **Corrida 1**: el juego quedó bien (11 checks en `pass`, "8 archivos cambiados +310 −5"), pero hubo dos problemas.
  - Con `.godot/` en el `.gitignore`, `git add -- . :(exclude).godot` sale con error: git rechaza un pathspec que nombra una ruta ignorada, aunque sea para excluirla. Los checkpoints quedaron apagados después de `cp1`. Arreglo: si `.godot/` está ignorado, el pathspec es `-- .`. Si `start()` falla a mitad de camino, vuelve a la rama del usuario y borra la rama del agente.
  - Claude Code no usó ninguna herramienta de plan, y el harness insistió con "la próxima tarea pendiente es «la tarea pendiente»". Arreglo: un checkpoint por playtest y avance por checks cuando no hay plan (D24).
- **Corrida 2**: checkpoints por playtest y "Volver acá" exacto. Pero el agente cerró el turno con "pruebo si `add_node` acepta un shape inline", con un check en `fail` y otro en `pending`, y el harness lo tomó como final. Arreglo: sin plan, el harness sigue mientras queden checks sin pasar (D24).
- **Corrida 3**: terminó sola con "todos los checks pasan" (paletas, rebote, puntaje, saque, sin errores), con un checkpoint por playtest. "Volver acá" a `cp4` dejó el proyecto exacto.
- En las tres, la captura del playtest mostró el juego corriendo (marcador incluido) y la cuota real del plan se vio en la barra: 77–82 % de la ventana de 5 h, con el banner "se pausa al 90 % en el próximo checkpoint".
- La actividad mostraba comandos de shell enteros (heredocs de 40 líneas). Ahora va solo la primera línea, recortada a 140 caracteres.

### Prueba manual

1. `tests/make_sandbox.sh ~/sandbox-oneshot` y abrir ese proyecto en el editor.
2. En el dock, iniciar sesión y elegir **One-shot**: se abre la pantalla **Agent**.
3. Escribir "Pong de 2 jugadores con puntaje", dejar los presupuestos y los checkpoints, e **Iniciar One-shot**.
4. Mirar el plan, la actividad, las capturas de cada playtest y los checkpoints `cpN`. **Guiar al agente** manda un mensaje al terminar el turno.
5. **Volver acá** en un checkpoint: el proyecto queda como en ese momento y el One-shot se pausa. **Retomar** sigue desde esa tarea.
6. **Revisar cambios** lista los archivos (doble clic: diff contra el inicio). **Aceptar todo** deja la rama `agent/<fecha>` lista para mergear a mano.
7. Cuota: con el umbral de pausa en Settings (`godot_agent/quota/pause_percent`) por debajo del uso actual, el One-shot se pausa al empezar la próxima tarea y el banner lo explica.

### Pendiente

- Marcas A/M en el FileSystem para los archivos tocados (mockup); el dock del FileSystem es interno del editor.
- Resuelto en M7: `session/load` para retomar una sesión perdida, y los presupuestos default en Settings.

---

## M7 · Settings, historial, Markdown, rendimiento y README

### Qué hay

- **Settings** (`ui/settings/settings_dialog.gd`): un diálogo propio, porque una sección en Project Settings escribiría en `project.godot`. Se abre con el botón de ajustes del dock y reemplaza al editor de perfiles en JSON de M1. Secciones:
  - **Agentes**: CRUD de perfiles y predeterminado. En `env` las claves van como `$VAR`: un valor literal en una variable con nombre de secreto no se guarda.
  - **Permisos**: la matriz grupo × modo, "Volver a los valores de la spec" y la espera de las preguntas.
  - **Servidor MCP**: URL actual, puerto, **Regenerar token** (reinicia el server en el mismo puerto), límites de las tools, playtest en runs manuales y carpetas extra para `fs/*`.
  - **One-shot y cuota**: presupuestos default, checkpoints, umbrales de aviso y de pausa, y qué hacer al reiniciarse la ventana.
  - **Interfaz**: color de acento y ubicación inicial del dock (nuevo `godot_agent/ui/dock_slot`).
  - **Export**: presets sin el filtro y el botón para agregarlo, previa confirmación.

  Guardar valida primero: ids únicos, un solo predeterminado, pausa por encima del aviso, rutas absolutas. Lo del usuario va a `EditorSettings` y lo del proyecto a `project_config.tres`; la matriz guarda solo lo que difiere de la spec. Permisos, carpetas, límites de las tools y presupuestos se aplican en caliente; puerto, color y dock, al reabrir el editor.
- **Historial** (`session/session_history.gd`, spec §11): `user://godot_agent/sessions/<id>.jsonl` más un `index.json`.
  - Guarda prompts, chunks unidos por mensaje, tool calls sin capturas ni `rawOutput` (los textos se recortan a 4000 caracteres), plan, título y fin de turno.
  - Escribe una vez por turno y solo agrega las líneas nuevas, en un worker. Reescribir el JSON entero costaba 49 ms con 3,5 MB. Agregar las líneas cuesta 0,2 ms (p50), pero con el disco ocupado abrir el archivo llegó a 600 ms: por eso la escritura no va en el hilo principal.
  - Las lecturas (menú, reanudar) y el cierre del plugin esperan al worker.
  - Mientras se rearma una conversación del historial, `SessionModel.replaying` evita que las señales del replay se tomen como eventos nuevos (sincronizar archivos, checkpoints, playtests).
  - El botón **Historial** del dock lista las sesiones del proyecto.
  - Abrir una sesión arma la conversación desde el archivo y llama a `session/load`. El replay que manda el agente se descarta, porque trae el prompt de sistema como mensaje del usuario. Sin `loadSession`, la sesión queda de solo lectura.
  - El One-shot, si perdió la sesión, la reabre con `session/load` (`SessionController.reopen`) y sigue con el mismo prompt de reanudación (D24).
- **Markdown → BBCode robusto** (m7-04):
  - escapes y code spans protegidos antes de aplicar formato;
  - spans de N backticks;
  - links con paréntesis;
  - fences ``` y ~~~;
  - continuación de listas, saltos forzados y citas anidadas;
  - tags siempre balanceados, aun con marcas cruzadas.
- **Rendimiento con sesiones largas** (m7-05):
  - el transporte entrega las líneas de stdout con 6 ms por frame;
  - la conversación arma las vistas por tandas de 8 ms y no arma las que quedarían ocultas;
  - agrupa los refrescos;
  - "Mostrar 50 anteriores" reemplaza al aviso de entradas ocultas.
- **README** (`README.md`): instalación, modos, permisos, tools, One-shot, cuota, historial, perfiles, dónde se guarda cada setting, export, cómo actualizar sin perder la config y limitaciones por versión.

### Verificación automática

```sh
$G --headless --path . --script tests/run_all.gd                 # 84 tests, 570 checks (+ Settings, Markdown)
$G --headless --path . --script tests/acp_session_check.gd       # 88 checks (+ historial, session/load, reopen)
$G --headless --path . --script tests/oneshot_check.gd           # 34 checks
tests/run_in_xvfb.sh $G --godot-agent-settings-shots=/tmp/s      # Settings desde el dock: 6 secciones; Guardar aplica la matriz
tests/run_in_xvfb.sh $G --godot-agent-history-test=/tmp/h.png    # dos turnos, menú de historial y reanudación desde el dock
tests/run_in_xvfb.sh $G --godot-agent-long-test                  # 641 entradas: frames, tope de vistas, "Mostrar anteriores"
```

Todo pasa en 4.4.1, 4.7.2 y 4.8-beta1, junto con el cycle test, `--godot-agent-oneshot-test` y `--godot-agent-ui-test=ui_quota`.
- Sesión larga en 4.8 (OpenGL por software en Xvfb): peor frame entre 83 y 133 ms, y p95 entre 49 y 95 ms. Antes de m7-05, un frame llegó a 3951 ms.
- Con el historial escribiendo en el hilo principal y la máquina cargada (load 5–6, el indexador de archivos activo), hubo frames de 400 ms a 2 s justo al fin del turno. Con el historial apagado no pasaba, y el guardado medido adentro del editor dio 9 ms en una corrida y 607 ms en otra. Pasar la escritura a un worker lo resolvió.
- La revisión de código (checklist godot-code-review) encontró un problema alto: el replay del historial disparaba checkpoints y avisos de "escena modificada". También encontró tres medios: `reopen` relanzaba después de una cancelación; quitar un perfil corría el formulario de edición; reanudar sin índice rompía. Los cuatro están arreglados y tienen test. De los bajos se arreglaron 5 de 6: la config queda como estaba si falla el guardado, una línea cortada no se pega a la siguiente, no se conecta dos veces `process_frame`, no se pierden refrescos, el menú de historial revisa el estado al elegir, y los diffs largos no van al historial. Queda uno: la carga de una sesión del historial es sincrónica.

### Prueba manual

1. **Settings** (ícono de herramientas del dock):
   - en Permisos, poné "Editar escenas" en **no** para Construir y guardá;
   - en Construir, pedile al agente que agregue un nodo: se deniega sin preguntar.
2. En **Agentes**, agregá una variable `ANTHROPIC_API_KEY=sk-…`: no se guarda y pide `$VAR`.
3. **Historial**:
   - hacé dos preguntas y tocá **Nueva sesión**;
   - en **Historial** elegí la anterior: se ve la conversación y, con Claude Code, el aviso "Sesión reanudada";
   - preguntale algo de lo anterior: lo recuerda.
4. **Sesión larga**: con el agente falso (`--godot-agent-long-test`) o una sesión real larga, el editor no se congela. "Mostrar 50 anteriores" trae las entradas viejas.

### Pendiente

- m7-01: reportar a Godot los problemas de la main screen en 4.8-beta1. Es otra tarea, fuera de esta sesión.
- La ubicación del dock solo cuenta la primera vez con `EditorDock` (4.8): después el editor recuerda la que eligió el usuario.


## M8a · Completado local: núcleo sin IA

Spec §16, §12 (M8a). Decisiones en D26.

### Hecho

- **CompletionController** (m8-01), uno por CodeEdit de script:
  - se engancha con `editor_script_changed` y se suelta cuando el CodeEdit se libera (pestaña cerrada). Si el Script Editor se hace flotante, el CodeEdit solo cambia de padre y el controller sigue;
  - dispara con un debounce de 30 ms si el caret está al final de la línea (o solo hay cierres a la derecha), sin selección, sin el popup nativo abierto y en un `.gd`;
  - invalida al cambiar de línea, al tipear algo distinto a la sugerencia, con Esc y al perder el foco;
  - type-through: tipear el comienzo de la sugerencia lo consume sin pedir otra;
  - Alt+\ pide una a mano, y solo se consume si en ese lugar se puede pedir;
  - con selección o varios carets no se sugiere, y Tab no acepta;
  - descarta las respuestas viejas por número de secuencia.
- **GhostTextRenderer y aceptación** (m8-02):
  - dibuja desde la señal `draw` del CodeEdit, en la posición del caret, con la fuente y el tamaño del editor, recortado al área de texto;
  - Tab inserta la sugerencia en una sola acción de undo y la suma al historial;
  - con cierres a la derecha del caret (`")` del autocierre), el ghost text va en el medio y los cierres se redibujan después;
  - las teclas se interceptan con `gui_input` y `accept_event()`, sin hacer falta el fallback por `_input` (D26).
- **ProjectContext** (m8-03), indexado en `WorkerThreadPool` y publicado entero:
  - `extends` y `class_name`;
  - funciones y señales de cada script;
  - nodos de cada `.tscn` (tipo, únicos, instancias, script), grupos y conexiones;
  - qué nodos usan cada script;
  - recursos del proyecto.
  En el hilo principal, con caché: virtuales y señales de ClassDB, clases globales, input map, autoloads y la escena abierta. Se reindexa con `filesystem_changed`, `resources_reimported` y el buffer sin guardar.
- **ContextRules** (m8-04): las 9 reglas de la tabla §16.2a.
- **LineRetrieval, historial de la sesión y Ranker** (m8-05).
- **Fixture, tests y benchmark** (m8-06):
  - `tests/completion_fixture/`: escenas con hijos, `%` únicos, una instancia, conexiones, input map, autoloads y una herencia por `class_name`;
  - tests de cada regla, del índice, la recuperación, el historial, el ranker y el post-procesado;
  - tests del controller sobre un CodeEdit real con reloj simulado, y un proveedor falso (`tests/fake_completion_provider.gd`);
  - benchmark con 200 scripts generados.

### Verificación automática

```sh
$G --headless --path . --script tests/run_all.gd                 # 109 tests, 752 checks (25 del completado)
$G --headless --path . --script tests/run_all.gd -- completion_bench
tests/run_in_xvfb.sh $G --godot-agent-completion-test [--godot-agent-ui-shot=/tmp/c]
```

- **Benchmark** (`test_completion_bench`): 200 scripts, 60 escenas y 13 529 líneas únicas, con 1500 consultas mezcladas (reglas y recuperación). El build del índice va en el worker y no frena el editor.

  | Versión | Build | p50 | p95 | Máx. |
  |---|---|---|---|---|
  | 4.8-beta1 | 209 ms | 0,05 ms | 1,29 ms | 3,1 ms |
  | 4.7.2 | 208 ms | 0,05 ms | 1,43 ms | 3,3 ms |
  | 4.4.1 | 223 ms | 0,05 ms | 1,62 ms | 3,8 ms |

  El criterio es p95 < 10 ms. El test lo verifica y deja la medición en la salida. El rebuild del test relee todo porque los archivos se acaban de escribir (lo modificado hace menos de 2 s nunca se reutiliza, D26).
- **En el Script Editor real** (`--godot-agent-completion-test`, con eventos de teclado como los de una persona), en 4.4.1, 4.7.2 y 4.8-beta1:
  - `@onready var ` sugiere `cooldown: Timer = $Cooldown`, el primer hijo de la escena;
  - con `ba` sugiere `r: ProgressBar = %Bar`, un nodo único;
  - Tab inserta y un undo lo deshace;
  - Esc descarta;
  - `func _` sugiere `process(delta: float) -> void:` (`_ready` ya estaba);
  - una línea repetida en otros dos scripts se sugiere al tipear su comienzo;
  - Tab sin sugerencia indenta;
  - con `")` del autocierre a la derecha, `preload("res://…/sco` sugiere el resto de la ruta y Tab respeta el cierre;
  - con el popup nativo abierto no se pide sugerencia, y Tab elige la opción del popup.
- Todo pasa en 4.4.1, 4.7.2 y 4.8-beta1: `run_all`, `acp_session_check`, `oneshot_check` y el cycle test.
- El cycle test crece 29 objetos en 5 ciclos, y lo mismo sin el servicio de completado, así que no viene de M8a. Está por debajo de la tolerancia de 50.

### Revisión de código

Corregido después de la revisión de M8a:
- Selección y varios carets: Tab no acepta y no se sugiere.
- `%` como operador (`x % 2`) ya no dispara la regla de nodos únicos.
- Conexiones con `binds`/`unbinds` y señales de varias líneas: no se proponen firmas que no se pueden saber.
- Las cachés de nodos y señales se vacían al publicar un índice nuevo.
- Script Editor flotante: el controller no se pierde.
- Tipos desconocidos (nodos de escenas instanciadas o heredadas): `@onready` sale sin tipo antes que con uno inventado.
- Costo por tecla: el set de funciones definidas se arma una vez, la petición no vuelve a partir el texto y el índice viejo se libera en el worker.
- El ghost text no se dibuja si el caret no está en su ancla.
- Apagado no indexa, y cambiar `completion_exclude` reindexa.
- `load`/`preload` solo sugieren recursos con extensiones conocidas; sin nada escrito y con varias opciones no se adivina (rutas, acciones, grupos).
- La normalización no colapsa espacios dentro de strings.
- `wait()` cancela el build en curso.

Queda documentado y sin resolver: si el addon se recarga como `@tool` con un build en curso, el worker sigue con los scripts viejos hasta terminar (D26).

### Prueba manual

1. Abrí un script adjunto a una escena con hijos y escribí `@onready var ` en una línea nueva: aparece en gris el primer hijo no declarado, con tipo y ruta. Tab lo inserta y Ctrl+Z lo deshace de una vez.
2. Escribí `func _`: aparece el primer virtual de la clase base que falta, con su firma.
3. Copiá una línea a otro script y escribí su comienzo en un tercero: se sugiere el resto.
4. En una línea sin sugerencia, Tab indenta. Con el autocompletado de Godot abierto, Tab elige la opción de la lista.
5. En el Agent Log, canal `cmp`: el tiempo del índice y, por cada sugerencia, la fuente, la latencia y qué pasó (aceptada o descartada, con el motivo). El código no aparece.

Lo que era M8b (línea siguiente, bloques, multilínea, Ctrl+→, adaptación, n-gram, caché y set de evaluación) está en la sección siguiente.

## M8b · Completado local: calidad

Spec §16.2–§16.9, §12 (M8b). Decisiones en D27.

### Hecho

- **Recuperación ampliada** (m9-01):
  - predicción de la línea siguiente en una línea vacía, con la sangría relativa;
  - extensión a bloque mientras todas las apariciones (al menos 2) sigan iguales;
  - adaptación de un identificador (`enemy_` ↔ `player_`) en snake_case, PascalCase y MAYÚSCULAS.
- **Multilínea y Ctrl+→** (m9-02):
  - la primera línea va inline y el resto en una caja debajo (o arriba, si no entra);
  - todo se dibuja en un overlay hijo del CodeEdit. Esto arregla además el tapado de los cierres de M8a, que en 4.8 quedaba debajo del texto;
  - Ctrl+→ inserta la siguiente palabra en su propio paso de undo.
- **n-gram** (m9-03): lexer GDScript, orden 4 con stupid backoff, clase número, actualización por archivo copy-on-write y generación hasta la primera duda.
- **Post-procesado completo y caché** (m9-04): stops, recorte de bloques, solapamiento con el suffix, sangría del editor, chequeo de paréntesis multilínea y LRU de sugerencias.
- **Reglas** (m9-06, al ajustar por precisión): veto cuando la regla reconoce el contexto pero no puede elegir, convenciones de nombres de `@onready`, hijos directos primero, herencia y `load("` por nombre de variable.
- **Set de evaluación** (m9-05, m9-06): `tests/completion_eval/` (proyecto propio, 48 casos), `tests/run_completion_eval.gd` con la tabla por combinación de fuentes y `test_completion_eval` como regresión. Los umbrales por defecto salen de ahí.
- **Settings**, en `godot_agent/completion/`: `multiline`, `max_lines` (8), `sources/{rule,retrieval,ngram,history}` y `extra_corpus` (carpetas que solo entrenan el n-gram).

### Verificación automática

```sh
$G --headless --path . --script tests/run_all.gd                 # 122 tests, 877 checks
$G --headless --path . --script tests/run_completion_eval.gd     # tabla por fuentes; -- --cases para el detalle
tests/run_in_xvfb.sh $G --godot-agent-completion-test [--godot-agent-ui-shot=/tmp/c]
```

- **Set de evaluación** (48 casos; mismos números en 4.4.1, 4.7.2 y 4.8-beta1):

  | Fuentes | Mostradas | Exactas | Correctas | FP | p95 |
  |---|---|---|---|---|---|
  | reglas | 9 | 9 | 9 | 0 | 0,6 ms |
  | recuperación | 16 | 11 | 11 | 5 | 1,2 ms |
  | n-gram | 5 | 2 | 5 | 0 | 0,2 ms |
  | reglas + recuperación | 19 | 17 | 17 | 2 | 0,3 ms |
  | reglas + recuperación + n-gram | 20 | 17 | 18 | 2 | 0,3 ms |

  Antes de M8b, reglas + recuperación daba 17 mostradas, 11 correctas y 6 FP.
- **Benchmark** (`test_completion_bench`, 200 scripts, 60 escenas, 1500 consultas): ahora el build incluye el lexer y el n-gram.

  | Versión | Build | p50 | p95 | Máx. | Rebuild |
  |---|---|---|---|---|---|
  | 4.8-beta1 | 756 ms | 0,17 ms | 1,86 ms | 5,9 ms | 520 ms |
  | 4.7.2 | 810 ms | 0,17 ms | 1,92 ms | 4,7 ms | 519 ms |
  | 4.4.1 | 815 ms | 0,18 ms | 2,07 ms | 5,1 ms | 550 ms |

  El rebuild del test relee todo (archivos recién escritos, D26). En el editor, un archivo cambiado re-lexea solo ese archivo y actualiza el n-gram por diferencia.
- **En el Script Editor real** (`--godot-agent-completion-test`, en 4.4.1, 4.7.2 y 4.8-beta1), además de lo de M8a:
  - después de `func reset() -> void:` + Enter, se sugiere el cuerpo de tres líneas que tienen otros dos scripts;
  - la caja muestra las dos líneas siguientes. En 4.4.1 el caret queda en la última fila visible y la caja va arriba;
  - Ctrl+→ inserta `combo_multiplier` y deja ` = 1…` a la vista; Tab inserta el resto del bloque.
- Las capturas ampliadas muestran que el `")` del autocierre queda tapado y que el caret se ve.
- Todo pasa en 4.4.1, 4.7.2 y 4.8-beta1: `run_all`, `acp_session_check`, `oneshot_check`, el cycle test y el test de completado.
- En 4.7.2 y 4.4.1 el editor imprime "3 resources still in use at exit" al salir. Pasa igual en el cycle test sin completado y en el commit de M8a, así que no viene de M8b.

### Revisión de código

Corregido después de la revisión de M8b (con tests, salvo el build cancelado y el recorte del overlay; los de la adaptación y de Tab en el mismo frame se comprobaron fallando sin el arreglo):
- El build incremental del n-gram agregaba tokens al vocabulario del modelo publicado, que el hilo principal estaba leyendo (los `Packed*Array` asignados se comparten). Ahora se copian.
- La adaptación de identificadores corría también con una línea ya completa o un prefijo ambiguo: `health -= damage` completo sugería ` * 0.5` de `armor -= damage * 0.5`.
- La caché devolvía sugerencias viejas después de cambiar el input map, los nodos de la escena abierta o el historial: la generación del proveedor entra en la clave.
- Tab (o Ctrl+→) en el mismo frame que otra tecla aceptaba la sugerencia vieja.
- Una línea de 20 000 caracteres costaba ~18 ms por tecla; ahora menos de 5 ms (`test_long_lines_stay_cheap`).
- Un build cancelado seguía armando las líneas y el n-gram mientras el hilo principal esperaba.
- Con 2 espacios por nivel no había bloques ni `<indent>` en el n-gram.
- El contexto del n-gram no tenía los cambios de sangría entre las líneas de arriba.
- El overlay se recorta al área de texto (scroll horizontal, barra horizontal).

Queda documentado: con los umbrales actuales el backoff del n-gram no genera (D27).

### Prueba manual

1. En un script nuevo, escribí la línea de un `func` que ya existe en otros scripts con el mismo cuerpo y Enter: aparece el cuerpo, la primera línea inline y el resto en una caja. Ctrl+→ acepta palabra por palabra; Tab, todo.
2. Escribí el comienzo de una línea que existe con otro nombre (`enemy_health -= ` donde el proyecto tiene `player_health -= damage`): se sugiere con el nombre cambiado.
3. Con `Input.is_action_pressed("` y varias acciones, no aparece nada (veto); con una letra, la acción que empieza así.
4. En Configuración del editor, `godot_agent/completion/sources/ngram` apagado: desaparecen las sugerencias que solo venían del n-gram. `multiline` apagado: solo la primera línea.

## M8c · Completado con LLM opcional

Spec §16.1, §16.7–§16.10, §12 (M8c). Decisiones en D28.

### Hecho

- **Proveedores y modo híbrido** (m10-01):
  - `LlmProvider` implementa la misma interfaz que el local (`complete`/`cancel`), con un HTTPRequest sin hilos por editor y cancelación por generación;
  - modos solo local, híbrido y solo LLM en el controller: en híbrido lo local nunca espera al LLM, el LLM se pide solo sin nada local y con su debounce, una request por vez, y tipear la cancela;
  - Alt+\ en híbrido va al LLM.
- **Cinco tipos de endpoint** (m10-02): Ollama, llama.cpp `/infill`, Codestral FIM, OpenAI-compatible y Gemini (experimental). Están verificados contra la documentación y el código de cada servidor (D28), con plantillas FIM, stops y keys por nombre de variable de entorno. El contexto del proyecto va como comentarios, con presupuesto y prioridad.
- **Métricas, indicador y settings** (m10-03):
  - contadores por fuente (p50/p95, mostradas, aceptadas, errores) en Settings y en el log;
  - indicador en la barra del Script Editor con estado y modo; clic y Alt+Shift+\ prenden y apagan;
  - **Settings → Completado**: on/off de usuario y de proyecto, modo, fuentes, umbrales, corpus extra, exclusiones, ABM de perfiles LLM con aviso de envío a un host remoto, debounce y tamaños del LLM, marcador y log raw. Todo se aplica sin reiniciar.
- **Marcador**: un punto chico después de las sugerencias del LLM.

### Verificación automática

```sh
$G --headless --path . --script tests/run_all.gd                 # 131 tests, 995 checks
tests/run_in_xvfb.sh $G --godot-agent-completion-test [--godot-agent-ui-shot=/tmp/c]
```

- `test_completion_llm`: los cinco formatos de pedido (URL, headers, body) y de respuesta (incluidos errores, cercos de Gemini y respuesta bloqueada), plantillas y stops, recorte de prefix/suffix, contexto con presupuesto. También el proveedor contra `tests/fake_llm_server.gd`: respuesta, demora con cancelación, HTTP 500 y conexión rechazada.
- `test_completion_controller`:
  - en híbrido, lo local en el mismo frame aunque el LLM esté en vuelo (proveedor falso de 300 ms);
  - sin pedido al LLM si hubo algo local; el debounce del LLM;
  - tipear cancela y la respuesta cancelada no se muestra;
  - Alt+\ fuerza el LLM;
  - en solo LLM, el debounce propio y sin consultar lo local.
- `test_settings_dialog`: la sección Completado valida (key pegada, ids repetidos, híbrido sin perfiles, rutas), los stops con escapes, el ABM de perfiles y el aviso de host remoto, y guarda cada valor en EditorSettings o en la config del proyecto.
- **En el Script Editor real** (`--godot-agent-completion-test`), además de M8a y M8b:
  - el indicador está en la barra y dice «local»;
  - se cambia a híbrido desde los settings sin reiniciar, con un perfil Ollama que apunta al servidor falso: el indicador pasa a «híbrido · fake-coder»;
  - `spawn_w` no tiene nada local: el indicador pasa a «pensando» y aparece `ave(3)` del LLM, con el punto. Tab la acepta. Hubo un solo pedido, con el modelo y el prefix;
  - un HTTP 500 pone el indicador en error;
  - de vuelta a local, no hay más pedidos;
  - Alt+Shift+\ apaga y prende.

  Los settings que toca son los EditorSettings reales y se restauran al terminar.
- Todo pasa en 4.4.1, 4.7.2 y 4.8-beta1: `run_all` (131 tests, 995 checks), `acp_session_check` (90), `oneshot_check` (34), el cycle test y el test de completado con el paso del LLM.

### Revisión de código

La revisión de M8c no encontró problemas en la concurrencia: token y secuencia del controller, generación del proveedor, cancelación y reutilización del HTTPRequest. Se corrigió (con tests):
- Un error HTTP sin campo de mensaje conocido iba al log con los primeros 200 caracteres del body; un 422 de FastAPI repite el prompt. Ahora solo van los campos de mensaje.
- Un `null` o un array en `temperature`/`max_tokens` del JSON de perfiles (editable a mano) rompía `llm_profiles()` y con eso `apply_settings()`.
- HTTPRequest seguía redirecciones y reenviaba el código y la key al host nuevo. Ahora `max_redirects = 0` y el body se limita a 1 MB.
- Codestral y Gemini sin variable de entorno mandaban el código sin key. Ahora Settings no valida y el proveedor no manda nada.
- Con el caret al final de la línea, el suffix recortado terminaba con media línea.
- Un controller reemplazado por otro CodeEdit en la misma dirección no liberaba su HTTPRequest.

Además, de la propia verificación: `is_remote` tomaba `[::1]:1234` como remoto, y una key sin guiones (`AIzaSy…`) pasaba como nombre de variable.

### Prueba manual

Sin Ollama ni llama.cpp en esta máquina, no se probó contra un modelo real. Para hacerlo:
1. `ollama pull qwen2.5-coder:1.5b-base` y `ollama serve`.
2. Settings → Completado → modo Híbrido; el perfil Ollama ya viene. Guardar: el indicador dice «híbrido · qwen2.5-coder:1.5b-base».
3. En un script, escribí algo que el proyecto no tenga (`var gravity_scale := `): después de una pausa aparece una sugerencia con un punto al final. El Agent Log muestra `llm sugerencia N ms in X out Y`.
4. Seguí tipeando mientras el indicador está ámbar: la request se cancela (`llm cancelled` en el log) y lo local sigue apareciendo al instante.
5. Con un perfil Codestral, sin `MISTRAL_API_KEY` en el entorno: el indicador se pone rojo con el error. Con la variable y reabriendo el editor, funciona; la tarjeta del perfil avisa que el código se envía a api.mistral.ai.
6. Settings → Completado → «Esta sesión, por fuente» muestra p50/p95 y aceptación de `llm` y de las fuentes locales.

## Después de M8c · Prueba en un proyecto real

- **UI del editor rota al activar el plugin** (Asteroids, 4.8-beta1): toda la UI quedaba en una franja angosta. Labels con autowrap del dock oculto pedían miles de píxeles de alto, y los slots de docks cuentan las pestañas ocultas (D29). Arreglado con `ui/min_size_guard.gd` alrededor de cada superficie.
- Verificado con una copia del proyecto en Xvfb: con el dock oculto y con el dock como pestaña elegida (como lo tenía el usuario), el editor se acomoda normal. `test_min_size_guard` lo reproduce.
- En 4.4.1, 4.7.2 y 4.8-beta1: `run_all` (132 tests, 1003 checks), `acp_session_check`, `oneshot_check`, cycle, completion, edit, review, oneshot, sync y long test.
- **Composer**: Enter envía, Ctrl+Enter y Shift+Enter bajan de línea (pedido del usuario, D30). Tipear `/` o `@` abre una lista propia arriba del texto, como la de VS Code (la del CodeEdit mostraba una fila), y elegir un comando ya no pierde la `/`. `test_composer`.
- **Historial de prompts** con ↑/↓ en el composer, como en una terminal, persistido por proyecto (D30). `test_composer`.
- **Subagentes** (D31): lo que hace un subagente de Claude Code queda dentro de la tarjeta de su llamada `Agent`, en vez de salir suelto y con su texto mezclado en la respuesta. `test_session_model`, `test_tool_group_view`, y el guion `ui_demo` lo muestra.
- **Login del agente** desde el dock, como en Zed o JetBrains (D32): si el agente pide autenticarse, el aviso ofrece «Iniciar sesión · Claude Subscription / Anthropic Console», corre el login de Claude Code (navegador), muestra el enlace, deja pegar el código y vuelve a abrir la sesión. `test_agent_login`, `acp_session_check` (login) y `--godot-agent-login-test`.
- **Cambios del agente por fuera del editor** (D33): el Write de Claude Code escribe directo al disco, y Godot preguntaba «Files have been modified outside Godot» por `project.godot` y las escenas abiertas. Ahora `project.godot` se aplica a ProjectSettings y el editor lo guarda, y las escenas abiertas sin cambios sin guardar se recargan solas (4.7+). `--godot-agent-external-test`.
- **Mínimo Godot 4.6** (D34, pedido del usuario): matriz 4.6.3, 4.7.2 y 4.8-beta1; se fue el código que solo existía por 4.4 (pipes retenidos, lectura del panel Output, reflexión).
- **Settings → Completado**: «Todavía no hubo sugerencias» salía una letra por línea (otro label con autowrap en una grilla). El cycle test ahora busca labels así en el dock y en todas las secciones de Settings.
- **Tarjeta de revisión que no aparecía**: si se armaba antes de que el CodeEdit acomodara el texto, la línea parecía fuera de pantalla y, si el scroll no cambiaba después, nadie la volvía a ubicar. Ahora también se ubica en el `draw` del CodeEdit (sin trabajo si nada cambió). Lo mostró el review test con la ventana del editor más chica que dejaron las pruebas en Asteroids.
- **El editor ya no se cae si un script del addon cambia en disco con el agente corriendo** (D35): `AgentProcess` lee los pipes en el hilo principal, sin threads. Pasó en little-villages al editar el addon por el symlink, y se perdió el One-shot. `test_agent_process` recarga el script con un proceso escribiendo.
- **Cola de prompts** en el dock (D36, pedido del usuario): con el agente trabajando, Enter deja el mensaje en cola; sale al terminar el turno, y si el turno se cancela o falla, la cola espera «Enviar ahora». `test_prompt_queue`, `test_composer` y `--godot-agent-queue-test`.
- **El One-shot sobrevive a un cierre o una caída del editor** (D37): el run se guarda en `user://` mientras corre y, al volver, queda en pausa con su actividad; «Retomar» reabre la sesión del agente (o una nueva con el resumen). Antes de empezar se avisa si no va a haber checkpoints (repo sin commits). `test_oneshot_store`, `oneshot_check` (recuperación) y `--godot-agent-oneshot-test`.
