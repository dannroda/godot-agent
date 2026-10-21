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
