# Decisiones

Registro de decisiones de diseño, choques entre skills y spec, y verificaciones de API.
Formato: fecha · decisión · por qué.

---

## D1 · Estructura de carpetas (M0)

Skills: `godot-architecture` (por feature), `godot-communication`, `godot-patterns`, `godot-data-driven`, `godot-code-review`.

El repo es un proyecto Godot "anfitrión" para desarrollar el addon. Solo `addons/godot_agent/` se distribuye.

```
project.godot                      # proyecto anfitrión de desarrollo (no se distribuye)
addons/
  godot_agent/                     # EL addon. Todo @tool, todo excluido del export
    plugin.cfg
    plugin.gd                      # raíz de composición: crea los servicios y los inyecta en la UI
    export/
      agent_export_plugin.gd       # skip() de addons/godot_agent/ + guard de autoload huérfano
      export_presets_patcher.gd    # lee/parchea exclude_filter en export_presets.cfg
    playtest/
      playtest_autoload.gd         # alta/baja/limpieza del autoload (lado editor)
      playtest_debugger.gd         # M4: EditorDebuggerPlugin del canal godot_agent: (D20)
      runtime/
        playtest_probe.gd          # el autoload que corre en el juego. Aislado (sin preload)
    transport/                     # M1: agent_process.gd
    acp/                           # M1: acp_client.gd, fs_handler.gd (M2)
    session/                       # M1: session_model.gd · M2: permission_policy.gd
    mcp/                           # M3: mcp_server.gd, http_request_parser.gd, tool_registry.gd,
                                   #     mcp_stdio_shim.gd, tools/<grupo>_tools.gd
                                   # M4: tools/scene_edit_tools.gd, run_tools.gd, value_coercion.gd
    editor/                        # M2: editor_sync.gd · M4: editor_undo.gd (D19)
    oneshot/                       # M6: checkpoints.gd, budgets.gd
    completion/                    # M8: controller, providers/, project_context, ranker…
    config/                        # Resources por proyecto (D5) y prompts editables
    ui/
      dock/                        # agent_dock.tscn/.gd (+ mensajes, composer en M1/M2)
      main_screen/                 # agent_main_screen.tscn/.gd (One-shot, M6)
      log_panel/                   # agent_log_panel.tscn/.gd
      review/  settings/  markdown/
  godot_agent_dev/                 # SOLO desarrollo: herramientas de test que necesitan el editor
docs/                              # decisions.md, progress.md
tests/                             # export_check.gd, plugin_cycle_check.gd, run_all.gd, fake_agent.gd…
compass/                           # tablero de tareas (scompass)
```

- Dentro del addon se agrupa por **feature/capa** (transport, acp, session, mcp, ui…) en vez de por tipo de archivo, como pide `godot-architecture` §4.
- `snake_case` para archivos y carpetas; nodos raíz de escenas en PascalCase.

## D2 · Sin `class_name` global en el addon: constantes `preload` (choque skill ↔ spec)

La skill pide `class_name` que coincida con el archivo. En el addon **no** se usa `class_name`; cada script que necesita otro lo trae con `const AcpClient := preload("../acp/acp_client.gd")` y lo usa como tipo (`var client: AcpClient`).

Por qué:
1. **Export en 4.4**: verificado con 4.4.1: aunque la carpeta del addon se excluya, el `.godot/global_script_class_cache.cfg` exportado sigue listando las clases del addon con su ruta. En 4.8-beta1 ya se filtra, pero el mínimo es 4.4. Sin `class_name` no hay entradas.
2. **Espacio global del usuario**: nombres como `SessionModel`, `ToolRegistry` o `McpServer` chocarían con clases del proyecto del usuario.

Se mantiene el resto de la convención: un script por clase y el nombre de la constante en PascalCase igual al archivo.

Los scripts de `tests/` y `addons/godot_agent_dev/` tampoco usan `class_name`, por la misma razón (no ensucian el proyecto anfitrión).

## D3 · Comunicación: raíz de composición + inyección, sin autoloads de editor

- `plugin.gd` es el "contexto" (`godot-architecture` §6): construye `AgentProcess`, `AcpClient`, `SessionModel`, `McpServer`, `PermissionPolicy`, etc., y los inyecta en la UI con `setup(...)` **antes** de `add_child`/agregar el dock.
- Modelos y transporte son `RefCounted` (testeables sin escena). La UI son escenas.
- Regla de la spec respetada: UI → SessionModel → AcpClient → AgentProcess. La UI solo escucha señales del `SessionModel` (push) y lee su estado actual al conectarse (pull), como pide `godot-communication` §6.
- **No hay EventBus ni autoloads del addon en el editor**: la spec prohíbe entradas en `project.godot`, y con una raíz de composición alcanza. El único autoload es el de playtest (spec §6), temporal.

## D4 · Compatibilidad de API verificada (4.4.1, 4.7.2, 4.8-beta1)

Verificado con `ClassDB.class_get_method_list` en los tres binarios:

| API | Firma | Notas |
|---|---|---|
| `OS.execute_with_pipe` | `(path: String, arguments: PackedStringArray, blocking: bool = true) -> Dictionary` | Igual en 4.4, 4.7 y 4.8. Devuelve `stdio`, `stderr` (FileAccess) y `pid`. Con `blocking=true` las lecturas bloquean: van en `Thread`. |
| `OS.read_string_from_stdin` | `(buffer_size: int)` | **En 4.4 el argumento no tiene default**: pasarlo siempre (fake agent, shim). |
| `OS.kill`, `is_process_running`, `get_process_exit_code` | — | Presentes en 4.4. |
| `EditorPlugin._build() -> bool` | — | Presente en 4.4 (alta del autoload de playtest, M4). |
| `EditorPlugin.add_control_to_dock / add_control_to_bottom_panel` | — | Presentes en 4.4–4.8. `EditorDock` + `add_dock` existen solo desde 4.7: **se usa la API vieja** para soportar 4.4. |
| `EditorExportPlugin.skip()`, `_export_file`, `_export_begin` | — | Iguales en 4.4–4.8. |
| `EngineDebugger.register_message_capture/send_message`, `EditorDebuggerPlugin._capture/_setup_session` | — | Presentes en 4.4. |
| `CodeEdit.get_code_completion_selected_index`, `TextEdit.get_rect_at_line_column` | — | Presentes en 4.4 (M8). |
| Feature tag `editor_runtime` | — | Existe en 4.4 y 4.8: `true` al correr el proyecto con el binario de editor, `false` en el editor (`editor_hint`) y en exports. El guard de `playtest_probe.gd` usa `editor_runtime` + `EngineDebugger.is_active()`. |

Binario de desarrollo: `/opt/godot/versions/4.8-beta1/godot`. El de PATH (`godot`) es 4.7.2. Para verificar el mínimo se usó el 4.4.1 oficial.

## D5 · Settings por proyecto: Resource, no ProjectSettings

`godot-data-driven` pide Resources para lo tuneable, y la spec (§2) prohíbe entradas del addon en `project.godot` (terminarían en `project.binary`). La matriz de permisos y los presupuestos van en un `Resource` en `res://addons/godot_agent/config/project_config.tres` (excluido del export junto con el resto del addon). Riesgo: actualizar el addon pisando la carpeta borraría la config; se avisa en el README (M7). Settings por usuario: `EditorSettings` con prefijo `godot_agent/`.

## D6 · "Agregar a los presets": edición del archivo + aviso de reinicio

No hay API de script para modificar `EditorExportPreset` (solo getters). El botón edita `export_presets.cfg` con `ConfigFile` (el mismo formato que usa el editor) previa confirmación. El editor tiene los presets en memoria: si después se guarda desde el diálogo de Exportar sin reiniciar, puede pisar el cambio. Por eso la UI pide reiniciar el editor, y el export plugin vuelve a avisar en cada export si algún preset no tiene el filtro.

En M0 el aviso vive en el dock (Settings llega en M7).

## D7 · Test de ciclo del plugin vía plugin de desarrollo

Habilitar/deshabilitar un plugin necesita `EditorInterface`, que no existe en `--script`. `addons/godot_agent_dev/` es un plugin que solo actúa si el editor se lanza con `-- --godot-agent-cycle-test`: alterna `godot_agent` 5 veces, mide nodos huérfanos y objetos, y sale con código ≠ 0 si algo queda colgado. `tests/plugin_cycle_check.gd` lanza el editor headless y además falla si la salida tiene errores.

## D8 · Rastros que quedan en el export (aceptados)

`tests/export_check.gd` los reporta como **aviso**, no como fallo:

- `uid_cache.bin` conserva las rutas de los scripts del addon (solo strings, no archivos). Pasa en 4.4, 4.7 y 4.8 cuando el addon se saca con `skip()` y en 4.4 también con el filtro. No hay hook para filtrarlo desde un `EditorExportPlugin`.
- `project.binary` conserva `editor_plugins/enabled` con `res://addons/godot_agent/plugin.cfg` si el plugin estaba habilitado. Es la configuración del proyecto del usuario (pasa con cualquier plugin habilitado) y el runtime la ignora.

Lo que **sí** falla el test: cualquier archivo bajo `addons/godot_agent/` (incluidos `.gdc` y `.remap`), el autoload de playtest en `project.binary` y clases del addon en `global_script_class_cache.cfg`.

## D9 · Docks y main screen: EditorDock en 4.7+/4.8+, API vieja en 4.4–4.6

En 4.8 `_has_main_screen`, `add_control_to_dock`, `add_control_to_bottom_panel` y `_get_plugin_icon` están deprecados en favor de `add_dock(EditorDock)` (main screen = `default_slot = DOCK_SLOT_MAIN_SCREEN` + layout `DOCK_LAYOUT_MAIN_SCREEN`; panel inferior = `DOCK_SLOT_BOTTOM`).

Medido con `tests/plugin_cycle_check.gd`: en **4.8-beta1** un plugin con `_has_main_screen() == true` deja un `EditorDock` huérfano (el que el editor crea por dentro) en cada deshabilitado. Con `add_dock` + `remove_dock` + `queue_free` no queda nada.

`ui/editor_surfaces.gd` decide por superficie, mirando `ClassDB` (no el número de versión):

| Superficie | EditorDock si… | Si no |
|---|---|---|
| Dock lateral | existe `EditorDock` (4.7+) | `add_control_to_dock(DOCK_SLOT_RIGHT_UL)` |
| Panel inferior | existe `EditorDock.DOCK_SLOT_BOTTOM` (4.7+) | `add_control_to_bottom_panel` |
| Main screen | existe `EditorDock.DOCK_SLOT_MAIN_SCREEN` (4.8+) | `_has_main_screen()` + `_make_visible()` |

- Todo lo de `EditorDock` se llama por reflexión (`ClassDB.instantiate`, `set`, `call(&"add_dock")`) para que el addon parsee en 4.4.
- Los valores de `EditorDock.DockSlot` no son los de `EditorPlugin.DockSlot`: se leen con `ClassDB.class_get_integer_constant(&"EditorDock", …)`.
- **Main screen activa al cerrar (4.8-beta1)**: si el editor se cierra con la main screen "Agent" activa, el `remove_dock` da `Condition "!is_inside_tree()"` en `grab_focus`. `EditorSurfaces` cambia antes a la pantalla "2D". No a "Script": en headless eso mete al editor en un bucle de llamadas diferidas ("Message queue out of memory") y crashea. Las dos cosas se reprodujeron y se verificó que el cambio las arregla (tarea m7-01: reportarlas upstream).

## D10 · Export plugin: orden por nombre y baja del autoload a mano

Hallado con `tests/export_check.gd` en 4.8-beta1 (confirmado leyendo `editor/export/editor_export_platform.cpp`):

1. **`skip()` no alcanzaba a los `.gd`.** El editor ordena los export plugins por `get_name()` (`SortByName`) y, por archivo, corta la cadena en el primer plugin que hace `skip()` o un remap. El plugin interno de GDScript remapea `.gd` → `.gdc` antes que el nuestro, así que los scripts se exportaban igual (como `.gdc` + `.remap`). Las escenas sí se salteaban. **Solución**: `_get_name()` devuelve `"!GodotAgentExcludeAddon"`; `!` ordena antes que cualquier letra, así nuestro `skip()` corre primero.
2. **Baja del autoload en `_export_begin`.** `project.binary` se genera al final del export (después de `_export_begin`), así que quitar el autoload ahí **sí** afecta al export en curso. Pero `remove_autoload_singleton` no borraba la entrada en ese momento (tampoco al cerrar el editor: "Trying to remove non-existent autoload", porque el editor nunca lo cargó). `PlaytestAutoload.unregister()` llama a `remove_autoload_singleton` y, si la entrada sigue, la borra con `ProjectSettings.set_setting(…, null)` + `save()`.

Resultado: `export_check.gd` pasa los 4 escenarios en 4.4.1, 4.7.2 y 4.8-beta1. Con el plugin habilitado, el addon queda fuera aunque el preset no tenga filtro. El filtro sigue siendo la red de seguridad para exportar con el plugin deshabilitado.

## D11 · Pipes de `execute_with_pipe` en 4.4.x: no se cierran (M1)

Hallado con `tests/acp_session_check.gd` en 4.4.1: el segundo agente lanzado en la misma sesión del editor no recibía nada y el editor moría con SIGPIPE (código 141). Reproducido con `cat` como hijo. En 4.4.x, cerrar o liberar el `FileAccess` de un pipe cierra descriptores equivocados, **incluido el fd 0 del editor**. El siguiente `pipe()` reutiliza esos números y queda todo cruzado. En 4.5.1, 4.6, 4.7.2 y 4.8-beta1 no pasa.

**Solución** (`transport/agent_process.gd`):
- Con versión < 4.5 (`pipe_close_is_broken()`), los pipes de un agente terminado no se cierran: se guardan en un array estático hasta que se cierra el editor.
- Costo: unos pocos fds por sesión de agente, solo en 4.4.

