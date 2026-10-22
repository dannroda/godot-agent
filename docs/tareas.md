# Tareas — agent-harness

> Export de `compass/`, que es la fuente de verdad. No editar: los cambios se hacen en `compass/` o con `scompass`, y este archivo se regenera.
> Generado: 2026-10-22

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

## M1 — Transporte y ACP mínimo  (14/14, 13 en revisión)

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

### 1.12 QuotaMonitor en modo observación (canal quota) · Revisión

**Prioridad:** alta · **Tamaño:** S · **Responsable:** Claude · **Etiquetas:** `quota`

Spec §10.1 y M1 (actualizado): QuotaMonitor nuevo en la arquitectura. En M1 solo observa: loguea crudo en un canal nuevo `quota` del Agent Log cada `usage_update` de ACP y cualquier aviso o error de límite (error JSON-RPC en session/prompt, notice o mensaje del agente). Guarda el último payload crudo para mapear los campos después. No estima cuota a partir de tokens, no consulta endpoints no documentados y no lee archivos internos ni credenciales del agente.

**Prueba:** tests/unit/test_quota_monitor.gd (4 tests), en 4.8-beta1 y 4.4.1:
- usage_update sin `_meta` → "sin datos de cuota";
- con `_meta["_claude/rateLimit"]` → guarda el SDKRateLimitInfo crudo y loguea "allowed_warning · five_hour · 82 % · umbral 75 % · reinicio …";
- texto "You've hit your limit · resets 3pm" → evento de límite; la prosa con "rate limiting" no;
- error de prompt con errorKind rate_limit → límite, y todos los errores de prompt quedan en el canal.

**Notas:** core/quota_monitor.gd, con patrones editables en config/quota_patterns.txt: los prefijos USAGE_LIMIT_ERROR_PREFIXES del SDK de Claude, anclados al principio de línea y sin patrones sueltos. Canal `quota` nuevo en AgentLog (color amarillo). SessionController le pasa cada usage_update, el texto del agente de cada turno y los errores de session/prompt. Todavía no expone estados al SessionModel: eso es m6-06.

**Bloquea a:** 1.13 Verificar qué cuota reporta el adapter de Claude Code

### 1.13 Verificar qué cuota reporta el adapter de Claude Code · Revisión

**Prioridad:** alta · **Tamaño:** S · **Responsable:** Claude · **Etiquetas:** `quota`

Spec M1 (actualizado): con el adapter real (@agentclientprotocol/claude-agent-acp), documentar en docs/decisions.md qué reporta realmente: cuota del plan con hora de reinicio, solo tokens de la sesión, o nada; y cómo se ve un error de límite. Fuentes: el canal quota de una sesión real y el código del adapter. El diseño de §10.1 (nombres de campo y patrones de límite) se ajusta a eso. Criterio de M1: "hola" recibe respuesta y la verificación de cuota está documentada.

**Prueba:** `$G --headless --path . --script tests/claude_smoke_check.gd -- "hola"` con Claude Code real (4.8-beta1): respondió y el canal quota mostró "cuota del plan: allowed · five_hour · reinicio 2026-10-21 05:40:00 · five_hour 63 % hasta … · seven_day 47 % hasta …", con el JSON crudo. Documentado en docs/decisions.md D22.

**Notas:** - Cuota: `usage_update._meta["_claude/rateLimit"]` (SDKRateLimitInfo) con status allowed/allowed_warning/rejected, resetsAt en unix segundos y `unifiedWindows.five_hour/seven_day` con utilization 0–1. `unifiedWindows` no está en el .d.ts pero llega.
- Límite (del código; no se puede provocar): mensaje sintético con prefijo "You've hit your…" y error -32603 de session/prompt con data.errorKind.
- La extensión sessionFailure es de JetBrains AIR y no se anuncia.
- El diseño de §10.1 no cambia: ventana actual = five_hour, semanal = seven_day.

**Bloquea a:** 1.14 Agente falso: cuota simulada y errores de límite; 6.6 QuotaMonitor: fuentes, estados y umbrales

**Bloqueada por:** 1.12 QuotaMonitor en modo observación (canal quota)

**Relacionadas:** 1.11 Verificar M1 contra el agente falso y Claude Code real

### 1.14 Agente falso: cuota simulada y errores de límite · Revisión

**Prioridad:** media · **Tamaño:** S · **Responsable:** Claude · **Etiquetas:** `quota`

Spec §13 (actualizado): el agente falso emite también `usage_update` con cuota simulada y errores de límite con hora de reinicio, según el guion JSON. Usa la forma que salga de m1-13. Es la base de los tests del QuotaMonitor y de la verificación de M6 (cuota al 90 % y después límite).

**Prueba:** tests/acp_session_check.gd, escenario quota (tests/scripts/quota.json), con 12 checks; pasa en 4.8-beta1 y 4.4.1:
- turno 1: five_hour al 63 %;
- turno 2: allowed_warning al 91 %, todavía sin límite;
- turno 3: status rejected, mensaje "You've hit your limit · resets HH:MM" y error -32603 con errorKind rate_limit, los dos en el canal quota; el turno termina en "error" y la sesión sigue usable.

**Notas:** Pasos nuevos del guion de tests/fake_agent.gd:
- `quota`: usage_update con `_meta["_claude/rateLimit"]` en la forma real de D22;
- `limit`: simula el límite;
- `error` ahora acepta `data`.
Es la base de la verificación de M6 (m6-05).

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

## M5 — Revisar y Script Editor  (4/4, 4 en revisión)

Modo Revisar, parseo de findings, anotaciones en el CodeEdit, tarjetas y lista de hallazgos; "Aplicar arreglo" y "Exportar a CLAUDE.md".

**Hecho cuando:**
- Revisar una carpeta con 3 bugs sembrados: aparecen anotados en las líneas correctas.

### 5.1 Parser tolerante de findings y checks · Revisión

**Prioridad:** alta · **Tamaño:** S · **Responsable:** Claude

Extrae bloques {"findings":[…]} y {"checks":[…]} del texto del agente aunque vengan en fences, con texto alrededor o con campos faltantes; normaliza severidades bug|order|perf|style. Tests unitarios.

**Prueba:** godot --headless --path . --script tests/run_all.gd -- findings (test_findings_parser: 6 tests/28 checks) y -- review_store (3 tests/24 checks); 4.8 y 4.4.1.

