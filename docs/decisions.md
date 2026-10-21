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