Otros hallazgos del transporte:
- `OS.is_process_running(pid)` da error con un pid que no es hijo directo del editor o que ya fue cosechado. Para los nietos (node bajo npx), `ProcessTree` solo usa `OS.kill`.
- `npx` deja a `node` como hijo. `OS.kill` sobre el pid de npx no lo mata y sus pipes no llegan a EOF. `ProcessTree.kill_tree` mata el árbol (`pgrep -P` recursivo; `taskkill /T /F` en Windows). Además, `AgentProcess` guarda la lista de descendientes: si el proceso principal muere solo, los huérfanos ya no aparecen en `pgrep -P`.
- Un proceso Godot headless (agente falso, y el shim stdio de M3) **no termina con `quit()`** mientras un thread está bloqueado leyendo stdin. El agente falso sale en EOF y, para simular una caída, se mata a sí mismo.

## D12 · Capa de comandos: SessionController (M1)

La spec pide UI → SessionModel → AcpClient → AgentProcess, con un SessionModel que "no hace IO". Para respetar las dos cosas, la sesión se parte en dos:
- `session/session_model.gd`: estado y señales, sin IO.
- `session/session_controller.gd`: comandos (start, open_session, send_prompt, cancel, set_config_option, stop). Es el único dueño de `AcpClient` y `AgentProcess`. Aplica al modelo lo que llega por ACP.

La UI lee el modelo y llama comandos del controller; nunca toca el cliente ni el proceso. El controller no depende del editor: recibe por inyección `cwd`, `mcp_servers_provider` y `prompt_variables_provider` (y en M2 los handlers de fs y permisos). Por eso se prueba headless contra el agente falso.

Modos del harness ↔ modos del agente: si el agente publica `modes`, Preguntar y Revisar piden `plan`, y Construir y One-shot piden `default` (`session/set_mode`). Al cambiar de modo, el próximo prompt vuelve a llevar el prompt de sistema con el modo nuevo.

## D13 · Adapter de Claude Code: `@agentclientprotocol/claude-agent-acp` (M1)

`npm view` (2026-10-21): `@zed-industries/claude-agent-acp` y `@zed-industries/claude-code-acp` están deprecados. El paquete vigente es `@agentclientprotocol/claude-agent-acp` (v0.94.0, binario `claude-agent-acp`). Perfil por defecto: `npx -y @agentclientprotocol/claude-agent-acp`.

Respuestas reales capturadas que difieren o amplían la spec (gana el agente real):
- `session/new` devuelve `modes` (default, acceptEdits, plan, auto, bypassPermissions) y `configOptions` (`mode` y `model`, tipo select). El modelo se cambia con `session/set_config_option {sessionId, configId, value}`.
- Notificación no estándar `_auth/status_update`: se loguea y se ignora.
- `usage_update` trae `used`, `size` y `cost`. El resultado de `session/prompt` trae `usage` con tokens.
- `authMethods` llega vacío si el usuario ya está logueado en Claude Code.

## D14 · Prompt de sistema y contexto del prompt (M1)

- El prompt de sistema vive en `config/system_prompt.md` (editable, con `{mode}`, `{mode_rules}`, `{project_name}`…). Va como primer bloque de texto, envuelto en `<harness_context>`, del primer `session/prompt` de cada sesión y después de cada cambio de modo.
- Chips de contexto: escena abierta (`resource_link` con `file://`), selección (bloque de texto con rutas y tipos) y captura del viewport (bloque `image`, ≤ 1280 px). Se agregan solos y se pueden quitar. Un chip quitado no vuelve mientras no cambie la escena o la selección.

## D15 · Sincronización editor ↔ disco sin el diálogo de "modificado afuera" (M2)

Cuando el agente escribe un script que está abierto en el Script Editor:
- **Buffer limpio**: el harness reemplaza solo el tramo de líneas que cambió (`EditorSync.replace_buffer`), en una operación compleja del CodeEdit. Así se deshace con un Ctrl+Z y conserva cursor y scroll. Después hace `tag_saved_version` y "adopta" el recurso:
  - `source_code` = texto del disco;
  - `ResourceSaver.save` (alinea la fecha del recurso);
  - `reload(true)`;
  - `EditorFileSystem.update_file`;
  - por último emite a mano `EditorNode.resource_saved(script)`.
- **Por qué emitir `resource_saved`**: el Script Editor guarda la fecha de cada pestaña (`edited_file_data.last_modified_time`) y solo la actualiza al escuchar esa señal. `ResourceSaver.save` no la emite. Sin ella, al volver el foco al editor (`_test_script_times_on_disk`) recarga con `set_text` y agrega un paso de undo, o muestra el diálogo si el buffer tiene cambios. El comportamiento es el mismo en 4.4, 4.7 y 4.8.
- **Buffer con cambios sin guardar**: no se pisa. Queda un conflicto con tres acciones: ver diff, usar la del agente (deshacible) o mantener la mía (guarda el buffer a disco).
- **Detección**: hay tres vías:
  - `fs/write_text_file`;
  - tool calls de edición completados (usan `locations` o `rawInput.file_path`);
  - un watcher de mtime de los scripts abiertos cada 0,5 s, para escrituras que el agente hace por su cuenta.
- **Escenas abiertas**: no se recargan solas. Hay un aviso con "Recargar escena" (`EditorInterface.reload_scene_from_path`).
- **Alternativa descartada**: `ScriptEditor.reload_open_files()`. Existe solo en 4.8, pasa por el mismo `set_text` (pierde el undo fino y el cursor) y con cambios sin guardar abre el diálogo.

## D16 · Server MCP: polling en `_process`, sin thread de red (M3)

La spec §5 propone un thread de red que encola y un `_process` que despacha. Se implementó todo en el hilo principal: `TCPServer` y `StreamPeerTCP` se atienden con polling no bloqueante en `_process`. Razones:
- Las tools tienen que correr en el hilo principal igual (acceden al editor). Un thread solo movería bytes y obligaría a sincronizar colas.
- Con pocas conexiones locales, `poll()` + `get_available_bytes()` no bloquea y la latencia es de un frame. Con el editor sin foco son ~100 ms, aceptable para tools.
- Cada conexión procesa sus requests en orden (keep-alive y pipelining). Una tool en "ask" puede esperar el permiso con `await` sin frenar las otras conexiones.

Otros detalles:
- **Token**: 24 bytes aleatorios por cada arranque del plugin. Se compara en tiempo constante y se redacta en el Agent Log (`AgentLog.add_secret`).
- **Origin**: se rechaza cualquier origen que no sea local (protección contra DNS rebinding). Los clientes que no son navegador no lo mandan.
- **Sin SSE**: `GET /mcp` y `DELETE /mcp` → 405 (permitido por Streamable HTTP).
- **Puerto**: `godot_agent/mcp/port` en EditorSettings (0 = aleatorio). Es por usuario y no por proyecto, porque dos proyectos abiertos a la vez no pueden compartir puerto.
- **Bug encontrado**: el server se agrega en el `_enter_tree` del plugin y su `_ready` corre recién con el ready del plugin, después de `start()`. Por eso `set_process(false)` va en `_init` y no en `_ready`.

## D17 · Shim stdio en un proyecto vacío propio (M3)

Si el agente no anuncia `mcpCapabilities.http`, `session/new` recibe una entrada stdio con `OS.get_executable_path()` y `--headless --script mcp_stdio_shim.gd`. El shim no corre con `--path` al proyecto del usuario: cargaría sus autoloads y, como el cwd del agente es el proyecto, Godot lo encontraría solo. `StdioShimInstaller` copia el shim y un `project.godot` mínimo (con `flush_stdout_on_print`) a `user://godot_agent_mcp_shim/`, y el shim corre con `--path` a esa carpeta. URL y token van por `env`.

Claude Code (`claude-agent-acp` 0.94) anuncia HTTP, así que en la práctica usa la entrada http. El shim se prueba en `--godot-agent-mcp-test`.

## D18 · `get_errors` y `validate_scripts` (M3)

- **`get_errors`** junta tres fuentes en un solo stream numerado; la marca es el último número:
  - **4.5+**: un `Logger` propio (`OS.add_logger`). La clase no existe en 4.4, así que el script del logger se compila en runtime desde un string (`ErrorCollector.LOGGER_SOURCE`) y el addon parsea en todas las versiones.
  - **4.4**: el texto del panel Output, por líneas nuevas. Ahí el formato es `ERROR: archivo:línea - mensaje` y los mensajes llegan diferidos.
  - **Todas las versiones**: el árbol de errores del Debugger (errores del juego). Se lo reconoce por tener 2 columnas, raíz oculta y la hora en la primera columna.
- **`validate_scripts`**: corre un subproceso `godot --headless --path <proyecto> --script script_checker.gd -- <rutas>`, que carga cada script con `CACHE_MODE_IGNORE` y deja marcas `@@BEGIN`/`@@END` en stderr, el mismo flujo que los errores del motor. El parseo asocia cada `SCRIPT ERROR` a su `at: (res://…:línea)`. No toca el estado del editor ni las clases globales; usa AgentProcess, así que respeta D11 en 4.4. El loader devuelve el script aunque tenga errores de parseo: la fuente de verdad es la lista de errores.

## D19 · Tools de edición: undo por tool call y "↶ undo" con el menú del editor (M4)

- Cada tool de edición hace **una** acción de `EditorUndoRedoManager` llamada `Agente: …`, con `custom_context` en la raíz de la escena, para que caiga en la historia de esa escena. El resultado termina en `Paso de undo: «…»`.
- Los valores JSON se convierten al tipo de la propiedad con `mcp/tools/value_coercion.gd`. Acepta vectores como lista u objeto, colores `#rrggbb` o por nombre, enums por nombre, recursos `res://` (con chequeo de tipo) y la sintaxis de Godot (`"Vector2(1, 2)"`). Si una propiedad no existe, el error sugiere las 5 más parecidas.
- **Undo desde el dock**: `EditorUndoRedoManager` no expone `undo()` a GDScript, y llamar al `UndoRedo` de una historia directo desincroniza el manager. `editor/editor_undo.gd` dispara la opción Undo del menú principal: un `PopupMenu` hijo de un `MenuBar` con un ítem cuyo atajo es Ctrl+Z. Solo lo hace si la versión de la historia de la escena y la de la global no cambiaron desde la acción del agente; si no, avisa y no deshace.
- **Unión con el tool call**: el server MCP no conoce el `toolCallId` de ACP. La acción se une al tool call `mcp__godot__<tool>` que tiene los mismos argumentos (`rawInput`). Las acciones que llegan antes que su tool call esperan hasta 60 s.

## D20 · Autoload de playtest: baja cuando el juego ya leyó project.godot (M4)

- **Alta** en `EditorPlugin._build()`, solo si `run_scene` pidió el run (`RunTools.harness_requested`) o si `playtest_on_manual_runs` está activo. `play_custom_scene` llama a `_build()` de forma sincrónica, así que el flag se pone y se saca alrededor de esa llamada.
- `add_autoload_singleton` y `remove_autoload_singleton` **no guardan** `project.godot`: `autoload_add` sin undo solo cambia ProjectSettings en memoria. El juego es otro proceso que lee el archivo del disco, así que `PlaytestAutoload.register` y `unregister` llaman a `ProjectSettings.save()`.
- **Baja** en `EditorDebuggerSession.started`, que el editor emite cuando el juego manda su PID, o sea cuando ya cargó la configuración. También en `stopped`, en `stop_scene`, si el juego no llegó a arrancar, al deshabilitar el plugin, en `_export_begin` y al arrancar el plugin (huérfano). La ventana en la que el autoload está en disco dura lo que tarda en arrancar el juego. `tests/crash_check.sh` mata el editor justo después del alta y también con un run en curso: al reabrir, el autoload no está y `export_check` pasa.
- **Canal** `godot_agent:` entre `playtest/playtest_debugger.gd` (EditorDebuggerPlugin) y `playtest/runtime/playtest_probe.gd`:
  - juego → editor: `ready`, `frame` (PNG reescalado en el juego), `inputs_done`, `problem`;
  - editor → juego: `capture`, `inputs`.
- **Probe sin variables miembro**: en 4.7.2, con una `var` en el probe, el juego reportaba dos errores "get_node() with absolute paths from outside the active scene tree" con backtrace en `@implicit_new` del probe. Con el probe mínimo no pasaba, y sin la variable tampoco. No hay repro mínimo todavía; candidato para m7-01.
- **Pausa del debugger**: con un error de script el juego queda detenido (no termina). `run_scene` lo detecta con `EditorDebuggerSession.breaked` y lee el motivo y la ubicación del panel Stack Trace, porque la sesión no los expone.

## D21 · Pruebas que lanzan el juego: en Xvfb (M4)

En el escritorio, la ventana del editor de prueba le robó el foco al usuario: el debugger abrió `run_broken.gd` en la línea del error, quedó "bil" tipeado ahí y el guardado previo al siguiente run lo persistió. Las pruebas de editor corren con `tests/run_in_xvfb.sh`: Xvfb sin GPU, editor y juego con `--rendering-driver opengl3` (llvmpipe). El juego recibe sus argumentos por `editor/run/main_run_args`, que `run_check.gd` pone solo en memoria cuando existe `GODOT_AGENT_TEST_RUN_ARGS`. Bajo Xvfb el editor suma errores `BadWindow` de X11 y el juego un warning de V-Sync, así que la prueba exige que no haya errores **del juego**, en vez de exigir cero entradas.

`tests/crash_check.sh` se corre con `setsid -w`: matar el editor con `OS.kill` llegó a terminar la shell que lo había lanzado.

## D22 · Qué cuota reporta Claude Code por ACP (M1, spec §10.1)

Verificado con `claude-agent-acp` 0.94.0 (SDK 0.3.303) y Claude Code real (`tests/claude_smoke_check.gd`, que imprime el canal `quota`), y leyendo el código del adapter.