**Notas:** review/findings_parser.gd: parse(text, project_root) → {findings, checks}. Acepta fences ```json o sin lenguaje, JSON suelto con prosa alrededor (busca llaves balanceadas respetando strings), varios bloques (sin duplicados), comas finales, campos alternativos (file/description/fix/kind…), "ruta.gd:12" en path, rutas relativas o absolutas → res://, severidades en castellano/inglés → bug|order|perf|style (desconocida → style). Checks: {title, ok, detail} con ok bool/string/número. review/review_store.gd: revisión vigente; cada turno en modo Revisar con bloque findings la reemplaza (D23); dismiss, counts, scope_label, fix_prompt, question_prompt, claude_md_section y append_to_claude_md.

### 5.2 Anotaciones en el CodeEdit y tarjetas de hallazgo · Revisión

**Prioridad:** alta · **Tamaño:** L · **Responsable:** Claude

Marcar la línea (fondo y gutter por severidad) en el Script Editor; tarjeta con título, explicación, sugerencia y botones Aplicar arreglo / Preguntar / Descartar. Banda "Revisión del agente · solo lectura" (docs/design pantalla 3).

**Prueba:** tests/run_in_xvfb.sh $G --godot-agent-review-test (review_check.gd): marca en la línea, gutter propio, cursor, tarjeta con título y los 3 botones, banda en la barra de estado; Descartar saca la marca y cierra la tarjeta. Pasa en 4.4.1, 4.7.2 y 4.8-beta1. Captura revisada a ojo (4.8, agente falso y Claude real).

**Notas:** review/review_annotations.gd (Node hijo del plugin):
- gutter custom "godot_agent_review" al final, que dibuja ● y el fondo de la línea por severidad (ScriptTextEditor borra set_line_background_color al validar, D23);
- tarjeta overlay en el CodeEdit bajo la línea (get_rect_at_line_column, sigue el scroll), que se abre con clic en la marca o desde la lista del dock (focus_finding);
- banda "Revisión del agente · solo lectura · N hallazgos" en la barra de estado del CodeTextEditor, o como overlay si no la encuentra.
Anota los editores que fueron el actual (editor_script_changed). Colores en AgentTheme.SEVERITY_COLORS/BG. Los botones de la tarjeta los resuelve plugin.gd:
- Descartar: store.dismiss;
- Preguntar: send_prompt sin recolectar hallazgos;
- Aplicar arreglo: send_in_mode(BUILD) y saca el hallazgo si termina en end_turn.
Afuera (D23): conteos por archivo en la lista de scripts y seguimiento de ediciones.

### 5.3 Lista de hallazgos en el dock y acciones · Revisión

**Prioridad:** alta · **Tamaño:** M · **Responsable:** Claude

Modo Revisar: aviso de solo lectura, contadores por severidad, lista con archivo:línea clickeable. "Aplicar arreglo" cambia a Construir y pide ese arreglo; "Exportar a CLAUDE.md" agrega convenciones previa confirmación; "Arreglar en modo Construir".

**Prueba:** review_check.gd (agente falso), en 4.4.1, 4.7.2 y 4.8-beta1:
- el panel se ve en Revisar y se oculta fuera de él;
- título "Revisión de tests/fixtures/review/ · …";
- Preguntar no reemplaza la revisión ni cambia el modo;
- la vista previa de Exportar a CLAUDE.md trae la sección;
- Aplicar arreglo pasa a Construir, el agente pasa a default, el prompt lleva ruta:línea y sugerencia, y el hallazgo sale al terminar;
- Arreglar en modo Construir vacía la revisión.
test_review_store cubre los prompts y append_to_claude_md.

**Notas:** ui/dock/review_panel.gd, visible en modo Revisar:
- título con el alcance (carpeta común) y la cantidad de archivos;
- aviso de solo lectura;
- contadores bug/orden/rend/estilo con los colores del mockup;
- lista "archivo:línea · título" con ● por severidad, que abre el script con la tarjeta.
Botones en un HFlowContainer (dock angosto):
- Exportar a CLAUDE.md: ConfirmationDialog con vista previa editable; agrega al final de res://CLAUDE.md o lo crea, y hace update_file;
- Arreglar en modo Construir.
SessionController:
- send_in_mode(mode, text);
- send_prompt(…, collect_findings) espera a que termine session/set_mode con el estado ya en PROMPTING (antes la UI veía READY y el check fallaba de forma intermitente);
- se cuentan las sincronizaciones solapadas;
- si se cancela durante la espera, el turno termina como cancelled y el system prompt se reenvía en el próximo.
Además: el diff del chat va en un scroll horizontal, porque una línea larga ensanchaba el dock (se vio con Claude real).

### 5.4 Verificar M5 · Revisión

**Prioridad:** alta · **Tamaño:** S · **Responsable:** Claude

Revisar una carpeta con 3 bugs sembrados: aparecen anotados en las líneas correctas (agente falso con guion de findings y Claude Code real). Actualizar progress.

**Prueba:** Agente falso: tests/run_in_xvfb.sh $G --godot-agent-review-test (tests/scripts/review.json) PASS en 4.4.1, 4.7.2 y 4.8-beta1, dos corridas seguidas en cada una.
Claude Code real: XRUN_TIMEOUT=500 tests/run_in_xvfb.sh $G --godot-agent-claude-review-test, PASS en 4.8 (4 hallazgos: los 3 sembrados + uno válido sobre enemy_scene sin chequear) y en 4.4.1 (exactamente los 3).
Suite completa: run_all 71/427, acp 65, cycle, ui, edit y export_check.

**Notas:** tests/fixtures/review/ tiene 3 bugs sin pistas en el código:
- review_player.gd:13, movimiento sin delta (bug);
- review_spawner.gd:10, setter exportado que usa un @onready antes de _ready (orden);
- review_hud.gd:12, get_node en _process (rendimiento).
review_check.gd ubica la línea esperada buscando el código, y con Claude real acepta ±1 línea (marcó el HUD en la línea del _process) y severidades razonables.
Observado (D23): en plan mode Claude Code ejecuta comandos de solo lectura y escribe su archivo de plan fuera del proyecto sin pedirle permiso al cliente. El log perm quedó vacío en Revisar.
progress.md tiene la sección M5.

## M6 — One-shot  (8/11, 8 en revisión)

Pantalla principal completa, checkpoints git, presupuestos, checks, "Guiar al agente" y reglas de cuota del plan (§10.1).

**Hecho cuando:**
- En un proyecto vacío: "Pong de 2 jugadores con puntaje" completa al menos un playtest con captura, crea checkpoints y "Volver acá" restaura correctamente.
- Con el agente falso simulando la cuota al 90 % y después un error de límite con hora de reinicio: el One-shot pausa al terminar la tarea, crea cpN-quota, muestra la cuenta regresiva y retoma solo (o con confirmación) desde la tarea correcta.

### 6.1 Pantalla principal One-shot · Revisión

**Prioridad:** alta · **Tamaño:** L · **Responsable:** Claude

Barra superior: objetivo, estado/fase, presupuestos con barras (cuota de la ventana, tiempo, tokens, playtests), la regla de cuota activa en una línea ("se pausa al 90 % en el próximo checkpoint"), cuenta regresiva hasta el reinicio en "Limitado", y Pausar/Detener (spec §9.2 actualizado). Columnas Plan (editable), Actividad (con "Guiar al agente") y Playtest/Verificaciones/Checkpoints. Barra inferior con resumen de cambios, "Revisar cambios" y "Aceptar todo" (docs/design pantalla 2).

**Prueba:** tests/run_in_xvfb.sh $G --godot-agent-oneshot-test [--godot-agent-ui-shot=…] (addons/godot_agent_dev/oneshot_ui_check.gd, agente falso con tests/scripts/oneshot_ui.json sobre un repo git temporal en user://). PASS en 4.4.1, 4.7.2 y 4.8-beta1. Recorre:
- el formulario: no deja iniciar sin objetivo;
- en "Pausado por cuota": fase "fase 2 de 3", objetivo, banner, cuenta regresiva, regla, barras de cuota y playtests, Retomar, 3 tareas, 2 verificaciones, 3 checkpoints, captura y actividad;
- en "Limitado": ⏳, banner de límite y cp4-quota;
- espera la confirmación y Retomar;
- al terminar: resumen "1 archivo cambiado · 0 escenas · 1 script", "Nuevo One-shot" y banner de fin;
- Revisar cambios: lista y diff contra la base;
- Volver acá a cp2 borra pong.gd y recarga;
- Aceptar todo deja las dos ramas.
Cycle test de 5 ciclos sin huérfanos en las tres versiones. Capturas revisadas a ojo.

**Notas:** ui/main_screen/agent_main_screen.gd:
- formulario con objetivo, presupuestos (defaults de project_config) y checkpoints; preflight, y diálogo de WIP si hay cambios sin commitear;
- barra superior: OBJETIVO · ONE-SHOT, fase y "fase n de m", Pausar/Retomar, Detener (o Nuevo One-shot), el objetivo, y la grilla Cuota/Tiempo/Tokens/Playtests (4 columnas, 2 si es angosta), con la regla de cuota y la cuenta regresiva;
- banner de cuota o de fin;
- columnas:
  - Plan: ✓ ● ○, con "Editar" que manda el texto como guía;
  - Actividad: RichTextLabel con hora y tipo, más "Guiar al agente";
  - Último playtest, Verificaciones y Checkpoints con "Volver acá" (con confirmación);
- barra inferior: archivos, escenas y scripts, +/−, Revisar cambios (lista; doble clic emite diff_requested hacia el DiffDialog) y Aceptar todo (con confirmación).
El resumen se recalcula con debounce de 2 s después de la actividad.
Plugin:
- crea OneShotRun (after_restore recarga las escenas abiertas y pasa los scripts por EditorSync; restart_session usa el perfil activo; resume_auto sale de Settings);
- elegir One-shot en el dock abre la pantalla Agent;
- con un One-shot en curso, el composer del dock manda "Guiar al agente";
- EditorSurfaces.make_visible(MAIN_SCREEN) con la API vieja usa set_main_screen_editor.
git_checkpoints.changes_summary ahora corre solo en la rama del agente.

### 6.2 Checkpoints git · Revisión

**Prioridad:** alta · **Tamaño:** M · **Responsable:** Claude

git con OS.execute y args en array: repo limpio o commit WIP con confirmación, rama agent/<timestamp>, commit cpN antes de cada tarea del plan, "Volver acá" con reset --hard solo en la rama del agente + scan + recarga de escenas. Nunca merge ni push. Sin git: se desactiva con aviso.

**Prueba:** run_all -- git_checkpoints (2 tests, 33 checks) en 4.4.1, 4.7.2 y 4.8 sobre un repo temporal con el proyecto en una subcarpeta:
- sin git o sin repo se desactiva con el motivo;
- con cambios del usuario, el WIP va a la rama agent/<ts> y main no se toca;
- cp1 "Estado inicial" y cpN;
- changes_summary sin .godot;
- restore deja player.gd como en cp2, borra los archivos nuevos (también los sin commitear), no toca .godot/ ni los cambios sin commitear fuera del proyecto, y descarta los checkpoints posteriores;
- fuera de la rama del agente no commitea ni restaura;
- accept deja las dos ramas, sin merge.
oneshot_check también verifica la cadena de commits cp1…cp5.

**Notas:** oneshot/git_checkpoints.gd:
- OS.execute("git", ["-C", root, …]) en un Thread, esperando frames;
- pathspec "-- . :(exclude).godot" en add/status/diff/checkout/clean;
- start(): checkout -b agent/<ts>, WIP si había cambios (en la rama del agente; la confirmación la pide la UI) y cp1;
- checkpoint(label, suffix) hace commit --allow-empty --no-verify "cpN[-quota]: label";
- restore() equivale a un reset --hard limitado a la carpeta del proyecto: reset --mixed sha + checkout -- . + clean -fd. Devuelve las rutas cambiadas para recargar el editor y solo corre en la rama del agente;
- changes_summary() = add -A + diff --cached --numstat contra la base;
- base_text() para los diffs;
- accept() hace el commit final. Nunca merge ni push.
Sin user.email configurado usa -c user.name/user.email de fallback.

### 6.3 Loop One-shot y presupuestos · Revisión

**Prioridad:** alta · **Tamaño:** M · **Responsable:** Claude

Prompt inicial (objetivo, modo, plan, bloque checks, run_scene/capture/get_errors tras cada tarea). Presupuestos de tiempo, tokens y playtests: aviso al 80%, al 100% session/cancel + prompt de cierre con reporte final. "Guiar al agente" encola un prompt para el fin del turno.

**Prueba:** tests/oneshot_check.gd (headless, agente falso, 30 checks) en 4.4.1, 4.7.2 y 4.8:
- escenario oneshot_quota: prompt inicial con objetivo y bloque checks; checkpoints por tarea; playtest contado; captura; checks; pausa por cuota; límite; reanudación sola y con confirmación; fin del plan;
- escenario oneshot_budget: aviso al 80 % de playtests; la guía va al terminar el turno; al 100 %, session/cancel y prompt de cierre con reporte final; motivo de fin; checks del reporte.

**Notas:** oneshot/oneshot_run.gd (Node), fases IDLE/PREPARING/RUNNING/PAUSED/PAUSED_QUOTA/LIMITED/WAITING_CONFIRM/CLOSING/FINISHED.
- preflight(use_checkpoints) → {needs_wip_confirm, warning}; start(goal, budgets, checkpoints).
- Turnos con controller.send_in_mode(ONESHOT). Checks del texto de cada turno (FindingsParser, formato del spec {label, status}).
- Checkpoint al pasar una entrada del plan a in_progress.
- Auto-continuación si quedan tareas pendientes (máx. 3 turnos seguidos sin avance).
- Guía encolada para el fin del turno. edit_plan → guía.
- Presupuestos:
  - tiempo activo, sin pausas ni limitado;
  - tokens = input + output + cache writes del usage de session/prompt, sin las lecturas de caché (D24);
  - playtests = run_scene completados.
  Aviso al 80 % (notice + actividad); al 100 %, cancel y prompt de cierre.
- Actividad con hh:mm:ss desde el inicio. Última captura = imagen en el contenido de un tool call.
- pause/resume/stop/restore/accept_all/changes_summary. Sesión perdida: sesión nueva con un prompt resumen (plan, checks, checkpoints).
- Operaciones git serializadas (_git).

### 6.4 Proyecto sandbox para one-shots · Revisión

**Prioridad:** media · **Tamaño:** S · **Responsable:** Claude

tests/sandbox_project/ separado (con .gdignore para el anfitrión) para correr one-shots; nunca sobre el proyecto del addon.

**Prueba:** tests/make_sandbox.sh <dir fuera del repo> --dev crea el proyecto, copia el addon (y el de dev), hace git init y el commit "Sandbox inicial". Se niega a usar un destino dentro del repo y a pisar una carpeta que no sea un sandbox (marca .sandbox_one_shot). Import headless de 4.8 sin errores. XRUN_PROJECT=<sandbox> tests/run_in_xvfb.sh … abre el editor sobre el sandbox; ahí corre --godot-agent-claude-oneshot-test (m6-05).

**Notas:** tests/sandbox_project/ (.gdignore para que el proyecto del addon no lo importe) contiene:
- project.godot (features 4.4, solo el plugin godot_agent);
- CLAUDE.md con las convenciones del sandbox (scenes/, scripts/, no tocar addons/, verificar con godot.*, sin commits);
- .gitignore con .godot/.
tests/make_sandbox.sh lo copia fuera del repo con el addon y --dev habilita godot_agent_dev. Nunca se corre un One-shot sobre el proyecto del addon: los checkpoints crean ramas y "Volver acá" resetea la carpeta.
run_in_xvfb.sh acepta XRUN_PROJECT para abrir otro proyecto.

### 6.5 Verificar M6 · Revisión

**Prioridad:** alta · **Tamaño:** M · **Responsable:** Claude

En el sandbox: "Pong de 2 jugadores con puntaje" completa al menos un playtest con captura, crea checkpoints y "Volver acá" restaura correctamente. Cuota (spec M6 actualizado): con el agente falso simulando la cuota al 90 % y después un error de límite con hora de reinicio, el One-shot pausa al terminar la tarea, crea cpN-quota, muestra la cuenta regresiva y retoma solo (o con confirmación) desde la tarea correcta. Actualizar progress.

**Prueba:** Suites (4.4.1, 4.7.2 y 4.8-beta1): run_all 78 tests / 509 checks, acp_session_check 70, oneshot_check 34 (cuota al 91 % → pausa al terminar la tarea con su checkpoint, reinicio y retoma solo; límite a mitad de turno → cp4-quota, cuenta regresiva y espera de confirmación; presupuestos; guía; sin plan). En el editor: --godot-agent-oneshot-test (pantalla Agent, barras, banner, diff, Volver acá, Aceptar todo), --godot-agent-ui-test=ui_quota, cycle test. Claude Code real en el sandbox (tests/make_sandbox.sh <dir> --dev; XRUN_PROJECT=<dir> tests/run_in_xvfb.sh $G --godot-agent-claude-oneshot-test), tercera corrida: Pong con todos los checks en pass, 4 playtests con captura, 5 checkpoints, 114k tokens, 6,6 min, y Volver acá a cp4 sin diff ni archivos sin seguimiento. El árbol del commit de M6 (sin lo de M7) se probó aparte con las mismas suites.

**Notas:** Tres corridas reales, detalladas en docs/progress.md (M6 · One-shot con Claude Code real).
1. Checkpoints apagados después de cp1: con .godot/ en el .gitignore, `git add` rechaza el pathspec :(exclude).godot. Ahora, si .godot/ está ignorado, el pathspec es `-- .`, y si start() falla vuelve a la rama del usuario. Además Claude no usó herramienta de plan.
2. Con un checkpoint por playtest anduvo, pero el fin de turno se tomaba como final aunque quedaran checks en fail o pending.
3. Sin plan, el harness sigue mientras queden checks sin pasar (hasta MAX_IDLE_CONTINUES turnos sin un playtest nuevo). Terminó sola con todo en pass.
La actividad recorta los comandos de shell a una línea. Con plan vacío y el run terminado, la columna Plan explica que el avance sale de los checks. La corrida 3 no guardó capturas: faltó --godot-agent-ui-shot. Las de la corrida 2 están en el scratchpad de la sesión.

**Bloqueada por:** 6.8 Reglas de cuota en One-shot: pausa, Limitado y reanudación

### 6.6 QuotaMonitor: fuentes, estados y umbrales · Revisión

**Prioridad:** alta · **Tamaño:** M · **Responsable:** Claude · **Etiquetas:** `quota`

Spec §10.1. Fuentes, en orden: (1) campos de cuota del `usage_update` (los de m1-13); (2) avisos y errores de límite, con parseo tolerante y patrones en un archivo editable del addon; (3) sin datos: solo tokens de sesión y "desconocido". Estados normal / aviso / pausa_programada / limitado / desconocido, expuestos al SessionModel. Umbrales por usuario en EditorSettings godot_agent/: aviso (75 %), pausa del One-shot (90 % o nunca), y al reiniciar la ventana retomar solo o esperar confirmación. Hora de reinicio conocida → timer; sin hora → backoff 5, 10, 20 y luego cada 60 min. Tests unitarios con payloads del agente falso.

**Prueba:** run_all -- quota: test_quota_monitor (7 tests, 49 checks): estados con payloads del agente falso, umbrales configurables, pausa desactivable, resetsAt exacto vs texto, backoff 5/10/20/60/60 y reinicio del backoff, parse_reset_time (HH:MM, am/pm, "reinicia a las", unix viejo), format_duration. acp_session_check (70 checks): con el agente falso normal → pausa programada (91 %) → limitado, ~120 s hasta el reinicio y la transición logueada en el canal quota.

**Notas:** core/quota_monitor.gd:
- estados UNKNOWN/NORMAL/WARNING/PAUSE_SCHEDULED/LIMITED;
- ventanas five_hour/seven_day {utilization, resets_at} leídas de unifiedWindows;
- "limitado" entra por status rejected, por texto o por error de límite, y sale con status allowed* o con un turno end_turn sin texto de límite;
- hora de reinicio: el resetsAt exacto de la cuota rejected, si no la del texto (parse tolerante), si no backoff;
- retry_due / seconds_until_retry / note_retry, rule_text(), describe_window(), format_duration();
- cada transición se loguea en el canal quota.
Umbrales en EditorSettings godot_agent/quota/: warn_percent 75, pause_percent 90, pause_enabled, resume_mode (Retomar solo / Esperar confirmación). El plugin los aplica al arrancar y con settings_changed.
El estado queda en SessionController.quota, que la UI lee por el controller; SessionController.last_turn_usage guarda el usage del session/prompt para el presupuesto de tokens.

**Bloquea a:** 6.7 Medidor de cuota en el dock y bloqueo en Limitado; 6.8 Reglas de cuota en One-shot: pausa, Limitado y reanudación

**Bloqueada por:** 1.13 Verificar qué cuota reporta el adapter de Claude Code

### 6.7 Medidor de cuota en el dock y bloqueo en Limitado · Revisión

**Prioridad:** media · **Tamaño:** S · **Responsable:** Claude · **Etiquetas:** `quota`

Spec §9.1 y §10.1 (fuera de One-shot): barras de la ventana actual y semanal, con porcentaje y tiempo hasta el reinicio. Si el agente no informa cuota, se ocultan y queda el medidor de contexto del composer, con un tooltip que dice que el agente no la informa. En el dock solo hay avisos; en "Limitado", el botón enviar se deshabilita y muestra la cuenta regresiva.

**Prueba:** tests/run_in_xvfb.sh $G --godot-agent-ui-test=ui_quota (tests/scripts/ui_quota.json: cuota 82 % y después límite con reinicio en 90 min). Verifica que el botón enviar queda deshabilitado con "⏳ …" y que el medidor se ve. PASS en 4.4.1, 4.7.2 y 4.8-beta1. Captura revisada a ojo: barras de ventana y semana, aviso "Cuota del plan al 82 %", aviso de límite con "se reinicia en 1 h 30 min" y botón "⏳ 1 h 30 min".

**Notas:** ui/dock/quota_meter.gd, debajo del estado:
- filas "Ventana N % · reinicia en …" y "Semana N % · …" con ProgressBar fina, color por umbral (acento, aviso, pausa, límite);
- en "limitado", la cuenta regresiva;
- oculto sin datos del agente; el tooltip del medidor de contexto del composer dice entonces "El agente no informa la cuota del plan".
Dock:
- un aviso en el chat al pasar a aviso o pausa programada, y otro al pasar a limitado;
- Composer.set_locked deshabilita el envío (incluido Ctrl+Enter) con "⏳ <tiempo>" hasta el próximo intento permitido (reinicio o backoff);
- un timer de 1 s refresca la cuenta.
tests/run_in_xvfb.sh ahora usa una pantalla de 1920×1200: con 900 de alto, el editor 4.8 no entraba y el composer quedaba fuera de la captura.

**Bloqueada por:** 6.6 QuotaMonitor: fuentes, estados y umbrales

### 6.8 Reglas de cuota en One-shot: pausa, Limitado y reanudación · Revisión

**Prioridad:** alta · **Tamaño:** M · **Responsable:** Claude · **Etiquetas:** `quota`

Spec §10.1.
- Aviso: banner en la pantalla Agent y entrada en el canal quota.
- Umbral de pausa: no corta el turno; al terminar la tarea actual y crear su checkpoint, no manda la siguiente y pasa a "Pausado por cuota".
- Límite a mitad de turno: los tool calls pendientes pasan a cancelled, se crea el checkpoint cpN-quota y se pasa a "Limitado".
- Reanudar (solo o con confirmación): session/prompt "continuá con el plan desde la tarea X; el estado está en el checkpoint cpN". Si la sesión se perdió, session/load o una sesión nueva con el resumen del plan, los checks y los checkpoints.
- El tiempo en Limitado no cuenta contra el presupuesto de tiempo.
- Barra superior: cuota de la ventana, regla activa en una línea ("se pausa al 90 % en el próximo checkpoint") y cuenta regresiva en Limitado.

**Prueba:** tests/oneshot_check.gd, escenario de cuota (headless, 4.4.1, 4.7.2 y 4.8):
- al 91 % la tarea en curso termina; al empezar la siguiente se crea cp3 y se corta el turno: no llega el texto posterior;
- "Pausado por cuota" retoma solo al reiniciarse la ventana, con el prompt "Continuá con el plan desde la tarea «Puntaje y saque»; el estado está en el checkpoint cp3";
- con el límite a mitad de turno: cp4-quota, "Limitado" y cuenta regresiva;
- con resume_auto=false espera confirmación, y el tiempo en Limitado no cuenta;
- Retomar sigue desde cp4-quota;
- la cadena de commits es cp1…cp5.
En la UI (--godot-agent-oneshot-test): banner de cuota y de límite, la regla de cuota y la cuenta regresiva en la barra superior, y Retomar en "Listo para retomar".

**Notas:** En oneshot_run.gd:
- _pause_for_quota: el checkpoint de la siguiente tarea y session/cancel;
- _enter_limited: tool calls pendientes pasan a cancelled, cpN-quota una sola vez por episodio y fase LIMITED;
- _tick: retry_due o resets_at llama a _on_quota_back, que retoma o pasa a WAITING_CONFIRM según Settings (quota/resume_mode).
Si la sesión se perdió, resume() abre una sesión nueva con _summary_prompt (objetivo, plan, checks y checkpoints). Se eligió sesión nueva y no session/load: Claude Code no anuncia loadSession de forma confiable, y el resumen alcanza para retomar.
El banner de la pantalla Agent: aviso (≥ umbral), pausa programada (texto de rule_text) y límite con la cuenta. El canal quota del Agent Log ya registra cada transición (m6-06).

**Bloquea a:** 6.5 Verificar M6

**Bloqueada por:** 6.6 QuotaMonitor: fuentes, estados y umbrales

### One-shot: evaluator separado y vuelta de corrección · Pendiente

**Prioridad:** alta · **Tamaño:** L

Hoy el One-shot es un solo agente que planifica, construye y reporta sus propios checks en un bloque JSON, y el harness acepta esos pass/fail tal cual (`oneshot_run.gd:190`, `initial_prompt`). Según "Harness design for long-running application development" (Anthropic, 2026-03), el agente que construye es indulgente con su propio trabajo. Un evaluator aparte, ajustado para ser escéptico y que use la app como un usuario, encuentra bugs reales que el generator dio por buenos.

Qué hacer:
- Cuando el generator da el objetivo por cumplido (o se agota el plan), abrir una sesión ACP nueva, separada y sin el contexto del generator, con un prompt de QA escéptico.
- El evaluator juega el juego con `godot.run_scene` e inputs simulados, `capture_game_frame` y `get_errors`, y lee el código. Califica cada check y cada criterio (ver la tarea de criterios) con un umbral duro, y devuelve findings concretos: qué falló, cómo reproducirlo y dónde.
- Los checks del run pasan a usar el veredicto del evaluator. El autorreporte del generator queda solo como progreso.
- Si algo no pasa, los findings vuelven al generator como el próximo turno. Hay un máximo de vueltas configurable (2 por defecto), que cuenta para los presupuestos y la detección de loops (m7-11).
- En modo Preguntar, el evaluator usa permisos de solo lectura más run/capture: no edita archivos.
- Reutilizar lo que se pueda del modo Revisar (`FindingsParser`, tarjetas de hallazgos).
- Mostrar en la pantalla del One-shot la fase "Evaluando", con los findings de cada vuelta.

Afinar el prompt leyendo trazas reales del evaluator. El artículo cuenta que al principio encontraba problemas y se convencía solo de aprobarlos.

Tests: el agente falso con dos roles. El generator reporta todo en pass, el evaluator encuentra un fallo, y el run hace una vuelta de corrección y cierra en pass.

**Relacionadas:** One-shot: criterios de evaluación para juegos

### One-shot: spec y progreso en archivos (planner y traspaso) · Pendiente

**Prioridad:** media · **Tamaño:** M

Basado en "Harness design for long-running application development" (Anthropic, 2026-03):
- Un planner que convierte el objetivo corto en un spec evita que el generator se quede corto de alcance. El spec tiene que ser ambicioso en alcance pero de alto nivel; si mete detalle técnico, los errores se arrastran.
- Los agentes se pasan el trabajo por archivos, no por contexto.

Qué hacer:
- Primer paso del One-shot: escribir el spec en `.godot_agent/oneshot/<id>/spec.md`. Incluye las mecánicas, el loop de juego, la dirección visual y los criterios de "terminado". Antes de construir, el usuario puede revisarlo y editarlo (paso opcional, con "Aprobar spec").
- El generator mantiene `progress.md`: qué está hecho, qué falta, decisiones y problemas conocidos. Se actualiza al cerrar cada tarea.
- El evaluator lee el spec y el progress, y escribe `qa-<n>.md` con sus findings.
- Esos archivos son el traspaso. Si el editor se cae o hay que reiniciar contexto, una sesión nueva retoma leyendo spec y progress. Se complementa con m7-09: el estado del harness va en `user://` y el del trabajo en el proyecto.
- Decidir si `.godot_agent/` se ignora en git, se commitea en los checkpoints o queda excluido del export. El export check no debe incluirlo.

