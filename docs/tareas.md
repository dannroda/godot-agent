# Tareas — agent-harness

> Export de `compass/`, que es la fuente de verdad. No editar: los cambios se hacen en `compass/` o con `scompass`, y este archivo se regenera.
> Generado: 2026-10-29

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

## M2 — Tool calls, diffs y permisos  (10/10, 10 en revisión)

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

El test de line_diff se agregó después (tests/unit/test_line_diff.gd).

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

### Modo Auto: chat sin pedir permiso, shell clasificada por listas revisables · Revisión

**Prioridad:** media · **Tamaño:** M · **Etiquetas:** `permisos`

Pedido del usuario (2026-10-22): un modo para el chat que no corte a cada rato. Es como Construir, pero sin pedir permiso para lo que se puede deshacer. No es One-shot: sin spec, plan, presupuestos ni evaluador; es solo una política de permisos.

**Matriz** (`PermissionPolicy.DEFAULTS`, nueva columna AUTO en `SessionModel.HarnessMode`):
- read, diagnostics, edit_scene, edit_files, run y project se permiten (red de seguridad: ↶ de las tarjetas, undo del editor, D48);
- shell lo decide el clasificador.
Los overrides por proyecto y «permitir en esta sesión» siguen funcionando igual.

**Clasificador de shell, por reglas** (no por modelo: predecible, sin costo, testeable), con tres resultados:
- **allowlist** (se permite): comandos de lectura o build, como `ls`, `cat`, `grep`, `find`, `git status/diff/log/show`, `godot --headless …`;
- **denylist** (siempre se pregunta, nunca se permite solo): lo destructivo o hacia afuera, como `rm`, `git push/reset/checkout/clean`, `curl`/`wget`, instaladores de paquetes, `sudo`, y escribir o redirigir fuera del proyecto;
- **el resto**: se pregunta.

Un comando compuesto (`&&`, `;`, `|`, `$(…)`, backticks) se permite solo si cada parte está en la allowlist. Si hay redirección a un archivo, se evalúa también la ruta de destino.

**Listas revisables** (pedido explícito del usuario): tiene que poder ver qué comandos entran en cada lista y por qué.
- Las listas se guardan en project_config: patrón + origen (default / agregado por el usuario / agregado desde una tarjeta de permiso) + fecha.
- La tarjeta de permiso de una shell en Auto ofrece «Permitir siempre este comando» y «Preguntar siempre». No agrega nada sin que el usuario lo elija, y al agregar muestra el patrón que va a quedar (p. ej. `npm test` vs `npm *`) para poder ajustarlo.
- En Settings → Permisos, una sección «Modo Auto» con las dos listas: ver, editar, borrar, origen de cada entrada, y «restaurar defaults».
- Canal `permissions` en el Agent Log: cada decisión del clasificador (comando, resultado, regla que lo decidió). Así se puede revisar después qué se permitió solo.

**UI:** «Auto» en el selector de modo del dock (con tooltip que explique qué permite) y en es.po.

Registrar la decisión de diseño como D57 en docs/decisions.md y actualizar la wiki (Modos y Settings, en/es) y la spec.

**Decisiones:**
- ✓ La tarjeta de shell en Auto no ofrece «Preguntar siempre» ni «Siempre en esta sesión»: solo «Permitir siempre» con el patrón editable; la lista «preguntar siempre» se edita en Settings
  Por qué: La tarjeta ya está preguntando, así que agregar a esa lista solo importa si hay un allow más amplio; y «siempre en esta sesión» habría abierto todo el grupo shell, listas incluidas
  Descartado: Ofrecer los dos botones en la tarjeta (como decía la descripción); dejar «siempre en esta sesión»
- ✓ Defaults: allowlist de lectura/build incluyendo `godot --headless *`; «preguntar siempre» para rm, mv, sudo, chmod, kill, git push/reset/checkout/restore/clean/rebase, curl, wget, ssh, instaladores y find -delete/-exec
  Por qué: `godot --headless` es como el agente valida scripts; puede correr código arbitrario, igual que run_scene (que en Auto está en allow)
  Descartado: Dejar `godot --headless *` afuera de la allowlist (preguntaría cada vez); listas más amplias (sort, tree, file, que pueden escribir con flags)
- ✓ Auto va entre Construir y One-shot en el dock y en Settings; en el enum va al final (valor 4) para no cambiar los demás
  Por qué: Orden de menos a más autonomía; el valor del enum no se renumera
  Descartado: Ponerlo al final de la barra, después de One-shot
- ✓ Las decisiones del clasificador van al canal `perm` que ya existía en el Agent Log, no a un canal `permissions` nuevo
  Por qué: El canal perm ya registra cada permiso (allowed by mode, asking, denied); así las decisiones de Auto quedan intercaladas con las demás, en orden
  Descartado: Un canal `permissions` aparte solo para el modo Auto

**Prueba:** Todo en 4.8-beta1 y 4.6.3:
- run_all 205/0, con test_shell_rules (allow/ask, compuestos, comillas, sustituciones, redirecciones, patrones con `*`, sugerencias) y test_permission_policy (columna Auto y overrides);
- acp_session_check 133/0 (escenario auto_shell: ls && git status sin tarjeta; rm con tarjeta; «Permitir siempre» de npm test cubre npm test -- --watch; edición sin tarjeta; redirección con tarjeta; regla con origen y fecha; log perm);
- oneshot_check 125/0;
- editor: --godot-agent-auto-test (botón Auto del dock, tarjetas resueltas con sus botones, config guardada, regla vista, filtrada y borrada en Settings → Permisos), mcp, edit, run, oneshot e i18n (es): PASS.

**Notas:** Commit 0f083c0 en la rama auto-mode (worktree agent-harness-st), subida a origin; ya está en main. D57 en docs/decisions.md.
- Nuevo: session/shell_rules.gd (clasificador), ui/settings/auto_rules_page.gd (listas en Settings), addons/godot_agent_dev/auto_check.gd, tests/scripts/auto_shell.json.
- Config: project_config.auto_shell_rules ({pattern, list, origin, added}).
- Tarjeta: patrón editable + «Permitir siempre». No se ofrece si una regla allow no ganaría (redirección, sustitución, lista ask).
- Diferencias con la descripción, registradas como decisiones: sin «Preguntar siempre» en la tarjeta, y canal perm en lugar de uno nuevo.
- Capturas de la tarjeta y de Settings revisadas.

### Modo Auto: probar un comando contra las reglas desde Settings · Revisión

**Prioridad:** baja · **Tamaño:** S

Pedido del usuario (2026-10-22), sigue a m2-09 (D57). Hoy, para saber si un comando de shell corre solo o pregunta en Auto, hay que esperar a que el agente lo use y mirar el Agent Log.

En Settings → Permisos → «Modo Auto: comandos de shell», un campo donde se escribe un comando y muestra al momento el resultado de ShellRules.classify con las reglas que se están editando (todavía sin guardar): corre / pregunta, la regla que decidió y el motivo (parte fuera de la allowlist, redirección, sustitución…). Si se puede, marcar en la tabla la regla que decidió.

Tests: unitario si hace falta lógica nueva, y el check del editor de Auto (--godot-agent-auto-test) usando el campo.

**Prueba:** test_shell_rules: código y segmento de cada tipo de decisión (permitido, lista ask, fuera de la allowlist, sustitución, sustitución de procesos, redirección, comilla, vacío) y el texto del resultado. --godot-agent-auto-test: con la regla agregada desde la tarjeta, «ls && npm test --watch» corre sin preguntar con las dos reglas, la fila se resalta, y «git push origin main» pregunta; captura revisada. Suite completa verde en 4.8-beta1 y 4.6.3, i18n incluido.

**Notas:** Commit 21c6977, ya en main (vino de la rama auto-rule-tester). Durante el desarrollo, un scroll_to_item diferido con un TreeItem ya borrado tiró el editor; ahora el scroll es directo al final del refresh. Esa caída dejó un project_config.tres en el worktree (el check no llegó a restaurarlo); se borró a mano.

## M3 — Servidor MCP y tools de lectura  (9/9, 9 en revisión)

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

### Consultar la API del motor · Revisión

**Prioridad:** media · **Tamaño:** S · **Etiquetas:** `swallowtail`

Como engine.classinfo/search/docs de swallowtail. Tool de lectura que responde con lo que tiene la versión de Godot del editor abierto: métodos, propiedades, señales, constantes y herencia de una clase (ClassDB), búsqueda por nombre o capacidad, y la documentación cuando esté disponible. Evita APIs inventadas o de otra versión (4.6 vs 4.8). Sirve en todos los modos, incluido Preguntar.

**Decisiones:**
- ✓ Las descripciones salen del caché de docs que arma el editor (`editor_doc_cache-<major>.<minor>.res`); los miembros, de ClassDB
  Por qué: Godot no expone la documentación a GDScript. El caché lo regenera el editor para su propio binario, así que coincide con la versión abierta, y carga en ~80 ms. ClassDB manda sobre qué existe (incluye GDExtensions sin docs).
  Descartado: Bajar el XML de docs de GitHub por versión (red, y no coincide con builds propios); solo ClassDB sin descripciones. Si el formato interno del caché cambia, la tool sigue andando sin descripciones.

**Prueba:** `tests/unit/test_api_tools.gd` (firmas con defaults, sin setters, herencia, miembro heredado, built-ins y @GlobalScope desde el caché, sugerencias para KinematicBody2D, búsqueda con filtros, BBCode a texto, índice en <3 s): pasa en 4.6.3, 4.7.2 y 4.8-beta1. `--godot-agent-mcp-test` en el editor real (4.8-beta1): tools/list las incluye, class_info Timer con descripción, class_name del proyecto y search_api.

**Notas:** Commit fe41b95 (rama swallowtail-tools). `mcp/tools/api_tools.gd`, grupo read (sirve en Preguntar):
- `class_info(class, member?, inherited?, description?)`: herencia, métodos con firma (virtual/const/static), propiedades con default, señales, enums y constantes, con una línea de descripción. Sin `inherited`, solo los miembros propios. `member` busca también en los ancestros y da la descripción completa. Clase inexistente → nombres parecidos.
- `search_api(query, kind?, class?)`: todas las palabras en el nombre (y en la descripción breve, para clases). Índice de ~19k entradas en ~300 ms, se arma la primera vez; no pide defaults (ClassDB instanciaría cada clase).
- Engine classes desde ClassDB + caché; built-ins, @GlobalScope y @GDScript solo del caché; class_name del proyecto desde su script.
- System prompt: consultar estas tools antes de usar una API dudosa. Wiki (en/es) y spec §6 actualizados.

### Tool genérica con descubrimiento cuando crezcan las tools · Revisión

**Prioridad:** baja · **Tamaño:** M · **Etiquetas:** `swallowtail`

Como godot_run + engine.commands de swallowtail. Cada tool MCP suma su descripción al contexto del agente en cada turno. Con las tareas de swallowtail la lista crece mucho. Mantener un núcleo de tools tipadas (lectura, edición de escenas, ejecución) y exponer el resto por una tool genérica godot.run(method, params), más una tool que lista los métodos disponibles con sus parámetros. Medir el tamaño de tools/list antes y después. Los permisos se siguen aplicando por método.

**Decisiones:**
- ✓ Lista compacta activada por defecto: núcleo tipado (lectura, diagnóstico, edición de escenas, run_scene/stop_scene/capture_game_frame) más godot.methods y godot.run; API, proyecto, archivos, recursos, tilemaps, animación y game_* pasan a extendidas
  Por qué: tools/list baja de 29.978 a 11.232 caracteres (−63 %) en cada turno; lo de todos los turnos queda tipado y lo puntual se descubre con methods. Permisos, validación y log siguen por método, y llamar por nombre directo sigue funcionando (D56)
  Descartado: Desactivada por defecto; un solo godot_run para todo, sin núcleo tipado; dejar class_info/search_api en el núcleo; mover también la edición de escenas a extendidas

**Prueba:** run_all (test_tool_registry: lista compacta, methods con filtro y detalle, run con validación y permiso del grupo del método; test_session_model: ToolCall desenvuelve run) 197/0 en 4.8-beta1 y 4.6.3; --godot-agent-mcp-test por HTTP (lista sin extendidas, methods, run(class_info), llamada directa) PASS en 4.8-beta1 y 4.6.3; edit-test y run-test PASS en 4.8-beta1 con compacto activo.

**Notas:** Commit 07a1d14 en swallowtail-tools (D56). Medido: completo 55 tools / 29.978 caracteres → compacto 26 tools / 11.232 (−63 %); la salida de methods sin filtro son 5.359 caracteres, solo cuando se pide. Setting compact_tools en Settings → Servidor MCP (default activado; vale desde la próxima sesión). ToolCall.godot_tool_name()/godot_arguments() desenvuelven run, así el deshacer de la tarjeta y el conteo del One-shot ven la tool real. El prompt de sistema explica que una tool nombrada que no está en la lista se usa vía methods/run.

## M4 — Tools de edición y ejecución  (13/13, 13 en revisión)

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

### Inspeccionar y controlar el juego en ejecución · Revisión

**Prioridad:** alta · **Tamaño:** L · **Etiquetas:** `swallowtail`

Como runtime.* e input.* de swallowtail. Con el juego corriendo (run_scene o un run manual), el agente puede leer el árbol vivo, leer y cambiar propiedades, llamar métodos, esperar una condición o una señal (waitfor, awaitsignal), mandar inputs en vivo (tecla, acción, click, secuencia) y leer los errores del juego. Hoy solo hay inputs fijos al lanzar, capturas y errores, así que verificar "el jefe murió" o "subió el puntaje" es adivinar por la imagen. Sirve en Construir (probar lo que se acaba de hacer), en Revisar (reproducir un bug) y en One-shot (checks y el evaluador de m6-09). Se apoya en el autoload de playtest (que ya se quita al terminar y nunca llega al export). El canal juego ↔ editor queda en 127.0.0.1 con token, como el MCP.

**Decisiones:**
- ✓ El canal juego↔editor es el del debugger (request/reply con id por el probe de playtest), sin socket ni token propios; runs manuales solo con el setting de autoload en runs manuales
  Por qué: El debugger del editor ya escucha solo en 127.0.0.1 y habla únicamente con el juego que lanzó; un socket aparte duplicaba eso. El probe sigue sin llegar al export.
  Descartado: Un servidor TCP/WebSocket en el juego con token como el MCP; inyectar el probe siempre en runs manuales.
- ✓ Un paso de input sin `pressed` ahora es apretar y soltar (0.1 s), también en run_scene; game_tree/game_get van en el grupo read y el resto en run
  Por qué: Un tap es lo que se quiere casi siempre; antes un paso sin pressed dejaba la tecla apretada. Leer el juego no cambia nada; game_wait evalúa una Expression que puede llamar métodos, así que va en run.
  Descartado: Mantener el default de solo apretar; todas las tools game_* en run.

**Prueba:** tests/run_in_xvfb.sh <godot> --godot-agent-run-test pasa en 4.8-beta1, 4.7.2 y 4.6.3: game_tree (árbol vivo, sin el probe), game_get (variables del script, propiedades pedidas, nodo inexistente), game_set (conversión de vectores y error de valor inválido), game_call (resultado, método inexistente), game_wait (condición, timeout, condición rota, señal con argumentos), game_input (acción, Ctrl+S y click recibidos por el juego). Unit: test_run_tools (normalize_steps). Suite: 193 tests, 0 fallos; mcp-test 0 fallas.

**Notas:** Commit 27deaa5 en swallowtail-tools (D54). Protocolo 2 del probe: request [id, op, params] → reply [id, {text}|{error}]; ops tree, get, set, call, wait, input. Los resultados incluyen los errores [game] nuevos; si el juego está parado en el debugger lo dice. Los inputs de run_scene usan los mismos pasos (action, key, event, click, move). En 4.6/4.7 el motor deja un error "get_node() with absolute paths…" en @implicit_new del primer script con variables cuando corre bajo el debugger (no es del harness, en 4.8 no pasa); el run-check lo ignora. System prompt y loop_detector conocen las tools nuevas.

**Relacionadas:** One-shot: evaluator separado y vuelta de corrección

### Armar escenas en lote · Revisión

**Prioridad:** alta · **Tamaño:** M · **Etiquetas:** `swallowtail`

Como batch.addnodes y node.duplicate de swallowtail. Una tool que crea un subárbol entero (nodos anidados con tipos, propiedades, scripts e instancias) en una llamada y un solo paso de deshacer, y otra que duplica un nodo con sus hijos. Hoy cada nodo es un add_node: escribir el .tscn a mano era más corto, y D48 lo bloquea. Sirve en cualquier modo que edite escenas.

**Prueba:** `--godot-agent-edit-test` en el editor real (4.8-beta1 y 4.6.3): add_nodes arma HUD (CanvasLayer > Label, HBox con script nuevo > Button + escena instanciada) y un Marker2D, con owners, grupos, propiedades y script; un Ctrl+Z lo saca entero; un item inválido anidado no crea nada y el error dice la ruta (Bad/X). duplicate_node copia Player con Sprite, grupo, script y posición al lado del original; Ctrl+Z la saca; con new_name/new_parent va bajo Enemies.

**Notas:** Commit 36ebd0a (rama swallowtail-tools).
- `add_nodes(parent, nodes, scene?)`: items {name, type | scene, properties?, script?, groups?, children?}. Arma todo fuera del árbol, valida antes de tocar la escena (todo o nada) y lo aplica en una acción de EditorUndoRedo. Tope de 200 nodos por llamada.
- `duplicate_node(node_path, new_name?, new_parent?)`: Node.duplicate con señales, grupos, scripts e instanciación; restaura owners por ruta relativa; nombre libre Player2, Player3…
- System prompt: add_nodes para subárboles nuevos.
- Hallazgo aparte: los checks del editor que se cortaban por un error de script devolvían null y daban "PASS: 0 fallas". En el worktree pasaba porque `tests/tmp/` (ignorado por git) no existía. Ahora un corte cuenta como falla y el plugin de dev crea `tests/tmp`.

**Relacionadas:** El agente no escribe el proyecto por fuera del editor

### Project settings por el editor: input map, autoloads y settings · Revisión

**Prioridad:** alta · **Tamaño:** M · **Etiquetas:** `swallowtail`

Como inputmap.*, project.addautoload/setsetting de swallowtail. Tools para leer y cambiar acciones de input (con sus eventos), autoloads y project settings a través del editor (ProjectSettings + guardar), con deshacer cuando se pueda. Hoy el agente edita project.godot como texto y D33 lo sincroniza, pero es frágil. Con las tools, el harness puede rechazar también las ediciones a mano de project.godot (extensión de D48). Grupo de permisos: project.

**Decisiones:**
- ✓ El grupo project pasa a allow en One-shot (antes ask)
  Por qué: Solo lo usan las tools nuevas, y antes el agente hacía lo mismo escribiendo project.godot con edit_files, que en One-shot se permite. Con ask, un One-shot desatendido se quedaba esperando (y vencía el permiso) para agregar una acción de input.
  Descartado: Dejar las tools en edit_files (pierde el control aparte que pide la tarea); dejar ask (regresión del One-shot). En Construir sigue preguntando; se puede volver a ask en Settings → Permisos.

**Prueba:** `test_project_tools` (teclas con modificadores, mouse, joypad por nombre y número, ejes con signo, errores) y `test_project_write_guard` (project.godot por Write y por `sed -i`). `--godot-agent-edit-test` en 4.8-beta1 y 4.6.3: set_input_action guarda en project.godot, append y dos Ctrl+Z la sacan; set_project_setting + project_settings con prefijo, tipo inválido → error, input/ → su tool, Ctrl+Z revierte; set_autoload / remove_autoload con undo; el nombre `Input` se rechaza; Preguntar deniega; project.godot igual al final. acp_session_check: 117 checks, 0 fallos.

**Notas:** Commits b2fb5ae y 7edecdd (rama swallowtail-tools). D49 en docs/decisions.md.
- `mcp/tools/project_tools.gd`: `project_settings` (read) y `set_project_setting`, `set_input_action`, `remove_input_action`, `set_autoload`, `remove_autoload` (grupo project).
- Cada cambio es una acción del historial global de deshacer y guarda project.godot (también al deshacer). El «↶ undo» del chat sigue siendo solo para escenas: estas se deshacen con Ctrl+Z.
- Guard: project.godot entra en `ProjectWriteGuard.is_editor_managed`; el rechazo de fs/write_text_file nombra las tools. Traducción del aviso actualizada.
- Grupo project: allow en One-shot (antes ask), ver la decisión. Construir pregunta; Preguntar y Revisar deniegan.
- `ProjectSettings.save()` reescribe `config/features` con la versión del editor (como hace el editor).

**Relacionadas:** El agente no escribe el proyecto por fuera del editor

### Mover, copiar y borrar archivos arreglando referencias · Revisión

**Prioridad:** media · **Tamaño:** M · **Etiquetas:** `swallowtail`

Como fs.move/copy/delete de swallowtail. Mover o renombrar actualiza las rutas res:// en escenas y recursos, mueve los .uid/.import y mantiene el uid. Copiar da un uid nuevo. Borrar se niega si algo lo referencia o si es una escena abierta, y dice qué se rompería. Hoy el agente usa mv/rm y una escena queda rota sin aviso. Con las tools, el harness puede rechazar mv/rm/cp dentro del proyecto (extensión de D48).

**Prueba:** `test_project_write_guard.test_file_commands` (mv, rm -rf, cp hacia el proyecto sí / hacia afuera no, git mv, sudo con ruta absoluta, rm en /tmp, rm dentro de un string). `--godot-agent-edit-test` en 4.8-beta1 (dos corridas seguidas) y 4.6.3: mover una escena instanciada por otra y precargada por un script reescribe ambas y mantiene el uid; mover la carpeta y el script (con su .uid) también; la escena que la instancia sigue cargando con el script; delete_file se niega y lista level.tscn y spawner.gd; copy_file da uid nuevo; delete_file sin referencias borra; no mueve una escena abierta ni pisa un archivo.

**Notas:** Commit 819ddf7 (rama swallowtail-tools). D50 en docs/decisions.md.
- `mcp/tools/file_tools.gd` (grupo edit_files): `move_file`, `copy_file`, `delete_file`. Los archivos reescritos pasan por EditorSync.after_agent_write (scripts abiertos, escenas abiertas, conflictos).
- copy_file trae también archivos de afuera del proyecto (assets bajados).
- delete_file va a la papelera del sistema cuando se puede (la prueba deja un hero_copy.tscn en la papelera por corrida).
- Guard: mv, cp (destino), rm, rmdir, unlink, git mv/rm sobre el proyecto → rechazo.
- Sin deshacer del editor (no hay API para el FileSystem); quedan checkpoints y git.
- Hallazgo: reescribir un script recarga ese script en el editor y corta sus corrutinas suspendidas. Le pasó a la propia prueba (tenía la ruta como literal). Las tools del harness son síncronas, y `addons/godot_agent` queda fuera de las reescrituras.

**Relacionadas:** El agente no escribe el proyecto por fuera del editor

### Tools de tilemaps · Revisión

**Prioridad:** media · **Tamaño:** M · **Etiquetas:** `swallowtail`

Como tilemap.* de swallowtail. Para TileMapLayer y TileSet: crear la capa, agregar fuentes de atlas o de escenas, poner celdas, rellenar rectángulos, pintar con terrenos, leer celdas y las usadas, limpiar. Todo con deshacer. tile_map_data no se puede escribir a mano, y sin tools el agente arma los niveles desde código. Sirve para construir niveles en Construir y One-shot (p. ej. el Megaman de great-boy-one).

**Prueba:** `--godot-agent-edit-test` en 4.8-beta1 y 4.6.3: TileMapLayer con TileSet inline vía add_node; tileset_add_atlas de una textura 48×16 crea 2 tiles (el transparente no) con colisión y capa de física; tilemap_set_cells con rect y celdas sueltas (una con otro atlas); tile inexistente → error; tilemap_get muestra 12 celdas, la fila `3 aaaaaaaaaa`, la leyenda y la capa de física; Ctrl+Z deshace un set; erase; clear y su Ctrl+Z; paint_terrain sin terrenos → error que explica; con un terreno armado, pinta 3×3 por nombre; sobre un Timer → error.

**Notas:** Commit 11ec564 (rama swallowtail-tools). D52 en docs/decisions.md.
- `mcp/tools/tilemap_tools.gd`: tilemap_get (read); tileset_add_atlas, tileset_add_scenes, tilemap_set_cells, tilemap_paint_terrain, tilemap_clear (edit_scene). Usan el botón «↶ undo» del chat, como las demás tools de escena.
- La capa se crea con add_node/add_nodes (tile_set inline gracias a D51).
- Deshacer de celdas: tile_map_data antes/después. Un TileSet .tres se guarda al hacer y al deshacer.
- Fuera por ahora: configurar terrenos (peering bits). Se pinta con los que ya tenga el TileSet.

### Tools de animación · Revisión

**Prioridad:** media · **Tamaño:** M · **Etiquetas:** `swallowtail`

Como animation.* (y más adelante animtree.*) de swallowtail. Crear animaciones en un AnimationPlayer, agregar pistas y keyframes, leer y borrar, con deshacer; también SpriteFrames para AnimatedSprite2D. Hoy set_properties no llega a pistas ni keyframes, y el agente anima por código o escribe la biblioteca a mano.

**Prueba:** `--godot-agent-edit-test` en 4.8-beta1 y 4.6.3: animation_create (length, loop linear, autoplay); animation_set_track de position (3 keys, continuous), modulate con colores y una pista de método; key fuera del largo y propiedad inexistente → error; animation_get con keys; Ctrl+Z quita la pista de método; animation_remove de una pista y de la animación (con su autoplay), y Ctrl+Z la restaura; sprite_frames_set desde una hoja (AtlasTexture, autoplay, sin la animación default), reemplazo de cuadros y Ctrl+Z; animation_get de un AnimatedSprite2D.