- **Cuota del plan: sí, con hora de reinicio.** Cuando el SDK emite un `rate_limit_event` (al cambiar la info de límites, en la práctica en el primer turno de la sesión), el adapter manda un `usage_update` extra con `_meta["_claude/rateLimit"]` = `SDKRateLimitInfo`. Ejemplo real:

  ```json
  {"status": "allowed", "rateLimitType": "five_hour", "resetsAt": 1792572000,
   "isUsingOverage": false, "overageStatus": "rejected", "overageDisabledReason": "org_level_disabled",
   "unifiedWindows": {"five_hour": {"utilization": 0.63, "resetsAt": 1792572000},
                      "seven_day": {"utilization": 0.47, "resetsAt": 1793062800}}}
  ```

  - `status`: `allowed` | `allowed_warning` | `rejected`.
  - `resetsAt`: unix en segundos.
  - `utilization`: fracción 0–1.
  - `unifiedWindows` trae la ventana actual (`five_hour`) y la semanal (`seven_day`); no está en el `.d.ts` del SDK, pero es lo que llega. `utilization` y `surpassedThreshold` sueltos sí están tipados, pero en el estado `allowed` no vinieron.
  - El mapeo de §10.1: ventana actual = `unifiedWindows.five_hour`, semanal = `unifiedWindows.seven_day`, y el estado sale de `status`.
- **Tokens de la sesión**: cada `usage_update` trae `used`/`size` (contexto). El último del turno trae además `cost: {amount, currency}`. No son cuota y no se usan para estimarla.
- **Límite alcanzado** (sacado del código: no se puede provocar a propósito). Un cliente sin la extensión `sessionFailure` de JetBrains AIR (`_meta.jetbrains.air`, que el harness no anuncia porque no es ese cliente) recibe:
  1. el texto sintético del SDK como mensaje del agente, con uno de los `USAGE_LIMIT_ERROR_PREFIXES` ("You've hit your…", "You've reached your…", "You're out of usage credits"…);
  2. el `session/prompt` termina con un error JSON-RPC `-32603` (`RequestError.internalError`), con `data.errorKind` cuando el SDK lo clasificó (`rate_limit`, `billing_error`…) y el texto del resultado en el mensaje;
  3. antes, normalmente, un `usage_update` con `status: "rejected"`.

  `QuotaMonitor` mira las tres cosas. Los prefijos están en `config/quota_patterns.txt` (editable), anclados al principio de línea. Un patrón suelto como "rate limit" dispararía con la prosa del agente.
- **Prohibido y respetado**: no se consulta el endpoint de uso del adapter (`/usage`, `usage-markdown.js`) ni se leen credenciales o archivos de `~/.claude`.

## D23 · Revisión: de dónde salen los hallazgos y cómo se muestran (M5, spec §9.4)