**Relacionadas:** Persistir el run del One-shot y ofrecer retomarlo

### One-shot: criterios de evaluación para juegos · Pendiente

**Prioridad:** media · **Tamaño:** S

El artículo "Harness design for long-running application development" (Anthropic, 2026-03) muestra que criterios explícitos, con peso y umbral, guían tanto al generator como al evaluator, y que su redacción cambia el resultado. Hacen falta criterios propios para juegos de Godot.

Criterios propuestos, con su umbral cada uno:
- **Jugabilidad:** la mecánica principal responde a los inputs, hay un loop completo (empezar → jugar → ganar o perder → reiniciar) y no hay estados trabados. Este es el fallo típico: "las entidades aparecen pero no responden al input".
- **Funcionalidad:** cada feature del spec funciona en un playtest con inputs simulados, sin errores en `get_errors`.
- **Visual y feel:** legibilidad, feedback de las acciones y coherencia de estilo, evaluados con `capture_game_frame`.
- **Código:** tipado estático, estructura de escenas y sin warnings. Se puede reutilizar el modo Revisar.

Qué hacer:
- Ponerlos en el prompt del generator y del evaluator, con pesos y umbrales configurables en Settings.
- Calibrar al evaluator con ejemplos de puntaje (few-shot) para que no se corra con el tiempo.
- Dejar explícito que el evaluator no puede oír: el audio solo se verifica por código (que los nodos existan y se disparen), no por calidad.

