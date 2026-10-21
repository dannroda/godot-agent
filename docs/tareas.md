# Tareas — agent-harness

> Export de `compass/`, que es la fuente de verdad. No editar: los cambios se hacen en `compass/` o con `scompass`, y este archivo se regenera.
> Generado: 2026-10-21

## M0 — Esqueleto y decisiones  (6/6, 6 en revisión)

Estructura de carpetas y clases decidida con las skills; plugin que agrega y quita dock, panel inferior y main screen; el addon nunca llega a un export.

**Hecho cuando:**
- Habilitar y deshabilitar el plugin 5 veces seguidas sin errores en Output.
- `tests/export_check.gd` pasa con el plugin habilitado y también deshabilitado (con el filtro del preset).

### 0.1 Cargar skills y proponer estructura en docs/decisions.md · Revisión

**Prioridad:** alta · **Tamaño:** M · **Responsable:** Claude

Cargar godot-architecture, godot-communication, godot-patterns, godot-code-review y godot-data-driven; proponer estructura de carpetas bajo res://addons/godot_agent/ y la lista de clases. Registrar los choques skill↔spec y las verificaciones de API (execute_with_pipe en 4.4, tags de editor) en docs/decisions.md.

**Prueba:** docs/decisions.md tiene D1–D9: estructura, sin class_name, composición, API verificada en 4.4.1/4.7.2/4.8-beta1, settings por proyecto, presets, test de ciclo, uid_cache y docks.

**Notas:** Binarios: 4.8-beta1 en /opt/godot/versions/4.8-beta1/godot (dev), 4.7.2 en PATH, 4.4.1 oficial bajado al scratchpad solo para verificar. Hallazgos: en 4.4 el export filtra la carpeta pero deja class_name y rutas en global_script_class_cache.cfg/uid_cache.bin → addon sin class_name (preload consts). read_string_from_stdin(buffer_size) no tiene default en 4.4. editor_runtime existe en 4.4.

### 0.2 plugin.cfg y plugin.gd con dock, panel inferior y main screen · Revisión

**Prioridad:** alta · **Tamaño:** S · **Responsable:** Claude

EditorPlugin que agrega y quita el dock "Agent" vacío, el panel inferior "Agent Log" y la main screen "Agent" sin errores ni leaks al deshabilitar (spec §9, §15).

**Prueba:** godot --headless --path . --script tests/plugin_cycle_check.gd → PASS en 4.8-beta1, 4.7.2 y 4.4.1 (5 ciclos, sin huérfanos ni errores).

**Notas:** 4.8 deprecó _has_main_screen/add_control_to_dock/bottom_panel en favor de add_dock(EditorDock); con _has_main_screen 4.8-beta1 deja un EditorDock huérfano por ciclo. ui/editor_surfaces.gd elige EditorDock o API vieja por superficie (D9). Falta verificar a ojo en el editor con ventana que la main screen "Agent" aparece en 4.8 (headless no lo muestra).

### 0.3 EditorExportPlugin: excluir addon y limpiar autoload huérfano · Revisión

**Prioridad:** alta · **Tamaño:** S · **Responsable:** Claude

_export_file llama a skip() para todo bajo res://addons/godot_agent/. En _export_begin, si el autoload de playtest sigue registrado, error claro y quitarlo; verificar si afecta al export en curso y documentarlo (spec §2).

**Prueba:** tests/export_check.gd: escenarios plugin_on_sin_filtro y plugin_on_autoload_huerfano PASS en 4.4.1, 4.7.2 y 4.8-beta1.

**Notas:** D10: el editor ordena los export plugins por nombre y corta la cadena en el primer skip/remap; el de GDScript remapeaba .gd→.gdc antes que el nuestro → _get_name() = "!GodotAgentExcludeAddon". project.binary se genera al final, así que quitar el autoload en _export_begin sí afecta al export en curso, pero remove_autoload_singleton no borraba la entrada en ese momento: unregister() la borra a mano si sigue. Rastros aceptados (D8): uid_cache.bin y editor_plugins/enabled.

### 0.4 Botón "Agregar a los presets" (filtro de exclusión) · Revisión

**Prioridad:** media · **Tamaño:** S · **Responsable:** Claude