- **Fuente**: el texto del agente en cada turno del modo Revisar. Las reglas del modo piden un bloque ```json `{"findings": […]}` con `path` relativo al proyecto y `line` desde 1. `review/findings_parser.gd` es tolerante:
  - JSON con o sin fence, con prosa alrededor, comas finales y nombres de campo alternativos;
  - `ruta.gd:12` en `path`;
  - severidades en castellano o inglés.

  Lo que no se puede normalizar se descarta, sin cortar el resto.
- **Una revisión vigente**: cada turno de Revisar con un bloque `findings` reemplaza la revisión anterior, y un bloque vacío la limpia. Las reglas del modo le piden al agente que repita todos los hallazgos vigentes. "Preguntar" sobre un hallazgo manda el turno sin recolectar hallazgos, así que la respuesta no pisa la revisión.
- **Líneas fijas**: las marcas usan las líneas del texto revisado. Si el archivo cambia después, se vuelve a revisar; no hay seguimiento de ediciones.
- **Marcas en el Script Editor**: el fondo de la línea se dibuja desde un gutter propio (al final, junto al código) y no con `set_line_background_color`, porque `ScriptTextEditor` borra esos colores cada vez que valida el script. Se anotan los editores que fueron el actual. No se puede emparejar `get_open_script_editors()` con `get_open_scripts()`: cuando hay archivos de texto abiertos, los índices no coinciden.
- **Tarjeta**: es un overlay hijo del `CodeEdit`, debajo de la línea. No empuja el código, porque `TextEdit` no tiene widgets en línea. Se abre al hacer clic en la marca o al elegir el hallazgo en el dock.
- **Banda**: "Revisión del agente · solo lectura" va en la barra de estado del `CodeTextEditor`, y como overlay si no se la encuentra. Los conteos por archivo en la lista de scripts quedaron afuera: esa `ItemList` es interna del editor.
- **Plan mode de Claude Code**: Revisar pone al agente en `plan`. En ese modo Claude Code ejecuta comandos de solo lectura y escribe su propio archivo de plan, fuera del proyecto, sin mandarle `session/request_permission` al cliente. Los cambios al proyecto siguen pasando por la política: en Revisar, `edit_*`, `shell` y `project` se deniegan.
- **Arreglos**: "Aplicar arreglo" y "Arreglar en modo Construir" pasan a Construir (`send_in_mode`). Si el turno termina con `end_turn`, esos hallazgos salen de la revisión. Un turno espera a que termine `session/set_mode` antes de mandarse, pero el estado pasa a PROMPTING enseguida, así que la UI no lo da por terminado.

## D24 · One-shot: checkpoints, presupuestos y cuota (M6, spec §10 y §10.1)

- **Checkpoints acotados al proyecto**: todos los comandos git van con `-C <proyecto>` y el pathspec `-- . :(exclude).godot`, aunque el repo no ignore `.godot/`. Si el proyecto vive dentro de un repo más grande, lo de afuera no se toca.
  - "Volver acá" equivale a un `reset --hard` limitado a esa carpeta: `reset --mixed <sha>`, `checkout -- .` y `clean -fd`, con el mismo pathspec.
  - Solo corre si la rama actual es la del agente. Devuelve las rutas cambiadas, para que el editor las recargue: las escenas abiertas se recargan directamente (el usuario pidió volver) y los scripts abiertos pasan por EditorSync, que no pisa los cambios sin guardar.
- **WIP en la rama del agente**: si había cambios sin commitear, el commit "WIP antes del one-shot" va en `agent/<fecha>`, después de crearla. La rama del usuario no recibe commits; la UI pide confirmación antes.
- **Nunca merge ni push**: "Aceptar todo" hace un commit final en la rama del agente y la deja para que el usuario la mergee. Los commits van con `--no-verify` (son del harness, no del usuario) y, si el repo no tiene `user.email`, con una identidad de fallback que solo se pasa por `-c`, sin escribir en la config.
- **Checkpoint por tarea**: el harness no puede saber cuándo "empieza" una tarea si no es por el plan de ACP. El checkpoint se crea cuando una entrada pasa a `in_progress`. El prompt inicial le pide al agente que use su herramienta de plan o de tareas (TodoWrite o TaskCreate/TaskUpdate en Claude Code: el adapter las convierte en `plan`) y que marque así cada tarea.
- **Agente sin plan**: en la primera corrida real (Pong, 4.8), Claude Code no usó ninguna herramienta de plan, y el harness insistió tres veces con "la próxima tarea pendiente es «la tarea pendiente»". Ahora, si nunca llegó un `plan`:
  - se crea un checkpoint por cada playtest completado ("cpN: Playtest #k");
  - lo que falta sale de los checks. Si al fin de turno alguno no está en `pass` (o no reportó ninguno), el harness sigue con "quedan checks sin pasar: «X» (pending)…", hasta `MAX_IDLE_CONTINUES` turnos seguidos sin un playtest nuevo. Termina cuando todos pasan. En la segunda corrida real, Claude cerró el turno a mitad de camino ("pruebo si add_node acepta un shape inline") con un check en `fail` y otro en `pending`: tomar el fin de turno como final dejaba el juego a medias;
  - la reanudación dice "continuá con el objetivo desde donde quedaste".
- **Tokens del presupuesto** = `inputTokens + outputTokens + cachedWriteTokens` del `usage` de cada `session/prompt`. Las lecturas de caché se dejan afuera: cuestan una fracción y en una sesión larga dominarían la cuenta, de modo que el presupuesto se agotaría sin que el agente haga casi nada. Esto no es la cuota del plan: la cuota sale solo de lo que informa el agente (D22).
- **Tiempo** = tiempo activo (En curso y Cerrando). Pausado, Pausado por cuota, Limitado y "Listo para retomar" no cuentan.
- **Al 100 % de un presupuesto**: `session/cancel` del turno en curso y un turno de cierre que pide el reporte final y los checks. Al 80 %, un aviso en el chat y en la actividad.
- **Pausa por cuota**: el turno no se corta a mitad de una tarea. Cuando el plan pasa la siguiente tarea a `in_progress` con la cuota en "pausa programada", se crea su checkpoint y se cancela el turno. Así el estado guardado es el del final de la tarea anterior y la reanudación empieza esa tarea de nuevo.
- **Reanudar**: "Continuá con el plan desde la tarea «X»; el estado está en el checkpoint cpN (…)". Si la sesión se perdió y está en el historial (M7), se reabre con `session/load` y sigue con el mismo prompt de reanudación. Si el agente no lo soporta, se abre una sesión nueva con un resumen (objetivo, plan con estados, checks y checkpoints).
- **Auto-continuación**: si el turno termina con tareas pendientes, se manda "Seguí con el plan…". Después de 3 turnos seguidos sin completar ninguna tarea, el One-shot se da por terminado ("el agente dejó de avanzar").
- **Plan mode no se usa en One-shot**: Claude Code en `plan` escribe su propio archivo de plan sin pedir permiso y no edita el proyecto (D23). One-shot usa el modo `default`, y la política de permisos de One-shot decide (spec §7).

## D25 · Settings e historial (M7, spec §9.5 y §11)

- **Settings en un diálogo propio**, no en Project Settings: una sección ahí escribiría en `project.godot` (D5). Se edita una copia y todo se guarda junto al aceptar, después de validar.
  - La matriz de permisos guarda solo lo que difiere de la spec, así un cambio de defaults en el addon llega a los proyectos.
  - Se aplica en caliente lo que el plugin ya tiene vivo (política, carpetas de `fs/*`, límites de las tools, defaults del One-shot). Puerto, color y ubicación del dock se aplican al reabrir el editor.
  - Regenerar el token reinicia el server en el mismo puerto. Las sesiones abiertas se quedan con el token viejo y pierden las tools `godot.*` hasta abrir una nueva.
  - Un agente sin comando es válido: queda listado, pero no arranca (el default de Codex viene así).
- **Historial en JSON Lines y escrito en un worker**: un archivo por sesión, más un índice. Reescribir el registro entero en cada turno costaba 49 ms con 3,5 MB; agregar solo las líneas nuevas cuesta 0,2 ms (p50).
  - Aun así, con el disco ocupado abrir el archivo llegó a 600 ms. Por eso las escrituras van a una cola que procesa una sola tarea del `WorkerThreadPool`, en orden. Leer (menú, reanudar) y cerrar el plugin esperan a la cola.
  - El worker usa un `Callable` sobre el script, no sobre el objeto, así no depende de que el historial siga vivo.
  - Una línea cortada por un cierre a mitad de escritura se saltea al leer, y la próxima escritura empieza en una línea nueva.
- **Replay sin efectos**: mientras se rearma una conversación, `SessionModel.replaying` es true. Los listeners con efectos (sincronización de archivos del plugin, checkpoints y playtests del One-shot) lo ignoran.
- **Qué se guarda**: lo necesario para volver a armar la conversación. No se guardan:
  - capturas (cientos de KB en base64);
  - `rawOutput`;
  - estado de la sesión (uso, comandos, modos);
  - el prompt de sistema ni los adjuntos de los prompts.

  Los textos de las tools se recortan. Los ids vienen del agente, así que se valida que no traigan rutas.
- **Reanudar**: la conversación sale del archivo, no del replay de `session/load`, porque el adapter de Claude reenvía el prompt de sistema como mensaje del usuario. Las notificaciones del replay llegan antes de la respuesta y se descartan solas: `model.session_id` recién se asigna con la respuesta.

## D26 · Completado local: índice, puntajes y enganche al CodeEdit (M8a, spec §16)

- **Módulo aparte** (`addons/godot_agent/completion/`): no usa ACP ni el agente. Comparte Settings (`godot_agent/completion/*` y `ProjectConfig.completion_*`) y el Agent Log (canal `cmp`, sin código).
- **Índice en un worker, publicado entero**:
  - `ProjectIndex.build` lee `.gd` y `.tscn` línea por línea en `WorkerThreadPool` y arma un objeto nuevo. El hilo principal lo reemplaza cuando el worker termina; nunca lo modifica.
  - El build siguiente reutiliza lo que no cambió (mismo mtime). El mtime tiene resolución de 1 s, así que lo modificado hace menos de 2 s se vuelve a leer siempre.
  - ClassDB, ProjectSettings y la escena abierta se leen en el hilo principal, con caché.
  - **Sin persistencia**: con 200 scripts y 60 escenas el build tarda unos 180 ms en el worker, por debajo del 1 s que pide la spec.
- **Buffer sin guardar**: cuando el buffer queda quieto 800 ms, el controller lo manda al índice sin la línea del caret, que está a medio escribir. Si entrara, una línea cortada se sugeriría a sí misma.
- **Corpus**: por defecto excluye `addons/` (`ProjectConfig.completion_exclude`). La estructura (escenas, nodos, señales) se indexa siempre, también en `addons/`.
- **Recuperación**: las líneas normalizadas (sin indentación y con los espacios colapsados) se ordenan. Las que empiezan con lo escrito forman un rango, que se encuentra con `bsearch`.
  - Si el rango tiene más de 400 líneas, el prefijo es ambiguo y no se sugiere nada.
  - Puntaje: `raw` = Σ ocurrencias × cercanía (mismo archivo 3, misma carpeta 2, resto 1) × recencia del archivo (0,5 a 1, con semivida de 7 días).
  - El puntaje final es `raw/Σraw × (1 − e^(−raw/1,5))`. El segundo factor exige evidencia: una línea que aparece una sola vez en otro archivo no llega al umbral (0,49 < 0,5), aunque sea la única opción. Dos apariciones, o una en el mismo archivo, sí. **M8b bajó la escala a 1** (una aparición lejana da 0,63 y alcanza): ver D27.
- **Ranker**:
  - Una regla que aplica gana sin pasar por el margen. Sus candidatos ya vienen ordenados (por ejemplo, el primer hijo no declarado).
  - Para el resto: umbral 0,5 y margen 0,12 sobre el primer rival.
  - Dos candidatos donde uno es prefijo del otro no compiten. Si están empatados, gana el más largo.
  - Los duplicados entre fuentes se combinan con `1 − Π(1 − s)`.
- **Historial de la sesión**:
  - Una línea entra al historial cuando el caret la deja después de editarla, o cuando se acepta una sugerencia.
  - La coincidencia más reciente vale 0,8, y las dos siguientes 0,6 y 0,5.
- **Teclas**: alcanza con la señal `gui_input` del CodeEdit más `accept_event()`. La señal se emite antes del manejo propio del CodeEdit, y el Script Editor no tiene atajos sobre Tab ni Esc. No hizo falta el fallback por `_input`.
  - Verificado con eventos de teclado reales en el Script Editor de 4.4.1, 4.7.2 y 4.8-beta1: Tab acepta, Esc descarta, y Tab sin sugerencia indenta.
  - Con el popup nativo abierto (`get_code_completion_selected_index() != -1`), Tab es del popup.
- **Posición del ghost text**: la x sale de `get_caret_draw_pos()`. La y es la de la fila, de `get_rect_at_line_column`.
  - Al final de la línea, `get_rect_at_line_column(línea, col)` devuelve el carácter anterior al caret (medido en 4.4 y 4.8). Con el último espacio, eso dejaba el ghost text un carácter antes.
  - El ghost text solo se dibuja con el caret en su ancla, porque mover el caret lo invalida. Por eso la x del caret siempre es la correcta.
  - Se dibuja con un `TextLine` recortado al área de texto (sin el minimapa ni la barra de scroll), con la fuente y el tamaño del editor (incluye zoom). El color es el de comentarios del tema, con alpha 0,75.
- **Disparo**: `text_changed` y `caret_changed` llegan diferidos y en cualquier orden. El controller compara contra el último estado visto (línea, columna y `get_version()`), así procesa cada cambio una sola vez.
  - Cada cambio invalida la respuesta en vuelo, porque sube el número de secuencia.
  - El debounce lo vence `tick(now)`, llamado por el servicio cada frame. Los tests usan un reloj simulado.
- **Fixture**: `tests/completion_fixture/` tiene `.gdignore` para que el editor del repo no lo importe ni registre sus `class_name`. Su input map y sus autoloads están en `project_settings.cfg`, que tiene el formato de `project.godot`.
- **Lo que no se adivina**: sin nada escrito y con varias opciones posibles (rutas, acciones, grupos, recursos), no se sugiere. `@onready` y los virtuales sí proponen la primera, porque el orden (el primer hijo no declarado, los virtuales comunes primero) ya es una buena apuesta. Un tipo de nodo que no se puede saber se omite: `name = $Path` antes que un tipo equivocado.
- **Cancelación y recarga**: `wait()` levanta un flag que el walker del build revisa, y el índice reemplazado se libera en el worker para no pagar su destrucción en el hilo principal. Riesgo conocido: si el plugin se recarga (`@tool`) con un build en curso, el worker termina con los scripts viejos. Godot no permite matar una tarea del pool, así que solo se acorta con el flag.

## D27 · Completado local: calidad (M8b, spec §16.2–§16.9)

- **Lexer GDScript propio** (`local/gd_lexer.gd`): una regex por línea, cada token con su espacio adelante (`" foo"` y `"foo"` son tokens distintos, así la generación reproduce el espaciado del proyecto). Sin comentarios; `<indent>`/`<dedent>` por nivel y `\n` al final de la línea; el interior de los strings multilínea no cuenta. La regex se compila al cargar el script (`static var`): compilarla la primera vez que se usa era una carrera entre el worker y el hilo principal.
- **n-gram de orden 4 con stupid backoff (0,4)**. Con el umbral por paso de 0,5, un paso que viene de un contexto más corto nunca alcanza (0,4 × p < 0,5): en la práctica genera solo el contexto completo de 3 tokens. Se probó comparar el umbral con la probabilidad sin el factor de backoff y el set de evaluación no cambió, así que quedó así:
  - Se entrena en el worker del índice con todos los `.gd` del corpus. Las claves son enteros (20 bits por id, el más cercano abajo, el largo en los bits altos), no strings, para que armar la clave no cree strings en cada paso.
  - **Clase número**: en los contextos, `1.5` y `200` son `<num>`. En la salida se genera el número del corpus. Sin esto, cada constante distinta partía la estadística.
  - **Actualización por archivo, copy-on-write**: si cambió hasta el 30 % de los archivos, el modelo nuevo copia los conteos y resta/suma solo lo de esos archivos; el anterior queda intacto porque el hilo principal lo puede estar leyendo. Si no cambió nada, se reutiliza el mismo objeto. Con más cambios, se reentrena. El vocabulario (`words`, `context_ids`) también se copia: en Godot 4 un `Packed*Array` asignado se comparte, y el worker le agregaba tokens al del modelo publicado (lo encontró la revisión).
  - **Sangría**: los `<indent>`/`<dedent>` salen de una pila de anchos, así sirven tabs, 2 o 4 espacios. Para la sangría relativa de las líneas (bloques, línea siguiente) cada archivo del corpus usa su propia unidad (la sangría más chica que tiene) y el pedido usa la del editor (`indent_size`).
  - **Generación**: token a token hasta el fin de línea, mientras cada paso tenga probabilidad > 0,5, la acumulada > 0,3 y el contexto que decide haya aparecido al menos 2 veces. Ante un empate, para: seguir con el primero de dos empatados producía bucles (`x.x.x…`) y adivinanzas. El puntaje es el producto de los pasos, así que una línea larga y segura compite con la recuperación.
  - Cachés en el hilo principal: estadísticas por contexto y, para el token a medio escribir, la lista ordenada de continuaciones con `bsearch`. Con eso el p95 de una consulta bajó de 3,7 ms a 0,7 ms.
  - Una salida sin ningún nombre, número o string (solo `(` o `%`) no se muestra.
- **Recuperación ampliada** (`local/line_index.gd`): el índice guarda además la secuencia de líneas de cada archivo (con su sangría), así una línea encontrada sabe qué la sigue.
  - **Línea siguiente**: en una línea vacía (solo indentación) después de una línea con código, se sugiere lo que sigue a esa línea en el proyecto, con su sangría relativa. Una sangría menor que la ya escrita no se sugiere (habría que borrar).
  - **Bloques**: la línea elegida se extiende con las siguientes mientras todas sus apariciones (al menos 2) sigan iguales, hasta una línea en blanco, una sangría menor que la del comienzo, el máximo de líneas (8) o la línea que ya está debajo del caret.
  - **Adaptación de un identificador**: solo si ninguna línea empieza con lo escrito (`has_prefix`): una línea ya completa o un prefijo ambiguo no se reemplazan con la de un pariente. Si nada empieza con lo escrito pero sí con lo escrito cambiando un nombre (`enemy_health` ↔ `player_health`), se sugiere esa línea con la misma sustitución en el resto, en snake_case, PascalCase y MAYÚSCULAS. Vale 0,9 de una coincidencia exacta y no se extiende a bloque (traería el nombre viejo).
  - Se bajó la escala de soporte de 1,5 a 1: en el set de evaluación, las líneas con una sola aparición lejana acertaban casi siempre.
- **Reglas que se abstienen (veto)**: si una regla reconoce el contexto pero no puede elegir (sin nada escrito y varias acciones, grupos, recursos o `extends`), devuelve un veto y ninguna otra fuente sugiere ahí. Antes, la recuperación o el n-gram ocupaban ese lugar con una línea de otro contexto: varios de los falsos positivos del set de evaluación eran eso.
- **Convenciones de `@onready`**: el nombre de la variable sale de cómo nombra el proyecto esa misma referencia en otros scripts (si escribe `@onready var anim: AnimationPlayer = $AnimationPlayer`, se propone `anim`) y de los sufijos que suele quitar (`Component`); los hijos directos y los `%` únicos van antes que los nietos; lo que la clase base ya declara (herencia por `extends "…"` o `class_name`) no se vuelve a proponer. `load("` se resuelve por el nombre de la variable (`var hit_sound := load("` → el recurso que se llama `hit_sound`) o se abstiene.
- **Post-procesado multilínea** (`post_processor.gd`): marcadores FIM y stops, recorte de bloques (sangría menor, línea en blanco, máximo, línea igual a la de abajo), solapamiento con el suffix, sangría del editor (tabs o espacios, del `CodeEdit`) y el chequeo de paréntesis y comillas sobre todas las líneas. Con algo a la derecha del caret, la sugerencia es de una línea.
- **Ghost text multilínea**: Godot no tiene líneas virtuales. La primera línea va inline y las demás en una caja casi opaca (0,96) desde el borde del área de texto, debajo de la línea del caret. Si abajo no entran y arriba hay más lugar (caret en la última fila visible), la caja va arriba.
  - Todo se dibuja en un **canvas item propio hijo del CodeEdit**: lo dibujado desde la señal `draw` queda debajo del texto en 4.8, y el `")` del autocierre se veía encima de la sugerencia (el tapado de M8a no funcionaba; lo mostró una captura ampliada). Un hijo siempre se dibuja después. El overlay se limpia en cada `draw` y se libera al soltar el CodeEdit.
  - El fondo sale del stylebox `normal`: el Script Editor deja `background_color` transparente.
  - El overlay se recorta al área de texto (sin gutter ni barras de scroll): con scroll horizontal, la columna 0 de la caja queda a la izquierda de los números de línea. Queda por encima del hint de argumentos propio del CodeEdit (se dibuja en el mismo CodeEdit): aceptado, la sugerencia se ve igual que antes de M8b.
- **Ctrl+→** acepta la siguiente palabra (con los espacios o el salto de línea que la preceden) en su propio paso de undo; el resto queda a la vista con el ancla en el caret nuevo.
- **Caché de sugerencias**: LRU de 64 por (ruta, hash del texto, línea, largo del prefijo, manual, generación del proveedor). Volver a una posición ya vista (borrar y retipear) responde sin consultar. La generación sube con un índice nuevo, con ProjectSettings (input map, autoloads), cuando cambian los nodos de la escena abierta sin guardar y con el historial: sin ella, la caché devolvía una sugerencia vieja después de agregar una acción o renombrar un nodo. Además se vacía al cambiar Settings.
- **Líneas muy largas** (un literal de datos): ninguna clave del índice pasa de 240 caracteres, así que con una línea de más de 480 no se busca, y del contexto del n-gram se tokeniza solo el final de cada línea. Antes, 20 000 caracteres costaban ~18 ms por tecla.
- **Teclas en el mismo frame**: `text_changed` y `caret_changed` llegan diferidos, así que Tab justo después de otra tecla aceptaba la sugerencia vieja. El handler de teclas sincroniza el estado antes de decidir.
- **Corpus extra** (`godot_agent/completion/extra_corpus`): carpetas de otros proyectos propios que solo entrenan el n-gram. No aportan líneas a la recuperación, porque sus nombres no existen en este proyecto.
- **Set de evaluación** (`tests/completion_eval/`): un juego chico escrito para esto (33 scripts, 20 escenas) y 48 casos en cuatro grupos: contexto de Godot, líneas con parientes cercanos, línea siguiente y API de Godot con forma parecida. El runner corta el archivo en el caret, lo pasa como buffer sin guardar y corre cada combinación de fuentes. Los umbrales por defecto salen de ahí:

  | Fuentes | Mostradas | Correctas | Exactas | FP |
  |---|---|---|---|---|
  | reglas + recuperación, antes de M8b | 17 | 11 | 11 | 6 |
  | reglas + recuperación | 19 | 17 | 17 | 2 |
  | reglas + recuperación + n-gram | 20 | 18 | 17 | 2 |
  | n-gram solo | 5 | 5 | 2 | 0 |

  Correcta = lo mostrado es el comienzo de lo esperado. Los 2 FP que quedan son ambiguos de verdad (`"x%d" % GameState.lives` contra `% lives`; `Vector2(1.2, 1.2), 0.08)` contra `Vector2.ONE, 0.12)`). Con soporte mínimo 1 en el n-gram aparecen más FP: se descartó. `test_completion_eval` exige que el n-gram sume correctas sin sumar FP y una precisión de al menos 0,85.
- **Costo**: el n-gram triplica el build del índice (unos 800 ms con 200 scripts, todavía bajo el segundo de la spec y en el worker). El lexer es la mitad de eso, y el límite es el motor de regex. La consulta sigue en p95 de unos 2 ms.

## D28 · Completado con LLM opcional (M8c, spec §16.1, §16.7–§16.10)

- **Endpoints, verificados contra la documentación oficial y el código de cada servidor** (octubre de 2026). Cada perfil tiene `kind`, URL, modelo, nombre de la variable de entorno con la key, plantilla FIM opcional, stops, temperatura y máximo de tokens (`completion/llm/llm_profile.gd`, `llm_client.gd`):
  - **Ollama** `POST /api/generate` con `stream: false` y `keep_alive`. El FIM nativo es el campo `suffix`, pero un modelo cuya plantilla no lo soporta responde 400 «does not support insert». Con una plantilla FIM en el perfil se manda `raw: true` y el prompt ya armado; `raw` ignora `suffix`. Las duraciones de la respuesta vienen en nanosegundos. Default: `qwen2.5-coder:1.5b-base` (los tags `-base` traen FIM).
  - **llama.cpp** `llama-server` `POST /infill` con `input_prefix`, `input_suffix` e `input_extra` (`[{filename, text}]`, ahí va el contexto del proyecto). El puerto por defecto ahora es 9931 (antes 8080); `/health` para comprobarlo.
  - **Codestral** `POST /v1/fim/completions` en `https://api.mistral.ai` (el host de la spec oficial; `codestral.mistral.ai` no figura y no se usa). El body tiene `additionalProperties: false`: solo se mandan campos del schema. Bearer.
  - **OpenAI-compatible** (LM Studio, vLLM, llama.cpp en modo OpenAI) `POST /v1/completions`. `suffix` no es portable entre servidores, así que el perfil nuevo trae la plantilla de Qwen y se manda el prompt armado; sin plantilla se manda `suffix`. Hasta 4 stops (límite del schema de OpenAI).
  - **Gemini** `POST /v1beta/models/{modelo}:generateContent` con el header `x-goog-api-key`. No tiene FIM: una instrucción de sistema pide solo el código que va en `<CURSOR>`; se quitan cercos de Markdown y las partes `thought`; una respuesta bloqueada es "sin sugerencia". Hasta 5 stops. Default `gemini-3.5-flash-lite`. Es **experimental** en Settings: más lento y menos preciso que un FIM. No se manda `thinkingLevel` (no se pudo verificar para Flash-Lite) y la temperatura se ignora desde 3.6 Flash.
  - Plantillas FIM conocidas para el campo del perfil: Qwen (`<|fim_prefix|>…<|fim_suffix|>…<|fim_middle|>`), CodeLlama (`<PRE> … <SUF>… <MID>`), StarCoder (`<fim_prefix>…<fim_suffix>…<fim_middle>`) y DeepSeek (con los caracteres de ancho completo `<｜fim▁begin｜>`). Con la de Qwen se agregan sus tokens especiales a los stops.
- **Keys**: el perfil guarda el nombre de la variable de entorno (`MISTRAL_API_KEY`), nunca el valor; se lee con `OS.get_environment` en cada pedido; si la variable está vacía no se manda nada y el indicador muestra el error. Codestral y Gemini exigen la variable. El JSON de perfiles se puede editar a mano en Configuración del editor: un valor de otro tipo queda en el default. Settings solo acepta un nombre de variable (`^[A-Za-z_][A-Za-z0-9_]*$`) que no parezca una key (20 caracteres o más con mayúsculas, minúsculas y dígitos, como `AIzaSy…`). Un perfil remoto (no `localhost`/`127.0.0.1`/`::1`) muestra «el código alrededor del cursor se envía a <host>».
- **Qué se manda**: prefix y suffix recortados (4000/1000 caracteres por defecto, cortados en un salto de línea) y un bloque de comentarios `#` con lo que ProjectContext sabe del archivo (nodos de la escena, clase base, clases del proyecto referenciadas, autoloads, acciones sin `ui_*`, grupos), en ese orden de prioridad y dentro de un presupuesto de tokens estimado a 4 caracteres por token (2000 por defecto).
- **Sin redirecciones y con límite de body**: HTTPRequest sigue hasta 8 redirecciones reenviando el body y los headers (la key incluida) al host del `Location`; con `max_redirects = 0` la URL del perfil tiene que ser la final. El body se limita a 1 MB porque el JSON se parsea en el hilo principal. Un error HTTP muestra solo los campos de mensaje conocidos (`error`, `error.message`, `message`, `detail`, `detail[0].msg`), nunca el body: un 422 de FastAPI (vLLM) repite el prompt.
- **Un HTTPRequest por editor, sin hilos**: `cancel_request()` con `use_threads` espera al hilo, y con un servidor en el mismo hilo principal (el falso de los tests, o un proxy local en el editor) se trababa. Sin hilos no bloquea: HTTPRequest es asíncrono igual. `cancel_request()` no emite `request_completed`, así que la cancelación se avisa a mano. Un contador de generación descarta una respuesta que llega después de cancelar.
- **Modos** (`completion/mode`): solo local (default), híbrido y solo LLM.
  - En híbrido lo local sale como siempre (mismo debounce, mismo frame). El LLM se pide solo si no hubo nada local, cuando venció su propio debounce (200 ms desde la última tecla) y sin otra request en vuelo. Tipear, mover el caret, Esc o perder el foco cancelan la request; una respuesta se muestra solo si el texto, el caret y la secuencia siguen iguales y no apareció algo local mientras tanto.
  - Alt+\ en híbrido va directo al LLM (lo local ya se ve sin pedirlo).
  - Solo LLM usa el debounce del LLM y no consulta lo local.
  - La respuesta pasa por el mismo post-procesado que lo local (stops del perfil, recorte de bloques, solapamiento con el suffix, paréntesis) y entra en la caché con clave propia.
- **Marcador**: la sugerencia del LLM lleva un punto chico después del texto (se puede apagar), para saber de dónde viene sin mirar el log.
- **Indicador** en la barra de menús del Script Editor (el primer HBoxContainer con MenuButton): «● Completado: local / híbrido · modelo / LLM · modelo», en verde (activo), ámbar (pensando), rojo (error, con el mensaje en el tooltip) o gris (apagado). Un clic lo prende o lo apaga; también **Alt+Shift+\\** desde cualquier lugar del editor.
- **Métricas** por fuente en la sesión (`completion_metrics.gd`): latencia p50/p95 de las últimas 200 consultas, mostradas, aceptadas (enteras o por palabra) y errores. Se ven en Settings → Completado y en el Agent Log cada 10 sugerencias. El canal `cmp` registra fuente, latencia, caracteres de entrada y salida, resultado y caché, nunca código, salvo con `completion/log_raw` prendido.
- **Settings sin reiniciar**: Settings → Completado escribe en EditorSettings (usuario) y en `project_config.tres` (on/off y exclusiones del proyecto), y el servicio reconfigura cada editor abierto: modo, perfil, proveedor y caché.
- **Pruebas sin endpoints reales**: `tests/fake_llm_server.gd` es un servidor HTTP mínimo en 127.0.0.1 con respuestas y demoras por ruta. Prueba los cinco formatos de pedido y respuesta, la cancelación, los errores HTTP y la conexión rechazada, y en el editor real el modo híbrido de punta a punta. No hubo Ollama ni llama.cpp instalados para probar contra uno real.

## D29 · Tope del tamaño mínimo de las superficies (después de M8c)

- **Síntoma** (primer proyecto real, 4.8-beta1): al activar el plugin, toda la UI del editor quedaba metida en una franja de ~600 px de ancho y el resto de la ventana vacía. El editor respondía, pero los paneles inferiores y el FileSystem quedaban fuera de la ventana.
- **Causa**: un `Label` con autowrap dentro de un contenedor oculto nunca se acomoda. Queda con el ancho de una letra (13 px) y su mínimo pide un alto de miles de píxeles. Los slots de docks del editor cuentan también las pestañas ocultas para su mínimo, así que el dock Agent (con el banner de presets de export sin filtro, que el proyecto de prueba no mostraba) pedía 3592 px de alto y el editor entero se desacomodaba.
- **Arreglo**: cada superficie (dock, panel inferior, main screen; con EditorDock y con la API vieja) se monta dentro de `ui/min_size_guard.gd`. Es un Container que reporta el mínimo de su contenido con un tope de 320×240 px (por la escala del editor) y le da a su contenido todo su rect. Mientras está oculta, lo que no entra se recorta; al mostrarse, el contenido toma el ancho real y los labels vuelven a un alto normal. Es genérico a propósito: cualquier label que se agregue después queda cubierto.
- Verificado con una copia del proyecto que lo mostró (dock oculto y dock como pestaña elegida) y con `test_min_size_guard`, que reproduce el label de miles de píxeles en una pestaña oculta.

## D30 · Enter envía en el composer (cambia el atajo de la spec)

- Pedido del usuario al probarlo: **Enter** envía y **Ctrl+Enter** baja de línea; también **Shift+Enter**, que es lo habitual en los chats. Con la lista de `/` o `@` abierta, Enter elige la opción y no envía.
- Al probarlo apareció un bug previo: elegir un comando de la lista dejaba `compact` sin la `/`, y el agente lo recibía como texto. El CodeEdit reemplaza la `/` junto con la palabra, pero no la `@` (igual en 4.4.1, 4.7.2 y 4.8-beta1). Ahora la opción del comando incluye la `/`.
- Tipear `/` o `@` no abría la lista: el CodeEdit solo no pide completado al escribir un prefijo (en el Script Editor lo hace un timer del editor), y solo lo pedía el botón **@**.
- Además, la lista del CodeEdit se dibuja dentro del texto (72 px) y mostraba una sola fila. Se reemplazó por una lista propia arriba del texto (`ui/dock/suggestion_list.gd`, un Tree de dos columnas sin foco), como la del chat de VS Code: título, nombre y descripción atenuada (la descripción solo con 380 px o más; si no, en el tooltip), hasta 10 filas con scroll. Filtra mientras se escribe (primero lo que empieza con lo escrito), flechas y Re Pág/Av Pág mueven, Enter o Tab eligen (reemplaza la palabra por la opción y un espacio, en un paso de deshacer) y Esc la cierra hasta que se empiece otra palabra. Los comandos son los que publica el agente: sin sesión, la lista lo dice.
- **Historial de prompts** (pedido del usuario): ↑ en la primera línea trae el prompt anterior y ↓ en la última el siguiente; después del más nuevo vuelve el borrador. Dentro de un texto de varias líneas las flechas mueven el caret como siempre, y con la lista de `/` o `@` abierta son de la lista. Los últimos 100, sin repetir el último, en `user://godot_agent/prompt_history.json` (datos del usuario por proyecto, fuera del repo).
- El cycle test ahora revisa el layout (D29): con el dock oculto y el banner de export, el slot no puede pedir más alto que la ventana, y ningún label con autowrap del dock ni de las secciones de Settings puede quedar de menos de 40 px. Sin el tope de MinSizeGuard falla.
- `test_composer` tipea con eventos de teclado y cubre las teclas y las dos listas.

## D31 · Subagentes de Claude Code (después de M8c)

- **Cómo llegan**: el adaptador de Claude Code (`claude-agent-acp`) abre sesiones aparte para los subagentes solo si el cliente declara la capacidad `subagents`. El addon no la declara, así que todo llega por la misma sesión. Lo que hace un subagente (tool calls, texto, thoughts, plan) trae `_meta.claudeCode.parentToolUseId` con el id del tool call de `Agent`/`Task` que lo lanzó. La llamada `Agent` en sí trae `_meta.claudeCode.toolName`, el prompt como content y, al terminar, el informe.
- **Problema**: el addon ignoraba el `_meta`. Las herramientas del subagente salían sueltas, mezcladas con las del agente principal, y su texto se pegaba en la burbuja de la respuesta principal.
- **Modelo**: con `parentToolUseId`, el tool call queda como hijo del de Agent (`parent_id`, `child_ids`) y avisa al grupo de su padre. El texto va a `subagent_text` del padre, con los últimos 2000 caracteres. Se descartan el thought, el `user_message_chunk` y el plan del subagente (el plan reemplazaría el del agente principal). Cubre estos casos:
  - Un tool call creado antes por un pedido de permiso, que recién después dice de qué subagente es, se mueve al subagente. Si el grupo queda vacío, se borra.
  - Un padre que no se vio se crea.
  - No se arman ciclos.
- **Vista**: la fila de Agent muestra la descripción y «subagente · <tipo>». Debajo tiene «▸ N herramientas del subagente · <la última>» (plegado) con las filas de los hijos sangradas y un «💬» con el último texto. El content se ve como «prompt» mientras corre y como «informe» al terminar.
- **Permisos**: no cambian (la política es la misma). La tarjeta dice «· subagente «<descripción>»» para saber quién pide.
- **Historial**: del `_meta` se guardan solo `toolName` y `parentToolUseId`, y los chunks de un subagente no se unen con los del principal. El replay arma lo mismo.
- **Sin sesiones aparte**: declarar `subagents` haría que el adaptador mandara cada subagente como otra sesión con su propio ciclo de vida. Eso es más trabajo y no muestra nada más de lo que ya llega por esta vía.

## D32 · Login del agente desde el dock (después de M8c)

- **Pedido del usuario**: un login como el de otros clientes de ACP. Antes, el addon dependía de que `claude` ya tuviera una sesión iniciada en la máquina. Si no la tenía, solo mostraba los nombres de los métodos de auth en el error.
- **Cómo lo hacen los demás**: el cliente declara `clientCapabilities.auth.terminal`. Con eso, `claude-agent-acp` ofrece dos `authMethods` de tipo `terminal`, «Claude Subscription» y «Anthropic Console». Sus `args` (`--cli auth login --claudeai|--console`) van después del comando del agente y terminan en `claude auth login`. Verificado con el adaptador real: `initialize` devuelve esos dos métodos, y `npx … --cli auth login --help` llega a `claude auth login`.
- **Sin TTY funciona**: `claude auth login` corrido como lo corre el editor (stdin en un pipe, con un HOME temporal para no tocar las credenciales reales y el navegador anulado) imprime «Opening browser…», una línea con el enlace y deja «Paste code here if prompted >» sin salto de línea. Si el navegador vuelve al callback local, termina solo; si no, espera el código por stdin.
- **Flujo** (`session/agent_login.gd` + SessionController):
  - Si `session/new` o un turno fallan con `authRequired` (código -32000 y el mensaje «Authentication required» del SDK de ACP, porque el AcpClient usa el mismo código para errores de transporte), el aviso agrega «Iniciar sesión · <método>».
  - Solo se ofrecen los métodos `terminal` y los del agente (los sin `type`: el cliente llama `authenticate`). `env_var` necesita configurar el perfil, así que no lleva botón.
  - El login corre con AgentProcess, sin bloquear el editor. El aviso muestra «Abrir enlace» (la primera URL de la salida), «Pegar código…» (un diálogo con LineEdit secreto que escribe en stdin) y «Cancelar» (mata el proceso y sus hijos).
  - Si sale con 0, vuelve a lanzar el agente y abre la sesión. Con otro código, muestra las últimas líneas de la salida sin el enlace y deja reintentar.
  - Si el agente manda `_meta.terminal-auth` con un comando exacto, se usa ese.
- **Credenciales**: las guarda el agente, como en una terminal. El addon nunca las lee ni las guarda (spec §10.1). El código pegado no se registra: el log dice «código enviado».
- **Pruebas**:
  - El agente falso tiene un modo `--login` (imprime como Claude Code, espera el código y crea un marcador), y `tests/scripts/auth.json` exige ese marcador para abrir la sesión.
  - `acp_session_check` prueba un código malo, uno bueno y la cancelación (el proceso termina).
  - `--godot-agent-login-test` hace lo mismo desde los botones del dock y el diálogo.
  - `test_agent_login` cubre la elección de métodos, el comando y el reconocimiento del error.
- **Pendiente**: no hay un botón para iniciar sesión cuando la sesión ya abre (por ejemplo, para cambiar de cuenta). Para eso sigue estando `claude auth login` en una terminal.

## D33 · El editor toma lo que el agente escribe por fuera (después de M8c)

- **Síntoma** (probando el One-shot en un proyecto real): el agente parecía editar desde afuera, porque al volver al editor Godot mostraba «Files have been modified outside Godot» por `project.godot` y por las escenas abiertas.
- **Causa**: en `claude-agent-acp` (0.94), el Write y el Edit de Claude Code escriben directo al disco. El adaptador tiene `writeTextFile`, pero ninguna herramienta lo llama. El addon ya ponía al día los scripts abiertos (D15), pero:
  - de una escena abierta solo avisaba;
  - con `project.godot` no hacía nada. Godot compara la fecha del archivo con la del último guardado de ProjectSettings y, al volver el foco, pregunta si recargarlo. Si el usuario no recargaba, el próximo guardado del editor pisaba lo del agente (acciones de input, autoloads, escena principal).
- **`project.godot`**: un watcher (cada 0,5 s, más los tool calls y «Volver acá») compara el archivo con ProjectSettings. Para eso lee el archivo con ConfigFile y compara cada valor con `var_to_str` (los InputEvent son objetos).
  - Lo que cambió o se agregó se aplica con `set_setting`. Lo que estaba en la versión anterior del archivo y ya no está se borra con `set_setting(nombre, null)`.
  - Después llama a `ProjectSettings.save()`. Eso deja la fecha de guardado igual a la del archivo, así Godot no pregunta, y el editor queda con lo mismo que el archivo.
  - Si el editor ya tenía lo mismo (lo guardó él), no hace nada. La sección raíz (`config_version`) no se toca. Un archivo que no se puede leer no se aplica, y queda el diálogo de Godot.
  - Siempre está activo, igual que el de los scripts: equivale a elegir «Recargar» en el diálogo.
- **Escenas abiertas**: si la escena no tiene cambios sin guardar (`EditorInterface.get_unsaved_scenes()`, desde 4.7), se recarga con `reload_scene_from_path`, sin diálogo. Con cambios sin guardar no se pisa: queda el aviso con «Recargar escena». En 4.4 esa API no existe y no hay una forma segura de saberlo (el número de versión del undo no ve los cambios hechos sin undo), así que en 4.4 se avisa siempre.
  - El watcher de escenas ignora los guardados del propio editor (`EditorPlugin.scene_saved`). Sin eso, cada Ctrl+S recargaba la escena y se perdía el historial de deshacer; el external test lo verifica sacando la conexión.
- **Prueba**: `--godot-agent-external-test` escribe `project.godot` y la escena abierta como lo haría el Write de Claude Code. Antes del arreglo mostraba el diálogo en los dos casos. Verifica lo siguiente:
  - los settings llegan a ProjectSettings y se aplican solo esos dos;
  - al volver el archivo atrás, se borran;
  - la escena se recarga, salvo con cambios sin guardar, donde avisa;
  - un guardado del editor no recarga;
  - no aparece ningún diálogo.

## D34 · Mínimo Godot 4.6 (antes 4.4)

- **Decisión del usuario**: soportar tres versiones (4.6, 4.7 y 4.8) es más manejable que arrastrar 4.4 y 4.5. La matriz de pruebas pasa a 4.6.3, 4.7.2 y 4.8-beta1; la spec §2 dice ahora «Mínimo soportado: 4.6».
- **Código que se fue**, porque solo existía por 4.4:
  - los pipes retenidos de `AgentProcess` (D11): cerrar los pipes de `execute_with_pipe` rompía descriptores del editor hasta 4.4.x, y está corregido desde 4.5;
  - la lectura del panel Output en `ErrorCollector`: 4.4 no tenía `Logger`. El Logger pasó de un script compilado en runtime (para que el archivo parseara en 4.4) a `core/editor_logger.gd`;
  - las llamadas por reflexión a `Node.get_orphan_node_ids()` (dev plugin) y a `Script.get_global_name()`.
- **Lo que sigue dependiendo de la versión**:
  - 4.6 no tiene `EditorInterface.get_unsaved_scenes()` (llega en 4.7): ahí una escena abierta que el agente cambia en disco no se recarga sola (D33).
  - 4.6 y 4.7 tienen `EditorDock` para el dock y el panel inferior, pero no para la main screen (D9).
  - Las decisiones anteriores que hablan de 4.4 quedan como estaban: cuentan lo que pasaba cuando se tomaron.


## D35 · AgentProcess sin threads: el editor ya no se cae si un script del addon cambia en disco

- **Lo que pasó** (2026-10-22, little-villages, 4.8-beta1): el proyecto usa el addon por symlink al repo. Se editó `agent_process.gd` con el agente corriendo, el editor recargó el script y se cayó con SIGSEGV.
  - En el core dump se ve el thread `_watch_exit`, dentro de `GDScriptInstance::callp`. El thread seguía ejecutando el bytecode del script, y la recarga ya lo había liberado.
  - Lo mismo pasa con un `git pull` del addon con una sesión abierta. El run del One-shot estaba solo en memoria y se perdió (m7-09).
- **Decisión**: `AgentProcess` lee los pipes desde el hilo principal, en `process_frame`, sin threads.
  - Cada frame lee solo los bytes que ya están en el pipe: `FileAccess.get_length()` usa FIONREAD en Unix y PeekNamedPipe en Windows, también en 4.6. Leer exactamente eso no bloquea, aunque el pipe sea bloqueante.
  - El pipe sigue en modo bloqueante a propósito. En modo no bloqueante, `store_buffer` puede escribir a medias en stdin sin decir cuánto, y eso rompería el JSON-RPC con prompts grandes (imágenes).
  - Las líneas de stdout se arman acá (`_split_lines`) y se entregan con el mismo presupuesto por frame que antes. El exit sale después de la última línea, incluida una última sin `\n`.
  - El fin del stream se define por el proceso, no por EOF: un pipe vacío y un EOF dan el mismo error en `get_buffer`. Muerto el proceso, se espera a que se vacíen los pipes y, hasta `EOF_GRACE_MS`, a que los descendientes que quedaron (un nieto de npx) mueran. Después se los mata.
  - Los descendientes en Linux salen de `/proc/<pid>/task/*/children`, sin lanzar procesos; se refrescan cada 2 s. En macOS se usa `pgrep` cada 10 s, porque lanza procesos desde el hilo principal. En Windows no hace falta: `taskkill /T`.
- **Costo**: con el editor sin foco, los frames bajan a unos 10 por segundo y cada lectura toma lo que haya en el pipe (64 KB en Linux). Si el agente escribe más rápido que eso, su `write` espera; nada se pierde.
- **Sin probar**: Windows. Ahí `PeekNamedPipe` falla cuando el pipe ya se cerró, y puede quedar un error en Output al terminar el proceso.
- **Prueba**: `test_agent_process`:
  - recarga `agent_process.gd` con un proceso escribiendo y verifica que sigue leyendo. Con los threads, esto crasheaba en headless igual que en el editor;
  - verifica stdout, stderr, el exit después de la última línea, stdin y stop.
- Quedan threads cortos (checkpoints de git, índice del completado, escrituras del historial): duran milisegundos o segundos, no toda la sesión.

## D36 · Cola de prompts en el dock

- **Pedido del usuario**: poder escribir y encolar prompts mientras el agente trabaja, como en Claude Code. Antes, Enter no hacía nada con un turno en curso.
- **Funcionamiento**:
  - Con un turno en curso, el composer entrega el texto igual. El dock lo guarda en una `PromptQueue` junto con su contexto: escena, selección, captura y archivos, tomados al encolar.
  - ACP no permite meter texto dentro de un turno, así que la cola espera al fin del turno.
- **Envío automático solo con `end_turn`**:
  - Si el turno termina cancelado, con error, por negativa o por límite, la cola se pausa: lo que el usuario pidió puede ya no tener sentido. Lo mismo pasa si la sesión se cierra o empieza otra (`entries_cleared`).
  - La cola nunca se descarta sola, para no perder lo que el usuario escribió. La vista muestra el motivo de la pausa y «Enviar ahora» (con una sesión lista) o «Descartar».
- **One-shot**: durante un One-shot el composer ya va a «Guiar al agente» (`submit_interceptor`), así que la cola no recibe nada. Si un One-shot arranca con prompts en cola, la cola se pausa en lugar de mandarlos dentro del One-shot.
- **Límite del plan**: el composer sigue bloqueado como antes, y si la cuota está agotada, la cola se pausa.
- **Prueba**: `test_prompt_queue`, `test_composer` (Enter con un turno en curso) y `--godot-agent-queue-test`. Este último hace un turno largo, encola dos prompts con Enter, cancela, verifica que la cola quedó en pausa, aprieta «Enviar ahora» y comprueba que salen los dos en orden.

## D37 · El One-shot se guarda en disco y se retoma después de un cierre o una caída

- **Lo que pasó** (D35): el editor se cayó con un One-shot recién terminado y el run, que vivía solo en memoria, se perdió. Lo mismo pasaba al cerrar el editor con un run en curso, porque `_exit_tree` lo daba por terminado.
- **Decisión**: `OneShotRun` guarda su estado en `user://godot_agent/oneshot/<id>.json` (`OneShotStore`). Los datos son del usuario y no van al repo.
  - Se guarda en cada cambio de fase y como mucho cada 2 s mientras corre.
  - La escritura es atómica: un archivo temporal y después rename. La última captura va en `<id>.png`. Quedan los últimos 20 runs.
  - Se guarda: objetivo, presupuestos y uso, checks, actividad, plan, tarea actual, guía pendiente, el estado de los checkpoints (rama, sha base, lista) y la sesión del agente.