Nota: el artículo también usa contratos por sprint (generator y evaluator acuerdan antes de cada tarea cómo se verifica). Con Opus 4.6 ellos mismos los sacaron por costo, así que por ahora quedan afuera. Se pueden reconsiderar si el informe de m7-12 muestra checks mal definidos.

**Relacionadas:** One-shot: evaluator separado y vuelta de corrección

## M7 — Pulido  (8/12, 8 en revisión)

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

- [ ] Zipear tests/upstream/main_screen_orphan
  Proyecto mínimo: legacy_ms (_has_main_screen) + driver que lo alterna 5 veces y cuenta EditorDock huérfanos. Correr: godot --headless --editor --path . -- --cycle. Zipear sin .godot/ ni .uid.
- [ ] Probar en el último 4.8 publicado antes de abrir el issue
  Si ya está arreglado, cerrar la tarea y anotar la versión.
- [ ] Abrir el issue con la plantilla de bug
  Tested versions: 4.8-beta1, master e7cfa294a; regresión de #113051. Incluir la causa y el arreglo probable.
- [ ] Decidir si se saca el cambio a 2D de remove_all()
  El error de grab_focus ya no se reproduce; el cambio a 2D es inofensivo pero su comentario describe un bug que no aparece. Actualizar D9.

**Prueba:** Issue abierto en godotengine/godot con el repro adjunto y su link en notes. Si se arregla upstream, `tests/plugin_cycle_check.gd` pasa en esa versión con la main screen por `_has_main_screen()`.

### 7.2 Diálogo de Settings completo · Revisión

**Prioridad:** alta · **Tamaño:** L · **Responsable:** Claude

Navegación según docs/design pantalla 4. Secciones:
- Agentes (CRUD de perfiles).
- Herramientas/Permisos (matriz).
- Puerto MCP y regenerar token.
- Presupuestos default de One-shot.
- Cuota y límites (spec §9.5 y §11 actualizados): umbral de aviso, umbral de pausa del One-shot (o nunca) y al reiniciarse la ventana retomar solo o esperar confirmación. Se guardan por usuario en EditorSettings godot_agent/, porque la cuota es del plan, no del proyecto.
- Checkpoints on/off, ubicación del dock, color de acento, aviso y botón de filtro de presets.
Diálogo propio (no Project Settings: escribiría en project.godot).

**Prueba:** `$G --headless --path . --script tests/run_all.gd -- test_settings` (3 tests, 21 checks: defaults validan, secreto literal en env rechazado y $VAR aceptado, ids repetidos, un solo predeterminado, pausa > aviso, carpetas absolutas, overrides de la matriz solo con lo que difiere, formulario de perfil). En el editor: `tests/run_in_xvfb.sh $G --godot-agent-settings-shots=<prefijo>` abre Settings desde el botón del dock, guarda una captura por sección y comprueba que Guardar aplica la matriz en caliente y escribe project_config.tres. Pasa en 4.4.1, 4.7.2 y 4.8-beta1; suite completa 84 tests / 569 checks en las tres.