**Notas:** Commit 4dd9bbf (rama swallowtail-tools). D53 en docs/decisions.md.
- `mcp/tools/animation_tools.gd`: animation_get (read); animation_create, animation_set_track, animation_remove, sprite_frames_set (edit_scene), con el botón «↶ undo» del chat.
- Undo: copia editada de la animación cambiada en su AnimationLibrary; SpriteFrames restaurado cuadro por cuadro. Bibliotecas/SpriteFrames en .tres propios se guardan al hacer y al deshacer.
- Fuera por ahora: AnimationTree (animtree.* de swallowtail, la descripción dice "más adelante"), pistas bezier, de audio y 3D.

### Recursos .tres: crear, leer y editar · Revisión

**Prioridad:** media · **Tamaño:** M · **Etiquetas:** `swallowtail`

Como resource.* de swallowtail. Crear un recurso (built-in o de un script con class_name) con sus propiedades, leerlo y editarlo a través del editor, y asignarlo a un nodo. Es lo que pide el diseño data-driven (valores ajustables en Resources). Hoy el agente escribe los .tres a mano. Con las tools, el harness puede rechazar también los .tres escritos a mano (extensión de D48).

**Prueba:** `test_resource_values` (StyleBoxFlat inline con hint, error con tipo que no cumple, class_name FixtureLoot con Array[FixtureItem] que sigue tipado, describe sin defaults) y `test_project_write_guard` (.tres a mano). `--godot-agent-edit-test` en 4.8-beta1 y 4.6.3: create_resource FixtureLoot con items inline (uno con StyleBoxFlat inline) y weights; get_resource muestra `[0] <FixtureItem, inline>`, bg_color y weights sin defaults; set_resource_properties guarda y Ctrl+Z revierte y vuelve a guardar; panel.tres asignado por ruta y luego un StyleBoxFlat inline con set_properties; add_nodes con un class_name sin @tool; no pisa. Suite: 192 tests, 0 fallos.

**Notas:** Commit 5b19448 (rama swallowtail-tools). D51 en docs/decisions.md.
- `mcp/tools/resource_tools.gd`: `get_resource` (read), `create_resource` y `set_resource_properties` (edit_files). Para asignar a un nodo: `set_properties` con la ruta res:// o inline.
- ValueCoercion: recursos inline `{"type": …}` contra el hint, y arrays tipados elemento por elemento (sirve en set_properties y add_nodes).
- Arreglo de paso: en el editor, `script.new()` falla para class_name sin @tool. Ahora se instancia la base nativa y se pone el script (como el Inspector). `add_node` con un class_name de nodo también fallaba por eso.
- Guard: `.tres` a mano se rechaza.
- Fixtures nuevos con class_name: tests/fixtures/resources/ (FixtureItem, FixtureLoot, FixtureEnemy).

**Relacionadas:** El agente no escribe el proyecto por fuera del editor

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

## M6 — One-shot  (18/18, 18 en revisión)

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

### One-shot: evaluator separado y vuelta de corrección · Revisión

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

**Decisiones:**
- ✓ El evaluador corre en una sesión nueva del mismo proceso del agente, con permisos restringidos en la política (no edita), y después se vuelve a la sesión del que construye con restart_session
  Por qué: Las tools godot.* se autorizan con el controller del dock: un segundo proceso habría heredado los permisos de One-shot salvo con un token por rol en el server MCP. Volver con restart_session reusa el camino de la recuperación (session/load o sesión nueva con resumen).
  Descartado: Segundo SessionController y proceso del agente para el evaluador, con un token MCP por rol.
- ✓ qa_rounds (default 2) cuenta evaluaciones, con una vuelta de corrección entre una y otra; la última evaluación decide el final. Una evaluación sin checks ni puntajes no tiene veredicto y termina el run sin otra vuelta
  Por qué: Con 2: QA → corrección → QA y fin, como pide el test. Repetir una evaluación que no da veredicto gasta presupuesto sin información nueva.
  Descartado: Contar vueltas de corrección (QA hasta 3 veces con 2); reintentar la evaluación sin veredicto.

**Prueba:** tests/oneshot_check.gd (125 checks, 0 fallos en 4.8-beta1 y 4.6.3): escenario "evaluador" con el agente falso en dos roles (evaluator_turns): el generator reporta todo en pass; el evaluador, en sesión nueva sin el prompt del generator y con edit_files/edit_scene/shell en deny y run en allow, encuentra que el puntaje no sube; el run vuelve al generator con checks, criterios y hallazgos; corrige y la vuelta 2 aprueba ("QA round 2: the game passes."). También qa-1.md/qa-2.md, checks verified, actividad qa, playtests del evaluador en el presupuesto, informe con las vueltas. --godot-agent-oneshot-test pasa en 4.8-beta1 y 4.6.3 (fase «Evaluating · QA round 1», Pausar habilitado, banner final, actividad, tabla del informe). Unit 193/0, acp_session_check 117/0.

**Notas:** Commit 65f9317 en swallowtail-tools (D55; las referencias a "D42" en D40/D41 pasaron a D55). Setting nuevo qa_rounds en Settings → One-shot. PermissionPolicy.restrictions y SessionController.mode_rules_override sirven para cualquier rol futuro. Pendiente del enunciado: afinar el prompt leyendo trazas reales del evaluador (necesita correr con Claude Code real). Arreglé de paso el check del dock en oneshot-test ("el dock ofrece «Resume One-shot»"), que fallaba desde dc2fc2d bajo Xvfb porque la pestaña del dock no era la elegida en su slot: ahora mira la visibilidad dentro del dock.

**Relacionadas:** One-shot: criterios de evaluación para juegos; Inspeccionar y controlar el juego en ejecución

### One-shot: spec y progreso en archivos (planner y traspaso) · Revisión

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

**Prueba:** test_oneshot_files; oneshot_check «spec» (espera, guiar, aprobar con cambios, termina, spec.md en git, informe con files_dir); --godot-agent-oneshot-test con Revisar/Aprobar spec. Matriz 4.6.3/4.7.2/4.8-beta1 + 24 UI checks en verde.

**Notas:** ad50af8 (D41). OneShotFiles (oneshot/oneshot_files.gd) escribe en <proyecto>/.godot_agent/oneshot/<id>/:
- spec.md: paso 0 del prompt, de alto nivel (mecánicas, loop, dirección visual, criterio de «terminado»);
- progress.md: se actualiza al cerrar cada tarea;
- qa-<n>.md: lo escribe el evaluador (m6-09).
El prompt de resumen manda leer esos archivos.

Opción «Revisar el spec antes de construir» (form y Settings, config spec_review): agrega Phase.SPEC_REVIEW y approve_spec.

Decisión git/export:
- .godot_agent/.gdignore deja la carpeta fuera del FileSystem y del export; además, el export plugin saltea res://.godot_agent/;
- la carpeta entra en los checkpoints, sincronizada con el código;
- SUMMARY_PATHSPEC la excluye de «Revisar cambios».

Feedback del usuario, resuelto en 755ef8b (oneshot-wip):
- durante la revisión, la columna Plan muestra el spec con «Editar» y «Aprobar spec»;
- diálogo con pestañas Spec, Progreso y QA, más «Mostrar en carpeta» y «Abrir con editor externo»;
- los links a .godot_agent desde el chat abren ese visor; otros archivos que no son recursos usan OS.shell_open.

**Relacionadas:** Persistir el run del One-shot y ofrecer retomarlo

### One-shot: criterios de evaluación para juegos · Revisión

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

**Prueba:** test_game_criteria (resolve con overrides, textos de prompt/rúbrica, veredicto, bloque scores del parser) en 4.6.3 y 4.8; settings-shots muestra la grilla; cycle test y oneshot_check en verde.

**Notas:** a17a419 (D40). oneshot/game_criteria.gd: 4 criterios (jugabilidad 3/7, funcionalidad 3/7, visual y feel 2/5, código 1/5 = peso/mínimo), cada uno con 3 anclas de puntaje (3/6/9) para calibrar al evaluador; AUDIO_NOTE (no puede oír). generator_text va en initial_prompt; evaluator_rubric la usa el evaluador de m6-09. verdict(): pasa si cada criterio con peso llega al mínimo (sin puntaje = no pasa), promedio ponderado. FindingsParser lee `scores` [{criterion, score 0–10, reason}]; el criterio se reconoce por id o nombre sin tildes. Config `criteria` (solo lo que difiere del default) + grilla Peso/Mínimo en Settings → One-shot. Contratos por sprint quedan afuera (ver D40).

**Relacionadas:** One-shot: evaluator separado y vuelta de corrección

### One-shot: cambiar presupuestos con el run en curso, y opción ilimitado · Revisión

**Prioridad:** alta · **Tamaño:** S

Pedido del usuario (2026-10-22): una vez arrancado el One-shot, poder cambiar los presupuestos de tiempo, tokens y playtests desde la pantalla Agent, y tener un botón o setting "ilimitado" para cuando el run ya está en curso.

Qué hacer:
- Editar cada presupuesto desde la barra de arriba del run (spin al tocar la barra, o un diálogo «Presupuestos»), con un "sin límite" por presupuesto y un «Ilimitado» general.
- Al subir un presupuesto que ya pasó el 80 % o el 100 %:
  - se rearman los avisos;
  - si el run estaba cerrando por presupuesto y todavía no mandó el pedido de reporte final, sigue.
- Se guarda en el estado del run (D37) y queda en la actividad y en el informe (D39).

**Prueba:** oneshot_check._scenario_budget_raise: cerrando por tiempo, se sube el presupuesto y el run sigue. --godot-agent-oneshot-test cubre el diálogo de presupuestos con «Ilimitado». Matriz 4.6.3/4.7.2/4.8-beta1 y 24 UI checks en verde.

**Notas:** 755ef8b (rama oneshot-wip, worktree agent-harness-wt). Main sigue sin avanzar porque el editor del usuario usa el addon por symlink.
- El botón «Presupuestos» se ve mientras el run está activo. Abre un diálogo con un spin por presupuesto (0 = sin límite) y la acción «Ilimitado».
- OneShotRun.set_budgets rearma los avisos y registra la actividad y budget_changes en el informe.
- Si el cierre fue por presupuesto (BUDGET_CLOSE_PREFIX) y ya no hay ninguno agotado, el run sigue:
  - en CLOSING vuelve a RUNNING;
  - en RUNNING continúa después del cancel, o con _resume_prompt.
- En la barra, el texto es «x / y min» o «x min / ∞».

### Pantalla Agent: el editor del objetivo es chico en monitores grandes · Revisión

**Prioridad:** media · **Tamaño:** S

Pedido del usuario (2026-10-22): en la pantalla Agent, el campo para escribir el prompt del One-shot queda chico en monitores grandes. El panel del formulario tiene un ancho fijo de 640 px y el objetivo, 110 px de alto.

Qué hacer:
- Que el formulario y el TextEdit del objetivo escalen con el tamaño de la pantalla, con un mínimo y un máximo razonables.
- Revisar también el campo «Guiar al agente» de la vista del run: que sea multilínea y crezca.
- Verificarlo con capturas a 1280×720 y a 2560×1440.

**Prueba:** --godot-agent-oneshot-test verifica que el formulario crezca a 1920×1200 (captura _form). Matriz y UI checks en verde.

**Notas:** 755ef8b (oneshot-wip).
- El formulario ocupa el 62 % del ancho, entre 640 y 1400 px.
- El objetivo ocupa el 40 % del alto disponible, con un mínimo de 110 px.
- Los tamaños se recalculan con _fit_form, conectado a center.resized.
- Se sacó el campo «Guiar al agente»: la guía va por el chat del dock, cuyo placeholder cambia durante el One-shot.

### Cola de guía visible en el One-shot · Revisión

**Tamaño:** S

El usuario no veía dónde quedaban los mensajes encolados durante un One-shot. Ahora, al escribir en el chat mientras el agente trabaja, se agrega al log una entrada de tipo guía «en cola: …» y se muestra un aviso en el chat. Cuando el mensaje sale de verdad, se agrega «enviado: …».

**Prueba:** oneshot_check presupuestos: «en cola» y «enviado» en orden, y el aviso del chat. oneshot_check loop: en pausa, la guía sale enseguida.

**Notas:** 518c819.
- OneShotRun._queue_guidance agrega la actividad «guía · en cola: …» y un aviso en el chat.
- _pop_guidance registra «enviado: …» cuando la guía sale de verdad. Si sale enseguida, se registra «enviado» directo.
- _user_guidance separa la guía del usuario de la que mete el harness (por ejemplo el aviso de loop) y se persiste.
- Color «guía» en la actividad.

### One-shot: cambiar de cuenta al llegar al límite y retomar sin perder contexto · Revisión

**Prioridad:** alta · **Tamaño:** M

El usuario llegó al límite de 5 h en un One-shot real (great-boy-one, 2026-10-22). Preguntó si puede cambiar de cuenta y si el botón Reintentar sobrevive a cerrar el editor.

Hoy pasa esto:
- «Reintentar» del dock abre una sesión en blanco, y el run después retoma ahí sin contexto.
- Cambiar de cuenta en una terminal no tiene efecto hasta que se relanza el proceso del agente.
- Un run en Limitado que se restaura al reabrir el editor queda en pausa normal y no retoma solo.

Qué hacer:
- En Limitado / Pausado por cuota, un botón «Cambié de cuenta» que reinicia el proceso del agente, limpia el estado de cuota de la cuenta anterior y retoma con session/load.
- Con un One-shot activo, «Reintentar» del dock retoma el run con su sesión.
- Al restaurar, si el run estaba en Limitado o Pausado por cuota, vuelve a esa fase con su cuenta regresiva.
- El prompt de reanudación menciona spec.md y progress.md si existen.

**Prueba:** oneshot_check «cambio de cuenta»: límite, suspend y restore en Pausado por cuota sin retomar antes de hora, después switch_account y termina; el informe cuenta account_switches. --godot-agent-oneshot-test: menú en Limitado, y «Reintentar» del dock retoma en la misma sesión.

**Notas:** 69155d2 (D45).
- MenuButton «Cambiar de cuenta» en la pantalla Agent, con dos opciones:
  - login con un método del agente; al terminar, SessionController.after_login llama a switch_account;
  - «Ya inicié sesión con otra cuenta (en una terminal)».
- switch_account: QuotaMonitor.forget_account, controller.stop y resume con session/load de la misma sesión.
- «Reintentar» del dock con un One-shot activo pasa por retry_interceptor y va a resume() en la sesión del run.
- Se persisten phase_id y quota_resume_at: un run en Limitado o Pausado por cuota vuelve a Pausado por cuota y retoma solo a la hora.
- El prompt de reanudación menciona spec.md y progress.md.
- Arreglo aparte (b041a85): el informe lista los checkpoints después de esperar la cola de git (fallo intermitente en 4.7).

### One-shot: tiempos visibles de tareas, turnos y tools · Revisión

**Prioridad:** media · **Tamaño:** S

El usuario pidió (2026-10-22) ver cuánto tarda la sesión en hacer cada cosa.

Qué hacer:
- Mientras corre: cada tarea del plan muestra su duración (las terminadas, cuánto tardaron; la actual, un contador).
- La actividad registra el fin de cada turno con su duración.
- Las tool calls muestran su duración (el dock ya lo hace por grupo).
- Al final: el informe ya tiene las duraciones por tarea (D39); sumar el desglose por turno y el tiempo de espera por cuota.

**Prueba:** test_run_report (timing, markdown, persistencia, task_ms, format_ms). oneshot_check: actividad de turnos y espera por cuota en el informe. --godot-agent-oneshot-test: duraciones en el plan.

**Notas:** f9b7582.
- RunReport suma:
  - turns [{started_ms, ms, reason, tools}] y waits (quota, paused, spec_review);
  - el tiempo acumulado (ms) de cada tool;
  - task_ms() para la duración de una tarea;
  - format_ms().
- El informe gana timing (trabajando, turnos, promedio, el más largo, esperas), la sección «Tiempos» y la columna de tiempo en Tools.
- Run:
  - una actividad «Turno N · duración · n tools» por turno, con el motivo si fue cortado o falló;
  - la duración en cada actividad de tool;
  - las esperas se miden en _set_phase (WAIT_KINDS).
- Plan: un label de duración por tarea que se actualiza en cada refresco sin rearmar la lista.
- Además: is_git_busy() cuenta las operaciones en cola (_git_pending); antes daba false un frame entre operaciones y el escenario de cuota fallaba de forma intermitente.

### La pausa por cuota no llegaba si la tarea no cambiaba · Revisión

**Prioridad:** alta · **Tamaño:** S

Reporte del usuario (great-boy-one, 2026-10-22): el banner decía «Cuota al 95 %: se pausa en el próximo checkpoint», pero el One-shot nunca pausó.

Causa: la pausa solo se disparaba cuando el plan pasaba a otra tarea. Si el agente seguía en la misma tarea o trabajaba sin plan, no llegaba nunca. Además, al terminar un turno se mandaba «Seguí con el plan» sin mirar la cuota.

Arreglo:
- Pausar al terminar el turno.
- Red de seguridad: si la pausa lleva 10 min programada o la cuota llega al 98 %, se corta el turno y se pausa con un checkpoint -quota.
- El banner dice cuándo va a pausar.

**Prueba:** oneshot_check: «cuota al terminar el turno» (no manda otro turno y retoma solo), «cuota con tope de espera» (corta el turno con cp3-quota) y el escenario de cuota de siempre. test_quota_monitor y --godot-agent-oneshot-test para la regla.

**Notas:** b4736c0 (D44).
- La pausa por cuota también se dispara al terminar el turno, antes de mandar «Seguí con el plan».
- _check_quota_pause corta el turno y pausa con un checkpoint -quota si la pausa lleva QUOTA_PAUSE_GRACE_S (600 s) programada o la cuota llega a QUOTA_PAUSE_HARD (0,98).
- quota_pause_text() alimenta el banner: dice cuándo pausa y cuánto falta para que corte igual.
- Textos: «se pausa al terminar la tarea o el turno en curso».

### Dock: retomar el One-shot al reabrir el editor · Revisión

**Prioridad:** alta

Al reabrir con un One-shot a medias, el aviso contaba como conversación y el dock escondía «Start session»: no había cómo arrancar ni retomar desde el dock. Ahora el botón sigue a la vista con solo avisos y, con un run esperando, dice «Resume One-shot»; el aviso trae «Resume One-shot» y «Open Agent screen».

**Prueba:** --godot-agent-oneshot-test simula la reapertura (chat vacío, sin sesión, _restore_oneshot del plugin): el aviso trae «Resume One-shot» y «Open Agent screen», y el dock muestra «Resume One-shot». Matriz 4.6.3/4.7.2/4.8-beta1 verde (27 UI checks).

**Notas:** Commit dc2fc2d. Venía de D37: el aviso del run a medias contaba como conversación y escondía la vista vacía.

## M7 — Pulido  (51/53, 51 en revisión)

Settings completos, historial de sesiones, Markdown→BBCode robusto, rendimiento con sesiones largas (>500 entradas) y README de uso.

**Hecho cuando:**
- Settings completos y persistidos.
- Sesión de más de 500 entradas sin degradación visible.
- README de uso escrito.

### Reportar a Godot el EditorDock huérfano de _has_main_screen (4.8) · Revisión

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

- [x] Zipear tests/upstream/main_screen_orphan
  Proyecto mínimo: legacy_ms (_has_main_screen) + driver que lo alterna 5 veces y cuenta EditorDock huérfanos. Correr: godot --headless --editor --path . -- --cycle. Zipear sin .godot/ ni .uid.
- [x] Probar en el último 4.8 publicado antes de abrir el issue
  Si ya está arreglado, cerrar la tarea y anotar la versión.
- [ ] Abrir el issue con la plantilla de bug
  Tested versions: 4.8-beta1, master e7cfa294a; regresión de #113051. Incluir la causa y el arreglo probable.
- [x] Decidir si se saca el cambio a 2D de remove_all()
  El error de grab_focus ya no se reproduce; el cambio a 2D es inofensivo pero su comentario describe un bug que no aparece. Actualizar D9.

**Decisiones:**
- ✓ Se deja el cambio a "2D" en remove_all() como precaución, con el comentario y D9 corregidos (el error de grab_focus ya no se reproduce)
  Por qué: No cuesta nada y solo se descartó el bug en Linux (xvfb y headless); sacarlo arriesga reintroducirlo en Windows/macOS sin ganar nada
  Descartado: Sacar el cambio a 2D y simplificar remove_all()

**Prueba:** Issue abierto en godotengine/godot con el repro adjunto y su link en notes (pendiente: lo abre el usuario). Si se arregla upstream, `tests/plugin_cycle_check.gd` pasa en esa versión con la main screen por `_has_main_screen()`.

**Notas:** 2026-10-22: 4.8-beta1 sigue siendo el último 4.8 publicado. El repro sigue fallando en 4.8-beta1 (4d10419ca) y master e7cfa294a: 2 → 7 EditorDock huérfanos en 5 ciclos. editor_main_screen.cpp no cambió después de a1bf7cf93 (18/10, incluido en e7cfa294a). No hay issue ni PR. Nota: c40a33125 depreca _has_main_screen(), así que upstream puede darle poca prioridad; el issue lo menciona. Borrador del issue (plantilla de bug, scripts inline) en tests/upstream/issue_main_screen_orphan.md y zip del MRP en tests/upstream/main_screen_orphan.zip (repo principal, sin trackear). El usuario prefirió abrirlo él: falta pegar el link acá. Cambio a 2D de remove_all(): queda como precaución, con el comentario y D9 corregidos (commit 9f3464e).

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

### Persistir el run del One-shot y ofrecer retomarlo · Revisión

**Prioridad:** alta · **Tamaño:** M

El estado del One-shot (plan, checks, checkpoints, presupuestos, actividad) vive solo en memoria en `oneshot/oneshot_run.gd`. Si el editor crashea, se pierde todo. Visto en little-villages el 2026-10-22: después del crash, para la sesión era como si el One-shot no hubiera corrido.

Qué hacer:
- Guardar el run en `user://godot_agent/oneshot/<id>.json` a medida que avanza, con escritura atómica (archivo temporal y después rename).
- Al abrir el editor con un run sin terminar o reciente, ofrecer "Retomar". Eso restaura la pantalla y hace `session/load` de la sesión ACP.
- Avisar antes de arrancar un One-shot si el repo no tiene commits, porque sin commits no hay checkpoints.

**Prueba:** - `test_oneshot_store`.
- `oneshot_check` (recuperación): el editor "se cae" a mitad de turno, otra instancia carga el run y retoma con el resumen hasta cp3.
- `--godot-agent-oneshot-test`: la pantalla con un run cargado (banner, Retomar, plan, actividad) y Detener lo cierra.

**Notas:** D37. `oneshot/oneshot_store.gd` guarda en `user://godot_agent/oneshot/<id>.json`, con la captura en `<id>.png`. Escribe con archivo temporal y rename, y conserva los últimos 20 runs.
- **Cuándo guarda:** en cada cambio de fase y como mucho cada 2 s mientras corre.
- **Al cerrar el editor:** `_exit_tree` del plugin llama a `suspend()` en lugar de `stop()`, así el run queda guardado como activo.
- **Al abrir el editor:** `_restore_oneshot` carga el run a medias en pausa y avisa en el dock. Hasta retomar se ve el plan guardado (`current_plan()`).
- **Retomar:** reabre su propia sesión con `reopen` (session/load) o, si no puede, abre una nueva con `_summary_prompt`.
- **Aviso antes de empezar:** si los checkpoints no se pueden usar, un diálogo ofrece seguir sin ellos. Antes el warning de `preflight` se ignoraba.
- **Prueba de UI:** usa una carpeta temporal para el store, así un run a medias no aparece en otra prueba.

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

### One-shot: detectar loops sin progreso real · Revisión

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

**Prueba:** test_loop_detector (8 tests); oneshot_check escenario «loop» con umbral 2: dos Edit fallidos cortan el turno y piden otro enfoque, el mismo check roto pide otro enfoque y después pausa, guiar retoma. Matriz 4.6.3/4.7.2/4.8-beta1 + 24 UI checks en verde.

**Notas:** c2faff8 (D38). LoopDetector (oneshot/loop_detector.gd) con tres huellas: check con el mismo detalle en `repeats` reportes seguidos; tool call que falla con los mismos argumentos (si es lectura/verificación, un cambio en el medio reinicia la cuenta); el mismo cambio repetido repeats+1 veces en las últimas 40. Primera vez: actividad «loop», aviso y guía "otro enfoque" (corta el turno si viene de tool calls); la misma huella otra vez: pausa con banner (pause_note). Umbral `loop_repeats` (3) en project_config + Settings → One-shot.
Corrección a la descripción: _idle_continues no se reiniciaba por el resumen sino por playtests; ahora el avance real son tareas completadas + checks en pass (_progress()).

**Relacionadas:** One-shot: informe de métricas de la corrida

### One-shot: informe de métricas de la corrida · Revisión

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

**Prueba:** test_run_report; oneshot_check (recuperación: informe en disco con lo de antes de la caída; loop: loops/guías/fallas); --godot-agent-oneshot-test abre el informe y busca godot.run_scene y pong.gd. Matriz completa en verde.

**Notas:** c2faff8 (D39). RunReport (oneshot/run_report.gd) junta métricas mientras corre (tareas in_progress→completed, tools por nombre con fallas, fallas por check, eventos: turnos, errores, permisos pedidos/denegados, pausas por cuota, límites, loops, guías) y se guardan dentro del estado (sobreviven a una caída). _finish → _write_report: build + changes_summary → store.save_report(<id>.report.json), se poda con el run. UI: botón «Informe» (barra de abajo, al terminar) con el Markdown renderizado y «Copiar Markdown».