- **Al cerrar el editor o deshabilitar el plugin**, el run se suspende (`suspend()`): queda guardado como activo, en lugar de terminarse.
- **Al abrir el editor**:
  - Si el run más nuevo quedó activo, se carga en pausa y el dock avisa. La pantalla Agent muestra el run con su actividad y un banner que lo explica.
  - Mientras tanto se ve el plan guardado, porque la sesión del dock puede ser otra.
- **«Retomar»** reabre la sesión del run, aunque el dock tenga otra abierta. Usa `controller.reopen`, que hace `session/load` con el historial; si falla, abre una sesión nueva y manda el resumen (objetivo, plan, checks y checkpoints).
  - «Guiar al agente» sobre un run cargado también retoma primero.
  - «Detener» lo da por terminado.
- **Sin checkpoints**: si al empezar git no está disponible o el repo no tiene commits (el caso de little-villages), un diálogo lo dice y ofrece seguir sin checkpoints. Antes ese aviso se perdía y el run arrancaba sin «Volver acá».
- **Pruebas**:
  - `test_oneshot_store`;
  - `oneshot_check` (recuperación): el editor "se cae" a mitad del segundo turno; otra instancia carga el run en pausa, con plan, checks y checkpoints, retoma en una sesión nueva con el resumen y termina creando cp3 en la misma rama;
  - `--godot-agent-oneshot-test` verifica la pantalla con un run cargado.