**Notas:** ui/settings/settings_dialog.gd reemplaza a profiles_dialog.gd (JSON de M1, borrado). El dock emite settings_requested y el plugin abre el diálogo, porque necesita la config del proyecto y el server MCP.
- Por usuario (EditorSettings godot_agent/): perfiles, puerto MCP, cuota (aviso, pausa on/off y umbral, retomar solo o esperar), color y ubicación del dock (nuevo ui/dock_slot, que se aplica a EditorSurfaces.side_slot).
- Por proyecto (project_config.tres): matriz de permisos (solo overrides respecto de la spec), timeout de preguntas, max_output_chars, max_image_side, playtest en runs manuales, carpetas extra para fs/*, presupuestos y checkpoints.
- Guardar valida antes y aplica en caliente: policy.overrides, fs.extra_roots, límites del registry y run_tools, defaults de la pantalla One-shot. La cuota llega por settings_changed.
- El puerto, el color y la ubicación del dock se aplican al reabrir el editor; con EditorDock (4.8) la ubicación es solo la inicial.
- "Regenerar token" reinicia el server en el mismo puerto; las sesiones abiertas quedan con el token viejo.
- Export: lista los presets sin filtro y lo agrega, previa confirmación.
- Un agente sin comando es válido (el default de Codex viene así) y su tarjeta dice "sin comando".

### 7.3 Historial de sesiones · Revisión

**Prioridad:** media · **Tamaño:** M · **Responsable:** Claude

user://godot_agent/sessions/<id>.json con eventos ACP normalizados; lista en el dock para reabrir y mostrar; session/load para reanudar si el agente lo soporta.

**Prueba:** `$G --headless --path . --script tests/acp_session_check.gd`: escenario history (16 checks) en 4.4.1, 4.7.2 y 4.8-beta1.
- Graba por turno.
- Índice con título y turnos.
- Sin capturas, rawOutput ni usage_update, y con los textos largos recortados.
- Chunks unidos.
- Rechaza ids con rutas.
- session/load reanuda la misma sesión con la conversación del archivo (descarta el replay del agente) y sigue grabando en el mismo archivo.
- Sin loadSession queda de solo lectura.

En el editor, `tests/run_in_xvfb.sh $G --godot-agent-history-test=<png>`: dos turnos con el agente falso, el menú de historial del dock muestra la sesión, y se reanuda desde el dock.

**Notas:** session/session_history.gd guarda en user://godot_agent/sessions/<id>.jsonl (JSON Lines: una cabecera y un evento por línea), más un index.json con título, fechas y turnos. Conserva hasta 100 sesiones.
- Escritura: al fin de cada turno se agregan solo los eventos nuevos, en un worker (una cola en orden en WorkerThreadPool). Las lecturas y el cierre del plugin esperan con flush(). Con el disco ocupado, abrir el archivo llegó a 600 ms en el hilo principal.
- Qué guarda: prompts del usuario (sin el system prompt ni los adjuntos), chunks unidos por mensaje, tool calls sin rawOutput ni _meta, plan, título y fin de turno. Las capturas se reemplazan por un marcador, los textos se recortan a 4000 caracteres y los diffs de más de 40k no se guardan.
- Qué no guarda: usage, comandos, modos ni opciones.
- El controller graba si tiene `history`; el plugin se lo da, los tests no.
- start(profile, record): initialize, replay del archivo (con model.replaying, para que el plugin y el One-shot no lo tomen como eventos nuevos) y session/load. Las notificaciones que el agente manda durante el load se descartan solas, porque model.session_id recién se asigna con la respuesta.
- reopen(profile, lost_id) es para el One-shot: usa session/load y, si el agente no lo soporta, abre una sesión nueva. Si se canceló, no relanza.
- Sin loadSession, o si el load falla: solo lectura con un aviso.
- Dock: el botón Historial lista las sesiones de este proyecto. No abre otra sesión mientras el agente trabaja ni con un One-shot en curso.

### 7.4 Markdown→BBCode robusto · Revisión

**Prioridad:** media · **Tamaño:** S · **Responsable:** Claude

Párrafos, títulos, negrita, itálica, code inline, bloques de código, listas (anidadas), links, escapado de corchetes BBCode. Tests unitarios con casos borde.

**Prueba:** run_all -- markdown: test_markdown_bbcode (6 tests, 57 checks) en 4.4.1, 4.7.2 y 4.8. Casos borde:
- en línea: ***negrita e itálica***, énfasis anidado, escapes con \, code spans con `` ` `` adentro y relleno, dos spans por línea, link dentro de code (no se convierte), code y énfasis dentro del texto de un link, paréntesis en la URL, guiones bajos en URL sueltas, marcas sin cerrar literales, BBCode del agente escapado y \ dentro de code;
- bloques: listas anidadas (•/◦), continuación de un ítem, ~~~, fence largo que contiene uno corto, bloque dentro de una lista, saltos forzados (dos espacios y \), citas anidadas y con lista, "#sin espacio" que no es título, code en un título y regla ***;
- tags siempre balanceados, aun con marcas cruzadas (**a *b** c*).

**Notas:** ui/markdown/markdown_bbcode.gd:
- Antes de cualquier formato, `\X` pasa a caracteres de uso privado (U+E000+X) y los code spans a U+E100+n. Así, ni el énfasis ni los links ven lo que hay adentro, y un span dentro del texto de un link se renderiza bien.
- Code spans de N backticks con el relleno de un espacio.
- Links con un nivel de paréntesis en la URL.
- Fences ``` y ~~~: cierra uno del mismo carácter y por lo menos igual de largo.
- Las líneas indentadas después de un ítem siguen el ítem.
- Salto forzado con dos espacios o `\` al final.
- Citas con profundidad (▎ por nivel) y con bloque adentro.
- _balance() cierra y reabre b/i/s cruzados.

### 7.5 Rendimiento con sesiones largas · Revisión

**Prioridad:** media · **Tamaño:** M · **Responsable:** Claude

Más de 500 entradas sin degradación: límite de nodos vivos en la lista (las viejas se colapsan o se cargan bajo demanda), batch de chunks por frame. Medido con un guion largo del agente falso.

**Prueba:** tests/run_in_xvfb.sh $G --godot-agent-long-test (addons/godot_agent_dev/long_session_check.gd): el agente falso manda un turno de 641 entradas, 320 mensajes en Markdown de 12 chunks cada uno, alternados con tool calls. Antes del cambio, un frame tardó 3951 ms: toda la ráfaga en un solo frame, con 391 vistas armadas y tiradas. Ahora, en 4.8 con OpenGL por software en Xvfb: p95 45–97 ms y peor frame 105–129 ms (umbrales del check: 120 y 400). Quedan 250 vistas vivas y 391 ocultas, el último mensaje está completo y "Mostrar anteriores" agrega 50. run_all, acp_session_check y oneshot_check siguen pasando.

**Notas:** - transport/agent_process.gd: el thread lector encola las líneas de stdout y el hilo principal las entrega con un presupuesto de 6 ms por frame. Lo que sobra sigue en process_frame: con call_deferred correría en la misma vuelta de la cola de mensajes. El exit espera a la última línea encolada. stderr sigue con call_deferred.
- ui/dock/conversation_view.gd:
  - las vistas nuevas se arman por tandas con 8 ms por frame;
  - si una ráfaga trae más entradas que el tope, las que quedarían ocultas no se arman;
  - los refrescos (tool groups, plan, permisos) se agrupan a uno por vista y por frame;
  - "N entradas anteriores ocultas" pasó a ser el botón "Mostrar 50 anteriores (N ocultas)", que arma las previas arriba y sube el tope hasta la próxima sesión.
- agent_message_view ya convertía el Markdown una vez por frame.

### 7.6 README de uso · Revisión

**Prioridad:** media · **Tamaño:** S · **Responsable:** Claude

Instalación, perfiles, modos, permisos, MCP, One-shot, completado, exclusión del export (filtro de presets), actualizar sin perder la config, limitaciones conocidas por versión de Godot.

**Prueba:** Leer README.md y contrastarlo con el código. Tools: la lista sale de McpTool.create en mcp/tools. Matriz de permisos: PermissionPolicy.DEFAULTS, la misma que muestra Settings. Settings y dónde se guarda cada cosa: HarnessSettings y ProjectConfig. Límites por versión: D4, D9 y D11.

**Notas:** README.md en la raíz, en español.
- Uso: requisitos, instalación, dock, modos, matriz de permisos, tools MCP por grupo, One-shot paso a paso, cuota del plan, historial.
- Configuración: perfiles con $VAR para las claves, tabla de dónde se guarda cada setting.
- Export: qué hace el export plugin y el filtro como red de seguridad.
- Actualizar sin perder project_config.tres (vive dentro de la carpeta del addon, D5).
- Limitaciones por versión (4.4 pipes y Logger; 4.4–4.7 docks; 4.8-beta1 main screen) y cómo correr los tests.
- El completado inline figura como "llega en M8".
- Gemini CLI: el perfil por defecto no trae argumentos. El README sugiere el flag de ACP de su versión (`--experimental-acp`), sin afirmar cuál es.

### 7.7 Verificar M7 · Revisión

**Prioridad:** alta · **Tamaño:** S · **Responsable:** Claude

Suite completa en 4.4.1/4.7.2/4.8-beta1, settings persistidos, sesión de 500+ entradas, revisión godot-code-review sin hallazgos altos. Actualizar progress.

**Prueba:** En 4.4.1, 4.7.2 y 4.8-beta1:
- Headless: run_all 84 tests / 571 checks, acp_session_check 90, oneshot_check 34.
- En el editor (4.8 y 4.4.1):
  - --godot-agent-settings-shots: Settings persistidos, project_config.tres escrito y matriz aplicada en caliente;
  - --godot-agent-history-test;
  - --godot-agent-long-test: 641 entradas, peor frame 83–133 ms, p95 49–95 ms;
  - cycle test, --godot-agent-oneshot-test y ui_quota.

Revisión godot-code-review hecha por un subagente: 1 alto, 3 medios y 6 bajos. Quedan arreglados el alto y los tres medios, con tests de regresión, y 5 de los 6 bajos. No quedan hallazgos altos abiertos.

**Notas:** Hallazgo alto: SessionHistory.replay disparaba tool_call_changed y plan_changed. Al reanudar, el plugin sincronizaba archivos (avisos falsos de "escena modificada" con un "Recargar" que pierde cambios) y el One-shot creaba checkpoints de tareas viejas. Arreglo: SessionModel.replaying, que esos listeners ignoran.

Medios:
- reopen() relanzaba el agente después de una cancelación. Ahora solo vuelve a abrir si el load falló por el agente (_load_failed).
- Quitar un perfil de más arriba corría el índice que se estaba editando.
- begin() sin entrada en el índice rompía record_prompt.

Bajos arreglados:
- Si guardar falla, la config vuelve a como estaba.
- Una línea cortada no se pega a la siguiente.
- process_frame no se conecta dos veces.
- No se pierden refrescos.
- El menú de historial revisa el estado al elegir, y no abre otra sesión con un One-shot en curso.
- Los diffs de más de 40k caracteres no van al historial.

Bajo pendiente: load_record y replay son sincrónicos. Corren solo al elegir una sesión.

Durante la verificación, la sesión larga en 4.8 dio frames de 0,4–2 s, siempre al fin del turno. Midiendo: el guardado del historial tardaba 9 ms o 607 ms según la carga del disco. Las escrituras pasaron a un worker (cola en orden en WorkerThreadPool) y la misma secuencia quedó en 83–133 ms.

### Cola de prompts en el chat · Revisión

**Prioridad:** alta · **Tamaño:** M

Hoy, con un turno en curso, el composer no deja enviar: Enter no hace nada y el botón pasa a "■ Detener" (`composer.gd` `_submit` retorna si `_busy`). La idea es poder encolar prompts mientras el agente trabaja, como en Claude Code.

Propuesta:
- Con un turno en curso, Enter encola el texto en lugar de ignorarlo. Arriba del composer aparece una lista "En cola (N)"; cada ítem se puede editar (vuelve al composer) o quitar (✕).
- Al terminar el turno con `end_turn`, se manda el siguiente de la cola automáticamente (`session_model.turn_finished`).
- Si el turno termina cancelado, con error o por límite de cuota, la cola se pausa y no se manda nada solo. Se muestra "N en cola · Enviar ahora / Descartar".
- El contexto adjunto (escena, selección, imagen) se toma al encolar, para que el agente reciba lo que el usuario veía al escribir.
- La cola vive en el controller o el dock, no en el One-shot. Cambiar de sesión o cerrar el dock la descarta, avisando si no estaba vacía.
- Opcional: "Enviar ya" sobre un ítem cancela el turno actual y lo manda. ACP no permite inyectar texto en medio de un turno.

Tests: unit de la cola (encolar, quitar, pausa por cancel o error) y un ui-check con el agente falso: dos prompts encolados durante un turno largo salen en orden.

**Prueba:** `test_prompt_queue` y `test_composer` (Enter con un turno en curso, `insert_text`). `--godot-agent-queue-test`: un turno largo, dos prompts encolados con Enter, cancel → cola en pausa, «Enviar ahora» → salen en orden.

**Notas:** D36. `session/prompt_queue.gd` es el modelo y `ui/dock/prompt_queue_view.gd` la vista, arriba del composer. El dock decide cuándo enviar.
- Con un turno en curso, el composer entrega el texto igual y el placeholder lo avisa.
- Al encolar se toma el contexto (escena, selección, captura y archivos).
- Con `end_turn` sale el siguiente. Si el turno se cancela, falla, se niega o se cierra la sesión, o si empieza otra sesión, la cola se pausa: nunca se descarta sola.
- «Enviar ahora» solo funciona con una sesión lista.
- Si hay un One-shot activo o la cuota está agotada, la cola se pausa.
- Opción descartada: «Enviar ya», que cortaba el turno actual. Con «Detener» y después «Enviar ahora» se logra lo mismo.

### Persistir el run del One-shot y ofrecer retomarlo · Pendiente

**Prioridad:** alta · **Tamaño:** M

El estado del One-shot (plan, checks, checkpoints, presupuestos, actividad) vive solo en memoria en `oneshot/oneshot_run.gd`. Si el editor crashea, se pierde todo. Visto en little-villages el 2026-10-22: después del crash, para la sesión era como si el One-shot no hubiera corrido.

Qué hacer:
- Guardar el run en `user://godot_agent/oneshot/<id>.json` a medida que avanza, con escritura atómica (archivo temporal y después rename).
- Al abrir el editor con un run sin terminar o reciente, ofrecer "Retomar". Eso restaura la pantalla y hace `session/load` de la sesión ACP.
- Avisar antes de arrancar un One-shot si el repo no tiene commits, porque sin commits no hay checkpoints.

**Bloquea a:** One-shot: informe de métricas de la corrida

**Relacionadas:** One-shot: spec y progreso en archivos (planner y traspaso)

### Crash al recargar agent_process.gd con un agente corriendo · Revisión

**Prioridad:** media · **Tamaño:** S

Si se modifica `transport/agent_process.gd` en disco mientras hay un agente corriendo (un git pull, o un proyecto que usa el addon por symlink), Godot recarga el script en caliente. El hilo `_watch_exit` sigue ejecutando el bytecode viejo, que ya fue liberado, y el editor muere con SIGSEGV. Visto el 2026-10-22 en little-villages; el backtrace está en `Thread::_start_func` → `GDScriptInstance::callp`.

Opciones:
- Detectar la recarga del script (por ejemplo con `NOTIFICATION_PREDELETE` o la recarga de scripts del editor) y detener los hilos antes de que ocurra.
- Que los hilos no ejecuten GDScript del addon en el loop: usar una clase interna o mínima que no cambie, o hacer el polling desde el hilo principal.

Hay que reproducirlo en un test y confirmar que no crashea.

**Prueba:** `test_agent_process`: recarga el script con un proceso escribiendo y sigue leyendo. También cubre stdout, stderr, el exit después de la última línea, stdin y stop. Matriz 4.6.3, 4.7.2 y 4.8-beta1.

**Notas:** D35. `AgentProcess` ya no usa threads. Lee los pipes en `process_frame`, solo los bytes disponibles (`get_length()`: FIONREAD en Unix, PeekNamedPipe en Windows), así que no bloquea.
- El pipe sigue siendo bloqueante: en modo no bloqueante, `store_buffer` podía escribir a medias en stdin sin avisar.
- El exit se decide por el proceso y no por EOF. Muerto el proceso, se espera a que los pipes se vacíen y a que mueran los descendientes, hasta 2 s.
- Descendientes: en Linux salen de `/proc/<pid>/task/*/children`, sin lanzar procesos. En macOS, pgrep cada 10 s.
- Reproducción: con los threads, recargar `agent_process.gd` en headless crasheaba igual que en el editor.
- Sin probar en Windows: puede quedar un error de PeekNamedPipe en Output al cerrar.
- Quedan threads cortos en los checkpoints de git, el índice del completado y el historial.

### One-shot: detectar loops sin progreso real · Pendiente

**Prioridad:** media · **Tamaño:** M

Hoy el One-shot tiene dos frenos:
- los presupuestos de tiempo, tokens y playtests;
- `MAX_IDLE_CONTINUES` (3 turnos seguidos sin avance).

Pero `_idle_continues` vuelve a 0 apenas un turno trae resumen (`oneshot_run.gd:337-341`). Un agente que "arregla" una y otra vez el mismo check sin lograrlo, o que repite la misma tool con los mismos argumentos, solo se detiene al agotar el presupuesto. Es uno de los modos de falla de corridas largas ("loop forever, retry bad actions") del artículo "Agent Harness — A no-BS guide".

Qué hacer:
- Huella por check fallido: guardar la etiqueta y el error de `get_errors`/`run_scene`. Si el mismo check falla con la misma huella N veces seguidas (N=3, configurable), avisar en la actividad. Al pasar el umbral, pausar con "Guiar al agente" o pedirle un enfoque distinto en el próximo continue.
- Huella por tool call (nombre + argumentos normalizados): la misma huella K veces dentro de una ventana de turnos dispara el mismo aviso.
- Que el avance real se cuente por el plan (una entrada que pasa a completed) o por los checks (fail → pass), no porque haya texto de resumen.

Tests: unit con secuencias simuladas, y un guion del agente falso que repite el mismo error.

**Relacionadas:** One-shot: informe de métricas de la corrida

### One-shot: informe de métricas de la corrida · Pendiente

**Prioridad:** media · **Tamaño:** M

Al cerrar, el One-shot le pide al agente un reporte final en texto ("qué quedó hecho, qué falta y cómo probarlo"). Pero el harness no arma un informe propio con datos medidos. Sin ese informe no se pueden comparar corridas, ni saber si conviene cambiar de modelo, ajustar el prompt o sumar una tool. Es el punto de "observability & evaluation" del artículo "Agent Harness — A no-BS guide".

Qué hacer: al terminar (por cualquier motivo), generar un informe a partir de datos que ya tenemos (activity, tool calls, plan, checks, budgets, checkpoints). Debe incluir:
- el objetivo y el motivo de cierre;
- la duración total y por tarea del plan;
- los tokens usados, los playtests y el presupuesto consumido;
- las tools usadas: conteo por tool y fallidas;
- los checks: estado final y cuántas veces falló cada uno;
- los checkpoints creados, los permisos pedidos y denegados, y los errores de turno y pausas por cuota;
- los archivos cambiados (`changes_summary`).

Se muestra en la pantalla del One-shot y se guarda en `user://godot_agent/oneshot/<id>.report.json` (junto a lo de m7-09), para compararlo con otras corridas. Opcional: exportarlo como Markdown.