**Bloqueada por:** Persistir el run del One-shot y ofrecer retomarlo

**Relacionadas:** One-shot: detectar loops sin progreso real

### Interfaz en inglés con traducción al español · Revisión

**Prioridad:** alta · **Tamaño:** L

El usuario pidió que el plugin esté primero en inglés y traducido al español. Los textos de la UI pasan a inglés con tr() y la traducción española va en un .po que se carga en el dominio de traducción del editor. Elegido con el usuario: el idioma sigue al del editor de Godot, y Settings → Interfaz suma un override (Automático / English / Español). Lo que lee el agente (descripciones de las tools MCP, prompts del One-shot, system prompt, rúbrica) queda solo en inglés, con la instrucción de responder en el idioma del usuario. Hay unos 650 literales en español repartidos por ui, oneshot, session, mcp y otras carpetas, y los tests se actualizan al inglés.

**Prueba:** run_all (test_i18n: catálogo completo, placeholders, sin entradas sin usar) y --godot-agent-i18n-test con GODOT_AGENT_LANGUAGE=es (dock, pantalla Agent, Agent Log y cada página de Settings sin textos traducibles en inglés). Matriz 4.6.3/4.7.2/4.8-beta1 verde en 6541f02.

**Notas:** D46. Texto fuente en inglés; español en addons/godot_agent/i18n/es.po (~620 msgids), cargado con load() como Translation. Idioma: GODOT_AGENT_LANGUAGE > Settings → Interface → Language > idioma del editor; se aplica al reabrir. Lo que lee el agente (prompts, tools, logs, nombres de deshacer, commits de checkpoint) queda solo en inglés. Raíces con auto_translate desactivado; los diálogos ponen cancel_button_text = I18n.t("Cancel"). Commit da82c9f (+ ajustes en 6541f02 y dc2fc2d).

### README en inglés y en español · Revisión

**Tamaño:** M

README.md pasa a inglés y README.es.md queda como versión en español. Cada uno enlaza al otro y a la wiki. El contenido se mantiene al día con lo que hace el plugin (One-shot con spec, presupuestos editables, guía por el chat, informe, criterios).

**Prueba:** README.md y README.es.md enlazan a la wiki de su idioma; los nombres de botones en negrita coinciden con los textos de la interfaz (script de verificación contra el código y es.po).

**Notas:** Commit c274ae8.

### Mini wiki: cómo funciona y cómo usarlo (en y es) · Revisión

**Tamaño:** M

Crear docs/wiki/en y docs/wiki/es con páginas Markdown sobre cómo funciona y cómo usarlo: arquitectura (ACP, MCP, editor), primeros pasos, modos y permisos, tools MCP, One-shot (spec, presupuestos, checkpoints, cuota, informe, criterios), Revisar, completado predictivo, Settings y troubleshooting. Se puede copiar tal cual a la wiki de GitHub.

**Prueba:** docs/wiki/en y docs/wiki/es con 10 páginas cada una (inicio, primeros pasos, cómo funciona, modos y permisos, herramientas del editor, One-shot, revisión, completado, settings, problemas frecuentes); etiquetas verificadas contra la interfaz final.

**Notas:** Commit c274ae8. Pendiente si cambian etiquetas: volver a correr la verificación de negritas contra el código.

### El agente usa el binario del editor abierto para correr Godot · Revisión

**Prioridad:** alta · **Tamaño:** S

El usuario reportó que el agente corre `godot --headless` y toma el godot del PATH, que puede ser otra versión que la del editor abierto. Hay que darle el binario del editor: OS.get_executable_path() en las variables de entorno GODOT y GODOT_BIN del proceso del agente, un shim `godot` al frente del PATH del hijo, y una regla en el system prompt con la ruta. project_info también la reporta.

**Prueba:** test_editor_binary (entorno, contenido del shim y que el shim corra la versión del editor). acp_session_check: el agente falso ve $GODOT y el shim al frente del PATH, y el prompt nombra el binario.

**Notas:** 08bfad4 (oneshot-wip, D43). transport/editor_binary.gd entrega el binario por tres vías:
- GODOT y GODOT_BIN en el entorno del agente (el perfil puede pisarlas);
- un shim `godot` en <cache>/godot_agent/bin-<hash>/, al frente del PATH;
- una regla con la ruta en el system prompt y en project_info.
La regla del prompt es la que manda, porque la shell de Claude Code puede volver a armar el PATH desde .zshrc.

### El addon no cargaba en un juego con class_name Level · Revisión

**Prioridad:** alta

great-boy-one declara class_name Level y el addon tenía enum Level (ChatEntry): Godot resolvía el tipo a la clase global y el dock no compilaba (4.6, 4.7 y 4.8). Enums y clases internas con nombres compuestos (D47), clases globales genéricas en tests/fixtures/global_names y test_type_names.

**Prueba:** Con tests/fixtures/global_names en el proyecto (Level, State, Kind, Phase, Request…), el código anterior da los mismos Parse Error; con el arreglo, matriz 4.6.3/4.7.2/4.8-beta1 verde (27 UI checks) y una copia de great-boy-one abre sin SCRIPT ERROR. test_type_names falla con un enum o clase interna de una palabra.

**Notas:** D47. Commit 6541f02, ya en main.

### El agente no escribe el proyecto por fuera del editor · Revisión

**Prioridad:** alta

En great-boy-one el agente del One-shot editó un script con un heredoc de python3 y escribió escenas con cat >, salteándose el editor (el usuario mostró cómo lo hace swallowtail). D48: rechazo automático de shell que escribe archivos del proyecto y de .tscn/.uid/.import a mano, reglas en el system prompt, y create_scene con script y propiedades de la raíz.

**Prueba:** test_project_write_guard (24 casos, incluidos los comandos de la captura del usuario); acp_session_check _scenario_project_writes (modo One-shot: 3 «Rejected:» sin tarjeta); edit-test con create_scene + script + exports. Matriz 4.6.3/4.7.2/4.8-beta1 verde: run_all 176/1328, acp 117, oneshot 106, 27 UI checks. El external-test de 4.6.3 no imprimió nada en la matriz y pasó al repetirlo solo.

**Notas:** Commit 9f289c8 (D48). ACP no lleva el motivo del rechazo: el system prompt explica la regla, y el chat avisa con «Rejected: … without going through the editor».

**Relacionadas:** Armar escenas en lote; Project settings por el editor: input map, autoloads y settings; Mover, copiar y borrar archivos arreglando referencias; Recursos .tres: crear, leer y editar

### Convenciones de Godot en el system prompt · Revisión

**Prioridad:** alta · **Tamaño:** S · **Etiquetas:** `swallowtail`

Como el CLAUDE.md que trae swallowtail. Reglas de estructura en el system prompt, para todos los modos (Construir, Revisar y One-shot): componer con escenas guardadas en disco (sin un script que arme todo el árbol en _ready), nodos built-in antes que scripts propios, "call down, signal up", tipado estático, valores ajustables en Resources o data.json y no en constantes, aleatoriedad con semilla (playtests reproducibles), verificar después de cada cambio. Son las mismas reglas de las skills de Godot del usuario. Respetar el CLAUDE.md/AGENTS.md del proyecto si dice otra cosa. Revisar también que la rúbrica de criterios (D40) y la revisión (M5) usen las mismas reglas.

**Prueba:** `tests/unit/test_system_prompt.gd`: las convenciones aparecen en el system prompt de los cuatro modos; Revisar las pide como hallazgos; el criterio Código de la rúbrica (D40) las nombra. Suite unitaria completa en 4.8-beta1: 180 tests, 0 fallos.

**Notas:** Commit eacaaaf (rama swallowtail-tools).
- `config/system_prompt.md`: sección "Godot conventions" (escenas en disco, nodos built-in, call down/signal up, tipado, tunables en exports/Resources/data, RNG con semilla, verificar después de cada cambio). El CLAUDE.md/AGENTS.md del proyecto manda si dice otra cosa.
- Revisar (M5): la regla del modo pide reportar los desvíos como findings (severidad order para estructura, style para tipado).
- D40: el criterio Código y sus anclas 3/6/9 usan las mismas reglas.

### Imágenes en el chat: pegar, arrastrar y capturar el juego · Revisión

**Prioridad:** alta

Pedido del usuario: poder pegar imágenes en el chat del agente, o que saque capturas del juego en ejecución. El agente ya captura con run_scene + capture_game_frame; faltaba que el usuario pudiera adjuntar. Ctrl+V con imagen o archivos copiados, arrastrar archivos del FileSystem, «+ contexto → Captura del juego» (con aviso si el run no tiene el autoload de playtest), hasta 6 imágenes por mensaje achicadas a 1280 px.