## D38 · El One-shot detecta loops del agente

- **Problema**: un agente autónomo puede quedarse repitiendo lo mismo ("loop forever, retry bad actions"): reintentar un Edit que falla, reportar el mismo check roto turno tras turno, aplicar el mismo cambio una y otra vez. El tope de "seguí con el plan" (`MAX_IDLE_CONTINUES`) no lo frena: los avances de plan o los playtests lo reinician.
- **Decisión**: `LoopDetector` mira tres huellas (nombre + argumentos con las claves ordenadas):
  - un check que falla con el mismo detalle en `repeats` reportes seguidos (pasar o cambiar de detalle corta la racha);
  - una tool call que falla con los mismos argumentos `repeats` veces. Si es una lectura o una verificación (run_scene, get_errors, capturas…), cualquier cambio en el medio reinicia la cuenta: editar y volver a probar no es un loop;
  - una tool call que cambia algo, idéntica, `repeats + 1` veces entre las últimas 40. Las lecturas, las verificaciones, open_scene y save_scene se repiten libremente.
- **Qué hace el run**:
  - la primera vez: actividad «loop», aviso en el dock y una guía que pide otro enfoque. Si el loop es de tool calls, corta el turno para que la guía llegue ya;
  - si la misma huella vuelve a llegar al umbral: pausa con un banner que lo explica. Guiar o «Retomar» lo sigue.
- **Umbral**: `loop_repeats` en la config del proyecto (Settings → One-shot), 3 por default.
- **Avance real**: el tope de turnos sin avance (`MAX_IDLE_CONTINUES`) ahora cuenta tareas completadas y checks que pasan. Antes también contaba playtests, y un agente que probaba sin arreglar nada nunca llegaba al tope.
- **Pruebas**: `test_loop_detector`; `oneshot_check` (loop) con umbral 2: dos Edit que fallan cortan el turno, el mismo check roto pide otro enfoque y después pausa, y guiar retoma.