**Bloqueada por:** Persistir el run del One-shot y ofrecer retomarlo

**Relacionadas:** One-shot: detectar loops sin progreso real

## M8a — Completado predictivo: núcleo sin IA  (7/7, 7 en revisión)

CompletionController, GhostTextRenderer de una línea, Tab/Esc, ProjectContext en segundo plano y proveedor local (reglas, recuperación, historial + ranker).

**Hecho cuando:**
- `@onready var ` sugiere nodos hijos reales con tipo y ruta; `func _` sugiere virtuales con firma; una línea repetida se sugiere al tipear su comienzo.
- Tab sin sugerencia sigue indentando y el popup nativo no se rompe.
- p95 < 10 ms por consulta en un proyecto de 200 scripts (medido y logueado).

### 8.1 CompletionController: disparo, debounce e invalidación · Revisión

**Prioridad:** alta · **Tamaño:** M · **Responsable:** Claude

Uno por CodeEdit (enganche con editor_script_changed). Dispara con caret al final o solo cierres a la derecha, sin selección, popup nativo cerrado, archivo .gd. Invalida al mover de línea, tipear distinto, Esc o perder foco. Type-through. Atajo manual Alt+\ (spec §16.5).

**Prueba:** tests/unit/test_completion_controller.gd (CodeEdit real, reloj simulado: debounce, condiciones de disparo, type-through, invalidación, respuesta vieja, Alt+\); --godot-agent-completion-test en 4.4.1/4.7.2/4.8.