**Prueba:** test_composer: rutas de archivos copiados (file:// con %20, absolutas, texto mezclado → se pega como texto) y arrastre real con force_drag (archivos sin carpetas; el texto arrastrado lo sigue insertando el TextEdit). --godot-agent-ui-test=ui_demo: PNG de afuera del proyecto + imagen pegada de 2560 px → dos bloques de imagen, la pegada achicada a 1280 sin tocar la original, y los chips se limpian al enviar. --godot-agent-run-test: Captura del juego desde el dock adjunta el frame rojo del juego; en un run manual avisa que falta el autoload. Matriz 4.6.3/4.7.2/4.8-beta1 verde: run_all 178/1336, acp 117, oneshot 106, 33 UI checks.

**Notas:** Commit 844f3c0. El TextEdit llama al drop del forwarding con cualquier dato (también texto) y después inserta el texto él: _drop_files filtra. Archivos soltados desde el sistema operativo no se manejan: el editor ya los importa al FileSystem, así que alcanza con Ctrl+V o con arrastrarlos desde el FileSystem.

### Soporte para Remote Control de Claude Code desde el dock · Revisión

**Prioridad:** media · **Tamaño:** M · **Etiquetas:** `acp`

Pedido del usuario (2026-10-22): seguir la sesión del dock desde claude.ai/code o la app de Claude en el celular.

**Qué hay en el adapter** (@agentclientprotocol/claude-agent-acp 0.94.0, `dist/acp-agent.js`):
- si el SDK expone `query.enableRemoteControl`, publica el comando `remote-control` en `available_commands_update`;
- intercepta `/remote-control [nombre]` y `/remote-control off` en `session/prompt` (líneas ~2162–2190 y 2281–2303);
- responde en la sesión con «Remote Control is active… <session_url>» o con el error;
- no se puede cambiar a mitad de un turno.

Requisitos de Claude Code (según docs de terceros; verificar en code.claude.com): research preview; planes Pro, Max, Team o Enterprise; login con claude.ai, no API key; sin ANTHROPIC_BASE_URL propio.

**Sin verificar (primer paso):** probar con Claude real desde el dock.
- ¿El comando aparece y anda?
- Un prompt mandado desde el celular, ¿llega al dock como turno sin `session/prompt` del harness? ¿Con `user_message_chunk`? Hoy SessionModel puede no esperar eso.
- Las tool calls y los permisos de esos turnos, ¿llegan como `session/request_permission` al editor? Si es así, alguien tiene que aprobar en la PC (esto se cruza con el modo Auto, m2-09).
- ¿Funcionan `session/cancel` y session/load con Remote Control activo?

**A hacer según lo que salga:**
- botón o entrada de menú «Remote Control» en el dock (además de `/remote-control`);
- indicador de estado (conectado / apagado) y el link clickeable más un QR;
- mostrar los turnos que vienen del remoto, marcados como tales;
- historial;
- que la cuota y el One-shot no se rompan con turnos ajenos;
- la decisión de permisos mientras el usuario no está en la PC.

Documentar en la wiki (en/es) y como decisión.

**Decisiones:**
- ✓ Sin QR: la franja muestra el link con «Copiar link» y el link abre el navegador · revertida
  Por qué: Godot no trae generador de QR; la sesión aparece igual en la lista de sesiones de la app de Claude y en claude.ai/code
  Descartado: QR generado en GDScript (un encoder propio, más código para mantener)
  Qué hacer: QR agregado en m7-25 (rama remote-qr).
- ✓ Empezar un One-shot apaga Remote Control (y en ese modo el botón no aparece)
  Por qué: Los turnos mandados desde el celular no pasan por el run: romperían presupuestos y el conteo de checks
  Descartado: Dejarlo prendido y solo avisar; no dejar empezar el One-shot mientras está prendido
- ✓ Los permisos se contestan de los dos lados; si contesta el celular la tarjeta se cierra como «Contestado en otro lado»
  Por qué: Es como funciona el adaptador ($/cancel_request); la matriz del modo sigue decidiendo lo que no pregunta
  Descartado: Que con Remote Control prendido todo lo que pregunta se conteste solo desde el celular
- ✓ La sesión remota se llama como el proyecto, y el botón «Remoto» va en la línea de estado, no en el encabezado
  Por qué: El nombre del proyecto identifica la sesión en la app; el encabezado ya llena un dock angosto y el botón lo ensanchaba
  Descartado: Nombre fijo («Godot») o pedirlo al prender; botón en el encabezado o en un menú
- ✓ Todo prompt que empieza con /comando va solo, sin contexto del harness ni adjuntos (no solo /remote-control)
  Por qué: Claude Code reconoce un comando solo si es el mensaje entero; con el contexto delante /remote-control fallaba
  Descartado: Tratar aparte solo /remote-control

**Prueba:** Con Claude Code real (probe, antes del arreglo): /remote-control da el link, el celular sigue la sesión (probado por el usuario), y contestar un permiso en el celular manda $/cancel_request. El cierre de la tarjeta con Claude real no se probó; con el agente falso sí. Automático (4.8-beta1 y 4.6.3): test_slash_command; acp_session_check escenario remote_control (comando solo, link en el modelo, permiso retirado con $/cancel_request, contexto en el mensaje siguiente, off, sesión nueva apagada); oneshot_check «Remote Control» (el run lo apaga); --godot-agent-remote-test (botón, franja, tarjeta cerrada, Apagar, sin botón en One-shot, el dock no pasa su mínimo de diseño); i18n.

**Notas:** Commit 2f69910 (rama remote-control), ya en main. D58.

Hallazgos con claude-agent-acp 0.94: los mensajes del celular y las respuestas del agente NO llegan al cliente ACP, así que «mostrar los turnos remotos en el dock» no se puede; la franja lo aclara. Llegan solo las tool calls que piden permiso; lo de solo lectura corre sin tráfico. El permiso es una carrera: si el harness contesta en el momento (matriz, D48, Auto) el celular no pregunta; si hay tarjeta, preguntan los dos y el que contesta primero gana ($/cancel_request).

Sin QR (link + copiar). session/load con Remote Control activo no se probó.

### Remote Control: mostrar en el dock lo que cambió desde el celular · Revisión

**Prioridad:** media · **Tamaño:** M · **Etiquetas:** `acp`

Pedido del usuario (2026-10-22), sale de m7-21. Claude Code no le pasa al cliente ACP los mensajes ni las respuestas de los turnos remotos (D58), así que hoy lo que se hace desde el celular no deja rastro en el dock.

Lo que el editor sí ve: los archivos y escenas que cambian (la sincronización editor ↔ disco) y las tool calls que piden permiso. Mientras Remote Control está prendido, agregar al chat una entrada tipo «Desde el celular: cambió player.gd, main.tscn», con ↶ para deshacer cuando se pueda (undo del editor o checkpoint).

A definir:
- cómo agrupar (por ráfaga de cambios, o por permiso pedido);
- qué pasa con cambios hechos a mano en el editor mientras tanto (no atribuirlos al celular);
- deshacer: archivos fuera del editor vs. escenas abiertas.

Documentar en la wiki (Remote Control) y en D58.

**Decisiones:**
- ✓ Los cambios del celular se detectan mirando los archivos del proyecto (cada 2 s, solo con Remote Control prendido y sin turno del dock), agrupados por tanda en un aviso con «Ver diff» y «Deshacer»
  Por qué: Los turnos remotos no llegan por ACP y las tool calls que corren sin permiso tampoco; los archivos son lo único que se ve siempre
  Descartado: Atribuir cada cambio a una tool call (incompleto); EditorFileSystem (solo escanea cuando el editor recupera el foco); un watcher del sistema operativo (no hay API en Godot)
- ✓ Deshacer guarda el texto solo de archivos de texto de hasta 256 KB (32 MB en total) y mira hasta 5000 archivos; los binarios aparecen en el aviso pero sin Deshacer
  Por qué: Memoria y tiempo de cada vuelta acotados en proyectos grandes; recorrer 750 archivos cada 2 s no se nota
  Descartado: Checkpoint git al prender Remote Control (toca el repo del usuario); copiar también binarios

**Prueba:** test_remote_watch (cambios modificado/creado/borrado sin .godot, .uid ni ignorados; texto de antes; restaurar; rebase y guardado desde el editor; merge de tandas; texto del aviso). --godot-agent-remote-test: con Remote Control prendido se modifica y crea un archivo en tests/tmp, aparece el aviso con los dos, «Ver diff» abre el diff, «Deshacer» los deja como estaban y no genera otro aviso. Suite completa verde en 4.8-beta1 y 4.6.3, i18n incluido. Con Claude real y el celular no se probó (va con m7-24).

**Notas:** Commit 3b0ded6, ya en main (vino de la rama remote-activity). Ver D58 «Actividad del celular». Recorrer este repo (~750 archivos) cada 2 s no se nota. Límite: se compara fecha (segundos) y tamaño.

### La barra de modos no entra en un dock angosto · Revisión

**Prioridad:** media · **Tamaño:** S

Visto en las capturas de m2-09 y m7-21 (2026-10-22): con cinco modos (Preguntar, Revisar, Construir, Auto, One-shot) el último botón queda cortado («One-s…») cuando el dock está en su mínimo de diseño (260 px), y el MinSizeGuard lo recorta. En español los nombres son más largos y empeora.

Opciones: botones que se achican con clip y tooltip, íconos más texto corto, o un selector desplegable cuando no hay lugar. Que el check del editor verifique que la barra no pasa el mínimo del dock (como hace remote_check con la franja), en inglés y en español.

**Decisiones:**
- ✓ El mínimo del dock baja de 260 a 220 px y la barra de modos pasa a ser un HFlowContainer: si no entran, los modos siguen en una segunda línea
  Por qué: El panel del editor por defecto mide 240 px, y con 260 el MinSizeGuard recortaba el último modo, el botón de Settings y Enviar. Cortar palabras («Constr…») se lee peor que dos líneas.
  Descartado: Botones recortados con tooltip; íconos con texto corto; un selector desplegable

**Prueba:** layout_check.gd (nuevo) falla antes del arreglo con el dock en el panel por defecto de 240 px: «el dock pide 260 px», y Settings, One-shot y Enviar quedan fuera del borde, en inglés y en español. Después pasa: corre en --godot-agent-remote-test (con la franja y una tarjeta) y en --godot-agent-i18n-test (español). Suite completa verde en 4.8-beta1 y 4.6.3.

**Notas:** Commit 2f42d86 (rama dock-narrow), ya en main. La causa no era la barra de modos sola: el mínimo de diseño de 260 px del dock no entraba en el panel por defecto de 240, y el MinSizeGuard recortaba 20 px a la derecha (también el «+» del encabezado y Enviar). Bajó a 220 y la barra pasó a HFlowContainer sin clip_text.

### Remote Control: verificar con Claude real el cierre de la tarjeta y session/load · Pendiente

**Prioridad:** media · **Tamaño:** S · **Etiquetas:** `acp`

Pendiente de m7-21 (2026-10-22). El cierre de la tarjeta cuando el permiso se contesta en el celular ($/cancel_request → «Contestado en otro lado») solo se probó con el agente falso; con Claude real se vio que el adaptador manda la notificación, pero eso fue antes del arreglo.

Probar con Claude Code real y el celular:
- un permiso contestado en el celular cierra la tarjeta del dock, y el log de permisos lo registra;
- contestar en el dock cierra el aviso del celular;
- recargar la sesión (historial / session/load) con Remote Control prendido: ¿sigue prendido del lado de Claude? ¿El dock debería mostrar la franja? Hoy una sesión nueva arranca con el link vacío;
- reiniciar el editor con Remote Control prendido.

Anotar lo que salga en D58 y la wiki.

### Remote Control: QR del link en la franja · Revisión

**Prioridad:** media · **Tamaño:** M · **Etiquetas:** `acp`

Pedido del usuario (2026-10-22). Quedó afuera de m7-21 (revierte la decisión «Sin QR»). El usuario: «godot debería ser capaz de generar qr. Se puede usar _draw por ejemplo. O alguna forma de generarlo usando gdscript».

Encoder QR en GDScript (modo byte, corrección M; versiones hasta ~6 alcanzan para un link de claude.ai): datos → Reed-Solomon → matriz con patrones, máscara elegida por penalización. Dibujado con _draw (o una Image/ImageTexture) con zona de silencio, en la franja de Remote Control o en un popup al tocarlo. Test unitario del encoder contra vectores conocidos (matriz de un texto de referencia) y el check del editor de Remote Control.

**Decisiones:**
- ✓ El QR se muestra con un botón «QR» en la franja (oculto por defecto), dibujado con _draw al ancho del dock
  Por qué: Con el QR siempre a la vista la franja ocupa ~250 px de alto en el dock; el link se sigue copiando o abriendo sin él
  Descartado: QR siempre visible; en un popup aparte

**Prueba:** test_qr_code: matriz del link de prueba igual a la de qrencode 4 (misma máscara elegida); versión 7 con bloque de versión y texto UTF-8 igual a qrencode con la máscara 3; límites (versión 1, 213 bytes en la 10, 214 no entra); imagen con zona de silencio. A mano: 11 largos (versiones 1–10) decodificados con zbarimg, 8 idénticos a qrencode y los otros 3 idénticos con la máscara de qrencode (libqrencode calcula la penalización distinto). --godot-agent-remote-test: «QR» muestra el código y la captura del editor se decodifica con zbarimg. Suite completa verde en 4.8-beta1 y 4.6.3, i18n incluido.

**Notas:** Commit 2f5b02e, ya en main (vino de la rama remote-qr). Traducido de la librería de Project Nayuki (MIT); el aviso de copyright está en el encabezado de core/qr_code.gd. Con un celular real no se escaneó.

### Remote Control: franja colapsable · Revisión

**Prioridad:** media · **Tamaño:** S · **Etiquetas:** `acp`

Pedido del usuario (2026-10-23): «Que se pueda colapsar, creo que hay un nodo control colapsable». Con el link, el QR y la aclaración, la franja de Remote Control ocupa mucho alto en el dock. Usar FoldableContainer (Godot 4.5+, el mínimo del addon es 4.6): el título «● Remote Control activo» y los botones a la vista siempre, el resto plegable; recordar el estado.

**Prueba:** --godot-agent-remote-test en 4.8-beta1 y 4.6.3: la franja es un FoldableContainer; plegada, el link no se ve y «Apagar» sí; «QR» la despliega y muestra el código. Capturas plegada y desplegada revisadas. Suite completa verde en las dos versiones, i18n incluido.

**Notas:** Commit b99a386, ya en main (vino de la rama remote-qr). El estado plegado se conserva mientras el editor está abierto (no se guarda entre sesiones: Remote Control arranca apagado en cada sesión nueva). get_title_bar_control no existe en 4.6, así que el código no lo usa.

### Cuota del plan como anillos en la fila del composer y modelo por defecto con nombre · Revisión

**Tamaño:** S

El medidor de cuota (dos barras debajo del estado) quedaba oculto hasta el primer mensaje de cada sesión y parecía haber desaparecido. Pasa a dos anillos chicos al lado del contexto (afuera la ventana de 5 h, adentro la semanal), siempre visibles, con el detalle en el tooltip y grises con el motivo mientras no hay datos. Además, el selector de modelo mostraba «Default (recommended)»: ahora muestra el modelo que usa, «Opus 5.5 (default)».

**Decisiones:**
- ✓ Dos anillos concéntricos (afuera 5 h, adentro semanal) de 16 px, siempre visibles y grises sin datos
  Por qué: Ocupan el lugar de un ícono en la fila del composer; siempre visibles para que no parezca que la cuota desapareció cuando la sesión todavía no la informó.
  Descartado: Dos barras finitas en la fila; un solo círculo con la ventana más llena; seguir ocultándolo sin datos.
- ✓ La opción "default" se muestra como «<modelo> (default)» solo si su descripción coincide con el nombre de otra opción; el nombre original queda en el tooltip
  Por qué: Claude Code pone el modelo en la descripción de "default"; si otro agente usa la descripción para otra cosa, se mantiene su nombre.
  Descartado: Usar siempre la descripción; mostrar el modelo de _claude/model del usage_update (llega recién con el primer turno).

**Prueba:** test_quota_ring (tooltip sin datos, con las dos ventanas y con el límite; colores por umbral) y test_composer.test_model_label. Escenario ui_quota del editor: el anillo se ve y su tooltip trae el detalle. Pasada completa verde en 4.8-beta1 y 4.6.3, incluido i18n. A mano: abrir una sesión de Claude Code, ver los anillos grises y el selector «Opus 5.5 (default)»; después del primer mensaje, los anillos se llenan.

**Notas:** ui/dock/quota_ring.gd reemplaza a quota_meter.gd. Se agrega con Composer.add_status_control antes del medidor de contexto. Se sacó set_usage_hint: el aviso de que el agente no informa la cuota ahora va en el tooltip del anillo. La franja de Remote Control se ubica después de status_row. El nombre del modelo sale de Composer.model_label. Commit 6d83e4e (rama quota-ring), ya en main.

### Capturas del agente: verlas en grande · Revisión

**Prioridad:** media · **Tamaño:** M · **Responsable:** Claude

Las capturas que devuelve el agente (godot.capture_game_frame, screenshots) se ven en el chat a 160 px de alto y no hay forma de agrandarlas. Un clic en la miniatura abre un visor con la imagen ajustada a la ventana, zoom con la rueda, arrastre para moverla, 1:1 / Ajustar y guardar como PNG. Lo mismo para la captura del último playtest en la pantalla One-shot.

**Decisiones:**
- ✓ El visor es una ventana (AcceptDialog) que se abre con un clic en la miniatura, no una ampliación dentro del dock
  Por qué: El dock es angosto: para ver la captura en grande hace falta una ventana. Abre ajustada al 85 % del editor, con zoom, arrastre y Guardar PNG…; las miniaturas siguen a 160 px.
  Descartado: Miniaturas más grandes en el chat; expandir la imagen dentro del dock; abrirla con el visor del sistema (OS.shell_open de un PNG temporal).

**Prueba:** - `--godot-agent-ui-test=ui_markdown` (tests/scripts/ui_markdown.json, agente falso con una captura de `capture_game_frame`): hay una sola miniatura clicable, el clic abre el visor con el tamaño en el título (480×270), y al cerrarlo se libera. Capturas en <shot>_chat.png y <shot>_viewer.png. Pasa en 4.6.3 y 4.8-beta1.
- run_all: 224 tests en 4.6.3, 4.7.2 y 4.8-beta1; cycle test (5 ciclos sin huérfanos) y ui_demo siguen pasando.
- Falta probar a mano (no automatizado): rueda (zoom hacia el puntero), arrastrar, doble clic (Ajustar ↔ 100 %), teclas + − 0 1 y Guardar PNG… (si cae dentro del proyecto, re-escanea el FileSystem).

**Notas:** ui/image_viewer.gd: AcceptDialog que se cuelga del base control del editor y se libera al cerrarse. `ImageViewer.attach(rect, get_image)` vuelve clicable una miniatura (cursor de mano, tooltip); lo usan la tool_group_view (imágenes de tool calls) y la columna "Último playtest" del One-shot. `ImageViewer.open()` lo usa también el dock para los links a imágenes del Markdown (`![alt](ruta)` y links a .png/.jpg/.webp/.svg…).
Ajustar no tiene tope: una captura chica se agranda hasta llenar la ventana; desde 200 % se dibuja sin filtro (píxeles nítidos).
Trabajado en el worktree .claude/worktrees/chat-images-markdown (rama chat-images-markdown) para no recargar el addon bajo el editor abierto.

### Markdown del chat: tablas, listas, bloques de código y más · Revisión

**Prioridad:** media · **Tamaño:** M · **Responsable:** Claude

El conversor de m7-04 cubre lo mínimo pero se ve pobre: las tablas salen como texto mono con los |, las líneas largas de una lista no quedan alineadas bajo el texto, los bloques de código son un fondo detrás de las letras sin forma de copiarlos, los títulos h3–h6 son iguales a negrita, no hay espacio entre párrafos, las URL sueltas no son links y ![img](…) sale como "!" + link. Mejorarlo: tablas reales con encabezado y bordes, listas con sangría colgante ([ul]/[ol]), regla horizontal [hr], URLs sueltas como links, imágenes como link que abre el visor, bloques de código en el chat como caja a todo el ancho con lenguaje, botón copiar y resaltado de GDScript.

**Decisiones:**
- ✓ En el chat, los bloques de código son un control aparte (caja con lenguaje y copiar), no BBCode dentro del mismo RichTextLabel
  Por qué: Una tabla de RichTextLabel no llega a todo el ancho y no hay forma de poner un botón de copiar adentro. Costo: no se puede seleccionar de corrido texto y código a la vez.
  Descartado: Todo en un solo RichTextLabel con el código en una tabla de una celda (es lo que queda para la pantalla One-shot y los thoughts).
- ✓ Las URL sueltas (https://…) pasan a ser links; antes quedaban como texto
  Por qué: Es lo que hace GFM y lo que espera quien lee el chat; los guiones bajos de la URL no se toman como itálica y la puntuación final queda afuera.
  Descartado: Dejarlas como texto (el test de m7-04 lo pedía así; se cambió).
- ✓ Tareas de lista con ▣ / □ en lugar de ☑ / ☐
  Por qué: Con la fuente del editor, ☑ salía como emoji de color y ☐ diminuto; ▣ y □ son de la misma familia y se ven parejos.
  Descartado: ☑/☐ (lo de antes), ✓/○.

**Prueba:** - run_all -- markdown: test_markdown_bbcode, 12 tests y 107 checks (tablas con alineación, | escapado y dentro de code, filas cortas/largas; listas anidadas, sueltas, perezosas y numeración que sigue después de un bloque de código; blocks(); resaltado de GDScript/shader; URLs sueltas con puntuación y paréntesis; imágenes; link_target con #L, :línea y file://; tags balanceados).
- Suite completa: 224 tests en 4.6.3, 4.7.2 y 4.8-beta1.
- `--godot-agent-ui-test=ui_markdown`: el mensaje queda en un solo recuadro con el bloque de código en su caja; capturas revisadas (título, links, lista con sangría colgante, código resaltado con copiar, tabla, tareas, cita, regla). Pasa en 4.6.3 y 4.8-beta1. ui_demo y el cycle test siguen pasando.

**Notas:** - markdown_bbcode.gd: `blocks()` parte el texto en `{bbcode}` y `{code, language}`; `convert()` los junta (el código en una tabla de una celda con fondo) para la pantalla One-shot y los thoughts.
- Cada ítem de lista es su propio `[ul bullet=<marca>]`: la marca es el número del texto, así una lista cortada por un bloque de código sigue en 3 y las líneas largas quedan alineadas. Anidado por sangría real (pila de sangrías), lista suelta con [br] para los párrafos del ítem.
- Tablas: `[table]` con encabezado en negrita sobre fondo, bordes, padding y [center]/[right] por columna; también sin | en los bordes (GFM).
- Respiro entre bloques separados por una línea en blanco: una línea con un espacio a 45 % del tamaño.
- code_bbcode.gd (no CodeHighlighter: choca con la clase nativa): resaltado por línea con los colores del Script Editor (Editor Settings), GDScript y shaders con keywords y tipos (ClassDB para los del motor), el resto solo strings/números/comentarios.
- code_block_view.gd: caja del chat con lenguaje, botón copiar (ActionCopy) y RichTextLabel mono seleccionable. agent_message_view reusa los controles por posición en el streaming.
- El dock: `MarkdownBBCode.link_target()` entiende `ruta#L42`, `ruta:42[:col]` y file://; los links a imágenes abren el visor de m7-28.
- [hr], [br], [ul bullet=], padding de celdas y [right] en celdas probados en 4.6.3.
- Se mantuvo el recuadro de fondo del RichTextLabel del editor (como antes), ahora uno solo por mensaje, con los tramos de texto sin fondo adentro.

### El agente no abre Godot en una ventana desde la shell · Revisión

**Prioridad:** alta · **Tamaño:** S · **Responsable:** Claude · **Etiquetas:** `bug`

Reporte del usuario (little-villages): para sacar capturas de 4 semillas, el agente escribió /tmp/shoot_seeds.gd y lo corrió con `timeout 90 "$GODOT" --path . --script …` sin --headless (headless no dibuja). Se abrió el juego en una ventana aparte, gris, en vez de correrlo desde el editor. Rechazar sin tarjeta (como D48) los comandos que lanzan Godot sin --headless, y que el system prompt diga cómo sacar capturas: run_scene + game_call/game_set para preparar la situación + capture_game_frame.

**Decisiones:**
- ✓ Godot sin --headless por la shell se rechaza solo, en todo modo, aunque el usuario lo hubiera permitido con la tarjeta
  Por qué: En el reporte, el usuario aprobó el comando sin ver que abría una ventana. La alternativa del editor (run_scene + capture_game_frame) existe y es la que se quiere; mismo criterio que las escrituras de D48.
  Descartado: Solo la instrucción en el system prompt; mostrar la tarjeta con una advertencia; rechazarlo solo en Auto/One-shot.

**Prueba:** - test_godot_window_guard (3 tests, 14 checks): el comando de la captura (`timeout 90 "$GODOT" --path . --script /tmp/shoot_seeds.gd …`) se rechaza; también godot del PATH, el binario del editor, ${GODOT}, binarios descargados y prefijos (timeout -k, env, VAR=). Pasan --headless, --display-driver headless, --version, --export-*, xvfb-run, y godot como argumento o dentro de un string.
- Suite completa: 227 tests en 4.6.3, 4.7.2 y 4.8-beta1.
- Falta: probarlo con Claude Code real pidiéndole capturas de varias semillas (que use run_scene + game_call + capture_game_frame).

**Notas:** session/godot_window_guard.gd: `windowed_launch(command, godot_bin)` parte el comando por ; && || | y saltos, saca prefijos (timeout con opciones y duración, env, VAR=…, nice -n, time, sudo…) y mira si el primer word es Godot ($GODOT, ${GODOT}, el binario del editor, godot*, Godot_v*) sin un flag que evite la ventana.
SessionController lo aplica después del guard de D48: rechazo sin tarjeta, en todo modo, con aviso en el chat. Mismo límite que D48: si las reglas `allow` de Claude Code dejan pasar el comando, no hay pedido de permiso y solo queda el system prompt.
System prompt: `$GODOT` siempre con --headless, y para ver el juego o sacar capturas (también de variantes, como semillas) run_scene + game_call/game_set/game_input + game_wait + capture_game_frame, nunca un script que renderice.

### Prueba: hablar con Claude Code en stream-json desde GDScript, sin claude-agent-acp · Pendiente

**Prioridad:** baja · **Tamaño:** M

Hoy Claude Code se usa a través de `npx -y @agentclientprotocol/claude-agent-acp`, lo que obliga a tener Node. Claude Code tiene un modo sin interfaz (`claude -p --input-format stream-json --output-format stream-json --verbose --include-partial-messages --mcp-config … --permission-prompt-tool mcp__godot__permission`) y, con el instalador nativo, es un binario autónomo. Prueba corta: lanzarlo desde GDScript, mandar un prompt que use una tool godot.* y una que pida permiso, y registrar qué eventos llegan (texto en streaming, tool calls y resultados, uso, rate limit, resultado) con la versión instalada. Con eso decidir si vale un segundo transporte solo para Claude (ACP queda para Gemini CLI y Codex). Revisar qué se pierde del adapter: cambio de modo y modelo, cancelar, --resume, imágenes, login, /remote-control, _meta de subagentes.

### Modo (Preguntar/Revisar/Construir/Auto/One-shot) como dropdown al lado del selector de modelo · Revisión

**Prioridad:** media · **Tamaño:** S · **Responsable:** Claude

Pedido del usuario: los cinco botones de modo ocupan dos filas arriba del dock. Pasarlos a un dropdown en la fila del composer, al lado del selector de modelo, para ganar lugar en la conversación.

**Prueba:** - --godot-agent-auto-test: Auto está en el selector justo después de Construir, con tooltip, y elegirlo pasa a modo Auto.
- --godot-agent-remote-test: elegir One-shot en el selector esconde Remote Control.
- --godot-agent-i18n-test (es): el dock entra en el panel (LayoutCheck) y el selector se ve.
- ui_demo: captura revisada, ya no está la fila de botones y «Construir ▾» va en la fila del composer.
- run_all: 227 tests (4.7.2).

**Notas:** Composer: `_mode_button` (OptionButton plano, en el color de acento) antes del selector de modelo; `set_modes([{id,label,tooltip}])`, `set_current_mode(id)` (el tooltip del botón dice el modo actual) y `choose_mode(id)` para las pruebas. Se guardan hasta que el composer arma sus controles. Dock: sin el HFlowContainer ModeBar (también fuera del .tscn); `_build_mode_selector()` y `_refresh_modes()` van por el composer.

### Cola de mensajes: «Enviar ahora» · Revisión

**Prioridad:** media · **Tamaño:** S · **Responsable:** Claude

Pedido del usuario: un mensaje en la cola (escrito mientras el agente trabaja) espera a que termine el turno. Agregar «Enviar ahora» en cada mensaje encolado: corta el turno en curso (session/cancel) y lo manda enseguida, sin perder el resto de la cola.

**Prueba:** - test_prompt_queue: move_to_front, y en la vista el ➤ de cada fila avisa su índice, sigue a set_send_available y no saca el prompt (lo hace el dock).
- --godot-agent-queue-test, segunda fase (tests/scripts/queue_now.json): con un turno largo corriendo y "uno", "dos" en cola, ➤ en "dos" corta el turno (no llega el resto del texto largo), "dos" sale enseguida, "uno" queda en la cola sin pausa y sale después.
- La primera fase (cancelar pausa la cola; «Enviar ahora» del encabezado) sigue pasando.

**Notas:** PromptQueueView: botón ➤ en cada fila (antes de editar y quitar) con la señal send_item_now_requested(index). Dock `_send_queued_now(index)`: pasa el prompt al frente, saca la pausa y, si el agente trabaja, marca `_interrupt_for_queue` y cancela; `_on_turn_finished` ve la marca y manda el siguiente aunque el turno haya terminado con cancelled. Sin turno en curso lo manda directo.

### Extensiones: panel de MCP servers (los del addon y los del agente) · Revisión

**Prioridad:** alta · **Tamaño:** L · **Etiquetas:** `ui`, `mcp`

El usuario quiere manejar MCP, skills y plugins desde el editor como en Claude Code (pedido 2026-10-23, ejemplo: el MCP de Blender).

Hoy: el addon solo pasa su server godot en session/new; claude-agent-acp además carga los de la config de Claude Code (settingSources user/project/local: ~/.claude.json, .mcp.json), pero el addon no los muestra ni los maneja, y sus tools caen en el grupo Other (ask en todos los modos, One-shot se frena).

Hacer:
- Pestaña Extensions en Settings → MCP: lista de servers propios del addon (stdio con command/args/env, o http con url/headers), por proyecto (res://, versionable) y globales (EditorSettings / user://). Se pasan en mcpServers de session/new y session/load, así sirven para cualquier agente ACP (Claude, Gemini, Codex).
- Ver también los que el agente carga solo: en Claude, el estado que da `/mcp` del adaptador (conectado, falló, deshabilitado), con Reconectar y Habilitar/Deshabilitar (`/mcp reconnect|enable|disable <server>`).
- Importar desde .mcp.json / ~/.claude.json y "Agregar a Claude Code" (claude mcp add-json, scope project o user) como opción.
- Secretos (tokens en headers/env) fuera del repo: en user:// y agregados a AgentLog.add_secret.
- Al cambiar la lista, se aplica en la próxima sesión (o reinicia la sesión con aviso).

**Decisiones:**
- ✓ Los MCP se configuran en el addon y se pasan por ACP; skills y plugins usan los archivos de Claude Code, no un formato propio
  Por qué: mcpServers es parte de ACP, así que un MCP configurado en el addon sirve para Claude, Gemini y Codex. Skills y plugins existen solo en Claude Code: duplicar su formato implicaría mantener dos copias que se desincronizan con la CLI.
  Descartado: Que el addon edite directamente ~/.claude.json o .mcp.json también para MCP (queda atado a Claude). Un formato propio de skills y plugins para todos los agentes (Gemini y Codex no los soportan).

**Prueba:** Unit (234 tests en 4.6.3, 4.7.2 y 4.8-beta1): test_external_mcp_servers (to_acp stdio/http, $VAR/${VAR}, validación, merge, import de .mcp.json, nombres, página de Settings). Xvfb: --godot-agent-settings-shots (en y es) importa un server, la matriz suma la fila mcp:blender, guardar escribe project_config.tres y external_mcp_names. Contra claude-agent-acp 0.95.0 real con un server stdio de prueba: la tool llega como mcp__pingsrv__ping (title y _meta.claudeCode.toolName), el env llega al server.

**Notas:** Hecho: mcp/external_mcp_servers.gd (formato, validación, to_acp, secret_values, from_mcp_json), ui/settings/mcp_servers_page.gd arriba en Settings → Servidores MCP, project_config.mcp_servers y EditorSettings mcp/servers; plugin._mcp_servers agrega los habilitados (HTTP queda afuera con aviso si el agente no lo soporta). No hecho: ver el estado de los servers que el agente carga solo (el SDK tiene mcpServerStatus pero ACP no lo expone; queda el hint de /mcp) ni "Agregar a Claude Code" (claude mcp add-json).

**Relacionadas:** Permisos por server MCP externo en la matriz

### Permisos por server MCP externo en la matriz · Revisión

**Prioridad:** alta · **Tamaño:** M · **Etiquetas:** `mcp`, `permisos`

Las tools `mcp__<server>__*` que no son de godot caen en el grupo Other (PermissionPolicy.matrix_value devuelve ask para grupos sin DEFAULTS), en todos los modos: el One-shot se frena esperando.

Hacer: un grupo por server (mcp:blender) con valores por modo editables en Settings (por defecto ask; sugerir allow para tools read-only si el server marca readOnlyHint), "Permitir siempre este server" desde la tarjeta de permiso, y que el One-shot avise antes de arrancar si hay servers en ask. En el chat, mostrar el nombre corto (blender.get_objects_summary) como con godot.* (tool_call.gd, tool_group_view.gd, run_report.gd).

**Decisiones:**
- ✓ Los servers MCP de terceros arrancan en Preguntar en todos los modos, incluidos Auto y One-shot
  Por qué: Un server de terceros puede hacer cualquier cosa (borrar en Blender, escribir en una base), y el harness no sabe qué hacen sus tools. Se permite explícitamente por server y modo, desde Settings o desde la tarjeta.
  Descartado: Permitir en Auto y One-shot como las tools de edición; usar readOnlyHint para permitir las de solo lectura (el adaptador no lo manda en el pedido de permiso).

**Prueba:** acp_session_check escenario "MCP servers de terceros": tarjeta por server con nombre corto, «Permitir siempre en el proyecto» guarda allow en Construir y la segunda tool de blender pasa sin tarjeta, db sigue preguntando, mcp_servers_not_allowed para el aviso del One-shot. Unit test_policy_groups_per_server. Xvfb auto/remote/cycle/oneshot/i18n en verde.

**Notas:** Grupo mcp:<server> sacado del prefijo mcp__<server>__ (title o _meta.claudeCode.toolName); ask por defecto en todos los modos, overrides en la matriz. La tarjeta suma un botón «Permitir siempre «x» en modo M, en este proyecto» (persist_label/persist_allow → permissions_changed → plugin guarda la config). One-shot: activity warning al arrancar. No se usó readOnlyHint (el adaptador no lo manda en el permiso).

**Relacionadas:** Extensiones: panel de MCP servers (los del addon y los del agente)

### Extensiones: skills (listar, crear, activar, skills de Godot incluidas) · Revisión

**Prioridad:** media · **Tamaño:** M · **Etiquetas:** `ui`

Skills de Claude Code = carpetas con SKILL.md en ~/.claude/skills (usuario) y <proyecto>/.claude/skills (proyecto); los plugins también traen skills. claude-agent-acp las carga (settingSources) y el SDK acepta `skills` (lista o 'all') por `_meta.claudeCode.options` en session/new.

Hacer: en Extensions → Skills, lista con origen (usuario, proyecto, plugin), descripción del frontmatter y activar/desactivar por proyecto (options.skills); crear una skill nueva (plantilla SKILL.md abierta en el editor de scripts), importar una carpeta o zip, y copiar de usuario a proyecto. Evaluar incluir skills de Godot con el addon (convenciones, tests headless) en vez de meter todo en el system prompt.

Otros agentes: Gemini y Codex no tienen skills; para ellos ocultar la sección o (decidir) inyectar la descripción en el system prompt.

**Decisiones:**
- ✓ Apagar skills por proyecto con skillOverrides "off" en las settings de la sesión, no con options.skills; las skills de plugins no tienen interruptor (van con su plugin)
  Por qué: Probado contra Claude Code real: la lista de options.skills no ocultó nada, y una lista blanca escondería las skills que trae Claude Code. skillOverrides oculta la skill del modelo y del menú /, pero el CLI no lo aplica a skills de plugins.
  Descartado: options.skills con todas menos las apagadas; escribir skillOverrides en .claude/settings.local.json
- ✓ Las skills de Godot no vienen dentro del addon: la pestaña sugiere el marketplace godot-agent y lo instala con un clic
  Por qué: Viven en dannroda/godot-agent-plugins (m7-40), se actualizan solas por plugin y sirven fuera del harness; meterlas en el addon las duplicaría y engordaría el zip.
  Descartado: Copiarlas en addons/godot_agent y pasarlas por el system prompt o por .claude/skills del proyecto
- ✓ El SKILL.md se abre con la app del sistema (OS.shell_open), no en el editor de scripts; con Gemini o Codex la pestaña solo dice que las skills son de Claude Code
  Por qué: .claude/ es una carpeta oculta que el FileSystem de Godot no ve, y las skills de usuario están fuera del proyecto, así que el editor de scripts no las puede abrir. Inyectar descripciones en el prompt de otros agentes sumaría contexto sin la carga bajo demanda que hace útiles a las skills.
  Descartado: Abrir el archivo en el Script Editor; inyectar las descripciones en el system prompt de otros agentes

**Prueba:** Unit: tests/unit/test_skill_catalog.gd (frontmatter, scan con plugins declarados por el marketplace, settings de sesión, crear/copiar, importar carpeta y zip); 269 tests en 4.6.3, 4.7.2 y 4.8-beta1. UI: tests/skills_check.sh (copia del proyecto, CLAUDE_CONFIG_DIR de prueba) en las tres versiones; i18n es, cycle, ui remote, settings. Real: tests/skills_session_check.gd -- godot-patterns contra Claude Code: con la skill apagada el menú baja de 120 a 119 comandos, el modelo ya no la nombra y los 63 comandos propios de Claude Code siguen.

**Notas:** Commit d5f5ece (worktree-skills-tab), en main desde el 2026-10-27: había quedado sin mergear y la v0.1.6 salió sin m7-36, m7-43 ni m7-44. Pestaña Skills en Extensions (ui/extensions/skills_tab.gd) sobre extensions/skill_catalog.gd, que lee del disco las skills del proyecto (.claude/skills), del usuario (<CLAUDE_CONFIG_DIR>/skills) y de los plugins (installed_plugins.json + plugin.json o la entrada del marketplace con `skills`, para los strict:false como awesome-gamedev). Apagar una skill guarda su nombre en ProjectConfig.disabled_skills y la sesión manda `_meta.claudeCode.options.settings.skillOverrides {nombre: "off"}` en session/new y session/load (SessionController.session_meta_provider). Hallazgos con Claude Code 2.1.310 / claude-agent-acp 0.95: `options.skills` (lista) no ocultó nada; skillOverrides sí oculta skills de usuario/proyecto del modelo y del menú /, pero no se aplica a skills de plugins (el CLI solo los mira para skills sincronizadas): esas van con su plugin. Crear (plantilla, abre el SKILL.md con la app del sistema), importar carpeta o zip, copiar de usuario a proyecto, borrar (a la papelera). Tarjeta que sugiere el marketplace godot-agent (m7-40) e instala gdscript y shaders.

### Extensiones: plugins de Claude Code (marketplaces, instalar, habilitar) · Revisión

**Prioridad:** media · **Tamaño:** M · **Etiquetas:** `ui`

Plugins de Claude Code: se instalan desde marketplaces y se habilitan en settings (enabledPlugins); traen skills, comandos, agentes, hooks y MCP. claude-agent-acp los carga de la config del usuario, y el SDK acepta `plugins: [{type: "local", path}]` por `_meta.claudeCode.options`.

Hacer: en Extensions → Plugins, lista de instalados con estado y lo que trae (`claude plugin details`), Habilitar/Deshabilitar (por proyecto o usuario), agregar marketplace e instalar (por el CLI `claude plugin ...`, que puede no estar instalado aparte del adaptador: detectarlo y explicar), y cargar un plugin local de una carpeta del proyecto (options.plugins). Después de cambiar, recargar en la sesión abierta (el SDK tiene reload_plugins) o reiniciarla con aviso. Solo Claude Code; para otros agentes la sección dice que no aplica.

**Prueba:** Unit test_claude_extensions (parseo de mcp list, plugin list, acciones --json, scopes de config, cwd por sh, ventana sin CLI) en 4.6.3, 4.7.2 y 4.8-beta1. tests/extensions_cli_check.gd contra el CLI real con CLAUDE_CONFIG_DIR temporal: agrega un marketplace local, instala, deshabilita, desinstala, quita (12 checks; la config del usuario quedó con el mismo md5). Xvfb --godot-agent-extensions-shots (en y es): abre desde el dock con la config real, 9 instalados, 3912 disponibles, 2 marketplaces, 12 MCP con estado.

**Notas:** extensions/claude_cli.gd (busca claude o el del SDK en la cache de npx; corre con AgentProcess vía sh -c cd), extensions/claude_extensions.gd (parseo estático + acciones), ui/extensions/extensions_window.gd. Botón ExtensionsButton en el header del dock. No se recarga en la sesión abierta (ACP no expone reload_plugins): franja con «Nueva sesión». Cuidado: `claude plugin enable` de un id inexistente lo agrega a enabledPlugins sin fallar; la ventana solo ofrece enable para instalados. No probado: Autenticar (claude mcp login abre el navegador) ni un install que pide aceptar el comando del marketplace (el formato de shownCommand se supuso).

### Updater: buscar e instalar versiones nuevas del addon desde el editor · Revisión

**Prioridad:** media · **Tamaño:** M · **Etiquetas:** `ui`

Pedido del usuario (2026-10-23): un updater.

- Chequeo: GitHub API releases/latest de dannroda/godot-agent (HTTPRequest, sin token) al abrir el editor (una vez por día como máximo, se puede apagar en Settings) y con un botón «Buscar actualizaciones»; compara el tag con plugin.cfg (AddonVersion). Pre-releases solo si se pide.
- Aviso en el dock: «Versión X disponible» con las notas del release (Markdown del CHANGELOG) y «Actualizar».
- Actualizar: baja el zip del asset, lo extrae (ZIPReader) a user:// y lo valida (plugin.cfg con la versión esperada). Después reemplaza addons/godot_agent conservando config/project_config.tres y los config/*.md|txt que el usuario cambió, y pide reiniciar el editor (EditorInterface.restart_editor). Reemplazar scripts del addon con el plugin cargado puede tirar el editor (D35, hot reload): deshabilitar el plugin antes de escribir, o escribir y reiniciar enseguida. Hay que probar cuál es seguro.
- No ofrecerlo si el addon es un checkout de git o un symlink (desarrollo): ahí se actualiza con git.

**Prueba:** Unit: tests/unit/test_addon_updater.gd (versiones, elección del release, extracción y validación de un zip armado con ZIPPacker, install con borrado/respaldo/KEEP, copia de dev); 246 tests verdes en 4.6.3, 4.7.2 y 4.8-beta1. UI: --godot-agent-update-shots= (aviso debajo del de export, notas en Markdown, Settings → Buscar ahora dice copia de desarrollo, «Después» guarda la versión), en en y es; ciclo del plugin y settings shots pasan. E2E real: sandbox con el addon copiado marcado 0.1.0 + Godot self-contained (._sc_) + plugin sonda en Xvfb propio: encontró v0.1.3 en GitHub, bajó el zip (sigue el redirect), lo instaló, respaldó system_prompt.md editado, conservó project_config.tres, borró addon_updater.gd (0.1.3 no lo trae), reinició y el plugin quedó habilitado en 0.1.3.

**Notas:** Commit 6bc34fc (worktree-updater), ya en main. core/addon_updater.gd (Node con HTTPRequest; API /releases?per_page=10, elige el más nuevo no-draft con .zip; pre-releases no). ui/dock/update_banner.gd vía dock.add_banner(). Settings → Interfaz → Actualizaciones (check al abrir, una vez por día; Buscar ahora). Instalar: confirm → download a user://godot_agent/update → validar versión de plugin.cfg → save_all_scenes, controller.stop → install → restart_editor(false) sin awaits entre escribir y reiniciar. Solo borra archivos obsoletos de tipos del release (gd, uid, tscn, po, cfg, md, txt). Copia de dev (symlink o godot_agent_dev) no se actualiza. Canal de log nuevo "update". Ojo: quien tenga 0.1.3 o anterior tiene que instalar a mano la primera versión que traiga el updater. Sin probar: Windows/macOS, y Authenticate de GitHub con rate limit (60 req/h sin token: una búsqueda por día alcanza).

### Asset Library de Godot: buscar, sugerir, instalar y activar plugins · Revisión

**Prioridad:** media · **Tamaño:** L

Pedido del usuario (2026-10-23): que el harness pueda buscar en la Asset Library de Godot (godotengine.org/asset-library/api: /asset?filter=&category=&godot_version=, /asset/<id> con download_url y download_hash), sugerir plugins según lo que se está haciendo, instalarlos (bajar el zip, extraer addons/<x>/ con ZIPReader, verificar el hash) y activarlos (EditorInterface.set_plugin_enabled). Dos caras: una pestaña "Godot assets" en la ventana Extensions (buscar, ver, instalar, activar/desactivar los addons del proyecto) y tools MCP godot.asset_search / godot.asset_install con permiso propio (instalar baja código de terceros: pedir siempre). Reusa la descarga y extracción del updater (m7-38).

**Decisiones:**
- ✓ Store nuevo (store.godotengine.org) en vez de la Asset Library clásica; Instalar escribe por defecto solo addons/ y nunca pisa archivos
  Por qué: El editor de Godot ya solo usa el store nuevo (la URL clásica no está en el código de master), y su API trae releases por versión de Godot. Los zips traen demos, README y hasta project.godot: instalar solo addons/ evita ensuciar el proyecto; no pisar sigue al instalador del editor.
  Descartado: Asset Library clásica (godotengine.org/asset-library/api); instalar todo el zip como el editor; sobrescribir para poder actualizar
- ✓ asset_install tiene un grupo de permisos propio («Install from the Asset Store»: Preguntar en Construir, Auto y One-shot); plugin_enable va en el grupo project
  Por qué: Instalar baja código de terceros: se pide confirmación siempre, pero como grupo de la matriz se puede cambiar en Settings si alguien lo quiere en Permitir. El evaluador del One-shot lo tiene denegado.
  Descartado: Dentro del grupo project con una excepción fija de «siempre preguntar»

**Prueba:** tests/asset_check.sh <godot> (con red, copia del proyecto): busca, instala Simple TODO con el diálogo y queda activo; las tools lo listan, lo apagan/prenden, no dejan apagar el harness y reinstalar no pisa nada. Pasa en 4.6.3, 4.7.2 y 4.8-beta1. Unit: test_asset_store, test_asset_tools.

**Notas:** Commit 20df5e3 en worktree-asset-store. API del store nuevo (la del editor en master; la clásica ya no está en el código de Godot): search/query/?query=&require_release=true&type=0&sort=&compatibility=4.7.2&page=N (24 por página, hits[].asset), assets/<pub>/<slug>/, releases/<pub>/<slug>/ (download_url firmado, vence a los 10 min: se pide justo antes de bajar). price_cent > 0 = pago, no se instala. Para activar un plugin recién instalado hay que esperar a que el editor importe (dest_files de los .import) y registre los uids; si no, preload("uid://…") falla. Tools en la lista extendida (godot.methods/run); el system prompt pide buscar addons antes de escribir sistemas grandes. Helpers de UI de Extensions movidos a extensions_ui.gd.

### Marketplace propio (repo) con las skills, tools y plugins de Godot · Revisión

**Prioridad:** baja · **Tamaño:** M

Pedido del usuario (2026-10-23, «para después»): un repo que sea un marketplace de Claude Code (.claude-plugin/marketplace.json) con las skills, tools (MCP) y demás que se usan para Godot, para que las skills que se creen vayan ahí. El harness lo puede ofrecer como marketplace sugerido en la ventana Extensions (m7-37) y en la pestaña de skills (m7-36).

**Decisiones:**
- ✓ Dos plugins por tema (gdscript con 5 skills, shaders con 1), con los nombres de las skills sin cambiar
  Por qué: Las 5 de GDScript se citan entre sí, así que separadas quedarían referencias rotas; las de shaders son independientes. Con los nombres iguales, las referencias cruzadas y los hábitos siguen andando.
  Descartado: Un plugin por skill (6); un solo plugin con todo
- ✓ Las skills básicas de awesome-gamedev-agent-skills se recomiendan en el README, no se copian
  Por qué: Son de otro autor (Apache 2.0) y se actualizan en su propio marketplace; las nuestras van más allá de lo básico y las nombran con su origen.
  Descartado: Copiarlas al repo con su NOTICE
- ✓ El marketplace lista godot, disciplines, genres y workflows de awesome-gamedev-agent-skills apuntando a su repo (sin router), generados con scripts/sync_upstream.py
  Por qué: Pedido del usuario: instalar las de awesome-gamedev desde nuestro marketplace. Apuntar a su repo evita copiar código Apache 2.0 y trae sus actualizaciones (la versión es su commit). router queda afuera porque enruta a skills de otros motores que no se instalan.
  Descartado: Copiarlas al repo con NOTICE; fijarlas a un commit; incluir router y los motores no Godot

**Prueba:** claude plugin validate --strict en el marketplace y cada plugin; CI del repo verde; claude plugin list muestra gdscript@godot-agent y shaders@godot-agent habilitados.

**Notas:** Publicado en https://github.com/dannroda/godot-agent-plugins (CI verde). Marketplace "godot-agent" con dos plugins: gdscript (godot-architecture, godot-communication, godot-patterns, godot-data-driven, godot-code-review) y shaders (godot-shader-techniques), copiados de las skills del usuario sin rutas locales a los PDFs; los libros quedan citados por título/capítulo/página. Chequeo de texto literal contra ambos libros (ventanas de 12 palabras): solo esqueletos de código genéricos. claude plugin validate --strict pasa. Instalados en el perfil personal desde GitHub (gdscript@godot-agent y shaders@godot-agent). Mover las skills locales godot-* a skills/.trash lo bloqueó el permiso automático: lo hace el usuario. Queda para m7-36/m7-37: sugerir el marketplace desde Extensions y la pestaña de skills.

### Guía con imágenes para el README (y la wiki) · Revisión

**Prioridad:** media · **Tamaño:** M · **Etiquetas:** `docs`

Pedido del usuario (2026-10-23): una guía con capturas, al menos para el README. Capturas reales del editor (Xvfb, plugin de dev con agente falso para que no dependa de una cuenta): dock con una conversación, tarjeta de permiso, modos, Review con marcas en el Script Editor, pantalla One-shot, Settings, Extensions, aviso de update. Van a docs/images/ y se regeneran con un flag del plugin de dev.

**Prueba:** tests/docs_shots.sh <godot> en|es: copia limpia del proyecto + Godot self-contained con el idioma del editor; --godot-agent-docs-shots= saca overview, chat, permission, review y settings sin fallas en los dos idiomas. Revisadas a ojo: sin rutas del usuario, sin contenido de tests, sin recortes. Unit 246 verdes, ui_markdown y ciclo del plugin pasan.

**Notas:** Commits 8d0647a (LICENSE MIT a nombre de Daniel Rodriguez Aires, CONTRIBUTING.md, LICENSE en el zip del release) y 94ca4f4 (guía), ya en main (en worktree-docs-guide eran 6cf8931 y 06cd486). README «Quick start» con capturas en en/es (docs/images/<lang>/, .gdignore). Escena demo tests/docs_demo/ (con 2 bugs a propósito para Review), escenarios docs_build(_es)/docs_review(_es). El dock se ensancha a 480 px moviendo split_offsets del DockHSplitMain (un offset por divisor entre hijos visibles). Arreglado de paso: el botón «Thinking» no recortaba su texto y ensanchaba el chat más que el dock. Pendiente aparte: m7-42 (fila del composer más ancha que el dock por defecto). Descripción y topics de GitHub puestos con gh repo edit. Sin captura del One-shot (su check usa contenido de test en español).

### El composer no entra en el dock con el ancho por defecto (sesión abierta) · Revisión

**Prioridad:** alta · **Tamaño:** S · **Etiquetas:** `ui`

Encontrado armando las capturas (m7-41): con una sesión abierta, la fila de abajo del composer (@, imagen, /, anillo de cuota, uso «38k / 200k» 90 px, modo 66, modelo 67, Enviar 63) pide 418 px; el dock por defecto mide ~289 px en 1920x1200, así que el modelo y Enviar quedan cortados (el dock se recorta en su guard). layout_check no lo ve porque mide sin sesión (sin uso ni modelo). Opciones: pasar el uso al tooltip del anillo o acortarlo, OptionButtons con clip_text, o una segunda fila cuando no entra. Agregar a layout_check el caso con sesión. (El botón «Thinking» que ensanchaba el chat ya se arregló en m7-41.)

**Decisiones:**
- ✓ La fila se compacta por niveles (Enviar solo con símbolo, después sin uso, /, @ y captura, y por último el modelo con «…») en vez de pasar a dos filas
  Por qué: Mantiene el composer en una sola fila y no le quita alto al chat. Lo que se esconde tiene otro acceso: el anillo de contexto y su tooltip, escribir / o @, y Ctrl+V para la imagen.
  Descartado: Una segunda fila cuando no entra; mover el uso al tooltip del anillo siempre; clip_text siempre en los OptionButtons

**Prueba:** GODOT_AGENT_LANGUAGE=es tests/run_in_xvfb.sh godot --godot-agent-i18n-test (LayoutCheck.composer_fits: dock de 240 px con uso, modelo y modo, libre y ocupado); pasa en 4.6.3, 4.7.2 y 4.8-beta1. Docs shots a 480 px muestran la fila completa.

**Notas:** Commit 8e8aada, ya en main (vino de worktree-composer-width). composer.gd _fit_row(): calcula el ancho visible (row.size.x menos lo que el contenido del dock se pasa del MinSizeGuard) y sube el nivel de compactación hasta que entra: 1 Enviar/Detener solo símbolo, 2 sin medidor, 3 sin /, 4 sin @, 5 sin captura, 6 modelo con clip + «…» y expand (spacer oculto). Anchos medidos independientes del nivel actual (fuente para Enviar y modelo) para no oscilar. Ojo: con text_overrun_behavior != NO_TRIMMING el Button no cuenta el texto en su mínimo, por eso el overrun se pone solo en el nivel 6.

### Subagentes: ver lo que hacen y setting para permitirlos y limitarlos · Revisión

**Prioridad:** media · **Tamaño:** M

Pedido del usuario (2026-10-23, para después): que se vea lo que hacen los subagentes (hoy el chat agrupa las tools con parentToolUseId bajo la tarjeta del Agent/Task, pero hay que revisar si se ve su progreso en vivo, su prompt y su reporte, y cuántos corren a la vez) y una setting para permitir/denegar el uso de subagentes y la cantidad permitida (por modo; tool Agent/Task de Claude Code: negarla por permiso, contar los que están en curso y rechazar los que pasen el límite).

**Decisiones:**
- ✓ Seguir los subagentes con la forma nativa de ACP (clientCapabilities.subagents) en vez de limitar con la variable CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS
  Por qué: Solo la forma nativa informa cuándo termina un subagente en segundo plano, y da su sesión para mostrar sus tools en la tarjeta. La variable de entorno se fija al arrancar el proceso y no puede cambiar por modo durante la sesión.
  Descartado: Variable de entorno de Claude Code; contar por el estado del tool call de Agent (falla con los de segundo plano)
- ✓ Subagentes permitidos en todos los modos por defecto, sin límite (0)
  Por qué: Así se comportaba antes; el límite y la denegación se activan desde Ajustes → Permisos.
  Descartado: Denegar en Ask/Review; límite por defecto (p. ej. 3)

**Prueba:** Unit: tests/unit/test_subagents.gd (grupo, límite, modo, sesiones nativas, pedido de permiso del hijo); 276 tests en 4.6.3/4.7.2/4.8. Real (gasta tokens): godot --headless --path . --script tests/subagents_session_check.gd → PASS (uno permitido, otro rechazado por límite 1 en Build, estados running→idle, su Read dentro de la tarjeta). UI: settings shots, i18n es, cycle y skills_check pasan.

**Notas:** Commit 9ae15c6 (worktree-skills-tab). Grupo de permisos "subagents" (Agent/Task, por defecto Allow en todo modo) y "Subagentes a la vez" por modo (project_config.subagent_limits, 0 = sin límite). La sesión manda settings permissions.ask ["Agent"] en _meta, así cada lanzamiento llega como session/request_permission. Hallazgo: los subagentes pueden correr en segundo plano y el tool call de Agent termina enseguida, así que contar por estado del tool call no sirve. El cliente ahora declara clientCapabilities.subagents {} (RFD de ACP): claude-agent-acp anuncia cada hijo con subagent_update (running/requires_action/idle), liga la sesión hija al tool call con un session_message (messageId = id del lanzamiento), y los updates y pedidos de permiso del hijo llegan con su sessionId. SessionModel.apply_child_update los manda a la tarjeta del lanzamiento; ToolCall.subagent_state/is_working() decide si corre. Sin ese informe (otros agentes) se cuenta como antes, por el tool call.

### Varias sesiones abiertas a la vez que se coordinan entre sí · Revisión

**Prioridad:** media · **Tamaño:** L

Pedido del usuario (2026-10-23, para después): poder tener múltiples sesiones de agente abiertas en el editor, coordinadas para no pisarse (archivos y escenas en edición, el juego corriendo, checkpoints). Investigar cómo lo hace el plugin «backstitch» pero local, y la funcionalidad de Claude Code para que sesiones se comuniquen entre sí (mensajes entre sesiones locales). Decidir: locks por archivo/escena en el harness, cola para run_game, un canal compartido; y cómo se ve en el dock (pestañas por sesión).

**Decisiones:**
- ✓ Lock per file for the length of the owning session's turn, enforced (rejection with the owner's name), instead of advisory claims or worktrees
  Por qué: The harness already sees every write (edit permission, fs/write, godot.* tools), so enforcing costs nothing and doesn't depend on the agent obeying. Releasing at the end of the turn avoids stale locks without timers. There's only one live editor, so a worktree per agent doesn't fit (merging .tscn is painful).
  Descartado: Advisory claims via a tool with TTL; a permission card for the user; worktree/branch per session; CRDT like backstitch
- ✓ Channel between sessions as its own godot.* tools (sessions, session_send) and not Claude Code's SendMessage
  Por qué: claude-agent-acp doesn't bring cross-session messages to the client, and ACP has nothing between sibling sessions; with our own tools it works with any agent and the message is visible in the chat of the session that receives it (it arrives as a queued prompt).
  Descartado: Claude Code's SendMessage/ListAgents with crossSessionInbound accept; a shared notes file
- ✓ Tab bar always visible (Session 1 + «+»), One-shot / Review / Remote Control only in the first session
  Por qué: The «+» in the tab bar is distinguishable from the header's «+» (new conversation) and is discoverable; the One-shot, review annotations and Remote Control are tied to a single session in the plugin, and moving them to N sessions would be another task.
  Descartado: Hide the row with a single session and put the button in the header; One-shot in any tab

**Prueba:** Unit: tests/unit/test_sessions.gd (claims, game queue, registry guard and caller, controller file guard, session tools) and test_mcp_server.test_session_tokens; 283 tests. Editor: tests/run_in_xvfb.sh godot --godot-agent-sessions-test=<prefix> → PASS (opens a second tab, its own token, s2 can't touch a file s1 copied, godot.sessions shows it, it frees up at the end of the turn, closing revokes the token). cycle, i18n, queue, auto, review, oneshot, login, remote, edit, sync, run, mcp and external all pass.

**Notas:** Commit 59f352c (worktree-skills-tab). Research: backstitch (inkandswitch) is real-time version control with Automerge (CRDT), not agent coordination. What carries over is the visual diff idea. Claude Code has cross-session messaging (ListAgents/SendMessage over a Unix socket), but claude-agent-acp 0.95 doesn't bring it to the client, and ACP has nothing for messages between sibling sessions. Implemented: SessionTabs (one AgentDock per session, + opens another, close only on the extras); the first one (PRIMARY_SESSION "s1") keeps One-shot, Review annotations and Remote Control. plugin._make_controller wires each session: its own FsHandler, its own MCP token (McpServer.session_token; registry.call_tool gets the caller; session_authorizer uses that session's controller). SessionCoordinator: per-turn file claims (released on turn_finished or on close), enforced in controller.file_guard (edit permission + fs/write) and in registry.guard (godot.* tools in edit_scene/edit_files/project, paths res:// from args or the open scene); the game belongs to whoever launched it while it runs, run_scene from another session waits up to 90 s, game_*/stop/capture of someone else's game are rejected. godot.sessions / godot.session_send (extended, via godot.run) to see the others and send a message that arrives as a queued prompt. Not done: a real run with two Claude agents at once (token routing tested over HTTP and the guard in the editor); checkpoints are still per One-shot (primary session only).

### Asset Store: detectar y aplicar actualizaciones de plugins · Revisión

**Prioridad:** media · **Tamaño:** M

Pedido del usuario (2026-10-24): «Agrega también el poder detectar updates de plugins», sobre m7-39. Detectar versiones nuevas en el Asset Store de los plugins del proyecto (instalados desde el harness o a mano) y poder actualizarlos desde la pestaña y desde las tools del agente.

**Decisiones:**
- ✓ Las instalaciones se anotan en res://.godot_agent/assets.json (versionable) y los plugins instalados a mano se buscan en el store por nombre; actualizar reemplaza la carpeta del addon
  Por qué: plugin.cfg no dice de qué asset vino ni todos los autores suben la versión ahí; el archivo en el proyecto lo comparte el equipo y el export lo saltea. Reemplazar la carpeta es lo que hace falta para actualizar (el instalador nunca pisa); se avisa que se pierden los cambios locales.
  Descartado: Guardar la anotación en user:// (por máquina); solo detectar sin actualizar; chequear actualizaciones al abrir el editor como el updater del addon

**Prueba:** tests/asset_check.sh <godot> (red, copia del proyecto): tras instalar, el resultado dice «Installed»; con la versión anotada vuelta a v0.1 la pestaña ofrece «Update to 1.6», el diálogo dice qué reemplaza y borra, actualizar deja el plugin activo, borra el archivo viejo y anota la versión; sin anotación y con plugin.cfg 0.1, addons_list check_updates lo encuentra por nombre. Pasa en 4.6.3, 4.7.2 y 4.8-beta1. Unit: test_asset_store (plan con replace, stale, manifest, match_asset, installed_assets), test_asset_tools (FakeStore).

**Notas:** Commit ab6a502 en worktree-asset-updates. Anotación en res://.godot_agent/assets.json: {asset_id: {version, folders, files}}. Instalados a mano: search(plugin.name) y match por nombre simplificado o slug == carpeta; sin versión en plugin.cfg no se compara. Actualizar: plan_install con replace=carpetas de addons/ del zip, stale = anotados que ya no vienen (sin anotación no se borra nada), plugins activos se apagan antes de escribir y se prenden después. PROTECTED_FOLDERS pasó a AssetStore.

### Asset Store: una actualización no pisa al harness ni a otros plugins · Revisión

**Prioridad:** alta · **Tamaño:** S · **Etiquetas:** `bug`

Revisión de m7-39/m7-45: con update=true, plan_install reemplaza todas las carpetas addons/* que trae el zip nuevo (addon_folders(plan)), no las anotadas para ese asset; un zip que trae addons/godot_agent u otro plugin los pisa. PROTECTED_FOLDERS no se mira al instalar (una instalación nueva puede agregar archivos dentro de addons/godot_agent).

**Decisiones:**
- ✓ Los archivos del zip dentro de addons/godot_agent(_dev) se saltean en silencio, sin listarlos como conflicto
  Por qué: Listarlos como conflicto metería la carpeta del harness en las carpetas anotadas del asset (installed_assets lo daría por instalado); un zip que trae el harness es un caso raro
  Descartado: Listarlos como conflicto u «otros»; rechazar el zip entero

**Prueba:** Unit: test_asset_store (run_all -- asset: 17 tests, 94 checks, 0 fallos en 4.7.2). Casos: zip con addons/godot_agent no lo planea; anotado con otra carpeta deja los archivos existentes como conflicto.

**Notas:** plan_install saltea todo lo de addons/<PROTECTED_FOLDERS> del zip (como las rutas con ..). Nuevo replace_folders(entry, plan): una actualización pisa solo las carpetas anotadas del asset; sin anotación (instalado a mano), las de addons/ del zip. prepare() devuelve replace y la pestaña lo reusa al tildar «incluir otros archivos».

### Asset Store: una actualización que falla vuelve a activar sus plugins · Revisión

**Prioridad:** alta · **Tamaño:** S · **Etiquetas:** `bug`

Revisión de m7-45: finish() apaga los plugins activos antes de escribir y, si install() falla (disco lleno, archivo de solo lectura), vuelve sin prenderlos: el plugin queda apagado y a medio reemplazar.

**Prueba:** Necesita el editor (EditorInterface); no tiene test propio. Revisado leyendo el código; asset_check.sh no cubre una escritura fallida.

**Notas:** finish(): si install() falla, vuelve a activar los plugins que apagó (was_enabled) antes de devolver el error. Los archivos quedan a medio reemplazar, como antes.

### Asset Store: un campo null del store no rompe la búsqueda · Revisión

**Prioridad:** media · **Tamaño:** S · **Etiquetas:** `bug`

Revisión de m7-39: int(null) es error de script en Godot 4 (probado en 4.7.2) y get(key, 0) devuelve null si la clave viene con null. Un hit con reviews_score o price_cent null corta search() (pestaña y agente); lo mismo size en compatible_releases.

**Prueba:** Unit: test_asset_store (run_all -- asset: 17 tests, 94 checks, 0 fallos en 4.7.2). Fixture con reviews_score y price_cent null, y una release con size null.

**Notas:** parse_hits (score, price_cent) y compatible_releases (size) usan int(str(…)) / float(str(…)), como ya hacía parse_details con price_cent: str(null) da 0.

### Asset Store: zip temporal propio por descarga · Revisión

**Prioridad:** baja · **Tamaño:** S · **Etiquetas:** `bug`

Revisión de m7-39: el zip se llama solo por asset_id; si el agente instala el mismo asset mientras el diálogo de la pestaña está abierto, pisa el zip y lo borra, y la pestaña falla con «not a valid zip».

**Prueba:** Sin test: cambio de nombre de archivo; asset_check.sh lo ejercita al instalar.

**Notas:** download(): el zip se llama <asset>_<ticks_usec>.zip. Se sigue borrando al terminar o cancelar.

### Asset Store: apagar el harness durante una instalación no rompe _scan · Revisión

**Prioridad:** baja · **Tamaño:** S · **Etiquetas:** `bug`

Revisión de m7-39: plugin.gd saca el AssetStore del árbol al apagarse; _scan sigue esperando get_tree().process_frame y get_tree() es null: error a mitad de finish(), con los archivos escritos y sin anotar en el manifest.

**Prueba:** Script de prueba: un Node que hace await process_frame, remove_child + queue_free → no imprime ni da error.

**Notas:** Sin cambios: la revisión se equivocó. Probado en 4.7.2: si el nodo se libera durante un await, Godot no reanuda la corrutina (sin error), así que _scan nunca llega a get_tree() null. Apagar el harness a mitad de una instalación la abandona: archivos escritos, sin anotar en el manifest; aceptable al apagar el plugin.

### Dock: mostrar con qué cuenta está logueada cada sesión; «+» de pestañas más grande · Revisión

**Prioridad:** media · **Tamaño:** S

Pedido del usuario (2026-10-27): «en ningún lado estamos mostrando qué cuenta está logueada en la sesión» y «el + para abrir una sesión paralela es muy chiquito».

**Decisiones:**
- ! La cuenta va en la línea de estado del dock («● Claude Code · ready · email»), con organización y plan en su tooltip · sin revisar
  Por qué: Es la línea que ya nombra el agente de cada sesión, existe en cada pestaña y recorta con «…» en un dock angosto
  Descartado: Una etiqueta propia en el header; solo en el tooltip de la cuota; en la pantalla del One-shot
- ! El «+» de pestañas usa el mismo ícono Add que «Nueva conversación» del header · sin revisar
  Por qué: Con el mismo tamaño se ve como el resto de los íconos; se distingue por estar en la fila de pestañas (como en un navegador) y por su tooltip
  Descartado: Texto «+» más grande (el glifo igual queda chico); otro ícono del editor

**Prueba:** Unit: test_claude_extensions.test_parse_auth_status (claude.ai, API key sin email, sin sesión, salida no JSON, tooltip); suite 284 tests (falla solo test_api_tools.test_search, previa). Editor: --godot-agent-sessions-test pasa y la captura muestra el «+» del tamaño de los íconos del header. auth_status() contra el CLI real devuelve las cuatro claves. No probado: la línea de estado con Claude real en el editor (el agente falso no es Claude).

**Notas:** ClaudeCli.auth_status() corre `claude auth status --json` (Claude Code 2.1.311) con el entorno del perfil (su CLAUDE_CONFIG_DIR) y parse_auth_status() devuelve {email, org, plan, method}. SessionController._refresh_account() lo pide al quedar lista la sesión (session/new y session/load), solo si ClaudeExtensions.is_claude_profile(); queda en SessionModel.account (no lo borra reset(): es del proceso) con la señal account_changed. El dock suma «· email» a la línea de estado y el tooltip dice cuenta, organización (salvo la «<email>'s Organization» de una cuenta personal) y plan. El Agent Log anota método y plan, sin el email. De paso: el StatusLabel tenía mouse_filter IGNORE (default de Label), así que su tooltip (error, subagentes) nunca se veía. «+» de pestañas: ícono Add del editor en un botón de 28 px; con texto «+» salía de unos 8 px.

### Mensajes entre sesiones: el recibido no se ve y una sesión nueva no los lee hasta su primer prompt · Revisión

**Prioridad:** alta · **Tamaño:** S · **Etiquetas:** `bug`

Pedido del usuario (2026-10-27): «a una sesión nueva, si no le mando un primer mensaje, no aparecen los mensajes… si se lo envía otra sesión no se muestra» y «no aparece en el log/chat el mensaje recibido, solo que envía».

**Decisiones:**
- ! No se oculta SendMessage/ListAgents de Claude Code: el system prompt orienta a godot.session_send y el chat avisa cuando llega trabajo sin su mensaje · sin revisar
  Por qué: Denegar las tools nativas rompería la coordinación con sesiones de Claude fuera del editor (terminal, otros proyectos); el aviso también cubre tareas en segundo plano que terminan
  Descartado: Reglas deny para SendMessage en las settings de la sesión; godot.session_send como tool del núcleo (no extendida)

**Prueba:** Unit: test_sessions.test_notice_for_work_outside_a_turn (aviso una vez, subagente no cuenta, Remote Control sin aviso, dentro de un turno sin aviso); suite 285/0; acp_session_check 159/0. No probado con dos Claude reales: que el agente elija godot.session_send después del cambio de prompt.

**Notas:** Causa (historial de LittleVillages b52301ca y 9bc88f39, claude-agent-acp 0.98): los agentes usaban SendMessage/ListAgents de Claude Code, no godot.session_send. (1) El adaptador solo reenvía mensajes de usuario de otros clientes si origin.kind == human (isRemoteHumanMessage, para Remote Control); el de otra sesión se descarta, así que el chat ve la respuesta del turno que Claude arranca solo, sin la pregunta. (2) Antes del primer session/prompt la sesión del SDK no corre y no lee su bandeja: el mensaje se procesa recién con el primer prompt. Ninguno se arregla del lado del harness. Hecho: el system prompt dice que con otras sesiones del editor se usen godot.sessions/godot.session_send (entra como prompt, se ve en el chat y sirve sin primer prompt); SessionController._notice_outside_turn() avisa una vez por tanda cuando llega trabajo del agente fuera de un turno pedido (sin user_message_chunk antes, sin parentToolUseId), y se rearma con cada prompt.

**Relacionadas:** Soporte para Antigravity CLI (agy) como agente

### Renombrar las sesiones (pestañas del dock) · Revisión

**Prioridad:** media · **Tamaño:** S

Pedido del usuario (2026-10-27): «poder nombrar las sesiones. Así no serían simplemente "Session n" y uno podría saber qué hacen».

**Decisiones:**
- ! Se renombra con doble clic sobre la pestaña (campo flotante debajo), sin menú contextual · sin revisar
  Por qué: Es el gesto habitual para renombrar pestañas y no ocupa lugar en un dock angosto; el tooltip de la pestaña lo dice
  Descartado: Clic derecho con menú; un botón de lápiz; que el agente le ponga nombre solo
- ! Ícono de Extensions: EditorPlugin (pieza de rompecabezas a color) · sin revisar
  Por qué: Llena el cuadro como el resto de los íconos y es el de Project Settings → Plugins; AssetLib dibuja una figura diminuta
  Descartado: Un ícono gris de otro tipo; texto «Ext»

**Prueba:** Editor: --godot-agent-sessions-test pasa con el caso nuevo (abre el campo con el nombre actual, aplica «  Level design » recortado a pestaña, coordinador y godot.sessions, rechaza «session 1», vacío vuelve a «Session 2»). Suite completa e i18n en verde.

**Notas:** SessionTabs: doble clic en una pestaña abre un PopupPanel con un LineEdit (máx. 40) debajo de ella; Enter emite rename_requested(id, nombre). plugin._rename_session lo aplica al coordinador (godot.sessions, session_send, los rechazos «being edited by») y a la pestaña; vacío vuelve a «Session N». Un nombre repetido (sin distinguir mayúsculas) se rechaza con aviso en el chat de esa sesión, porque session_send busca por nombre; al abrir otra pestaña, «Session N» saltea los que ya usa alguna renombrada. Los nombres no se guardan entre reinicios del editor (las pestañas extra tampoco). Aparte, pedido en el mismo rato: el botón Extensions pasó del ícono AssetLib (diminuto) a EditorPlugin, que es a color (pieza naranja).

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

## M9 — Ideas de otros harness  (21/21, 21 en revisión)

Lo que vale la pena traer de Claude Code, Codex, Antigravity, Copilot y Cursor, adaptado a Godot: deshacer y revisar por turno, sesiones que avisan, verificación automática, chat en línea en el Script Editor, artefactos del juego, más contexto y trabajo en segundo plano.

**Hecho cuando:**
- Cada idea quedó hecha o descartada con su motivo en la tarjeta.

### Checkpoints y «volver a antes de este mensaje» en cada turno · Revisión

**Prioridad:** alta · **Tamaño:** M · **Etiquetas:** `idea`

Idea de la comparación con otros harness (2026-10-27). Como /rewind de Claude Code o volver a un mensaje en Cursor/Copilot. Hoy hay checkpoints de git solo en One-shot y deshacer por tool godot.*. Snapshot del proyecto al empezar cada turno de Construir/Auto (refs de git, sin ramas ni commits en la rama del usuario) y acción «volver a antes de este mensaje» en el chat. Reusar oneshot/git_checkpoints.gd.

**Decisiones:**
- ! Snapshots como commits sueltos con un index propio, no git stash ni ramas · sin revisar
  Por qué: stash create no incluye archivos sin trackear y stash push toca el árbol con el editor abierto; ramas o commits ensuciarían el historial del usuario. Las refs propias no se ven en git log ni en las ramas
  Descartado: git stash create; una rama por sesión; copiar los archivos a user://
- ! Prendido por defecto y solo en Construir y Auto · sin revisar
  Por qué: Es invisible (refs fuera de las ramas) y es lo que más ayuda al deshacer; en Preguntar y Revisar el agente no edita y One-shot tiene sus checkpoints
  Descartado: Apagado por defecto; también en One-shot

**Prueba:** Unit: test_turn_snapshots (parse_diff; repo temporal: qué captura, diff A/M/D sin ignorados, volver un archivo, volver todo, deshacer la vuelta, HEAD e index del usuario intactos, refs; aviso de fin de turno con acciones y sin aviso si no hubo cambios); suite completa en verde. Editor: auto-test, edit-test y cycle-test pasan; el turno de auto-test dejó sus dos snapshots con el cambio real (project_config.tres). No probado a mano: los botones del aviso y el diálogo en el editor.

**Notas:** session/turn_snapshots.gd: snapshot = commit suelto de la carpeta del proyecto armado con un index propio (copia del real, por GIT_INDEX_FILE vía env o cmd /c set en un Thread; OS.execute no recibe entorno): add -A, write-tree, commit-tree -p HEAD, update-ref refs/godot-agent/turns/<sesión>/<ms>, se guardan 60 por sesión. Respeta .gitignore; diff y restore excluyen .godot/ y .godot_agent/. restore(sesión, sha, paths) toma un snapshot de ahora, restaura con git restore --source --worktree (no toca el index) y borra lo que se creó después; devuelve {changed, before} para deshacerlo. SessionController: snapshot al empezar cada turno de Construir/Auto (no comandos /), y al terminar _report_turn_changes() deja un aviso «Este turno cambió N archivos (+a −r): …» con «Ver cambios» y «Volver a antes de este turno» (data {session, start, end, files}). Plugin: TurnSnapshots compartido (setup() mira git), confirmación antes de volver todo, recarga lo abierto, aviso «Vuelto atrás» con «Deshacer» y note_for_agent() para el próximo prompt. Ajuste turn_snapshots (true) en Settings → Servidores MCP. No se reporta en turnos que terminan con error.

**Bloquea a:** Revisar los cambios del turno: diff y descartar por archivo

**Relacionadas:** Tareas en segundo plano en un worktree con Godot headless

### Revisar los cambios del turno: diff y descartar por archivo · Revisión

**Prioridad:** alta · **Tamaño:** M · **Etiquetas:** `idea`

Idea de la comparación con otros harness (2026-10-27). Como Keep/Undo por archivo de Copilot o el diff como artefacto de Antigravity. Al pie de cada turno: «N archivos cambiados · ver diff · descartar». Reusar la lista de cambios y el DiffDialog del One-shot. Se apoya en los checkpoints por turno.

**Prueba:** Ver m11-01. La UI del diálogo no tiene check propio en el editor.

**Notas:** ui/turn_changes_dialog.gd: lista de archivos del turno (estado +/~/−, ruta, +a −r) con «Diff» (DiffDialog: antes del turno vs. ahora) y «Volver atrás» por archivo (TurnSnapshots.restore con esa ruta; queda «Vuelto atrás»). Se abre desde el aviso de fin de turno (ver m11-01).

**Bloqueada por:** Checkpoints y «volver a antes de este mensaje» en cada turno

### Avisar cuando una sesión en segundo plano necesita al usuario · Revisión

**Prioridad:** alta · **Tamaño:** S · **Etiquetas:** `idea`

Idea de la comparación con otros harness (2026-10-27). Como el Agent Manager de Antigravity. Con varias pestañas, un pedido de permiso en una que no está a la vista pasa desapercibido. Marcar la pestaña («⚠ nombre»), notificación del editor y, si hace falta, un resumen de las sesiones.

**Prueba:** Editor: --godot-agent-sessions-test con el caso nuevo (permiso en la segunda con la primera al frente → «⚠ », se va al cancelarlo); captura revisada. El toast no se verifica en el check.

**Notas:** SessionTabs: la pestaña muestra «⚠ nombre» mientras SessionModel.pending_permissions no está vacío (pesa más que «●» trabajando); se refresca al pedir y al resolver cada permiso. Si el dock de esa sesión no está a la vista (otra pestaña o el dock tapado), EditorToaster muestra ««nombre» espera tu permiso.». No hice un panel de resumen de sesiones: godot.sessions y las pestañas alcanzan por ahora.

### Verificación automática al terminar cada turno · Revisión

**Prioridad:** alta · **Tamaño:** S · **Etiquetas:** `idea`

Idea de la comparación con otros harness (2026-10-27). Como los hooks de Claude Code o los tests que corren Codex y Copilot. Al terminar un turno de Construir/Auto, correr godot.validate_scripts y get_errors; si hay errores nuevos, devolvérselos al agente (otro turno, con tope) o mostrarlos. Configurable por proyecto.

**Decisiones:**
- ! La verificación solo usa validate_scripts (errores de parseo), no get_errors · sin revisar
  Por qué: get_errors mezcla errores del juego que el agente pudo provocar a propósito al probar; los de parseo son inequívocos y baratos de corregir
  Descartado: Sumar los errores del editor desde la marca del inicio del turno
- ! Hasta 2 turnos de corrección seguidos y prendida por defecto · sin revisar
  Por qué: Corrige lo común sin quedar en loop; el usuario la puede apagar por proyecto
  Descartado: Solo avisar sin devolverle los errores al agente; apagada por defecto

**Prueba:** Unit: test_diagnostic_tools.test_scripts_modified_since (filtro por mtime, carpetas ocultas y .gdignore, failure_lines) y test_turn_check_sends_fix_or_notice (manda la corrección, con tope queda aviso, en Preguntar no verifica); suite 287/0; acp_session_check 159/0. No probado con Claude real en el editor.

**Notas:** SessionController._verify_turn(): después de un turno con end_turn en Construir o Auto (no en comandos con /), llama a turn_verifier(inicio del turno). El plugin lo conecta a DiagnosticTools.verify_changed_scripts(): recorre res:// en disco (no el EditorFileSystem, que puede no tener todavía lo que el agente creó por shell; saltea carpetas ocultas y con .gdignore), valida con el checker en otro proceso los .gd con mtime >= inicio del turno y devuelve las líneas «✗ ruta» + errores. Si hay errores y la sesión está READY, manda un prompt «[Automatic check after your turn]…» con aviso en el chat, hasta MAX_FIX_TURNS = 2 seguidos (se reinicia con cada prompt del usuario); si no (tope, la cola del dock ya mandó otro prompt), deja los errores como aviso. Ajuste del proyecto verify_after_turn (true), en Settings → Servidores MCP. Solo errores de parseo: get_errors queda afuera para no devolver errores del juego que el agente provocó a propósito.

### Chat en línea en el Script Editor (seleccionar y pedir) · Revisión

**Prioridad:** media · **Tamaño:** L · **Etiquetas:** `idea`

Idea de la comparación con otros harness (2026-10-27). Como Ctrl+I de Copilot o Cmd+K de Cursor: seleccionar código, escribir el pedido y ver el cambio como diff en el mismo editor, para aceptar o rechazar. Puente entre el dock y el completado (M8). Después: sugerencias del próximo cambio relacionado (next edit suggestions de Copilot).

**Decisiones:**
- ! El pedido va a la sesión activa del dock (queda en el chat) en vez de una sesión aparte · sin revisar
  Por qué: Reusa la conexión, el modo y los permisos que ya hay y deja rastro de lo pedido; una sesión propia costaría otro agente corriendo
  Descartado: Una sesión oculta solo para el chat en línea; una llamada directa a un LLM como el completado
- ! Atajo Alt+I · sin revisar
  Por qué: Ctrl+I ya es Indentar en el Script Editor; Alt+\ es el pedido manual del completado
  Descartado: Ctrl+Shift+I; solo el menú contextual

**Prueba:** Unit: test_inline_edit (extract_code, build_prompt con y sin selección, apply sobre un CodeEdit con deshacer en un paso, rechazo si el código cambió, inserción en el caret, Alt+I); suite 296/0. Editor: cycle-test y edit-test pasan con el menú registrado (el crecimiento de objetos varía entre corridas: 1–33, también sin esta feature). No probado: el flujo completo con un agente real.

**Notas:** editor/inline_edit.gd (Node del plugin): Alt+I en el CodeEdit activo (Ctrl+I ya es Indentar) y editor/inline_edit_menu.gd (EditorContextMenuPlugin en CONTEXT_SLOT_SCRIPT_EDITOR_CODE) abren un LineEdit junto al caret. El pedido va con build_prompt (archivo, líneas, código seleccionado; pide solo el código nuevo en un bloque y no editar archivos) a la sesión de la pestaña activa por plugin._ask_inline (send_prompt + agent_text_since; error si no hay sesión o está ocupada). extract_code toma el primer bloque; la propuesta se ve con DiffDialog.diff_bbcode (sacado del DiffDialog) en un PopupPanel con Aceptar/Rechazar. apply() verifica que el rango siga igual y reemplaza en begin/end_complex_operation (un Ctrl+Z, sin guardar). Pedido y respuesta quedan en el chat. No hecho: sugerencias del próximo cambio (next edit suggestions); queda como idea.

### Artefactos de verificación: capturas y GIF del juego · Revisión

**Prioridad:** media · **Tamaño:** M · **Etiquetas:** `idea`

Idea de la comparación con otros harness (2026-10-27). Como los walkthroughs de Antigravity. Al cerrar una tarea, un resumen con capturas del juego de antes y después o un GIF del playtest, para mirar o compartir. Ya existen capture_game_frame y game_input; falta juntarlos. Diferencial: ningún otro harness muestra el juego corriendo.

**Decisiones:**
- ! Reporte como carpeta con report.md y PNG, sin GIF · sin revisar
  Por qué: Godot no escribe GIF ni WebP animado sin código extra; las capturas que el agente ya toma son lo que verifica el trabajo, y un .md con imágenes se lee en GitHub o en cualquier visor
  Descartado: Escribir un GIF a mano (LZW); grabar video con Movie Maker

**Prueba:** Unit: test_turn_report (collect solo del turno, write con resumen, archivos y la captura byte a byte); test_turn_snapshots estable en 3 corridas; suite completa en verde.

**Notas:** session/turn_report.gd: collect(model, first_entry) junta el texto del agente y las imágenes (base64 + mimeType) de los tool calls del turno; write() escribe res://.godot_agent/reports/<fecha>/report.md (resumen, archivos con +/−, capturas) y capture-N.png/jpg/webp tal como llegaron. El aviso de fin de turno de Construir/Auto (SessionController._report_turn_changes) suma «N capturas del juego o del editor» y la acción «Guardar reporte» (ACTION_TURN_REPORT); el plugin escribe el reporte y abre la carpeta. Sin git aparece igual si hubo capturas. No hecho: GIF o video del playtest (Godot no escribe GIF ni WebP animado; queda la secuencia de capturas). De paso, turn_snapshots: el index propio se arma una vez con read-tree HEAD y se reusa (copiar el del usuario le cambiaba la fecha y git podía no ver un cambio del mismo tamaño en el mismo segundo; lo agarró el test).

### Instrucciones del proyecto: editar AGENTS.md/CLAUDE.md y generarlas · Revisión

**Prioridad:** media · **Tamaño:** M · **Etiquetas:** `idea`

Idea de la comparación con otros harness (2026-10-27). Como las reglas de Cursor, las custom instructions de Copilot o /init de Claude Code. Panel para ver y editar AGENTS.md/CLAUDE.md del proyecto y un «generar convenciones» que analice autoloads, capas de colisión, estructura de carpetas y estilo de los scripts.

**Decisiones:**
- ! Los datos del proyecto los arma el harness, sin el agente · sin revisar
  Por qué: Son datos que se leen sin pensar (ProjectSettings y carpetas), no gastan tokens y se pueden regenerar; las convenciones de estilo se le pueden pedir al agente en el chat
  Descartado: Pedirle al agente que analice el proyecto y escriba el archivo (como /init)

**Prueba:** Unit: test_project_facts (sección con todos los datos y sin ui_* ni capas sin nombre; merge en archivo vacío, al final y reemplazando una vez); test_claude_extensions ahora cuenta 6 pestañas; suite 299/0. Editor: --godot-agent-extensions-shots pasa y la captura de la pestaña se ve bien.

**Notas:** ui/extensions/instructions_tab.gd: pestaña «Instructions» de Extensions con CLAUDE.md, AGENTS.md y GEMINI.md del proyecto (quién lee cada uno, «(nuevo)» si no existe), un TextEdit y Guardar; cambiar de archivo guarda el que se editaba. core/project_facts.gd: section() arma «## Project facts» entre <!-- godot-agent:project-facts --> … <!-- /… --> con versión de Godot, nombre, escena principal, autoloads, capas con nombre (física, render, navegación, avoidance), acciones de input sin ui_* y carpetas de primer nivel (sin ocultas ni .gdignore); merge() la reemplaza o la agrega al final sin tocar el resto. No hecho: que el agente analice el estilo del código y proponga convenciones (se puede pedir en el chat; la sección generada no gasta tokens).

### Más contexto con @: errores, output, juego y docs · Revisión

**Prioridad:** media · **Tamaño:** S · **Etiquetas:** `idea`

Idea de la comparación con otros harness (2026-10-27). @errors, @output, @game (árbol del juego en marcha), @docs Clase (referencia de la API) y arrastrar un nodo del Scene Tree al composer. Revisar primero qué menciones existen.

**Prueba:** Unit: test_mentions (detección sin repetir y con la clase, sin falsos positivos, opciones del menú; run_for_user sin permiso y con tool inexistente); suite 301/0. Editor: queue-test y auto-test pasan con el envío nuevo. No probado a mano: arrastrar nodos ni el texto de @game con un juego corriendo.

**Notas:** agent_dock: SPECIAL_MENTIONS (@errors, @output, @game, @docs:Clase) van primero en el menú de @ y, al enviar (también lo que sale de la cola), special_mentions_in() las encuentra (sin mails ni nodos parecidos) y _send_with_mentions() agrega un bloque de texto por cada una con lo que trae context_provider. plugin._context_for_mention usa ToolRegistry.run_for_user() (nuevo: corre la tool sin permiso ni guard, porque la pide el usuario; con el tope de max_output_chars): get_errors desde 0, game_tree y class_info; @output son los últimos 4000 caracteres del panel Output (ErrorCollector.output_text). composer: arrastrar nodos del dock Escena escribe @ruta relativa a la escena. Las menciones de nodos y archivos de antes siguen siendo solo texto.

### Tareas en segundo plano en un worktree con Godot headless · Revisión

**Prioridad:** baja · **Tamaño:** L · **Etiquetas:** `idea`

Idea de la comparación con otros harness (2026-10-27). Como las cloud tasks de Codex o el coding agent de Copilot. Una sesión trabaja en otra copia del proyecto con su propio Godot headless y entrega un diff o una rama para integrar, sin competir con el editor abierto. Choca con «el harness nunca mergea»: decidir cómo se integra.

**Decisiones:**
- ! Aplicar los cambios de la copia con git apply como cambios sin commitear, no con merge · sin revisar
  Por qué: El harness no mergea por diseño; así el usuario revisa y commitea él, y si algo no entra limpio la rama queda para resolverlo a mano
  Descartado: git merge de la rama; cherry-pick del commit
- ! La copia va al lado del repo (<repo>.godot-agent-copies/), desde el último commit · sin revisar
  Por qué: Dentro del proyecto Godot la importaría como parte del juego; un worktree solo parte de un commit, así que lo sin commitear no está (se avisa)
  Descartado: Dentro del proyecto con .gdignore; copiar también los cambios sin commitear

**Prueba:** Unit: test_worktree_session (repo temporal con el proyecto en una subcarpeta: crea la copia al lado, el proyecto no cambia mientras el agente trabaja, commit_changes lista lo cambiado, apply_to_project deja los cambios sin commitear en la misma rama, remove borra copia y rama); suite 302/0. Editor: --godot-agent-sessions-test abre una copia de este repo, verifica cwd, que una tool de edición se rechaza y una de lectura anda, y que cerrarla sin cambios la borra (worktree y rama).

**Notas:** session/worktree_session.gd: create() hace git worktree add -b agent/copy-<fecha> en <repo>.godot-agent-copies/<fecha> (al lado del repo: adentro Godot lo importaría) desde HEAD, con el proyecto en su misma subcarpeta; commit_changes() commitea lo del agente en esa rama y lista los archivos cambiados; apply_to_project() arma el diff base..rama (git diff --binary, limitado al proyecto) y lo aplica con git apply en el repo principal como cambios sin commitear (el harness no mergea; si no entra limpio, queda la rama); remove() saca el worktree y, si se pide, la rama. SessionTabs: «+» abre un menú (sesión / sesión en una copia). Plugin: _make_controller con la copia como cwd y raíz de fs, sin sync con buffers, sin locks ni verificación por res://, con TurnSnapshots propios (los avisos de cambios del turno y volver atrás funcionan sobre la copia); aviso en el chat y note_for_agent explicando dónde trabaja y cómo validar con Godot headless. ToolRegistry.precheck (nuevo): rechaza antes de pedir permiso las tools no de lectura y las game_* para una copia (si no, Construir mostraba una tarjeta y recién después rechazaba). Cerrar la pestaña: si cambió algo, diálogo Aplicar al proyecto / Dejar la rama / Descartar / Cancelar; sin cambios, se borra sola. Al apagar el plugin las copias quedan como están. Una vez, en una corrida del check, quedó una copia sin borrar; no se repitió en tres corridas más.

**Relacionadas:** Checkpoints y «volver a antes de este mensaje» en cada turno

### Integración opcional con GitHub: PR desde una sesión y comentarios como hallazgos · Revisión

**Prioridad:** baja · **Tamaño:** M · **Etiquetas:** `idea`

Idea de la comparación con otros harness (2026-10-27). Como Copilot o Codex. Crear un PR desde una sesión y traer los comentarios de un PR como hallazgos de Revisar. Opcional y apagado por defecto: hoy el harness nunca pushea por diseño.

**Decisiones:**
- ! Abrir un PR desde una copia va apagado por defecto y solo se ofrece al cerrarla · sin revisar
  Por qué: Es lo único del harness que pushea; la importación de comentarios solo lee y queda siempre disponible
  Descartado: Prendido por defecto; un botón aparte para pushear cualquier rama

**Prueba:** Unit: test_github_reviews (repo de remotes ssh/https/otro host; comentarios a hallazgos con prefijo de proyecto, sin respuestas ni fuera del proyecto ni vacíos, original_line, autor; proyecto en la raíz); suite 304/0. Real: con gh sin sesión, fetch_review devuelve el error de gh legible. No probado: con gh logueado, importar un PR real ni abrir uno (pushea).

**Notas:** core/github_reviews.gd con el CLI gh y --repo owner/repo sacado de git remote origin (así no depende del cwd del editor): fetch_review(pr) usa gh pr view (número o la rama actual) y gh api --paginate repos/<repo>/pulls/<n>/comments; comments_to_findings() pasa cada comentario con archivo del proyecto y línea (o original_line si quedó desactualizado) a un hallazgo res:// con el texto y «— @autor on GitHub», sin respuestas de hilo. Panel de Revisar: «De un PR de GitHub…» abre un diálogo con el número (vacío = rama actual) y carga los hallazgos en el ReviewStore (marcas en el Script Editor, «Arreglar en modo Construir»). Solo lee. PR desde una copia (m11-09): con github_pull_requests (apagado por defecto, Settings → Servidores MCP), el diálogo al cerrar una copia suma «Pushear y abrir un PR»: git push -u origin <rama> desde la copia y gh pr create contra la rama de partida (WorktreeSession guarda base_branch); la copia se saca y la rama queda.

### Soporte para Antigravity CLI (agy) como agente · Revisión

**Prioridad:** media · **Tamaño:** M · **Etiquetas:** `idea`

Idea de la comparación con otros harness (2026-10-27). Google publica un adaptador ACP oficial para Antigravity en el registro de ACP (id antigravity-acp, v1.4.3, autor Google LLC, licencia propietaria): un zip por plataforma desde dl.google.com/agy-extensions/releases/<os>/agy-acp-server-<versión>-<os>-<arch>.zip, con sha256, que se ejecuta como ./agy_acp_server.par (en Linux con el argumento --uid=; en Windows agy_acp_server.exe). Así lo integra Zed: lee el registro, baja y verifica el zip, y lanza ese comando como agente ACP por stdio. Hay también adaptadores de la comunidad (agy-acp, antigravity-acp de GitHub) que leen el almacenamiento local de Antigravity; preferir el oficial. A probar: login, que pase los mcpServers de session/new (sin eso no ve godot.*) y godot.sessions/session_send entre agy y Claude Code en el mismo dock.

**Prueba:** Probe ACP a mano (initialize y session/new) contra el binario real. Pendiente del usuario: login con Google y mensajes entre agy y Claude Code.

**Notas:** Con m11-12, Google Antigravity se agrega desde Settings → Agentes → «+ Del registro de ACP…» (adaptador oficial de Google, antigravity-acp 1.4.3, ./agy_acp_server.par --uid= en Linux, ~930 MB). Probado a mano por stdio: initialize anuncia mcpCapabilities {http, sse} (recibe el MCP del harness por HTTP: godot.* incluidas sessions/session_send), loadSession, imágenes y _meta.antigravity.systemPrompt.append, y authMethods oauth-personal, oauth-business, gemini-api-key, agent-platform. session/new sin login devuelve -32000 «Authentication required», que SessionController.is_auth_required reconoce, así que el dock ofrece esos métodos (ACP authenticate). Falta, con la cuenta del usuario: completar el login, una conversación real con las tools godot.* y un godot.session_send entre agy y Claude Code en dos pestañas.

**Bloqueada por:** Instalar agentes desde el registro de ACP

**Relacionadas:** Mensajes entre sesiones: el recibido no se ve y una sesión nueva no los lee hasta su primer prompt

### Instalar agentes desde el registro de ACP · Revisión

**Prioridad:** media · **Tamaño:** M · **Etiquetas:** `idea`

Idea (2026-10-27), surgió de cómo Zed integra Antigravity. El registro de ACP (cdn.agentclientprotocol.com/registry/v1/latest/registry.json) lista ~43 agentes con su forma de instalarlos: npx, uvx o un binario por plataforma (zip con sha256, comando y args). Entre ellos Claude Agent, Codex, Gemini CLI, Copilot, Cursor, Google Antigravity, Goose, OpenCode, Junie, Kimi, Qwen Code, Mistral Vibe. En Settings → Perfiles: elegir un agente del registro y que el harness arme el perfil (npx/uvx) o baje, verifique y descomprima el binario en user://, como hace Zed. Reemplaza armar perfiles a mano y cubre agy sin código propio.

**Prueba:** Unit: test_acp_registry (parse con preferencia y plataforma, perfiles npx/uvx/binario, extract zip con zip slip, tar.gz, ejecutable suelto, chmod, filtro del diálogo); suite 291/0. Real: fetch del registro (43 agentes, linux-x86_64) e install de antigravity-acp 1.4.3 (sha256 ok, 930 MB, ejecutable). Editor: --godot-agent-settings-shots pasa y muestra el botón. No probado: el diálogo abierto en el editor (necesita red).

**Notas:** core/acp_registry.gd (Node): fetch() lee cdn.agentclientprotocol.com/registry/v1/latest/registry.json; parse(data, platform) elige npx > uvx > binario de la plataforma (platform_key: linux|darwin|windows-x86_64|aarch64) y descarta ids que no son nombres de archivo; profile_for() arma el perfil; install() baja el binario, verifica el sha256 si el registro lo trae y extract() lo descomprime en <editor data>/godot_agent/agents/<id>/<versión>/ (.zip con ZIPReader sin rutas que salgan; .tar.* con el tar del sistema; otro = el ejecutable suelto) y le da chmod +x. ui/settings/acp_registry_dialog.gd: lista con filtro, «Agregar», segundo clic «Agregar sin checksum» si falta el sha256 (42 de las ~100 descargas del registro no lo traen), aviso de que un binario puede tardar. Settings → Agentes: «+ Del registro de ACP…»; agregar uno con el mismo id reemplaza el perfil (conserva si era el predeterminado). El registro hoy: 43 agentes, 1.0.0. Los perfiles incluidos (Gemini sin --acp, Codex sin comando) no se tocaron: con el registro ya se pueden agregar bien.

**Bloquea a:** Soporte para Antigravity CLI (agy) como agente

### Cuota de Antigravity con /usage · Revisión

**Prioridad:** alta · **Tamaño:** S · **Etiquetas:** `acp`

Antigravity no manda la cuota en usage_update (solo el contexto, used/size). Su comando /usage, que no gasta tokens, lista por grupo de modelos (Gemini, Claude y GPT, Gemini 4 Argon) cuánto queda de la semana y de las 5 h, con la hora de reinicio en UTC: lo mismo que el menú View Usage del IDE de Antigravity, que lo saca del backend de Google. Pedirlo sin mostrarlo en el chat al abrir la sesión y después de cada turno, y llevar el grupo del modelo en uso a los anillos de cuota.

**Prueba:** tests/unit/test_quota_monitor.gd test_antigravity_usage con el /usage real; contra agy 1.4.3 headless: la cuota llega al abrir (14 %) y se actualiza tras el turno (semana 15 %, 5 h 1 %), y en el chat quedan solo el prompt y la respuesta.

**Notas:** QuotaMonitor.parse_antigravity_usage y antigravity_windows (Argon: semana propia y 5 h del grupo de Gemini). SessionController._query_agent_usage manda /usage oculto (agentInfo.name antigravity-acp) al conectar y al final de cada turno; un prompt del usuario espera a que termine. agy guarda /usage en su historial: un session/load podría reproducirlo.

### Cerrar sesión de la cuenta del agente (ACP logout) · Revisión

**Prioridad:** alta · **Tamaño:** S · **Etiquetas:** `acp`

Acceso rápido para cerrar la sesión de la cuenta en cualquier agente que anuncie agentCapabilities.auth.logout (Claude Code con claude auth logout, Antigravity): botón en la línea de estado con confirmación; el agente borra sus credenciales, se cierra la sesión y la próxima pide login.

**Prueba:** test_session_model test_supports_logout. Sin probar contra la cuenta real (borraría las credenciales).

**Notas:** Método ACP logout (SDK 2.1: AGENT_METHODS.logout = "logout"), anunciado con agentCapabilities.auth.logout. SessionController.logout: request, olvida cuenta y cuota, detiene el agente y avisa. Botón «Cerrar sesión» en la fila de estado del dock con confirmación.

### Terminales del cliente ACP (terminal/*) · Revisión

**Prioridad:** alta · **Tamaño:** L · **Etiquetas:** `acp`

Hoy clientCapabilities.terminal es false: los agentes corren sus comandos por su cuenta. Implementar terminal/create, output, wait_for_exit, kill y release para que los comandos del agente corran desde el editor, con la política de shell (reglas de Auto, permisos por modo), salida en la tarjeta del tool call y límite de bytes. Lo usan Codex y otros agentes del registro; se prueba con Claude Code y Antigravity.

**Prueba:** godot --headless --path . --script tests/run_all.gd -- terminal_handler (test_quoting_and_agent_env_ask: comillas POSIX, Auto permite ls -la sin env y pregunta con LD_PRELOAD, sin regla propuesta; test_command_key_ignores_quoting). No probado con un agente real que use terminal/* (Codex) ni en Windows.

**Notas:** TerminalHandler (terminal/create, output, wait_for_exit, kill y release) con AgentProcess en modo raw (sin threads), truncado UTF-8 desde el principio según outputByteLimit, autorización por SessionController (ProjectWriteGuard, GodotWindowGuard, ShellRules en Auto y tarjetas de permiso), clientCapabilities.terminal = true y visualización de bloques {type: terminal, terminalId} en ToolGroupView.

Revisión (2026-10-28, 2431546): el env del agente pasaba sin filtro y la política no lo veía (en Auto, git status + GIT_CONFIG_* corría código sin preguntar). Ahora con env siempre se pregunta, la tarjeta muestra NOMBRE=valor y el cwd si no es el del proyecto, y no propone regla. format_command_line cita cada arg como sh (shell_quote): las guardas revisan lo mismo que corre. En Windows se rechazan args con comillas o saltos de línea (cmd.exe no las escapa). Las terminales se matan si el agente se cae o al abrir otra sesión. handling_id ahora solo vale mientras el handler no se suspende (antes una tarjeta de una tool MCP quedaba asociada a un wait_for_exit y un $/cancel_request la cancelaba). c32c82c: los comandos preautorizados se comparan por palabras sin comillas (SessionController.command_key), así npm run "a b" del agente y npm run 'a b' de terminal/create no preguntan dos veces. Quedan: exit_signal SIGTERM fijo aunque Unix manda SIGKILL; la tarjeta de un fallo muestra el principio de la salida y no el final; la decodificación UTF-8 por chunk puede cortar un carácter.

### Sesiones del agente: session/list, resume, close y delete · Revisión

**Prioridad:** media · **Tamaño:** M · **Etiquetas:** `acp`

Los agentes anuncian sessionCapabilities.list y resume (Antigravity los tiene; session/list devuelve id, cwd y título). Mostrar en el historial las sesiones que guarda el agente para el proyecto (cwd), retomarlas con session/resume cuando no hay loadSession o no hace falta repetir el historial, y cerrar o borrar con session/close y session/delete si el agente los anuncia.

**Prueba:** godot --headless --path . --script tests/run_all.gd -- session_model (test_session_capabilities_and_merge, test_history_begin_from_agent_listing). acp_session_check 159/0. No probado contra un agente real con session/list (Antigravity) ni el diálogo de borrar en el editor.

**Notas:** SessionModel (supports_list_sessions, supports_resume_session, supports_close_session, supports_delete_session y can_resume_sessions) y SessionController (list_agent_sessions con paginación por cursor, _load_session con session/resume cuando ya hay historial local o sin loadSession, close_session en open_session, delete_session local y en el agente, y merge_session_lists en el menú de historial de AgentDock).

Revisión (2026-10-28, 2431546): retomar una sesión que solo lista el agente rompía el historial (el registro no traía created y save() fallaba): SessionHistory.begin completa la cabecera. Borrar desde el menú pide confirmación, manda session/delete solo si la sesión es del perfil conectado y, si el agente falla, deja la local y avisa. open_session resetea el modelo antes del await del close (sin doble session/new ni prompts a la sesión que se cierra) y un segundo «Nueva sesión» durante el close se ignora. El One-shot usa open_session_keeping_previous() para no cerrar la sesión del generador que después vuelve a cargar. agent_sessions se vacía al pasar a un agente sin session/list; se sacó el filtro por cwd del cliente (en Windows descartaba todo). c32c82c: session/close se cancela a los 10 s (CLOSE_TIMEOUT_S), así un agente que no contesta no deja «Nueva sesión» sin efecto. Quedan: el menú muestra la lista del pedido anterior; tope de 3 páginas; updatedAt ignora el offset de zona; fake_agent no implementa list/resume/close/delete (el timeout del close no tiene test).

### Formularios del agente (elicitation/create y complete) · Revisión

**Prioridad:** media · **Tamaño:** M · **Etiquetas:** `acp`

ACP v1 suma elicitation/create y elicitation/complete del lado del cliente: el agente pide datos al usuario con un esquema (texto, opciones, confirmación). Anunciar la capacidad y mostrarlos como tarjeta en el dock, como los permisos.

**Prueba:** godot --headless --path . --script tests/run_all.gd -- elicitation (incluye test_rejects_local_links_and_json_numbers, test_controller_rejects_invalid_elicitation, test_untouched_optional_fields_are_left_out). No probado con un agente real que mande elicitation/create ni la tarjeta en el editor.

**Notas:** Agregados ElicitationRequest (session/elicitation_request.gd) y ElicitationView (ui/dock/entries/elicitation_view.gd) para formularios (mode: form con string, enum/oneOf, boolean, integer/number y array multi-select) y enlaces (mode: url). Conectados elicitation/create, elicitation/complete, $/cancel_request y clientCapabilities.elicitation en SessionController, SessionModel y ConversationView.

Revisión (2026-10-28, 2431546 y 651d557): un enlace que no era http(s) iba por open_link del chat y terminaba en OS.shell_open de un archivo local. Ahora invalid_reason() rechaza con -32602 modos desconocidos, url sin elicitationId o que no es http(s); la URL se ve en la tarjeta y se abre directo en el navegador. minLength/minItems no se validaban nunca (JSON trae floats). Un booleano o número opcional sin default que el usuario no tocó no se manda; los number no se redondean (step 0); un default no numérico no rompe. elicitation/complete con el enlace pendiente responde cancel (antes accept sin que el usuario aceptara) y no toca formularios. Las pestañas de fondo muestran «⚠» y toast también para formularios. Quedan sin validar: maxLength, maxItems, pattern y format; enumNames; un required enum sin default preselecciona la primera opción.

### Cancelar requests en vuelo ($/cancel_request) · Revisión

**Prioridad:** baja · **Tamaño:** S · **Etiquetas:** `acp`

Soportar $/cancel_request en las dos direcciones: el cliente cancela un request que ya no espera (por ejemplo un /usage o un session/load que se dejó) y atiende el del agente cancelando permisos, fs o terminales pendientes.

**Prueba:** tests/unit/test_acp_client.gd test_cancel_request_both_directions y test_incoming_cancel_mark_survives_await (falla sin el arreglo).

**Notas:** AcpClient.cancel_request(id) manda $/cancel_request, resuelve el await local con ERR_REQUEST_CANCELLED (-32800) e ignora respuestas tardías; SessionController._cancel_abandoned_requests() cancela /usage, /status o session/new|load|resume en vuelo al abrir otra sesión. Del lado entrante, $/cancel_request emite incoming_cancelled (cancela tarjetas de permiso de request_permission, fs/write_text_file y terminal/create en _ask_user, elicitations y esperas de terminal) y responde -32800 sin duplicar si el handler termina más tarde.

Revisión (2026-10-28, 2431546): is_incoming_cancelled() nunca daba true (la marca se borraba en la misma llamada que la ponía), así que un terminal/create cancelado igual lanzaba el proceso. Ahora la marca dura hasta que el handler termina. handling_id se limpia en receive_line apenas el handler se suspende. Quedan: un -32800 del propio agente se toma como cancelación local (session/new podría quedar en STARTING); _cancelled_outgoing crece si el agente nunca responde.

### Extensiones por agente: skills, plugins, reglas e instrucciones · Revisión

**Prioridad:** media · **Tamaño:** L · **Etiquetas:** `acp`

La pestaña de Extensiones (skills, plugins, marketplaces) es solo de Claude Code. Investigar y soportar lo equivalente de cada agente con perfil: Codex (skills, AGENTS.md, config de MCP), Antigravity (AGENTS.md y GEMINI.md, reglas, workflows y skills, a confirmar dónde los lee), Copilot, Cursor y OpenCode. Lo que sea por archivos se arma desde el editor; lo que el agente anuncie por ACP (available_commands, configOptions) ya se muestra.

**Prueba:** godot --headless --path . --script tests/run_all.gd -- claude_extensions skill_catalog (test_codex_toml_variants, test_codex_toml_multiline_strings y test_project_dirs_per_agent). No probado en el editor con perfiles de cada agente.

**Notas:** Extendidas las pestañas Skills, Instructions y MCP de Extensions a todos los agentes: detección de perfil (Claude, Codex, Antigravity, Copilot, Cursor, OpenCode) en ClaudeExtensions.agent_kind(); escaneo, creación, importación y copia de skills en SkillCatalog y SkillsTab; edición y alta de instrucciones, reglas y workflows en InstructionsTab; y lectura de MCP servers desde config.toml de Codex, mcp_config.json de Antigravity, .cursor/mcp.json, .vscode/mcp.json y opencode.json en ClaudeExtensions.agent_mcp_servers().

Revisión (2026-10-28, 2431546, 651d557 y c32c82c): regresión en Claude: project_dirs listaba .agents/skills, .codex/skills, etc. para todos y aparecían como del proyecto skills que Claude no carga. Ahora PROJECT_SKILL_DIRS da las de cada agente. .mcp.json ya no se lista para agentes que no son Claude. config.toml de Codex con un lector de TOML acotado (extensions/toml_lite.gd): comentarios al final, arrays de varias líneas, strings literales, strings de comillas triples, tablas en línea, claves con puntos. Rutas de Antigravity verificadas contra la documentación actual: .agents/rules, .agents/workflows, .agents/skills, .agents/plugins, ~/.gemini/config/skills, ~/.gemini/config/mcp_config.json y ~/.gemini/config/plugins son las vigentes (.agent/ sigue por compatibilidad). Quedan: JSONC (opencode.jsonc, .vscode/mcp.json con comentarios) no se lee; Gemini CLI se detecta como «other»; borrar una skill de ~/.agents/skills la saca para todos los agentes sin decirlo.

### Cuota de los demás agentes · Revisión

**Prioridad:** media · **Tamaño:** M · **Etiquetas:** `acp`

Claude (usage_update _meta _claude/rateLimit) y Antigravity (/usage) ya informan la cuota. Ver qué informan Codex, Copilot y Cursor por ACP (usage_update, _meta, comandos como /status) y leerlo sin endpoints ni archivos del agente (regla de QuotaMonitor).

**Prueba:** tests/unit/test_quota_monitor.gd test_codex_and_other_agents_quota, test_opencode_payload_and_codes_only_in_errors y test_codex_status_locale_and_spend. No probado contra codex-acp real.

**Notas:** Codex (codex-acp): usage_update solo trae tokens de contexto, pero su comando local /status (sin gastar tokens) informa las ventanas de 5 h y semanal de RateLimitsMap y la cuenta; SessionController._query_agent_usage lo pide igual que /usage de Antigravity, y _auth/status_update mantiene model.account al día. OpenCode: reintentos por límite en session_info_update (_meta["opencode/retry"]). Copilot y Cursor no mandan ventanas de cuota por ACP: se detectan sus errores y textos de límite.

Revisión (2026-10-28, 2431546, 651d557 y c32c82c): Codex nunca se detectaba: el adaptador del registro se llama @agentclientprotocol/codex-acp, y el viejo de Zed (codex-acp) no tiene /status y se lo mandaría al modelo como prompt. Ahora _usage_agent() pide nombre …/codex-acp y que anuncie el comando status. La consulta oculta se cancela a los 20 s (session/cancel + $/cancel_request), y no hace nada si el agente ya se detuvo. La cuenta de _auth/status_update se borraba con el _refresh_account del session/new; ahora se guarda (_agent_account) y se olvida al reiniciar el agente o cerrar sesión. Retry real de OpenCode (provider.rate-limit, status 429). Los códigos insufficient_quota, rateLimitExceeded, etc. solo se buscan en errores (LIMIT_CODES_IN_ERRORS), no en la prosa del agente. /status: fechas con locale (3 dic., 3 de nov.), 24:05 como 00:05, grupos con espacios, y el límite de gasto del asiento no pisa la semanal. Queda: el offset de zona es el de hoy y no el del día del reinicio (cambio de horario).

### Cuota por grupo de modelos en el tooltip · Revisión

**Prioridad:** baja · **Tamaño:** S · **Etiquetas:** `acp`

Antigravity tiene cuotas separadas por grupo (Gemini, Claude y GPT, Gemini 4 Argon) y los anillos muestran solo el del modelo en uso. Mostrar todos los grupos en el tooltip de los anillos, como el menú View Usage del IDE de Antigravity.

**Prueba:** tests/unit/test_quota_monitor.gd test_antigravity_usage (describe_groups, QuotaRing.describe y select_antigravity_model).

**Notas:** QuotaMonitor.groups guarda los grupos de /usage, describe_groups() arma una línea por grupo (Gemini, Claude y GPT, Gemini 4 Argon) y QuotaRing.describe() las agrega al tooltip debajo de los anillos. select_antigravity_model() cambia las ventanas activas en cuanto cambia la opción model.

Revisión (2026-10-28): sin problemas en lo propio de esta tarea. Nota: con varios grupos de Codex, config_options_changed también llama a select_antigravity_model, que aplica la heurística de Antigravity (no rompe nada hoy).

## M10 — Revisión de UX  (7/37, 7 en revisión)

Arreglar lo que la revisión de UX del 29/10 encontró en el dock, Ajustes, el registro de ACP, Extensiones, One-shot, Alt+I y el Agent Log: primero el diseño roto que esconde controles, después los flujos que más se usan.

**Hecho cuando:**
- Cada hallazgo quedó hecho o descartado con su motivo en la tarjeta.
- Un recorrido de capturas de todas las superficies no muestra controles tapados ni cortados.

### «Cerrar» tapa el contenido y esconde «Guardar» en Extensiones y el registro · Revisión

**Prioridad:** alta · **Tamaño:** S · **Etiquetas:** `ux`, `roto`, `extensiones`

En el registro de ACP y en Extensiones la lista sigue por debajo de «Cerrar». En Instrucciones el área de texto llega abajo y «Guardar» y «Agregar los datos del proyecto» quedan fuera de la ventana.

Propuesta: Que el contenido de cada pestaña quepa en el alto disponible (se encogen el scroll y el área de texto) y las acciones de la pestaña en su propia barra arriba.

Archivos: extensions_window.gd, instructions_tab.gd, acp_registry_dialog.gd

Informe: https://claude.ai/artifact/KsFLJqJYs2XKeoAc8BAPWH
Lienzo: https://claude.ai/artifact/3WiCtTnZP94EADbreh18ny (pantalla 6)

**Prueba:** Recorrido de capturas en Xvfb (Extensiones › Instrucciones y registro de ACP); prueba headless de AcceptDialog con y sin wrap_controls.

**Notas:** Causa: con wrap_controls = false, AcceptDialog acomoda su contenido solo al cambiar de tamaño; un Label con autowrap se mide primero con ancho ~0 y deja el contenido de 1873 px de alto, debajo de los botones. ExtensionsUi.refit_dialog manda NOTIFICATION_THEME_CHANGED un frame después de abrir (y al cambiar de pestaña). Verificado con captura en Xvfb: Instrucciones muestra Guardar y el registro su estado.

### «Buscando actualizaciones…» se dibuja en vertical en Addons de Godot · Revisión

**Prioridad:** alta · **Tamaño:** S · **Etiquetas:** `ux`, `roto`, `extensiones`

El aviso es un Label con autowrap en una columna de ancho cero: una letra por línea, y el título de la sección queda centrado en el vacío.

Propuesta: El aviso en la fila del título («En este proyecto (3) · buscando actualizaciones…»), sin autowrap o con ancho mínimo.

Archivos: godot_addons_tab.gd

Informe: https://claude.ai/artifact/KsFLJqJYs2XKeoAc8BAPWH

**Prueba:** Captura de Addons de Godot en Xvfb.

**Notas:** ExtensionsUi.muted tiene autowrap: en una fila al lado de un título expandido queda con ancho 0. Sin autowrap en «Buscando actualizaciones…» y en los «+N −M» de turn_changes_dialog.

### El panel de Revisar tapa la conversación y no se va · Revisión

**Prioridad:** alta · **Tamaño:** M · **Etiquetas:** `ux`, `roto`, `dock`

Ocupa unos 230 px fijo arriba del chat, sigue después de cerrar la sesión, tapa tarjetas nuevas y muestra un hallazgo y medio cortado. El JSON de findings se ve crudo en el chat.

Propuesta: Plegarlo a una fila («Revisión · 1 bug, 1 rend · Ver»), cerrarlo con la sesión y ocultar el bloque findings ya leído.

Archivos: review_panel.gd, ReviewStore

Informe: https://claude.ai/artifact/KsFLJqJYs2XKeoAc8BAPWH

**Prueba:** Captura de la guía (docs_review) en Xvfb: una fila y el chat a la vista; review_check del plugin de dev actualizado al título del FoldableContainer.

**Notas:** Panel plegado por defecto en un FoldableContainer: el título resume alcance, archivos y contadores; se abre con un clic. La lista calcula su alto con la fila real (con 26 px fijos se veía un hallazgo y medio). Ocultar el bloque findings del chat quedó en m12-38. Cerrar el panel con la sesión no hizo falta: plegado ocupa una fila.

### Las pestañas de Extensiones no entran en la ventana · Pendiente

**Prioridad:** media · **Tamaño:** M · **Etiquetas:** `ux`, `roto`, `extensiones`

Seis pestañas en 640 px: Instrucciones queda detrás de las flechas y al llegar desaparecen Plugins y Marketplaces. Los contadores cambian mientras carga.

Propuesta: Barra lateral como la de Ajustes, con los contadores solo cuando cargaron.

Archivos: extensions_window.gd

Informe: https://claude.ai/artifact/KsFLJqJYs2XKeoAc8BAPWH
Lienzo: https://claude.ai/artifact/3WiCtTnZP94EADbreh18ny (pantalla 6)

### La barra del Agent Log se corta · Revisión

**Prioridad:** media · **Tamaño:** S · **Etiquetas:** `ux`, `roto`, `log`

Con el ancho por defecto «Limpiar» queda en «Limp». Los canales son palabras de colores sin estado visible y el «3» no dice qué cuenta.

Propuesta: Canales como chips con estado, «3 entradas», Copiar/Limpiar como íconos con tooltip.

Archivos: agent_log_panel.gd

Informe: https://claude.ai/artifact/KsFLJqJYs2XKeoAc8BAPWH

**Prueba:** Captura del Agent Log en Xvfb.

**Notas:** Barra como HFlowContainer (baja de línea en vez de cortarse), canales con ● / ○ según estén prendidos, «N entradas», Copiar y Limpiar como íconos del editor con tooltip.

### El panel de Alt+I queda gigante y tapa el código · Revisión

**Prioridad:** alta · **Tamaño:** S · **Etiquetas:** `ux`, `roto`, `alt-i`

Mínimo fijo de 520 × 220 y no se achica al reabrirse: hereda el alto de la propuesta anterior (700 px negros para una línea).

Propuesta: reset_size() antes de cada popup en _show_proposal, sin alto mínimo sin diff, abrirlo debajo de la selección.

Archivos: editor/inline_edit.gd

Informe: https://claude.ai/artifact/KsFLJqJYs2XKeoAc8BAPWH
Lienzo: https://claude.ai/artifact/3WiCtTnZP94EADbreh18ny (pantalla 10)

**Notas:** reset_size() antes de cada popup en _show_proposal; el RichTextLabel del diff pide 200 px solo cuando hay diff.

### Alt+I: «Reject» cuando no hay nada que rechazar · Revisión

**Prioridad:** alta · **Tamaño:** S · **Etiquetas:** `ux`, `alt-i`

Esperando, «Reject» solo esconde el panel y el turno sigue en el dock. Sin sesión, el aviso no ofrece iniciarla.

Propuesta: Esperando: «Cancelar» que cancela el turno. Sin sesión: «Iniciar con Claude Code» y el pedido sale al conectar. Propuesta: Aceptar (Enter) y Descartar (Esc).

Archivos: editor/inline_edit.gd

Informe: https://claude.ai/artifact/KsFLJqJYs2XKeoAc8BAPWH
Lienzo: https://claude.ai/artifact/3WiCtTnZP94EADbreh18ny (pantalla 10)

**Prueba:** test_inline_edit.test_where_label. Sin probar en el editor con un agente.

**Notas:** Botón según estado: Cancelar (cancela el turno con controller.cancel), Cerrar o Rechazar. Sin sesión: «Iniciar sesión» abre la de la pestaña activa (agent_dock._start_session) y reenvía el pedido. El panel repite el pedido y las líneas (where_label), parte de m12-08.

### Alt+I: esperando no dice qué se pidió ni muestra avance · Pendiente

**Prioridad:** media · **Tamaño:** S · **Etiquetas:** `ux`, `alt-i`

«Asking the agent…» fijo en un panel vacío.

Propuesta: El pedido entre comillas, «Claude Code · líneas 15–16», indicador animado y tiempo.

Archivos: editor/inline_edit.gd

Informe: https://claude.ai/artifact/KsFLJqJYs2XKeoAc8BAPWH
Lienzo: https://claude.ai/artifact/3WiCtTnZP94EADbreh18ny (pantalla 10)

### One-shot no se adapta al ancho y se corta · Revisión

**Prioridad:** alta · **Tamaño:** M · **Etiquetas:** `ux`, `roto`, `oneshot`

Con el dock ancho, al centro le quedan unos 320 px: el texto se corta a los dos lados y «Iniciar One-shot» no se ve.

Propuesta: La tarjeta usa el ancho disponible y, angosta, apila las columnas con el botón siempre visible.

Archivos: agent_main_screen.tscn

Informe: https://claude.ai/artifact/KsFLJqJYs2XKeoAc8BAPWH
Lienzo: https://claude.ai/artifact/3WiCtTnZP94EADbreh18ny (pantalla 7)

**Prueba:** Captura de One-shot con el dock a 1230 px (centro de ~380 px) en Xvfb: todo visible, Iniciar One-shot incluido.

**Notas:** El formulario va en un ScrollContainer y se achica hasta 280 px (FORM_NARROW_WIDTH) en vez de quedar fijo en 640 dentro de un CenterContainer; presupuestos en HFlowContainer con SpinBox de 110 px mínimo; las casillas con autowrap.

### El permiso repite el diff y el botón riesgoso va primero · Pendiente

**Prioridad:** alta · **Tamaño:** M · **Etiquetas:** `ux`, `dock`

El mismo diff en la herramienta y en la tarjeta de permiso; «Siempre en esta sesión» primero y sin atajos.

Propuesta: Resaltar la herramienta que espera y una barra de decisión fija sobre el composer: Permitir, Denegar y «siempre» como enlace. Enter/Esc solo con el foco en la barra (en el composer Enter encola y Esc detiene el turno).

Archivos: entries/permission_view.gd

Informe: https://claude.ai/artifact/KsFLJqJYs2XKeoAc8BAPWH
Lienzo: https://claude.ai/artifact/3WiCtTnZP94EADbreh18ny (pantalla 2)

### Pedir el login se ve como un error con seis botones · Pendiente

**Prioridad:** alta · **Tamaño:** M · **Etiquetas:** `ux`, `dock`

Tarjeta roja «Authentication required (-32000)» con cuatro métodos que repiten «Sign in · Log in with…», más Retry y Open the log below.

Propuesta: Tarjeta neutra «Iniciá sesión en <agente>» con el método principal como botón y los demás bajo «Otras formas de entrar», sin código ni Reintentar.

Archivos: SessionController._login_actions, notice_view.gd

Informe: https://claude.ai/artifact/KsFLJqJYs2XKeoAc8BAPWH
Lienzo: https://claude.ai/artifact/3WiCtTnZP94EADbreh18ny (pantalla 8)

### Al abrir, mostrar las sesiones anteriores y opción para continuar la última · Pendiente

**Prioridad:** alta · **Tamaño:** M · **Etiquetas:** `ux`, `dock`, `ajustes`

Con agente configurado, el dock abre en «Sin sesión» con «Iniciar sesión». Seguir lo anterior requiere el ícono de historial, y no hay forma de que reabra la última sesión solo.

Propuesta: Lista de sesiones del proyecto (título, agente, cuándo, turnos, Continuar) con «Nueva sesión» arriba. En Ajustes › Interfaz: «Al abrir el editor: mostrar las sesiones / continuar la última».

Archivos: agent_dock._refresh_empty_state, SessionHistory.list, harness_settings.gd

Informe: https://claude.ai/artifact/KsFLJqJYs2XKeoAc8BAPWH
Lienzo: https://claude.ai/artifact/3WiCtTnZP94EADbreh18ny (pantalla 9)

### Un error del agente es un párrafo rojo sin qué hacer · Pendiente

**Prioridad:** alta · **Tamaño:** M · **Etiquetas:** `ux`, `dock`

Todo en rojo con la ruta partida, y solo Reintentar y Abrir el log.

Propuesta: Título y causa en lenguaje claro, las últimas líneas del log con Copiar, y la acción que lo arregla. «Reinstalar» un agente del registro tiene que borrar la versión instalada antes (hoy Agregar reutiliza lo que está en disco).

Archivos: SessionController._fail, notice_view.gd, acp_registry.gd

Informe: https://claude.ai/artifact/KsFLJqJYs2XKeoAc8BAPWH
Lienzo: https://claude.ai/artifact/3WiCtTnZP94EADbreh18ny (pantalla 3)

### Tres filas de controles antes del chat · Pendiente

**Prioridad:** media · **Tamaño:** M · **Etiquetas:** `ux`, `dock`

Pestañas de sesión, agente con cuatro íconos sin texto y la línea de estado que repite el agente. Dos «+» casi pegados (pestaña y sesión). Sin agentes el selector es solo «⌄».

Propuesta: Una fila: chip del agente con estado, título, historial, «+» (sesión o pestaña) y «⋯» con extensiones, ajustes, cuenta y Remote Control.

Archivos: agent_dock.tscn, session_tabs.gd

Informe: https://claude.ai/artifact/KsFLJqJYs2XKeoAc8BAPWH
Lienzo: https://claude.ai/artifact/3WiCtTnZP94EADbreh18ny (pantalla 1)

### Primer arranque: el composer activo sin agente y la elección en Ajustes · Pendiente

**Prioridad:** media · **Tamaño:** M · **Etiquetas:** `ux`, `dock`

Sin agentes, el composer tiene main.tscn y «Construir» como si se pudiera usar; «Configurar un agente…» lleva a una lista vacía en Ajustes.

Propuesta: Los tres agentes más usados en el dock con lo que piden y «Agregar»; composer deshabilitado con «Agregá un agente para empezar».

Archivos: agent_dock._refresh_empty_state

Informe: https://claude.ai/artifact/KsFLJqJYs2XKeoAc8BAPWH
Lienzo: https://claude.ai/artifact/3WiCtTnZP94EADbreh18ny (pantalla 4)

### Formulario del agente: «Rechazar» y «Cancelar» confunden · Pendiente

**Prioridad:** media · **Tamaño:** S · **Etiquetas:** `ux`, `dock`

Enviar, Rechazar y Cancelar (decline y cancel en ACP); la lista obligatoria arranca en «—»; ícono de documentación.

Propuesta: «Enviar» y «No responder», Cancelar con Esc; listas con la primera opción o «Elegí…»; ícono de pregunta.

Archivos: entries/elicitation_view.gd

Informe: https://claude.ai/artifact/KsFLJqJYs2XKeoAc8BAPWH

### Todo va en una caja y las herramientas se cortan · Pendiente

**Prioridad:** media · **Tamaño:** L · **Etiquetas:** `ux`, `dock`

Texto, plan, herramientas y respuesta en cajas iguales; nombres técnicos cortados (godot.connect_sig…), salida y spawner.gd:13 sueltos.

Propuesta: Texto del agente sin caja; grilla de tres columnas con nombres para personas y la salida anidada.

Archivos: conversation_view.gd, tool_group_view.gd

Informe: https://claude.ai/artifact/KsFLJqJYs2XKeoAc8BAPWH
Lienzo: https://claude.ai/artifact/3WiCtTnZP94EADbreh18ny (pantalla 1)

### Ocho controles en la barra del composer · Pendiente

**Prioridad:** media · **Tamaño:** M · **Etiquetas:** `ux`, `dock`

@, imagen, /, anillo, 38k/200k, modo, modelo y Enviar en una fila; «Construir» parece un enlace.

Propuesta: Un «+» con archivo o nodo, captura y comando; el modo como píldora; un anillo con contexto y cuota en el tooltip.

Archivos: composer.gd

Informe: https://claude.ai/artifact/KsFLJqJYs2XKeoAc8BAPWH
Lienzo: https://claude.ai/artifact/3WiCtTnZP94EADbreh18ny (pantalla 1)

### Avisos del editor repetidos por sesión · Pendiente

**Prioridad:** baja · **Tamaño:** S · **Etiquetas:** `ux`, `dock`

«Sesión 1 espera tu permiso» y «espera tu respuesta» se apilan para la misma sesión.

Propuesta: Un aviso por sesión que se actualiza y se va al responder.

Archivos: session_tabs.gd

Informe: https://claude.ai/artifact/KsFLJqJYs2XKeoAc8BAPWH

### Pie de turno con los cambios · Pendiente

**Prioridad:** baja · **Tamaño:** S · **Etiquetas:** `ux`, `dock`

El reporte del turno es un aviso más y se pierde.

Propuesta: Pie: «Este turno cambió 1 archivo · Ver cambios · Deshacer turno».

Archivos: SessionController._report_turn_changes

Informe: https://claude.ai/artifact/KsFLJqJYs2XKeoAc8BAPWH
Lienzo: https://claude.ai/artifact/3WiCtTnZP94EADbreh18ny (pantalla 1)

### Ajustes › Agentes: vacío sin guía y el formulario lejos · Pendiente

**Prioridad:** alta · **Tamaño:** M · **Etiquetas:** `ux`, `ajustes`

Sin agentes, una línea sobre $VAR y dos botones. «Predeterminado» es texto que es botón, y Editar abre el formulario debajo de la lista.

Propuesta: Sin agentes, los tres sugeridos. Con agentes, lista a la izquierda y formulario a la derecha; estrella de predeterminado; la nota de $VAR junto al campo de entorno.

Archivos: settings_dialog._build_agents

Informe: https://claude.ai/artifact/KsFLJqJYs2XKeoAc8BAPWH
Lienzo: https://claude.ai/artifact/3WiCtTnZP94EADbreh18ny (pantalla 5)

### Ajustes › Permisos: 45 desplegables sin puntos de partida · Pendiente

**Prioridad:** media · **Tamaño:** M · **Etiquetas:** `ux`, `ajustes`

Matriz de 9 grupos por 5 modos con desplegables iguales; «Subagentes a la vez 0» ambiguo; nota de MCP cortada.

Propuesta: Celdas con color e ícono que cambian con un clic, marcar lo que difiere del default, «Restaurar» por columna, «0 = sin límite».

Archivos: settings_dialog._build_permissions

Informe: https://claude.ai/artifact/KsFLJqJYs2XKeoAc8BAPWH

### Ajustes › Servidores MCP mezcla tres temas · Pendiente

**Prioridad:** media · **Tamaño:** S · **Etiquetas:** `ux`, `ajustes`

Servidores externos con dos párrafos largos, el servidor del editor (puerto, token, máximo) y las carpetas fuera del proyecto en la misma página.

Propuesta: Solo los externos con una línea y enlace a la guía; el servidor del editor y las carpetas en «Avanzado».

Archivos: mcp_servers_page.gd, settings_dialog.gd

Informe: https://claude.ai/artifact/KsFLJqJYs2XKeoAc8BAPWH
Lienzo: https://claude.ai/artifact/3WiCtTnZP94EADbreh18ny (pantalla 5)

### Ajustes › Completado: perillas de ajuste fino a la vista · Pendiente

**Prioridad:** media · **Tamaño:** S · **Etiquetas:** `ux`, `ajustes`

Umbral del ranker, margen y debounce al nivel de «Activado».

Propuesta: Activado, modo y fuentes arriba; los números en «Avanzado» plegado.

Archivos: completion_settings_page.gd

Informe: https://claude.ai/artifact/KsFLJqJYs2XKeoAc8BAPWH

### Ajustes › One-shot repite la pantalla de One-shot · Pendiente

**Prioridad:** baja · **Tamaño:** S · **Etiquetas:** `ux`, `ajustes`

Presupuestos y checkpoint repetidos; los umbrales de cuota quedan abajo de los criterios.

Propuesta: Acá «Valores iniciales de cada One-shot»; la cuota en su propia sección.

Archivos: settings_dialog._build_oneshot

Informe: https://claude.ai/artifact/KsFLJqJYs2XKeoAc8BAPWH
Lienzo: https://claude.ai/artifact/3WiCtTnZP94EADbreh18ny (pantalla 5)

### Ajustes: Guardar y Cancelar lejos y sin aviso de cambios · Pendiente

**Prioridad:** baja · **Tamaño:** S · **Etiquetas:** `ux`, `ajustes`

Botones separados en el medio del pie; nada marca la sección con cambios; Export deshabilitado sin decir por qué.

Propuesta: Botones juntos a la derecha, un punto en la sección con cambios, y en Export «Creá un preset de export primero».

Archivos: settings_dialog.gd

Informe: https://claude.ai/artifact/KsFLJqJYs2XKeoAc8BAPWH
Lienzo: https://claude.ai/artifact/3WiCtTnZP94EADbreh18ny (pantalla 5)

### Registro de ACP: orden alfabético con lo menos útil primero · Pendiente

**Prioridad:** media · **Tamaño:** M · **Etiquetas:** `ux`, `registro`

Abre en Agoragentic, Amp y Auggie; nada dice si ya está agregado, qué cuenta pide o cuánto pesa.

Propuesta: Sugeridos y agregados arriba, después el resto; tipo de instalación y tamaño en cada tarjeta.

Archivos: acp_registry_dialog.gd

Informe: https://claude.ai/artifact/KsFLJqJYs2XKeoAc8BAPWH

### Registro de ACP: descripciones en inglés · Pendiente

**Prioridad:** baja · **Tamaño:** S · **Etiquetas:** `ux`, `registro`

Las descripciones del registro vienen en inglés.

Propuesta: Texto propio en es.po para los sugeridos.

Archivos: acp_registry_dialog.gd, es.po

Informe: https://claude.ai/artifact/KsFLJqJYs2XKeoAc8BAPWH

### Extensiones › Skills: acciones como íconos sueltos · Pendiente

**Prioridad:** media · **Tamaño:** S · **Etiquetas:** `ux`, `extensiones`

Cuatro íconos sin texto por skill; el selector dice «En este proyecto» y la lista muestra «Usuario».

Propuesta: Acciones en un menú «⋯» con texto; el selector como filtro con «Todas» y secciones con su alcance.

Archivos: skills_tab.gd

Informe: https://claude.ai/artifact/KsFLJqJYs2XKeoAc8BAPWH

### Extensiones: pestañas vacías o con mensajes confusos · Pendiente

**Prioridad:** media · **Tamaño:** S · **Etiquetas:** `ux`, `extensiones`

Cargando: una línea chica y 450 px vacíos. Sin agentes, Servidores MCP en blanco y Plugins dice «el perfil activo es otro agente» sin haber ninguno.

Propuesta: Filas fantasma mientras carga; sin agente, un mensaje y un botón para agregar uno.

Archivos: extensions_window.gd

Informe: https://claude.ai/artifact/KsFLJqJYs2XKeoAc8BAPWH

### Extensiones › Addons de Godot no es del agente · Pendiente

**Prioridad:** baja · **Tamaño:** M · **Etiquetas:** `ux`, `extensiones`

La tienda de addons de Godot comparte ventana con skills y MCP; el editor ya tiene su Tienda de Assets.

Propuesta: Solo lo del agente; como mucho «Del proyecto» con lo instalado.

Archivos: godot_addons_tab.gd

Informe: https://claude.ai/artifact/KsFLJqJYs2XKeoAc8BAPWH
Lienzo: https://claude.ai/artifact/3WiCtTnZP94EADbreh18ny (pantalla 6)

### Extensiones › Instrucciones: qué agente lee cada archivo · Pendiente

**Prioridad:** baja · **Tamaño:** S · **Etiquetas:** `ux`, `extensiones`

Para saber qué lee Antigravity hay que abrir el desplegable archivo por archivo.

Propuesta: Lista de archivos con quién lo lee al lado y el editor a la derecha.

Archivos: instructions_tab.gd

Informe: https://claude.ai/artifact/KsFLJqJYs2XKeoAc8BAPWH
Lienzo: https://claude.ai/artifact/3WiCtTnZP94EADbreh18ny (pantalla 6)

### One-shot: «Iniciar» deshabilitado sin decir por qué · Pendiente

**Prioridad:** alta · **Tamaño:** S · **Etiquetas:** `ux`, `oneshot`

Botón apagado casi ilegible, sin texto de qué falta ni con qué agente corre.

Propuesta: El agente elegido arriba y, junto al botón, lo que falta («Escribí el objetivo»); sin agentes, el selector del dock.

Archivos: agent_main_screen.gd

Informe: https://claude.ai/artifact/KsFLJqJYs2XKeoAc8BAPWH
Lienzo: https://claude.ai/artifact/3WiCtTnZP94EADbreh18ny (pantalla 7)

### One-shot: una tarjeta chica en una pantalla vacía · Pendiente

**Prioridad:** media · **Tamaño:** M · **Etiquetas:** `ux`, `oneshot`

900 px al medio de 1920, objetivo de 400 px de alto y presupuestos de 290 px para valores como «8».

Propuesta: Dos columnas: objetivo con ejemplos a la izquierda; agente, presupuestos compactos y opciones a la derecha.

Archivos: agent_main_screen.tscn

Informe: https://claude.ai/artifact/KsFLJqJYs2XKeoAc8BAPWH
Lienzo: https://claude.ai/artifact/3WiCtTnZP94EADbreh18ny (pantalla 7)

### Dos cosas se llaman «Agent» · Pendiente

**Prioridad:** baja · **Tamaño:** S · **Etiquetas:** `ux`, `oneshot`

La pantalla principal «Agent» abre One-shot y la pestaña del dock también se llama Agent.

Propuesta: La pantalla principal como «One-shot».

Archivos: plugin.gd (_get_plugin_name)

Informe: https://claude.ai/artifact/KsFLJqJYs2XKeoAc8BAPWH

### Agent Log: ir a la línea del error desde el chat · Pendiente

**Prioridad:** baja · **Tamaño:** M · **Etiquetas:** `ux`, `log`

El log es una lista plana; desde un error se abre el panel pero no se ubica en la línea.

Propuesta: «Abrir el log» filtra por la sesión y salta a la línea del error, resaltada.

Archivos: agent_log_panel.gd

Informe: https://claude.ai/artifact/KsFLJqJYs2XKeoAc8BAPWH

### Migrar perfiles viejos: quitar Gemini CLI y el Codex sin comando · Pendiente

**Prioridad:** media · **Tamaño:** S · **Etiquetas:** `ux`, `ajustes`

Los perfiles preseteados se sacaron en 0.1.8, pero quien ya tenía la configuración guardada conserva «Gemini CLI» (discontinuado, reemplazado por Antigravity) y «Codex» sin comando: aparecen en Ajustes › Agentes y en el selector del dock. Visto en la configuración real de Godot 4.7 durante la revisión del 29/10.

Propuesta: al cargar los perfiles, quitar una vez el gemini-cli preseteado (command "gemini", sin args) y el codex con comando vacío, solo si siguen iguales al preset (no tocar uno editado), y avisar en el log.

Archivos: harness_settings.gd (profiles)

## M11 — Revisiones de seguridad, patrones y arquitectura  (0/3)

Después de la revisión de UX: revisar el addon entero en seguridad (lo que el agente puede hacer en la máquina y en el proyecto), patrones de Godot y arquitectura, y dejar cada hallazgo como tarea con su arreglo.

**Hecho cuando:**
- Las tres revisiones tienen su informe y cada hallazgo quedó como tarea hecha o descartada con su motivo.

### Revisión de seguridad del addon · Pendiente

**Prioridad:** alta · **Tamaño:** L · **Etiquetas:** `revision`, `seguridad`

Revisar todo lo que el agente o un tercero puede hacer a través del harness: terminales y preautorización (como el command_key de eae1e13), fs/*, permisos por modo y reglas de Auto, el servidor MCP local (token, puerto, límites), instalación de agentes del registro (descargas, sha256, permisos de archivos), elicitation (URLs), extensiones y marketplaces, secretos en perfiles y en el log, y el export. Informe con hallazgos ordenados por gravedad y una tarea por hallazgo.

### Revisión de patrones de Godot · Pendiente

**Prioridad:** media · **Tamaño:** L · **Etiquetas:** `revision`, `patrones`

Revisar el GDScript del addon contra los patrones de Godot 4: ciclo de vida de nodos y RefCounted (ciclos de referencias como el del crash de 4.8), await y señales que sobreviven al nodo, call_deferred, @tool y recarga de scripts en caliente, Resources compartidos, Window/AcceptDialog y layout (wrap_controls, autowrap), y rendimiento en el editor. Informe y una tarea por hallazgo.

### Revisión de arquitectura · Pendiente

**Prioridad:** media · **Tamaño:** L · **Etiquetas:** `revision`, `arquitectura`

Revisar la estructura del addon: el tamaño y las responsabilidades de session_controller.gd, plugin.gd y agent_dock.gd, el acoplamiento entre sesión, dock y plugin, dónde vive el estado (EditorSettings, project_config.tres, user://), cómo se suman agentes nuevos (Claude, Antigravity, Codex) sin ramas por nombre, y la cobertura de tests por capa. Informe con propuestas y una tarea por cambio.