## D39 · Informe del One-shot con datos medidos

- **Problema**: al cerrar, el agente escribe su propio reporte ("qué quedó hecho, qué falta"), pero eso no sirve para comparar corridas ni para decidir si conviene cambiar de modelo, de prompt o sumar una tool. Hace falta lo que midió el harness.
- **Decisión**: `RunReport` junta métricas mientras el run corre y `OneShotRun._write_report` arma el informe al terminar, por cualquier motivo:
  - objetivo, motivo de cierre, duración y turnos;
  - presupuestos y uso;
  - tareas del plan con su duración: desde que pasa a `in_progress` hasta que pasa a `completed` (la que quedó abierta cuenta hasta el final);
  - tools: usos y fallas por tool (`godot.<tool>`, el `toolName` de Claude Code o el título); las canceladas no cuentan;
  - checks: estado final y cuántas veces se reportaron en `fail`;
  - checkpoints, permisos pedidos y denegados, turnos con error, pausas por cuota, límites del plan, loops (D38) y guías del usuario;
  - archivos cambiados (`changes_summary`, si hay checkpoints).
- **Dónde**: se guarda en `user://godot_agent/oneshot/<id>.report.json` (`OneShotStore.save_report`), al lado del estado (D37), y se poda con él. Las métricas parciales van dentro del estado guardado, así un run retomado después de una caída no las pierde.
- **UI**: botón «Informe» en la barra de abajo cuando el run terminó. Abre el informe en Markdown (con el conversor del dock) y «Copiar Markdown» lo deja en el portapapeles.
- **Pruebas**: `test_run_report`; `oneshot_check` (recuperación: el informe suma lo de antes de la caída y queda en disco; loop: loops, guías y fallas); `--godot-agent-oneshot-test` abre el informe.

## D40 · Criterios de evaluación para juegos

- **Por qué**: en "Harness design for long-running application development" (Anthropic, 2026-03), criterios explícitos con peso y umbral guían tanto al que construye como al que evalúa, y su redacción cambia el resultado.
- **Criterios** (`oneshot/game_criteria.gd`), puntaje de 0 a 10:
  - **Jugabilidad** (peso 3, mínimo 7): la mecánica responde a los inputs, hay un loop completo (empezar, jugar, ganar o perder, reiniciar) y nada se traba. El fallo típico es "las entidades aparecen pero no responden al input".
  - **Funcionalidad** (3, 7): cada feature del objetivo funciona en un playtest con inputs simulados, sin errores en `get_errors`.
  - **Visual y feel** (2, 5): legibilidad, feedback de las acciones y estilo coherente, mirado con `capture_game_frame`.
  - **Código** (1, 5): tipado estático, escenas bien armadas y sin warnings.
- **Veredicto**: el juego pasa si cada criterio con peso llega a su mínimo; un criterio sin puntaje no pasa. El peso arma el promedio ponderado y le dice al agente qué priorizar. Peso 0 apaga un criterio.
- **Dónde se usan**:
  - el prompt inicial del One-shot los lista con mínimo y peso;
  - la rúbrica del evaluador (D42) suma tres ejemplos de puntaje por criterio (3, 6 y 9) como referencia fija, para que no se vuelva indulgente vuelta a vuelta, y aclara que no puede oír: el audio se verifica solo por código.
- **Formato**: el evaluador responde con un bloque `{"scores": [{criterion, score, reason}]}`, que `FindingsParser` lee junto a `checks` y `findings`. El criterio se reconoce por id o por nombre, sin importar mayúsculas ni tildes.
- **Config**: `criteria` en `project_config.tres` (id → peso y mínimo; solo se guarda lo que difiere del default), editable en Settings → One-shot.
- **Fuera por ahora**: los contratos por sprint del artículo (el generator y el evaluator acuerdan cómo se verifica cada tarea). Ellos mismos los sacaron por costo; se pueden reconsiderar si el informe (D39) muestra checks mal definidos.

## D41 · Spec y progreso del One-shot en archivos

- **Por qué** ("Harness design for long-running application development", Anthropic, 2026-03):
  - un planner que convierte el objetivo corto en un spec evita que el agente se quede corto de alcance; el spec tiene que ser ambicioso pero de alto nivel, porque el detalle técnico equivocado se arrastra;
  - los agentes se pasan el trabajo por archivos, no por contexto.
- **Archivos** (`OneShotFiles`), en `<proyecto>/.godot_agent/oneshot/<id>/`:
  - `spec.md`: lo escribe el agente como paso 0: mecánicas, loop de juego, dirección visual y qué es "terminado", sin nodos ni APIs;
  - `progress.md`: lo actualiza al cerrar cada tarea (hecho, falta, decisiones, problemas conocidos);
  - `qa-<n>.md`: el informe del evaluador en cada vuelta (D42).
- **Traspaso**: si hay que abrir una sesión nueva (el editor se cayó, se perdió la sesión), el prompt de resumen manda leer spec y progress antes de seguir. El estado del harness sigue en `user://` (D37); el del trabajo, en el proyecto.
- **Revisión opcional** («Revisar el spec antes de construir», default en Settings → One-shot): el agente escribe el spec y termina el turno; el run pasa a «Spec para revisar».
  - «Revisar spec» abre el archivo en un diálogo editable; «Aprobar spec» guarda lo editado y sigue construyendo.
  - «Guiar al agente» le pide cambios y el run vuelve a esperar la aprobación.
  - Si el agente no escribió el spec, el banner lo dice y se puede aprobar igual.
- **Git y export**:
  - `.godot_agent/.gdignore` deja la carpeta fuera del FileSystem del editor, de la importación y del export; el export plugin además saltea `res://.godot_agent/` por las dudas.
  - La carpeta entra en los checkpoints: así, «Volver acá» deja spec y progreso sincronizados con el código. Va en la rama del agente; si el usuario no la quiere en su rama, la borra antes del merge.
  - «Revisar cambios» y el resumen de cambios no la cuentan: no son cambios del juego.
- **Dónde se ven** (después de probarlo en un proyecto real: la carpeta oculta no aparece en el FileSystem y la columna Plan quedaba vacía durante la revisión):
  - en «Spec para revisar», la columna Plan muestra el spec renderizado con «Editar» y «Aprobar spec»;
  - «Spec y progreso» abre un visor con pestañas Spec (editable), Progreso y QA n, con «Mostrar en carpeta» y «Abrir con editor externo»;
  - un link del chat a `.godot_agent/oneshot/…` abre ese visor en su pestaña. Los demás archivos de texto que Godot no carga (`.md`, `.txt`…) se abren con el programa del sistema, en vez de «No se pudo abrir».
- **Guiar = el chat**: con un One-shot en curso, lo que se escribe en el chat del dock ya iba a `guide()`. El campo «Guiar al agente» de la pantalla duplicaba eso y confundía, así que se sacó. El placeholder del composer lo dice.
- **Pruebas**: `test_oneshot_files`; `oneshot_check` (spec): esperar, guiar, aprobar con cambios, terminar y el spec en git; `--godot-agent-oneshot-test` con la columna del spec, el visor y un link a progress.md.

## D43 · El agente corre Godot con el binario del editor

- **Problema** (reporte del usuario): el agente corre `godot --headless` por su cuenta (importar, validar, correr tests) y toma el `godot` del PATH, que puede ser otra versión que la del editor abierto. El usuario tiene varias versiones instaladas una al lado de la otra.
- **Qué hace** (`transport/editor_binary.gd`): el binario es `OS.get_executable_path()` y le llega al agente por tres lados:
  - en su entorno, como `GODOT` y `GODOT_BIN`. El perfil del agente puede definirlas y entonces mandan las del perfil;
  - como un shim `godot` (`godot.cmd` en Windows) que lanza ese binario. Vive en `<cache>/godot_agent/bin-<hash del binario>/`, uno por binario para que editores de versiones distintas no se pisen, y va al frente del PATH del agente;
  - en el system prompt, con la ruta y la regla de usarla. `project_info` también la incluye.
- **Por qué los tres**: la shell que usa Claude Code para su Bash puede volver a armar el PATH desde el perfil del usuario (`.zshrc`) y dejar el shim atrás. La regla del prompt con la ruta absoluta es lo que manda; el shim y `$GODOT` cubren el resto.
- **Pruebas**: `test_editor_binary` (entorno, contenido del shim y que el shim corra la versión del editor) y `acp_session_check` (el agente falso recibe `$GODOT` y el PATH con el shim, y el prompt nombra el binario).

## D44 · Cuándo pausa el One-shot por cuota

- **Problema** (run real en great-boy-one): con la cuota al 95 %, el banner decía «se pausa en el próximo checkpoint» y el run siguió hasta el límite. La pausa solo se disparaba cuando el plan pasaba a otra tarea: un agente que se quedaba en una tarea larga, o trabajaba sin plan, nunca llegaba ahí. Además, al terminar un turno el run mandaba «Seguí con el plan» sin mirar la cuota.
- **Ahora** (con la pausa programada, al pasar el umbral):
  - pausa al empezar la tarea siguiente (con su checkpoint, como antes) **o** al terminar el turno, lo que llegue primero;
  - red de seguridad: si ninguna de las dos llega en 10 min (`QUOTA_PAUSE_GRACE_S`), o la cuota pasa el 98 % (`QUOTA_PAUSE_HARD`), corta el turno a mitad de la tarea y pausa con un checkpoint `-quota`;
  - el banner dice cuándo va a pausar y cuánto falta para que corte igual.
- **Pruebas**: `oneshot_check` (cuota al terminar el turno; cuota con tope de espera) y el escenario de cuota de siempre.

## D45 · Cambiar de cuenta al llegar al límite

- **Pedido** (run real en great-boy-one, límite de 5 h): seguir con otra cuenta sin esperar el reinicio, y que cerrar el editor no pierda la espera.
- **«Cambiar de cuenta»** (pantalla Agent, visible cuando el run se puede retomar). Tiene dos caminos:
  - «Iniciar sesión con otra cuenta · <método>»: corre el login del agente (D32) y, al terminar, el run retoma solo; el hook es `SessionController.after_login`;
  - «Ya inicié sesión con otra cuenta (en una terminal)»: para quien lo hizo con `claude` → `/login`.
- **Qué pasa al cambiar** (`OneShotRun.switch_account`):
  - la cuota medida era de la cuenta anterior: `QuotaMonitor.forget_account` la borra hasta que el agente informe la nueva;
  - se relanza el proceso del agente, que lee las credenciales nuevas;
  - se retoma la misma sesión con `session/load`, porque las conversaciones de Claude Code son locales y no dependen de la cuenta. Si no carga, se abre una sesión nueva con el resumen del plan, como en D37.
- **«Reintentar» del dock** con un One-shot activo retoma el run en su sesión. Antes abría una sesión en blanco y el run seguía ahí sin contexto.
- **Cerrar el editor esperando la cuota**: el estado guarda la fase (`phase_id`) y `quota_resume_at`. Al reabrir, un run que estaba Limitado o Pausado por cuota vuelve a «Pausado por cuota» y retoma solo a la hora del reinicio. Antes quedaba en pausa normal.
- **Prompt de reanudación**: si hay spec, recuerda releer spec.md y progress.md.
- **Pruebas**: `oneshot_check` (cambio de cuenta: límite, restauración esperando la cuota, cambio y fin) y `--godot-agent-oneshot-test` (menú en Limitado, «Reintentar» del dock en la misma sesión).

## D46 · Interfaz en inglés con traducción al español

- **Pedido**: el plugin primero en inglés, con traducción al español; README y wiki en los dos idiomas.
- **Texto fuente en inglés**, y el español en `addons/godot_agent/i18n/es.po`. `I18n.t("Budgets")` devuelve la traducción o el mismo texto. El `.po` se carga con `load()` como Translation, sin importar nada ni tocar el TranslationServer del editor.
- **Qué se traduce**: solo lo que lee el usuario en el dock, la pantalla Agent, el Agent Log, Settings, los avisos y las tarjetas de revisión.
  - Lo que lee el agente va siempre en inglés: system prompt, reglas de modo, prompts del One-shot, descripciones y resultados de tools. Lo mismo los logs, los nombres de deshacer (también los lee el agente en el resultado) y los commits de checkpoint. El agente responde en el idioma del usuario.
  - Una constante con etiquetas lleva `# i18n` al final de cada línea con texto; el último literal de la línea es el msgid y se traduce al mostrarlo. Si el texto también va al agente, el código usa la constante cruda para el agente y `I18n.t` para la interfaz (p. ej. `LoopDetector`: `text` y `label`).
- **Idioma**: la variable `GODOT_AGENT_LANGUAGE` (pruebas), Settings → Interfaz → Idioma, o el idioma del editor. Se elige al habilitar el plugin; cambiarlo se aplica al reabrir el editor.
- **El editor no traduce lo nuestro**: los nodos raíz del addon tienen `auto_translate_mode` desactivado. Si no, el editor en español traduciría con su propio catálogo textos que coinciden por casualidad («Cancel», «Review»), y los botones de diálogos de Godot quedarían en inglés con el plugin en inglés. Por eso cada diálogo pone `cancel_button_text = I18n.t("Cancel")`.
- **Runs viejos**: los tipos de actividad y el motivo de cierre guardados en español antes de D46 se muestran tal cual.
- **Pruebas**: `test_i18n` (cada msgid usado está en el catálogo con los mismos placeholders, y el catálogo no tiene entradas sin usar) y `--godot-agent-i18n-test` (con `GODOT_AGENT_LANGUAGE=es`, ningún texto visible del dock, la pantalla Agent, el Agent Log ni Settings queda en inglés). `run_in_xvfb.sh` corre en inglés salvo que se pida otro idioma.