**Notas:** completion/completion_controller.gd + completion_service.gd. text_changed/caret_changed llegan diferidos: se compara contra el último estado (línea, columna, get_version). Debounce vía tick(now) desde el servicio. Detalles en D26.

### 8.2 GhostTextRenderer y aceptación · Revisión

**Prioridad:** alta · **Tamaño:** M · **Responsable:** Claude

Texto atenuado con draw_string sobre el CodeEdit respetando fuente, scroll, wrap y zoom. Tab acepta (una acción de undo), Esc descarta; interceptar solo con sugerencia visible y popup cerrado. Documentar si gui_input alcanza o hace falta _input.

**Prueba:** test_completion_controller (Tab acepta en una acción de undo, Tab sin sugerencia indenta, Esc, popup nativo); --godot-agent-completion-test con capturas (posición en el caret, recorte al área de texto).

**Notas:** gui_input + accept_event alcanza (no hizo falta _input). x del ghost = get_caret_draw_pos: get_rect_at_line_column al final de la línea devuelve el carácter anterior (4.4 y 4.8). TextLine recortado sin minimapa ni scrollbar.

### 8.3 ProjectContext indexado en segundo plano · Revisión

**Prioridad:** alta · **Tamaño:** L · **Responsable:** Claude

extends/class_name y API de la clase base (ClassDB), firmas de clases del proyecto, nodos hijos por escena que usa el script ($ y %), autoloads, input map, grupos, señales conectadas. Invalidación por archivo con filesystem_changed.

**Prueba:** test_completion_rules.test_context_index (fixture); test_completion_bench (build 200 scripts ≈180 ms, rebuild incremental).

**Notas:** project_index.gd (worker, inmutable al publicarse, reutiliza por mtime salvo archivos de <2 s) + project_context.gd (ClassDB, ProjectSettings, escena abierta con caché). Sin persistencia: <1 s.

### 8.4 ContextRules · Revisión

**Prioridad:** alta · **Tamaño:** M · **Responsable:** Claude