Red de seguridad para exports con el plugin deshabilitado: agregar addons/godot_agent/* al exclude_filter de cada preset en export_presets.cfg, previa confirmación. Aviso visible (en M0 desde el dock; Settings llega en M7).

**Prueba:** tests/unit/test_export_presets_patcher.gd (5 tests) + prueba manual 5 de docs/progress.md.

**Notas:** Banner en el dock (Settings llega en M7). Edita export_presets.cfg con ConfigFile previa confirmación; pide reiniciar el editor porque los presets viven en memoria y el diálogo de Export puede pisar el cambio (D6). El dock relee el archivo cada 2 s si cambió su mtime. Falta probar el banner a mano en el editor con ventana.

### 0.5 Test headless de export (tests/export_check.gd) · Revisión

**Prioridad:** alta · **Tamaño:** M · **Responsable:** Claude

Exporta un preset de prueba como .zip con --export-pack, lo abre con ZIPReader y falla si encuentra archivos de addons/godot_agent/ o el autoload de playtest en project.binary. Debe pasar con el plugin habilitado y deshabilitado (con filtro).

**Prueba:** godot --headless --path . --script tests/export_check.gd → PASS (4 escenarios) en 4.4.1, 4.7.2 y 4.8-beta1.

**Notas:** Proyectos temporales en user://export_check/<escenario>. Incluye un escenario de control (plugin off, sin filtro) que tiene que detectar el addon, para que el test no pase por no mirar. El huérfano se escribe después del --import porque el plugin lo limpia al cerrar. Runner unitario: tests/run_all.gd + tests/unit/test_case.gd.

### 0.6 Verificar M0 y escribir docs/progress.md · Revisión

**Prioridad:** alta · **Tamaño:** S · **Responsable:** Claude

Habilitar/deshabilitar el plugin 5 veces sin errores, correr el test de export en ambos escenarios, pasar godot-code-review sin hallazgos altos, y dejar en docs/progress.md qué quedó, cómo probarlo a mano y qué falta.

**Prueba:** run_all, plugin_cycle_check y export_check PASS en 4.8-beta1, 4.7.2 y 4.4.1. Capturas con ventana en 4.8 y 4.4: main screen Agent, Agent Log y dock presentes.

**Notas:** docs/progress.md tiene qué quedó, cómo probar a mano y pendientes. Revisión con godot-code-review: sin hallazgos altos; se arreglaron parámetros sin usar en el export plugin y el banner que no se refrescaba con el dock ya visible. Pendiente: link al artifact de diseño (spec §9) para M1.

## M1 — Transporte y ACP mínimo  (11/14, 10 en revisión)

AgentProcess + AcpClient + SessionModel y agente falso: initialize → session/new → session/prompt con streaming al dock, y session/cancel. Agent Log con canales. QuotaMonitor en modo observación (canal quota).

**Hecho cuando:**
- Contra el agente falso: un prompt, una respuesta en streaming y una cancelación limpia.
- Contra Claude Code real: "hola" recibe respuesta y la verificación de cuota (qué reporta el adapter y cómo se ve un error de límite) está documentada en docs/decisions.md.

### Conseguir el mockup de UI (artifact de diseño, 4 pantallas) · Hecho

**Terminada:** 2026-10-21 · **Prioridad:** alta · **Tamaño:** S

La spec §9 pide respetar la estructura de un mockup de 4 pantallas (dock, main screen One-shot, Agent Log, revisión en Script Editor). Hay un artifact con el diseño, pero no aparece entre los artifacts listables desde esta cuenta: pedir el link al usuario y leerlo antes de construir la UI del dock en M1.

**Prueba:** docs/design/mockup/ tiene los 4 .dc.html + canvas.json; docs/design/README.md resume cada pantalla.

**Notas:** Link del usuario: https://claude.ai/chat/f88dea66-401f-4ccc-92af-c85b98fcf7d1?artifact=c94c1e9f-2037-475f-830c-e0671d0ef62d (Design artifact; el contenido está en project/*.dc.html, no en la página). Diferencias con la spec anotadas en el README: paquete del adapter (npx @agentclientprotocol/claude-agent-acp, a verificar con npm view en M1), sidecar .sh de ejemplo, severidades y Settings en Project Settings.

### 1.2 AgentProcess: lanzar el agente y leer stdout/stderr en threads · Revisión

**Prioridad:** alta · **Tamaño:** M · **Responsable:** Claude

OS.execute_with_pipe con el comando del perfil; Thread lector de stdout línea por línea y otro de stderr; send_line(String); señales line_received, stderr_received y exited(code) vía call_deferred. Mata el proceso al deshabilitar el plugin o cerrar el editor (spec §3, §15).

**Prueba:** tests/acp_session_check.gd lanza el agente falso como proceso real y pasa los escenarios basic, cancel y crash (32 checks) en 4.4.1, 4.7.2 y 4.8-beta1. El proceso queda muerto después de stop().

**Notas:** addons/godot_agent/transport/:
- agent_process.gd: hay threads para stdout, stderr y un watcher de salida. El exit se emite después de la última línea de stdout.
- process_tree.gd: mata el árbol de procesos con pgrep -P / taskkill /T. Además se recuerdan los hijos, porque npx deja huérfano a node.
- command_resolver.gd: busca el comando en PATH y en las carpetas de fnm, nvm, volta y similares, y agrega la carpeta del ejecutable al PATH del hijo.

Bug en Godot 4.4.x, corregido en 4.5 (verificado con 4.5.1 y 4.6): cerrar o liberar el FileAccess de un pipe de execute_with_pipe cierra fds equivocados, incluso el fd 0, y el siguiente proceso muere con SIGPIPE. Workaround: en 4.4 los pipes viejos se retienen en un array estático (pipe_close_is_broken). Anotar en D11.

OS.is_process_running da error con pids que no son hijos directos o que ya fueron cosechados.

### 1.3 AcpClient: JSON-RPC 2.0 sobre líneas · Revisión

**Prioridad:** alta · **Tamaño:** M · **Responsable:** Claude

Mapa id → pendiente, request(method, params) usable con await, notify(), handlers para requests entrantes del agente, -32601 para métodos desconocidos, JSON inválido logueado sin romper (spec §4).

**Prueba:** tests/unit/test_acp_client.gd (7 tests) cubre:
- ids fuera de orden;
- líneas vacías e inválidas;
- -32601;
- handlers sync y async;
- notificaciones;
- fail_all_pending;
- fallo de envío.

**Notas:** addons/godot_agent/acp/acp_client.gd.
- Los ids float del JSON se normalizan a int.
- Un handler puede devolver un valor o un AcpClient.Response.failure(...).
- Cada mensaje queda en el log, en el canal acp, con su raw.

### 1.4 SessionModel: estado de la conversación · Revisión

**Prioridad:** alta · **Tamaño:** M · **Responsable:** Claude

Fuente de verdad: entradas (mensajes con merge de chunks, thoughts), tool calls por toolCallId, plan, modo, permisos pendientes, uso de tokens, comandos disponibles. Señales granulares; no hace IO. Variantes desconocidas de session/update se loguean y se ignoran.

**Prueba:** tests/unit/test_session_model.gd (7 tests) cubre:
- merge por messageId;
- thoughts;
- grupos de tool calls;
- cancel → cancelled;
- plan (que se mueve al final);
- variantes desconocidas;
- content_to_text.

**Notas:** Archivos: session/session_model.gd, chat_entry.gd y tool_call.gd.
- Estados: DISCONNECTED/STARTING/READY/PROMPTING/CANCELLING/FAILED.
- HarnessMode vive en el modelo.
- Señal entry_removed: el plan se re-ubica al final.

### 1.5 Perfiles de agentes y HarnessSettings · Revisión

**Prioridad:** alta · **Tamaño:** S · **Responsable:** Claude

Perfiles (id, display_name, command, args, env, default) en EditorSettings godot_agent/. Perfil Claude Code con el adapter ACP verificado con npm view; Gemini/Codex/custom editables sin flags inciertos. Aviso si hay ANTHROPIC_API_KEY en el entorno (spec §4.4, §11).

**Prueba:** Al habilitar el plugin aparecen godot_agent/agents/profiles y ui/accent_color en Editor Settings. El botón de ajustes del dock edita los perfiles como JSON y valida que los ids sean únicos. Con ANTHROPIC_API_KEY en el entorno, al iniciar sesión aparece un aviso.

**Notas:** core/agent_profile.gd y core/harness_settings.gd (EditorSettings, o memoria en tests).
- Perfil por defecto: npx -y @agentclientprotocol/claude-agent-acp, verificado con npm view (D13).
- En env, "$VAR" se resuelve del entorno del editor, así no se guardan claves.
- Gemini y Codex quedan como entradas editables.
- ui/settings/profiles_dialog.gd es un stub hasta M7.

### 1.6 Agente falso en GDScript (tests/fake_agent.gd) · Revisión

**Prioridad:** alta · **Tamaño:** M · **Responsable:** Claude

Corre con godot --headless --script, lee stdin con OS.read_string_from_stdin y responde ACP según un guion JSON en tests/scripts/*.json: chunks, tool calls con diff, pedidos de permiso, plan, errores, cancelación (spec §13).

**Prueba:** Manual: el comando `godot --headless --no-header --path . --script res://tests/fake_agent.gd -- --scenario=res://tests/scripts/basic.json` responde initialize, session/new y prompt. Lo usa tests/acp_session_check.gd.

**Notas:** Guiones en tests/scripts/: basic.json, cancel.json y crash.json.
- Pasos: chunk, thought, update, delay, request, garbage, stop, error y exit.
- quit() no termina el proceso mientras un thread está bloqueado en stdin. Por eso "exit" se mata a sí mismo (OS.kill) y un EOF en stdin termina el proceso.
- Ojo con el shim stdio de M3: le pasa lo mismo.

### 1.7 Dock: header, modos, lista de mensajes y composer · Revisión

**Prioridad:** alta · **Tamaño:** L · **Responsable:** Claude

Según docs/design (pantalla 1): selector de perfil, título de sesión, historial/nueva sesión/ajustes, selector de 4 modos, burbujas de usuario, texto del agente en RichTextLabel (Markdown→BBCode mínimo), thoughts colapsados, composer con enviar/detener, Ctrl+Enter y Esc. Acento único configurable (#f0a85a).

**Prueba:** `$G -e --path . -- --godot-agent-ui-test=ui_demo --godot-agent-ui-shot=x.png` con el guion ui_demo. Captura revisada en 4.8-beta1 y 4.4.1: burbuja, thought colapsado, Markdown, plan, tool calls con diff, medidor 41k/200k y selector Opus. Prueba manual en docs/progress.md (M1).

**Notas:** ui/dock/:
- agent_dock.gd/.tscn;
- conversation_view.gd: pull + push, tope de 250 vistas, sigue el fondo;
- composer.gd: CodeEdit con completado de / y @, chips, Ctrl+Enter, Esc;
- entries/: user, agent/thought, notice, tool_group, diff_card, plan.

También ui/agent_theme.gd, ui/editor_context.gd y ui/markdown/markdown_bbcode.gd (con test).

Historial deshabilitado hasta M7.

### 1.8 Agent Log: canales, filtros, copiar y modo raw · Revisión

**Prioridad:** alta · **Tamaño:** M · **Responsable:** Claude

Modelo AgentLog acotado (ring buffer) con canales acp/mcp/fs/perm/proc/cmp; panel con columnas hora · canal · mensaje en mono, filtros por canal, botón copiar y modo raw con los JSON-RPC completos (spec §9.3).

**Prueba:** La captura de ui_demo muestra el Agent Log con los canales coloreados. "Ver log" (desde el aviso de error) abre el panel con EditorSurfaces.make_visible.

**Notas:** El panel está en ui/log_panel/agent_log_panel.gd/.tscn y el modelo en core/agent_log.gd.
- El modelo es un ring buffer de 2000 entradas. Guarda el raw de cada entrada, hasta 20k caracteres.
- El panel muestra el raw recortado a 4000.
- Los canales son acp, mcp, fs, perm, proc y cmp. El stderr del agente va al canal proc.

### 1.9 Flujo de sesión: initialize → session/new → prompt → cancel · Revisión

**Prioridad:** alta · **Tamaño:** M · **Responsable:** Claude

SessionController que orquesta el ciclo: initialize con clientCapabilities, authenticate informativo, session/new con cwd, session/prompt con streaming, session/cancel (tool calls a cancelled, permisos a cancelled). Errores de transporte en la UI con acción concreta (Reintentar, Ver log).

**Prueba:** tests/acp_session_check.gd pasa sus 32 checks en 4.4.1, 4.7.2 y 4.8-beta1. Cubre:
- streaming;
- set_mode;
- set_config_option;
- cancel con tool call → cancelled;
- caída → FAILED con acciones;
- reintentar.

**Notas:** session/session_controller.gd (D12).
- authenticate es informativo: si session/new falla con authMethods, se listan en el error.
- Los permisos pendientes que se cancelan llegan en M2.

### 1.10 Tests unitarios de transporte y sesión · Revisión

**Prioridad:** alta · **Tamaño:** S · **Responsable:** Claude

Framing de líneas JSON (partidas, varias por lectura), correlación de ids, requests entrantes y -32601, merge de chunks y variantes desconocidas en SessionModel (spec §13).

**Prueba:** run_all: 19 tests, 79 checks, 0 fallos en 4.4.1, 4.7.2 y 4.8-beta1.

### 1.11 Verificar M1 contra el agente falso y Claude Code real · Revisión

**Prioridad:** alta · **Tamaño:** S · **Responsable:** Claude

Prueba de integración headless: prompt, respuesta en streaming y cancelación limpia contra fake_agent. Contra Claude Code real: "hola" recibe respuesta. Actualizar docs/progress.md.

**Prueba:** Contra el agente falso: acp_session_check.gd y el ui-test. Contra Claude Code real: tests/claude_smoke_check.gd mandó "hola", recibió "¡Hola! Estoy dentro del editor de Godot…" con end_turn y no quedó ningún proceso vivo.

**Notas:** docs/progress.md (sección M1) y decisions.md D11–D14.

**Relacionadas:** 1.13 Verificar qué cuota reporta el adapter de Claude Code

### 1.12 QuotaMonitor en modo observación (canal quota) · Pendiente

**Prioridad:** alta · **Tamaño:** S · **Responsable:** Claude · **Etiquetas:** `quota`

Spec §10.1 y M1 (actualizado): QuotaMonitor nuevo en la arquitectura. En M1 solo observa: loguea crudo en un canal nuevo `quota` del Agent Log cada `usage_update` de ACP y cualquier aviso o error de límite (error JSON-RPC en session/prompt, notice o mensaje del agente). Guarda el último payload crudo para mapear los campos después. No estima cuota a partir de tokens, no consulta endpoints no documentados y no lee archivos internos ni credenciales del agente.

**Bloquea a:** 1.13 Verificar qué cuota reporta el adapter de Claude Code

### 1.13 Verificar qué cuota reporta el adapter de Claude Code · Pendiente

**Prioridad:** alta · **Tamaño:** S · **Responsable:** Claude · **Etiquetas:** `quota`

Spec M1 (actualizado): con el adapter real (@agentclientprotocol/claude-agent-acp), documentar en docs/decisions.md qué reporta realmente: cuota del plan con hora de reinicio, solo tokens de la sesión, o nada; y cómo se ve un error de límite. Fuentes: el canal quota de una sesión real y el código del adapter. El diseño de §10.1 (nombres de campo y patrones de límite) se ajusta a eso. Criterio de M1: "hola" recibe respuesta y la verificación de cuota está documentada.

**Bloquea a:** 1.14 Agente falso: cuota simulada y errores de límite; 6.6 QuotaMonitor: fuentes, estados y umbrales

**Bloqueada por:** 1.12 QuotaMonitor en modo observación (canal quota)

**Relacionadas:** 1.11 Verificar M1 contra el agente falso y Claude Code real

### 1.14 Agente falso: cuota simulada y errores de límite · Pendiente

**Prioridad:** media · **Tamaño:** S · **Responsable:** Claude · **Etiquetas:** `quota`

Spec §13 (actualizado): el agente falso emite también `usage_update` con cuota simulada y errores de límite con hora de reinicio, según el guion JSON. Usa la forma que salga de m1-13. Es la base de los tests del QuotaMonitor y de la verificación de M6 (cuota al 90 % y después límite).

**Bloqueada por:** 1.13 Verificar qué cuota reporta el adapter de Claude Code

## M2 — Tool calls, diffs y permisos  (8/8, 8 en revisión)

Render de tool_call/tool_call_update, tarjeta de diff y plan; session/request_permission con PermissionPolicy; fs/read_text_file y fs/write_text_file con sincronización editor ↔ disco.

**Hecho cuando:**
- Pedirle a Claude Code que edite un script abierto: el diff se muestra, el permiso se pide en Construir y se auto-deniega en Preguntar, y el editor muestra el cambio sin diálogos ni pérdida de buffer.

### 2.1 Render de tool calls en el dock · Revisión

**Prioridad:** alta · **Tamaño:** M · **Responsable:** Claude

Grupo colapsable de tool calls (tool_call / tool_call_update por toolCallId): estado ✓/✗/spinner, título, kind, resumen, content de tipo content (texto/imagen), diff y terminal ("no soportado"), locations clickeables que abren archivo y línea.

**Prueba:** - tests/unit/test_tool_group_view.gd: decode_image con png válido, mime no soportado, datos vacíos y basura.
- run_all: 35 tests y 229 checks en 4.8.
- Captura de la UI con ui_demo.json.

**Notas:** entries/tool_group_view.gd:
- estado, spinner, nombre (godot.* en violeta), resumen y ubicaciones clickeables;
- diffs como tarjetas; terminal "no soportado";
- texto de error en rojo; salida de texto plegada ("▸ salida · N líneas", hasta 40 líneas o 4000 caracteres, monoespaciada);
- imágenes base64 png, jpeg o webp como miniatura de hasta 160 px; resource_link y resource como 📎 uri.

La firma de refresco usa un hash del content para redibujar cuando cambia en un update.
El botón undo sigue oculto hasta M4.

### 2.2 Tarjeta de diff y plan colapsable · Revisión

**Prioridad:** alta · **Tamaño:** S · **Responsable:** Claude

Tarjeta de diff: ruta, +N/−M, primeras líneas coloreadas y "Abrir en Script". Plan: reemplazo completo en cada update, estados por entrada, colapsable.

**Prueba:** - tests/unit/test_line_diff.gd: igualdad, alta, baja, reemplazo, conteos y first_changed_line.
- test_session_model: el plan reemplaza y se re-ubica (entry_removed).
- Captura de la UI con ui_demo.json: tarjeta de diff y plan visibles.

**Notas:** Adelantado en M1:
- entries/diff_card.gd con core/line_diff.gd (LCS);
- entries/plan_view.gd, que se re-ubica al final si el agente lo reemplaza.

Falta el test de line_diff.

### 2.3 PermissionPolicy con matriz configurable · Revisión

**Prioridad:** alta · **Tamaño:** S · **Responsable:** Claude

Matriz modo × grupo → allow/ask/deny con los defaults de la spec §7, guardada en un Resource por proyecto (D5). Mapeo de kind de ACP a grupos. "Siempre en esta sesión" solo en memoria. Tests unitarios de la matriz.

**Prueba:** tests/unit/test_permission_policy.gd cubre:
- la matriz por defecto completa;
- que "siempre en esta sesión" solo levanta un ask;
- overrides válidos e inválidos;
- el mapeo de kind a grupo.

También acp_session_check, en los escenarios permisos/build y permisos/ask.

**Notas:** session/permission_policy.gd.
- Los overrides vienen de config/project_config.gd (Resource por proyecto, D5). Lo carga plugin.gd con load_or_default; el .tres se crea recién cuando se guarda desde Settings (M7).
- Las tools mcp__godot__* se permiten a nivel ACP porque las decide el server MCP (M3).

### 2.4 session/request_permission con tarjeta de permiso · Revisión

**Prioridad:** alta · **Tamaño:** M · **Responsable:** Claude

Consultar PermissionPolicy: allow/deny se responden solos eligiendo la opción adecuada; ask crea un pedido en SessionModel y la tarjeta muestra las opciones del agente como botones. Respuesta selected/cancelled. Canal perm en el log.

**Prueba:** acp_session_check, con el guion tests/scripts/permissions.json:
- En Construir aparecen dos tarjetas (edición y comando).
- "Siempre en esta sesión" se responde al agente como allow_once y la segunda edición se permite sola.
- En Preguntar, todo se auto-deniega sin tarjeta y con aviso.

**Notas:** El handler está en session_controller._on_request_permission y la tarjeta en ui/dock/entries/permission_view.gd.
- Un permiso de edición concedido preautoriza, durante 2 minutos, el fs/write_text_file que le sigue al mismo archivo. Así no hay doble tarjeta: el adapter pide permiso y después escribe por fs/*.
- SessionController.authorize(group, title, desc, diff, timeout) queda listo para las tools MCP de M3.
- Al cancelar el turno, los permisos pendientes se responden como cancelled.

### 2.5 fs/read_text_file y fs/write_text_file · Revisión

**Prioridad:** alta · **Tamaño:** M · **Responsable:** Claude

Leer devuelve el buffer del Script Editor si el archivo está abierto con cambios sin guardar (soporta line/limit). Escribir pasa por la política (edit_files) y la sincronización de §8. Rechazar rutas fuera del proyecto salvo directorios extra.

**Prueba:** Lo cubren:
- tests/unit/test_fs_handler.gd: rutas fuera del proyecto, .., relativas y .godot/; line/limit; prefiere el buffer; escritura denegada;
- acp_session_check: write y read reales a través del agente falso.

**Notas:** acp/fs_handler.gd no depende del editor.
- buffer_reader = EditorSync.buffer_text (el buffer solo se usa si tiene cambios sin guardar).
- after_write = EditorSync.after_agent_write.
- Las rutas extra salen de ProjectConfig.extra_fs_roots.
- Escribir .uid o .import se permite, pero queda un aviso en el log.

### 2.6 Sincronización editor ↔ disco · Revisión

**Prioridad:** alta · **Tamaño:** L · **Responsable:** Claude

Tras cada escritura (fs/write, tool call edit con diff, watcher de mtime): update_file o scan, recargar scripts abiertos sin perder el cursor ni mostrar el diálogo; si el usuario tenía cambios, marcar conflicto (ver diff / usar la del agente / mantener la mía). Aviso para .tscn abiertos y para .uid/.import (spec §8).

**Prueba:** `godot -e --path . -- --godot-agent-sync-test` pasa en 4.4.1, 4.7.2 y 4.8-beta1. Prueba tres casos:
- A: el watcher toma una escritura externa, el cursor sigue a su línea, el buffer no queda modificado, no hay diálogos tras el focus-in y un solo Ctrl+Z la deshace.
- B: con cambios sin guardar, el buffer no se pisa, hay conflicto y resolve_use_disk funciona.
- C: after_agent_write actualiza en el acto.

Unit: tests/unit/test_editor_sync.gd (replace_buffer).

**Notas:** editor/editor_sync.gd (Node hijo del plugin). Cuatro entradas:
- fs/write (after_agent_write);
- un tool call de edición, borrado o movida completado (plugin._on_tool_call_changed);
- un watcher de mtime cada 0,5 s para los scripts abiertos;
- buffer limpio: replace_buffer cambia solo el tramo que difiere, en una operación deshacible, y conserva cursor y scroll. Después _adopt_resource guarda el Script con ResourceSaver para alinear las fechas.

Hallazgo: el Script Editor guarda la fecha de cada pestaña (edited_file_data.last_modified_time) y solo la actualiza con la señal resource_saved de EditorNode. ResourceSaver no la emite. Sin esa señal, al volver el foco recarga el archivo con set_text y agrega un paso de undo. _notify_saved la emite a mano. Funciona igual en 4.4, 4.7 y 4.8.

Si el buffer tiene cambios sin guardar, emite conflict_detected y el dock muestra un aviso con tres acciones: ver diff (DiffDialog), usar la del agente y mantener la mía.
Si es una escena abierta, avisa con la acción "recargar escena".

### 2.7 Prompt de sistema y contexto del prompt · Revisión

**Prioridad:** media · **Tamaño:** S · **Responsable:** Claude

Archivo editable del addon con el prompt de sistema (tools godot.*, reglas de §8, modo actual, respetar CLAUDE.md) que va en el primer session/prompt. Chips de contexto (escena actual, selección, + contexto) como resource links o recursos embebidos.

**Prueba:** La UI test (`--godot-agent-ui-test=ui_demo`) agrega res://project.godot con add_context_files y verifica dos cosas: que aparece el chip y que desaparece al enviar. La captura muestra el link en el mensaje del usuario.

El prompt de sistema con Claude real se prueba en m2-08.

**Notas:** config/system_prompt.md va en el primer prompt y en cada cambio de modo (D14).

Chips de contexto:
- escena actual: resource_link;
- selección: texto;
- captura: image;
- "+ contexto": un menú con "Script actual", "Archivo del proyecto…" (EditorFileDialog, varios archivos) y "Captura del viewport".

Los archivos agregados a mano van como resource_link solo en el próximo prompt; después se limpian, igual que la captura. Escena y selección quedan mientras no se descarten.
API: agent_dock.add_context_files(paths).

### 2.8 Verificar M2 · Revisión

**Prioridad:** alta · **Tamaño:** S · **Responsable:** Claude

Guiones del agente falso con tool calls, diff, permisos y fs/*. Con Claude Code: editar un script abierto muestra el diff, pide permiso en Construir, se auto-deniega en Preguntar y el editor muestra el cambio sin diálogos ni pérdida de buffer. Actualizar progress.

**Prueba:** Todo pasa en 4.4.1, 4.7.2 y 4.8-beta1:
- run_all: 35 tests, 229 checks;
- acp_session_check: 53 checks;
- export_check;
- sync-test;
- ui-test ui_demo;
- cycle-test.

claude-edit-test con Claude Code real: PASS en 4.8-beta1 y en 4.4.1.

**Notas:** Nueva prueba con Claude real en el plugin de desarrollo: `--godot-agent-claude-edit-test`.
- **Construir**: llegó el permiso "Edit tests/tmp/claude_target.gd" (grupo edit_files) con diff; archivo y buffer quedaron con `speed := 2`, sin cambios pendientes ni diálogos.
- **Preguntar**: Claude no intentó editar ("la sesión está en modo Preguntar (y en modo plan)") y el archivo no cambió. El auto-deny de un pedido real lo cubre acp_session_check.
- No quedan procesos del adapter.

Ruido conocido: la prueba de ciclo puede crecer más de 50 objetos si corre justo después de export_check (el editor sigue escaneando). Repetida, pasa. Está anotado en progress.md.

Docs: progress.md (sección M2) y decisions.md (D15).

## M3 — Servidor MCP y tools de lectura  (7/7, 7 en revisión)

McpServer con token, initialize, tools/list y tools/call; tools read y diagnostics; fallback del shim stdio.

**Hecho cuando:**
- Claude Code lista las tools `godot.*` y responde "¿cuántos nodos tiene Main.tscn?" usando `scene_tree`.
- Tests del parser HTTP con requests partidos y concatenados.

### 3.1 Parser HTTP/1.1 mínimo · Revisión

**Prioridad:** alta · **Tamaño:** S · **Responsable:** Claude

Parser incremental: request line, headers, Content-Length, requests partidos y concatenados, Content-Length incorrecto, sin chunked (411/400). Tests unitarios.

**Prueba:** tests/unit/test_http_parser.gd (5 tests, 25 checks):
- un request;
- byte a byte y dos requests concatenados, con body UTF-8;
- body incompleto;
- chunked, Content-Length inválido o negativo, request line rota, HTTP/2, headers enormes y body enorme;
- serialización de la respuesta.

**Notas:** mcp/http_parser.gd (RefCounted): feed(bytes) devuelve los requests completos.
- Headers en minúscula; body por Content-Length; keep_alive() según la versión y Connection.
- Errores 400, 411 (Transfer-Encoding), 413 (body de más de 8 MB), 431 (headers de más de 16 KB) y 505. Después de un error no parsea más: la conexión se cierra.
- HttpParser.response(status, body, headers) serializa la respuesta.

### 3.2 McpServer: TCPServer en 127.0.0.1 con token · Revisión

**Prioridad:** alta · **Tamaño:** M · **Responsable:** Claude

Puerto configurable (0 = aleatorio), token Bearer por sesión, POST /mcp, Mcp-Session-Id, 202 para notificaciones, 401/404/405, Connection. Red no bloqueante (polling en _process); cada request se ejecuta en el hilo principal. initialize, notifications/initialized, tools/list, tools/call, ping.

**Prueba:** tests/unit/test_mcp_server.gd, con HTTP real contra el nodo:
- 401 (sin token y con token malo), 404, 405, 403 por Origin, 400 y 404 de sesión;
- initialize con versión y session id, notificación 202, tools/list, tools/call, -32602, -32601 y versión desconocida;
- dos requests pipelined en la misma conexión, respondidos en orden.

Pasa en 4.8 y 4.4.1.

**Notas:** mcp/mcp_server.gd (Node, hijo del plugin):
- TCPServer en 127.0.0.1 con polling no bloqueante en _process (D16), hasta 16 conexiones y keep-alive;
- cada conexión atiende sus requests en orden y puede esperar un permiso;
- token de 24 bytes aleatorios por arranque, comparado en tiempo constante;
- Origin no local → 403 (DNS rebinding); 401 con WWW-Authenticate; 404 de ruta o de Mcp-Session-Id desconocido; 405 para GET y DELETE (sin SSE); 400 por JSON inválido; 202 para notificaciones;
- métodos initialize (negocia la versión y devuelve Mcp-Session-Id e instructions), ping, tools/list y tools/call; -32601 y -32602.

El puerto sale de EditorSettings godot_agent/mcp/port (0 = aleatorio) y la URL queda en el log mcp.

### 3.3 ToolRegistry y base de tools · Revisión

**Prioridad:** alta · **Tamaño:** M · **Responsable:** Claude

Cada tool declara name, description, inputSchema, group y execute(args). Resultado {content, isError}; truncado de texto configurable con aviso; imágenes reescaladas a 1280 px; errores accionables; log con nombre, duración y resumen. Política del lado del server (ask con timeout).

**Prueba:** tests/unit/test_tool_registry.gd:
- list y orden;
- validación (required, tipo, desconocido, enum, float entero);
- tool desconocida y handler null;
- authorizer async que deniega;
- truncado y reescalado de imágenes;
- log;
- redacción del secreto.

**Notas:** mcp/mcp_tool.gd: `create(name, group, description, properties, required, handler)`.
- validate() revisa required, tipos básicos, enum y argumentos desconocidos, con mensajes accionables.
- Helpers text, error, image, int_arg y str_arg.

mcp/tool_registry.gd: call_tool siempre devuelve {content, isError}.
- Pasos: validación → authorizer (await; en plugin.gd es SessionController.authorize con permission_timeout_s de ProjectConfig) → handler.
- Si el handler devuelve null (error de script), responde un error.
- Trunca el texto a max_output_chars con un aviso y reescala imágenes PNG a max_image_side.
- Log en el canal mcp con nombre, args, duración y resumen. El raw va en JSON, sin el base64.

AgentLog.add_secret: el token MCP queda redactado en todo el log.

### 3.4 Tools de lectura · Revisión

**Prioridad:** alta · **Tamaño:** M · **Responsable:** Claude

project_info, list_files, scene_tree (compacto, propiedades no default, depth), get_node, editor_state (spec §6).

**Prueba:** `--godot-agent-mcp-test` (mcp_check.gd) en 4.4.1, 4.7.2 y 4.8 contra tests/fixtures/main_fixture.tscn:
- scene_tree: 5 nodos, position, speed=300, grupo y sin defaults; depth 0;
- get_node Timer: conexión timeout → Player::_on_timer_timeout y wait_time; nodo inexistente → isError;
- editor_state, list_files con pattern y project_info.

**Notas:** mcp/tools/read_tools.gd y mcp/tools/scene_access.gd. Todas devuelven texto compacto.
- project_info: versión, nombre, escena principal, renderer, features, autoloads, input map con eventos y plugins.
- list_files: lista de EditorFileSystem con tipo, pattern glob y recursive; hasta 2000 entradas.
- scene_tree:
  - con la escena abierta usa la del editor (con sus cambios sin guardar); si no, instancia del disco y libera;
  - una línea por nodo con tipo, instancia, script, grupos y propiedades no default (contra el default del script o de ClassDB);
  - depth y tope de 600 nodos.
- get_node: propiedades completas, conexiones persistentes, hijos. Si no lo encuentra, el error sugiere los hijos de la raíz.
- editor_state: escena actual y abiertas, selección, script abierto con línea, scripts abiertos y juego corriendo.

### 3.5 Tools de diagnóstico · Revisión

**Prioridad:** alta · **Tamaño:** M · **Responsable:** Claude

get_errors (errores y warnings desde una marca), validate_scripts (parse de scripts con errores por línea; fallback godot --headless --check-only), capture_editor_viewport 2d/3d como PNG base64.

**Prueba:** - Unit: tests/unit/test_diagnostic_tools.gd (parseo con ANSI, error de dependencia, ubicación, marcas).
- mcp-test en 4.4.1, 4.7.2 y 4.8:
  - get_errors ve un push_error nuevo desde la marca y no lo repite con la marca siguiente;
  - validate_scripts reporta "línea 4: … undefined_thing" del script roto y nada del sano;
  - capture 2d devuelve una imagen; un enum inválido da isError.

**Notas:** D18.
- core/error_collector.gd: stream numerado con marcas. Fuentes: Logger compilado en runtime en 4.5+, panel Output en 4.4 (formato inline "ERROR: archivo:línea - msg") y árbol de errores del Debugger.
- validate_scripts: subproceso con mcp/tools/script_checker.gd (marcas @@BEGIN/@@END en stderr), vía AgentProcess, con timeout de 60 s y tope de 400 scripts.
- capture_editor_viewport usa EditorContext.capture_viewport; el registro reescala a max_image_side.

### 3.6 Conectar el MCP en session/new y shim stdio · Revisión

**Prioridad:** alta · **Tamaño:** S · **Responsable:** Claude

Entrada http con header Authorization si mcpCapabilities.http; si no, shim stdio→HTTP en GDScript (godot --headless --script mcp_stdio_shim.gd con puerto y token por env).

**Prueba:** - mcp-test: el shim, lanzado con AgentProcess, responde initialize y tools/call editor_state, y no responde a notifications/initialized. Pasa en 4.4.1, 4.7.2 y 4.8.
- Con Claude real se usó la entrada http (el adapter anuncia http: true).

**Notas:** plugin._mcp_servers():
- si el agente anuncia mcpCapabilities.http, va una entrada http con el header Authorization;
- si no, StdioShimInstaller.server_entry, con OS.get_executable_path() y el shim copiado a user://godot_agent_mcp_shim con su propio project.godot (D17); URL y token por env.

mcp/mcp_stdio_shim.gd: un thread hace stdin → POST → stdout en orden y no escribe nada para las notificaciones (202). Mantiene el Mcp-Session-Id y reconecta. Si el server devuelve un error HTTP en un request, responde un error JSON-RPC.

### 3.7 Verificar M3 · Revisión

**Prioridad:** alta · **Tamaño:** S · **Responsable:** Claude

Tests de integración del server (HTTP real contra el editor headless). Claude Code lista las tools godot.* y responde "¿cuántos nodos tiene Main.tscn?" usando scene_tree. Actualizar progress.

**Prueba:** Pasan en 4.4.1, 4.7.2 y 4.8-beta1:
- run_all: 52 tests, 317 checks;
- acp_session_check: 53 checks;
- export_check;
- cycle;
- sync;
- ui;
- mcp-test.

claude-mcp-test con Claude real: PASS en 4.8.

**Notas:** `--godot-agent-claude-mcp-test` con Claude Code real en 4.8:
- el adapter anunció http y Claude Code 2.1.303 inicializó con MCP 2025-06-18;
- llamó a mcp__godot__scene_tree y respondió "tiene **5 nodos**: Main, Player, Sprite, Enemies, Timer".

La prueba de ciclo se volvió robusta: espera el escaneo del FS, toma la línea base después del primer ciclo y falla si queda huérfano un nodo con script del addon.

Bug encontrado y corregido: el set_process(false) en _ready del server lo apagaba después de start().
Docs: D16, D17, D18 y la sección M3 de progress.md.

## M4 — Tools de edición y ejecución  (6/6, 6 en revisión)

Grupos edit_scene, edit_files y run con undo; run_scene con captura de errores, autoload de playtest con su ciclo de vida, capture_game_frame e inputs simulados.

**Hecho cuando:**
- "Agregá un Label WaveLabel al HUD y conectá la señal X": aparece en el árbol, Ctrl+Z lo deshace en pasos y `run_scene` devuelve errores reales con un script roto.
- Tras un `run_scene`, un run manual y matar el editor a mitad de un playtest, el autoload no queda en `project.godot` y el test de export sigue pasando.

### 4.1 Tools edit_scene con undo · Revisión

**Prioridad:** alta · **Tamaño:** L · **Responsable:** Claude

add_node, set_properties, remove_node, reparent_node, rename_node, connect_signal (persistente), instantiate_scene, open_scene, save_scene. Toda mutación por EditorUndoRedoManager, una acción por tool call; devuelven el nombre del paso de undo.

**Prueba:** `godot --path . -e -- --godot-agent-edit-test` (addons/godot_agent_dev/edit_check.gd) llama por HTTP real a cada tool sobre una copia de main_fixture.tscn y verifica el árbol, los owners, los valores anteriores y nuevos, la señal persistente, los errores con sugerencia, que Ctrl+Z (la opción Undo del menú) deshace en pasos y que el undo de remove_node restaura los hijos con owner. Pasa en 4.4.1, 4.7.2 y 4.8-beta1.

**Notas:** - Valores JSON → propiedad: mcp/tools/value_coercion.gd (vectores, colores, enums por nombre, recursos res://, sintaxis de Godot), con test unitario.
- Una acción "Agente: …" por tool call, con custom_context en la raíz; el texto del resultado termina en "Paso de undo: «…»".
- EditorUndoRedoManager no expone undo(): editor/editor_undo.gd dispara la opción Undo del menú principal (PopupMenu hijo de MenuBar con atajo Ctrl+Z).
- La prueba recarga la escena si el editor restauró su pestaña de una corrida anterior; si no, open_scene ve la versión vieja.

### 4.2 Tools edit_files: create_scene y attach_script · Revisión

**Prioridad:** alta · **Tamaño:** S · **Responsable:** Claude

create_scene crea y guarda el .tscn con root_type/root_name; attach_script crea el script si no existe y lo adjunta con undo.

**Prueba:** edit_check.gd: create_scene crea el .tscn y no pisa uno existente (error); attach_script crea el script ("(creado)") y lo adjunta con undo; rechaza un script con una base incompatible; save_scene persiste la instancia y el script. Pasa en 4.4.1, 4.7.2 y 4.8.

**Notas:** Grupo edit_files: en el modo Revisar piden permiso aunque edit_scene esté permitido. create_scene no abre la escena; el agente usa open_scene.

### 4.3 Autoload de playtest y EditorDebuggerPlugin · Revisión

**Prioridad:** alta · **Tamaño:** L · **Responsable:** Claude

Canal del debugger con prefijo godot_agent:. El probe captura frames y reproduce inputs {t, action, pressed}. Ciclo de vida: alta en _build() solo si el run lo pidió el harness (u opción en Settings), baja al terminar la sesión de debug o tras stop, limpieza al arrancar (spec §6).

**Prueba:** `tests/run_in_xvfb.sh $G --godot-agent-run-test` (addons/godot_agent_dev/run_check.gd), con el editor en Xvfb y OpenGL. Después de run_scene, de un juego que terminó solo y de un run manual, el autoload no está en ProjectSettings ni en project.godot del disco. Un run manual no lo registra y capture_game_frame responde "sin probe". El probe reproduce los inputs (Output con "ui_accept recibido/soltado") y devuelve un frame rojo. Pasa en 4.4.1, 4.7.2 y 4.8-beta1.

**Notas:** - Alta en EditorPlugin._build() si run_tools.harness_requested (o playtest_on_manual_runs). play_custom_scene llama a _build() de forma sincrónica.
- add/remove_autoload_singleton no guardan project.godot y el juego lo lee del disco, así que PlaytestAutoload.register/unregister llaman a ProjectSettings.save().
- Baja en cuanto arranca la sesión de debug (EditorDebuggerSession.started se emite después de que el juego manda su PID, cuando ya leyó project.godot), y otra vez en stopped, en stop_scene y si el juego no llegó a arrancar. Esto achica la ventana de riesgo a lo que tarda en arrancar el juego.
- Canal godot_agent: playtest/playtest_debugger.gd (EditorDebuggerPlugin) ↔ runtime/playtest_probe.gd. El motivo de una pausa del debugger se lee del panel Stack Trace (la sesión no lo expone).
- 4.7.2: con una variable miembro, el juego reportaba dos "get_node() with absolute paths" en @implicit_new del probe. Sin la variable no pasa, así que el probe queda sin variables miembro (D20).
- Las pruebas que lanzan el juego corren en Xvfb (D21): en el escritorio, la ventana del editor robó el foco y quedó "bil" tipeado en un fixture.

### 4.4 run_scene, stop_scene y capture_game_frame · Revisión

**Prioridad:** alta · **Tamaño:** M · **Responsable:** Claude

run_scene corre la escena (play_custom_scene/play_current_scene), espera N segundos o la salida y devuelve errores y Output capturados; capture_game_frame pide un frame al probe; stop_scene detiene.

**Prueba:** run_check.gd por HTTP real:
- run_scene con inputs → "sigue corriendo", "Inputs: 2 de 2", Output del juego y ningún error del juego;
- capture_game_frame → PNG con el centro rojo (ColorRect del fixture);
- stop_scene;
- script roto → "se detuvo en el debugger" con "queue_free" y run_broken.gd;
- juego que termina solo → "terminó solo" con su Output;
- acción inexistente y capture sin juego → isError.
Pasa en 4.4.1, 4.7.2 y 4.8-beta1.

**Notas:** mcp/tools/run_tools.gd.
- run_scene no cierra el juego: el agente sigue con capture_game_frame o stop_scene. Si ya había un juego corriendo, lo reinicia.
- `seconds` se cuenta desde que el probe dice ready (arranque: hasta 20 s).
- Output = lo nuevo del panel Output, o todo si el editor lo limpió al correr (últimas 150 líneas). Errores = ErrorCollector.entries_since(marca); devuelve la marca para get_errors.
- Con un error de script el juego queda pausado en el debugger y el reporte trae el motivo y la ubicación.

### 4.5 Botón "↶ undo" en los tool calls del dock · Revisión

**Prioridad:** media · **Tamaño:** S · **Responsable:** Claude

Los tool calls MCP de edición registran su paso de undo; el dock muestra "↶ undo" y lo deshace si sigue siendo el último paso de esa escena (si no, avisa).

**Prueba:** edit_check.gd simula un tool call ACP `mcp__godot__add_node` con rawInput igual a los args; la acción se une a ese tool call (can_undo), y `_undo_tool_call` lo deshace y marca undo_done. Con un cambio posterior en la escena no deshace y avisa con "Hubo cambios posteriores…". Además: permisos (Preguntar deniega con isError; Construir muestra la tarjeta y ejecuta al aceptar).

**Notas:** La unión es por nombre de tool y argumentos (el server MCP no conoce el toolCallId de ACP); las acciones pendientes vencen a los 60 s. Solo deshace si la versión de la historia de la escena y la de la global no cambiaron.

### 4.6 Verificar M4 · Revisión

**Prioridad:** alta · **Tamaño:** M · **Responsable:** Claude

"Agregá un Label WaveLabel al HUD y conectá la señal X": aparece en el árbol, Ctrl+Z lo deshace en pasos; run_scene devuelve errores reales con un script roto. Tras run_scene, run manual y editor matado a mitad de un playtest, el autoload no queda en project.godot y export_check sigue pasando.

**Prueba:** - Claude Code real (`tests/run_in_xvfb.sh $G --godot-agent-claude-scene-test`, 4.8 y 4.4.1): agregó WaveLabel bajo HUD con add_node y conectó WaveTimer.timeout con connect_signal; el primer Ctrl+Z deshizo la conexión y el siguiente el Label; el .tscn en disco no cambió.
- run_scene con un script roto: run_check.gd ("se detuvo en el debugger … queue_free … run_broken.gd").
- Autoload: run_check.gd (después de run_scene, de un juego que terminó solo y de un run manual) y `setsid -w tests/crash_check.sh $G` (editor matado con el autoload recién registrado y con un run en curso; al reabrir no está en project.godot y export_check pasa).
- Suite completa (unit 58/353, acp, export, cycle, sync, ui, mcp, edit, run) en 4.4.1, 4.7.2 y 4.8-beta1.

**Notas:** docs/progress.md (sección M4) y decisions.md D19–D21. El prompt de sistema suma reglas para edición en pasos chicos y para run_scene/capture/stop. Los editores 4.4/4.7 reescriben tests/fixtures/main_fixture.tscn al correr la suite (sin unique_id): se restaura con git checkout, igual que project.godot.

## M5 — Revisar y Script Editor  (0/4)

Modo Revisar, parseo de findings, anotaciones en el CodeEdit, tarjetas y lista de hallazgos; "Aplicar arreglo" y "Exportar a CLAUDE.md".

**Hecho cuando:**
- Revisar una carpeta con 3 bugs sembrados: aparecen anotados en las líneas correctas.

### 5.1 Parser tolerante de findings y checks · Pendiente

**Prioridad:** alta · **Tamaño:** S · **Responsable:** Claude

Extrae bloques {"findings":[…]} y {"checks":[…]} del texto del agente aunque vengan en fences, con texto alrededor o con campos faltantes; normaliza severidades bug|order|perf|style. Tests unitarios.

### 5.2 Anotaciones en el CodeEdit y tarjetas de hallazgo · Pendiente

**Prioridad:** alta · **Tamaño:** L · **Responsable:** Claude

Marcar la línea (fondo y gutter por severidad) en el Script Editor; tarjeta con título, explicación, sugerencia y botones Aplicar arreglo / Preguntar / Descartar. Banda "Revisión del agente · solo lectura" (docs/design pantalla 3).

### 5.3 Lista de hallazgos en el dock y acciones · Pendiente

**Prioridad:** alta · **Tamaño:** M · **Responsable:** Claude

Modo Revisar: aviso de solo lectura, contadores por severidad, lista con archivo:línea clickeable. "Aplicar arreglo" cambia a Construir y pide ese arreglo; "Exportar a CLAUDE.md" agrega convenciones previa confirmación; "Arreglar en modo Construir".

### 5.4 Verificar M5 · Pendiente

**Prioridad:** alta · **Tamaño:** S · **Responsable:** Claude

Revisar una carpeta con 3 bugs sembrados: aparecen anotados en las líneas correctas (agente falso con guion de findings y Claude Code real). Actualizar progress.

## M6 — One-shot  (0/8)

Pantalla principal completa, checkpoints git, presupuestos, checks, "Guiar al agente" y reglas de cuota del plan (§10.1).

**Hecho cuando:**
- En un proyecto vacío: "Pong de 2 jugadores con puntaje" completa al menos un playtest con captura, crea checkpoints y "Volver acá" restaura correctamente.
- Con el agente falso simulando la cuota al 90 % y después un error de límite con hora de reinicio: el One-shot pausa al terminar la tarea, crea cpN-quota, muestra la cuenta regresiva y retoma solo (o con confirmación) desde la tarea correcta.

### 6.1 Pantalla principal One-shot · Pendiente

**Prioridad:** alta · **Tamaño:** L · **Responsable:** Claude

Barra superior: objetivo, estado/fase, presupuestos con barras (cuota de la ventana, tiempo, tokens, playtests), la regla de cuota activa en una línea ("se pausa al 90 % en el próximo checkpoint"), cuenta regresiva hasta el reinicio en "Limitado", y Pausar/Detener (spec §9.2 actualizado). Columnas Plan (editable), Actividad (con "Guiar al agente") y Playtest/Verificaciones/Checkpoints. Barra inferior con resumen de cambios, "Revisar cambios" y "Aceptar todo" (docs/design pantalla 2).

### 6.2 Checkpoints git · Pendiente

**Prioridad:** alta · **Tamaño:** M · **Responsable:** Claude

git con OS.execute y args en array: repo limpio o commit WIP con confirmación, rama agent/<timestamp>, commit cpN antes de cada tarea del plan, "Volver acá" con reset --hard solo en la rama del agente + scan + recarga de escenas. Nunca merge ni push. Sin git: se desactiva con aviso.

### 6.3 Loop One-shot y presupuestos · Pendiente

**Prioridad:** alta · **Tamaño:** M · **Responsable:** Claude

Prompt inicial (objetivo, modo, plan, bloque checks, run_scene/capture/get_errors tras cada tarea). Presupuestos de tiempo, tokens y playtests: aviso al 80%, al 100% session/cancel + prompt de cierre con reporte final. "Guiar al agente" encola un prompt para el fin del turno.

### 6.4 Proyecto sandbox para one-shots · Pendiente

**Prioridad:** media · **Tamaño:** S · **Responsable:** Claude

tests/sandbox_project/ separado (con .gdignore para el anfitrión) para correr one-shots; nunca sobre el proyecto del addon.

### 6.5 Verificar M6 · Pendiente

**Prioridad:** alta · **Tamaño:** M · **Responsable:** Claude

En el sandbox: "Pong de 2 jugadores con puntaje" completa al menos un playtest con captura, crea checkpoints y "Volver acá" restaura correctamente. Cuota (spec M6 actualizado): con el agente falso simulando la cuota al 90 % y después un error de límite con hora de reinicio, el One-shot pausa al terminar la tarea, crea cpN-quota, muestra la cuenta regresiva y retoma solo (o con confirmación) desde la tarea correcta. Actualizar progress.

**Bloqueada por:** 6.8 Reglas de cuota en One-shot: pausa, Limitado y reanudación

### 6.6 QuotaMonitor: fuentes, estados y umbrales · Pendiente

**Prioridad:** alta · **Tamaño:** M · **Responsable:** Claude · **Etiquetas:** `quota`

Spec §10.1. Fuentes, en orden: (1) campos de cuota del `usage_update` (los de m1-13); (2) avisos y errores de límite, con parseo tolerante y patrones en un archivo editable del addon; (3) sin datos: solo tokens de sesión y "desconocido". Estados normal / aviso / pausa_programada / limitado / desconocido, expuestos al SessionModel. Umbrales por usuario en EditorSettings godot_agent/: aviso (75 %), pausa del One-shot (90 % o nunca), y al reiniciar la ventana retomar solo o esperar confirmación. Hora de reinicio conocida → timer; sin hora → backoff 5, 10, 20 y luego cada 60 min. Tests unitarios con payloads del agente falso.

**Bloquea a:** 6.7 Medidor de cuota en el dock y bloqueo en Limitado; 6.8 Reglas de cuota en One-shot: pausa, Limitado y reanudación

**Bloqueada por:** 1.13 Verificar qué cuota reporta el adapter de Claude Code

### 6.7 Medidor de cuota en el dock y bloqueo en Limitado · Pendiente

**Prioridad:** media · **Tamaño:** S · **Responsable:** Claude · **Etiquetas:** `quota`

Spec §9.1 y §10.1 (fuera de One-shot): barras de la ventana actual y semanal, con porcentaje y tiempo hasta el reinicio. Si el agente no informa cuota, se ocultan y queda el medidor de contexto del composer, con un tooltip que dice que el agente no la informa. En el dock solo hay avisos; en "Limitado", el botón enviar se deshabilita y muestra la cuenta regresiva.

**Bloqueada por:** 6.6 QuotaMonitor: fuentes, estados y umbrales

### 6.8 Reglas de cuota en One-shot: pausa, Limitado y reanudación · Pendiente

**Prioridad:** alta · **Tamaño:** M · **Responsable:** Claude · **Etiquetas:** `quota`

Spec §10.1.
- Aviso: banner en la pantalla Agent y entrada en el canal quota.
- Umbral de pausa: no corta el turno; al terminar la tarea actual y crear su checkpoint, no manda la siguiente y pasa a "Pausado por cuota".
- Límite a mitad de turno: los tool calls pendientes pasan a cancelled, se crea el checkpoint cpN-quota y se pasa a "Limitado".
- Reanudar (solo o con confirmación): session/prompt "continuá con el plan desde la tarea X; el estado está en el checkpoint cpN". Si la sesión se perdió, session/load o una sesión nueva con el resumen del plan, los checks y los checkpoints.
- El tiempo en Limitado no cuenta contra el presupuesto de tiempo.
- Barra superior: cuota de la ventana, regla activa en una línea ("se pausa al 90 % en el próximo checkpoint") y cuenta regresiva en Limitado.

**Bloquea a:** 6.5 Verificar M6

**Bloqueada por:** 6.6 QuotaMonitor: fuentes, estados y umbrales

## M7 — Pulido  (0/7)

Settings completos, historial de sesiones, Markdown→BBCode robusto, rendimiento con sesiones largas (>500 entradas) y README de uso.

**Hecho cuando:**
- Settings completos y persistidos.
- Sesión de más de 500 entradas sin degradación visible.
- README de uso escrito.

### Reportar a Godot el EditorDock huérfano de _has_main_screen (4.8) · Pendiente

**Prioridad:** baja · **Tamaño:** S

Reportar upstream un leak de 4.8: un plugin con `_has_main_screen() == true` deja un `EditorDock` huérfano cada vez que se deshabilita. No hay issue ni PR abierto (búsqueda del 2026-10-21: "EditorDock", "main screen", "has_main_screen", "remove_main_plugin", "LegacyMainScreenContainer", "orphan"). Si se arregla, el path de main screen con la API vieja vuelve a ser utilizable en 4.8 (hoy `ui/editor_surfaces.gd` usa `add_dock` en 4.8+, D9).

**Causa (editor/editor_main_screen.cpp, igual en 4.8-beta1 y en master al 2026-10-21):** desde #113051 (main screen plugins → docks, @KoBeWi), cuando un plugin legacy agrega su control al main screen, `LegacyMainScreenContainer::add_child_notify` crea por dentro un `EditorDock` con `memnew`, lo registra con `add_dock` y lo guarda en el meta `_dock` del plugin. Al deshabilitar, `EditorMainScreen::remove_main_plugin` llama a `EditorDockManager::remove_dock(dock)`, que lo saca del árbol (`_move_dock(p_dock, nullptr)`), pero nadie lo libera: no hay `queue_free`/`memdelete` y el meta `_dock` queda. Cada ciclo deja un `EditorDock` fuera del árbol, con su `visibility_changed` conectado.

**Repro mínimo:** proyecto vacío con un plugin:

```gdscript
@tool
extends EditorPlugin
var panel: Control
func _enter_tree() -> void:
	panel = Label.new()
	EditorInterface.get_editor_main_screen().add_child(panel)
func _exit_tree() -> void:
	panel.queue_free()
func _has_main_screen() -> bool:
	return true
func _get_plugin_name() -> String:
	return "LegacyMS"
```

Alternarlo 5 veces con `EditorInterface.set_plugin_enabled()` desde otro plugin y contar los `EditorDock` en `Node.get_orphan_node_ids()`. Medido en 4.8-beta1 (4d10419ca) y master e7cfa294a, headless: base 2, después 3, 4, 5, 6, 7 (uno más por ciclo). Con `add_dock` + `remove_dock` + `queue_free` desde el plugin no crece.

**Arreglo probable:** en `remove_main_plugin`, después de `remove_dock`, liberar el dock (`dock->queue_free()`) y `remove_meta("_dock")`. Ojo: el control del plugin está reparentado dentro del dock, así que liberarlo también libera el control si el plugin no lo hizo en `_exit_tree`.

**Aparte, menor:** sin `_get_plugin_icon()`, el mismo path da `WARNING: Trying to access a non-existing editor theme icon "LegacyMS"` en cada habilitado, porque `add_child_notify` hace `set_icon_name(get_plugin_name())`. Se puede mencionar en el mismo issue.

**Descartado:** el segundo problema que listaba D9 (`Condition "!is_inside_tree()"` en `grab_focus` al cerrar el editor con la main screen activa; crash por "Message queue out of memory" al cambiar antes a "Script" en headless) no se reproduce en 4.8-beta1 ni en 4.8-dev7. Se probó con un repro mínimo (`add_dock` en main screen, con la pantalla anterior en 2D y en Script; con y sin cambiar a "Script" en `_exit_tree`) y con el addon real sin el cambio a "2D" de `remove_all()` (prueba de captura, xvfb y headless). No se reporta.

- [ ] Armar el proyecto de repro y zipearlo
  Plugin legacy de arriba + plugin driver que alterna 5 veces y cuenta EditorDock huérfanos. Sin .godot/.
- [ ] Probar en el último 4.8 publicado antes de abrir el issue
  Si ya está arreglado, cerrar la tarea y anotar la versión.
- [ ] Abrir el issue con la plantilla de bug
  Tested versions: 4.8-beta1, master e7cfa294a; regresión de #113051. Incluir la causa y el arreglo probable.
- [ ] Decidir si se saca el cambio a 2D de remove_all()
  El error de grab_focus ya no se reproduce; el cambio a 2D es inofensivo pero su comentario describe un bug que no aparece. Actualizar D9.

**Prueba:** Issue abierto en godotengine/godot con el repro adjunto y su link en notes. Si se arregla upstream, `tests/plugin_cycle_check.gd` pasa en esa versión con la main screen por `_has_main_screen()`.

### 7.2 Diálogo de Settings completo · Pendiente

**Prioridad:** alta · **Tamaño:** L · **Responsable:** Claude

Navegación según docs/design pantalla 4. Secciones:
- Agentes (CRUD de perfiles).
- Herramientas/Permisos (matriz).
- Puerto MCP y regenerar token.
- Presupuestos default de One-shot.
- Cuota y límites (spec §9.5 y §11 actualizados): umbral de aviso, umbral de pausa del One-shot (o nunca) y al reiniciarse la ventana retomar solo o esperar confirmación. Se guardan por usuario en EditorSettings godot_agent/, porque la cuota es del plan, no del proyecto.
- Checkpoints on/off, ubicación del dock, color de acento, aviso y botón de filtro de presets.
Diálogo propio (no Project Settings: escribiría en project.godot).

### 7.3 Historial de sesiones · Pendiente

**Prioridad:** media · **Tamaño:** M · **Responsable:** Claude

user://godot_agent/sessions/<id>.json con eventos ACP normalizados; lista en el dock para reabrir y mostrar; session/load para reanudar si el agente lo soporta.

### 7.4 Markdown→BBCode robusto · Pendiente

**Prioridad:** media · **Tamaño:** S · **Responsable:** Claude

Párrafos, títulos, negrita, itálica, code inline, bloques de código, listas (anidadas), links, escapado de corchetes BBCode. Tests unitarios con casos borde.

### 7.5 Rendimiento con sesiones largas · Pendiente

**Prioridad:** media · **Tamaño:** M · **Responsable:** Claude

Más de 500 entradas sin degradación: límite de nodos vivos en la lista (las viejas se colapsan o se cargan bajo demanda), batch de chunks por frame. Medido con un guion largo del agente falso.

### 7.6 README de uso · Pendiente

**Prioridad:** media · **Tamaño:** S · **Responsable:** Claude

Instalación, perfiles, modos, permisos, MCP, One-shot, completado, exclusión del export (filtro de presets), actualizar sin perder la config, limitaciones conocidas por versión de Godot.

### 7.7 Verificar M7 · Pendiente

**Prioridad:** alta · **Tamaño:** S · **Responsable:** Claude

Suite completa en 4.4.1/4.7.2/4.8-beta1, settings persistidos, sesión de 500+ entradas, revisión godot-code-review sin hallazgos altos. Actualizar progress.

## M8a — Completado predictivo: núcleo sin IA  (0/7)

CompletionController, GhostTextRenderer de una línea, Tab/Esc, ProjectContext en segundo plano y proveedor local (reglas, recuperación, historial + ranker).

**Hecho cuando:**
- `@onready var ` sugiere nodos hijos reales con tipo y ruta; `func _` sugiere virtuales con firma; una línea repetida se sugiere al tipear su comienzo.
- Tab sin sugerencia sigue indentando y el popup nativo no se rompe.
- p95 < 10 ms por consulta en un proyecto de 200 scripts (medido y logueado).

### 8.1 CompletionController: disparo, debounce e invalidación · Pendiente

**Prioridad:** alta · **Tamaño:** M · **Responsable:** Claude

Uno por CodeEdit (enganche con editor_script_changed). Dispara con caret al final o solo cierres a la derecha, sin selección, popup nativo cerrado, archivo .gd. Invalida al mover de línea, tipear distinto, Esc o perder foco. Type-through. Atajo manual Alt+\ (spec §16.5).

### 8.2 GhostTextRenderer y aceptación · Pendiente

**Prioridad:** alta · **Tamaño:** M · **Responsable:** Claude

Texto atenuado con draw_string sobre el CodeEdit respetando fuente, scroll, wrap y zoom. Tab acepta (una acción de undo), Esc descarta; interceptar solo con sugerencia visible y popup cerrado. Documentar si gui_input alcanza o hace falta _input.

### 8.3 ProjectContext indexado en segundo plano · Pendiente

**Prioridad:** alta · **Tamaño:** L · **Responsable:** Claude

extends/class_name y API de la clase base (ClassDB), firmas de clases del proyecto, nodos hijos por escena que usa el script ($ y %), autoloads, input map, grupos, señales conectadas. Invalidación por archivo con filesystem_changed.

### 8.4 ContextRules · Pendiente

**Prioridad:** alta · **Tamaño:** M · **Responsable:** Claude

Reglas de la tabla §16.2a: @onready var, $/%, acciones de input, func _ virtuales con firma, .connect(, func _on_, grupos, preload/load, extends.

### 8.5 LineRetrieval, SessionHistory y Ranker · Pendiente

**Prioridad:** alta · **Tamaño:** M · **Responsable:** Claude

Índice de líneas normalizadas con puntaje frecuencia × cercanía × recencia; predicción de línea siguiente; historial de sesión estilo fish; ranker con umbral, margen y desempate por longitud; presupuesto <5 ms en el hilo principal.

### 8.6 Fixture, tests y benchmark del completado · Pendiente

**Prioridad:** alta · **Tamaño:** M · **Responsable:** Claude

tests/completion_fixture/ (escenas, %únicos, input map, autoloads, señales); tests de cada regla, retrieval y ranker; benchmark con 200 scripts generados: p95 < 10 ms por consulta, logueado.

### 8.7 Verificar M8a · Pendiente

**Prioridad:** alta · **Tamaño:** S · **Responsable:** Claude

@onready var sugiere nodos hijos reales con tipo y ruta; func _ sugiere virtuales con firma; una línea repetida se sugiere; Tab sin sugerencia indenta y el popup nativo no se rompe; p95 < 10 ms. Actualizar progress.

## M8b — Completado predictivo: calidad local  (0/6)

Línea siguiente y bloques cortos, ghost text multilínea, aceptación por palabra, n-gram, adaptación de identificadores, post-procesado completo, caché y set de evaluación.

**Hecho cuando:**
- El set de evaluación reporta resultados por fuente y el n-gram mejora la línea base de reglas + recuperación.

### 8b.1 Línea siguiente, bloques cortos y adaptación de identificadores · Pendiente

**Prioridad:** alta · **Tamaño:** M · **Responsable:** Claude

Recuperación de bloques de hasta N líneas mientras el corpus coincida y la indentación se mantenga; adaptación de un identificador (mana/health) aplicada al resto de la línea (spec §16.2b).

### 8b.2 Ghost text multilínea y aceptación por palabra · Pendiente

**Prioridad:** alta · **Tamaño:** M · **Responsable:** Claude

Primera línea inline y el resto en una caja translúcida bajo la línea actual (o +N si queda mal, documentado). Ctrl+→ acepta la siguiente palabra (accepted_partial).

### 8b.3 Lexer GDScript y modelo n-gram · Pendiente

**Prioridad:** alta · **Tamaño:** L · **Responsable:** Claude

Lexer simple (identificadores, keywords, operadores, strings, números, newline/indent/dedent); 4-gramas con stupid backoff, generación greedy hasta fin de línea o confianza baja; entrenamiento en WorkerThreadPool, actualización por archivo; corpus extra configurable.

### 8b.4 PostProcessor y SuggestionCache · Pendiente

**Prioridad:** alta · **Tamaño:** M · **Responsable:** Claude

Pasos de §16.6 en orden (tokens FIM, recorte al bloque, solapamiento con suffix, indentación del editor, descartes, chequeo de balanceo) y caché LRU por hash de prefix. Tests con salidas defectuosas reales.

### 8b.5 Set de evaluación del completado · Pendiente

**Prioridad:** alta · **Tamaño:** M · **Responsable:** Claude

tests/completion_eval/ con 30–50 recortes reales y script headless que corre cualquier combinación de fuentes: exact match de primera línea, similitud por tokens, cobertura, falsos positivos y latencia, por fuente.

### 8b.6 Verificar M8b · Pendiente

**Prioridad:** alta · **Tamaño:** S · **Responsable:** Claude

El set de evaluación reporta resultados por fuente y el n-gram mejora la línea base de reglas + recuperación. Ajustar umbrales priorizando precisión. Actualizar progress.

## M8c — Completado predictivo: LLM opcional  (0/4)

Proveedor Ollama y modo híbrido; después llama.cpp, Codestral, OpenAI-compatible y Gemini (experimental). Métricas e indicador en el Script Editor.

**Hecho cuando:**
- Cambiar de proveedor y de modo desde Settings sin reiniciar el editor.
- En híbrido, la sugerencia local nunca se demora por el LLM.
- Latencias p50 por fuente visibles en el log.

### 8c.1 Interfaz de proveedores, proveedor falso y modo híbrido · Pendiente

**Prioridad:** alta · **Tamaño:** M · **Responsable:** Claude

CompletionProvider (complete/cancel/describe) con LlmProvider sobre HTTPRequest reutilizado; tests/fake_completion_provider.gd con latencia configurable; modos solo local / híbrido / solo LLM con las reglas de §16.1 (el LLM nunca reemplaza ni demora lo local; una request en vuelo; secuencia).

### 8c.2 Proveedores Ollama, llama.cpp, Codestral, OpenAI-compatible y Gemini · Pendiente

**Prioridad:** media · **Tamaño:** L · **Responsable:** Claude

Endpoints verificados contra la documentación y anotados en decisions.md. Plantillas FIM por perfil, stop tokens, keys por nombre de variable de entorno, aviso de envío de código en perfiles remotos, Gemini marcado experimental. Contexto de ProjectContext con presupuesto y prioridad.

### 8c.3 Métricas, indicador y settings del completado · Pendiente

**Prioridad:** media · **Tamaño:** M · **Responsable:** Claude

Canal cmp con fuente, latencia, tamaños, resultado y caché (sin código salvo raw). Contadores p50/p95 y aceptación por fuente en Settings. Indicador en el Script Editor (estado y modo, clic on/off, atajo global). Settings de §16.10 aplicables sin reiniciar.

### 8c.4 Verificar M8c · Pendiente

**Prioridad:** alta · **Tamaño:** S · **Responsable:** Claude

Cambiar de proveedor y modo desde Settings sin reiniciar; en híbrido la sugerencia local nunca se demora por el LLM (proveedor falso lento); latencias p50 por fuente en el log. Ollama real si está instalado. Actualizar progress.