## D47 · Enums y clases internas con nombres compuestos

- **Problema** (great-boy-one, que tiene `class_name Level`): el addon no cargaba. `chat_entry.gd` tiene `enum Level` y `var level: Level`; cuando otro script compila y resuelve ese miembro, Godot toma `Level` como la clase global del juego, y falla con «Could not resolve external class member» y «chat_entry.gd.Level cannot be assigned to Level». Pasa igual en 4.6.3, 4.7.2 y 4.8-beta1, y con clases internas (`class Request`).
- **Decisión**: ningún enum ni clase interna del addon tiene nombre de una palabra. `Level` → `NoticeLevel`, `Kind` → `EntryKind`, `State` → `SessionState`/`QuotaState`/`IndicatorState`, `Phase` → `RunPhase`, `Section` → `SettingsSection`, `Surface` → `EditorSurface`, `Connection` → `McpConnection`, `Response` → `AcpResponse`, `Request` → `ParsedRequest`, `Resolved` → `ResolvedNode`, `Writer` → `HistoryWriter`. Un nombre compuesto puede chocar igual, pero es mucho menos probable que un nombre genérico.
- **Pruebas**: `tests/fixtures/global_names/` declara clases globales con nombres genéricos (Level, State, Kind, Phase, Request…), así todas las suites cargan el addon como en un juego real. `test_type_names` falla si aparece un enum o clase interna de una palabra.

## D48 · El agente no escribe el proyecto por fuera del editor

- **Problema** (run real en great-boy-one): el agente del One-shot editó `ui/balloon.gd` con un heredoc de python3 y escribió dos `.tscn` con `cat > …`. El editor no se enteraba hasta el próximo escaneo, y una escena escrita a mano con un id o un `node_paths` mal falla callada al cargar. Swallowtail (otro addon que el usuario usa) resuelve lo mismo con instrucciones explícitas y tools para todo.
- **Instrucciones**: el system prompt pide escenas solo con `godot.*` (nunca un `.tscn` a mano) y scripts solo con las herramientas de archivos del agente, y avisa que los comandos que escriben el proyecto se rechazan. La shell queda para leer, correr Godot y git.
- **Se rechaza solo, en todo modo y sin tarjeta** (`ProjectWriteGuard`):
  - Bash que escribe dentro del proyecto: redirecciones, `tee`, `sed -i`/`perl -i`, `dd of=`, y python/node/ruby/perl con heredoc o `-c`/`-e` que abren para escribir. Los cuerpos de los heredocs se separan antes de buscar redirecciones (un `if a > b` en python no es una). Una ruta relativa cuenta como del proyecto. Las que empiezan con `$` o `~` no se pueden resolver y pasan; también pasan las absolutas fuera del proyecto (`/tmp`).
  - Write/Edit del agente sobre `.tscn`, `.uid` o `.import` del proyecto, y `fs/write_text_file` de esos archivos (antes solo se avisaba en el log).
  - El chat muestra «Rejected: …». Por ACP la respuesta es un rechazo sin texto, así que el motivo le llega al agente por el system prompt.
- **La alternativa tiene que ser igual de corta**: `create_scene` acepta `script_path` y `properties` de la raíz (exports incluidos). La escena de un solo nodo con script y valores que el agente escribió con `cat` sale en una llamada.
- **Límite**: si el usuario tiene reglas `allow` en sus settings de Claude Code (p. ej. para `python3`), el agente no pide permiso y el harness no ve el comando. Ahí solo queda la instrucción.
- **Pruebas**: `test_project_write_guard` (incluye los comandos de la captura), `acp_session_check` (escrituras por fuera del editor en One-shot) y `--godot-agent-edit-test` (`create_scene` con script y exports).

## D49 · Project settings por el editor

- **Problema**: el agente editaba `project.godot` como texto (input map, autoloads, ventana) y D33 lo sincronizaba con el editor. Una línea mal escrita (un `InputEventKey` serializado a mano) rompe la acción callada.
- **Tools** (`mcp/tools/project_tools.gd`): `project_settings` (read) y `set_project_setting`, `set_input_action`, `remove_input_action`, `set_autoload`, `remove_autoload` (grupo project: se deniega en Preguntar y Revisar, pregunta en Construir y se permite en One-shot).
  - Cada cambio es una acción del historial global de deshacer (Ctrl+Z en el editor) que hace `ProjectSettings.save()`; el deshacer también guarda. El botón «↶ undo» del chat sigue siendo solo para escenas.
  - Eventos de input como texto corto: `Space`, `Ctrl+S`, `CmdOrCtrl+Z`, `mouse:left`, `joy_button:a`, `joy_axis:left_x:-`. Las teclas van como physical keycode, igual que las agrega el editor.
  - `set_project_setting` convierte el valor al tipo del setting (ValueCoercion), `null` vuelve al default, y no toca `input/`, `autoload/` ni `editor_plugins/`.
- **Guard**: `ProjectWriteGuard` rechaza también `project.godot` escrito a mano (Write/Edit y `fs/write_text_file`); el mensaje al agente nombra las tools. La shell ya estaba cubierta por D48.
- **One-shot**: el default del grupo project pasó de ask a allow. Solo lo usan estas tools, y antes el agente hacía lo mismo escribiendo `project.godot` con edit_files, que en One-shot se permite: con ask, un run desatendido se quedaba esperando para agregar una acción de input.
- **Efecto lateral**: `ProjectSettings.save()` reescribe `config/features` con la versión del editor, igual que cuando el usuario cambia un setting.
- **Pruebas**: `test_project_tools` (eventos), `test_project_write_guard` y `--godot-agent-edit-test` (acción con append y Ctrl+Z, setting con prefijo y tipo inválido, autoload que no pisa un singleton, permisos por modo, `project.godot` igual al final).

## D50 · Mover, copiar y borrar archivos con las referencias al día

- **Problema**: el agente movía o borraba con `mv`/`rm` y una escena quedaba apuntando a una ruta que ya no existe, sin aviso hasta abrirla.
- **Tools** (`mcp/tools/file_tools.gd`, grupo edit_files):
  - `move_file` (archivo o carpeta): mueve también el `.uid` y el `.import`, mantiene el uid (`ResourceUID.set_id`), pasa el recurso cacheado a la ruta nueva y reescribe `res://viejo` → `res://nuevo` en `.tscn`, `.tres`, `.gd`, shaders, `project.godot`, `.cfg`, `.json`, `.cs` y `.gdextension`. Una ruta exacta solo matchea entera (termina en comilla, espacio, `)`, `,` o `::`); una carpeta, como prefijo. Los archivos reescritos pasan por `EditorSync` (scripts abiertos sin diálogo, escenas abiertas recargadas, conflicto si había cambios sin guardar). No mueve escenas abiertas.
  - `copy_file`: la copia es otro recurso (uid nuevo en la cabecera de `.tscn`/`.tres`; sin `.uid` ni `.import`, que el editor regenera). Acepta un origen fuera del proyecto, para traer assets.
  - `delete_file`: busca la ruta y el uid en los archivos de texto del proyecto; si algo lo nombra, no borra y lista archivo y línea. Si no, a la papelera del sistema (o borrado, si no hay papelera).
  - No se reescribe nada dentro de `addons/godot_agent` ni de carpetas ocultas o con `.gdignore`. Las rutas relativas en scripts (`preload("x.tscn")`) no se tocan: el resultado lo avisa.
  - No hay deshacer del editor: quedan los checkpoints del One-shot y git.
- **Guard**: `ProjectWriteGuard` rechaza `mv`, `cp` (por el destino), `rm`, `rmdir`, `unlink`, `git mv` y `git rm` sobre rutas del proyecto.
- **Hallazgo al probarlo**: la primera versión reescribió el propio `edit_check.gd`, que tenía la ruta del fixture como literal, y el editor recargó el script en medio de la prueba ("Canceling suspended execution… due to a script reload"). Reescribir referencias en scripts es lo que se busca, pero hay que saber que recarga esos scripts.
- **Pruebas**: `test_project_write_guard` (mv, rm -rf, cp hacia y desde el proyecto, git mv, sudo, strings) y `--godot-agent-edit-test` (escena, carpeta y script movidos con referencias y uid; la escena que lo instancia sigue cargando; borrar se niega con la lista; copia con uid nuevo; no mueve una escena abierta ni pisa).

## D51 · Recursos `.tres` por el editor

- **Problema**: el diseño data-driven (valores ajustables en Resources, D40 y m7-19) llevaba al agente a escribir `.tres` a mano, con los mismos riesgos que una escena escrita a mano (ids, `ExtResource`, tipos de arrays).
- **Tools** (`mcp/tools/resource_tools.gd`): `get_resource` (read), `create_resource` y `set_resource_properties` (edit_files). Para asignar un recurso a un nodo alcanza `set_properties` con la ruta.
  - `set_resource_properties` es una acción de deshacer (historial del recurso) que guarda con `ResourceSaver` al hacer y al deshacer. Cambia la instancia cacheada, así que las escenas abiertas que lo usan lo ven.
  - `get_resource` muestra las propiedades guardadas que difieren del default, con los sub-recursos y los elementos de arrays anidados hasta 4 niveles.
- **ValueCoercion** (también para `set_properties` y `add_nodes`): un recurso nuevo inline como `{"type": "StyleBoxFlat", "bg_color": "#222"}` (propiedades sueltas o en `properties`), controlado contra el hint de la propiedad; arrays tipados (`Array[ItemData]`) se convierten elemento por elemento y siguen tipados.
- **class_name sin @tool**: en el editor `script.new()` falla para un script sin `@tool`. Se instancia la clase nativa base y se le pone el script, como el Inspector. Arregla también `add_node`/`add_nodes` con tipos `class_name`, que fallaban igual.
- **Guard**: `.tres` entra en los archivos que no se escriben a mano (Write/Edit y `fs/write_text_file`); el rechazo nombra las tools.
- **Pruebas**: `test_resource_values` (inline con hint, class_name con array tipado, describe sin defaults), `test_project_write_guard` y `--godot-agent-edit-test` (crear con array tipado y sub-recurso, leer, cambiar y Ctrl+Z que vuelve a guardar, asignar por ruta e inline, nodo class_name sin @tool, no pisa).

## D52 · Tools de tilemaps

- **Problema**: `tile_map_data` es binario y no se escribe a mano; sin tools, el agente armaba los niveles con `set_cell` en `_ready()`, que no se ve en el editor y contradice "componer con escenas guardadas" (m7-19).
- **Tools** (`mcp/tools/tilemap_tools.gd`), solo para `TileMapLayer` (al `TileMap` viejo se le sugiere el nuevo):
  - `tileset_add_atlas`: crea un tile por celda de la grilla que no sea transparente (como "crear tiles en regiones no transparentes" del editor); `collision` les da un cuadrado completo y agrega una capa de física si no hay.
  - `tileset_add_scenes`: fuente de escenas; cada escena es la alternativa N del tile (0, 0).
  - `tilemap_set_cells` (celdas sueltas, con tile por celda, y/o un rectángulo; `erase`), `tilemap_paint_terrain` (connect o path, terreno por índice o nombre) y `tilemap_clear`.
  - `tilemap_get`: fuentes con sus tiles, capas de física, sets de terrenos y un mapa ASCII (hasta 100×60, o el `rect` pedido) con leyenda `a = source:(x,y)`.
- **Deshacer**: las celdas se cambian directo y se registra `tile_map_data` antes y después en una acción (`commit_action(false)`); las fuentes con `add_source`/`remove_source`. Si el TileSet es un `.tres`, se guarda al hacer y al deshacer.
- **Fuera por ahora**: configurar terrenos (peering bits por tile). Se hace en el editor de TileSet; las tools pintan con los que haya, y el error lo explica.
- **Pruebas**: `--godot-agent-edit-test` (TileSet inline con add_node, atlas de una textura con un tile transparente, colisión, rect y celdas sueltas, tile inexistente, mapa y leyenda, Ctrl+Z, erase, clear y su undo, terreno por nombre), en 4.8-beta1 y 4.6.3.

## D53 · Tools de animación

- **Problema**: `set_properties` no llega a pistas ni keyframes, así que el agente animaba con tweens en código o escribía la biblioteca a mano.
- **Tools** (`mcp/tools/animation_tools.gd`): `animation_get` (read) y `animation_create`, `animation_set_track`, `animation_remove`, `sprite_frames_set` (edit_scene).
  - `animation_set_track` agrega una pista o reemplaza las keys de la que tiene el mismo path. Pistas de valor (`"Nodo:propiedad"` relativo al `root_node` del player, también subpropiedades como `position:y`) con el valor convertido al tipo de la propiedad, y pistas de método. Update mode: continuous para tipos que interpolan (float, vectores, colores, transforms) y discrete para el resto, salvo que se pida otro.
  - `animation_create` usa `"biblioteca/anim"` o la biblioteca por defecto (la crea en la misma acción) y puede marcar autoplay.
  - `sprite_frames_set` arma los cuadros desde imágenes o desde una hoja (AtlasTexture por celda); si el nodo no tenía SpriteFrames, crea uno sin la animación `default` vacía.
- **Deshacer**: cada cambio de una animación se hace sobre una copia (`duplicate(true)`) y la acción cambia una por otra en su AnimationLibrary (`add_animation` reemplaza). SpriteFrames se restaura cuadro por cuadro (clear + add_frame con las duraciones). Si la biblioteca o los SpriteFrames son un `.tres` propio, se guardan al hacer y al deshacer.
- **Fuera por ahora**: AnimationTree (state machines, blend spaces), pistas bezier, de audio y 3D.
- **Pruebas**: `--godot-agent-edit-test` en 4.8-beta1 y 4.6.3 (crear con loop y autoplay, pistas de posición, color y método, key fuera del largo, propiedad inexistente, animation_get con keys, Ctrl+Z por pasos, borrar pista y animación con autoplay, SpriteFrames desde hoja y reemplazo con undo).