Reglas de la tabla §16.2a: @onready var, $/%, acciones de input, func _ virtuales con firma, .connect(, func _on_, grupos, preload/load, extends.

**Prueba:** tests/unit/test_completion_rules.gd: un test por regla sobre tests/completion_fixture.

**Notas:** local/context_rules.gd: @onready var (nombres repetidos con el padre), $/%, acciones, func _ virtuales, .connect(, func _on_ (solo con firma conocida), grupos, preload/load por tipo, extends.

### 8.5 LineRetrieval, SessionHistory y Ranker · Revisión

**Prioridad:** alta · **Tamaño:** M · **Responsable:** Claude

Índice de líneas normalizadas con puntaje frecuencia × cercanía × recencia; predicción de línea siguiente; historial de sesión estilo fish; ranker con umbral, margen y desempate por longitud; presupuesto <5 ms en el hilo principal.

**Prueba:** tests/unit/test_completion_local.gd (índice, cercanía × recencia, ambigüedad, historial, ranker, post-procesado, reglas primero); bench p95 1,5–1,7 ms.

**Notas:** line_index.gd (bsearch sobre líneas únicas ordenadas), typed_history.gd, ranker.gd, local_provider.gd, post_processor.gd (M8a: una línea, solapamiento con suffix, descartes, balanceo). La predicción de línea siguiente quedó para M8b (m9-01).

### 8.6 Fixture, tests y benchmark del completado · Revisión

**Prioridad:** alta · **Tamaño:** M · **Responsable:** Claude

tests/completion_fixture/ (escenas, %únicos, input map, autoloads, señales); tests de cada regla, retrieval y ranker; benchmark con 200 scripts generados: p95 < 10 ms por consulta, logueado.

**Prueba:** tests/unit/test_completion_bench.gd: 200 scripts + 60 escenas generados, 1500 consultas: p95 1,52 ms (4.8), 1,61 (4.7.2), 1,73 (4.4.1); imprime la medición y falla si p95 ≥ 10 ms.

**Notas:** tests/completion_fixture/ (con .gdignore; input map y autoloads en project_settings.cfg), tests/fake_completion_provider.gd, test_completion_{rules,local,controller,bench}.gd (23 tests), addons/godot_agent_dev/completion_check.gd (Script Editor real).

### 8.7 Verificar M8a · Revisión

**Prioridad:** alta · **Tamaño:** S · **Responsable:** Claude

@onready var sugiere nodos hijos reales con tipo y ruta; func _ sugiere virtuales con firma; una línea repetida se sugiere; Tab sin sugerencia indenta y el popup nativo no se rompe; p95 < 10 ms. Actualizar progress.

**Prueba:** run_all (109 tests, 752 checks), acp_session_check (90) y oneshot_check (34) en 4.4.1, 4.7.2 y 4.8-beta1; --godot-agent-completion-test (onready, nodo único, Tab+undo, Esc, ancla en el caret, func _, línea repetida, Tab indenta, autocierre, popup nativo) y cycle test en las tres; bench p95 1,29/1,43/1,62 ms.

**Notas:** Revisión de código aplicada (selección/multi-caret, % operador, binds y señales multilínea, cachés, Script Editor flotante, tipos desconocidos, costo por tecla, guarda de dibujo, fondo con cierres, indexado apagado, exclude, Alt+\, whitelist de recursos, no adivinar, cancelación). Riesgo conocido documentado en D26: recarga @tool con build en curso. El cycle test crece 29 objetos también sin el servicio de completado (previo a M8a).

## M8b — Completado predictivo: calidad local  (6/6, 6 en revisión)

Línea siguiente y bloques cortos, ghost text multilínea, aceptación por palabra, n-gram, adaptación de identificadores, post-procesado completo, caché y set de evaluación.

**Hecho cuando:**
- El set de evaluación reporta resultados por fuente y el n-gram mejora la línea base de reglas + recuperación.

### 8b.1 Línea siguiente, bloques cortos y adaptación de identificadores · Revisión

**Prioridad:** alta · **Tamaño:** M · **Responsable:** Claude

Recuperación de bloques de hasta N líneas mientras el corpus coincida y la indentación se mantenga; adaptación de un identificador (mana/health) aplicada al resto de la línea (spec §16.2b).

**Prueba:** run_all -- completion: test_next_line_and_blocks, test_identifier_adaptation, test_provider_next_line_blocks_and_adaptation. Editor (--godot-agent-completion-test, 4.4.1/4.7.2/4.8): después de `func reset() -> void:` + Enter se sugiere el cuerpo de 3 líneas de otros dos scripts. Eval: 7 casos de línea siguiente/parientes ganados por recuperación.

**Notas:** LineIndex guarda la secuencia de líneas por archivo (texto + sangría) y, para cada clave ordenada, las posiciones [archivo, línea]. Línea siguiente: en línea vacía tras una con código; sangría relativa, nunca menor que la escrita. Bloques: extend() exige que todas las apariciones (>= 2) sigan iguales; corta en línea en blanco, sangría menor, max_lines o la línea de abajo. Adaptación: rotaciones de identificadores (MAX_ROTATIONS 4), sustitución snake/Pascal/UPPER, peso 0,9, sin bloque. SUPPORT_SCALE bajado a 1 por el eval (D27).

### 8b.2 Ghost text multilínea y aceptación por palabra · Revisión

**Prioridad:** alta · **Tamaño:** M · **Responsable:** Claude

Primera línea inline y el resto en una caja translúcida bajo la línea actual (o +N si queda mal, documentado). Ctrl+→ acepta la siguiente palabra (accepted_partial).

**Prueba:** Editor real en 4.4.1, 4.7.2 y 4.8 (completion_check paso 7): bloque de 3 líneas visible, renderer.box de >= 2 filas, Ctrl+→ inserta `combo_multiplier` y deja ` = 1…`, Tab inserta el resto. Capturas ampliadas: caja legible, `")` del autocierre tapado, caret visible. Unit: next_word en test del controller.

**Notas:** Overlay: canvas item propio hijo del CodeEdit (RenderingServer), limpiado en cada draw y liberado en detach/PREDELETE. Lo dibujado desde la señal draw quedaba bajo el texto en 4.8, así que el tapado de cierres de M8a no funcionaba; quedó corregido acá. Caja casi opaca (0,96, sin el alpha del theme: en 4.4 el fondo es translúcido), fondo del stylebox normal (background_color es transparente en el Script Editor). Si abajo no entra y arriba hay más lugar, la caja va arriba (pasa en 4.4 con el caret en la última fila). Ctrl+→ = command_or_control; signal accepted_partial y log en cmp.

### 8b.3 Lexer GDScript y modelo n-gram · Revisión

**Prioridad:** alta · **Tamaño:** L · **Responsable:** Claude

Lexer simple (identificadores, keywords, operadores, strings, números, newline/indent/dedent); 4-gramas con stupid backoff, generación greedy hasta fin de línea o confianza baja; entrenamiento en WorkerThreadPool, actualización por archivo; corpus extra configurable.

**Prueba:** run_all -- completion: test_completion_ngram (lexer, generation, incremental_update = reentrenar, provider_uses_ngram). Eval: el n-gram solo da 5/5 correctas sin FP y suma 1 correcta sobre reglas+recuperación sin sumar FP. Bench: build 785–817 ms con 200 scripts (< 1 s), p95 < 2,3 ms.

**Notas:** Tokens con su espacio adelante; claves int (20 bits por id); clase <num> en contextos; COW por archivo si cambió <= 30 %, mismo objeto si nada cambió. Generación: paso > 0,5, acumulada > 0,3, soporte >= 2, para en empates. Cachés de stats y rangos ordenados (bsearch) en el hilo principal: p95 3,7 -> 0,7 ms. Regex compiladas al cargar (static var): lazy era una carrera worker/main. Corpus extra (godot_agent/completion/extra_corpus) solo entrena el n-gram.

### 8b.4 PostProcessor y SuggestionCache · Revisión

**Prioridad:** alta · **Tamaño:** M · **Responsable:** Claude

Pasos de §16.6 en orden (tokens FIM, recorte al bloque, solapamiento con suffix, indentación del editor, descartes, chequeo de balanceo) y caché LRU por hash de prefix. Tests con salidas defectuosas reales.

**Prueba:** run_all -- completion: test_post_processor_defective_outputs (FIM, stops, recorte, solapamiento, sangría tabs/espacios, paréntesis multilínea), test_suggestion_cache (LRU, hits/misses). El servicio vacía la caché al publicar índice y al cambiar Settings.

**Notas:** PostProcessor.process(text, request, max_lines, stops). Con suffix no vacío fuerza una línea. Sangría con request.indent_unit() (indent_use_spaces/indent_size del CodeEdit). SuggestionCache: 64 entradas, clave ruta:hash del texto:línea:largo del prefijo:manual:generación del proveedor (índice, ProjectSettings, escena abierta, historial; agregada por la revisión: sin ella devolvía sugerencias viejas). Los resultados en caché se marcan cached y se loguean como hit.

### 8b.5 Set de evaluación del completado · Revisión

**Prioridad:** alta · **Tamaño:** M · **Responsable:** Claude

tests/completion_eval/ con 30–50 recortes reales y script headless que corre cualquier combinación de fuentes: exact match de primera línea, similitud por tokens, cobertura, falsos positivos y latencia, por fuente.

**Prueba:** godot --headless --path . --script tests/run_completion_eval.gd [-- combos] [--cases]: 48 casos, tabla por combinación y por fuente ganadora (exactas, correctas, FP, similitud, cobertura, p50/p95). test_completion_eval valida los casos y corre la regresión.

**Notas:** tests/completion_eval/project: juego propio "Mossy Caverns" (33 scripts, 20 escenas, .gdignore). cases.txt: file | line | cut, ⏎ marca espacio final, 4 grupos. El runner corta el archivo en el caret y lo pasa como buffer sin guardar. El historial arranca vacío por caso (se prueba en unit).

### 8b.6 Verificar M8b · Revisión

**Prioridad:** alta · **Tamaño:** S · **Responsable:** Claude

El set de evaluación reporta resultados por fuente y el n-gram mejora la línea base de reglas + recuperación. Ajustar umbrales priorizando precisión. Actualizar progress.

**Prueba:** Eval en 4.4.1/4.7.2/4.8 (iguales): reglas+recuperación 19 mostradas/17 correctas/2 FP; +n-gram 20/18/2 FP (antes de M8b: 17/11/6 FP). test_completion_eval exige más correctas con n-gram, FP sin subir, precisión >= 0,85, p95 < 10 ms. Todas las suites pasan en las 3 versiones (run_all 122 tests/877 checks sin los de M8c, acp 90, oneshot 34, cycle, completion en el editor).

**Notas:** Ajustes por precisión: veto de reglas cuando no pueden elegir, convención de nombres de @onready aprendida del proyecto, hijos directos primero, herencia, load(" por nombre de variable, clase número en el n-gram, salida del n-gram con al menos un nombre. Probados y descartados: min_support 1 (más FP); umbral del n-gram sin el factor de backoff (sin cambios en el set). Quedan 2 FP ambiguos de verdad. Revisión de código: 9 hallazgos corregidos (race del vocabulario del n-gram, adaptación con prefijo existente, caché con generación, Tab en el mismo frame, líneas largas, build cancelado, 2 espacios, sangría en el contexto del n-gram, recorte del overlay); detalle en progress.md. progress.md, D27 y README actualizados.

## M8c — Completado predictivo: LLM opcional  (4/4, 4 en revisión)

Proveedor Ollama y modo híbrido; después llama.cpp, Codestral, OpenAI-compatible y Gemini (experimental). Métricas e indicador en el Script Editor.

**Hecho cuando:**
- Cambiar de proveedor y de modo desde Settings sin reiniciar el editor.
- En híbrido, la sugerencia local nunca se demora por el LLM.
- Latencias p50 por fuente visibles en el log.

### 8c.1 Interfaz de proveedores, proveedor falso y modo híbrido · Revisión

**Prioridad:** alta · **Tamaño:** M · **Responsable:** Claude

CompletionProvider (complete/cancel/describe) con LlmProvider sobre HTTPRequest reutilizado; tests/fake_completion_provider.gd con latencia configurable; modos solo local / híbrido / solo LLM con las reglas de §16.1 (el LLM nunca reemplaza ni demora lo local; una request en vuelo; secuencia).

**Prueba:** test_completion_controller: test_hybrid_mode (lo local en el mismo frame aunque haya un LLM falso de 300 ms en vuelo; sin pedido si hubo algo local; debounce del LLM; tipear cancela y la respuesta cancelada no se muestra; Alt+\ fuerza el LLM) y test_llm_only_mode. test_completion_llm: LlmProvider contra tests/fake_llm_server.gd (respuesta, cancelación sin esperar al server, reutilización del HTTPRequest, HTTP 404, conexión rechazada, sin key no se manda nada). En el editor real (--godot-agent-completion-test, 4.4.1/4.7.2/4.8): híbrido de punta a punta contra el server falso.

**Notas:** LlmProvider: un HTTPRequest por editor SIN hilos (con use_threads, cancel_request() espera al hilo y se traba contra un server en el hilo principal). cancel_request() no emite request_completed: la cancelación se avisa a mano (RESULT_CANCELLED propio) y un contador de generación descarta respuestas tardías. Controller: MODE_LOCAL/HYBRID/LLM; en híbrido _llm_due = max(ahora, última tecla + debounce LLM) solo si no hubo nada local; la respuesta se muestra solo si suggestion vacía y seq/versión/caret iguales. tests/fake_completion_provider.gd ahora tiene `source` configurable. D28.

### 8c.2 Proveedores Ollama, llama.cpp, Codestral, OpenAI-compatible y Gemini · Revisión

**Prioridad:** media · **Tamaño:** L · **Responsable:** Claude

Endpoints verificados contra la documentación y anotados en decisions.md. Plantillas FIM por perfil, stop tokens, keys por nombre de variable de entorno, aviso de envío de código en perfiles remotos, Gemini marcado experimental. Contexto de ProjectContext con presupuesto y prioridad.

**Prueba:** test_completion_llm: test_profiles (defaults por tipo, is_remote con localhost/127.0.0.1/[::1] vs red, experimental, to_dict sin key), test_build_requests (URL, headers y body de los 5 tipos, plantillas FIM, límites de stops), test_parse_responses (formatos, errores, cercos y thought de Gemini, respuesta bloqueada), test_split_and_context (recorte en salto de línea, contexto con presupuesto). test_settings_dialog: key pegada rechazada, aviso de host remoto.

**Notas:** Endpoints verificados (docs y código en el scratchpad dl/) y anotados en D28: Ollama /api/generate (suffix → 400 en modelos sin FIM; con plantilla, raw:true), llama.cpp /infill en el puerto 9931 con input_extra, Codestral /v1/fim/completions en api.mistral.ai (additionalProperties false), OpenAI /v1/completions con la plantilla de Qwen por defecto (suffix no es portable, máx. 4 stops), Gemini generateContent con x-goog-api-key, gemini-3.5-flash-lite, experimental. Keys solo por nombre de variable (OS.get_environment en cada pedido; vacía → no se manda nada). Contexto de ProjectContext como comentarios #, prioridad nodos > base > clases > autoloads > acciones > grupos, 4 chars/token. Sin Ollama ni llama.cpp en la máquina: no se probó contra un modelo real.

### 8c.3 Métricas, indicador y settings del completado · Revisión

**Prioridad:** media · **Tamaño:** M · **Responsable:** Claude

Canal cmp con fuente, latencia, tamaños, resultado y caché (sin código salvo raw). Contadores p50/p95 y aceptación por fuente en Settings. Indicador en el Script Editor (estado y modo, clic on/off, atajo global). Settings de §16.10 aplicables sin reiniciar.

**Prueba:** test_settings_dialog: test_completion_section (carga, validación de la sección: key pegada con y sin guiones, codestral sin variable, híbrido sin perfiles, corpus relativo; stops con escapes; ABM de perfiles con id libre y activo; aviso de host remoto) y test_completion_save (cada valor a EditorSettings o a project_config; tabla de contadores). En el editor real: indicador en la barra del Script Editor con «local» → «híbrido · fake-coder», «pensando» mientras espera, error con HTTP 500, Alt+Shift+\ apaga y prende; cambio de modo sin reiniciar.

**Notas:** completion_metrics.gd: p50/p95 (últimas 200), mostradas/aceptadas/parciales/errores por fuente; en el log cada 10 sugerencias y en Settings → Completado («Esta sesión, por fuente», con reinicio). completion_indicator.gd: Button en el primer HBoxContainer con MenuButton del Script Editor. Settings → Completado es una página propia (ui/settings/completion_settings_page.gd) que el diálogo agrega como sección; completion_enabled y completion_exclude entran en el rollback de CONFIG_PROPERTIES. plugin.gd conecta completion_metrics_provider/reset. El log cmp nunca lleva código salvo completion/log_raw; un error HTTP solo muestra campos de mensaje conocidos (revisión: un 422 de FastAPI repite el prompt).

### 8c.4 Verificar M8c · Revisión

**Prioridad:** alta · **Tamaño:** S · **Responsable:** Claude

Cambiar de proveedor y modo desde Settings sin reiniciar; en híbrido la sugerencia local nunca se demora por el LLM (proveedor falso lento); latencias p50 por fuente en el log. Ollama real si está instalado. Actualizar progress.

**Prueba:** Matriz en 4.4.1, 4.7.2 y 4.8-beta1: run_all 131 tests / 995 checks, acp_session_check 90, oneshot_check 34, cycle test y --godot-agent-completion-test con el paso híbrido contra tests/fake_llm_server.gd (cambio de modo sin reiniciar, un solo pedido con modelo y prefix, marcador, error, vuelta a local sin pedidos). Lo local nunca espera al LLM: test_hybrid_mode con un proveedor falso de 300 ms en vuelo.

**Notas:** Ollama y llama.cpp no están instalados en esta máquina: no se probó contra un modelo real (pasos manuales en progress.md M8c). Revisión de código del diff hecha y corregida (progress.md M8c › Revisión de código): body de error al log, JSON de perfiles con tipos inválidos, redirecciones que reenviaban key y código (max_redirects 0, body ≤ 1 MB), Codestral/Gemini sin key, suffix con caret al final de línea, HTTPRequest sin liberar en un controller reemplazado. Además is_remote con [::1] y keys sin guiones. Los settings del paso del editor son los EditorSettings reales y se restauran al terminar.
