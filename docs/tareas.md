# Tareas — agent-harness

> Export de `compass/`, que es la fuente de verdad. No editar: los cambios se hacen en `compass/` o con `scompass`, y este archivo se regenera.
> Generado: 2026-11-11

## M0 — Esqueleto y decisiones  (6/6)

Estructura de carpetas y clases decidida con las skills; plugin que agrega y quita dock, panel inferior y main screen; el addon nunca llega a un export.

**Hecho cuando:**
- Habilitar y deshabilitar el plugin 5 veces seguidas sin errores en Output.
- `tests/export_check.gd` pasa con el plugin habilitado y también deshabilitado (con el filtro del preset).

### 0.2 plugin.cfg y plugin.gd con dock, panel inferior y main screen · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** S · **Responsable:** Claude

EditorPlugin que agrega y quita el dock "Agent" vacío, el panel inferior "Agent Log" y la main screen "Agent" sin errores ni leaks al deshabilitar (spec §9, §15).

**Prueba:** godot --headless --path . --script tests/plugin_cycle_check.gd → PASS en 4.8-beta1, 4.7.2 y 4.4.1 (5 ciclos, sin huérfanos ni errores).

**Notas:** 4.8 deprecó _has_main_screen/add_control_to_dock/bottom_panel en favor de add_dock(EditorDock); con _has_main_screen 4.8-beta1 deja un EditorDock huérfano por ciclo. ui/editor_surfaces.gd elige EditorDock o API vieja por superficie (D9). Falta verificar a ojo en el editor con ventana que la main screen "Agent" aparece en 4.8 (headless no lo muestra).

### 0.6 Verificar M0 y escribir docs/progress.md · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** S · **Responsable:** Claude

Habilitar/deshabilitar el plugin 5 veces sin errores, correr el test de export en ambos escenarios, pasar godot-code-review sin hallazgos altos, y dejar en docs/progress.md qué quedó, cómo probarlo a mano y qué falta.

**Prueba:** run_all, plugin_cycle_check y export_check PASS en 4.8-beta1, 4.7.2 y 4.4.1. Capturas con ventana en 4.8 y 4.4: main screen Agent, Agent Log y dock presentes.

**Notas:** docs/progress.md tiene qué quedó, cómo probar a mano y pendientes. Revisión con godot-code-review: sin hallazgos altos; se arreglaron parámetros sin usar en el export plugin y el banner que no se refrescaba con el dock ya visible. Pendiente: link al artifact de diseño (spec §9) para M1.

### 0.5 Test headless de export (tests/export_check.gd) · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** M · **Responsable:** Claude

Exporta un preset de prueba como .zip con --export-pack, lo abre con ZIPReader y falla si encuentra archivos de addons/godot_agent/ o el autoload de playtest en project.binary. Debe pasar con el plugin habilitado y deshabilitado (con filtro).

**Prueba:** godot --headless --path . --script tests/export_check.gd → PASS (4 escenarios) en 4.4.1, 4.7.2 y 4.8-beta1.

**Notas:** Proyectos temporales en user://export_check/<escenario>. Incluye un escenario de control (plugin off, sin filtro) que tiene que detectar el addon, para que el test no pase por no mirar. El huérfano se escribe después del --import porque el plugin lo limpia al cerrar. Runner unitario: tests/run_all.gd + tests/unit/test_case.gd.

### 0.4 Botón "Agregar a los presets" (filtro de exclusión) · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** media · **Tamaño:** S · **Responsable:** Claude

Red de seguridad para exports con el plugin deshabilitado: agregar addons/godot_agent/* al exclude_filter de cada preset en export_presets.cfg, previa confirmación. Aviso visible (en M0 desde el dock; Settings llega en M7).

**Prueba:** tests/unit/test_export_presets_patcher.gd (5 tests) + prueba manual 5 de docs/progress.md.

**Notas:** Banner en el dock (Settings llega en M7). Edita export_presets.cfg con ConfigFile previa confirmación; pide reiniciar el editor porque los presets viven en memoria y el diálogo de Export puede pisar el cambio (D6). El dock relee el archivo cada 2 s si cambió su mtime. Falta probar el banner a mano en el editor con ventana.

### 0.3 EditorExportPlugin: excluir addon y limpiar autoload huérfano · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** S · **Responsable:** Claude

_export_file llama a skip() para todo bajo res://addons/godot_agent/. En _export_begin, si el autoload de playtest sigue registrado, error claro y quitarlo; verificar si afecta al export en curso y documentarlo (spec §2).

**Prueba:** tests/export_check.gd: escenarios plugin_on_sin_filtro y plugin_on_autoload_huerfano PASS en 4.4.1, 4.7.2 y 4.8-beta1.

**Notas:** D10: el editor ordena los export plugins por nombre y corta la cadena en el primer skip/remap; el de GDScript remapeaba .gd→.gdc antes que el nuestro → _get_name() = "!GodotAgentExcludeAddon". project.binary se genera al final, así que quitar el autoload en _export_begin sí afecta al export en curso, pero remove_autoload_singleton no borraba la entrada en ese momento: unregister() la borra a mano si sigue. Rastros aceptados (D8): uid_cache.bin y editor_plugins/enabled.

### 0.1 Cargar skills y proponer estructura en docs/decisions.md · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** M · **Responsable:** Claude

Cargar godot-architecture, godot-communication, godot-patterns, godot-code-review y godot-data-driven; proponer estructura de carpetas bajo res://addons/godot_agent/ y la lista de clases. Registrar los choques skill↔spec y las verificaciones de API (execute_with_pipe en 4.4, tags de editor) en docs/decisions.md.

**Prueba:** docs/decisions.md tiene D1–D9: estructura, sin class_name, composición, API verificada en 4.4.1/4.7.2/4.8-beta1, settings por proyecto, presets, test de ciclo, uid_cache y docks.

**Notas:** Binarios: 4.8-beta1 en /opt/godot/versions/4.8-beta1/godot (dev), 4.7.2 en PATH, 4.4.1 oficial bajado al scratchpad solo para verificar. Hallazgos: en 4.4 el export filtra la carpeta pero deja class_name y rutas en global_script_class_cache.cfg/uid_cache.bin → addon sin class_name (preload consts). read_string_from_stdin(buffer_size) no tiene default en 4.4. editor_runtime existe en 4.4.

## M1 — Transporte y ACP mínimo  (14/14)

AgentProcess + AcpClient + SessionModel y agente falso: initialize → session/new → session/prompt con streaming al dock, y session/cancel. Agent Log con canales. QuotaMonitor en modo observación (canal quota).

**Hecho cuando:**
- Contra el agente falso: un prompt, una respuesta en streaming y una cancelación limpia.
- Contra Claude Code real: "hola" recibe respuesta y la verificación de cuota (qué reporta el adapter y cómo se ve un error de límite) está documentada en docs/decisions.md.

### 1.13 Verificar qué cuota reporta el adapter de Claude Code · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** S · **Responsable:** Claude · **Etiquetas:** `quota`

Spec M1 (actualizado): con el adapter real (@agentclientprotocol/claude-agent-acp), documentar en docs/decisions.md qué reporta realmente: cuota del plan con hora de reinicio, solo tokens de la sesión, o nada; y cómo se ve un error de límite. Fuentes: el canal quota de una sesión real y el código del adapter. El diseño de §10.1 (nombres de campo y patrones de límite) se ajusta a eso. Criterio de M1: "hola" recibe respuesta y la verificación de cuota está documentada.

**Prueba:** `$G --headless --path . --script tests/claude_smoke_check.gd -- "hola"` con Claude Code real (4.8-beta1): respondió y el canal quota mostró "cuota del plan: allowed · five_hour · reinicio 2026-10-21 05:40:00 · five_hour 63 % hasta … · seven_day 47 % hasta …", con el JSON crudo. Documentado en docs/decisions.md D22.

**Notas:** - Cuota: `usage_update._meta["_claude/rateLimit"]` (SDKRateLimitInfo) con status allowed/allowed_warning/rejected, resetsAt en unix segundos y `unifiedWindows.five_hour/seven_day` con utilization 0–1. `unifiedWindows` no está en el .d.ts pero llega.
- Límite (del código; no se puede provocar): mensaje sintético con prefijo "You've hit your…" y error -32603 de session/prompt con data.errorKind.
- La extensión sessionFailure es de JetBrains AIR y no se anuncia.
- El diseño de §10.1 no cambia: ventana actual = five_hour, semanal = seven_day.

**Bloquea a:** 1.14 Agente falso: cuota simulada y errores de límite; 6.6 QuotaMonitor: fuentes, estados y umbrales

**Bloqueada por:** 1.12 QuotaMonitor en modo observación (canal quota)

**Relacionadas:** 1.11 Verificar M1 contra el agente falso y Claude Code real

### 1.12 QuotaMonitor en modo observación (canal quota) · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** S · **Responsable:** Claude · **Etiquetas:** `quota`

Spec §10.1 y M1 (actualizado): QuotaMonitor nuevo en la arquitectura. En M1 solo observa: loguea crudo en un canal nuevo `quota` del Agent Log cada `usage_update` de ACP y cualquier aviso o error de límite (error JSON-RPC en session/prompt, notice o mensaje del agente). Guarda el último payload crudo para mapear los campos después. No estima cuota a partir de tokens, no consulta endpoints no documentados y no lee archivos internos ni credenciales del agente.

**Prueba:** tests/unit/test_quota_monitor.gd (4 tests), en 4.8-beta1 y 4.4.1:
- usage_update sin `_meta` → "sin datos de cuota";
- con `_meta["_claude/rateLimit"]` → guarda el SDKRateLimitInfo crudo y loguea "allowed_warning · five_hour · 82 % · umbral 75 % · reinicio …";
- texto "You've hit your limit · resets 3pm" → evento de límite; la prosa con "rate limiting" no;
- error de prompt con errorKind rate_limit → límite, y todos los errores de prompt quedan en el canal.

**Notas:** core/quota_monitor.gd, con patrones editables en config/quota_patterns.txt: los prefijos USAGE_LIMIT_ERROR_PREFIXES del SDK de Claude, anclados al principio de línea y sin patrones sueltos. Canal `quota` nuevo en AgentLog (color amarillo). SessionController le pasa cada usage_update, el texto del agente de cada turno y los errores de session/prompt. Todavía no expone estados al SessionModel: eso es m6-06.

**Bloquea a:** 1.13 Verificar qué cuota reporta el adapter de Claude Code

### 1.10 Tests unitarios de transporte y sesión · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** S · **Responsable:** Claude

Framing de líneas JSON (partidas, varias por lectura), correlación de ids, requests entrantes y -32601, merge de chunks y variantes desconocidas en SessionModel (spec §13).

**Prueba:** run_all: 19 tests, 79 checks, 0 fallos en 4.4.1, 4.7.2 y 4.8-beta1.

### 1.11 Verificar M1 contra el agente falso y Claude Code real · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** S · **Responsable:** Claude

Prueba de integración headless: prompt, respuesta en streaming y cancelación limpia contra fake_agent. Contra Claude Code real: "hola" recibe respuesta. Actualizar docs/progress.md.

**Prueba:** Contra el agente falso: acp_session_check.gd y el ui-test. Contra Claude Code real: tests/claude_smoke_check.gd mandó "hola", recibió "¡Hola! Estoy dentro del editor de Godot…" con end_turn y no quedó ningún proceso vivo.

**Notas:** docs/progress.md (sección M1) y decisions.md D11–D14.

**Relacionadas:** 1.13 Verificar qué cuota reporta el adapter de Claude Code

### 1.7 Dock: header, modos, lista de mensajes y composer · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** L · **Responsable:** Claude

Según docs/design (pantalla 1): selector de perfil, título de sesión, historial/nueva sesión/ajustes, selector de 4 modos, burbujas de usuario, texto del agente en RichTextLabel (Markdown→BBCode mínimo), thoughts colapsados, composer con enviar/detener, Ctrl+Enter y Esc. Acento único configurable (#f0a85a).

**Prueba:** `$G -e --path . -- --godot-agent-ui-test=ui_demo --godot-agent-ui-shot=x.png` con el guion ui_demo. Captura revisada en 4.8-beta1 y 4.4.1: burbuja, thought colapsado, Markdown, plan, tool calls con diff, medidor 41k/200k y selector Opus. Prueba manual en docs/progress.md (M1).

**Notas:** ui/dock/:
- agent_dock.gd/.tscn;
- conversation_view.gd: pull + push, tope de 250 vistas, sigue el fondo;
- composer.gd: CodeEdit con completado de / y @, chips, Ctrl+Enter, Esc;
- entries/: user, agent/thought, notice, tool_group, diff_card, plan.

También ui/agent_theme.gd, ui/editor_context.gd y ui/markdown/markdown_bbcode.gd (con test).

Historial deshabilitado hasta M7.

### 1.9 Flujo de sesión: initialize → session/new → prompt → cancel · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** M · **Responsable:** Claude

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

### 1.5 Perfiles de agentes y HarnessSettings · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** S · **Responsable:** Claude

Perfiles (id, display_name, command, args, env, default) en EditorSettings godot_agent/. Perfil Claude Code con el adapter ACP verificado con npm view; Gemini/Codex/custom editables sin flags inciertos. Aviso si hay ANTHROPIC_API_KEY en el entorno (spec §4.4, §11).

**Prueba:** Al habilitar el plugin aparecen godot_agent/agents/profiles y ui/accent_color en Editor Settings. El botón de ajustes del dock edita los perfiles como JSON y valida que los ids sean únicos. Con ANTHROPIC_API_KEY en el entorno, al iniciar sesión aparece un aviso.

**Notas:** core/agent_profile.gd y core/harness_settings.gd (EditorSettings, o memoria en tests).
- Perfil por defecto: npx -y @agentclientprotocol/claude-agent-acp, verificado con npm view (D13).
- En env, "$VAR" se resuelve del entorno del editor, así no se guardan claves.
- Gemini y Codex quedan como entradas editables.
- ui/settings/profiles_dialog.gd es un stub hasta M7.

### 1.2 AgentProcess: lanzar el agente y leer stdout/stderr en threads · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** M · **Responsable:** Claude

OS.execute_with_pipe con el comando del perfil; Thread lector de stdout línea por línea y otro de stderr; send_line(String); señales line_received, stderr_received y exited(code) vía call_deferred. Mata el proceso al deshabilitar el plugin o cerrar el editor (spec §3, §15).

**Prueba:** tests/acp_session_check.gd lanza el agente falso como proceso real y pasa los escenarios basic, cancel y crash (32 checks) en 4.4.1, 4.7.2 y 4.8-beta1. El proceso queda muerto después de stop().

**Notas:** addons/godot_agent/transport/:
- agent_process.gd: hay threads para stdout, stderr y un watcher de salida. El exit se emite después de la última línea de stdout.
- process_tree.gd: mata el árbol de procesos con pgrep -P / taskkill /T. Además se recuerdan los hijos, porque npx deja huérfano a node.
- command_resolver.gd: busca el comando en PATH y en las carpetas de fnm, nvm, volta y similares, y agrega la carpeta del ejecutable al PATH del hijo.

Bug en Godot 4.4.x, corregido en 4.5 (verificado con 4.5.1 y 4.6): cerrar o liberar el FileAccess de un pipe de execute_with_pipe cierra fds equivocados, incluso el fd 0, y el siguiente proceso muere con SIGPIPE. Workaround: en 4.4 los pipes viejos se retienen en un array estático (pipe_close_is_broken). Anotar en D11.

OS.is_process_running da error con pids que no son hijos directos o que ya fueron cosechados.

### 1.3 AcpClient: JSON-RPC 2.0 sobre líneas · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** M · **Responsable:** Claude

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

### Conseguir el mockup de UI (artifact de diseño, 4 pantallas) · Hecho

**Terminada:** 2026-10-21 · **Prioridad:** alta · **Tamaño:** S

La spec §9 pide respetar la estructura de un mockup de 4 pantallas (dock, main screen One-shot, Agent Log, revisión en Script Editor). Hay un artifact con el diseño, pero no aparece entre los artifacts listables desde esta cuenta: pedir el link al usuario y leerlo antes de construir la UI del dock en M1.

**Prueba:** docs/design/mockup/ tiene los 4 .dc.html + canvas.json; docs/design/README.md resume cada pantalla.

**Notas:** Link del usuario: https://claude.ai/chat/f88dea66-401f-4ccc-92af-c85b98fcf7d1?artifact=c94c1e9f-2037-475f-830c-e0671d0ef62d (Design artifact; el contenido está en project/*.dc.html, no en la página). Diferencias con la spec anotadas en el README: paquete del adapter (npx @agentclientprotocol/claude-agent-acp, a verificar con npm view en M1), sidecar .sh de ejemplo, severidades y Settings en Project Settings.

### 1.4 SessionModel: estado de la conversación · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** M · **Responsable:** Claude

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

### 1.6 Agente falso en GDScript (tests/fake_agent.gd) · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** M · **Responsable:** Claude

Corre con godot --headless --script, lee stdin con OS.read_string_from_stdin y responde ACP según un guion JSON en tests/scripts/*.json: chunks, tool calls con diff, pedidos de permiso, plan, errores, cancelación (spec §13).

**Prueba:** Manual: el comando `godot --headless --no-header --path . --script res://tests/fake_agent.gd -- --scenario=res://tests/scripts/basic.json` responde initialize, session/new y prompt. Lo usa tests/acp_session_check.gd.

**Notas:** Guiones en tests/scripts/: basic.json, cancel.json y crash.json.
- Pasos: chunk, thought, update, delay, request, garbage, stop, error y exit.
- quit() no termina el proceso mientras un thread está bloqueado en stdin. Por eso "exit" se mata a sí mismo (OS.kill) y un EOF en stdin termina el proceso.
- Ojo con el shim stdio de M3: le pasa lo mismo.

### 1.8 Agent Log: canales, filtros, copiar y modo raw · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** M · **Responsable:** Claude

Modelo AgentLog acotado (ring buffer) con canales acp/mcp/fs/perm/proc/cmp; panel con columnas hora · canal · mensaje en mono, filtros por canal, botón copiar y modo raw con los JSON-RPC completos (spec §9.3).

**Prueba:** La captura de ui_demo muestra el Agent Log con los canales coloreados. "Ver log" (desde el aviso de error) abre el panel con EditorSurfaces.make_visible.

**Notas:** El panel está en ui/log_panel/agent_log_panel.gd/.tscn y el modelo en core/agent_log.gd.
- El modelo es un ring buffer de 2000 entradas. Guarda el raw de cada entrada, hasta 20k caracteres.
- El panel muestra el raw recortado a 4000.
- Los canales son acp, mcp, fs, perm, proc y cmp. El stderr del agente va al canal proc.

### 1.14 Agente falso: cuota simulada y errores de límite · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** media · **Tamaño:** S · **Responsable:** Claude · **Etiquetas:** `quota`

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

## M2 — Tool calls, diffs y permisos  (10/10)

Render de tool_call/tool_call_update, tarjeta de diff y plan; session/request_permission con PermissionPolicy; fs/read_text_file y fs/write_text_file con sincronización editor ↔ disco.

**Hecho cuando:**
- Pedirle a Claude Code que edite un script abierto: el diff se muestra, el permiso se pide en Construir y se auto-deniega en Preguntar, y el editor muestra el cambio sin diálogos ni pérdida de buffer.

### Modo Auto: probar un comando contra las reglas desde Settings · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** baja · **Tamaño:** S

Pedido del usuario (2026-10-22), sigue a m2-09 (D57). Hoy, para saber si un comando de shell corre solo o pregunta en Auto, hay que esperar a que el agente lo use y mirar el Agent Log.

En Settings → Permisos → «Modo Auto: comandos de shell», un campo donde se escribe un comando y muestra al momento el resultado de ShellRules.classify con las reglas que se están editando (todavía sin guardar): corre / pregunta, la regla que decidió y el motivo (parte fuera de la allowlist, redirección, sustitución…). Si se puede, marcar en la tabla la regla que decidió.

Tests: unitario si hace falta lógica nueva, y el check del editor de Auto (--godot-agent-auto-test) usando el campo.

**Prueba:** test_shell_rules: código y segmento de cada tipo de decisión (permitido, lista ask, fuera de la allowlist, sustitución, sustitución de procesos, redirección, comilla, vacío) y el texto del resultado. --godot-agent-auto-test: con la regla agregada desde la tarjeta, «ls && npm test --watch» corre sin preguntar con las dos reglas, la fila se resalta, y «git push origin main» pregunta; captura revisada. Suite completa verde en 4.8-beta1 y 4.6.3, i18n incluido.

**Notas:** Commit 21c6977, ya en main (vino de la rama auto-rule-tester). Durante el desarrollo, un scroll_to_item diferido con un TreeItem ya borrado tiró el editor; ahora el scroll es directo al final del refresh. Esa caída dejó un project_config.tres en el worktree (el check no llegó a restaurarlo); se borró a mano.

### Modo Auto: chat sin pedir permiso, shell clasificada por listas revisables · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** media · **Tamaño:** M · **Etiquetas:** `permisos`

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

### 2.8 Verificar M2 · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** S · **Responsable:** Claude

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

### 2.1 Render de tool calls en el dock · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** M · **Responsable:** Claude

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

### 2.7 Prompt de sistema y contexto del prompt · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** media · **Tamaño:** S · **Responsable:** Claude

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

### 2.6 Sincronización editor ↔ disco · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** L · **Responsable:** Claude

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

### 2.5 fs/read_text_file y fs/write_text_file · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** M · **Responsable:** Claude

Leer devuelve el buffer del Script Editor si el archivo está abierto con cambios sin guardar (soporta line/limit). Escribir pasa por la política (edit_files) y la sincronización de §8. Rechazar rutas fuera del proyecto salvo directorios extra.

**Prueba:** Lo cubren:
- tests/unit/test_fs_handler.gd: rutas fuera del proyecto, .., relativas y .godot/; line/limit; prefiere el buffer; escritura denegada;
- acp_session_check: write y read reales a través del agente falso.

**Notas:** acp/fs_handler.gd no depende del editor.
- buffer_reader = EditorSync.buffer_text (el buffer solo se usa si tiene cambios sin guardar).
- after_write = EditorSync.after_agent_write.
- Las rutas extra salen de ProjectConfig.extra_fs_roots.
- Escribir .uid o .import se permite, pero queda un aviso en el log.

### 2.4 session/request_permission con tarjeta de permiso · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** M · **Responsable:** Claude

Consultar PermissionPolicy: allow/deny se responden solos eligiendo la opción adecuada; ask crea un pedido en SessionModel y la tarjeta muestra las opciones del agente como botones. Respuesta selected/cancelled. Canal perm en el log.

**Prueba:** acp_session_check, con el guion tests/scripts/permissions.json:
- En Construir aparecen dos tarjetas (edición y comando).
- "Siempre en esta sesión" se responde al agente como allow_once y la segunda edición se permite sola.
- En Preguntar, todo se auto-deniega sin tarjeta y con aviso.

**Notas:** El handler está en session_controller._on_request_permission y la tarjeta en ui/dock/entries/permission_view.gd.
- Un permiso de edición concedido preautoriza, durante 2 minutos, el fs/write_text_file que le sigue al mismo archivo. Así no hay doble tarjeta: el adapter pide permiso y después escribe por fs/*.
- SessionController.authorize(group, title, desc, diff, timeout) queda listo para las tools MCP de M3.
- Al cancelar el turno, los permisos pendientes se responden como cancelled.

### 2.3 PermissionPolicy con matriz configurable · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** S · **Responsable:** Claude

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

### 2.2 Tarjeta de diff y plan colapsable · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** S · **Responsable:** Claude

Tarjeta de diff: ruta, +N/−M, primeras líneas coloreadas y "Abrir en Script". Plan: reemplazo completo en cada update, estados por entrada, colapsable.

**Prueba:** - tests/unit/test_line_diff.gd: igualdad, alta, baja, reemplazo, conteos y first_changed_line.
- test_session_model: el plan reemplaza y se re-ubica (entry_removed).
- Captura de la UI con ui_demo.json: tarjeta de diff y plan visibles.

**Notas:** Adelantado en M1:
- entries/diff_card.gd con core/line_diff.gd (LCS);
- entries/plan_view.gd, que se re-ubica al final si el agente lo reemplaza.

El test de line_diff se agregó después (tests/unit/test_line_diff.gd).

## M3 — Servidor MCP y tools de lectura  (9/9)

McpServer con token, initialize, tools/list y tools/call; tools read y diagnostics; fallback del shim stdio.

**Hecho cuando:**
- Claude Code lista las tools `godot.*` y responde "¿cuántos nodos tiene Main.tscn?" usando `scene_tree`.
- Tests del parser HTTP con requests partidos y concatenados.

### Tool genérica con descubrimiento cuando crezcan las tools · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** baja · **Tamaño:** M · **Etiquetas:** `swallowtail`

Como godot_run + engine.commands de swallowtail. Cada tool MCP suma su descripción al contexto del agente en cada turno. Con las tareas de swallowtail la lista crece mucho. Mantener un núcleo de tools tipadas (lectura, edición de escenas, ejecución) y exponer el resto por una tool genérica godot.run(method, params), más una tool que lista los métodos disponibles con sus parámetros. Medir el tamaño de tools/list antes y después. Los permisos se siguen aplicando por método.

**Decisiones:**
- ✓ Lista compacta activada por defecto: núcleo tipado (lectura, diagnóstico, edición de escenas, run_scene/stop_scene/capture_game_frame) más godot.methods y godot.run; API, proyecto, archivos, recursos, tilemaps, animación y game_* pasan a extendidas
  Por qué: tools/list baja de 29.978 a 11.232 caracteres (−63 %) en cada turno; lo de todos los turnos queda tipado y lo puntual se descubre con methods. Permisos, validación y log siguen por método, y llamar por nombre directo sigue funcionando (D56)
  Descartado: Desactivada por defecto; un solo godot_run para todo, sin núcleo tipado; dejar class_info/search_api en el núcleo; mover también la edición de escenas a extendidas

**Prueba:** run_all (test_tool_registry: lista compacta, methods con filtro y detalle, run con validación y permiso del grupo del método; test_session_model: ToolCall desenvuelve run) 197/0 en 4.8-beta1 y 4.6.3; --godot-agent-mcp-test por HTTP (lista sin extendidas, methods, run(class_info), llamada directa) PASS en 4.8-beta1 y 4.6.3; edit-test y run-test PASS en 4.8-beta1 con compacto activo.

**Notas:** Commit 07a1d14 en swallowtail-tools (D56). Medido: completo 55 tools / 29.978 caracteres → compacto 26 tools / 11.232 (−63 %); la salida de methods sin filtro son 5.359 caracteres, solo cuando se pide. Setting compact_tools en Settings → Servidor MCP (default activado; vale desde la próxima sesión). ToolCall.godot_tool_name()/godot_arguments() desenvuelven run, así el deshacer de la tarjeta y el conteo del One-shot ven la tool real. El prompt de sistema explica que una tool nombrada que no está en la lista se usa vía methods/run.

### Consultar la API del motor · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** media · **Tamaño:** S · **Etiquetas:** `swallowtail`

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

### 3.7 Verificar M3 · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** S · **Responsable:** Claude

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

### 3.6 Conectar el MCP en session/new y shim stdio · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** S · **Responsable:** Claude

Entrada http con header Authorization si mcpCapabilities.http; si no, shim stdio→HTTP en GDScript (godot --headless --script mcp_stdio_shim.gd con puerto y token por env).

**Prueba:** - mcp-test: el shim, lanzado con AgentProcess, responde initialize y tools/call editor_state, y no responde a notifications/initialized. Pasa en 4.4.1, 4.7.2 y 4.8.
- Con Claude real se usó la entrada http (el adapter anuncia http: true).

**Notas:** plugin._mcp_servers():
- si el agente anuncia mcpCapabilities.http, va una entrada http con el header Authorization;
- si no, StdioShimInstaller.server_entry, con OS.get_executable_path() y el shim copiado a user://godot_agent_mcp_shim con su propio project.godot (D17); URL y token por env.

mcp/mcp_stdio_shim.gd: un thread hace stdin → POST → stdout en orden y no escribe nada para las notificaciones (202). Mantiene el Mcp-Session-Id y reconecta. Si el server devuelve un error HTTP en un request, responde un error JSON-RPC.

### 3.5 Tools de diagnóstico · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** M · **Responsable:** Claude

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

### 3.4 Tools de lectura · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** M · **Responsable:** Claude

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

### 3.3 ToolRegistry y base de tools · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** M · **Responsable:** Claude

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

### 3.2 McpServer: TCPServer en 127.0.0.1 con token · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** M · **Responsable:** Claude

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

### 3.1 Parser HTTP/1.1 mínimo · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** S · **Responsable:** Claude

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

## M4 — Tools de edición y ejecución  (13/13)

Grupos edit_scene, edit_files y run con undo; run_scene con captura de errores, autoload de playtest con su ciclo de vida, capture_game_frame e inputs simulados.

**Hecho cuando:**
- "Agregá un Label WaveLabel al HUD y conectá la señal X": aparece en el árbol, Ctrl+Z lo deshace en pasos y `run_scene` devuelve errores reales con un script roto.
- Tras un `run_scene`, un run manual y matar el editor a mitad de un playtest, el autoload no queda en `project.godot` y el test de export sigue pasando.

### Recursos .tres: crear, leer y editar · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** media · **Tamaño:** M · **Etiquetas:** `swallowtail`

Como resource.* de swallowtail. Crear un recurso (built-in o de un script con class_name) con sus propiedades, leerlo y editarlo a través del editor, y asignarlo a un nodo. Es lo que pide el diseño data-driven (valores ajustables en Resources). Hoy el agente escribe los .tres a mano. Con las tools, el harness puede rechazar también los .tres escritos a mano (extensión de D48).

**Prueba:** `test_resource_values` (StyleBoxFlat inline con hint, error con tipo que no cumple, class_name FixtureLoot con Array[FixtureItem] que sigue tipado, describe sin defaults) y `test_project_write_guard` (.tres a mano). `--godot-agent-edit-test` en 4.8-beta1 y 4.6.3: create_resource FixtureLoot con items inline (uno con StyleBoxFlat inline) y weights; get_resource muestra `[0] <FixtureItem, inline>`, bg_color y weights sin defaults; set_resource_properties guarda y Ctrl+Z revierte y vuelve a guardar; panel.tres asignado por ruta y luego un StyleBoxFlat inline con set_properties; add_nodes con un class_name sin @tool; no pisa. Suite: 192 tests, 0 fallos.

**Notas:** Commit 5b19448 (rama swallowtail-tools). D51 en docs/decisions.md.
- `mcp/tools/resource_tools.gd`: `get_resource` (read), `create_resource` y `set_resource_properties` (edit_files). Para asignar a un nodo: `set_properties` con la ruta res:// o inline.
- ValueCoercion: recursos inline `{"type": …}` contra el hint, y arrays tipados elemento por elemento (sirve en set_properties y add_nodes).
- Arreglo de paso: en el editor, `script.new()` falla para class_name sin @tool. Ahora se instancia la base nativa y se pone el script (como el Inspector). `add_node` con un class_name de nodo también fallaba por eso.
- Guard: `.tres` a mano se rechaza.
- Fixtures nuevos con class_name: tests/fixtures/resources/ (FixtureItem, FixtureLoot, FixtureEnemy).

**Relacionadas:** El agente no escribe el proyecto por fuera del editor

### Tools de animación · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** media · **Tamaño:** M · **Etiquetas:** `swallowtail`

Como animation.* (y más adelante animtree.*) de swallowtail. Crear animaciones en un AnimationPlayer, agregar pistas y keyframes, leer y borrar, con deshacer; también SpriteFrames para AnimatedSprite2D. Hoy set_properties no llega a pistas ni keyframes, y el agente anima por código o escribe la biblioteca a mano.

**Prueba:** `--godot-agent-edit-test` en 4.8-beta1 y 4.6.3: animation_create (length, loop linear, autoplay); animation_set_track de position (3 keys, continuous), modulate con colores y una pista de método; key fuera del largo y propiedad inexistente → error; animation_get con keys; Ctrl+Z quita la pista de método; animation_remove de una pista y de la animación (con su autoplay), y Ctrl+Z la restaura; sprite_frames_set desde una hoja (AtlasTexture, autoplay, sin la animación default), reemplazo de cuadros y Ctrl+Z; animation_get de un AnimatedSprite2D.

**Notas:** Commit 4dd9bbf (rama swallowtail-tools). D53 en docs/decisions.md.
- `mcp/tools/animation_tools.gd`: animation_get (read); animation_create, animation_set_track, animation_remove, sprite_frames_set (edit_scene), con el botón «↶ undo» del chat.
- Undo: copia editada de la animación cambiada en su AnimationLibrary; SpriteFrames restaurado cuadro por cuadro. Bibliotecas/SpriteFrames en .tres propios se guardan al hacer y al deshacer.
- Fuera por ahora: AnimationTree (animtree.* de swallowtail, la descripción dice "más adelante"), pistas bezier, de audio y 3D.

### Tools de tilemaps · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** media · **Tamaño:** M · **Etiquetas:** `swallowtail`

Como tilemap.* de swallowtail. Para TileMapLayer y TileSet: crear la capa, agregar fuentes de atlas o de escenas, poner celdas, rellenar rectángulos, pintar con terrenos, leer celdas y las usadas, limpiar. Todo con deshacer. tile_map_data no se puede escribir a mano, y sin tools el agente arma los niveles desde código. Sirve para construir niveles en Construir y One-shot (p. ej. el Megaman de great-boy-one).

**Prueba:** `--godot-agent-edit-test` en 4.8-beta1 y 4.6.3: TileMapLayer con TileSet inline vía add_node; tileset_add_atlas de una textura 48×16 crea 2 tiles (el transparente no) con colisión y capa de física; tilemap_set_cells con rect y celdas sueltas (una con otro atlas); tile inexistente → error; tilemap_get muestra 12 celdas, la fila `3 aaaaaaaaaa`, la leyenda y la capa de física; Ctrl+Z deshace un set; erase; clear y su Ctrl+Z; paint_terrain sin terrenos → error que explica; con un terreno armado, pinta 3×3 por nombre; sobre un Timer → error.

**Notas:** Commit 11ec564 (rama swallowtail-tools). D52 en docs/decisions.md.
- `mcp/tools/tilemap_tools.gd`: tilemap_get (read); tileset_add_atlas, tileset_add_scenes, tilemap_set_cells, tilemap_paint_terrain, tilemap_clear (edit_scene). Usan el botón «↶ undo» del chat, como las demás tools de escena.
- La capa se crea con add_node/add_nodes (tile_set inline gracias a D51).
- Deshacer de celdas: tile_map_data antes/después. Un TileSet .tres se guarda al hacer y al deshacer.
- Fuera por ahora: configurar terrenos (peering bits). Se pinta con los que ya tenga el TileSet.

### Mover, copiar y borrar archivos arreglando referencias · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** media · **Tamaño:** M · **Etiquetas:** `swallowtail`

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

### Project settings por el editor: input map, autoloads y settings · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** M · **Etiquetas:** `swallowtail`

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

### Armar escenas en lote · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** M · **Etiquetas:** `swallowtail`

Como batch.addnodes y node.duplicate de swallowtail. Una tool que crea un subárbol entero (nodos anidados con tipos, propiedades, scripts e instancias) en una llamada y un solo paso de deshacer, y otra que duplica un nodo con sus hijos. Hoy cada nodo es un add_node: escribir el .tscn a mano era más corto, y D48 lo bloquea. Sirve en cualquier modo que edite escenas.

**Prueba:** `--godot-agent-edit-test` en el editor real (4.8-beta1 y 4.6.3): add_nodes arma HUD (CanvasLayer > Label, HBox con script nuevo > Button + escena instanciada) y un Marker2D, con owners, grupos, propiedades y script; un Ctrl+Z lo saca entero; un item inválido anidado no crea nada y el error dice la ruta (Bad/X). duplicate_node copia Player con Sprite, grupo, script y posición al lado del original; Ctrl+Z la saca; con new_name/new_parent va bajo Enemies.

**Notas:** Commit 36ebd0a (rama swallowtail-tools).
- `add_nodes(parent, nodes, scene?)`: items {name, type | scene, properties?, script?, groups?, children?}. Arma todo fuera del árbol, valida antes de tocar la escena (todo o nada) y lo aplica en una acción de EditorUndoRedo. Tope de 200 nodos por llamada.
- `duplicate_node(node_path, new_name?, new_parent?)`: Node.duplicate con señales, grupos, scripts e instanciación; restaura owners por ruta relativa; nombre libre Player2, Player3…
- System prompt: add_nodes para subárboles nuevos.
- Hallazgo aparte: los checks del editor que se cortaban por un error de script devolvían null y daban "PASS: 0 fallas". En el worktree pasaba porque `tests/tmp/` (ignorado por git) no existía. Ahora un corte cuenta como falla y el plugin de dev crea `tests/tmp`.

**Relacionadas:** El agente no escribe el proyecto por fuera del editor

### Inspeccionar y controlar el juego en ejecución · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** L · **Etiquetas:** `swallowtail`

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

### 4.6 Verificar M4 · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** M · **Responsable:** Claude

"Agregá un Label WaveLabel al HUD y conectá la señal X": aparece en el árbol, Ctrl+Z lo deshace en pasos; run_scene devuelve errores reales con un script roto. Tras run_scene, run manual y editor matado a mitad de un playtest, el autoload no queda en project.godot y export_check sigue pasando.

**Prueba:** - Claude Code real (`tests/run_in_xvfb.sh $G --godot-agent-claude-scene-test`, 4.8 y 4.4.1): agregó WaveLabel bajo HUD con add_node y conectó WaveTimer.timeout con connect_signal; el primer Ctrl+Z deshizo la conexión y el siguiente el Label; el .tscn en disco no cambió.
- run_scene con un script roto: run_check.gd ("se detuvo en el debugger … queue_free … run_broken.gd").
- Autoload: run_check.gd (después de run_scene, de un juego que terminó solo y de un run manual) y `setsid -w tests/crash_check.sh $G` (editor matado con el autoload recién registrado y con un run en curso; al reabrir no está en project.godot y export_check pasa).
- Suite completa (unit 58/353, acp, export, cycle, sync, ui, mcp, edit, run) en 4.4.1, 4.7.2 y 4.8-beta1.

**Notas:** docs/progress.md (sección M4) y decisions.md D19–D21. El prompt de sistema suma reglas para edición en pasos chicos y para run_scene/capture/stop. Los editores 4.4/4.7 reescriben tests/fixtures/main_fixture.tscn al correr la suite (sin unique_id): se restaura con git checkout, igual que project.godot.

### 4.5 Botón "↶ undo" en los tool calls del dock · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** media · **Tamaño:** S · **Responsable:** Claude

Los tool calls MCP de edición registran su paso de undo; el dock muestra "↶ undo" y lo deshace si sigue siendo el último paso de esa escena (si no, avisa).

**Prueba:** edit_check.gd simula un tool call ACP `mcp__godot__add_node` con rawInput igual a los args; la acción se une a ese tool call (can_undo), y `_undo_tool_call` lo deshace y marca undo_done. Con un cambio posterior en la escena no deshace y avisa con "Hubo cambios posteriores…". Además: permisos (Preguntar deniega con isError; Construir muestra la tarjeta y ejecuta al aceptar).

**Notas:** La unión es por nombre de tool y argumentos (el server MCP no conoce el toolCallId de ACP); las acciones pendientes vencen a los 60 s. Solo deshace si la versión de la historia de la escena y la de la global no cambiaron.

### 4.4 run_scene, stop_scene y capture_game_frame · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** M · **Responsable:** Claude

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

### 4.3 Autoload de playtest y EditorDebuggerPlugin · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** L · **Responsable:** Claude

Canal del debugger con prefijo godot_agent:. El probe captura frames y reproduce inputs {t, action, pressed}. Ciclo de vida: alta en _build() solo si el run lo pidió el harness (u opción en Settings), baja al terminar la sesión de debug o tras stop, limpieza al arrancar (spec §6).

**Prueba:** `tests/run_in_xvfb.sh $G --godot-agent-run-test` (addons/godot_agent_dev/run_check.gd), con el editor en Xvfb y OpenGL. Después de run_scene, de un juego que terminó solo y de un run manual, el autoload no está en ProjectSettings ni en project.godot del disco. Un run manual no lo registra y capture_game_frame responde "sin probe". El probe reproduce los inputs (Output con "ui_accept recibido/soltado") y devuelve un frame rojo. Pasa en 4.4.1, 4.7.2 y 4.8-beta1.

**Notas:** - Alta en EditorPlugin._build() si run_tools.harness_requested (o playtest_on_manual_runs). play_custom_scene llama a _build() de forma sincrónica.
- add/remove_autoload_singleton no guardan project.godot y el juego lo lee del disco, así que PlaytestAutoload.register/unregister llaman a ProjectSettings.save().
- Baja en cuanto arranca la sesión de debug (EditorDebuggerSession.started se emite después de que el juego manda su PID, cuando ya leyó project.godot), y otra vez en stopped, en stop_scene y si el juego no llegó a arrancar. Esto achica la ventana de riesgo a lo que tarda en arrancar el juego.
- Canal godot_agent: playtest/playtest_debugger.gd (EditorDebuggerPlugin) ↔ runtime/playtest_probe.gd. El motivo de una pausa del debugger se lee del panel Stack Trace (la sesión no lo expone).
- 4.7.2: con una variable miembro, el juego reportaba dos "get_node() with absolute paths" en @implicit_new del probe. Sin la variable no pasa, así que el probe queda sin variables miembro (D20).
- Las pruebas que lanzan el juego corren en Xvfb (D21): en el escritorio, la ventana del editor robó el foco y quedó "bil" tipeado en un fixture.

### 4.2 Tools edit_files: create_scene y attach_script · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** S · **Responsable:** Claude

create_scene crea y guarda el .tscn con root_type/root_name; attach_script crea el script si no existe y lo adjunta con undo.

**Prueba:** edit_check.gd: create_scene crea el .tscn y no pisa uno existente (error); attach_script crea el script ("(creado)") y lo adjunta con undo; rechaza un script con una base incompatible; save_scene persiste la instancia y el script. Pasa en 4.4.1, 4.7.2 y 4.8.

**Notas:** Grupo edit_files: en el modo Revisar piden permiso aunque edit_scene esté permitido. create_scene no abre la escena; el agente usa open_scene.

### 4.1 Tools edit_scene con undo · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** L · **Responsable:** Claude

add_node, set_properties, remove_node, reparent_node, rename_node, connect_signal (persistente), instantiate_scene, open_scene, save_scene. Toda mutación por EditorUndoRedoManager, una acción por tool call; devuelven el nombre del paso de undo.

**Prueba:** `godot --path . -e -- --godot-agent-edit-test` (addons/godot_agent_dev/edit_check.gd) llama por HTTP real a cada tool sobre una copia de main_fixture.tscn y verifica el árbol, los owners, los valores anteriores y nuevos, la señal persistente, los errores con sugerencia, que Ctrl+Z (la opción Undo del menú) deshace en pasos y que el undo de remove_node restaura los hijos con owner. Pasa en 4.4.1, 4.7.2 y 4.8-beta1.

**Notas:** - Valores JSON → propiedad: mcp/tools/value_coercion.gd (vectores, colores, enums por nombre, recursos res://, sintaxis de Godot), con test unitario.
- Una acción "Agente: …" por tool call, con custom_context en la raíz; el texto del resultado termina en "Paso de undo: «…»".
- EditorUndoRedoManager no expone undo(): editor/editor_undo.gd dispara la opción Undo del menú principal (PopupMenu hijo de MenuBar con atajo Ctrl+Z).
- La prueba recarga la escena si el editor restauró su pestaña de una corrida anterior; si no, open_scene ve la versión vieja.

## M5 — Revisar y Script Editor  (4/4)

Modo Revisar, parseo de findings, anotaciones en el CodeEdit, tarjetas y lista de hallazgos; "Aplicar arreglo" y "Exportar a CLAUDE.md".

**Hecho cuando:**
- Revisar una carpeta con 3 bugs sembrados: aparecen anotados en las líneas correctas.

### 5.4 Verificar M5 · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** S · **Responsable:** Claude

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

### 5.3 Lista de hallazgos en el dock y acciones · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** M · **Responsable:** Claude

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

### 5.2 Anotaciones en el CodeEdit y tarjetas de hallazgo · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** L · **Responsable:** Claude

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

### 5.1 Parser tolerante de findings y checks · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** S · **Responsable:** Claude

Extrae bloques {"findings":[…]} y {"checks":[…]} del texto del agente aunque vengan en fences, con texto alrededor o con campos faltantes; normaliza severidades bug|order|perf|style. Tests unitarios.

**Prueba:** godot --headless --path . --script tests/run_all.gd -- findings (test_findings_parser: 6 tests/28 checks) y -- review_store (3 tests/24 checks); 4.8 y 4.4.1.

**Notas:** review/findings_parser.gd: parse(text, project_root) → {findings, checks}. Acepta fences ```json o sin lenguaje, JSON suelto con prosa alrededor (busca llaves balanceadas respetando strings), varios bloques (sin duplicados), comas finales, campos alternativos (file/description/fix/kind…), "ruta.gd:12" en path, rutas relativas o absolutas → res://, severidades en castellano/inglés → bug|order|perf|style (desconocida → style). Checks: {title, ok, detail} con ok bool/string/número. review/review_store.gd: revisión vigente; cada turno en modo Revisar con bloque findings la reemplaza (D23); dismiss, counts, scope_label, fix_prompt, question_prompt, claude_md_section y append_to_claude_md.

## M6 — One-shot  (18/18)

Pantalla principal completa, checkpoints git, presupuestos, checks, "Guiar al agente" y reglas de cuota del plan (§10.1).

**Hecho cuando:**
- En un proyecto vacío: "Pong de 2 jugadores con puntaje" completa al menos un playtest con captura, crea checkpoints y "Volver acá" restaura correctamente.
- Con el agente falso simulando la cuota al 90 % y después un error de límite con hora de reinicio: el One-shot pausa al terminar la tarea, crea cpN-quota, muestra la cuenta regresiva y retoma solo (o con confirmación) desde la tarea correcta.

### La pausa por cuota no llegaba si la tarea no cambiaba · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** S

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

### One-shot: tiempos visibles de tareas, turnos y tools · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** media · **Tamaño:** S

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

### One-shot: cambiar de cuenta al llegar al límite y retomar sin perder contexto · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** M

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

### Pantalla Agent: el editor del objetivo es chico en monitores grandes · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** media · **Tamaño:** S

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

### One-shot: cambiar presupuestos con el run en curso, y opción ilimitado · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** S

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

### One-shot: criterios de evaluación para juegos · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** media · **Tamaño:** S

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

### One-shot: spec y progreso en archivos (planner y traspaso) · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** media · **Tamaño:** M

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

### One-shot: evaluator separado y vuelta de corrección · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** L

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

### 6.8 Reglas de cuota en One-shot: pausa, Limitado y reanudación · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** M · **Responsable:** Claude · **Etiquetas:** `quota`

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

### 6.7 Medidor de cuota en el dock y bloqueo en Limitado · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** media · **Tamaño:** S · **Responsable:** Claude · **Etiquetas:** `quota`

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

### 6.6 QuotaMonitor: fuentes, estados y umbrales · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** M · **Responsable:** Claude · **Etiquetas:** `quota`

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

### 6.5 Verificar M6 · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** M · **Responsable:** Claude

En el sandbox: "Pong de 2 jugadores con puntaje" completa al menos un playtest con captura, crea checkpoints y "Volver acá" restaura correctamente. Cuota (spec M6 actualizado): con el agente falso simulando la cuota al 90 % y después un error de límite con hora de reinicio, el One-shot pausa al terminar la tarea, crea cpN-quota, muestra la cuenta regresiva y retoma solo (o con confirmación) desde la tarea correcta. Actualizar progress.

**Prueba:** Suites (4.4.1, 4.7.2 y 4.8-beta1): run_all 78 tests / 509 checks, acp_session_check 70, oneshot_check 34 (cuota al 91 % → pausa al terminar la tarea con su checkpoint, reinicio y retoma solo; límite a mitad de turno → cp4-quota, cuenta regresiva y espera de confirmación; presupuestos; guía; sin plan). En el editor: --godot-agent-oneshot-test (pantalla Agent, barras, banner, diff, Volver acá, Aceptar todo), --godot-agent-ui-test=ui_quota, cycle test. Claude Code real en el sandbox (tests/make_sandbox.sh <dir> --dev; XRUN_PROJECT=<dir> tests/run_in_xvfb.sh $G --godot-agent-claude-oneshot-test), tercera corrida: Pong con todos los checks en pass, 4 playtests con captura, 5 checkpoints, 114k tokens, 6,6 min, y Volver acá a cp4 sin diff ni archivos sin seguimiento. El árbol del commit de M6 (sin lo de M7) se probó aparte con las mismas suites.

**Notas:** Tres corridas reales, detalladas en docs/progress.md (M6 · One-shot con Claude Code real).
1. Checkpoints apagados después de cp1: con .godot/ en el .gitignore, `git add` rechaza el pathspec :(exclude).godot. Ahora, si .godot/ está ignorado, el pathspec es `-- .`, y si start() falla vuelve a la rama del usuario. Además Claude no usó herramienta de plan.
2. Con un checkpoint por playtest anduvo, pero el fin de turno se tomaba como final aunque quedaran checks en fail o pending.
3. Sin plan, el harness sigue mientras queden checks sin pasar (hasta MAX_IDLE_CONTINUES turnos sin un playtest nuevo). Terminó sola con todo en pass.
La actividad recorta los comandos de shell a una línea. Con plan vacío y el run terminado, la columna Plan explica que el avance sale de los checks. La corrida 3 no guardó capturas: faltó --godot-agent-ui-shot. Las de la corrida 2 están en el scratchpad de la sesión.

**Bloqueada por:** 6.8 Reglas de cuota en One-shot: pausa, Limitado y reanudación

### 6.4 Proyecto sandbox para one-shots · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** media · **Tamaño:** S · **Responsable:** Claude

tests/sandbox_project/ separado (con .gdignore para el anfitrión) para correr one-shots; nunca sobre el proyecto del addon.

**Prueba:** tests/make_sandbox.sh <dir fuera del repo> --dev crea el proyecto, copia el addon (y el de dev), hace git init y el commit "Sandbox inicial". Se niega a usar un destino dentro del repo y a pisar una carpeta que no sea un sandbox (marca .sandbox_one_shot). Import headless de 4.8 sin errores. XRUN_PROJECT=<sandbox> tests/run_in_xvfb.sh … abre el editor sobre el sandbox; ahí corre --godot-agent-claude-oneshot-test (m6-05).

**Notas:** tests/sandbox_project/ (.gdignore para que el proyecto del addon no lo importe) contiene:
- project.godot (features 4.4, solo el plugin godot_agent);
- CLAUDE.md con las convenciones del sandbox (scenes/, scripts/, no tocar addons/, verificar con godot.*, sin commits);
- .gitignore con .godot/.
tests/make_sandbox.sh lo copia fuera del repo con el addon y --dev habilita godot_agent_dev. Nunca se corre un One-shot sobre el proyecto del addon: los checkpoints crean ramas y "Volver acá" resetea la carpeta.
run_in_xvfb.sh acepta XRUN_PROJECT para abrir otro proyecto.

### 6.3 Loop One-shot y presupuestos · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** M · **Responsable:** Claude

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

### 6.2 Checkpoints git · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** M · **Responsable:** Claude

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

### 6.1 Pantalla principal One-shot · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** L · **Responsable:** Claude

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

### Cola de guía visible en el One-shot · Hecho

**Terminada:** 2026-10-29 · **Tamaño:** S

El usuario no veía dónde quedaban los mensajes encolados durante un One-shot. Ahora, al escribir en el chat mientras el agente trabaja, se agrega al log una entrada de tipo guía «en cola: …» y se muestra un aviso en el chat. Cuando el mensaje sale de verdad, se agrega «enviado: …».

**Prueba:** oneshot_check presupuestos: «en cola» y «enviado» en orden, y el aviso del chat. oneshot_check loop: en pausa, la guía sale enseguida.

**Notas:** 518c819.
- OneShotRun._queue_guidance agrega la actividad «guía · en cola: …» y un aviso en el chat.
- _pop_guidance registra «enviado: …» cuando la guía sale de verdad. Si sale enseguida, se registra «enviado» directo.
- _user_guidance separa la guía del usuario de la que mete el harness (por ejemplo el aviso de loop) y se persiste.
- Color «guía» en la actividad.

### Dock: retomar el One-shot al reabrir el editor · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta

Al reabrir con un One-shot a medias, el aviso contaba como conversación y el dock escondía «Start session»: no había cómo arrancar ni retomar desde el dock. Ahora el botón sigue a la vista con solo avisos y, con un run esperando, dice «Resume One-shot»; el aviso trae «Resume One-shot» y «Open Agent screen».

**Prueba:** --godot-agent-oneshot-test simula la reapertura (chat vacío, sin sesión, _restore_oneshot del plugin): el aviso trae «Resume One-shot» y «Open Agent screen», y el dock muestra «Resume One-shot». Matriz 4.6.3/4.7.2/4.8-beta1 verde (27 UI checks).

**Notas:** Commit dc2fc2d. Venía de D37: el aviso del run a medias contaba como conversación y escondía la vista vacía.

## M7 — Pulido  (52/53, 1 en revisión)

Settings completos, historial de sesiones, Markdown→BBCode robusto, rendimiento con sesiones largas (>500 entradas) y README de uso.

**Hecho cuando:**
- Settings completos y persistidos.
- Sesión de más de 500 entradas sin degradación visible.
- README de uso escrito.

### Renombrar las sesiones (pestañas del dock) · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** media · **Tamaño:** S

Pedido del usuario (2026-10-27): «poder nombrar las sesiones. Así no serían simplemente "Session n" y uno podría saber qué hacen».

**Decisiones:**
- ✓ Se renombra con doble clic sobre la pestaña (campo flotante debajo), sin menú contextual
  Por qué: Es el gesto habitual para renombrar pestañas y no ocupa lugar en un dock angosto; el tooltip de la pestaña lo dice
  Descartado: Clic derecho con menú; un botón de lápiz; que el agente le ponga nombre solo
- ✓ Ícono de Extensions: EditorPlugin (pieza de rompecabezas a color)
  Por qué: Llena el cuadro como el resto de los íconos y es el de Project Settings → Plugins; AssetLib dibuja una figura diminuta
  Descartado: Un ícono gris de otro tipo; texto «Ext»

**Prueba:** Editor: --godot-agent-sessions-test pasa con el caso nuevo (abre el campo con el nombre actual, aplica «  Level design » recortado a pestaña, coordinador y godot.sessions, rechaza «session 1», vacío vuelve a «Session 2»). Suite completa e i18n en verde.

**Notas:** SessionTabs: doble clic en una pestaña abre un PopupPanel con un LineEdit (máx. 40) debajo de ella; Enter emite rename_requested(id, nombre). plugin._rename_session lo aplica al coordinador (godot.sessions, session_send, los rechazos «being edited by») y a la pestaña; vacío vuelve a «Session N». Un nombre repetido (sin distinguir mayúsculas) se rechaza con aviso en el chat de esa sesión, porque session_send busca por nombre; al abrir otra pestaña, «Session N» saltea los que ya usa alguna renombrada. Los nombres no se guardan entre reinicios del editor (las pestañas extra tampoco). Aparte, pedido en el mismo rato: el botón Extensions pasó del ícono AssetLib (diminuto) a EditorPlugin, que es a color (pieza naranja).

### Mensajes entre sesiones: el recibido no se ve y una sesión nueva no los lee hasta su primer prompt · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** S · **Etiquetas:** `bug`

Pedido del usuario (2026-10-27): «a una sesión nueva, si no le mando un primer mensaje, no aparecen los mensajes… si se lo envía otra sesión no se muestra» y «no aparece en el log/chat el mensaje recibido, solo que envía».

**Decisiones:**
- ✓ No se oculta SendMessage/ListAgents de Claude Code: el system prompt orienta a godot.session_send y el chat avisa cuando llega trabajo sin su mensaje
  Por qué: Denegar las tools nativas rompería la coordinación con sesiones de Claude fuera del editor (terminal, otros proyectos); el aviso también cubre tareas en segundo plano que terminan
  Descartado: Reglas deny para SendMessage en las settings de la sesión; godot.session_send como tool del núcleo (no extendida)

**Prueba:** Unit: test_sessions.test_notice_for_work_outside_a_turn (aviso una vez, subagente no cuenta, Remote Control sin aviso, dentro de un turno sin aviso); suite 285/0; acp_session_check 159/0. No probado con dos Claude reales: que el agente elija godot.session_send después del cambio de prompt.

**Notas:** Causa (historial de LittleVillages b52301ca y 9bc88f39, claude-agent-acp 0.98): los agentes usaban SendMessage/ListAgents de Claude Code, no godot.session_send. (1) El adaptador solo reenvía mensajes de usuario de otros clientes si origin.kind == human (isRemoteHumanMessage, para Remote Control); el de otra sesión se descarta, así que el chat ve la respuesta del turno que Claude arranca solo, sin la pregunta. (2) Antes del primer session/prompt la sesión del SDK no corre y no lee su bandeja: el mensaje se procesa recién con el primer prompt. Ninguno se arregla del lado del harness. Hecho: el system prompt dice que con otras sesiones del editor se usen godot.sessions/godot.session_send (entra como prompt, se ve en el chat y sirve sin primer prompt); SessionController._notice_outside_turn() avisa una vez por tanda cuando llega trabajo del agente fuera de un turno pedido (sin user_message_chunk antes, sin parentToolUseId), y se rearma con cada prompt.

**Relacionadas:** Soporte para Antigravity CLI (agy) como agente

### Dock: mostrar con qué cuenta está logueada cada sesión; «+» de pestañas más grande · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** media · **Tamaño:** S

Pedido del usuario (2026-10-27): «en ningún lado estamos mostrando qué cuenta está logueada en la sesión» y «el + para abrir una sesión paralela es muy chiquito».

**Decisiones:**
- ✓ La cuenta va en la línea de estado del dock («● Claude Code · ready · email»), con organización y plan en su tooltip
  Por qué: Es la línea que ya nombra el agente de cada sesión, existe en cada pestaña y recorta con «…» en un dock angosto
  Descartado: Una etiqueta propia en el header; solo en el tooltip de la cuota; en la pantalla del One-shot
- ✓ El «+» de pestañas usa el mismo ícono Add que «Nueva conversación» del header
  Por qué: Con el mismo tamaño se ve como el resto de los íconos; se distingue por estar en la fila de pestañas (como en un navegador) y por su tooltip
  Descartado: Texto «+» más grande (el glifo igual queda chico); otro ícono del editor

**Prueba:** Unit: test_claude_extensions.test_parse_auth_status (claude.ai, API key sin email, sin sesión, salida no JSON, tooltip); suite 284 tests (falla solo test_api_tools.test_search, previa). Editor: --godot-agent-sessions-test pasa y la captura muestra el «+» del tamaño de los íconos del header. auth_status() contra el CLI real devuelve las cuatro claves. No probado: la línea de estado con Claude real en el editor (el agente falso no es Claude).

**Notas:** ClaudeCli.auth_status() corre `claude auth status --json` (Claude Code 2.1.311) con el entorno del perfil (su CLAUDE_CONFIG_DIR) y parse_auth_status() devuelve {email, org, plan, method}. SessionController._refresh_account() lo pide al quedar lista la sesión (session/new y session/load), solo si ClaudeExtensions.is_claude_profile(); queda en SessionModel.account (no lo borra reset(): es del proceso) con la señal account_changed. El dock suma «· email» a la línea de estado y el tooltip dice cuenta, organización (salvo la «<email>'s Organization» de una cuenta personal) y plan. El Agent Log anota método y plan, sin el email. De paso: el StatusLabel tenía mouse_filter IGNORE (default de Label), así que su tooltip (error, subagentes) nunca se veía. «+» de pestañas: ícono Add del editor en un botón de 28 px; con texto «+» salía de unos 8 px.

### Asset Store: apagar el harness durante una instalación no rompe _scan · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** baja · **Tamaño:** S · **Etiquetas:** `bug`

Revisión de m7-39: plugin.gd saca el AssetStore del árbol al apagarse; _scan sigue esperando get_tree().process_frame y get_tree() es null: error a mitad de finish(), con los archivos escritos y sin anotar en el manifest.

**Prueba:** Script de prueba: un Node que hace await process_frame, remove_child + queue_free → no imprime ni da error.

**Notas:** Sin cambios: la revisión se equivocó. Probado en 4.7.2: si el nodo se libera durante un await, Godot no reanuda la corrutina (sin error), así que _scan nunca llega a get_tree() null. Apagar el harness a mitad de una instalación la abandona: archivos escritos, sin anotar en el manifest; aceptable al apagar el plugin.

### Asset Store: zip temporal propio por descarga · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** baja · **Tamaño:** S · **Etiquetas:** `bug`

Revisión de m7-39: el zip se llama solo por asset_id; si el agente instala el mismo asset mientras el diálogo de la pestaña está abierto, pisa el zip y lo borra, y la pestaña falla con «not a valid zip».

**Prueba:** Sin test: cambio de nombre de archivo; asset_check.sh lo ejercita al instalar.

**Notas:** download(): el zip se llama <asset>_<ticks_usec>.zip. Se sigue borrando al terminar o cancelar.

### Asset Store: un campo null del store no rompe la búsqueda · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** media · **Tamaño:** S · **Etiquetas:** `bug`

Revisión de m7-39: int(null) es error de script en Godot 4 (probado en 4.7.2) y get(key, 0) devuelve null si la clave viene con null. Un hit con reviews_score o price_cent null corta search() (pestaña y agente); lo mismo size en compatible_releases.

**Prueba:** Unit: test_asset_store (run_all -- asset: 17 tests, 94 checks, 0 fallos en 4.7.2). Fixture con reviews_score y price_cent null, y una release con size null.

**Notas:** parse_hits (score, price_cent) y compatible_releases (size) usan int(str(…)) / float(str(…)), como ya hacía parse_details con price_cent: str(null) da 0.

### Asset Library de Godot: buscar, sugerir, instalar y activar plugins · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** media · **Tamaño:** L

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

### Asset Store: una actualización que falla vuelve a activar sus plugins · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** S · **Etiquetas:** `bug`

Revisión de m7-45: finish() apaga los plugins activos antes de escribir y, si install() falla (disco lleno, archivo de solo lectura), vuelve sin prenderlos: el plugin queda apagado y a medio reemplazar.

**Prueba:** Necesita el editor (EditorInterface); no tiene test propio. Revisado leyendo el código; asset_check.sh no cubre una escritura fallida.

**Notas:** finish(): si install() falla, vuelve a activar los plugins que apagó (was_enabled) antes de devolver el error. Los archivos quedan a medio reemplazar, como antes.

### Asset Store: una actualización no pisa al harness ni a otros plugins · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** S · **Etiquetas:** `bug`

Revisión de m7-39/m7-45: con update=true, plan_install reemplaza todas las carpetas addons/* que trae el zip nuevo (addon_folders(plan)), no las anotadas para ese asset; un zip que trae addons/godot_agent u otro plugin los pisa. PROTECTED_FOLDERS no se mira al instalar (una instalación nueva puede agregar archivos dentro de addons/godot_agent).

**Decisiones:**
- ✓ Los archivos del zip dentro de addons/godot_agent(_dev) se saltean en silencio, sin listarlos como conflicto
  Por qué: Listarlos como conflicto metería la carpeta del harness en las carpetas anotadas del asset (installed_assets lo daría por instalado); un zip que trae el harness es un caso raro
  Descartado: Listarlos como conflicto u «otros»; rechazar el zip entero

**Prueba:** Unit: test_asset_store (run_all -- asset: 17 tests, 94 checks, 0 fallos en 4.7.2). Casos: zip con addons/godot_agent no lo planea; anotado con otra carpeta deja los archivos existentes como conflicto.

**Notas:** plan_install saltea todo lo de addons/<PROTECTED_FOLDERS> del zip (como las rutas con ..). Nuevo replace_folders(entry, plan): una actualización pisa solo las carpetas anotadas del asset; sin anotación (instalado a mano), las de addons/ del zip. prepare() devuelve replace y la pestaña lo reusa al tildar «incluir otros archivos».

### Varias sesiones abiertas a la vez que se coordinan entre sí · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** media · **Tamaño:** L

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

### Asset Store: detectar y aplicar actualizaciones de plugins · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** media · **Tamaño:** M

Pedido del usuario (2026-10-24): «Agrega también el poder detectar updates de plugins», sobre m7-39. Detectar versiones nuevas en el Asset Store de los plugins del proyecto (instalados desde el harness o a mano) y poder actualizarlos desde la pestaña y desde las tools del agente.

**Decisiones:**
- ✓ Las instalaciones se anotan en res://.godot_agent/assets.json (versionable) y los plugins instalados a mano se buscan en el store por nombre; actualizar reemplaza la carpeta del addon
  Por qué: plugin.cfg no dice de qué asset vino ni todos los autores suben la versión ahí; el archivo en el proyecto lo comparte el equipo y el export lo saltea. Reemplazar la carpeta es lo que hace falta para actualizar (el instalador nunca pisa); se avisa que se pierden los cambios locales.
  Descartado: Guardar la anotación en user:// (por máquina); solo detectar sin actualizar; chequear actualizaciones al abrir el editor como el updater del addon

**Prueba:** tests/asset_check.sh <godot> (red, copia del proyecto): tras instalar, el resultado dice «Installed»; con la versión anotada vuelta a v0.1 la pestaña ofrece «Update to 1.6», el diálogo dice qué reemplaza y borra, actualizar deja el plugin activo, borra el archivo viejo y anota la versión; sin anotación y con plugin.cfg 0.1, addons_list check_updates lo encuentra por nombre. Pasa en 4.6.3, 4.7.2 y 4.8-beta1. Unit: test_asset_store (plan con replace, stale, manifest, match_asset, installed_assets), test_asset_tools (FakeStore).

**Notas:** Commit ab6a502 en worktree-asset-updates. Anotación en res://.godot_agent/assets.json: {asset_id: {version, folders, files}}. Instalados a mano: search(plugin.name) y match por nombre simplificado o slug == carpeta; sin versión en plugin.cfg no se compara. Actualizar: plan_install con replace=carpetas de addons/ del zip, stale = anotados que ya no vienen (sin anotación no se borra nada), plugins activos se apagan antes de escribir y se prenden después. PROTECTED_FOLDERS pasó a AssetStore.

### Subagentes: ver lo que hacen y setting para permitirlos y limitarlos · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** media · **Tamaño:** M

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

### El composer no entra en el dock con el ancho por defecto (sesión abierta) · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** S · **Etiquetas:** `ui`

Encontrado armando las capturas (m7-41): con una sesión abierta, la fila de abajo del composer (@, imagen, /, anillo de cuota, uso «38k / 200k» 90 px, modo 66, modelo 67, Enviar 63) pide 418 px; el dock por defecto mide ~289 px en 1920x1200, así que el modelo y Enviar quedan cortados (el dock se recorta en su guard). layout_check no lo ve porque mide sin sesión (sin uso ni modelo). Opciones: pasar el uso al tooltip del anillo o acortarlo, OptionButtons con clip_text, o una segunda fila cuando no entra. Agregar a layout_check el caso con sesión. (El botón «Thinking» que ensanchaba el chat ya se arregló en m7-41.)

**Decisiones:**
- ✓ La fila se compacta por niveles (Enviar solo con símbolo, después sin uso, /, @ y captura, y por último el modelo con «…») en vez de pasar a dos filas
  Por qué: Mantiene el composer en una sola fila y no le quita alto al chat. Lo que se esconde tiene otro acceso: el anillo de contexto y su tooltip, escribir / o @, y Ctrl+V para la imagen.
  Descartado: Una segunda fila cuando no entra; mover el uso al tooltip del anillo siempre; clip_text siempre en los OptionButtons

**Prueba:** GODOT_AGENT_LANGUAGE=es tests/run_in_xvfb.sh godot --godot-agent-i18n-test (LayoutCheck.composer_fits: dock de 240 px con uso, modelo y modo, libre y ocupado); pasa en 4.6.3, 4.7.2 y 4.8-beta1. Docs shots a 480 px muestran la fila completa.

**Notas:** Commit 8e8aada, ya en main (vino de worktree-composer-width). composer.gd _fit_row(): calcula el ancho visible (row.size.x menos lo que el contenido del dock se pasa del MinSizeGuard) y sube el nivel de compactación hasta que entra: 1 Enviar/Detener solo símbolo, 2 sin medidor, 3 sin /, 4 sin @, 5 sin captura, 6 modelo con clip + «…» y expand (spacer oculto). Anchos medidos independientes del nivel actual (fuente para Enviar y modelo) para no oscilar. Ojo: con text_overrun_behavior != NO_TRIMMING el Button no cuenta el texto en su mínimo, por eso el overrun se pone solo en el nivel 6.

### Guía con imágenes para el README (y la wiki) · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** media · **Tamaño:** M · **Etiquetas:** `docs`

Pedido del usuario (2026-10-23): una guía con capturas, al menos para el README. Capturas reales del editor (Xvfb, plugin de dev con agente falso para que no dependa de una cuenta): dock con una conversación, tarjeta de permiso, modos, Review con marcas en el Script Editor, pantalla One-shot, Settings, Extensions, aviso de update. Van a docs/images/ y se regeneran con un flag del plugin de dev.

**Prueba:** tests/docs_shots.sh <godot> en|es: copia limpia del proyecto + Godot self-contained con el idioma del editor; --godot-agent-docs-shots= saca overview, chat, permission, review y settings sin fallas en los dos idiomas. Revisadas a ojo: sin rutas del usuario, sin contenido de tests, sin recortes. Unit 246 verdes, ui_markdown y ciclo del plugin pasan.

**Notas:** Commits 8d0647a (LICENSE MIT a nombre de Daniel Rodriguez Aires, CONTRIBUTING.md, LICENSE en el zip del release) y 94ca4f4 (guía), ya en main (en worktree-docs-guide eran 6cf8931 y 06cd486). README «Quick start» con capturas en en/es (docs/images/<lang>/, .gdignore). Escena demo tests/docs_demo/ (con 2 bugs a propósito para Review), escenarios docs_build(_es)/docs_review(_es). El dock se ensancha a 480 px moviendo split_offsets del DockHSplitMain (un offset por divisor entre hijos visibles). Arreglado de paso: el botón «Thinking» no recortaba su texto y ensanchaba el chat más que el dock. Pendiente aparte: m7-42 (fila del composer más ancha que el dock por defecto). Descripción y topics de GitHub puestos con gh repo edit. Sin captura del One-shot (su check usa contenido de test en español).

### Marketplace propio (repo) con las skills, tools y plugins de Godot · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** baja · **Tamaño:** M

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

### Updater: buscar e instalar versiones nuevas del addon desde el editor · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** media · **Tamaño:** M · **Etiquetas:** `ui`

Pedido del usuario (2026-10-23): un updater.

- Chequeo: GitHub API releases/latest de dannroda/godot-agent (HTTPRequest, sin token) al abrir el editor (una vez por día como máximo, se puede apagar en Settings) y con un botón «Buscar actualizaciones»; compara el tag con plugin.cfg (AddonVersion). Pre-releases solo si se pide.
- Aviso en el dock: «Versión X disponible» con las notas del release (Markdown del CHANGELOG) y «Actualizar».
- Actualizar: baja el zip del asset, lo extrae (ZIPReader) a user:// y lo valida (plugin.cfg con la versión esperada). Después reemplaza addons/godot_agent conservando config/project_config.tres y los config/*.md|txt que el usuario cambió, y pide reiniciar el editor (EditorInterface.restart_editor). Reemplazar scripts del addon con el plugin cargado puede tirar el editor (D35, hot reload): deshabilitar el plugin antes de escribir, o escribir y reiniciar enseguida. Hay que probar cuál es seguro.
- No ofrecerlo si el addon es un checkout de git o un symlink (desarrollo): ahí se actualiza con git.

**Prueba:** Unit: tests/unit/test_addon_updater.gd (versiones, elección del release, extracción y validación de un zip armado con ZIPPacker, install con borrado/respaldo/KEEP, copia de dev); 246 tests verdes en 4.6.3, 4.7.2 y 4.8-beta1. UI: --godot-agent-update-shots= (aviso debajo del de export, notas en Markdown, Settings → Buscar ahora dice copia de desarrollo, «Después» guarda la versión), en en y es; ciclo del plugin y settings shots pasan. E2E real: sandbox con el addon copiado marcado 0.1.0 + Godot self-contained (._sc_) + plugin sonda en Xvfb propio: encontró v0.1.3 en GitHub, bajó el zip (sigue el redirect), lo instaló, respaldó system_prompt.md editado, conservó project_config.tres, borró addon_updater.gd (0.1.3 no lo trae), reinició y el plugin quedó habilitado en 0.1.3.

**Notas:** Commit 6bc34fc (worktree-updater), ya en main. core/addon_updater.gd (Node con HTTPRequest; API /releases?per_page=10, elige el más nuevo no-draft con .zip; pre-releases no). ui/dock/update_banner.gd vía dock.add_banner(). Settings → Interfaz → Actualizaciones (check al abrir, una vez por día; Buscar ahora). Instalar: confirm → download a user://godot_agent/update → validar versión de plugin.cfg → save_all_scenes, controller.stop → install → restart_editor(false) sin awaits entre escribir y reiniciar. Solo borra archivos obsoletos de tipos del release (gd, uid, tscn, po, cfg, md, txt). Copia de dev (symlink o godot_agent_dev) no se actualiza. Canal de log nuevo "update". Ojo: quien tenga 0.1.3 o anterior tiene que instalar a mano la primera versión que traiga el updater. Sin probar: Windows/macOS, y Authenticate de GitHub con rate limit (60 req/h sin token: una búsqueda por día alcanza).

### Extensiones: plugins de Claude Code (marketplaces, instalar, habilitar) · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** media · **Tamaño:** M · **Etiquetas:** `ui`

Plugins de Claude Code: se instalan desde marketplaces y se habilitan en settings (enabledPlugins); traen skills, comandos, agentes, hooks y MCP. claude-agent-acp los carga de la config del usuario, y el SDK acepta `plugins: [{type: "local", path}]` por `_meta.claudeCode.options`.

Hacer: en Extensions → Plugins, lista de instalados con estado y lo que trae (`claude plugin details`), Habilitar/Deshabilitar (por proyecto o usuario), agregar marketplace e instalar (por el CLI `claude plugin ...`, que puede no estar instalado aparte del adaptador: detectarlo y explicar), y cargar un plugin local de una carpeta del proyecto (options.plugins). Después de cambiar, recargar en la sesión abierta (el SDK tiene reload_plugins) o reiniciarla con aviso. Solo Claude Code; para otros agentes la sección dice que no aplica.

**Prueba:** Unit test_claude_extensions (parseo de mcp list, plugin list, acciones --json, scopes de config, cwd por sh, ventana sin CLI) en 4.6.3, 4.7.2 y 4.8-beta1. tests/extensions_cli_check.gd contra el CLI real con CLAUDE_CONFIG_DIR temporal: agrega un marketplace local, instala, deshabilita, desinstala, quita (12 checks; la config del usuario quedó con el mismo md5). Xvfb --godot-agent-extensions-shots (en y es): abre desde el dock con la config real, 9 instalados, 3912 disponibles, 2 marketplaces, 12 MCP con estado.

**Notas:** extensions/claude_cli.gd (busca claude o el del SDK en la cache de npx; corre con AgentProcess vía sh -c cd), extensions/claude_extensions.gd (parseo estático + acciones), ui/extensions/extensions_window.gd. Botón ExtensionsButton en el header del dock. No se recarga en la sesión abierta (ACP no expone reload_plugins): franja con «Nueva sesión». Cuidado: `claude plugin enable` de un id inexistente lo agrega a enabledPlugins sin fallar; la ventana solo ofrece enable para instalados. No probado: Autenticar (claude mcp login abre el navegador) ni un install que pide aceptar el comando del marketplace (el formato de shownCommand se supuso).

### Extensiones: skills (listar, crear, activar, skills de Godot incluidas) · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** media · **Tamaño:** M · **Etiquetas:** `ui`

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

### Cola de mensajes: «Enviar ahora» · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** media · **Tamaño:** S · **Responsable:** Claude

Pedido del usuario: un mensaje en la cola (escrito mientras el agente trabaja) espera a que termine el turno. Agregar «Enviar ahora» en cada mensaje encolado: corta el turno en curso (session/cancel) y lo manda enseguida, sin perder el resto de la cola.

**Prueba:** - test_prompt_queue: move_to_front, y en la vista el ➤ de cada fila avisa su índice, sigue a set_send_available y no saca el prompt (lo hace el dock).
- --godot-agent-queue-test, segunda fase (tests/scripts/queue_now.json): con un turno largo corriendo y "uno", "dos" en cola, ➤ en "dos" corta el turno (no llega el resto del texto largo), "dos" sale enseguida, "uno" queda en la cola sin pausa y sale después.
- La primera fase (cancelar pausa la cola; «Enviar ahora» del encabezado) sigue pasando.

**Notas:** PromptQueueView: botón ➤ en cada fila (antes de editar y quitar) con la señal send_item_now_requested(index). Dock `_send_queued_now(index)`: pasa el prompt al frente, saca la pausa y, si el agente trabaja, marca `_interrupt_for_queue` y cancela; `_on_turn_finished` ve la marca y manda el siguiente aunque el turno haya terminado con cancelled. Sin turno en curso lo manda directo.

### Permisos por server MCP externo en la matriz · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** M · **Etiquetas:** `mcp`, `permisos`

Las tools `mcp__<server>__*` que no son de godot caen en el grupo Other (PermissionPolicy.matrix_value devuelve ask para grupos sin DEFAULTS), en todos los modos: el One-shot se frena esperando.

Hacer: un grupo por server (mcp:blender) con valores por modo editables en Settings (por defecto ask; sugerir allow para tools read-only si el server marca readOnlyHint), "Permitir siempre este server" desde la tarjeta de permiso, y que el One-shot avise antes de arrancar si hay servers en ask. En el chat, mostrar el nombre corto (blender.get_objects_summary) como con godot.* (tool_call.gd, tool_group_view.gd, run_report.gd).

**Decisiones:**
- ✓ Los servers MCP de terceros arrancan en Preguntar en todos los modos, incluidos Auto y One-shot
  Por qué: Un server de terceros puede hacer cualquier cosa (borrar en Blender, escribir en una base), y el harness no sabe qué hacen sus tools. Se permite explícitamente por server y modo, desde Settings o desde la tarjeta.
  Descartado: Permitir en Auto y One-shot como las tools de edición; usar readOnlyHint para permitir las de solo lectura (el adaptador no lo manda en el pedido de permiso).

**Prueba:** acp_session_check escenario "MCP servers de terceros": tarjeta por server con nombre corto, «Permitir siempre en el proyecto» guarda allow en Construir y la segunda tool de blender pasa sin tarjeta, db sigue preguntando, mcp_servers_not_allowed para el aviso del One-shot. Unit test_policy_groups_per_server. Xvfb auto/remote/cycle/oneshot/i18n en verde.

**Notas:** Grupo mcp:<server> sacado del prefijo mcp__<server>__ (title o _meta.claudeCode.toolName); ask por defecto en todos los modos, overrides en la matriz. La tarjeta suma un botón «Permitir siempre «x» en modo M, en este proyecto» (persist_label/persist_allow → permissions_changed → plugin guarda la config). One-shot: activity warning al arrancar. No se usó readOnlyHint (el adaptador no lo manda en el permiso).

**Relacionadas:** Extensiones: panel de MCP servers (los del addon y los del agente)

### Extensiones: panel de MCP servers (los del addon y los del agente) · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** L · **Etiquetas:** `ui`, `mcp`

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

### Modo (Preguntar/Revisar/Construir/Auto/One-shot) como dropdown al lado del selector de modelo · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** media · **Tamaño:** S · **Responsable:** Claude

Pedido del usuario: los cinco botones de modo ocupan dos filas arriba del dock. Pasarlos a un dropdown en la fila del composer, al lado del selector de modelo, para ganar lugar en la conversación.

**Prueba:** - --godot-agent-auto-test: Auto está en el selector justo después de Construir, con tooltip, y elegirlo pasa a modo Auto.
- --godot-agent-remote-test: elegir One-shot en el selector esconde Remote Control.
- --godot-agent-i18n-test (es): el dock entra en el panel (LayoutCheck) y el selector se ve.
- ui_demo: captura revisada, ya no está la fila de botones y «Construir ▾» va en la fila del composer.
- run_all: 227 tests (4.7.2).

**Notas:** Composer: `_mode_button` (OptionButton plano, en el color de acento) antes del selector de modelo; `set_modes([{id,label,tooltip}])`, `set_current_mode(id)` (el tooltip del botón dice el modo actual) y `choose_mode(id)` para las pruebas. Se guardan hasta que el composer arma sus controles. Dock: sin el HFlowContainer ModeBar (también fuera del .tscn); `_build_mode_selector()` y `_refresh_modes()` van por el composer.

### Capturas del agente: verlas en grande · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** media · **Tamaño:** M · **Responsable:** Claude

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

### El agente no abre Godot en una ventana desde la shell · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** S · **Responsable:** Claude · **Etiquetas:** `bug`

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

### Cuota del plan como anillos en la fila del composer y modelo por defecto con nombre · Hecho

**Terminada:** 2026-10-29 · **Tamaño:** S

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

### Remote Control: franja colapsable · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** media · **Tamaño:** S · **Etiquetas:** `acp`

Pedido del usuario (2026-10-23): «Que se pueda colapsar, creo que hay un nodo control colapsable». Con el link, el QR y la aclaración, la franja de Remote Control ocupa mucho alto en el dock. Usar FoldableContainer (Godot 4.5+, el mínimo del addon es 4.6): el título «● Remote Control activo» y los botones a la vista siempre, el resto plegable; recordar el estado.

**Prueba:** --godot-agent-remote-test en 4.8-beta1 y 4.6.3: la franja es un FoldableContainer; plegada, el link no se ve y «Apagar» sí; «QR» la despliega y muestra el código. Capturas plegada y desplegada revisadas. Suite completa verde en las dos versiones, i18n incluido.

**Notas:** Commit b99a386, ya en main (vino de la rama remote-qr). El estado plegado se conserva mientras el editor está abierto (no se guarda entre sesiones: Remote Control arranca apagado en cada sesión nueva). get_title_bar_control no existe en 4.6, así que el código no lo usa.

### Imágenes en el chat: pegar, arrastrar y capturar el juego · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta

Pedido del usuario: poder pegar imágenes en el chat del agente, o que saque capturas del juego en ejecución. El agente ya captura con run_scene + capture_game_frame; faltaba que el usuario pudiera adjuntar. Ctrl+V con imagen o archivos copiados, arrastrar archivos del FileSystem, «+ contexto → Captura del juego» (con aviso si el run no tiene el autoload de playtest), hasta 6 imágenes por mensaje achicadas a 1280 px.

**Prueba:** test_composer: rutas de archivos copiados (file:// con %20, absolutas, texto mezclado → se pega como texto) y arrastre real con force_drag (archivos sin carpetas; el texto arrastrado lo sigue insertando el TextEdit). --godot-agent-ui-test=ui_demo: PNG de afuera del proyecto + imagen pegada de 2560 px → dos bloques de imagen, la pegada achicada a 1280 sin tocar la original, y los chips se limpian al enviar. --godot-agent-run-test: Captura del juego desde el dock adjunta el frame rojo del juego; en un run manual avisa que falta el autoload. Matriz 4.6.3/4.7.2/4.8-beta1 verde: run_all 178/1336, acp 117, oneshot 106, 33 UI checks.

**Notas:** Commit 844f3c0. El TextEdit llama al drop del forwarding con cualquier dato (también texto) y después inserta el texto él: _drop_files filtra. Archivos soltados desde el sistema operativo no se manejan: el editor ya los importa al FileSystem, así que alcanza con Ctrl+V o con arrastrarlos desde el FileSystem.

### Soporte para Remote Control de Claude Code desde el dock · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** media · **Tamaño:** M · **Etiquetas:** `acp`

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

### Remote Control: QR del link en la franja · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** media · **Tamaño:** M · **Etiquetas:** `acp`

Pedido del usuario (2026-10-22). Quedó afuera de m7-21 (revierte la decisión «Sin QR»). El usuario: «godot debería ser capaz de generar qr. Se puede usar _draw por ejemplo. O alguna forma de generarlo usando gdscript».

Encoder QR en GDScript (modo byte, corrección M; versiones hasta ~6 alcanzan para un link de claude.ai): datos → Reed-Solomon → matriz con patrones, máscara elegida por penalización. Dibujado con _draw (o una Image/ImageTexture) con zona de silencio, en la franja de Remote Control o en un popup al tocarlo. Test unitario del encoder contra vectores conocidos (matriz de un texto de referencia) y el check del editor de Remote Control.

**Decisiones:**
- ✓ El QR se muestra con un botón «QR» en la franja (oculto por defecto), dibujado con _draw al ancho del dock
  Por qué: Con el QR siempre a la vista la franja ocupa ~250 px de alto en el dock; el link se sigue copiando o abriendo sin él
  Descartado: QR siempre visible; en un popup aparte

**Prueba:** test_qr_code: matriz del link de prueba igual a la de qrencode 4 (misma máscara elegida); versión 7 con bloque de versión y texto UTF-8 igual a qrencode con la máscara 3; límites (versión 1, 213 bytes en la 10, 214 no entra); imagen con zona de silencio. A mano: 11 largos (versiones 1–10) decodificados con zbarimg, 8 idénticos a qrencode y los otros 3 idénticos con la máscara de qrencode (libqrencode calcula la penalización distinto). --godot-agent-remote-test: «QR» muestra el código y la captura del editor se decodifica con zbarimg. Suite completa verde en 4.8-beta1 y 4.6.3, i18n incluido.

**Notas:** Commit 2f5b02e, ya en main (vino de la rama remote-qr). Traducido de la librería de Project Nayuki (MIT); el aviso de copyright está en el encabezado de core/qr_code.gd. Con un celular real no se escaneó.

### La barra de modos no entra en un dock angosto · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** media · **Tamaño:** S

Visto en las capturas de m2-09 y m7-21 (2026-10-22): con cinco modos (Preguntar, Revisar, Construir, Auto, One-shot) el último botón queda cortado («One-s…») cuando el dock está en su mínimo de diseño (260 px), y el MinSizeGuard lo recorta. En español los nombres son más largos y empeora.

Opciones: botones que se achican con clip y tooltip, íconos más texto corto, o un selector desplegable cuando no hay lugar. Que el check del editor verifique que la barra no pasa el mínimo del dock (como hace remote_check con la franja), en inglés y en español.

**Decisiones:**
- ✓ El mínimo del dock baja de 260 a 220 px y la barra de modos pasa a ser un HFlowContainer: si no entran, los modos siguen en una segunda línea
  Por qué: El panel del editor por defecto mide 240 px, y con 260 el MinSizeGuard recortaba el último modo, el botón de Settings y Enviar. Cortar palabras («Constr…») se lee peor que dos líneas.
  Descartado: Botones recortados con tooltip; íconos con texto corto; un selector desplegable

**Prueba:** layout_check.gd (nuevo) falla antes del arreglo con el dock en el panel por defecto de 240 px: «el dock pide 260 px», y Settings, One-shot y Enviar quedan fuera del borde, en inglés y en español. Después pasa: corre en --godot-agent-remote-test (con la franja y una tarjeta) y en --godot-agent-i18n-test (español). Suite completa verde en 4.8-beta1 y 4.6.3.

**Notas:** Commit 2f42d86 (rama dock-narrow), ya en main. La causa no era la barra de modos sola: el mínimo de diseño de 260 px del dock no entraba en el panel por defecto de 240, y el MinSizeGuard recortaba 20 px a la derecha (también el «+» del encabezado y Enviar). Bajó a 220 y la barra pasó a HFlowContainer sin clip_text.

### Convenciones de Godot en el system prompt · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** S · **Etiquetas:** `swallowtail`

Como el CLAUDE.md que trae swallowtail. Reglas de estructura en el system prompt, para todos los modos (Construir, Revisar y One-shot): componer con escenas guardadas en disco (sin un script que arme todo el árbol en _ready), nodos built-in antes que scripts propios, "call down, signal up", tipado estático, valores ajustables en Resources o data.json y no en constantes, aleatoriedad con semilla (playtests reproducibles), verificar después de cada cambio. Son las mismas reglas de las skills de Godot del usuario. Respetar el CLAUDE.md/AGENTS.md del proyecto si dice otra cosa. Revisar también que la rúbrica de criterios (D40) y la revisión (M5) usen las mismas reglas.

**Prueba:** `tests/unit/test_system_prompt.gd`: las convenciones aparecen en el system prompt de los cuatro modos; Revisar las pide como hallazgos; el criterio Código de la rúbrica (D40) las nombra. Suite unitaria completa en 4.8-beta1: 180 tests, 0 fallos.

**Notas:** Commit eacaaaf (rama swallowtail-tools).
- `config/system_prompt.md`: sección "Godot conventions" (escenas en disco, nodos built-in, call down/signal up, tipado, tunables en exports/Resources/data, RNG con semilla, verificar después de cada cambio). El CLAUDE.md/AGENTS.md del proyecto manda si dice otra cosa.
- Revisar (M5): la regla del modo pide reportar los desvíos como findings (severidad order para estructura, style para tipado).
- D40: el criterio Código y sus anclas 3/6/9 usan las mismas reglas.

### README en inglés y en español · Hecho

**Terminada:** 2026-10-29 · **Tamaño:** M

README.md pasa a inglés y README.es.md queda como versión en español. Cada uno enlaza al otro y a la wiki. El contenido se mantiene al día con lo que hace el plugin (One-shot con spec, presupuestos editables, guía por el chat, informe, criterios).

**Prueba:** README.md y README.es.md enlazan a la wiki de su idioma; los nombres de botones en negrita coinciden con los textos de la interfaz (script de verificación contra el código y es.po).

**Notas:** Commit c274ae8.

### El agente no escribe el proyecto por fuera del editor · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta

En great-boy-one el agente del One-shot editó un script con un heredoc de python3 y escribió escenas con cat >, salteándose el editor (el usuario mostró cómo lo hace swallowtail). D48: rechazo automático de shell que escribe archivos del proyecto y de .tscn/.uid/.import a mano, reglas en el system prompt, y create_scene con script y propiedades de la raíz.

**Prueba:** test_project_write_guard (24 casos, incluidos los comandos de la captura del usuario); acp_session_check _scenario_project_writes (modo One-shot: 3 «Rejected:» sin tarjeta); edit-test con create_scene + script + exports. Matriz 4.6.3/4.7.2/4.8-beta1 verde: run_all 176/1328, acp 117, oneshot 106, 27 UI checks. El external-test de 4.6.3 no imprimió nada en la matriz y pasó al repetirlo solo.

**Notas:** Commit 9f289c8 (D48). ACP no lleva el motivo del rechazo: el system prompt explica la regla, y el chat avisa con «Rejected: … without going through the editor».

**Relacionadas:** Armar escenas en lote; Project settings por el editor: input map, autoloads y settings; Mover, copiar y borrar archivos arreglando referencias; Recursos .tres: crear, leer y editar

### El agente usa el binario del editor abierto para correr Godot · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** S

El usuario reportó que el agente corre `godot --headless` y toma el godot del PATH, que puede ser otra versión que la del editor abierto. Hay que darle el binario del editor: OS.get_executable_path() en las variables de entorno GODOT y GODOT_BIN del proceso del agente, un shim `godot` al frente del PATH del hijo, y una regla en el system prompt con la ruta. project_info también la reporta.

**Prueba:** test_editor_binary (entorno, contenido del shim y que el shim corra la versión del editor). acp_session_check: el agente falso ve $GODOT y el shim al frente del PATH, y el prompt nombra el binario.

**Notas:** 08bfad4 (oneshot-wip, D43). transport/editor_binary.gd entrega el binario por tres vías:
- GODOT y GODOT_BIN en el entorno del agente (el perfil puede pisarlas);
- un shim `godot` en <cache>/godot_agent/bin-<hash>/, al frente del PATH;
- una regla con la ruta en el system prompt y en project_info.
La regla del prompt es la que manda, porque la shell de Claude Code puede volver a armar el PATH desde .zshrc.

### Mini wiki: cómo funciona y cómo usarlo (en y es) · Hecho

**Terminada:** 2026-10-29 · **Tamaño:** M

Crear docs/wiki/en y docs/wiki/es con páginas Markdown sobre cómo funciona y cómo usarlo: arquitectura (ACP, MCP, editor), primeros pasos, modos y permisos, tools MCP, One-shot (spec, presupuestos, checkpoints, cuota, informe, criterios), Revisar, completado predictivo, Settings y troubleshooting. Se puede copiar tal cual a la wiki de GitHub.

**Prueba:** docs/wiki/en y docs/wiki/es con 10 páginas cada una (inicio, primeros pasos, cómo funciona, modos y permisos, herramientas del editor, One-shot, revisión, completado, settings, problemas frecuentes); etiquetas verificadas contra la interfaz final.

**Notas:** Commit c274ae8. Pendiente si cambian etiquetas: volver a correr la verificación de negritas contra el código.

### Interfaz en inglés con traducción al español · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** L

El usuario pidió que el plugin esté primero en inglés y traducido al español. Los textos de la UI pasan a inglés con tr() y la traducción española va en un .po que se carga en el dominio de traducción del editor. Elegido con el usuario: el idioma sigue al del editor de Godot, y Settings → Interfaz suma un override (Automático / English / Español). Lo que lee el agente (descripciones de las tools MCP, prompts del One-shot, system prompt, rúbrica) queda solo en inglés, con la instrucción de responder en el idioma del usuario. Hay unos 650 literales en español repartidos por ui, oneshot, session, mcp y otras carpetas, y los tests se actualizan al inglés.

**Prueba:** run_all (test_i18n: catálogo completo, placeholders, sin entradas sin usar) y --godot-agent-i18n-test con GODOT_AGENT_LANGUAGE=es (dock, pantalla Agent, Agent Log y cada página de Settings sin textos traducibles en inglés). Matriz 4.6.3/4.7.2/4.8-beta1 verde en 6541f02.

**Notas:** D46. Texto fuente en inglés; español en addons/godot_agent/i18n/es.po (~620 msgids), cargado con load() como Translation. Idioma: GODOT_AGENT_LANGUAGE > Settings → Interface → Language > idioma del editor; se aplica al reabrir. Lo que lee el agente (prompts, tools, logs, nombres de deshacer, commits de checkpoint) queda solo en inglés. Raíces con auto_translate desactivado; los diálogos ponen cancel_button_text = I18n.t("Cancel"). Commit da82c9f (+ ajustes en 6541f02 y dc2fc2d).

### One-shot: informe de métricas de la corrida · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** media · **Tamaño:** M

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

### One-shot: detectar loops sin progreso real · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** media · **Tamaño:** M

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

### Crash al recargar agent_process.gd con un agente corriendo · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** media · **Tamaño:** S

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

### Persistir el run del One-shot y ofrecer retomarlo · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** M

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

### Cola de prompts en el chat · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** M

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

### 7.7 Verificar M7 · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** S · **Responsable:** Claude

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

### 7.3 Historial de sesiones · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** media · **Tamaño:** M · **Responsable:** Claude

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

### 7.6 README de uso · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** media · **Tamaño:** S · **Responsable:** Claude

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

### 7.4 Markdown→BBCode robusto · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** media · **Tamaño:** S · **Responsable:** Claude

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

### 7.2 Diálogo de Settings completo · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** L · **Responsable:** Claude

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

### Reportar a Godot el EditorDock huérfano de _has_main_screen (4.8) · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** baja · **Tamaño:** S

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

### 7.5 Rendimiento con sesiones largas · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** media · **Tamaño:** M · **Responsable:** Claude

Más de 500 entradas sin degradación: límite de nodos vivos en la lista (las viejas se colapsan o se cargan bajo demanda), batch de chunks por frame. Medido con un guion largo del agente falso.

**Prueba:** tests/run_in_xvfb.sh $G --godot-agent-long-test (addons/godot_agent_dev/long_session_check.gd): el agente falso manda un turno de 641 entradas, 320 mensajes en Markdown de 12 chunks cada uno, alternados con tool calls. Antes del cambio, un frame tardó 3951 ms: toda la ráfaga en un solo frame, con 391 vistas armadas y tiradas. Ahora, en 4.8 con OpenGL por software en Xvfb: p95 45–97 ms y peor frame 105–129 ms (umbrales del check: 120 y 400). Quedan 250 vistas vivas y 391 ocultas, el último mensaje está completo y "Mostrar anteriores" agrega 50. run_all, acp_session_check y oneshot_check siguen pasando.

**Notas:** - transport/agent_process.gd: el thread lector encola las líneas de stdout y el hilo principal las entrega con un presupuesto de 6 ms por frame. Lo que sobra sigue en process_frame: con call_deferred correría en la misma vuelta de la cola de mensajes. El exit espera a la última línea encolada. stderr sigue con call_deferred.
- ui/dock/conversation_view.gd:
  - las vistas nuevas se arman por tandas con 8 ms por frame;
  - si una ráfaga trae más entradas que el tope, las que quedarían ocultas no se arman;
  - los refrescos (tool groups, plan, permisos) se agrupan a uno por vista y por frame;
  - "N entradas anteriores ocultas" pasó a ser el botón "Mostrar 50 anteriores (N ocultas)", que arma las previas arriba y sube el tope hasta la próxima sesión.
- agent_message_view ya convertía el Markdown una vez por frame.

### El addon no cargaba en un juego con class_name Level · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta

great-boy-one declara class_name Level y el addon tenía enum Level (ChatEntry): Godot resolvía el tipo a la clase global y el dock no compilaba (4.6, 4.7 y 4.8). Enums y clases internas con nombres compuestos (D47), clases globales genéricas en tests/fixtures/global_names y test_type_names.

**Prueba:** Con tests/fixtures/global_names en el proyecto (Level, State, Kind, Phase, Request…), el código anterior da los mismos Parse Error; con el arreglo, matriz 4.6.3/4.7.2/4.8-beta1 verde (27 UI checks) y una copia de great-boy-one abre sin SCRIPT ERROR. test_type_names falla con un enum o clase interna de una palabra.

**Notas:** D47. Commit 6541f02, ya en main.

### Remote Control: mostrar en el dock lo que cambió desde el celular · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** media · **Tamaño:** M · **Etiquetas:** `acp`

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

### Remote Control: verificar con Claude real el cierre de la tarjeta y session/load · Pendiente

**Prioridad:** media · **Tamaño:** S · **Etiquetas:** `acp`

Pendiente de m7-21 (2026-10-22). El cierre de la tarjeta cuando el permiso se contesta en el celular ($/cancel_request → «Contestado en otro lado») solo se probó con el agente falso; con Claude real se vio que el adaptador manda la notificación, pero eso fue antes del arreglo.

Probar con Claude Code real y el celular:
- un permiso contestado en el celular cierra la tarjeta del dock, y el log de permisos lo registra;
- contestar en el dock cierra el aviso del celular;
- recargar la sesión (historial / session/load) con Remote Control prendido: ¿sigue prendido del lado de Claude? ¿El dock debería mostrar la franja? Hoy una sesión nueva arranca con el link vacío;
- reiniciar el editor con Remote Control prendido.

Anotar lo que salga en D58 y la wiki.

**Notas:** PREPARADA para una sesión con el usuario y el celular, unos 20 minutos. Hay 4 pruebas (A–D), cada una con lo que hay que mirar. Anotar la respuesta a cada pregunta (sí/no y lo que se vio). Después se pasa a D58, a la wiki (Modes-and-permissions → Remote Control) y, si algo falla, a tareas nuevas.

Antes de empezar
1. Editor con el addon desde main (o la rama que esté por salir). Proyecto de prueba con un .gd cualquiera.
2. Perfil Claude Code (claude-agent-acp) con sesión iniciada. En el Agent Log, canal proc, anotar la versión del adapter y la de Claude Code (D58 se probó con 0.94).
3. Celular con la app de Claude, o claude.ai/code, en la misma cuenta.
4. Modo del harness: Review. Ahí las escrituras piden tarjeta y las lecturas no, así el permiso llega a los dos lados. En Auto el harness contesta solo y el celular nunca pregunta, así que no sirve para esto.
5. Agent Log abierto, con los canales acp y perm a la vista.

A. Permiso contestado en el celular (lo principal de la tarea)
1. ⋯ → Remote Control. Tiene que aparecer la franja con el link. Abrirla en el celular, con el QR o el link.
2. Desde el celular: «Agregá una línea `# remote A` al final de <archivo>.gd».
3. Mirar: en el dock aparece la tarjeta de permiso, y en el celular también pregunta. Si solo pregunta uno de los dos, anotar cuál.
4. Contestar Permitir en el celular, sin tocar el dock.
Qué mirar:
- La tarjeta del dock se cierra sola con «⇄ Contestado en otro lado» en menos de 1–2 s. Si queda colgada, es el bug que arregló m7-21.
- En el Agent Log, en acp, aparece `$/cancel_request` con el requestId del `session/request_permission`. En perm aparece «withdrawn by the agent (answered from Remote Control…)».
- El archivo cambió, y el aviso «Desde Remote Control: modificó <archivo>.gd» aparece unos 2 s después, con Ver diff y Deshacer.
5. Repetir con Rechazar en el celular. La tarjeta tiene que cerrarse igual y el archivo no tiene que cambiar.

B. Permiso contestado en el dock
1. Desde el celular, pedir otra escritura (`# remote B`).
2. Contestar Permitir en la tarjeta del dock.
Qué mirar:
- El aviso del celular se cierra solo, o queda contestado. Si sigue preguntando, el problema es del lado de Claude: anotarlo, no es nuestro.
- En perm aparece la respuesta del usuario y no «withdrawn».
- No aparece después un `$/cancel_request` para ese request. Si aparece tarde, la tarjeta ya contestada no tiene que cambiar de texto.

C. Recargar la sesión con Remote Control prendido (session/load)
1. Con la franja visible, anotar el link L1. Clic en Historial y abrir otra sesión, después volver a esta desde Historial. Sin historial local usa session/load; con historial local, session/resume. En acp se ve cuál fue.
2. Mirar: hoy la franja desaparece, porque reset() limpia remote_control_url.
3. Preguntas a contestar:
   a. ¿El celular sigue conectado a L1 y puede mandar mensajes? Mandar «¿seguís ahí?».
   b. ¿Un permiso pedido desde el celular llega al dock recargado? Pedir una escritura y mirar si sale la tarjeta.
   c. Desde el dock, ⋯ → Remote Control otra vez. ¿Devuelve el mismo link L1 o uno nuevo? ¿El viejo deja de andar?
   d. Con «/remote-control off» desde el composer, ¿el celular ve la sesión cerrada?
4. Con eso se decide:
   - Si Claude la mantiene prendida, el dock debería volver a mostrar la franja. El link puede guardarse en el historial de la sesión, o pedirse de nuevo con /remote-control.
   - Si Claude la apaga, que quede escrito en la wiki que una sesión retomada arranca con Remote Control apagado.

D. Reiniciar el editor con Remote Control prendido
1. Con Remote Control prendido y el celular conectado, cerrar el editor normalmente.
2. Mirar en el celular: ¿la sesión se ve cerrada u «offline»? ¿Un mensaje nuevo da error?
3. Abrir el editor. Mirar: el dock arranca sin franja, que es lo esperado. Retomar la sesión desde Historial y repetir C.3a y C.3c.
4. Opcional: matar el editor con kill -9 en lugar de cerrarlo. ¿Queda algún proceso claude/adapter vivo (`pgrep -fa claude-agent-acp`)? ¿El celular queda colgado?

Al terminar
- Resultados en D58 (un punto «Probado con Claude real, <fecha>, adapter <versión>»), con lo de C y D.
- Wiki en/es, Modes-and-permissions → Remote Control: qué pasa al retomar una sesión y al reiniciar.
- Si C muestra que sigue prendido, crear una tarea para mostrar la franja al retomar.
- No dejar el proyecto de prueba con las líneas `# remote …`: Deshacer desde el aviso, que de paso prueba Deshacer.

### Markdown del chat: tablas, listas, bloques de código y más · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** media · **Tamaño:** M · **Responsable:** Claude

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

### Prueba: hablar con Claude Code en stream-json desde GDScript, sin claude-agent-acp · Revisión

**Prioridad:** baja · **Tamaño:** M

Hoy Claude Code se usa a través de `npx -y @agentclientprotocol/claude-agent-acp`, lo que obliga a tener Node. Claude Code tiene un modo sin interfaz (`claude -p --input-format stream-json --output-format stream-json --verbose --include-partial-messages --mcp-config … --permission-prompt-tool mcp__godot__permission`) y, con el instalador nativo, es un binario autónomo. Prueba corta: lanzarlo desde GDScript, mandar un prompt que use una tool godot.* y una que pida permiso, y registrar qué eventos llegan (texto en streaming, tool calls y resultados, uso, rate limit, resultado) con la versión instalada. Con eso decidir si vale un segundo transporte solo para Claude (ACP queda para Gemini CLI y Codex). Revisar qué se pierde del adapter: cambio de modo y modelo, cancelar, --resume, imágenes, login, /remote-control, _meta de subagentes.

**Prueba:** `godot --headless --path . --script tests/stream_json_probe.gd [-- <modelo>]` (manual, gasta tokens, ~USD 0,17 con haiku): termina con exit 0 y las líneas T1–T7 en success (T4 interrupt da error_during_execution, que es lo esperado). Deja probe.txt con «chau» en el sandbox y el log en tests/tmp/stream_json_probe/events.jsonl. D62 en docs/decisions.md tiene el informe.

**Notas:** Rama sm/m7-31 (worktree .claude/worktrees/m7-31), commit 567b97b desde 9501d7f. Sin cambios en addons/godot_agent. Probado con Claude Code 2.1.321 nativo y Godot 4.7.2. Funciona: initialize (modelos, comandos, cuenta, remote_control_available), tool godot.* por HTTP (diferida: pasa por ToolSearch), can_use_tool por stdio y permiso por una tool MCP, set_model, set_permission_mode, imagen base64, interrupt (8–21 ms, la sesión sigue), /context, subagente (task_* + parent_tool_use_id con --forward-subagent-text), --resume en un proceso nuevo (no repite el historial), rate_limit_event. Sin login: authentication_failed «Not logged in», sin método de login. No probé /remote-control en -p porque abre una sesión real. Recomendación (D62): no hacer el segundo transporte ahora; si se hace, como shim stream-json⇄ACP para no duplicar SessionController. Ojo: D62 puede chocar con otra rama que agregue una D62.

## M8a — Completado predictivo: núcleo sin IA  (7/7)

CompletionController, GhostTextRenderer de una línea, Tab/Esc, ProjectContext en segundo plano y proveedor local (reglas, recuperación, historial + ranker).

**Hecho cuando:**
- `@onready var ` sugiere nodos hijos reales con tipo y ruta; `func _` sugiere virtuales con firma; una línea repetida se sugiere al tipear su comienzo.
- Tab sin sugerencia sigue indentando y el popup nativo no se rompe.
- p95 < 10 ms por consulta en un proyecto de 200 scripts (medido y logueado).

### 8.7 Verificar M8a · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** S · **Responsable:** Claude

@onready var sugiere nodos hijos reales con tipo y ruta; func _ sugiere virtuales con firma; una línea repetida se sugiere; Tab sin sugerencia indenta y el popup nativo no se rompe; p95 < 10 ms. Actualizar progress.

**Prueba:** run_all (109 tests, 752 checks), acp_session_check (90) y oneshot_check (34) en 4.4.1, 4.7.2 y 4.8-beta1; --godot-agent-completion-test (onready, nodo único, Tab+undo, Esc, ancla en el caret, func _, línea repetida, Tab indenta, autocierre, popup nativo) y cycle test en las tres; bench p95 1,29/1,43/1,62 ms.

**Notas:** Revisión de código aplicada (selección/multi-caret, % operador, binds y señales multilínea, cachés, Script Editor flotante, tipos desconocidos, costo por tecla, guarda de dibujo, fondo con cierres, indexado apagado, exclude, Alt+\, whitelist de recursos, no adivinar, cancelación). Riesgo conocido documentado en D26: recarga @tool con build en curso. El cycle test crece 29 objetos también sin el servicio de completado (previo a M8a).

### 8.6 Fixture, tests y benchmark del completado · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** M · **Responsable:** Claude

tests/completion_fixture/ (escenas, %únicos, input map, autoloads, señales); tests de cada regla, retrieval y ranker; benchmark con 200 scripts generados: p95 < 10 ms por consulta, logueado.

**Prueba:** tests/unit/test_completion_bench.gd: 200 scripts + 60 escenas generados, 1500 consultas: p95 1,52 ms (4.8), 1,61 (4.7.2), 1,73 (4.4.1); imprime la medición y falla si p95 ≥ 10 ms.

**Notas:** tests/completion_fixture/ (con .gdignore; input map y autoloads en project_settings.cfg), tests/fake_completion_provider.gd, test_completion_{rules,local,controller,bench}.gd (23 tests), addons/godot_agent_dev/completion_check.gd (Script Editor real).

### 8.5 LineRetrieval, SessionHistory y Ranker · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** M · **Responsable:** Claude

Índice de líneas normalizadas con puntaje frecuencia × cercanía × recencia; predicción de línea siguiente; historial de sesión estilo fish; ranker con umbral, margen y desempate por longitud; presupuesto <5 ms en el hilo principal.

**Prueba:** tests/unit/test_completion_local.gd (índice, cercanía × recencia, ambigüedad, historial, ranker, post-procesado, reglas primero); bench p95 1,5–1,7 ms.

**Notas:** line_index.gd (bsearch sobre líneas únicas ordenadas), typed_history.gd, ranker.gd, local_provider.gd, post_processor.gd (M8a: una línea, solapamiento con suffix, descartes, balanceo). La predicción de línea siguiente quedó para M8b (m9-01).

### 8.4 ContextRules · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** M · **Responsable:** Claude

Reglas de la tabla §16.2a: @onready var, $/%, acciones de input, func _ virtuales con firma, .connect(, func _on_, grupos, preload/load, extends.

**Prueba:** tests/unit/test_completion_rules.gd: un test por regla sobre tests/completion_fixture.

**Notas:** local/context_rules.gd: @onready var (nombres repetidos con el padre), $/%, acciones, func _ virtuales, .connect(, func _on_ (solo con firma conocida), grupos, preload/load por tipo, extends.

### 8.1 CompletionController: disparo, debounce e invalidación · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** M · **Responsable:** Claude

Uno por CodeEdit (enganche con editor_script_changed). Dispara con caret al final o solo cierres a la derecha, sin selección, popup nativo cerrado, archivo .gd. Invalida al mover de línea, tipear distinto, Esc o perder foco. Type-through. Atajo manual Alt+\ (spec §16.5).

**Prueba:** tests/unit/test_completion_controller.gd (CodeEdit real, reloj simulado: debounce, condiciones de disparo, type-through, invalidación, respuesta vieja, Alt+\); --godot-agent-completion-test en 4.4.1/4.7.2/4.8.

**Notas:** completion/completion_controller.gd + completion_service.gd. text_changed/caret_changed llegan diferidos: se compara contra el último estado (línea, columna, get_version). Debounce vía tick(now) desde el servicio. Detalles en D26.

### 8.2 GhostTextRenderer y aceptación · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** M · **Responsable:** Claude

Texto atenuado con draw_string sobre el CodeEdit respetando fuente, scroll, wrap y zoom. Tab acepta (una acción de undo), Esc descarta; interceptar solo con sugerencia visible y popup cerrado. Documentar si gui_input alcanza o hace falta _input.

**Prueba:** test_completion_controller (Tab acepta en una acción de undo, Tab sin sugerencia indenta, Esc, popup nativo); --godot-agent-completion-test con capturas (posición en el caret, recorte al área de texto).

**Notas:** gui_input + accept_event alcanza (no hizo falta _input). x del ghost = get_caret_draw_pos: get_rect_at_line_column al final de la línea devuelve el carácter anterior (4.4 y 4.8). TextLine recortado sin minimapa ni scrollbar.

### 8.3 ProjectContext indexado en segundo plano · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** L · **Responsable:** Claude

extends/class_name y API de la clase base (ClassDB), firmas de clases del proyecto, nodos hijos por escena que usa el script ($ y %), autoloads, input map, grupos, señales conectadas. Invalidación por archivo con filesystem_changed.

**Prueba:** test_completion_rules.test_context_index (fixture); test_completion_bench (build 200 scripts ≈180 ms, rebuild incremental).

**Notas:** project_index.gd (worker, inmutable al publicarse, reutiliza por mtime salvo archivos de <2 s) + project_context.gd (ClassDB, ProjectSettings, escena abierta con caché). Sin persistencia: <1 s.

## M8b — Completado predictivo: calidad local  (6/6)

Línea siguiente y bloques cortos, ghost text multilínea, aceptación por palabra, n-gram, adaptación de identificadores, post-procesado completo, caché y set de evaluación.

**Hecho cuando:**
- El set de evaluación reporta resultados por fuente y el n-gram mejora la línea base de reglas + recuperación.

### 8b.6 Verificar M8b · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** S · **Responsable:** Claude

El set de evaluación reporta resultados por fuente y el n-gram mejora la línea base de reglas + recuperación. Ajustar umbrales priorizando precisión. Actualizar progress.

**Prueba:** Eval en 4.4.1/4.7.2/4.8 (iguales): reglas+recuperación 19 mostradas/17 correctas/2 FP; +n-gram 20/18/2 FP (antes de M8b: 17/11/6 FP). test_completion_eval exige más correctas con n-gram, FP sin subir, precisión >= 0,85, p95 < 10 ms. Todas las suites pasan en las 3 versiones (run_all 122 tests/877 checks sin los de M8c, acp 90, oneshot 34, cycle, completion en el editor).

**Notas:** Ajustes por precisión: veto de reglas cuando no pueden elegir, convención de nombres de @onready aprendida del proyecto, hijos directos primero, herencia, load(" por nombre de variable, clase número en el n-gram, salida del n-gram con al menos un nombre. Probados y descartados: min_support 1 (más FP); umbral del n-gram sin el factor de backoff (sin cambios en el set). Quedan 2 FP ambiguos de verdad. Revisión de código: 9 hallazgos corregidos (race del vocabulario del n-gram, adaptación con prefijo existente, caché con generación, Tab en el mismo frame, líneas largas, build cancelado, 2 espacios, sangría en el contexto del n-gram, recorte del overlay); detalle en progress.md. progress.md, D27 y README actualizados.

### 8b.5 Set de evaluación del completado · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** M · **Responsable:** Claude

tests/completion_eval/ con 30–50 recortes reales y script headless que corre cualquier combinación de fuentes: exact match de primera línea, similitud por tokens, cobertura, falsos positivos y latencia, por fuente.

**Prueba:** godot --headless --path . --script tests/run_completion_eval.gd [-- combos] [--cases]: 48 casos, tabla por combinación y por fuente ganadora (exactas, correctas, FP, similitud, cobertura, p50/p95). test_completion_eval valida los casos y corre la regresión.

**Notas:** tests/completion_eval/project: juego propio "Mossy Caverns" (33 scripts, 20 escenas, .gdignore). cases.txt: file | line | cut, ⏎ marca espacio final, 4 grupos. El runner corta el archivo en el caret y lo pasa como buffer sin guardar. El historial arranca vacío por caso (se prueba en unit).

### 8b.4 PostProcessor y SuggestionCache · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** M · **Responsable:** Claude

Pasos de §16.6 en orden (tokens FIM, recorte al bloque, solapamiento con suffix, indentación del editor, descartes, chequeo de balanceo) y caché LRU por hash de prefix. Tests con salidas defectuosas reales.

**Prueba:** run_all -- completion: test_post_processor_defective_outputs (FIM, stops, recorte, solapamiento, sangría tabs/espacios, paréntesis multilínea), test_suggestion_cache (LRU, hits/misses). El servicio vacía la caché al publicar índice y al cambiar Settings.

**Notas:** PostProcessor.process(text, request, max_lines, stops). Con suffix no vacío fuerza una línea. Sangría con request.indent_unit() (indent_use_spaces/indent_size del CodeEdit). SuggestionCache: 64 entradas, clave ruta:hash del texto:línea:largo del prefijo:manual:generación del proveedor (índice, ProjectSettings, escena abierta, historial; agregada por la revisión: sin ella devolvía sugerencias viejas). Los resultados en caché se marcan cached y se loguean como hit.

### 8b.3 Lexer GDScript y modelo n-gram · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** L · **Responsable:** Claude

Lexer simple (identificadores, keywords, operadores, strings, números, newline/indent/dedent); 4-gramas con stupid backoff, generación greedy hasta fin de línea o confianza baja; entrenamiento en WorkerThreadPool, actualización por archivo; corpus extra configurable.

**Prueba:** run_all -- completion: test_completion_ngram (lexer, generation, incremental_update = reentrenar, provider_uses_ngram). Eval: el n-gram solo da 5/5 correctas sin FP y suma 1 correcta sobre reglas+recuperación sin sumar FP. Bench: build 785–817 ms con 200 scripts (< 1 s), p95 < 2,3 ms.

**Notas:** Tokens con su espacio adelante; claves int (20 bits por id); clase <num> en contextos; COW por archivo si cambió <= 30 %, mismo objeto si nada cambió. Generación: paso > 0,5, acumulada > 0,3, soporte >= 2, para en empates. Cachés de stats y rangos ordenados (bsearch) en el hilo principal: p95 3,7 -> 0,7 ms. Regex compiladas al cargar (static var): lazy era una carrera worker/main. Corpus extra (godot_agent/completion/extra_corpus) solo entrena el n-gram.

### 8b.2 Ghost text multilínea y aceptación por palabra · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** M · **Responsable:** Claude

Primera línea inline y el resto en una caja translúcida bajo la línea actual (o +N si queda mal, documentado). Ctrl+→ acepta la siguiente palabra (accepted_partial).

**Prueba:** Editor real en 4.4.1, 4.7.2 y 4.8 (completion_check paso 7): bloque de 3 líneas visible, renderer.box de >= 2 filas, Ctrl+→ inserta `combo_multiplier` y deja ` = 1…`, Tab inserta el resto. Capturas ampliadas: caja legible, `")` del autocierre tapado, caret visible. Unit: next_word en test del controller.

**Notas:** Overlay: canvas item propio hijo del CodeEdit (RenderingServer), limpiado en cada draw y liberado en detach/PREDELETE. Lo dibujado desde la señal draw quedaba bajo el texto en 4.8, así que el tapado de cierres de M8a no funcionaba; quedó corregido acá. Caja casi opaca (0,96, sin el alpha del theme: en 4.4 el fondo es translúcido), fondo del stylebox normal (background_color es transparente en el Script Editor). Si abajo no entra y arriba hay más lugar, la caja va arriba (pasa en 4.4 con el caret en la última fila). Ctrl+→ = command_or_control; signal accepted_partial y log en cmp.

### 8b.1 Línea siguiente, bloques cortos y adaptación de identificadores · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** M · **Responsable:** Claude

Recuperación de bloques de hasta N líneas mientras el corpus coincida y la indentación se mantenga; adaptación de un identificador (mana/health) aplicada al resto de la línea (spec §16.2b).

**Prueba:** run_all -- completion: test_next_line_and_blocks, test_identifier_adaptation, test_provider_next_line_blocks_and_adaptation. Editor (--godot-agent-completion-test, 4.4.1/4.7.2/4.8): después de `func reset() -> void:` + Enter se sugiere el cuerpo de 3 líneas de otros dos scripts. Eval: 7 casos de línea siguiente/parientes ganados por recuperación.

**Notas:** LineIndex guarda la secuencia de líneas por archivo (texto + sangría) y, para cada clave ordenada, las posiciones [archivo, línea]. Línea siguiente: en línea vacía tras una con código; sangría relativa, nunca menor que la escrita. Bloques: extend() exige que todas las apariciones (>= 2) sigan iguales; corta en línea en blanco, sangría menor, max_lines o la línea de abajo. Adaptación: rotaciones de identificadores (MAX_ROTATIONS 4), sustitución snake/Pascal/UPPER, peso 0,9, sin bloque. SUPPORT_SCALE bajado a 1 por el eval (D27).

## M8c — Completado predictivo: LLM opcional  (4/4)

Proveedor Ollama y modo híbrido; después llama.cpp, Codestral, OpenAI-compatible y Gemini (experimental). Métricas e indicador en el Script Editor.

**Hecho cuando:**
- Cambiar de proveedor y de modo desde Settings sin reiniciar el editor.
- En híbrido, la sugerencia local nunca se demora por el LLM.
- Latencias p50 por fuente visibles en el log.

### 8c.4 Verificar M8c · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** S · **Responsable:** Claude

Cambiar de proveedor y modo desde Settings sin reiniciar; en híbrido la sugerencia local nunca se demora por el LLM (proveedor falso lento); latencias p50 por fuente en el log. Ollama real si está instalado. Actualizar progress.

**Prueba:** Matriz en 4.4.1, 4.7.2 y 4.8-beta1: run_all 131 tests / 995 checks, acp_session_check 90, oneshot_check 34, cycle test y --godot-agent-completion-test con el paso híbrido contra tests/fake_llm_server.gd (cambio de modo sin reiniciar, un solo pedido con modelo y prefix, marcador, error, vuelta a local sin pedidos). Lo local nunca espera al LLM: test_hybrid_mode con un proveedor falso de 300 ms en vuelo.

**Notas:** Ollama y llama.cpp no están instalados en esta máquina: no se probó contra un modelo real (pasos manuales en progress.md M8c). Revisión de código del diff hecha y corregida (progress.md M8c › Revisión de código): body de error al log, JSON de perfiles con tipos inválidos, redirecciones que reenviaban key y código (max_redirects 0, body ≤ 1 MB), Codestral/Gemini sin key, suffix con caret al final de línea, HTTPRequest sin liberar en un controller reemplazado. Además is_remote con [::1] y keys sin guiones. Los settings del paso del editor son los EditorSettings reales y se restauran al terminar.

### 8c.3 Métricas, indicador y settings del completado · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** media · **Tamaño:** M · **Responsable:** Claude

Canal cmp con fuente, latencia, tamaños, resultado y caché (sin código salvo raw). Contadores p50/p95 y aceptación por fuente en Settings. Indicador en el Script Editor (estado y modo, clic on/off, atajo global). Settings de §16.10 aplicables sin reiniciar.

**Prueba:** test_settings_dialog: test_completion_section (carga, validación de la sección: key pegada con y sin guiones, codestral sin variable, híbrido sin perfiles, corpus relativo; stops con escapes; ABM de perfiles con id libre y activo; aviso de host remoto) y test_completion_save (cada valor a EditorSettings o a project_config; tabla de contadores). En el editor real: indicador en la barra del Script Editor con «local» → «híbrido · fake-coder», «pensando» mientras espera, error con HTTP 500, Alt+Shift+\ apaga y prende; cambio de modo sin reiniciar.

**Notas:** completion_metrics.gd: p50/p95 (últimas 200), mostradas/aceptadas/parciales/errores por fuente; en el log cada 10 sugerencias y en Settings → Completado («Esta sesión, por fuente», con reinicio). completion_indicator.gd: Button en el primer HBoxContainer con MenuButton del Script Editor. Settings → Completado es una página propia (ui/settings/completion_settings_page.gd) que el diálogo agrega como sección; completion_enabled y completion_exclude entran en el rollback de CONFIG_PROPERTIES. plugin.gd conecta completion_metrics_provider/reset. El log cmp nunca lleva código salvo completion/log_raw; un error HTTP solo muestra campos de mensaje conocidos (revisión: un 422 de FastAPI repite el prompt).

### 8c.2 Proveedores Ollama, llama.cpp, Codestral, OpenAI-compatible y Gemini · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** media · **Tamaño:** L · **Responsable:** Claude

Endpoints verificados contra la documentación y anotados en decisions.md. Plantillas FIM por perfil, stop tokens, keys por nombre de variable de entorno, aviso de envío de código en perfiles remotos, Gemini marcado experimental. Contexto de ProjectContext con presupuesto y prioridad.

**Prueba:** test_completion_llm: test_profiles (defaults por tipo, is_remote con localhost/127.0.0.1/[::1] vs red, experimental, to_dict sin key), test_build_requests (URL, headers y body de los 5 tipos, plantillas FIM, límites de stops), test_parse_responses (formatos, errores, cercos y thought de Gemini, respuesta bloqueada), test_split_and_context (recorte en salto de línea, contexto con presupuesto). test_settings_dialog: key pegada rechazada, aviso de host remoto.

**Notas:** Endpoints verificados (docs y código en el scratchpad dl/) y anotados en D28: Ollama /api/generate (suffix → 400 en modelos sin FIM; con plantilla, raw:true), llama.cpp /infill en el puerto 9931 con input_extra, Codestral /v1/fim/completions en api.mistral.ai (additionalProperties false), OpenAI /v1/completions con la plantilla de Qwen por defecto (suffix no es portable, máx. 4 stops), Gemini generateContent con x-goog-api-key, gemini-3.5-flash-lite, experimental. Keys solo por nombre de variable (OS.get_environment en cada pedido; vacía → no se manda nada). Contexto de ProjectContext como comentarios #, prioridad nodos > base > clases > autoloads > acciones > grupos, 4 chars/token. Sin Ollama ni llama.cpp en la máquina: no se probó contra un modelo real.

### 8c.1 Interfaz de proveedores, proveedor falso y modo híbrido · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** M · **Responsable:** Claude

CompletionProvider (complete/cancel/describe) con LlmProvider sobre HTTPRequest reutilizado; tests/fake_completion_provider.gd con latencia configurable; modos solo local / híbrido / solo LLM con las reglas de §16.1 (el LLM nunca reemplaza ni demora lo local; una request en vuelo; secuencia).

**Prueba:** test_completion_controller: test_hybrid_mode (lo local en el mismo frame aunque haya un LLM falso de 300 ms en vuelo; sin pedido si hubo algo local; debounce del LLM; tipear cancela y la respuesta cancelada no se muestra; Alt+\ fuerza el LLM) y test_llm_only_mode. test_completion_llm: LlmProvider contra tests/fake_llm_server.gd (respuesta, cancelación sin esperar al server, reutilización del HTTPRequest, HTTP 404, conexión rechazada, sin key no se manda nada). En el editor real (--godot-agent-completion-test, 4.4.1/4.7.2/4.8): híbrido de punta a punta contra el server falso.

**Notas:** LlmProvider: un HTTPRequest por editor SIN hilos (con use_threads, cancel_request() espera al hilo y se traba contra un server en el hilo principal). cancel_request() no emite request_completed: la cancelación se avisa a mano (RESULT_CANCELLED propio) y un contador de generación descarta respuestas tardías. Controller: MODE_LOCAL/HYBRID/LLM; en híbrido _llm_due = max(ahora, última tecla + debounce LLM) solo si no hubo nada local; la respuesta se muestra solo si suggestion vacía y seq/versión/caret iguales. tests/fake_completion_provider.gd ahora tiene `source` configurable. D28.

## M9 — Ideas de otros harness  (61/67, 40 en revisión)

Lo que vale la pena traer de Claude Code, Codex, Antigravity, Copilot y Cursor, adaptado a Godot: deshacer y revisar por turno, sesiones que avisan, verificación automática, chat en línea en el Script Editor, artefactos del juego, más contexto y trabajo en segundo plano.

**Hecho cuando:**
- Cada idea quedó hecha o descartada con su motivo en la tarjeta.

### Cuota por grupo de modelos en el tooltip · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** baja · **Tamaño:** S · **Etiquetas:** `acp`

Antigravity tiene cuotas separadas por grupo (Gemini, Claude y GPT, Gemini 4 Argon) y los anillos muestran solo el del modelo en uso. Mostrar todos los grupos en el tooltip de los anillos, como el menú View Usage del IDE de Antigravity.

**Prueba:** tests/unit/test_quota_monitor.gd test_antigravity_usage (describe_groups, QuotaRing.describe y select_antigravity_model).

**Notas:** QuotaMonitor.groups guarda los grupos de /usage, describe_groups() arma una línea por grupo (Gemini, Claude y GPT, Gemini 4 Argon) y QuotaRing.describe() las agrega al tooltip debajo de los anillos. select_antigravity_model() cambia las ventanas activas en cuanto cambia la opción model.

Revisión (2026-10-28): sin problemas en lo propio de esta tarea. Nota: con varios grupos de Codex, config_options_changed también llama a select_antigravity_model, que aplica la heurística de Antigravity (no rompe nada hoy).

### Cuota de los demás agentes · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** media · **Tamaño:** M · **Etiquetas:** `acp`

Claude (usage_update _meta _claude/rateLimit) y Antigravity (/usage) ya informan la cuota. Ver qué informan Codex, Copilot y Cursor por ACP (usage_update, _meta, comandos como /status) y leerlo sin endpoints ni archivos del agente (regla de QuotaMonitor).

**Prueba:** tests/unit/test_quota_monitor.gd test_codex_and_other_agents_quota, test_opencode_payload_and_codes_only_in_errors y test_codex_status_locale_and_spend. No probado contra codex-acp real.

**Notas:** Codex (codex-acp): usage_update solo trae tokens de contexto, pero su comando local /status (sin gastar tokens) informa las ventanas de 5 h y semanal de RateLimitsMap y la cuenta; SessionController._query_agent_usage lo pide igual que /usage de Antigravity, y _auth/status_update mantiene model.account al día. OpenCode: reintentos por límite en session_info_update (_meta["opencode/retry"]). Copilot y Cursor no mandan ventanas de cuota por ACP: se detectan sus errores y textos de límite.

Revisión (2026-10-28, 2431546, 651d557 y c32c82c): Codex nunca se detectaba: el adaptador del registro se llama @agentclientprotocol/codex-acp, y el viejo de Zed (codex-acp) no tiene /status y se lo mandaría al modelo como prompt. Ahora _usage_agent() pide nombre …/codex-acp y que anuncie el comando status. La consulta oculta se cancela a los 20 s (session/cancel + $/cancel_request), y no hace nada si el agente ya se detuvo. La cuenta de _auth/status_update se borraba con el _refresh_account del session/new; ahora se guarda (_agent_account) y se olvida al reiniciar el agente o cerrar sesión. Retry real de OpenCode (provider.rate-limit, status 429). Los códigos insufficient_quota, rateLimitExceeded, etc. solo se buscan en errores (LIMIT_CODES_IN_ERRORS), no en la prosa del agente. /status: fechas con locale (3 dic., 3 de nov.), 24:05 como 00:05, grupos con espacios, y el límite de gasto del asiento no pisa la semanal. Queda: el offset de zona es el de hoy y no el del día del reinicio (cambio de horario).

### Extensiones por agente: skills, plugins, reglas e instrucciones · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** media · **Tamaño:** L · **Etiquetas:** `acp`

La pestaña de Extensiones (skills, plugins, marketplaces) es solo de Claude Code. Investigar y soportar lo equivalente de cada agente con perfil: Codex (skills, AGENTS.md, config de MCP), Antigravity (AGENTS.md y GEMINI.md, reglas, workflows y skills, a confirmar dónde los lee), Copilot, Cursor y OpenCode. Lo que sea por archivos se arma desde el editor; lo que el agente anuncie por ACP (available_commands, configOptions) ya se muestra.

**Prueba:** godot --headless --path . --script tests/run_all.gd -- claude_extensions skill_catalog (test_codex_toml_variants, test_codex_toml_multiline_strings y test_project_dirs_per_agent). No probado en el editor con perfiles de cada agente.

**Notas:** Extendidas las pestañas Skills, Instructions y MCP de Extensions a todos los agentes: detección de perfil (Claude, Codex, Antigravity, Copilot, Cursor, OpenCode) en ClaudeExtensions.agent_kind(); escaneo, creación, importación y copia de skills en SkillCatalog y SkillsTab; edición y alta de instrucciones, reglas y workflows en InstructionsTab; y lectura de MCP servers desde config.toml de Codex, mcp_config.json de Antigravity, .cursor/mcp.json, .vscode/mcp.json y opencode.json en ClaudeExtensions.agent_mcp_servers().

Revisión (2026-10-28, 2431546, 651d557 y c32c82c): regresión en Claude: project_dirs listaba .agents/skills, .codex/skills, etc. para todos y aparecían como del proyecto skills que Claude no carga. Ahora PROJECT_SKILL_DIRS da las de cada agente. .mcp.json ya no se lista para agentes que no son Claude. config.toml de Codex con un lector de TOML acotado (extensions/toml_lite.gd): comentarios al final, arrays de varias líneas, strings literales, strings de comillas triples, tablas en línea, claves con puntos. Rutas de Antigravity verificadas contra la documentación actual: .agents/rules, .agents/workflows, .agents/skills, .agents/plugins, ~/.gemini/config/skills, ~/.gemini/config/mcp_config.json y ~/.gemini/config/plugins son las vigentes (.agent/ sigue por compatibilidad). Quedan: JSONC (opencode.jsonc, .vscode/mcp.json con comentarios) no se lee; Gemini CLI se detecta como «other»; borrar una skill de ~/.agents/skills la saca para todos los agentes sin decirlo.

### Cancelar requests en vuelo ($/cancel_request) · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** baja · **Tamaño:** S · **Etiquetas:** `acp`

Soportar $/cancel_request en las dos direcciones: el cliente cancela un request que ya no espera (por ejemplo un /usage o un session/load que se dejó) y atiende el del agente cancelando permisos, fs o terminales pendientes.

**Prueba:** tests/unit/test_acp_client.gd test_cancel_request_both_directions y test_incoming_cancel_mark_survives_await (falla sin el arreglo).

**Notas:** AcpClient.cancel_request(id) manda $/cancel_request, resuelve el await local con ERR_REQUEST_CANCELLED (-32800) e ignora respuestas tardías; SessionController._cancel_abandoned_requests() cancela /usage, /status o session/new|load|resume en vuelo al abrir otra sesión. Del lado entrante, $/cancel_request emite incoming_cancelled (cancela tarjetas de permiso de request_permission, fs/write_text_file y terminal/create en _ask_user, elicitations y esperas de terminal) y responde -32800 sin duplicar si el handler termina más tarde.

Revisión (2026-10-28, 2431546): is_incoming_cancelled() nunca daba true (la marca se borraba en la misma llamada que la ponía), así que un terminal/create cancelado igual lanzaba el proceso. Ahora la marca dura hasta que el handler termina. handling_id se limpia en receive_line apenas el handler se suspende. Quedan: un -32800 del propio agente se toma como cancelación local (session/new podría quedar en STARTING); _cancelled_outgoing crece si el agente nunca responde.

### Formularios del agente (elicitation/create y complete) · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** media · **Tamaño:** M · **Etiquetas:** `acp`

ACP v1 suma elicitation/create y elicitation/complete del lado del cliente: el agente pide datos al usuario con un esquema (texto, opciones, confirmación). Anunciar la capacidad y mostrarlos como tarjeta en el dock, como los permisos.

**Prueba:** godot --headless --path . --script tests/run_all.gd -- elicitation (incluye test_rejects_local_links_and_json_numbers, test_controller_rejects_invalid_elicitation, test_untouched_optional_fields_are_left_out). No probado con un agente real que mande elicitation/create ni la tarjeta en el editor.

**Notas:** Agregados ElicitationRequest (session/elicitation_request.gd) y ElicitationView (ui/dock/entries/elicitation_view.gd) para formularios (mode: form con string, enum/oneOf, boolean, integer/number y array multi-select) y enlaces (mode: url). Conectados elicitation/create, elicitation/complete, $/cancel_request y clientCapabilities.elicitation en SessionController, SessionModel y ConversationView.

Revisión (2026-10-28, 2431546 y 651d557): un enlace que no era http(s) iba por open_link del chat y terminaba en OS.shell_open de un archivo local. Ahora invalid_reason() rechaza con -32602 modos desconocidos, url sin elicitationId o que no es http(s); la URL se ve en la tarjeta y se abre directo en el navegador. minLength/minItems no se validaban nunca (JSON trae floats). Un booleano o número opcional sin default que el usuario no tocó no se manda; los number no se redondean (step 0); un default no numérico no rompe. elicitation/complete con el enlace pendiente responde cancel (antes accept sin que el usuario aceptara) y no toca formularios. Las pestañas de fondo muestran «⚠» y toast también para formularios. Quedan sin validar: maxLength, maxItems, pattern y format; enumNames; un required enum sin default preselecciona la primera opción.

### Sesiones del agente: session/list, resume, close y delete · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** media · **Tamaño:** M · **Etiquetas:** `acp`

Los agentes anuncian sessionCapabilities.list y resume (Antigravity los tiene; session/list devuelve id, cwd y título). Mostrar en el historial las sesiones que guarda el agente para el proyecto (cwd), retomarlas con session/resume cuando no hay loadSession o no hace falta repetir el historial, y cerrar o borrar con session/close y session/delete si el agente los anuncia.

**Prueba:** godot --headless --path . --script tests/run_all.gd -- session_model (test_session_capabilities_and_merge, test_history_begin_from_agent_listing). acp_session_check 159/0. No probado contra un agente real con session/list (Antigravity) ni el diálogo de borrar en el editor.

**Notas:** SessionModel (supports_list_sessions, supports_resume_session, supports_close_session, supports_delete_session y can_resume_sessions) y SessionController (list_agent_sessions con paginación por cursor, _load_session con session/resume cuando ya hay historial local o sin loadSession, close_session en open_session, delete_session local y en el agente, y merge_session_lists en el menú de historial de AgentDock).

Revisión (2026-10-28, 2431546): retomar una sesión que solo lista el agente rompía el historial (el registro no traía created y save() fallaba): SessionHistory.begin completa la cabecera. Borrar desde el menú pide confirmación, manda session/delete solo si la sesión es del perfil conectado y, si el agente falla, deja la local y avisa. open_session resetea el modelo antes del await del close (sin doble session/new ni prompts a la sesión que se cierra) y un segundo «Nueva sesión» durante el close se ignora. El One-shot usa open_session_keeping_previous() para no cerrar la sesión del generador que después vuelve a cargar. agent_sessions se vacía al pasar a un agente sin session/list; se sacó el filtro por cwd del cliente (en Windows descartaba todo). c32c82c: session/close se cancela a los 10 s (CLOSE_TIMEOUT_S), así un agente que no contesta no deja «Nueva sesión» sin efecto. Quedan: el menú muestra la lista del pedido anterior; tope de 3 páginas; updatedAt ignora el offset de zona; fake_agent no implementa list/resume/close/delete (el timeout del close no tiene test).

### Terminales del cliente ACP (terminal/*) · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** L · **Etiquetas:** `acp`

Hoy clientCapabilities.terminal es false: los agentes corren sus comandos por su cuenta. Implementar terminal/create, output, wait_for_exit, kill y release para que los comandos del agente corran desde el editor, con la política de shell (reglas de Auto, permisos por modo), salida en la tarjeta del tool call y límite de bytes. Lo usan Codex y otros agentes del registro; se prueba con Claude Code y Antigravity.

**Prueba:** godot --headless --path . --script tests/run_all.gd -- terminal_handler (test_quoting_and_agent_env_ask: comillas POSIX, Auto permite ls -la sin env y pregunta con LD_PRELOAD, sin regla propuesta; test_command_key_ignores_quoting). No probado con un agente real que use terminal/* (Codex) ni en Windows.

**Notas:** TerminalHandler (terminal/create, output, wait_for_exit, kill y release) con AgentProcess en modo raw (sin threads), truncado UTF-8 desde el principio según outputByteLimit, autorización por SessionController (ProjectWriteGuard, GodotWindowGuard, ShellRules en Auto y tarjetas de permiso), clientCapabilities.terminal = true y visualización de bloques {type: terminal, terminalId} en ToolGroupView.

Revisión (2026-10-28, 2431546): el env del agente pasaba sin filtro y la política no lo veía (en Auto, git status + GIT_CONFIG_* corría código sin preguntar). Ahora con env siempre se pregunta, la tarjeta muestra NOMBRE=valor y el cwd si no es el del proyecto, y no propone regla. format_command_line cita cada arg como sh (shell_quote): las guardas revisan lo mismo que corre. En Windows se rechazan args con comillas o saltos de línea (cmd.exe no las escapa). Las terminales se matan si el agente se cae o al abrir otra sesión. handling_id ahora solo vale mientras el handler no se suspende (antes una tarjeta de una tool MCP quedaba asociada a un wait_for_exit y un $/cancel_request la cancelaba). c32c82c: los comandos preautorizados se comparan por palabras sin comillas (SessionController.command_key), así npm run "a b" del agente y npm run 'a b' de terminal/create no preguntan dos veces. Quedan: exit_signal SIGTERM fijo aunque Unix manda SIGKILL; la tarjeta de un fallo muestra el principio de la salida y no el final; la decodificación UTF-8 por chunk puede cortar un carácter.

### Cerrar sesión de la cuenta del agente (ACP logout) · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** S · **Etiquetas:** `acp`

Acceso rápido para cerrar la sesión de la cuenta en cualquier agente que anuncie agentCapabilities.auth.logout (Claude Code con claude auth logout, Antigravity): botón en la línea de estado con confirmación; el agente borra sus credenciales, se cierra la sesión y la próxima pide login.

**Prueba:** test_session_model test_supports_logout. Sin probar contra la cuenta real (borraría las credenciales).

**Notas:** Método ACP logout (SDK 2.1: AGENT_METHODS.logout = "logout"), anunciado con agentCapabilities.auth.logout. SessionController.logout: request, olvida cuenta y cuota, detiene el agente y avisa. Botón «Cerrar sesión» en la fila de estado del dock con confirmación.

### Cuota de Antigravity con /usage · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** S · **Etiquetas:** `acp`

Antigravity no manda la cuota en usage_update (solo el contexto, used/size). Su comando /usage, que no gasta tokens, lista por grupo de modelos (Gemini, Claude y GPT, Gemini 4 Argon) cuánto queda de la semana y de las 5 h, con la hora de reinicio en UTC: lo mismo que el menú View Usage del IDE de Antigravity, que lo saca del backend de Google. Pedirlo sin mostrarlo en el chat al abrir la sesión y después de cada turno, y llevar el grupo del modelo en uso a los anillos de cuota.

**Prueba:** tests/unit/test_quota_monitor.gd test_antigravity_usage con el /usage real; contra agy 1.4.3 headless: la cuota llega al abrir (14 %) y se actualiza tras el turno (semana 15 %, 5 h 1 %), y en el chat quedan solo el prompt y la respuesta.

**Notas:** QuotaMonitor.parse_antigravity_usage y antigravity_windows (Argon: semana propia y 5 h del grupo de Gemini). SessionController._query_agent_usage manda /usage oculto (agentInfo.name antigravity-acp) al conectar y al final de cada turno; un prompt del usuario espera a que termine. agy guarda /usage en su historial: un session/load podría reproducirlo.

### Instalar agentes desde el registro de ACP · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** media · **Tamaño:** M · **Etiquetas:** `idea`

Idea (2026-10-27), surgió de cómo Zed integra Antigravity. El registro de ACP (cdn.agentclientprotocol.com/registry/v1/latest/registry.json) lista ~43 agentes con su forma de instalarlos: npx, uvx o un binario por plataforma (zip con sha256, comando y args). Entre ellos Claude Agent, Codex, Gemini CLI, Copilot, Cursor, Google Antigravity, Goose, OpenCode, Junie, Kimi, Qwen Code, Mistral Vibe. En Settings → Perfiles: elegir un agente del registro y que el harness arme el perfil (npx/uvx) o baje, verifique y descomprima el binario en user://, como hace Zed. Reemplaza armar perfiles a mano y cubre agy sin código propio.

**Prueba:** Unit: test_acp_registry (parse con preferencia y plataforma, perfiles npx/uvx/binario, extract zip con zip slip, tar.gz, ejecutable suelto, chmod, filtro del diálogo); suite 291/0. Real: fetch del registro (43 agentes, linux-x86_64) e install de antigravity-acp 1.4.3 (sha256 ok, 930 MB, ejecutable). Editor: --godot-agent-settings-shots pasa y muestra el botón. No probado: el diálogo abierto en el editor (necesita red).

**Notas:** core/acp_registry.gd (Node): fetch() lee cdn.agentclientprotocol.com/registry/v1/latest/registry.json; parse(data, platform) elige npx > uvx > binario de la plataforma (platform_key: linux|darwin|windows-x86_64|aarch64) y descarta ids que no son nombres de archivo; profile_for() arma el perfil; install() baja el binario, verifica el sha256 si el registro lo trae y extract() lo descomprime en <editor data>/godot_agent/agents/<id>/<versión>/ (.zip con ZIPReader sin rutas que salgan; .tar.* con el tar del sistema; otro = el ejecutable suelto) y le da chmod +x. ui/settings/acp_registry_dialog.gd: lista con filtro, «Agregar», segundo clic «Agregar sin checksum» si falta el sha256 (42 de las ~100 descargas del registro no lo traen), aviso de que un binario puede tardar. Settings → Agentes: «+ Del registro de ACP…»; agregar uno con el mismo id reemplaza el perfil (conserva si era el predeterminado). El registro hoy: 43 agentes, 1.0.0. Los perfiles incluidos (Gemini sin --acp, Codex sin comando) no se tocaron: con el registro ya se pueden agregar bien.

**Bloquea a:** Soporte para Antigravity CLI (agy) como agente

### Soporte para Antigravity CLI (agy) como agente · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** media · **Tamaño:** M · **Etiquetas:** `idea`

Idea de la comparación con otros harness (2026-10-27). Google publica un adaptador ACP oficial para Antigravity en el registro de ACP (id antigravity-acp, v1.4.3, autor Google LLC, licencia propietaria): un zip por plataforma desde dl.google.com/agy-extensions/releases/<os>/agy-acp-server-<versión>-<os>-<arch>.zip, con sha256, que se ejecuta como ./agy_acp_server.par (en Linux con el argumento --uid=; en Windows agy_acp_server.exe). Así lo integra Zed: lee el registro, baja y verifica el zip, y lanza ese comando como agente ACP por stdio. Hay también adaptadores de la comunidad (agy-acp, antigravity-acp de GitHub) que leen el almacenamiento local de Antigravity; preferir el oficial. A probar: login, que pase los mcpServers de session/new (sin eso no ve godot.*) y godot.sessions/session_send entre agy y Claude Code en el mismo dock.

**Prueba:** Probe ACP a mano (initialize y session/new) contra el binario real. Pendiente del usuario: login con Google y mensajes entre agy y Claude Code.

**Notas:** Con m11-12, Google Antigravity se agrega desde Settings → Agentes → «+ Del registro de ACP…» (adaptador oficial de Google, antigravity-acp 1.4.3, ./agy_acp_server.par --uid= en Linux, ~930 MB). Probado a mano por stdio: initialize anuncia mcpCapabilities {http, sse} (recibe el MCP del harness por HTTP: godot.* incluidas sessions/session_send), loadSession, imágenes y _meta.antigravity.systemPrompt.append, y authMethods oauth-personal, oauth-business, gemini-api-key, agent-platform. session/new sin login devuelve -32000 «Authentication required», que SessionController.is_auth_required reconoce, así que el dock ofrece esos métodos (ACP authenticate). Falta, con la cuenta del usuario: completar el login, una conversación real con las tools godot.* y un godot.session_send entre agy y Claude Code en dos pestañas.

**Bloqueada por:** Instalar agentes desde el registro de ACP

**Relacionadas:** Mensajes entre sesiones: el recibido no se ve y una sesión nueva no los lee hasta su primer prompt

### Integración opcional con GitHub: PR desde una sesión y comentarios como hallazgos · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** baja · **Tamaño:** M · **Etiquetas:** `idea`

Idea de la comparación con otros harness (2026-10-27). Como Copilot o Codex. Crear un PR desde una sesión y traer los comentarios de un PR como hallazgos de Revisar. Opcional y apagado por defecto: hoy el harness nunca pushea por diseño.

**Decisiones:**
- ✓ Abrir un PR desde una copia va apagado por defecto y solo se ofrece al cerrarla
  Por qué: Es lo único del harness que pushea; la importación de comentarios solo lee y queda siempre disponible
  Descartado: Prendido por defecto; un botón aparte para pushear cualquier rama

**Prueba:** Unit: test_github_reviews (repo de remotes ssh/https/otro host; comentarios a hallazgos con prefijo de proyecto, sin respuestas ni fuera del proyecto ni vacíos, original_line, autor; proyecto en la raíz); suite 304/0. Real: con gh sin sesión, fetch_review devuelve el error de gh legible. No probado: con gh logueado, importar un PR real ni abrir uno (pushea).

**Notas:** core/github_reviews.gd con el CLI gh y --repo owner/repo sacado de git remote origin (así no depende del cwd del editor): fetch_review(pr) usa gh pr view (número o la rama actual) y gh api --paginate repos/<repo>/pulls/<n>/comments; comments_to_findings() pasa cada comentario con archivo del proyecto y línea (o original_line si quedó desactualizado) a un hallazgo res:// con el texto y «— @autor on GitHub», sin respuestas de hilo. Panel de Revisar: «De un PR de GitHub…» abre un diálogo con el número (vacío = rama actual) y carga los hallazgos en el ReviewStore (marcas en el Script Editor, «Arreglar en modo Construir»). Solo lee. PR desde una copia (m11-09): con github_pull_requests (apagado por defecto, Settings → Servidores MCP), el diálogo al cerrar una copia suma «Pushear y abrir un PR»: git push -u origin <rama> desde la copia y gh pr create contra la rama de partida (WorktreeSession guarda base_branch); la copia se saca y la rama queda.

### Tareas en segundo plano en un worktree con Godot headless · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** baja · **Tamaño:** L · **Etiquetas:** `idea`

Idea de la comparación con otros harness (2026-10-27). Como las cloud tasks de Codex o el coding agent de Copilot. Una sesión trabaja en otra copia del proyecto con su propio Godot headless y entrega un diff o una rama para integrar, sin competir con el editor abierto. Choca con «el harness nunca mergea»: decidir cómo se integra.

**Decisiones:**
- ✓ Aplicar los cambios de la copia con git apply como cambios sin commitear, no con merge
  Por qué: El harness no mergea por diseño; así el usuario revisa y commitea él, y si algo no entra limpio la rama queda para resolverlo a mano
  Descartado: git merge de la rama; cherry-pick del commit
- ✓ La copia va al lado del repo (<repo>.godot-agent-copies/), desde el último commit
  Por qué: Dentro del proyecto Godot la importaría como parte del juego; un worktree solo parte de un commit, así que lo sin commitear no está (se avisa)
  Descartado: Dentro del proyecto con .gdignore; copiar también los cambios sin commitear

**Prueba:** Unit: test_worktree_session (repo temporal con el proyecto en una subcarpeta: crea la copia al lado, el proyecto no cambia mientras el agente trabaja, commit_changes lista lo cambiado, apply_to_project deja los cambios sin commitear en la misma rama, remove borra copia y rama); suite 302/0. Editor: --godot-agent-sessions-test abre una copia de este repo, verifica cwd, que una tool de edición se rechaza y una de lectura anda, y que cerrarla sin cambios la borra (worktree y rama).

**Notas:** session/worktree_session.gd: create() hace git worktree add -b agent/copy-<fecha> en <repo>.godot-agent-copies/<fecha> (al lado del repo: adentro Godot lo importaría) desde HEAD, con el proyecto en su misma subcarpeta; commit_changes() commitea lo del agente en esa rama y lista los archivos cambiados; apply_to_project() arma el diff base..rama (git diff --binary, limitado al proyecto) y lo aplica con git apply en el repo principal como cambios sin commitear (el harness no mergea; si no entra limpio, queda la rama); remove() saca el worktree y, si se pide, la rama. SessionTabs: «+» abre un menú (sesión / sesión en una copia). Plugin: _make_controller con la copia como cwd y raíz de fs, sin sync con buffers, sin locks ni verificación por res://, con TurnSnapshots propios (los avisos de cambios del turno y volver atrás funcionan sobre la copia); aviso en el chat y note_for_agent explicando dónde trabaja y cómo validar con Godot headless. ToolRegistry.precheck (nuevo): rechaza antes de pedir permiso las tools no de lectura y las game_* para una copia (si no, Construir mostraba una tarjeta y recién después rechazaba). Cerrar la pestaña: si cambió algo, diálogo Aplicar al proyecto / Dejar la rama / Descartar / Cancelar; sin cambios, se borra sola. Al apagar el plugin las copias quedan como están. Una vez, en una corrida del check, quedó una copia sin borrar; no se repitió en tres corridas más.

**Relacionadas:** Checkpoints y «volver a antes de este mensaje» en cada turno

### Más contexto con @: errores, output, juego y docs · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** media · **Tamaño:** S · **Etiquetas:** `idea`

Idea de la comparación con otros harness (2026-10-27). @errors, @output, @game (árbol del juego en marcha), @docs Clase (referencia de la API) y arrastrar un nodo del Scene Tree al composer. Revisar primero qué menciones existen.

**Prueba:** Unit: test_mentions (detección sin repetir y con la clase, sin falsos positivos, opciones del menú; run_for_user sin permiso y con tool inexistente); suite 301/0. Editor: queue-test y auto-test pasan con el envío nuevo. No probado a mano: arrastrar nodos ni el texto de @game con un juego corriendo.

**Notas:** agent_dock: SPECIAL_MENTIONS (@errors, @output, @game, @docs:Clase) van primero en el menú de @ y, al enviar (también lo que sale de la cola), special_mentions_in() las encuentra (sin mails ni nodos parecidos) y _send_with_mentions() agrega un bloque de texto por cada una con lo que trae context_provider. plugin._context_for_mention usa ToolRegistry.run_for_user() (nuevo: corre la tool sin permiso ni guard, porque la pide el usuario; con el tope de max_output_chars): get_errors desde 0, game_tree y class_info; @output son los últimos 4000 caracteres del panel Output (ErrorCollector.output_text). composer: arrastrar nodos del dock Escena escribe @ruta relativa a la escena. Las menciones de nodos y archivos de antes siguen siendo solo texto.

### Instrucciones del proyecto: editar AGENTS.md/CLAUDE.md y generarlas · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** media · **Tamaño:** M · **Etiquetas:** `idea`

Idea de la comparación con otros harness (2026-10-27). Como las reglas de Cursor, las custom instructions de Copilot o /init de Claude Code. Panel para ver y editar AGENTS.md/CLAUDE.md del proyecto y un «generar convenciones» que analice autoloads, capas de colisión, estructura de carpetas y estilo de los scripts.

**Decisiones:**
- ✓ Los datos del proyecto los arma el harness, sin el agente
  Por qué: Son datos que se leen sin pensar (ProjectSettings y carpetas), no gastan tokens y se pueden regenerar; las convenciones de estilo se le pueden pedir al agente en el chat
  Descartado: Pedirle al agente que analice el proyecto y escriba el archivo (como /init)

**Prueba:** Unit: test_project_facts (sección con todos los datos y sin ui_* ni capas sin nombre; merge en archivo vacío, al final y reemplazando una vez); test_claude_extensions ahora cuenta 6 pestañas; suite 299/0. Editor: --godot-agent-extensions-shots pasa y la captura de la pestaña se ve bien.

**Notas:** ui/extensions/instructions_tab.gd: pestaña «Instructions» de Extensions con CLAUDE.md, AGENTS.md y GEMINI.md del proyecto (quién lee cada uno, «(nuevo)» si no existe), un TextEdit y Guardar; cambiar de archivo guarda el que se editaba. core/project_facts.gd: section() arma «## Project facts» entre <!-- godot-agent:project-facts --> … <!-- /… --> con versión de Godot, nombre, escena principal, autoloads, capas con nombre (física, render, navegación, avoidance), acciones de input sin ui_* y carpetas de primer nivel (sin ocultas ni .gdignore); merge() la reemplaza o la agrega al final sin tocar el resto. No hecho: que el agente analice el estilo del código y proponga convenciones (se puede pedir en el chat; la sección generada no gasta tokens).

### Artefactos de verificación: capturas y GIF del juego · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** media · **Tamaño:** M · **Etiquetas:** `idea`

Idea de la comparación con otros harness (2026-10-27). Como los walkthroughs de Antigravity. Al cerrar una tarea, un resumen con capturas del juego de antes y después o un GIF del playtest, para mirar o compartir. Ya existen capture_game_frame y game_input; falta juntarlos. Diferencial: ningún otro harness muestra el juego corriendo.

**Decisiones:**
- ✓ Reporte como carpeta con report.md y PNG, sin GIF
  Por qué: Godot no escribe GIF ni WebP animado sin código extra; las capturas que el agente ya toma son lo que verifica el trabajo, y un .md con imágenes se lee en GitHub o en cualquier visor
  Descartado: Escribir un GIF a mano (LZW); grabar video con Movie Maker

**Prueba:** Unit: test_turn_report (collect solo del turno, write con resumen, archivos y la captura byte a byte); test_turn_snapshots estable en 3 corridas; suite completa en verde.

**Notas:** session/turn_report.gd: collect(model, first_entry) junta el texto del agente y las imágenes (base64 + mimeType) de los tool calls del turno; write() escribe res://.godot_agent/reports/<fecha>/report.md (resumen, archivos con +/−, capturas) y capture-N.png/jpg/webp tal como llegaron. El aviso de fin de turno de Construir/Auto (SessionController._report_turn_changes) suma «N capturas del juego o del editor» y la acción «Guardar reporte» (ACTION_TURN_REPORT); el plugin escribe el reporte y abre la carpeta. Sin git aparece igual si hubo capturas. No hecho: GIF o video del playtest (Godot no escribe GIF ni WebP animado; queda la secuencia de capturas). De paso, turn_snapshots: el index propio se arma una vez con read-tree HEAD y se reusa (copiar el del usuario le cambiaba la fecha y git podía no ver un cambio del mismo tamaño en el mismo segundo; lo agarró el test).

### Chat en línea en el Script Editor (seleccionar y pedir) · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** media · **Tamaño:** L · **Etiquetas:** `idea`

Idea de la comparación con otros harness (2026-10-27). Como Ctrl+I de Copilot o Cmd+K de Cursor: seleccionar código, escribir el pedido y ver el cambio como diff en el mismo editor, para aceptar o rechazar. Puente entre el dock y el completado (M8). Después: sugerencias del próximo cambio relacionado (next edit suggestions de Copilot).

**Decisiones:**
- ✓ El pedido va a la sesión activa del dock (queda en el chat) en vez de una sesión aparte
  Por qué: Reusa la conexión, el modo y los permisos que ya hay y deja rastro de lo pedido; una sesión propia costaría otro agente corriendo
  Descartado: Una sesión oculta solo para el chat en línea; una llamada directa a un LLM como el completado
- ✓ Atajo Alt+I
  Por qué: Ctrl+I ya es Indentar en el Script Editor; Alt+\ es el pedido manual del completado
  Descartado: Ctrl+Shift+I; solo el menú contextual

**Prueba:** Unit: test_inline_edit (extract_code, build_prompt con y sin selección, apply sobre un CodeEdit con deshacer en un paso, rechazo si el código cambió, inserción en el caret, Alt+I); suite 296/0. Editor: cycle-test y edit-test pasan con el menú registrado (el crecimiento de objetos varía entre corridas: 1–33, también sin esta feature). No probado: el flujo completo con un agente real.

**Notas:** editor/inline_edit.gd (Node del plugin): Alt+I en el CodeEdit activo (Ctrl+I ya es Indentar) y editor/inline_edit_menu.gd (EditorContextMenuPlugin en CONTEXT_SLOT_SCRIPT_EDITOR_CODE) abren un LineEdit junto al caret. El pedido va con build_prompt (archivo, líneas, código seleccionado; pide solo el código nuevo en un bloque y no editar archivos) a la sesión de la pestaña activa por plugin._ask_inline (send_prompt + agent_text_since; error si no hay sesión o está ocupada). extract_code toma el primer bloque; la propuesta se ve con DiffDialog.diff_bbcode (sacado del DiffDialog) en un PopupPanel con Aceptar/Rechazar. apply() verifica que el rango siga igual y reemplaza en begin/end_complex_operation (un Ctrl+Z, sin guardar). Pedido y respuesta quedan en el chat. No hecho: sugerencias del próximo cambio (next edit suggestions); queda como idea.

### Verificación automática al terminar cada turno · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** S · **Etiquetas:** `idea`

Idea de la comparación con otros harness (2026-10-27). Como los hooks de Claude Code o los tests que corren Codex y Copilot. Al terminar un turno de Construir/Auto, correr godot.validate_scripts y get_errors; si hay errores nuevos, devolvérselos al agente (otro turno, con tope) o mostrarlos. Configurable por proyecto.

**Decisiones:**
- ✓ La verificación solo usa validate_scripts (errores de parseo), no get_errors
  Por qué: get_errors mezcla errores del juego que el agente pudo provocar a propósito al probar; los de parseo son inequívocos y baratos de corregir
  Descartado: Sumar los errores del editor desde la marca del inicio del turno
- ✓ Hasta 2 turnos de corrección seguidos y prendida por defecto
  Por qué: Corrige lo común sin quedar en loop; el usuario la puede apagar por proyecto
  Descartado: Solo avisar sin devolverle los errores al agente; apagada por defecto

**Prueba:** Unit: test_diagnostic_tools.test_scripts_modified_since (filtro por mtime, carpetas ocultas y .gdignore, failure_lines) y test_turn_check_sends_fix_or_notice (manda la corrección, con tope queda aviso, en Preguntar no verifica); suite 287/0; acp_session_check 159/0. No probado con Claude real en el editor.

**Notas:** SessionController._verify_turn(): después de un turno con end_turn en Construir o Auto (no en comandos con /), llama a turn_verifier(inicio del turno). El plugin lo conecta a DiagnosticTools.verify_changed_scripts(): recorre res:// en disco (no el EditorFileSystem, que puede no tener todavía lo que el agente creó por shell; saltea carpetas ocultas y con .gdignore), valida con el checker en otro proceso los .gd con mtime >= inicio del turno y devuelve las líneas «✗ ruta» + errores. Si hay errores y la sesión está READY, manda un prompt «[Automatic check after your turn]…» con aviso en el chat, hasta MAX_FIX_TURNS = 2 seguidos (se reinicia con cada prompt del usuario); si no (tope, la cola del dock ya mandó otro prompt), deja los errores como aviso. Ajuste del proyecto verify_after_turn (true), en Settings → Servidores MCP. Solo errores de parseo: get_errors queda afuera para no devolver errores del juego que el agente provocó a propósito.

**Relacionadas:** Checks del proyecto al terminar el turno, con reintento

### Avisar cuando una sesión en segundo plano necesita al usuario · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** S · **Etiquetas:** `idea`

Idea de la comparación con otros harness (2026-10-27). Como el Agent Manager de Antigravity. Con varias pestañas, un pedido de permiso en una que no está a la vista pasa desapercibido. Marcar la pestaña («⚠ nombre»), notificación del editor y, si hace falta, un resumen de las sesiones.

**Prueba:** Editor: --godot-agent-sessions-test con el caso nuevo (permiso en la segunda con la primera al frente → «⚠ », se va al cancelarlo); captura revisada. El toast no se verifica en el check.

**Notas:** SessionTabs: la pestaña muestra «⚠ nombre» mientras SessionModel.pending_permissions no está vacío (pesa más que «●» trabajando); se refresca al pedir y al resolver cada permiso. Si el dock de esa sesión no está a la vista (otra pestaña o el dock tapado), EditorToaster muestra ««nombre» espera tu permiso.». No hice un panel de resumen de sesiones: godot.sessions y las pestañas alcanzan por ahora.

**Relacionadas:** Avisar fuera del editor cuando el agente termina o espera (sonido o notificación), y «Steer» para la cola (como Zed)

### Revisar los cambios del turno: diff y descartar por archivo · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** M · **Etiquetas:** `idea`

Idea de la comparación con otros harness (2026-10-27). Como Keep/Undo por archivo de Copilot o el diff como artefacto de Antigravity. Al pie de cada turno: «N archivos cambiados · ver diff · descartar». Reusar la lista de cambios y el DiffDialog del One-shot. Se apoya en los checkpoints por turno.

**Prueba:** Ver m11-01. La UI del diálogo no tiene check propio en el editor.

**Notas:** ui/turn_changes_dialog.gd: lista de archivos del turno (estado +/~/−, ruta, +a −r) con «Diff» (DiffDialog: antes del turno vs. ahora) y «Volver atrás» por archivo (TurnSnapshots.restore con esa ruta; queda «Vuelto atrás»). Se abre desde el aviso de fin de turno (ver m11-01).

**Bloqueada por:** Checkpoints y «volver a antes de este mensaje» en cada turno

### Checkpoints y «volver a antes de este mensaje» en cada turno · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** M · **Etiquetas:** `idea`

Idea de la comparación con otros harness (2026-10-27). Como /rewind de Claude Code o volver a un mensaje en Cursor/Copilot. Hoy hay checkpoints de git solo en One-shot y deshacer por tool godot.*. Snapshot del proyecto al empezar cada turno de Construir/Auto (refs de git, sin ramas ni commits en la rama del usuario) y acción «volver a antes de este mensaje» en el chat. Reusar oneshot/git_checkpoints.gd.

**Decisiones:**
- ✓ Snapshots como commits sueltos con un index propio, no git stash ni ramas
  Por qué: stash create no incluye archivos sin trackear y stash push toca el árbol con el editor abierto; ramas o commits ensuciarían el historial del usuario. Las refs propias no se ven en git log ni en las ramas
  Descartado: git stash create; una rama por sesión; copiar los archivos a user://
- ✓ Prendido por defecto y solo en Construir y Auto
  Por qué: Es invisible (refs fuera de las ramas) y es lo que más ayuda al deshacer; en Preguntar y Revisar el agente no edita y One-shot tiene sus checkpoints
  Descartado: Apagado por defecto; también en One-shot

**Prueba:** Unit: test_turn_snapshots (parse_diff; repo temporal: qué captura, diff A/M/D sin ignorados, volver un archivo, volver todo, deshacer la vuelta, HEAD e index del usuario intactos, refs; aviso de fin de turno con acciones y sin aviso si no hubo cambios); suite completa en verde. Editor: auto-test, edit-test y cycle-test pasan; el turno de auto-test dejó sus dos snapshots con el cambio real (project_config.tres). No probado a mano: los botones del aviso y el diálogo en el editor.

**Notas:** session/turn_snapshots.gd: snapshot = commit suelto de la carpeta del proyecto armado con un index propio (copia del real, por GIT_INDEX_FILE vía env o cmd /c set en un Thread; OS.execute no recibe entorno): add -A, write-tree, commit-tree -p HEAD, update-ref refs/godot-agent/turns/<sesión>/<ms>, se guardan 60 por sesión. Respeta .gitignore; diff y restore excluyen .godot/ y .godot_agent/. restore(sesión, sha, paths) toma un snapshot de ahora, restaura con git restore --source --worktree (no toca el index) y borra lo que se creó después; devuelve {changed, before} para deshacerlo. SessionController: snapshot al empezar cada turno de Construir/Auto (no comandos /), y al terminar _report_turn_changes() deja un aviso «Este turno cambió N archivos (+a −r): …» con «Ver cambios» y «Volver a antes de este turno» (data {session, start, end, files}). Plugin: TurnSnapshots compartido (setup() mira git), confirmación antes de volver todo, recarga lo abierto, aviso «Vuelto atrás» con «Deshacer» y note_for_agent() para el próximo prompt. Ajuste turn_snapshots (true) en Settings → Servidores MCP. No se reporta en turnos que terminan con error.

**Bloquea a:** Revisar los cambios del turno: diff y descartar por archivo

**Relacionadas:** Tareas en segundo plano en un worktree con Godot headless

### Plan aprobable antes de construir (fuera del One-shot) · Revisión

**Prioridad:** media · **Tamaño:** M · **Etiquetas:** `idea`

Idea de la revisión de otros harness (2026-11-10), de Kiro y Junie.
- Kiro: un spec arma requirements.md (o bugfix.md), design.md y tasks.md en tres fases, con criterios en EARS («WHEN … THE SYSTEM SHALL …»). Las tareas se corren de a una o todas, con estado en vivo. https://kiro.dev/docs/specs/ y https://kiro.dev/docs/specs/feature-specs/
- Kiro permite comentar pasajes del documento con Markdown Review y mandarle los comentarios juntos al agente. https://kiro.dev/docs/specs/
- Kiro: que haya aprobación entre fases sale solo de que Quick Spec dice ir «without approval gates». No está confirmado en la doc.
- Junie: el Plan mode analiza en solo lectura y produce un design document (pestañas Requirements, Technical design, Testing, Delivery steps). Pausa con «Confirm and implement» / «Save the plan and stop»; el plan es «a living design document» que se revisa las veces que haga falta. https://junie.jetbrains.com/docs/junie-cli-plan-mode.html
- Junie IDE: «Plan: Junie prepares a plan and waits for your approval before implementing it». https://www.jetbrains.com/help/ai-assistant/junie-agent.html

Qué existe: el One-shot ya tiene spec.md con «Revisar el spec antes de construir» (m6-10). Preguntar usa el modo plan del agente, pero no deja un documento ni lo aprueba. En Construir no hay nada parecido.

Adaptación a Godot y al harness:
- Una acción «Planificar» en el dock (o /plan). La sesión pasa a Preguntar y el agente escribe `.godot_agent/plans/<fecha>-<slug>.md`:
  - qué tiene que pasar en el juego, con criterios jugables («CUANDO el jugador toca un enemigo, EL JUEGO DEBE restarle una vida»);
  - diseño en términos de Godot: escenas y nodos nuevos, scripts, señales, autoloads, input map y capas de colisión;
  - tareas.
- El dock lo muestra con Editar, comentarios por pasaje (como en el visor de spec del One-shot) y «Aprobar y construir»: pasa a Construir y manda «implementá el plan», con las tareas como plan del agente (plan_view) tildándose.
- El archivo queda en el proyecto, para retomarlo en otra sesión.

Por qué: es el pedido de diseño-antes-de-código que dos harness distintos convirtieron en modo propio. En un juego, aprobar primero qué escenas y señales se tocan evita cambios grandes que después hay que deshacer con los checkpoints por turno (m11-01).

- [x] Capturar el pedido real de ExitPlanMode (0.105) y guardarlo como fixture
  Hecho 2026-11-11 con un cliente ACP en Python (scratchpad). Resultados: el plan viene en rawInput.plan (también planFilePath en ~/.claude/plans); toolCall.name "ExitPlanMode", kind switch_mode, title "Approve Plan" (no «Ready to code?»). Opciones reales: exit-plan-default (allow_once), exit-plan-clear-auto, exit-plan-auto, exit-plan-bypass (allow_always), reject (reject_once); no vino acceptEdits. Reject: tool_call_update failed con nonExecutionKind user-rejected y el turno termina con stopReason cancelled. Allow: current_mode_update default, ExitPlanMode completed («User has approved your plan») y el agente sigue en el mismo turno (pidió Write enseguida); no llega plan_update. En modo plan el agente edita su archivo de plan sin pedir permiso.
- [x] Broker + approve_plan + feedback tras rechazo (unit tests contra el fixture)
  f2a5940: plan_approval.gd, plan_store.gd, permission_broker _ask_plan/_emit_feedback, session_controller.approve_plan (_skip_mode_sync) y reject_feedback; tests/unit/test_plan_approval.gd (10 tests).
- [x] PlanApprovalView, «Denegar con motivo», cola después del rechazo, plan-test en/es, wiki y CHANGELOG

**Decisiones:**
- ✓ ¿Dónde se guardan los planes: en .godot_agent/plans/ del proyecto (versionables), en user:// del editor, o no se guardan?
  Descartado: user:// del editor; no guardarlos
  Respuesta: Los planes aprobados se guardan en .godot_agent/plans/ (respuesta del usuario, vía agent-harness-81).
- ✓ Si el agente presenta un plan (ExitPlanMode) estando en Revisar, ¿aprobar pasa a Construir, o en Revisar se rechaza siempre y se sigue revisando?
  Descartado: rechazarlo siempre en Revisar
  Respuesta: En Revisar, aprobar el plan pasa a Construir (respuesta del usuario, vía agent-harness-81).
- ✓ «Denegar con motivo»: ¿el motivo se ve en el chat como línea plegada del harness (etiqueta DENY_REASON) o como mensaje normal del usuario?
  Descartado: mensaje normal del usuario
  Respuesta: El motivo va como línea plegada del harness (etiqueta DENY_REASON) (respuesta del usuario, vía agent-harness-81).
- ✓ ¿Las tarjetas de plan usan el timeout de permisos, o esperan indefinidamente?
  Descartado: usar el mismo timeout que los demás permisos
  Respuesta: Las tarjetas de plan no vencen: esperan indefinidamente (respuesta del usuario, vía agent-harness-81).
- ! La fuente B (botón «Planificar» y /plan para agentes sin modo plan) va en una tarea aparte; m11-22 hace solo la fuente A (ExitPlanMode) y «Denegar con motivo». · sin revisar
  Por qué: La fuente A cubre a Claude Code, que es el agente principal, y depende de un payload que se puede capturar y probar. La fuente B depende de que otros agentes respeten el bloque ```plan y no se puede verificar con agentes reales instalados; mezclarlas agranda la tarea y su riesgo.
  Descartado: hacer las dos fuentes en m11-22
- ! Aprobar un plan pasa solo a Construir: la tarjeta no ofrece acceptEdits, auto, bypass ni las opciones «clear context» del adapter. · sin revisar
  Por qué: Las ediciones las sigue rigiendo la matriz de permisos de Construir; ofrecer Auto o bypass desde la tarjeta saltearía esa matriz con un clic, y «clear context» arranca otra query dentro del mismo turno.
  Descartado: ofrecer también «Aprobar en Auto»
- ! PlanApprovalView va sola; el componente compartido con el visor de spec del One-shot (DocumentApproval) se hace después, en otra tarea. · sin revisar
  Por qué: Extraerlo toca agent_main_screen.gd (1449 líneas), la pantalla más probada; el riesgo de romper el One-shot es alto para el beneficio dentro de esta tarea.
  Descartado: extraer DocumentApproval ahora y usarlo en las dos vistas
- ! Al aprobar, el harness pasa a Construir sin mandar session/set_mode y recién después contesta allow (exit-plan-default); el modo del agente lo cambia el propio adapter (current_mode_update → default). · sin revisar
  Por qué: Captura real de claude-agent-acp 0.105 (tests/fixtures/acp/exit_plan_mode_0105.json): con allow el adapter manda current_mode_update default y sigue en el mismo turno pidiendo editar (Write player.gd enseguida), así que la matriz ya tiene que ser la de Construir al contestar. Mandar set_mode mientras ExitPlanMode está pendiente es un caso que no se probó y no hace falta.
  Descartado: set_harness_mode con sync (set_mode default) y esperar agent_mode_synced antes de contestar, como decía el plan; contestar primero y cambiar el modo después (la primera edición caería en la matriz de Preguntar)
- ! «Denegar con motivo» (y Editar/Seguir planeando en el plan) corta el turno apenas el agente recibió el rechazo, y el motivo sale cuando el agente confirma el corte (como «Enviar ahora»). Un Detener del usuario antes del corte lo deja en la cola en pausa. · sin revisar
  Por qué: Corrida real con Claude Code (2026-11-11): después de rechazar una edición, Claude siguió en el mismo turno en lugar de terminarlo, así que el motivo, que esperaba el fin del turno, no llegaba. Con el agente falso el turno siempre terminaba y no se veía. El rechazo del plan ya termina cancelled, así que ahí no cambia nada.
  Descartado: esperar el fin del turno (el motivo puede no llegar nunca si el agente pide otra tarjeta); mandarlo como mensaje en medio del turno (ACP no lo permite)

**Prueba:** Unit: tests/unit/test_plan_approval.gd (12 tests; fixture real tests/fixtures/acp/exit_plan_mode_0105.json). Xvfb: --godot-agent-plan-test (agente falso, tests/scripts/plan_mode.json), en y es. Real (gasta tokens): --godot-agent-claude-plan-test. Regresiones: review, oneshot, queue, ui_long_permission, ui_harness_prompt, auto, remote, i18n. suite.sh ci: 12/13 (edit falla por scope_compass en project.godot; su arreglo está en sm/suite).

**Notas:** Absorbe m11-48 (1): editar el plan y mandar el diff como feedback antes de «Build» (Roblox Planning Mode, Bezi, Unity Plan). La parte (2) de m11-48, «Denegar con motivo» en cualquier tarjeta de permiso, se hace acá también (pedido de agent-harness-50, 2026-11-10). Relacionada: m11-27/m11-38 (modelo para planear).

PROPUESTA DE DISEÑO (agent-harness-57, 2026-11-10), sin implementar, a aprobar:

Qué hay hoy:
- Preguntar ya corre al agente en su modo "plan" (AGENT_MODE_FOR, session_controller.gd:119). Revisar también.
- claude-agent-acp 0.105 manda el plan como request_permission de ExitPlanMode:
  - Título «Ready to code?», el plan en rawInput.plan (o planFilePath) y en content.
  - Opciones: default, acceptEdits, auto, «clear context…» (allow_always) y reject, que contesta deny «User chose to keep planning» con interrupt, y el turno termina como cancelled.
  - Al aprobar manda plan_update {type: markdown, planId: "plan-mode"}.
- Hoy eso cae en GROUP_OTHER y es una tarjeta genérica: el plan aparece como output colapsado de la tool y no hay nada para editarlo.
- El One-shot tiene su propio spec.md con aprobación: _spec_view, _spec_bar Editar/Aprobar y _files_dialog, armados inline en agent_main_screen.gd. No hay comentarios por pasaje ni diff de lo editado. plan_view.gd es la lista TodoWrite, de solo lectura.

Diseño, un solo sistema de planes, dos fuentes:
1. Fuente A, el agente con modo plan (Claude Code): la tarjeta de ExitPlanMode es el plan a aprobar. No se inventa otro paso. PermissionBroker la reconoce por la herramienta ExitPlanMode o por kind switch_mode con plan, y la dibuja una vista nueva, PlanApprovalView, en lugar de la tarjeta genérica:
   - plan en markdown (MarkdownBBCode);
   - «Aprobar y construir»: allow con la opción default, y el modo del harness pasa a Construir. Las ediciones las sigue rigiendo la matriz de Construir: no se ofrece acceptEdits, auto ni bypass;
   - «Editar»: TextEdit con el plan. Al confirmar, reject, y al terminar el turno (cancelled) se manda como prompt del harness (etiqueta PLAN_EDIT, m12-44) «the user edited your plan:» con el diff de líneas (core/line_diff.gd) y el plan completo, para que lo rehaga y vuelva a llamar ExitPlanMode;
   - «Seguir planeando con motivo…»: el «denegar con motivo» de abajo.
2. Fuente B, agentes sin ExitPlanMode (Codex, Gemini por ACP) o Construir sin modo plan: la acción «Planificar» del dock (botón junto al selector de modo y /plan en el composer):
   - pasa a Preguntar y manda un prompt del harness (PLAN_REQUEST) que pide el plan con la estructura de abajo. Si el agente tiene ExitPlanMode, que lo presente con él (fuente A); si no, que termine el turno con el plan en un bloque ```plan;
   - con el bloque, la misma PlanApprovalView aparece debajo del mensaje. Aprobar manda send_in_mode(BUILD, PLAN_APPROVED) con la ruta del archivo.
3. Estructura que pide PLAN_REQUEST: criterios jugables («CUANDO el jugador toca un enemigo, EL JUEGO DEBE restarle una vida»); diseño en términos de Godot (escenas y nodos nuevos, scripts, señales, autoloads, input map, capas de colisión); tareas numeradas. Al construir se le pide llevar las tareas como su plan (TodoWrite), así plan_view las tilda como hoy.
4. Archivo: cada plan presentado se guarda en .godot_agent/plans/<fecha>-<slug>.md (slug del primer título). Lo editado se reescribe ahí y lo aprobado queda con «Approved: <fecha>». Se retoma en otra sesión con @ en el composer (ya completa archivos); no hago lista de planes.
5. Componente compartido con el One-shot, para no tener un tercer sistema: saco de agent_main_screen.gd un DocumentApproval (ui/document_approval.gd) con la vista markdown, Editar, Aprobar y el diff de lo editado. Lo usan el spec del One-shot (approve_spec y edit_plan siguen igual, solo cambia la UI) y PlanApprovalView. La lógica del One-shot (etapas, spec.md, ONESHOT_SPEC_*) no se toca.
6. Revisar: no cambia. Sigue siendo hallazgos → «Arreglar» en Construir. No le agrego plan: ahí el «plan» es la lista de hallazgos, que ya se aprueba eligiendo cuáles arreglar. Lo único compartido es que Revisar también corre en modo plan del agente. Si el agente llama ExitPlanMode estando en Revisar (hoy pasa, m16-03), se ve la misma PlanApprovalView y aprobar pasa a Construir.
7. Sincronización de modo: si el agente sale del modo plan por su cuenta (current_mode_update a default o acceptEdits), hoy el harness no cambia (agent_modes_changed no tiene a nadie conectado). Con un plan aprobado, el harness pasa a Construir. Fuera de eso no lo cambio, para no abrir otro comportamiento.

«Denegar con motivo» (m11-48 (2)), en toda tarjeta de permiso:
- Botón «Denegar con motivo…» al lado de Denegar: abre un LineEdit en la misma tarjeta; Enter o el botón confirman.
- Contesta reject_once como hoy, porque ACP no tiene campo de motivo; el adapter manda su mensaje fijo.
- El motivo va a la cola como prompt del harness (DENY_REASON, «Denied with a reason») «I denied <tool>: <motivo>» y sale al terminar el turno. Cambio necesario en la cola: hoy se pausa con stop reasons distintos de end_turn, y ExitPlanMode con interrupt termina en cancelled. Ese prompt sale igual.
- En Auto, la tarjeta de shell ya tiene _rule_edit: el motivo va aparte.

Fuera de esta tarea: comentarios por pasaje (Kiro Markdown Review), porque hoy no existe en ningún lado y alcanza con Editar + diff; una lista de planes guardados; el modelo para planear (m11-27/m11-38).

Tests previstos:
- Unit: detección de la tarjeta ExitPlanMode con el payload de 0.105 como fixture; el diff de la edición; el guardado del archivo; DENY_REASON en la cola con cancelled; el bloque ```plan de la fuente B.
- UI test con el agente falso: plan → Editar → feedback → plan nuevo → Aprobar → Construir. Captura en dock angosto.
- Que el spec del One-shot sigue andando con el componente (oneshot_check.gd y la UI del One-shot).

PLAN DE IMPLEMENTACIÓN (agent-harness fix-b, 2026-11-10), revisado contra sm/next2 709be97 y claude-agent-acp 0.105.0 instalado. Solo plan: sin rama hasta después del release.

Verificado del diseño de arriba:
- 0.105 (permissions/options/tools.js buildExitPlanModePermissionOptions, effects.js, presentation.js):
  - título «Ready to code?»;
  - opciones exitPlanDefault (allow_once); acceptEdits, auto y bypass (allow_always); tres «clear context» (allow_always, arrancan otra query); y reject «No, keep planning»;
  - reject contesta deny «User chose to keep planning» con interrupt:true; exit-plan.js reconoce el ciclo interrumpido.
- Sin verificar:
  - el campo exacto del plan (rawInput.plan vs planFilePath: este último solo con la capability AIR planFile, que no anunciamos);
  - el stopReason real después del reject (el adapter puede seguir el mismo turno en una query nueva en vez de terminarlo cancelled).
  - Primer paso: capturar un request real con el probe ACP y el proxy que loguea (ver memoria «MCP client testing») y guardarlo como fixture.
- Hoy en el harness:
  - kind switch_mode → GROUP_OTHER (permission_policy.gd:143). Sin DEFAULTS cae en ASK en todos los modos: tarjeta genérica.
  - No hay fixture de ExitPlanMode en tests/.
  - El fake agent ya manda request_permission (tests/scripts/permissions.json) y termina turnos con cualquier stopReason.
  - La cola se pausa con todo lo que no sea end_turn (agent_dock.gd:1242 _on_turn_finished).
  - One-shot ya tiene ONESHOT_PLAN_EDIT y edit_plan (oneshot_run.gd:753) para la lista de tareas, no para un documento.
  - LineDiff ya existe (core/line_diff.gd; lo usan diff_dialog y permission_broker).

Forma de la UI:
- PlanApprovalView (entrada del chat, reemplaza la tarjeta de permiso cuando es ExitPlanMode):
  - encabezado «Plan listo para construir»;
  - el plan en markdown, con alto acotado y «Mostrar todo» como el permiso largo de m-ui_long_permission;
  - botones: Aprobar y construir (primario) · Editar · Seguir planeando… ;
  - Editar cambia la vista por un CodeEdit con el texto, con Mandar cambios / Cancelar. Arriba, contador +N −M en vivo con LineDiff;
  - Seguir planeando… abre un LineEdit en la tarjeta (el mismo control que «Denegar con motivo»);
  - una vez contestada queda plegada con el resultado («Aprobado · construyendo», «Editado: +3 −1», «Seguir planeando: <motivo>»), como _result_text hoy.
- Tarjeta de permiso común: «Denegar con motivo…» como botón secundario después de Denegar. En dock angosto los botones ya bajan de línea (HFlow). Enter confirma y Esc vuelve.
- Fuente B: botón «Planificar» en la fila del selector de modo (solo con sesión READY y modo ≠ One-shot) y /plan <pedido> en el composer. Sin texto, toma lo que haya en el composer.

Tools: ninguna tool MCP nueva. Todo pasa por ACP (request_permission y prompts del harness). Si el agente no tiene ExitPlanMode, el protocolo es el bloque ```plan. Una tool godot.present_plan sería la alternativa (ver Preguntas).

Archivos:
- Nuevos:
  - session/plan_store.gd: guarda y lee .godot_agent/plans/<fecha>-<slug>.md, marca Approved;
  - ui/dock/entries/plan_approval_view.gd;
  - (si se hace el punto 5) ui/document_approval.gd.
- session/permission_broker.gd:
  - es_plan(params) por toolCall.title/rawInput/kind switch_mode;
  - filtra las opciones a default + reject (sin acceptEdits/auto/bypass/clear context);
  - deja el texto del plan en el PermissionRequest.
- session/permission_request.gd: campos plan_text y deny_reason.
- ui/dock/conversation (donde se elige la vista por tipo de entrada) y entries/permission_view.gd: «Denegar con motivo».
- session/session_controller.gd:
  - approve_plan(): pasa el harness a BUILD con set_harness_mode, espera agent_mode_synced (ya existe el loop _mode_syncs_running) y recién ahí contesta allow default;
  - feedback de Editar/motivo.
- session/prompt_queue.gd + ui/dock/agent_dock.gd: un item con after_interrupt:true (los prompts DENY_REASON/PLAN_EDIT) sale aunque el turno haya terminado cancelled, solo si ese cancel lo causó el reject propio.
- session/harness_prompts.gd: PLAN_REQUEST, PLAN_EDIT, PLAN_APPROVED, DENY_REASON + es.po.
- Fuente B: ui/dock/agent_dock.gd (botón, /plan), session_controller (parseo del bloque ```plan al terminar el turno).
- Tests y dev:
  - tests/fixtures/acp/exit_plan_mode_0105.json (capturado);
  - tests/scripts/plan_mode.json (fake agent: plan → reject → plan nuevo → allow);
  - tests/unit/test_plan_approval.gd y test_deny_reason.gd;
  - addons/godot_agent_dev/plan_check.gd + PLAN_ARG «--godot-agent-plan-test» en plugin.gd.
- docs/wiki en/es (modos y permisos), CHANGELOG.

Riesgos:
1. Carrera de modo al aprobar: allow default en ExitPlanMode cambia el modo del agente a default. Si el harness sigue en ASK, _sync_agent_mode lo vuelve a plan y la matriz de ASK deniega las ediciones. Orden obligatorio: harness a BUILD, esperar sync, contestar. Test: aprobar y que la primera edición pida permiso de Construir, no DENY.
2. Las opciones «clear context» arrancan una query nueva dentro del mismo turno: se esconden. Si una versión futura cambia los optionId, filtrar por kind/nombre y loguear lo que no se reconoce.
3. El reject puede no terminar el turno. Si el adapter sigue en otra query, el feedback no espera al fin del turno: se manda como mensaje cuando llegue end_turn o cancelled, lo que pase primero (lo decide la captura).
4. Permiso con timeout (_ask_user timeout_s): editar un plan largo puede vencerlo. Sin timeout para los de plan.
5. Revisar en modo plan llama ExitPlanMode (m16-03): aprobar pasa de Revisar a Construir. Es un cambio de comportamiento visible; va a Preguntas.
6. Extraer DocumentApproval del One-shot toca agent_main_screen.gd (1449 líneas) en la pantalla más probada; el riesgo de romper es alto para el beneficio. Recomiendo NO hacerlo en esta tarea (ver Preguntas).
7. Prompts que salen tras un cancel: no debe salir uno si el cancel fue del usuario (botón Stop). Solo cuando el cancel lo causó el reject propio del harness.
8. Otros agentes (Codex/Gemini ACP) pueden tener otro mecanismo de plan (modos sin ExitPlanMode). La fuente B depende de que respeten el bloque ```plan; sin verificar con agentes reales (solo están Claude Code y antigravity-acp instalados).

Cómo se prueba:
- Unit: detección y filtro de opciones con el fixture real; approve_plan con un FakeController que registra el orden (modo BUILD → sync → allow); LineDiff del editado en el prompt PLAN_EDIT; plan_store (slug, Approved, reescritura); cola: after_interrupt sale con cancelled propio y no con cancel del usuario; parseo del bloque ```plan.
- Xvfb con el agente falso (plan-test, en y es): plan → Editar → feedback con diff → plan nuevo → Aprobar → modo Construir → la primera edición pide permiso. «Denegar con motivo» en una tarjeta de shell → el motivo sale en el turno siguiente con etiqueta. Captura en dock angosto.
- Regresión: review-test, oneshot-test, queue-test, i18n-test (textos nuevos), ui_long_permission.
- Manual con Claude Code real (gasta tokens, como claude-*-test): Preguntar → pedir un cambio → ExitPlanMode → Editar → Aprobar. Confirmar que construye en Construir con permisos.

Preguntas para el usuario:
1. Fuente B («Planificar» y /plan para agentes sin modo plan): ¿entra ahora o queda como tarea aparte después de la fuente A? Recomiendo aparte.
2. ¿Se guardan los planes en .godot_agent/plans/ (en el proyecto, versionables) o no se guardan? ¿O en user:// del editor?
3. Al aprobar: ¿solo «Aprobar y construir» (Construir), o también «Aprobar en Auto»? Recomiendo solo Construir.
4. Revisar + ExitPlanMode: ¿aprobar pasa a Construir, o en Revisar se rechaza siempre y se sigue revisando?
5. ¿Se extrae el visor de spec del One-shot a un componente común ahora (punto 5), o PlanApprovalView va sola y se unifica después? Recomiendo después.
6. «Denegar con motivo»: el motivo ¿se ve en el chat como mensaje plegado del harness (etiqueta DENY_REASON) o como mensaje del usuario normal?
7. ¿Hace falta el timeout de permisos en los planes, o se espera indefinidamente?

**Bloquea a:** Criterios de aceptación del plan verificados jugando; «Planificar» y /plan para agentes sin modo plan

**Relacionadas:** Plan editable antes de construir y «Denegar con motivo»; Modelo por modo: planificar con uno y construir con otro

### Criterios de aceptación del plan verificados jugando · Revisión

**Prioridad:** baja · **Tamaño:** M · **Etiquetas:** `idea`

Idea de la revisión de otros harness (2026-11-10), de Kiro.
- Correctness (solo IDE) convierte los requisitos EARS en propiedades, las vincula a su requisito y su tarea, y genera cientos de entradas al azar para romperlas, con shrinking. Si falla, muestra el escenario y se decide en el chat si se arregla el código, el test o el requisito. https://kiro.dev/docs/specs/correctness/
- La misma página aclara que es evidencia y no prueba formal, y que lo no determinista necesita otros tests.

Adaptación a Godot y al harness:
- Sin un framework de property-based testing para GDScript, lo que se traslada es el vínculo requisito → verificación.
- Cada criterio jugable del plan (ver la idea del plan aprobable) se convierte en un pedido de playtest con veredicto (m14-03 / m15). El resultado vuelve al plan como ✓ / ✗ / blocked con su evidencia (captura, números del juego).
- Los que pasan se pueden guardar como regresión (el CI workflow de v0.1.19 ya las corre).
- Las variaciones al azar (posiciones, inputs con semilla) quedan para después, con input por frame (m14-01).

Por qué: hoy los playtests responden a lo que el agente decide probar. Atarlos a criterios aprobados por el usuario cierra el loop pedido → plan → juego verificado, y el One-shot ya tiene un evaluador que lo aprovecharía. Depende del plan aprobable y de los playtests con veredicto.

**Decisiones:**
- ! Un playtest por criterio (no uno solo con veredictos por criterio); la verificación viene prendida por defecto; tope de 6 por corrida, configurable en el mismo setting; la tarjeta aclara que cada criterio es un playtest · sin revisar
  Por qué: Uno por criterio deja veredicto, evidencia y regresión atados a cada criterio. Prendido por defecto: según agent-harness-81, lo decidió el usuario (no me lo confirmó a mí directamente). La línea del costo y el tope configurable los pidió 81.
  Descartado: Un playtest para todos con un veredicto por criterio en el JSON; apagado por defecto; tope fijo

**Prueba:** tests/run_all.gd -- plan_criteria (6 tests: criteria(), casilla/setting, corrida con pass/fail/blocked y re-prueba solo del que falló, tope y «Verificar el resto», reintentos y mensaje del usuario, sección ## Verification, tarjeta). Editor check ui-plan-criteria (suite full) con el agente falso: 2 criterios, el 2 falla, se corrige, se re-juega solo ese y pasa → «2 ✓ · 0 ✗». suite.sh ci en verde (4.7.2).

**Notas:** Hecho en sm/m11-23 (d37eaf4, desde 9a600eb), sin pushear.
- PlanApproval.criteria/plan_title; la corrida de receta ganó `criteria` (origen "plan" o receta con «Planificar primero»: sus playtests van como criterios primero).
- Un playtest por criterio en Revisar; fail → un turno de corrección con todos los que fallaron (PLAN_CRITERIA_FIX), después se re-juegan solo esos; blocked → ⊘; tope de reintentos 2.
- Tarjeta: casilla «Verify the criteria by playing (N)» + línea del costo (cada criterio es un playtest, tope N, se cambia en Settings); estado por criterio con evidencia en el tooltip. PermissionRequest.verify_criteria (-1/0/1), criteria_max, criteria_results, señal changed.
- Settings → MCP servers → Advanced: verify_plan_criteria (true) y verify_plan_criteria_max (6).
- «Verificar el resto» juega los que pasaron el tope sin turno de corrección.
- Fuera: One-shot (tiene su QA), variaciones al azar, ⊘ «no hay escena» (lo decide el playtest con blocked).

**Bloqueada por:** Plan aprobable antes de construir (fuera del One-shot)

### Hooks del proyecto en eventos del editor · Revisión

**Prioridad:** media · **Tamaño:** M · **Etiquetas:** `idea`

Idea de la revisión de otros harness (2026-11-10), de Kiro.
- Agent hooks: archivos JSON en `.kiro/hooks/<id>.json` con trigger, matcher (regex de la ruta), acción `command` (shell, recibe el contexto por STDIN) o `agent` (inyecta un prompt en la conversación), timeout y enabled. https://kiro.dev/docs/hooks/
- Triggers: Prompt Submit, Agent Stop, Session Start/End, Pre/Post Compaction, Pre/Post Tool Use, File Create/Save/Delete y Pre/Post Task Execution de un spec. https://kiro.dev/docs/hooks/types/
- File Save dispara con lo que guarda el agente («when the agent saves or modifies files»), no el usuario.

Qué existe: la verificación al terminar el turno (m11-04) es un hook fijo. Claude Code tiene sus hooks propios, pero no ven eventos del editor de Godot.

Adaptación a Godot y al harness:
- `.godot_agent/hooks.json` (versionable), con una pestaña en Extensions.
- Disparadores que solo ve el editor:
  - el usuario guarda un script o una escena (resource_saved y scene_saved, que el plugin ya escucha);
  - un run_scene o un juego lanzado a mano termina con errores;
  - un import falla;
  - terminó un playtest;
  - antes de exportar.
- Acciones:
  - prompt a una sesión (por ejemplo «revisá este cambio» en Revisar, o «arreglá estos errores» en Construir, con tope de turnos como m11-04);
  - una tool godot.* (validate_scripts, las regresiones);
  - un comando, pasando por las reglas de shell y los permisos del modo.
- Con matcher por ruta (`res://enemies/**/*.gd`).

Por qué: lo que ningún agente externo puede ver son los eventos del editor y del juego. «Al guardar una escena de nivel, correr la regresión de ese nivel» o «si el juego crashea, mandarle el backtrace a la sesión» son flujos de Godot que hoy el usuario hace a mano.

**Decisiones:**
- ! Hooks en project_config.tres (`hooks`). La acción prompt por defecto es un aviso con «Send to the agent» (como m11-55); `auto_send: true` la manda sola con tope de 2 seguidos, el editor lo explica al prenderlo, y como cambia el JSON pide aprobar de nuevo. saved con by=user por defecto. · sin revisar
  Por qué: Respuestas de agent-harness-81 al plan: ProtectedPaths no deja al agente escribir project_config; el harness nunca le manda algo al agente por su cuenta, y un guardado no debe gastar tokens sin que el usuario lo pida.
  Descartado: .godot_agent/hooks.json; prompt que siempre se manda solo; by=any.
- ! Los hooks se editan en Ajustes › MCP servers › Avanzado, debajo de los checks del turno (HooksEditor), no en una pestaña de Extensions como decía el plan. Las tools de un hook solo pueden ser de los grupos read, diagnostics y run. Sin el último resultado en la lista: está en el Agent Log. · sin revisar
  Por qué: Los dos son entradas de project_config.tres con aprobación por máquina, y Ajustes ya los guarda y aprueba al guardar (keys_to_approve), así que comparten el flujo y no hace falta otro guardado de la config en Extensions. Una tool de hook corre sin pasar por el modo (run_for_user): nada que edite ni la shell. El último resultado necesitaba cablear el runner a Ajustes y el log ya lo tiene.
  Descartado: Pestaña Hooks en Extensions con su propio guardado; tools de cualquier grupo; columna con el último resultado.

**Prueba:** Unit: test_project_hooks (7: definición y rechazos, filtros, clave que sigue a la definición menos enabled, placeholders sin shell, runner con aprobación/debounce/env/timeout/falla una vez, procesos parados al salir del árbol, prompt con el evento en sobre), test_hooks_editor (aviso de sin aprobar, keys_to_approve al editar o con Allow, campos por acción, explicación de auto_send, validación), test_run_error_watcher.test_game_ended_for_hooks. Editor (Xvfb, ci grupo editor): hooks_check — guardado sin aprobar avisa y no corre; Aprobar… con el comando en el diálogo; aprobado corre con el próximo guardado; by=agent con lo que escriben las file tools; prompt deja aviso con Send to the agent y no manda; auto_send con tope queda en aviso; tool validate_scripts corre y delete_file (edit_files) no. suite.sh ci 17/17 PASS y i18n PASS en 4.7.2; CI verde en las tres fases (43103212734, 43105120678, 43107251241).

**Notas:** HECHO (sm/m11-24: b534c8d fase 1, 00add70 fases 2-3, bdf4c3c fase 4), según el plan aprobado con estos cambios:
- Eventos: saved, game_stopped, regressions_finished (el «playtest_finished» del plan: lo que hay son tandas de regresiones; RunTools.regressions_finished) y export_started (AgentExportPlugin.on_export_begin, `path` = salida).
- by=agent: un guardado del editor mientras corre una tool del agente (ToolRegistry.running_calls) o lo que escriben sus file tools y fs/write (_after_agent_write).
- Variables: GODOT_AGENT_HOOK, _EVENT, _PATH, _BY, _ERRORS (sin HOOK_JSON).
- Tool: solo grupos read, diagnostics, run (ProjectHooks.TOOL_GROUPS) vía ToolRegistry.tool_group/run_for_user. Las tools de m11-46 entran solas cuando estén en el registry (mismo nombre godot.<x>), con su propia aprobación.
- Prompt: aviso con «Send to the agent» (ACTION_SEND_HOOK_PROMPT) salvo auto_send, tope MAX_AUTO_PROMPTS=2 que se reinicia con un mensaje del usuario sin etiqueta o al apretar el botón; etiqueta HarnessPrompts.HOOK. La protección de bucles es el tope (no hay regla aparte para guardados del agente en un turno de hook).
- Editor en Ajustes (decisión 2), sin columna de último resultado (está en el Agent Log).
- Robustez: HookRunner para sus procesos en _exit_tree (la red de AgentProcess en PREDELETE falla al cerrar el editor: «stop on null instance», ya conocido).
- TurnChecks.run_process compartido con los checks del turno.

**Relacionadas:** Error en un run manual: «Arreglar con el agente»; Checks del proyecto al terminar el turno, con reintento

### Instrucciones que se cargan según el archivo (reglas por ruta o tipo) · Revisión

**Prioridad:** baja · **Tamaño:** S · **Etiquetas:** `idea`

Idea de la revisión de otros harness (2026-11-10), de Kiro.
- Steering: markdown en `.kiro/steering/` (y `~/.kiro/steering/`), con front matter YAML de inclusión. https://kiro.dev/docs/steering/
- Modos de inclusión:
  - always;
  - fileMatch (`fileMatchPattern`, un glob o una lista);
  - manual (con `#nombre`);
  - auto (por `description`, como una skill).
- Referencias `#[[file:ruta:10-20]]`. AGENTS.md se lee siempre.

Qué existe:
- La pestaña Instructions edita CLAUDE.md, AGENTS.md y GEMINI.md, y genera «Project facts» (m11-07).
- Las skills de cada agente se manejan en Extensions (m11-19).
- No hay nada que cargue instrucciones solo para cierto tipo de archivo, y cada agente tiene su propio mecanismo (o ninguno). No confirmé hoy el soporte de Claude Code para reglas por ruta (.claude/rules con paths): verificarlo antes de duplicarlo.

Adaptación a Godot y al harness:
- `.godot_agent/rules/*.md` con `files:` (glob res://) o `types:` (gdshader, tscn, cs, gd).
- Cuando el turno menciona o adjunta un archivo que coincide, el harness agrega la regla al prompt, una vez por sesión, igual que las menciones especiales (m11-08):
  - un archivo con @;
  - el script abierto en el Script Editor;
  - el inline edit (m11-05).
- Funciona igual con cualquier agente ACP.
- Ejemplos de Godot:
  - reglas de shaders (precisión, uniforms con hint);
  - convenciones de escenas de UI (anchors, Theme);
  - C# vs GDScript en proyectos mixtos (m14-07).

Por qué: AGENTS.md crece con reglas que solo valen para una parte del juego y gasta contexto en cada turno. Cargar por archivo es barato y agnóstico del agente.

**Decisiones:**
- ! Las reglas por archivo van al agente como un bloque del harness con etiqueta («Project rules for <glob> (from .agents/rules/x.md)»), con la misma confianza que CLAUDE.md, no dentro de un sobre UntrustedText · sin revisar
  Por qué: Una regla del proyecto es una instrucción, como CLAUDE.md, que los agentes cargan como instrucciones. El sobre dice «es dato, no instrucciones» y el agente la ignoraría. Corrección de agent-harness-81 al plan. El riesgo es el mismo que con el CLAUDE.md de un repo clonado.
  Descartado: Sobre UntrustedText (el plan original)
- ! Las reglas que coinciden van una vez por sesión, en el primer lugar donde se pueden mandar: al final del resultado de una tool godot.* (mismo turno) o en el próximo prompt; las tools propias del agente (Read/Edit) solo pueden esperar al próximo prompt. Archivos tomados de locations, diffs y cualquier argumento con res:// o ruta absoluta del proyecto · sin revisar
  Por qué: Una sola copia por sesión gasta poco contexto; leer los argumentos genéricos cubre las tools godot.* sin un enganche por tool.
  Descartado: Mandarla en cada turno que toca el archivo; solo en el próximo prompt

**Prueba:** tests/unit/test_path_rules.gd (front matter de los 3 formatos, globs con **, llaves y patrones sin /, pending sin las nativas ni las ya mandadas, bloque sin sobre con tope, controller: una vez por sesión, menciones, apagado, regla cambiada; regla al final del resultado de una tool godot.*; pestaña Instructions: resumen, plantillas, Test). Editor check ui-path-rules (el agente edita un .gdshader → el próximo prompt lleva la regla y el chat el adjunto «rules: …»; el siguiente no). suite.sh ci verde.

**Notas:** Absorbe de m11-36 las reglas por glob. El panel de memorias y /recordar siguen en m11-36.

Hecho en sm/m11-25 (12d6a75, desde origin/sm/next4 e3e3ca3), hitos 1 y 2 juntos.
- Verificado 2026-11-12: Claude Code carga solo .claude/rules con `paths:`; Antigravity carga solo .agents/rules (y .agent/rules) con `trigger: glob` + `globs`; Cursor usa .mdc con `globs`/`alwaysApply`; Codex, Gemini, Copilot y OpenCode no tienen reglas por ruta.
- core/path_rules.gd: lee los 3 formatos (solo las reglas por glob, tope de 64 KB, sin symlinks), globs (`**`, `*`, `?`, `{a,b}`; sin / vale en cualquier carpeta), pending (sin native == adapter.kind ni las ya mandadas por hash), block (encabezado del harness y «### Project rules for <globs> (from <file>)», sin sobre, ~4000 caracteres).
- SessionController:
  - path_rules_block: en cada prompt, con los archivos de touched_paths (locations, diffs y args de los tool_call desde el prompt anterior), las rutas del texto, los uri de los adjuntos y context_paths_provider (el script abierto en el Script Editor visible). Va antes del pedido y como adjunto.
  - path_rules_for_tool: ToolRegistry.result_note la pone al final del resultado de godot.*, fuera de los sobres.
  - _rules_sent se reinicia al abrir o reanudar una sesión.
- Config path_rules (Settings → MCP servers → Advanced, prendido por defecto).
- Instructions: rule_summary (patrones y quién la lee sola), plantillas por carpeta, «Test» con una ruta.
- Docs: wiki en/es (Modes and permissions › Rules by file, Settings › Instructions), CHANGELOG, SECURITY.

**Relacionadas:** Memorias visibles y gestionables, y «/recordar» desde el chat (como Windsurf)

### Mapa del proyecto Godot rankeado para el agente (godot.project_map) · Revisión

**Prioridad:** media · **Tamaño:** M · **Etiquetas:** `idea`

Idea de la revisión de otros harness (2026-11-10), de Aider.
- El repo map lista los archivos con sus símbolos clave y las líneas de cada definición. Elige qué entra con un ranking sobre un grafo (archivos = nodos, dependencias = aristas), dentro de un presupuesto de tokens (`--map-tokens`, 1k por defecto) que se ajusta según el chat. https://aider.chat/docs/repomap.html
- Usa tree-sitter para extraer los símbolos: https://aider.chat/2023/10/22/repomap.html. El post es de 2023 y la doc actual no lo nombra: puede haber cambiado.

Qué existe:
- ProjectContext / project_index (m8-03) indexa clases, firmas, nodos por escena, autoloads, input map, grupos y señales, pero solo lo usa el completado.
- El agente explora con grep, scene_tree y class_info, una cosa por vez.

Adaptación a Godot y al harness:
- Una tool godot.project_map(focus?, max_tokens?) que arma el grafo propio de Godot:
  - escenas → scripts adjuntos → class_name usados;
  - ext_resource e instancias de escenas;
  - preload/load con ruta literal;
  - señales conectadas en .tscn;
  - autoloads;
  - grupos.
- Rankea (PageRank personalizado hacia los archivos de `focus` o los mencionados en el turno) y devuelve, hasta el presupuesto:
  - por escena, el árbol resumido;
  - por script, las firmas públicas.
- Reusa el índice que ya existe, sin parser nuevo.

Por qué: en Godot las dependencias reales están en los .tscn, no en los imports, y un grep no las ve. Un mapa así le ahorra al agente varias tool calls de exploración por tarea y lo hace con lo que el harness ya calcula en segundo plano.

**Decisiones:**
- ! El mapa reusa el código de ProjectIndex (parsers de .gd y .tscn) con un modo structure_only y un índice propio cacheado. No usa la instancia del completado. Ranking: PageRank personalizado con damping 0.6 cuando hay foco, aristas de vuelta a la mitad, peso de entrada dividido por √(usuarios) y escena↔script adjunto fuerte en los dos sentidos. Sale entero en sobre no confiable. · sin revisar
  Por qué: El índice del completado solo existe si el completado está prendido, y no tiene preload/load, .tres, identificadores ni firmas. Agregárselos le sumaría costo a cada rebuild del completado. Con structure_only el completado queda igual (hay un test que lo verifica) y el mapa salta el índice de líneas y el n-gram.

  Probado en project-epiphany (744 scripts, 315 escenas, 356 .tres). Con PageRank estándar (0.85), player.gd y game_state.gd quedaban por encima de push_block.tscn al enfocar PushBlock. Con los ajustes salen primero el foco, su escena y sus vecinos reales (Door, Interactable, FloorSwitch, y el jugador, que llama a block_ahead() -> PushBlock).

  Firmas, nombres de nodos y defaults son texto del proyecto, así que todo el resultado va en sobre (ENVELOPE_ALL).
  Descartado: Usar el índice del completado (no existe con el completado apagado, y le faltan datos); un parser nuevo o tree-sitter; PageRank sin personalizar ni atenuar hubs; sacar los strings de las firmas y no usar sobre.

**Prueba:** Unit tests:
- run_all 4.7.2: 555 tests / 4370 checks, 0 fallos.
- project_map, completion_local y tool_group_view también pasan en 4.8-beta2.
- test_project_map (nuevo, fixture tests/map_fixture con .gdignore) cubre:
  - índice structure_only: decls con línea, sin privadas; enum y static; refs; idents; deps de .tres y .tscn;
  - el índice del completado no cambia;
  - grafo: escena→script/instancia, conexión receptor→emisor, autoload, class_name, preload relativo, .tres;
  - resolve_focus por class_name, autoload, archivo, ruta y nombre sin extensión, más lo no encontrado;
  - ranking: vecino directo antes que el de dos saltos y antes que lo suelto;
  - render: header, autoloads, foco primero, declaraciones, «on:», árbol con instancia y %único, conexiones, presupuesto que corta y lo dice;
  - la tool por el registry: en sobre, nota en la descripción, readOnlyHint, focus del editor, «Not found», índice cacheado.
- tool_group_view: nombre «Project map», traducido.

Xvfb 4.7.2: mcp-test con 0 fallas y una llamada real sin focus. Rankea hacia la escena abierta, 2 s en frío en este repo (377 scripts). completion-test con 0 fallas.

Medición (solo lectura, por la API con raíz absoluta) en project-epiphany: 5667 archivos, 744 scripts, 315 escenas, 356 .tres, 5789 aristas.
- Índice en frío: 3.4–3.7 s; en caliente: 60–70 ms.
- Grafo: ~50 ms. Ranking y texto: ~0.4 s.
- Todo corre en un worker y no traba el editor.
little-villages tiene solo 25 scripts, así que usé project-epiphany. En Asteroids: 613 scripts, 129 escenas, 3387 aristas.

**Notas:** 3b21dc9 en sm/m11-26, desde sm/next2 cc1f8f4.

Piezas:
- ProjectIndex.build({structure_only}) saltea el índice de líneas, C# y n-gram. Además:
  - por script: decls ([línea, texto] de class_name, signal, func pública, @export var, enum), refs (preload/load/change_scene_to_file con ruta literal) e idents (palabras con mayúscula);
  - por escena: deps (todos los ext_resource);
  - resource_deps de los .tres.
- ProjectMap (mcp/project_map.gd): grafo, resolve_focus, rank (PageRank personalizado) y render con presupuesto de chars/4.
  - Con una raíz que no es res:// arma una vista con las claves en res://, para tests y medición.
  - Los nodos de escenas heredadas que solo pisan propiedades no se muestran.
- MapTools (mcp/tools/map_tools.gd): godot.project_map(focus?, max_tokens?), grupo read y core (va en tools/list compacto).
  - Arma índice, grafo y texto en WorkerThreadPool; las llamadas simultáneas esperan a la anterior.
  - Guarda el índice y lo reusa por mtime.
  - Sin focus usa la escena editada y el script actual (plugin._editor_focus).
- ENVELOPE_ALL (m11-45).
- Una regla en system_prompt.md para usarla al orientarse.
- Nombre en la UI: «Project map» / «Mapa del proyecto».

Límites:
- «on:» lista solo dónde un script está adjunto, o es la raíz de una escena instanciada; no cada instancia de la escena.
- Los .tres binarios (.res) no se leen.
- Las referencias por uid:// en preload no se resuelven. ext_resource trae path, así que las escenas sí.
- Las clases de C# no entran al grafo: el índice no parsea .cs más allá de líneas.

### Modelo por modo: planificar con uno y construir con otro · Pendiente

**Prioridad:** baja · **Tamaño:** S · **Etiquetas:** `idea`

Idea de la revisión de otros harness (2026-11-10), de Aider.
- El modo architect usa dos modelos: «An architect model will propose changes and an editor model will translate that proposal into specific file edits» (`--editor-model`). La contra: dos pedidos por cambio, más tiempo y costo. https://aider.chat/docs/usage/modes.html
- En su benchmark (2024-09-26), varios modelos mejoraron emparejados consigo mismos (Sonnet 3.5 de 77,4 a 80,5 %), y el mejor resultado salió de un razonador con un editor barato. https://aider.chat/2024/09/26/architect.html. Los números son de modelos viejos.

Qué existe: el modo del harness cambia el modo del agente (Preguntar y Revisar → plan; Construir, Auto y One-shot → default), pero el modelo es uno por sesión, salvo que el usuario lo cambie a mano.

Adaptación a Godot y al harness:
- En Settings → Agentes, un modelo opcional por modo del harness, entre los que anuncia el agente (configOption model).
- Al cambiar de modo, el harness manda session/set_config_option con ese modelo y lo muestra en el chip.
- Junto con el plan aprobable: planificar en Preguntar con el modelo fuerte y «Aprobar y construir» en Construir con el rápido.
- La edición la sigue haciendo el agente: el formato de edits de Aider no aplica.

Por qué: con la cuota del plan (anillos) como límite real, gastar el modelo caro solo en decidir y el barato en escribir es lo que hace el par architect/editor, y acá sale casi gratis porque ACP ya expone el modelo como opción.

**Relacionadas:** Plan aprobable antes de construir (fuera del One-shot); Modelo por modo del harness (sticky), como Plan/Act de Cline y los modos de Roo

### Segunda opinión de otro agente (oráculo de solo lectura) · Revisión

**Prioridad:** baja · **Tamaño:** M · **Etiquetas:** `idea`

Idea de la revisión de otros harness (2026-11-10), de Amp.
- El Oracle (`@amp/oracle`, hoy un plugin opcional) agrega una tool `oracle` que «reviews code and advises on hard decisions, and it never edits files», con modelo y esfuerzo configurables. Delega las búsquedas en Finder y Librarian. https://ampcode.com/docs/models-and-subagents
- No pude confirmar qué modelo usa por defecto: la página no lo dice.

Qué existe:
- Varias sesiones en pestañas, con godot.sessions y godot.session_send entre ellas (m7-44).
- Agentes de cualquier perfil del registro de ACP (m11-12).
- El modo Revisar.
- Falta que una sesión le pida a otra, de otro agente y sin editar, una opinión y reciba la respuesta como resultado de tool.

Adaptación a Godot y al harness:
- Una tool godot.ask_second_opinion(question, files?) que abre (o reusa) una sesión oculta en Preguntar con el perfil elegido en Settings (por ejemplo Codex si construye Claude), le pasa la pregunta, el diff del turno o el plan, y devuelve su respuesta.
- Con permiso de solo lectura forzado y la cuota de ese agente a la vista.
- El usuario también puede pedirla desde el aviso de fin de turno: «Pedir segunda opinión».

Por qué: un segundo modelo, de otra familia y sin el contexto del primero, encuentra errores de diseño que el mismo agente no ve, que es la idea del evaluador del One-shot (D55). El harness ya tiene las piezas (sesiones, perfiles, permisos), y Godot no cambia nada: es agnóstico del agente.

**Decisiones:**
- ! Oráculo sin pestaña, visible con un chip de máquina mientras trabaja; grupo second_opinion Ask en todos los modos y deny en One-shot; su respuesta vuelve en sobre no confiable · sin revisar
  Por qué: Respuestas del coordinador al plan. El chip (como los de m12-47) muestra «Second opinion · thinking · N s» con el agente y el modelo en el tooltip; la conversación se abre desde el aviso. El oráculo leyó código y textos del proyecto, así que su salida puede traer instrucciones plantadas. Al cerrar el editor entra en AgentProcess.stop_all.
  Descartado: Una pestaña visible para el oráculo; sin chip (solo historial); Allow en Preguntar/Revisar

**Prueba:** - run_all: 792 tests, 0 fallos. test_second_opinion (7 tests, 68 checks) cubre:
  - el prompt: la pregunta por defecto, el plan, el diff cortado con la lista de archivos y los @paths;
  - las restricciones de solo lectura en todos los modos;
  - el grupo y sus defaults;
  - la tool: el sobre, el encabezado y los errores;
  - fill_notice;
  - el rechazo solo de las tarjetas;
  - ask sin perfil.
- tests/suite.sh ci en 4.7.2: 20/20 PASS. El check nuevo second-opinion (Xvfb, dos agentes falsos) cubre:
  - el botón del aviso del turno;
  - «Asking…» con Cancel;
  - el chip con el agente y el modelo en el tooltip;
  - delete_file del oráculo denegado (el archivo sigue);
  - session_send del oráculo rechazado;
  - la respuesta plegada con los tokens;
  - «Send to the agent» en sobre con la etiqueta del harness;
  - godot.ask_second_opinion con tarjeta de permiso y el resultado en sobre;
  - /second-opinion seguido de Cancel.
- Está en ci.yml (grupo editor).

**Notas:** HECHO (sm/m11-28, 145600d, desde origin/sm/next4 57ab055). El plan de abajo se implementó con los ajustes del coordinador.

- Hallazgo de seguridad: godot.session_send es del grupo read, que el oráculo tiene permitido. Manda un prompt a otra pestaña sin pedir permiso, así que el oráculo podía meterle instrucciones al agente principal sin sobre. _send_to_session ahora lo rechaza cuando quien llama es SecondOpinion.SESSION_ID. Ninguna otra tool de read o diagnostics tiene efectos.
- /second-opinion sale en el menú de / solo con una sesión abierta, como /handoff.
- Gancho para checks: second_opinion_profile_override en el plugin, como restart_override. El check usa un oráculo falso sin tocar EditorSettings.
- Caveat pendiente: «Open the conversation» usa _open_elsewhere → open_history_session. Abre la sesión del oráculo en una pestaña nueva aunque el proceso del oráculo la siga teniendo cargada. Funciona como lectura, pero dos procesos tienen la misma sesión. Si molesta, se puede parar el oráculo antes de abrirla.
- Archivos principales: session/second_opinion.gd (la clase), mcp/tools/second_opinion_tools.gd (la tool) y addons/godot_agent_dev/second_opinion_check.gd (el check).

--- PLAN original ---

Cómo se lanza
- Sesión oculta, sin pestaña: un SessionController + SessionModel propios en el plugin («el oráculo»), con su propio proceso y el perfil que el usuario elige en Settings › Agentes › «Second opinion» (ajuste del usuario; por defecto ninguno). Si no hay perfil, la tool y los botones dicen cómo elegirlo.
- Uno solo en el editor, arrancado a la primera pregunta y reusado después: no paga el arranque ni el prompt de sistema en cada pregunta (con claude-agent-acp son ~40k tokens de cache write la primera vez, lo vi en el probe de m11-38). Las preguntas van de a una (cola); timeout de 5 min, después se cancela. Se cierra con el editor o con «Nueva sesión» del oráculo.
- Solo lectura forzada, como el evaluador de QA del One-shot: policy.restrictions con read y diagnostics en allow y todo lo demás en deny (editar, project, shell, run, addons, project_tools). mode_rules_override: «You are a second opinion… never edit, answer with findings». Va en Preguntar (agente en plan), con el server MCP del addon para leer escenas y scripts.
- La conversación queda en el historial (SessionHistory, etiqueta «Second opinion»), así el usuario la abre como cualquier sesión pasada si quiere ver qué leyó.

Quién la pide
1) El agente: godot.ask_second_opinion(question, include_turn_diff?=true, paths?=[]) devuelve la respuesta como resultado de la tool (sellado en sobre como todo resultado). Grupo de permisos nuevo «second_opinion», porque gasta la cuota de otra cuenta: Ask en todos los modos por defecto, deny en One-shot (el run ya tiene su evaluador). El usuario lo cambia en la matriz.
2) El usuario:
- «Second opinion» en el aviso de fin de turno de Construir/Auto con cambios: sobre el diff del turno.
- «Second opinion…» en la tarjeta del plan, antes de aprobar: sobre el plan.
- /second-opinion <pregunta> en el composer.

Qué contexto recibe (sin la conversación principal: la independencia es el punto, como D55)
- La pregunta: la del agente o la del usuario. Si no hay, una por defecto: riesgos, bugs, problemas de diseño y qué haría distinto, con archivo:línea.
- El diff del turno desde los snapshots (m11-01): unificado, cortado a ~30k caracteres, con la lista de archivos si se corta. Sin snapshots, la lista de archivos que tocó el turno, para que los lea.
- El plan, si viene de la tarjeta.
- Los paths que pase el agente: van como @ruta; el oráculo los lee con sus tools.
- Las instrucciones del proyecto (CLAUDE.md/AGENTS.md) las carga el agente solo, por el cwd.

Cómo vuelve la respuesta
- A la tool del agente: como resultado de tool, con una línea de encabezado «Second opinion from <perfil> (<modelo>), <N> tokens».
- Al usuario: un aviso en la pestaña que la pidió, con la respuesta plegada (Markdown), el agente y modelo, los tokens y dos botones:
  - «Send to the agent»: harness prompt SECOND_OPINION, con la respuesta en sobre no confiable.
  - «Open the conversation».
  No se manda sola: el usuario decide si el agente principal la ve. Desde la tarjeta del plan, el aviso queda debajo de la tarjeta, que sigue esperando.
- Mientras corre, el aviso muestra «Asking <perfil> for a second opinion…» con «Cancel».

Costo en tokens
- Primera pregunta: el arranque de la sesión del otro agente (prompt de sistema y tools; ~40k de cache write con Claude Code), más el diff y lo que lea. Las siguientes reusan el cache.
- Se ve en cada respuesta: los tokens del turno del oráculo, de usage/_meta. Además, la cuota de esa cuenta va a la tabla de cuotas existente, porque es otro perfil.
- Topes: diff cortado, una pregunta a la vez, timeout. El agente no puede pedirla en bucle porque pregunta por el permiso; el detector de loops de m11-49 no aplica fuera del playtest.

Pruebas
- Unit: el armado del prompt (diff cortado, plan, paths), las restricciones de solo lectura, el grupo nuevo y sus defaults, la tool sin perfil y la cola.
- Editor (Xvfb): agente principal falso más oráculo falso (fake_agent con su propio escenario).
  - El botón del fin de turno manda el diff y la respuesta vuelve en el aviso.
  - «Send to the agent» sale en sobre.
  - La tool desde el agente devuelve el texto.
  - Si el oráculo intenta editar, se deniega.
  - Cancelar corta el turno.

Fuera de esta tarea: la segunda opinión dentro del One-shot, y elegir el modelo del oráculo (usa el que recuerde para Preguntar ese perfil, por m11-38).

### Mencionar otra sesión y seguir en una nueva con un traspaso · Revisión

**Prioridad:** media · **Tamaño:** S · **Etiquetas:** `idea`

Idea de la revisión de otros harness (2026-11-10), de Amp.
- Pegar la URL de un hilo o escribir `@T-…` hace que el agente lo lea y saque lo que importa para la tarea actual; `@@` busca hilos. https://ampcode.com/docs/threads
- Handoff (2025-10) reemplazó la compactación: el usuario dice el objetivo del hilo nuevo y Amp arma un borrador de prompt con el contexto relevante y la lista de archivos, que se revisa antes de mandar. https://ampcode.com/news/handoff
- Ojo, no está claro el estado actual: una nota en https://ampcode.com/news/stick-a-fork-in-it dice «we removed handoff» y recomienda abrir un hilo nuevo y mencionar el original. La doc de threads todavía nombra «Handoff and …». Lo que sigue vigente seguro es la mención de hilos.

Qué existe: un historial local de sesiones por proyecto (session_history, con el menú de historial) y session/list del agente (m11-16). Las menciones especiales (@errors, @game, m11-08) no incluyen otra sesión.

Adaptación a Godot y al harness:
- `@session:<nombre o fecha>` en el composer (con autocompletado desde el historial): el harness agrega como bloque de contexto lo esencial de esa sesión. No el transcript entero, sino:
  - pedidos del usuario;
  - archivos cambiados (de los snapshots de turno);
  - decisiones y el último plan.
- Funciona entre agentes distintos.
- Encima de eso, «Seguir en una sesión nueva» en el medidor de contexto: pide el objetivo, arma el borrador con esa mención y lo deja editable en el composer.

Por qué: con varias pestañas y agentes, retomar o pasar trabajo entre sesiones hoy obliga a copiar y pegar. Que el harness tenga el historial de todos los agentes hace esto agnóstico, algo que ningún agente hace solo.

**Prueba:** Headless: test_session_digest y test_mentions (@session:<id>). Editor: ui-handoff (sesión cerrada de otro agente en el menú de @, bloque en sobre al mandar, adjunto con título en el chat). La parte de traspaso, en m11-35.

**Notas:** Hecho en sm/m11-35 (653f149): session/session_digest.gd, @session:<id> en el composer (menú con las otras sesiones del historial del proyecto), bloque en sobre UntrustedText marcado como contexto, adjunto «@session:… · título» con tooltip. «Seguir en una sesión nueva» con borrador se hizo en m11-35 (0608d63).

**Relacionadas:** Traspaso entre sesiones: «Nueva sesión con resumen» cerca del límite de contexto y un archivo de traspaso (Zed + memory bank de Cline)

### Recetas: pedidos reutilizables con parámetros y checks · Revisión

**Prioridad:** media · **Tamaño:** M · **Etiquetas:** `idea`

Idea de la revisión de otros harness (2026-11-10), de Goose.
- Una recipe (YAML o JSON) tiene:
  - title y description;
  - instructions y/o prompt con plantillas;
  - parameters (key, input_type, requirement, default, options);
  - extensions (MCP);
  - settings (proveedor, modelo, max_turns);
  - response.json_schema para salida estructurada;
  - retry con checks de shell que tienen que salir con 0 (si fallan, resetea la historia y reintenta hasta max_retries);
  - sub_recipes.

  https://goose-docs.ai/docs/guides/recipes/recipe-reference/
- Se comparten como archivo o deeplink («Each recipient gets their own private session») y se corren con `goose run --recipe` (también por cron). https://goose-docs.ai/docs/guides/recipes/session-recipes/

Qué existe:
- Las skills y slash commands de cada agente se ven en Extensions, pero son del agente, sin formulario de parámetros ni checks.
- El One-shot tiene su formulario y sus checks, pero para un juego entero.

Adaptación a Godot y al harness:
- `.godot_agent/recipes/*.json`, versionables, con una pestaña en Extensions.
- Cada receta tiene título, modo del harness, prompt con `{{param}}` y parámetros con tipos propios de Godot: escena, nodo, recurso, acción de input, ruta res://.
- Los checks pueden ser:
  - validate_scripts;
  - regresiones de playtest;
  - un playtest con veredicto;
  - un comando.
- Con tope de reintentos.
- Ejemplos de juego: «Agregar enemigo {escena base} con comportamiento {texto}», «Pantalla de opciones con {ajustes}», «Portar {script} a C#».
- Se lanzan desde el dock (menú de recetas, formulario generado) y el resultado lo dice el aviso de fin de turno.

Por qué: los pedidos de un juego se repiten (enemigos, niveles, menús), y una receta con checks hace el resultado más predecible, para cualquier agente. El equipo la comparte por git. Ver la idea de checks del proyecto, que es la mitad de esto.

**Decisiones:**
- ! recipes_dir va después de turn_checks en project_config y el bloque «Recipes» de Settings va después de la lista de checks del proyecto, no pegados a lo de m11-46 · sin revisar
  Por qué: Así sm/m11-30 y sm/m11-46 no tocan las mismas líneas (project_tools_dir va debajo de mcp_servers y «Project tools» antes de «Folders outside the project»), y el merge sale sin conflictos. Además, recetas y checks quedan juntos.
  Descartado: Pegados a project_tools_dir / «Project tools», como se había propuesto: daba conflicto textual en el merge.
- ! Los checks de una receta corren después de cada turno aunque el turno no haya cambiado archivos (salvo que tengan paths); una receta sin checks no arma corrida · sin revisar
  Por qué: Los checks de la receta dicen si el pedido está hecho, no solo si se rompió algo. Sin checks no hay nada que reintentar ni que avisar.
  Descartado: Los mismos criterios que los checks del proyecto (solo con cambios).
- ! Hito 1: los mensajes de validación de una receta (campo desconocido, {{x}} sin parámetro…) quedan en inglés; los checks de tipo playtest se rechazan como «unknown kind» hasta el hito 2 · sin revisar
  Por qué: Hoy solo aparecen en el tooltip de una receta rota y en el aviso de /recipe. Se traducen en el hito 2 junto con el editor con validación en vivo, que es donde se leen. El check playtest es parte del hito 2 según el plan.
  Descartado: Traducirlos ya: unas 25 entradas más en es.po que el hito 2 probablemente reescribe.
- ! Si un check de comando de la receta no está aprobado en esta máquina, no corre y la corrida termina con un aviso («el resultado no se comprobó») en vez de reintentar · sin revisar
  Por qué: Sin aprobar no se sabe si el pedido pasa, y mandarle reintentos al agente no lo resuelve. El aviso de los checks ya ofrece «Aprobar…». Una receta clonada no corre nada sin preguntar.
  Descartado: Dejar la corrida abierta hasta que se apruebe.
- ! Check playtest: corre solo cuando los otros checks de la receta pasan, como un turno en Revisar (prompt del harness «Recipe · playtest»); pass termina, fail vuelve como corrección dentro de max_retries, blocked/sin veredicto termina la corrida con aviso · sin revisar
  Por qué: Jugar cuesta tokens y tiempo: no tiene sentido si Lint/tests fallan. Un «could not test» no se arregla con otro turno de código.
  Descartado: Playtest en paralelo con los otros; blocked contado como fail y reintentado
- ! «Plan first»: casilla en el formulario (default = "plan" de la receta); el composer queda con /plan <pedido> y la corrida arranca en «Aprobar y construir», en Construir (no en el modo de la receta) · sin revisar
  Por qué: Reusa el flujo /plan de m11-22/m11-58 tal cual; aprobar el plan pasa a Construir por diseño.
  Descartado: Tras aprobar, pasar al modo de la receta (Auto); un flujo de plan propio de recetas
- ! Pestaña Recipes sin «Borrar» (se borra desde el FileSystem); guardar con errores se permite, «Use in the dock» exige receta válida y guardada. Validación traducida en la fuente (recipes.gd), así también el dock la muestra en español. La carpeta de recetas se excluye de los exports · sin revisar
  Por qué: Alcance acotado; guardar a medias es útil al editar; los .json se exportarían como recursos sin servir al juego.
  Descartado: Botón Borrar con confirmación; bloquear el guardado con errores; traducir solo en la pestaña

**Prueba:** tests/unit/test_recipes.gd (parse/validación con playtest, valores y expand, load_dir/find, formulario, corrida con reintentos, playtest pass/fail/blocked, «Plan first» arranca con Aprobar y construir, plantillas y pestaña Recipes); test_claude_extensions (9 pestañas); editor check ui-recipe (formulario → composer → Lint falla → reintento → pasa; pestaña Recipes lista la receta válida, «Use in the dock» abre el formulario, «Plan first» deja /plan en el composer). suite.sh ci verde.

**Notas:** Hito 1 (f014d21) y hito 2 (10f4806) en sm/m11-30, con origin/sm/next4 mergeado.
- Recetas en res://agent_recipes/*.json (Settings → MCP servers → Advanced → Recipes); core/recipes.gd (formato, validación traducida, expand, run_spec), core/recipe_templates.gd (3 plantillas), core/project_dirs.gd.
- Dock: /recipe y + → Receta…, formulario recipe_form.gd, chip con los checks. Controller: corrida con max_retries, check playtest (turno en Revisar después de los otros; pass/fail/blocked), «Plan first» vía /plan y arranque en approve_plan; los prompts con etiqueta del harness no cortan la corrida.
- Extensiones → Recipes (recipes_tab.gd): lista con estado, editor JSON con validación en vivo, New desde plantilla, Use in the dock.
- Comandos de checks: misma aprobación por máquina que los checks del proyecto. Carpeta excluida del export.
- Docs: wiki en/es (Modes and permissions › Recipes, Settings), CHANGELOG, SECURITY.

**Relacionadas:** Checks del proyecto al terminar el turno, con reintento

### Checks del proyecto al terminar el turno, con reintento · Revisión

**Prioridad:** media · **Tamaño:** S · **Etiquetas:** `idea`

Idea de la revisión de otros harness (2026-11-10), de Goose.
- `retry` de una recipe: max_retries y checks de tipo shell que tienen que salir con 0, con timeout_seconds (300 por defecto) y on_failure. Después de cada corrida se ejecutan en orden y, si alguno falla, goose corre on_failure y reintenta. https://goose-docs.ai/docs/guides/recipes/recipe-reference/
- En Kiro, el mismo patrón es un hook Agent Stop. https://kiro.dev/docs/hooks/types/

Qué existe: la verificación automática (m11-04) solo corre validate_scripts sobre los .gd cambiados y le devuelve los errores al agente, hasta 2 turnos.

Adaptación a Godot y al harness:
- En Settings, una lista de checks del proyecto (en project_config, versionable) que corren después de cada turno de Construir/Auto con cambios:
  - las regresiones de playtest guardadas (las mismas del CI workflow);
  - un runner de tests (gdUnit4 o GUT headless);
  - un comando, pasando por las reglas de shell.
- Con filtro por ruta: solo si el turno tocó `res://player/**`.
- La falla vuelve al agente como hoy, con el mismo tope.
- El aviso de fin de turno muestra ✓/✗ por check.

Por qué: un juego con regresiones grabadas o tests ya tiene la mejor señal de «esto se rompió». Correrla en cada turno y no solo en el CI agarra el error mientras el agente todavía tiene el contexto. Es una extensión chica de m11-04.

**Decisiones:**
- ! Cómo se configuran los checks del proyecto al terminar el turno. Dónde viven: - En project_config.tres (`turn_checks: Array`), versionable con el proyecto. Se editan en Settings → MCP servers, en la sección avanzada donde está «Check the scripts after each turn». - Cada check es {name, kind, command, paths, timeout_s, enabled}. - kind "regressions": las regresiones de playtest guardadas, con el mismo regression_cli.gd que el workflow de CI, en un Godot headless aparte. No toma el Play del editor. - kind "command": un programa con argumentos. GUT y gdUnit4 son presets que completan el comando. - `{godot}` en el comando se reemplaza por el binario del editor. - paths: globs res:// (`res://player/**`). Vacío = cualquier cambio. - timeout_s: 300 por defecto. Qué comandos se permiten: - Un solo programa con sus argumentos, sin shell: OS.create_process con los argumentos ya separados (comillas simples y dobles), sin `|`, `&&`, `;`, redirecciones ni `$()`. Un comando con eso se rechaza al guardarlo. - Lo que necesite shell va en un script del proyecto (`sh tests/run.sh`). Cómo pasan por los permisos: - Las regresiones no piden nada: son del harness y sus scripts ya pasan por el bloqueo de APIs (PlaytestRegressions.SCRIPT_BLOCKED). - Un comando corre solo si quien usa este editor aprobó ese texto exacto en esta máquina. La aprobación queda en los ajustes del usuario (no en el proyecto), con la ruta del proyecto y un hash del comando. - Agregarlo o editarlo en Settings ya cuenta como aprobarlo. - Un comando que viene en el archivo sin aprobar (un proyecto clonado, otro miembro del equipo, o lo cambió el agente desde la shell) no corre: el aviso del fin de turno lo marca «sin aprobar en esta máquina» con «Aprobar…», que muestra el comando. - Las reglas de shell del modo Auto no deciden: también viven en project_config, así que un proyecto podría traer su propio comando y la regla que lo permite. Cuándo corren: - Después de un turno de Construir o Auto que terminó con end_turn y cambió archivos. Los cambios salen de los mtime ≥ inicio del turno, sin .godot, .git ni .godot_agent, así que no hace falta git. - Corren después de validate_scripts y solo si los scripts parsean. - En orden. Uno que falla no frena a los demás. - Lo que fallen vuelve al agente como prompt del harness TURN_CHECK, con la salida recortada y sellada como texto no confiable, y comparte el tope de 2 turnos con validate_scripts. - El aviso del fin de turno muestra ✓/✗ por check. · sin revisar
  Por qué: project_config.tres viaja con el proyecto, así que cualquiera que lo clone le puede plantar un comando que correría después de cada turno sin que nadie lo apruebe. Por eso la aprobación es local y por el texto exacto. Las file tools del agente no escriben addons/godot_agent (ProtectedPaths), pero en Auto la shell sí podría. Sin shell, el comando se comporta igual en Linux, macOS y Windows, y no hay que analizar cadenas ni redirecciones. Las regresiones van en otro proceso para no tomar el Play del editor mientras el usuario mira.
  Descartado: - Pasar el comando por ShellRules.classify con las reglas de Auto: las reglas también vienen en el proyecto.
  - Correr por `sh -c` / `cmd /c`: cada plataforma distinta, y otra vez un shell completo.
  - Guardar los checks en los ajustes del usuario: no se comparten con el equipo ni con el CI.
  - Detectar cambios por los snapshots de git: no anda sin git.

**Prueba:** - tests/unit/test_turn_checks.gd (8 tests, 72 checks): parse_command sin shell, normalize, applies/changed_since, tienda de aprobación (clave por proyecto + texto exacto), aviso y prompt (sobre sellado), corridas reales (0, código ≠ 0, tope de tiempo, programa inexistente), flujo del controller (copia aparte, aprobado/sin aprobar, «Aprobar…», tope de arreglos, Preguntar no corre), lista de Settings (qué aprueba guardar).
- Check de editor `tests/suite.sh run checks` (--godot-agent-checks-test, turn_checks_check.gd + tests/scripts/turn_checks.json): en Auto, Lint falla → TURN_CHECK con la salida en sobre; Script sin aprobar → «Aprobar…» → diálogo con el comando → aprobado; el turno de arreglo pasa los dos. En suite ci y ci.yml.
- suite.sh ci 15/15 en 4.7.2; i18n en español PASS; captura de Settings con la lista revisada.

**Notas:** Absorbe la extensión de m11-04 (done: validate_scripts al terminar el turno con hasta 2 reintentos): suma checks del proyecto con el mismo tope. Relacionadas: m11-24 (si se hacen hooks, esto es el disparador «fin de turno»), m11-30 (recetas con retry) y m11-42 (correr las regresiones repetidas para no reintentar por una inestable).

Hecho en sm/m11-31 (934da58, desde origin/sm/next3):
- core/turn_checks.gd: modelo, parse sin shell, {godot}/{project}, globs, mtime, run con AgentProcess y tope.
- La clave de aprobación usa la carpeta del proyecto del editor (provider "project"), no el cwd de la sesión: en una copia aparte (worktree) Settings y la sesión verían claves distintas.
- ui/settings/turn_checks_editor.gd en Settings → MCP servers → Avanzado; HarnessSettings security/approved_commands {clave: fecha}.
- El check de editor aprueba en una tienda en memoria: el Xvfb usa los EditorSettings reales del usuario.
- m13-31 (MCP servers del proyecto) debe reusar HarnessSettings.is_command_approved/approve_command y el «Aprobar…» del dock (_confirm_turn_check).

**Relacionadas:** Verificación automática al terminar cada turno; Hooks del proyecto en eventos del editor; Recetas: pedidos reutilizables con parámetros y checks

### Exportar una sesión para compartirla (Markdown con capturas) · Revisión

**Prioridad:** baja · **Tamaño:** S · **Etiquetas:** `idea`

Idea de la revisión de otros harness (2026-11-10), de Amp.
- Los hilos se comparten con visibilidad Private, Workspace, Group o Unlisted (con el link). https://ampcode.com/docs/threads
- Los commits del agente llevan un trailer `Amp-Thread-ID` que vincula el cambio con su conversación (misma página).

Qué existe: «Guardar reporte» de un turno (m11-06: report.md con lo que dijo el agente, los archivos y las capturas) y el informe del One-shot (RunReport.to_markdown). No hay forma de llevarse una sesión entera.

Adaptación a Godot y al harness:
- En el menú del historial, «Exportar sesión»: arma `.godot_agent/reports/<fecha>-session/session.md` con los pedidos, las respuestas, las tool calls resumidas (como en el chat, plegadas), los diffs por turno y las capturas del juego como PNG.
- Los secretos van redactados, como en todo lo que se muestra (PRIVACY.md › Secrets).
- Opcional: un trailer `Godot-Agent-Session: <id>` en los commits que haga el agente, cuando el usuario lo pida.
- Sin servidor: compartir es pasar la carpeta o subirla donde quiera el usuario.

Por qué: mostrar cómo se llegó a un cambio (para un PR, un bug report o enseñar) hoy obliga a sacar capturas del dock. Las capturas del juego, que ningún otro harness tiene, son lo que hace útil el export. Y no hace falta el backend de Amp.

**Decisiones:**
- ! «Export session…» va en el menú ⋯ del dock y exporta la pestaña, no una entrada del menú del historial. Por defecto saca las rutas absolutas, los emails y el contenido de los sobres no confiables, y deja las capturas; cada casilla dice cuánto encontró y la vista previa cambia al marcarla. · sin revisar
  Por qué: El historial no guarda las imágenes, y las capturas son lo que hace útil el export: sale del modelo vivo de la pestaña. Lo más seguro para compartir es sacar por defecto; el usuario ve y puede devolver cada cosa. Las capturas quedan porque son el propósito, y se pueden sacar.
  Descartado: Exportar desde el menú del historial (sin capturas). Preguntar sin nada marcado. Sacar también las capturas por defecto.

**Prueba:** Headless: tests/run_all.gd -- test_session_export: find cuenta rutas (proyecto, otro usuario, /tmp), emails, sobres y capturas; todo sacado: proyecto relativo, ~, <path>, sin email, sin sobre (con aviso), sin secreto, sin capturas; nada sacado: estructura, sobre sin marcas, secreto igual fuera, captura enlazada, diff, tool calls plegadas; write; el diálogo (por defecto saca rutas/emails/afuera y deja capturas, vista previa filtrada, casillas con cuántos y cuáles, desmarcar cambia la vista, guarda lo que se vio). Editor: ui-handoff exporta la conversación del check desde el dock.

**Notas:** Hecho en sm/m11-32 (72b4ed3).
- session/session_export.gd: build, find, filter, write.
- ui/dock/session_export_dialog.gd: casillas, vista previa, Guardar.
- agent_dock: MORE_EXPORT en ⋯, open_export_dialog y export_context (proyecto, HOME/USERPROFILE, email de model.account, agent_log.redact).
- Sale del modelo de la pestaña: el historial guarda las capturas como placeholder. Para exportar una sesión vieja hay que abrirla (sin capturas).
- Fuera de alcance: el trailer Godot-Agent-Session en commits (opcional en la descripción).

### Seguir al agente: el editor salta a cada archivo y nodo que toca (como Zed) · Revisión

**Prioridad:** media · **Tamaño:** M · **Etiquetas:** `idea`

Idea de la investigación de UX (2026-11-10). Zed: «Follow the agent as it reads and edits files by clicking the crosshair icon at the bottom left of the panel. Your editor will jump to each file the agent touches», y mantener cmd/ctrl al enviar sigue automáticamente (https://zed.dev/docs/ai/agent-panel). Hoy el harness ofrece «Abrir en Script» por tarjeta y las marcas de Revisar, pero mirar qué hace el agente mientras trabaja es manual. Propuesta: un toggle «Seguir» en el encabezado del dock (y Ctrl+Enter al enviar): con cada tool call de edición el editor abre el script en la línea del diff, selecciona el nodo de set_properties/create_scene en el árbol o enfoca la escena que corre; se apaga solo si el usuario toca otra cosa. Diferencial: en Godot «seguir» incluye el Scene Tree y el viewport, no solo archivos.

**Decisiones:**
- ! El apagado es por pestaña: un toggle en el header del dock, apagado al abrir cada pestaña, sin persistir y sin opción en Settings · sin revisar
  Por qué: Seguir tiene sentido para una sesión que estás mirando; con varias pestañas, cada una decide. Apagado por defecto porque mover el editor sin pedirlo sorprende a quien no lo prendió.
  Descartado: Una opción global en Settings; recordar el estado entre reinicios (por proyecto o por pestaña)
- ! Con el usuario trabajando en el editor, el salto espera 2,5 s sin input y va al último cambio, en vez de apagar el seguimiento solo · sin revisar
  Por qué: Lo pidió el coordinador: no robar el foco mientras se escribe o edita una escena. Si se apagara solo con cada clic, habría que volver a prenderlo todo el tiempo. Cuenta como trabajo un clic, una tecla o un arrastre fuera del dock, o el foco en un campo de texto fuera del dock. Si el foco estaba en el composer, vuelve ahí.
  Descartado: Apagarlo solo cuando el usuario toca otra cosa, como proponía la idea original
- ! Solo saltan las ediciones terminadas, no las lecturas ni los borrados, y por ahora no hay Ctrl+Enter ni enfoque de la escena que corre · sin revisar
  Por qué: Saltar por cada lectura mueve el editor sin parar mientras el agente explora. Un archivo borrado no se puede abrir. El atajo y el foco del juego son extras que se pueden sumar después.
  Descartado: Seguir también las lecturas, como Zed; Ctrl+Enter al enviar; enfocar la vista Game con run_scene

**Prueba:** tests/unit/test_agent_follower.gd covers the targets per tool, that reads and deletes don't jump, waiting with the latest change pending, and cancel. In the editor, --godot-agent-sessions-test checks that the active tab with follow on opens the scene and selects the node, the other tab doesn't move anything, recent input makes it wait before jumping, and nothing happens when follow is off. A mutation run (follow disabled) makes all 4 checks fail. suite.sh ci passes 13/13 on 4.7.2.

**Notas:** Branch sm/m11-33, commit 69a5b7b, from origin/main 46dc03e.
- New file editor/agent_follower.gd. In plugin.gd, _follow_call is invoked from _on_tool_call_changed, after the replay check, and only acts on the active tab's model when that dock has follow_enabled. Switching tabs or turning follow off cancels the pending jump.
- The FollowButton (CenterView icon, the crosshair) sits in the header before History.
- Paths outside the project are not opened, for example from a separate copy.
- Not done, possible follow-ups: Ctrl+Enter to follow on send, focusing the Game view during run_scene, and following reads.

### Revisar los cambios del turno por trozo (keep/reject) y contador vivo de archivos (como Zed) · Revisión

**Prioridad:** media · **Tamaño:** L · **Etiquetas:** `idea`

Idea de la investigación de UX (2026-11-10). Zed muestra durante el turno «which files, how many of them, and how many lines have been edited» en un acordeón arriba del composer, y «Review Changes» abre un multibuffer donde «You can accept or reject each individual change hunk, or the whole set of changes»; con agent.single_file_review los diffs aparecen en el propio archivo con los mismos controles (https://zed.dev/docs/ai/agent-panel). El harness tiene el diálogo de cambios del turno (m11-02) con diff y «Volver atrás» por archivo entero. Propuesta: (1) una línea plegable arriba del composer mientras el turno corre: «3 archivos · +42 −7 · Ver cambios»; (2) en el diálogo, keep/reject por trozo usando el snapshot del turno (git apply -R del hunk), y «Rechazar todo»; (3) opcional, las marcas del diff en el Script Editor con el mismo keep/reject, reusando las anotaciones de Revisar.

**Prueba:** - Unitarios:
  - test_turn_hunks: trozos, stale, deshacer, subcarpeta del repo, peek sin refs, serialización.
  - test_turn_changes_hunks: conservar, rechazar, deshacer desde el chat, stale, sin guardar, reclamado por otra sesión, turno corriendo, copia aparte y escenas por nodo.
  - test_scene_revert: ida y vuelta por cambio, todo rechazado da la escena de antes, texto idéntico al deshacer, stale, por unique_id.
  - test_turn_counter.
- edit-test:
  - las guardas con el Script Editor y una escena abiertos de verdad;
  - escena abierta y guardada, cambiada por las tools del agente: rechazar una propiedad deja el árbol con el valor de antes, sin «cambió en disco» y sin marcarla sin guardar; Deshacer la vuelve. Con la recarga desactivada a propósito, el check falla.
- Capturas del diálogo de texto y del de escena.
- suite.sh ci en verde en 4.7.2 en cada hito.

**Notas:** Absorbe m11-57 dentro de la misma vista: para .tscn el diff por nodos (agregados, quitados, movidos, propiedades antes → después) reemplaza al diff de texto, y keep/reject por trozo se vuelve por nodo. La tool scene_diff para el agente sigue en m11-57.

PLAN (2026-11-11, esperando el ok del coordinador; rama sm/m11-34 desde next3 f8b3205)

1. Trozos y rechazo
- Los trozos salen de git diff -U3 entre turn_start y turn_end. Ese diff es lo que hizo el turno. Ya están en data.start y data.end del aviso.
- Rechazar un trozo:
  - Se arma un parche con el encabezado del archivo y ese trozo solo.
  - Se corre git apply -R --check sobre el archivo actual del worktree y, si pasa, git apply -R. Con -C de la raíz de los snapshots, sin --index: no toca el index del usuario.
  - git apply busca el contexto con desplazamiento. Si el usuario o el agente editaron otra parte del archivo después, el trozo se revierte igual.
  - Si cambiaron esas mismas líneas, el --check falla y no se pisa nada: el trozo queda como «cambió después del turno» y su Rechazar se deshabilita. El tooltip ofrece «Volver atrás» del archivo entero, el de hoy, que sí pisa y pide confirmación.
- Conservar: es una marca, el archivo no cambia. Sirve para ver qué falta revisar.
- Deshacer un rechazo: git apply hacia adelante del mismo trozo, también con --check. Es simétrico y tampoco pisa ediciones posteriores.
- Rechazar todo en un archivo: aplica en reversa los trozos que pasan el --check e informa los que no.
- Rechazar todo el turno: es el «Deshacer el turno» de hoy y no cambia.
- El estado de cada trozo (keep, rejected o stale) vive en el data del aviso, en memoria. Los ids son ruta más índice del trozo en el diff start→end.
- El --check se calcula al abrir el archivo en el diálogo.

2. Editor abierto y undo
- Un script abierto con cambios sin guardar (EditorSync.buffer_text no es null) no se toca. Rechazar queda deshabilitado con «guardá o descartá tus cambios en el editor». Si no, se perderían o habría conflicto.
- Una escena abierta con cambios sin guardar, igual (get_unsaved_scenes).
- Sin cambios pendientes, después de escribir se llama al after_restore de hoy (EditorSync.sync_path y recarga de la escena abierta), igual que «Volver atrás».
- Ctrl+Z del editor: no cubre escrituras a disco, como hoy con «Volver atrás». El deshacer es el botón Deshacer del trozo en el diálogo, más un aviso en el chat que también ofrece Deshacer.
- Al agente, como en restore(): note_for_agent con «el usuario rechazó N cambios en X: releelos antes de editarlos».
- Durante un turno de otra sesión que tiene el archivo reclamado (SessionCoordinator.claim_label), Rechazar se bloquea con el nombre de esa sesión.

3. Escenas (.tscn)
- Por nodo, sobre el parse de m11-57:
  - Rechazar una propiedad cambiada: vuelve esa línea de la sección del nodo a su valor de antes, o la borra si era el valor por defecto.
  - Rechazar un nodo agregado: borra su sección, la de sus descendientes y las conexiones que los nombran.
- Se edita el texto actual de la escena y se verifica antes: la sección del nodo se encuentra por unique_id o ruta, y la propiedad tiene que seguir con el valor de después. Si no, el cambio queda stale, igual que un trozo.
- Fase 2, si el ok lo incluye: rechazar un nodo borrado o movido, propiedades con SubResource o ExtResource nuevos, y cambios de conexiones. Hasta entonces, para eso queda «Volver atrás» del archivo, con confirmación. Necesitan rearmar ext_resource y sub_resource con ids nuevos.

4. Contador vivo
- Una línea plegable arriba del composer mientras corre el turno: «3 archivos · +42 −7 · Ver cambios».
- TurnSnapshots gana peek(session): write-tree con el index propio, sin commit, sin ref y sin prune, y git diff --numstat turn_start árbol. take() no sirve: sus refs y el prune podrían sacar a turn_start.
- Se recalcula en un thread después de cada tool call de escritura terminada, a lo sumo cada 2 s, y una vez más al terminar el turno. Al terminar queda el resumen de hoy.
- «Ver cambios» durante el turno abre el diálogo de solo lectura, porque el agente sigue escribiendo. Conservar y Rechazar se habilitan al terminar el turno.

5. Copia aparte (m11-09)
- Todo pasa por _snapshots_of(session): los snapshots de la copia y git apply -C en la raíz de la copia.
- En la copia no hay nada abierto en el editor, así que no hay chequeo de buffers ni recarga, igual que restore() hoy.

6. Fuera de esta tarea
- Las marcas del diff en el Script Editor con keep/reject (punto 3 opcional de la idea): seguimiento aparte, reusando las anotaciones de Revisar.

Tests
- Unitarios sobre un repo git temporal, como test_turn_snapshots:
  - un trozo se revierte con una edición posterior en otra parte del archivo;
  - con una edición posterior en las mismas líneas, el trozo queda stale y el archivo no cambia;
  - Deshacer re-aplica el trozo;
  - rechazo por nodo en una .tscn;
  - peek no crea refs.
- Check de editor: script abierto sin y con cambios sin guardar, y escena abierta.

**Bloquea a:** Rechazar por nodo en escenas, fase 2: nodos borrados o movidos, recursos nuevos y conexiones

**Relacionadas:** Diff por nodos de las escenas en los cambios del turno

### Traspaso entre sesiones: «Nueva sesión con resumen» cerca del límite de contexto y un archivo de traspaso (Zed + memory bank de Cline) · Revisión

**Prioridad:** media · **Tamaño:** M · **Etiquetas:** `idea`

Idea de la investigación de UX (2026-11-10). Zed: «New From Summary» en el menú de nuevo hilo «starts a fresh Zed Agent thread seeded with a summary of the current conversation», y un banner ofrece «Start New Thread» al acercarse al límite (https://zed.dev/docs/ai/agent-panel). Cline: el memory bank son archivos markdown del proyecto (projectbrief, activeContext, progress…) que el agente mantiene; antes de que el contexto se llene se pide «update memory bank», se abre otra conversación y se le dice «follow your custom instructions» (https://docs.cline.bot/best-practices/memory-bank). El harness ya tiene el anillo de contexto y, en One-shot, spec.md/progress.md con el prompt de resumen al reabrir; el chat normal no. Propuesta: cuando el anillo pasa un umbral (85 %), un aviso «El contexto se está llenando · Nueva sesión con resumen»: el harness pide al agente un traspaso corto (qué se hizo, qué falta, archivos tocados) y abre una sesión nueva con ese texto en el primer prompt; el mismo traspaso se guarda en .godot_agent/handoff.md y lo lee la próxima sesión del proyecto. Comando /handoff para hacerlo a mano.

**Decisiones:**
- ! Los traspasos se guardan en .godot_agent/handoffs/<fecha>-<sesión>.md, uno por traspaso, en lugar de un único handoff.md. La sesión vacía ofrece el más reciente, con «Ver otros» si hay más. El bloque de @session y la parte del traspaso que sale del historial van en un sobre no confiable (UntrustedText), marcados como contexto y no como instrucciones. · sin revisar
  Por qué: Lo pidió agent-harness-81 al aprobar el plan. Con varias sesiones haciendo traspasos, un solo archivo se pisa. El último mensaje de otra sesión puede traer texto del juego o de una página.
  Descartado: Un handoff.md único (se pisan); el bloque como texto plano.
- ! El borrador se divide en dos: en el composer, editable, va el objetivo y el resumen del agente; los hechos del historial (SessionDigest: pedidos, último plan, archivos de las tool calls) van como chip de contexto «Traspaso: título» en un sobre UntrustedText y se ven en el chat como adjunto «@handoff · título». · sin revisar
  Por qué: El usuario revisa el resumen antes de mandarlo, así que pasa a ser su mensaje. Los hechos salen del historial y tienen que ir marcados como contexto; con los marcadores del sobre metidos en el texto editable, el usuario podría romperlos sin darse cuenta.
  Descartado: Todo en el composer con el sobre en el texto. El resumen del agente también en sobre.
- ! Sin campo chico para el objetivo: el aviso, el «+» del dock, el clic en el porcentaje y el aviso de compactación piden el traspaso directamente. El objetivo opcional se escribe con /handoff &lt;objetivo&gt;. Los hechos del harness salen del historial (SessionDigest), no de TurnSnapshots/PlanStore. El porcentaje sigue en amarillo desde el 80 % (METER_SHOW_RATIO, como antes) y el aviso aparece al 85 %. · sin revisar
  Por qué: Un clic menos en el caso común. El borrador es editable, así que el objetivo se puede agregar ahí. El historial existe para cualquier agente y para sesiones sin git, y reusa lo de @session.
  Descartado: Un diálogo con el objetivo antes de pedir el resumen. Archivos cambiados según los snapshots de git.
- ! La pestaña nueva del traspaso arranca la sesión enseguida, con el perfil que corre en la pestaña de origen (cuenta incluida, aunque no esté guardado en Ajustes) y su modo (salvo One-shot). Si el origen es una copia (worktree), la nueva abre en el proyecto del editor. «Nueva sesión con resumen de esta» va en el «+» del encabezado del dock, no en el «+» de la barra de pestañas. · sin revisar
  Por qué: Queda lista para mandar el borrador. Antes se elegía el perfil por id, y con uno no guardado (el agente falso del check) arrancaba Claude Code de verdad. El «+» del dock ya tiene las opciones de sesión y pestaña.
  Descartado: Pestaña sin arrancar hasta mandar. Heredar la copia. Agregarlo también al «+» de pestañas.

**Prueba:** Headless: tests/run_all.gd -- handoff (test_handoff: prompt, borrador con y sin agente, sobre, nombres de archivo sin pisarse, guardar/listar el más nuevo primero, ContextWatch 85/60/✕/reset, detección de compactación, /handoff y el adjunto «@handoff · título»). Editor: tests/suite.sh run ui-handoff godot (agente falso: uso al 90 % → franja; tool call «Compact conversation» → aviso con acción; «Nueva sesión con resumen» → prompt etiquetado, pestaña nueva elegida, mismo agente y modo, resumen en el composer sin mandar, chip con los hechos en sobre, archivo en .godot_agent/handoffs; pestaña vacía ofrece el traspaso). Suite ci entera PASS (4.7.2).

**Notas:** Hecho en sm/m11-35 (653f149 @session de m11-29; 0608d63 el traspaso). session/handoff.gd (prompt, build, save/list/parse), session/context_watch.gd, agent_dock (franja, aviso de compactación, oferta en la vista vacía, /handoff, chip CHIP_HANDOFF, request_handoff → handoff_ready), agent_plugin._open_handoff, composer (/handoff en el menú de / con sesión, clic en el porcentaje alto). Ver decisiones de la tarea (borrador partido en composer + chip; sin campo de objetivo; perfil que corre; «+» del dock).
Arreglos de tests en el camino: handoff_check espera al escritor del historial (el editor abortaba con 134 al salir, ya en el hito 1); sessions_check suelta el foco de un TextEdit antes de probar seguir (si el editor reabre un script, el Script Editor queda con foco y seguir espera 15 s); dev plugin _finish espera GitCheckpoints.pending().
Queda en m11-60: anunciar session.compaction y manejar compaction_update (is_compaction ya lo reconoce). Agentes sin usage_update (Antigravity) solo tienen la acción manual.

**Relacionadas:** Mencionar otra sesión y seguir en una nueva con un traspaso

### Memorias visibles y gestionables, y «/recordar» desde el chat (como Windsurf) · Revisión

**Prioridad:** media · **Tamaño:** M · **Etiquetas:** `idea`

Idea de la investigación de UX (2026-11-10). Windsurf/Devin: dos mecanismos de contexto persistente, «Memories, which can be automatically generated by Cascade, and rules, which are manually defined by the user»; las memorias se pueden pedir («create a memory of …») y se administran en un panel (Settings › Manage Memories), y las reglas tienen modos de activación always_on / glob / model_decision / manual (https://docs.devin.ai/desktop/cascade/memories, antes docs.windsurf.com/windsurf/cascade/memories). El harness ya guarda memoria de los playtests (notas, scripts, «no es un bug») y hechos del proyecto en CLAUDE.md/AGENTS.md, pero nada lo muestra junto ni se puede borrar una memoria suelta. Propuesta: pestaña «Memoria» en Extensiones con lo que el harness recuerda del proyecto (memoria de playtests, marcas «no es un bug», hechos generados), cada entrada con editar/borrar; y el comando /recordar «…» en el composer, que agrega una línea a la sección del harness en el archivo de instrucciones del agente activo. Reglas por glob (p. ej. solo al tocar *.tscn o shaders) como skills con frontmatter glob, a evaluar.

**Decisiones:**
- ! De las memorias propias de los agentes solo se leen las de Claude Code (solo los .md de projects/<ruta>/memory, al mostrar la pestaña Memoria). El ~/.gemini/GEMINI.md de Antigravity queda afuera, aunque el plan lo mostraba solo para leer: para otros agentes la pestaña dice que no se puede leer. Al mandar una memoria de Claude a la papelera, también se saca su renglón de MEMORY.md (escritura atómica). /remember sale siempre en el menú de /, y su nota para la sesión en curso va en sobre aunque la escribió el usuario. · sin revisar
  Por qué: Por la condición de privacidad de agent-harness-81: leer lo menos posible de las carpetas de config, y el GEMINI.md global no es del proyecto ni está verificado cómo lo usa Antigravity. Sin sacar el renglón, MEMORY.md queda apuntando a un archivo que ya no está. El sobre lo pidió el coordinador.
  Descartado: Mostrar GEMINI.md solo para leer. Dejar MEMORY.md como está. Nota sin sobre.

**Prueba:** Headless: tests/run_all.gd -- project_memory (sección marcada: merge sin tocar el resto, quitarla sin renglones de más, remember/forget/replace sin duplicar; ruta de Claude por cuenta y slug; listar solo memory/*.md con el índice primero; papelera solo dentro de la carpeta y sin el índice, y el renglón sale de MEMORY.md; notas/«no es un bug»/scripts sueltos; /remember y /recordar; la nota en sobre; la pestaña: editar, borrar, confirmar antes de la papelera, sin leer la carpeta de Claude con otro agente). Editor: tests/suite.sh run ui-memory godot (agente falso: /recordar → AGENTS.md con aviso, no va al agente, el próximo prompt lleva la nota en sobre, Deshacer, «Ver memoria» abre la pestaña Memoria con el recuerdo y lo borra; deja el archivo como estaba). Suite ci PASS (4.7.2).

**Notas:** Hecho en sm/m11-36 (566af65, desde origin/sm/next4). core/project_memory.gd (sección «Remembered by the harness» entre marcas; memorias de Claude Code: config dir de la cuenta, slug, listar, papelera); ui/extensions/memory_tab.gd (pestaña MEMORY, la 8.ª; se refresca solo a la vista); PlaytestMemory set_notes/unmark_not_a_bug/scripts/remove_script; dock /remember + /recordar (aviso con Deshacer y Ver memoria → plugin abre Extensions en Memory), SessionController.drop_note_for_agent; composer con /remember en el menú de /. PRIVACY.md/.es.md, wiki Settings (en/es) y CHANGELOG.
Condiciones de agent-harness-81: solo memory/*.md de la carpeta de config y solo al abrir la pestaña; borrar → OS.move_to_trash con confirmación; texto que llega al agente en sobre; /remember es el comando y /recordar el alias. El plan anterior queda abajo como referencia.

PLAN ORIGINAL
1. Dónde viven: .godot_agent/playtests, handoffs, plans; CLAUDE.md/AGENTS.md/GEMINI.md; memorias de Claude Code en <config>/projects/<ruta>/memory (ACP no las expone; claude-agent-acp 0.106 solo manda tool calls memory_recall).
2. Qué edita: lo suyo libre; en instrucciones solo la sección marcada; memorias del agente: leer y borrar.
3. UI: pestaña Memoria y /remember.
4. Reglas por glob: afuera (ya están en .claude/rules y .cursor/rules desde Instructions).

**Relacionadas:** Instrucciones que se cargan según el archivo (reglas por ruta o tipo)

### Señalar con un clic en la captura del juego: el nodo bajo el cursor como @mención (como Send element de Windsurf) · Revisión

**Prioridad:** media · **Tamaño:** M · **Etiquetas:** `idea`

Idea de la investigación de UX (2026-11-10). Windsurf/Devin Previews: «click on the "Send element" button on the bottom right and then proceed to select the element you want to send. The selected element will be inserted into your current agent prompt as an @ mention», también para errores de consola (https://docs.devin.ai/desktop/previews, antes docs.windsurf.com/windsurf/previews). El harness ya muestra el juego corriendo en el chat (capturas de run_scene y capture_game_frame) y tiene @menciones de nodos; falta unir las dos cosas. Propuesta: un clic sobre una captura del juego (o un botón «Señalar» en la tarjeta) pide al probe de playtest el nodo visible en esa posición (CanvasItem/Control bajo el punto, o el Node3D por raycast) y escribe «@Path/Del/Nodo» en el composer con la captura y las coordenadas; igual en el viewport del editor con el nodo seleccionado (ya existe arrastrar desde el Scene Tree). Diferencial frente a todos los harness: señalar algo en el juego en marcha.

**Decisiones:**
- ! Alcance mínimo: «Señalar en el juego…» en el menú «+ contexto» del composer (con el juego corriendo con el probe). Abre la captura en vivo en el ImageViewer en modo señalar (clic sin arrastre → punto en [0,1]); el probe contesta con el op nuevo «point» (PointPick: Control visible que contiene el punto salvo que cubra ≥90 % de la pantalla; después mundo 2D por física (intersect_point) y, si no, Sprite2D/AnimatedSprite2D/Polygon2D/TileMapLayer por sus rects; después 3D por raycast de la cámara activa, solo con colisión; al final el Control de fondo). El dock escribe «@ruta » (relativa a la escena en marcha) en el caret y adjunta la captura con un círculo en el punto. Sin clic sobre las capturas viejas del chat ni sobre el viewport del editor (m11-54). · sin revisar
  Por qué: Lo útil es señalar lo que se ve ahora; una captura vieja del chat puede no coincidir con el juego en marcha, y el viewport del editor ya tiene el arrastre del Scene Tree. La captura marcada le da al agente el contexto visual además de la ruta. MeshInstance3D sin colisión no se resuelve (haría falta un raycast por triángulos): se documenta.
  Descartado: Clic directo sobre las miniaturas del chat (ambiguo cuando el juego cambió); una tool MCP para el agente (no la necesita: ya tiene game_find y game_ui); picking de MeshInstance3D sin colisión (caro para el mínimo).

**Prueba:** run_all 547 tests 0 fallos (test_point_pick: botón bajo el punto, botón oculto no se señala, el fondo a pantalla completa no tapa un Sprite2D, Polygon2D por su polígono, vacío → fondo, con Camera2D el centro es el sprite). acp_session_check 203/0. En Xvfb, run-test 0 fallas con los checks nuevos sobre playtest_game: point_at en el botón Start del HUD → HUD/Menu/Start (control), en el 92 % de alto del centro → Floor (3d, raycast), en el cielo → «Nothing under that point»; y el camino del dock: _on_game_point_picked deja «@HUD/Menu/Start » en el composer y adjunta la captura marcada (círculo con punto central). Una corrida con acp_session_check en paralelo falló en un check viejo de game_script (soltar ui_right tras un timeout): repetida sola, verde.

**Notas:** Rama sm/m11-37 desde sm/next2 (322ebb2), commit ver git log (m11-37). playtest/runtime/point_pick.gd (lado del juego, sin EditorInterface): Control visible que contiene el punto (último en orden de dibujo, salvo fondos ≥ 90 % del viewport) → 2D por intersect_point y, si no, Sprite2D/AnimatedSprite2D/Polygon2D/TileMapLayer por sus rects con get_global_transform_with_canvas → 3D por intersect_ray desde la cámara activa → el fondo. Probe: op «point» {u, v}. RunTools.point_at(uv). ImageViewer.pick(image, title, near, on_pick): modo señalar (cursor cruz, clic sin arrastre → uv, Cancelar). Composer.insert_mention(path). AgentDock: ADD_CONTEXT_POINT «Señalar en el juego…» (deshabilitado sin juego), _point_in_game/_on_game_point_picked, mark_point (círculo del acento). plugin: dock.game_point = _point_game_for_dock (pide el probe como la captura). es.po y CHANGELOG Added. Fuera de alcance (documentado en la decisión): clic sobre capturas viejas del chat, viewport del editor (m11-54), MeshInstance3D sin colisión.

**Relacionadas:** «Preguntar al agente» desde el menú contextual del editor

### Modelo por modo del harness (sticky), como Plan/Act de Cline y los modos de Roo · Revisión

**Prioridad:** baja · **Tamaño:** S · **Etiquetas:** `idea`

Idea de la investigación de UX (2026-11-10). Cline: «Enable "Use different models for Plan and Act"… switching modes automatically switches to that mode's model» y recomienda un modelo de razonamiento para planear y uno rápido para implementar (https://docs.cline.bot/core-workflows/plan-and-act). Roo: cada modo tiene «Sticky Models», recuerda el último modelo usado con ese modo y vuelve a él al cambiar (https://roocodeinc.github.io/Roo-Code/features/custom-modes). El harness tiene Preguntar/Revisar/Construir/One-shot/Auto y un selector de modelo por sesión, pero cambiar de modo no cambia el modelo. Propuesta: recordar el modelo elegido por modo y por agente (ajuste del proyecto): al pasar a Preguntar o Revisar se elige el que se usó la última vez ahí (p. ej. Opus) y al volver a Construir el rápido; un aviso de una línea la primera vez («Construir usa Sonnet · cambiar»).

**Decisiones:**
- ! El modelo por modo es un ajuste del usuario por perfil de agente (agents/models_by_mode), no del proyecto · sin revisar
  Por qué: Los modelos dependen de la cuenta y del plan de cada uno: un proyecto compartido no puede imponer modelos que tu cuenta quizás no tiene. Aprobado por el coordinador. One-shot es un modo más de la tabla.
  Descartado: project_config.tres (lo que decía la tarea); un modelo para el evaluador y otro para el constructor de One-shot (queda para después)

**Prueba:** - Unit: tests/unit/test_mode_models.gd (7 tests). Cubren la tienda (por perfil y por modo, One-shot incluido, olvidar), la opción por category o id, que el modelo sale antes que el modo, que elegir recuerda y el cambio automático no, el aviso una vez, el valor que ya no está, el agente sin la opción y «Aprobar y construir» sin set_mode. test_settings_dialog.test_mode_models cubre las filas, «Olvidar» y el hint.
- Editor (Xvfb): check plan con la configOption model en plan_mode.json y una tienda en memoria. Al abrir en Construir pide Sonnet, con el aviso y «Change», que abre el selector. Preguntar pide Opus antes del set_mode plan y lo dice el tooltip. «Aprobar y construir» pide Sonnet en medio del turno. Elegir Haiku en el selector queda recordado.
- Probe ACP contra claude-agent-acp 0.106: el modelo cambia en medio de un turno.
- Hallazgo en 4.8-beta2: con el selector visible, cambiar de modo dejaba _fit_row del composer alternando entre los niveles 0 y 6 sin fin (el ancho se mide antes de que la fila se reacomode). La cola de mensajes se llenaba y el editor se caía. Arreglado en 046f195: no se deshace el último cambio de compactación dentro de 250 ms. plan, remote y ui-basic pasan en 4.7.2 y 4.8-beta2.
- tests/suite.sh ci: 19/19 PASS en 4.7.2. CI 43122914975 en verde (4.7.2 y 4.8-beta2).

**Notas:** Absorbe m11-27 (architect/editor de Aider: planear con un modelo y construir con otro; acá sale de recordar el modelo por modo, sin dos pedidos por cambio). Relacionada con m11-39: un modo personalizado lleva su modelo, que usa este mismo mecanismo.

CÓMO QUEDÓ (sm/m11-27: 6f3f82c núcleo, af9dc60 check de editor). Plan aprobado: ajuste del usuario por perfil (decisión registrada) y One-shot es un modo más.

ACP
- claude-agent-acp 0.106: el modelo es la configOption {id:"model", category:"model"} y se cambia con session/set_config_option. No tiene session/set_model. ModeModels.model_option busca por category "model" y si no hay, por id "model"; SessionModel.model_option() la usa, y también el dock y _current_model_name.
- Probe ACP contra 0.106 (scratchpad, sin fixture): set_config_option model en medio de un turno → ok, y el prompt siguiente corrió con claude-haiku-5-5. Por eso «Aprobar y construir» pide el modelo de Construir enseguida y no al terminar el turno.

Tienda
- core/mode_models.gd. HarnessSettings agents/models_by_mode = {perfil: {ask|review|build|oneshot|auto: {value, name}}}. name es el nombre que mostraba el agente, para Settings.

Controller
- choose_model(value): lo que el dock manda desde el selector; se aplica y se recuerda para el modo actual y el perfil.
- _sync_mode_model(): pide el recordado si hay uno, el agente lo ofrece y no es el actual. Suma a _mode_syncs_running, así el prompt lo espera igual que a un set_mode.
  - _on_harness_mode_changed lo llama antes de _sync_agent_mode, y también con _skip_mode_sync («Aprobar y construir»).
  - _open_session y _load_session lo esperan antes de READY.
- Un valor que el agente ya no ofrece no se manda: aviso WARNING una vez por pestaña y valor; queda guardado.
- El cambio automático no se recuerda. El aviso «<Modo> uses <Modelo>.» con «Change» (ACTION_CHOOSE_MODEL abre el selector) sale una vez por pestaña; después solo el log.
- model_tooltip(): «Remembered for X…» si el actual es el recordado, si no «The one you pick is remembered for X».

UI
- Composer: set_model_option(option, tooltip) y open_model_selector().
- Settings › Agentes: en el formulario del perfil, «Model by mode» con una fila por modo recordado y «Forget», que se aplica al guardar (_apply_model_forgets). Sin nada recordado, un hint que explica que se elige en el composer.

Cambio respecto del plan: Settings no dice «este agente no deja elegir el modelo», porque sin sesión no se sabe. El hint dice que los agentes sin selector no lo muestran; en el dock, sin la opción no hay selector ni se manda nada.

No se recuerda un /model escrito como prompt (el adapter lo informa con config_option_update): solo cuenta la elección en el selector.

Queda para después (coordinador): modelos distintos para el evaluador y el constructor de One-shot.

**Relacionadas:** Modelo por modo: planificar con uno y construir con otro; Modos personalizados del proyecto: rol, permisos, archivos permitidos e instrucciones (como Roo Code)

### Modos personalizados del proyecto: rol, permisos, archivos permitidos e instrucciones (como Roo Code) · Pendiente

**Prioridad:** media · **Tamaño:** L · **Etiquetas:** `idea`

Idea de la investigación de UX (2026-11-10). Roo Code: modos personalizados globales o del proyecto (.roomodes, YAML) con slug, name, roleDefinition («placed at the start of the system prompt»), whenToUse, customInstructions, groups (read/edit/command/mcp) y fileRegex en edit para «restrict which files the mode can edit», reglas por modo en .roo/rules-{slug}/, exportar/importar en un YAML, y el agente puede proponer cambiar de modo con switch_mode guiado por whenToUse (https://roocodeinc.github.io/Roo-Code/features/custom-modes). El harness tiene cinco modos fijos con la matriz de permisos y las reglas de shell. Propuesta: modos del proyecto en project_config.tres: nombre, modo base (de dónde salen los permisos), instrucciones propias (van al system prompt), patrones de archivos que puede editar (p. ej. solo res://levels/**), modelo, y una línea «cuándo usarlo»; aparecen en el selector de modo del composer y en One-shot. Casos: «Diseño de niveles» (solo escenas de niveles), «Shaders», «Solo tests». Segunda parte: tool godot.request_mode para que el agente proponga el cambio con una tarjeta, como «Arreglar en modo Construir».

**Relacionadas:** Modelo por modo del harness (sticky), como Plan/Act de Cline y los modos de Roo

### Avisar fuera del editor cuando el agente termina o espera (sonido o notificación), y «Steer» para la cola (como Zed) · Revisión

**Prioridad:** baja · **Tamaño:** M · **Etiquetas:** `idea`

Idea de la investigación de UX (2026-11-10). Zed: «If you put Zed in the background after sending a prompt, you can get a desktop notification or a sound when generation finishes» (agent.notify_when_agent_waiting, agent.play_sound_when_agent_done), y los mensajes enviados durante un turno se encolan; «Toggle "Steer" on a queued message to interrupt the Zed Agent at its next step», o «Send Now» para interrumpir ya (https://zed.dev/docs/ai/agent-panel). El harness ya encola con Enter y tiene «Enviar ahora» y toasts dentro del editor (m11-03), pero con el editor en segundo plano un turno largo o una tarjeta de permiso pasan desapercibidos. Propuesta: ajuste «Avisar cuando el editor no tiene el foco»: un sonido corto del editor al terminar el turno o al pedir permiso, y el título de la ventana con «● Agent» mientras espera (Godot no tiene notificaciones nativas del sistema; evaluar notify-send/osascript/PowerShell como opcional). «Steer»: un mensaje en cola marcado para cortar en el próximo tool call (cancel + reenvío con el texto, dejando claro al agente que es una corrección, no un turno nuevo).

**Decisiones:**
- ! Aviso fuera del editor prendido por defecto (ajuste de usuario ui/notify_when_unfocused). Solo con la ventana del editor sin foco, al terminar un turno (no si se canceló) y al esperar un permiso o una respuesta (una vez por espera): DisplayServer.window_request_attention() siempre, más una notificación del sistema con notify-send en Linux (si está en PATH) y osascript en macOS. En Windows solo la atención de la ventana. Sin sonido propio, sin «● Agent» en el título y sin «Steer» en esta tarea. · sin revisar
  Por qué: Solo actúa cuando el editor está en segundo plano, que es justamente cuando un turno largo o una tarjeta de permiso pasan desapercibidos; apagado por defecto nadie lo descubriría. Godot no trae sonidos del editor y agregar un .wav sería un asset nuevo; notify-send suele sonar con el tema del escritorio. Un toast de PowerShell en Windows es frágil (AppID, políticas). El título de la ventana lo maneja el editor y lo pisa. Steer no lo pidió el coordinador: queda para otra tarea.
  Descartado: Apagado por defecto; un sonido propio (.wav en el addon); toast de PowerShell en Windows; marcar el título de la ventana; avisar también con el editor enfocado.

**Prueba:** test_session_tabs::test_notifies_outside_when_unfocused (fin de turno avisa; cancelado no; espera una vez; con foco o ajuste apagado nada; comando de macOS con comillas escapadas, Windows sin comando). suite.sh ci PASS en 4.7.2; CI verde en 4.7.2, 4.8-beta2 y C# (run 43090229553).

**Notas:** sm/m11-40 cc42f95 (desde origin/sm/next4). editor/desktop_notifier.gd (DisplayServer.window_is_focused + window_request_attention; notify-send buscado en PATH una vez; osascript en macOS). Lo llama SessionTabs (turn_finished, permission_requested, elicitation_requested) con notify_outside_enabled = HarnessSettings.notify_when_unfocused. Casilla en Ajustes › avanzado, junto a «Arreglar con el agente»; documentado en Settings en/es y CHANGELOG. Queda afuera: «Steer» de la cola, sonido propio y el título de la ventana (ver decisión 1).

**Relacionadas:** Avisar cuando una sesión en segundo plano necesita al usuario

### Regresiones: mutaciones automáticas para medir si detectan algo · Revisión

**Prioridad:** media · **Tamaño:** M · **Etiquetas:** `idea`, `playtest`

De dónde: Beckett v1.16, op=mutate («puts one fault at a time into a restarted scene»: una propiedad a 0, una conexión de señal cortada) y cuenta cuántas fallas atrapa la suite (https://beckettlabs.itch.io/beckett-godot-mcp/devlog/1695575/beckett-v1160-strict-at-the-door-honest-in-the-answer). Cómo se adapta: hoy m16-09 controla con un sabotaje escrito a mano solo en la suite; el agente no escribe sabotajes. Una acción «Medir regresiones» corre cada regresión guardada contra N mutaciones generadas por el harness sobre los nodos que el script toca (game_set a 0/null/false de propiedades exportadas, desconectar señales, ocultar nodos), una por run, y reporta cuáles no detectó ninguna regresión. Por qué: una regresión que pasa siempre da falsa confianza (la nota de m16-06), y esto lo mide sin pedirle nada al agente. Reusar PlaytestRegressions.detects y regression_cli.

**Decisiones:**
- ! Cada mutante corre todas las regresiones; el guard de guardado devuelve OK sin escribir; un mutante que cuelga el juego cuenta como detectado. · sin revisar
  Por qué: Cortar en la primera regresión que atrapa es más rápido pero deja el «atrapó N» por regresión mal contado. Si el saver devuelve error, ResourceSaver prueba el siguiente saver y el archivo se escribe igual. Un cuelgue es algo que la regresión nota (timeout).
  Descartado: Cortar en la primera regresión (≈2× más rápido); devolver ERR_UNAUTHORIZED; contar los timeouts aparte sin sumar.

**Prueba:** tests/unit/test_mutation.gd (operadores, lo que no se muta, apply, muestra pareja y determinista, scripts de una escena, puntaje, el guard no escribe, aviso), test_review_panel.test_measure_button_requests_a_measurement, tests/regressions_cli_check.sh (--mutate=6 con puntaje y sobrevivientes, --min-score=100 sale 1, hash de .gd/.tscn igual antes y después, un mutante que guarda sale 4 sin dejar archivo). Commit 3353995.

**Notas:** Hecho en 3353995 (sm/m11-41). Mutación en memoria: source_code + reload(true) en el GDScript cacheado, un Godot headless por mutante; SaveGuard intercepta cualquier guardado, no escribe y sale con 4. Cada mutante corre todas las regresiones (no corta en la primera que lo atrapa) para que «atrapó N» por regresión sea exacto. En el fixture: 20 mutantes ≈ 1 min. UI: «Medir regresiones» en el panel de revisión, aviso de progreso con Cancelar que pasa a ser el resultado (puntaje, no detectados con Abrir path:line, por regresión); res://.godot_agent/playtests/mutation.json. CLI: --mutate[=N] --min-score=P. Fase 2 (sabotajes de escena) en m11-62.

### Regresiones: repetir N veces y marcar las inestables · Revisión

**Prioridad:** media · **Tamaño:** S · **Etiquetas:** `idea`, `playtest`

De dónde: Beckett v1.16, op=repeat corre una suite n veces, informa pass^k (true solo si pasaron todas) y ordena los pasos que cambiaron entre corridas (https://beckettlabs.itch.io/beckett-godot-mcp/devlog/1695575/beckett-v1160-strict-at-the-door-honest-in-the-answer). Cómo se adapta: `repeat` en run_regression y en regression_cli (--repeat=N), y al guardar una regresión del agente correrla 3 veces antes de aceptarla; una que alterna pass/fail se marca «inestable» en el panel y no se escribe al workflow de CI sin confirmar. Por qué: una regresión que depende del framerate o del azar rompe el CI del usuario sin bug real; hoy no hay forma de verlo.

**Decisiones:**
- ! No se corre automáticamente 3 veces cada regresión que guarda un playtest del agente; las inestables se detectan al repetir a mano (×N en el panel, godot.run_regressions con repeat) · sin revisar
  Por qué: Correr el juego 3 veces en el editor justo después de cada playtest ocupa el editor (y el juego) del usuario sin que lo pida; el agente puede llamar run_regressions con repeat cuando quiera confirmar que una es estable
  Descartado: Correrla 3 veces antes de aceptarla, como proponía la descripción
- ! Una inestable no hace fallar la corrida del CLI (ni la del workflow) salvo con --fail-on-flaky; una marcada inestable en el editor que falla la única vez que corre también cuenta como inestable. La que falla todas las corridas sí falla · sin revisar
  Por qué: Pedido: que una inestable no rompa el CI salvo que se pida. Con la marca guardada, el CI de una sola corrida no se rompe en cada push por una que ya se sabe inestable
  Descartado: Excluir las inestables del workflow hasta confirmar (como decía la descripción); que fallen siempre
- ! La cuenta (pasó k de N) se guarda en el JSON de la regresión (campo runs) solo con 2 o más corridas; pasar todas en una repetición posterior la desmarca · sin revisar
  Por qué: Con una corrida no se sabe si es inestable; el JSON ya es lo que comparten el panel, la tool, el CLI y el CI
  Descartado: Guardarla en la memoria de playtest o en la config del editor (el CI no la vería)
- ! «Correr regresiones» tiene al lado una casilla ×N (1 a 20, empieza en 1) en lugar de un botón aparte para repetir · sin revisar
  Por qué: Un solo botón y un número; el máximo de 20 evita dejar el editor ocupado por accidente
  Descartado: Botón «Correr ×3»; menú con 3/5/10; un ajuste en Settings
- ! Reemplaza la segunda decisión (revisión de agent-harness-50): con una sola corrida, una marcada inestable que falla se reintenta hasta 3 veces en total; es inestable si pasa alguna y falla si fallan las 3 · sin revisar
  Por qué: Contarla como inestable solo por la marca dejaba tapada para siempre, con el CI por defecto (una corrida), una inestable que se rompió de verdad
  Descartado: Contar la marcada que falla como inestable (la versión de 4c22155); ignorar la marca

**Prueba:** Sobre cd5901d, en 4.7.2: run_all 530/0, con el test nuevo test_regression_repeat: pass^k; inestable con su cuenta; una marcada que falla se reintenta hasta 3 y no queda tapada (retry_marked); resumen con fail_on_flaky y traducido; record_runs marca y desmarca en el JSON; opciones del CLI; workflow con --repeat/--fail-on-flaky; el panel muestra «(2 · 1 flaky)», las nombra en el tooltip y manda el ×N. tests/regressions_cli_check.sh bien: además de los 4 casos de antes, pass con --repeat=3 (passed 3 of 3); flaky (fixture que alterna con Engine meta) da FLAKY 2 de 3 y sale con 0, y con 1 si se agrega --fail-on-flaky; marked (marcada, falla siempre) da FAIL 0 de 3 y sale con 1; recovers (marcada, falla la primera y después pasa) da FLAKY 1 de 2 y sale con 0; --repeat=0 sale con 2. run-test en Xvfb pasa en en y es: desde el panel, ×2 dice «basket is full (pasó 0 de 2)» y guarda en cada JSON 0/2 y 2/2; godot.run_regressions con repeat 2 y goal «START» da «PASS start works (passed 2 of 2)» sin la otra, y el juego queda cerrado. Después de 6d14a4b, una corrida falló una vez en otro check (game_input text en el LineEdit) y pasó en las 2 siguientes: parece inestable y ajeno a esta tarea.

**Notas:** Commits 4c22155 y 6d14a4b en sm/m11-42 (desde cd5901d). PlaytestRegressions: tally (pass^k, inestable, primera salida que falló), is_flaky, retry_marked, record_runs (campo runs {passed, total, at} en el JSON, solo con 2 o más corridas), flaky_count, y summary(results, fail_on_flaky, translate). retry_marked (6d14a4b): con repeat 1, una marcada inestable que falla se reintenta hasta 3 corridas; es inestable si pasa alguna y falla si no. RunTools.run_saved_regressions es el lazo que comparten el panel y la tool nueva godot.run_regressions (repeat de 1 a 20, goal para filtrar). La tool corre de a una: regressions_running reemplaza el flag que tenía el plugin. Con un juego en marcha da error, y entre sesiones pasa por la cola del juego como run_scene. Panel: casilla ×N al lado de «Correr regresiones» y «(N · K inestables)» con las inestables en el tooltip. regression_cli.gd: --repeat=N y --fail-on-flaky; el sabotaje se prueba una vez. RegressionsWorkflow.write/workflow_text aceptan repeat y fail_on_flaky (la tool write_regressions_workflow también). El botón «Workflow de CI…» del panel escribe como antes (sin repetir). Wiki en y es (Review/Revisar, Editor tools/Herramientas del editor) y CHANGELOG › Added. Lo que queda afuera está en las decisiones: no se corre 3 veces al guardar una regresión del agente.

### game_monitors: monitores de Performance y nodos huérfanos del juego · Revisión

**Prioridad:** media · **Tamaño:** S · **Etiquetas:** `idea`, `performance`

De dónde: Roblox Scene Analysis skill (hotspots de render y memoria, instancias sin padre filtradas: https://devforum.roblox.com/t/new-studio-testing-apis-and-assistant-improvements/4657854), performance_audit de flopperam (https://github.com/flopperam/unreal-engine-mcp), toolset Perf del MCP de Unreal 5.8 (https://dev.epicgames.com/documentation/en-us/unreal-engine/unreal-mcp-in-unreal-editor), manage_profiler de MCP for Unity con contadores y memoria (https://coplaydev.github.io/unity-mcp/reference/tools). Cómo se adapta: una tool live game_monitors que lee del probe Performance.get_monitor (fps, frame time, process/physics time, draw calls, objetos, nodos, memoria estática y de video) como muestras durante una ventana (min/media/p95/max) y la cantidad y lista de nodos huérfanos (Node.get_orphan_node_ids en 4.x debug, verificar disponibilidad en 4.7/4.8). Por qué: profile_run solo ve GDScript; un juego lento por draw calls, física o fugas de nodos no aparece ahí.

**Decisiones:**
- ! De TIME_PROCESS y TIME_PHYSICS_PROCESS se informa solo el máximo («el frame más lento de cada segundo»); el tiempo de frame (promedio, p95, máximo) se mide entre frames · sin revisar
  Por qué: Godot actualiza esos dos monitores una vez por segundo con el máximo de ese segundo: un promedio daba 7 ms con frames de 1,8 ms. Medir entre process_frame da el tiempo real de cada frame
  Descartado: Promedio y máximo de los monitores tal cual; TIME_FPS (también un promedio por segundo)
- ! Los huérfanos se listan agrupados por nombre, clase y script (los 20 grupos más grandes, ×N), y el resto de los monitores se muestran como principio → final con la diferencia · sin revisar
  Por qué: Una fuga típica son cientos del mismo nodo (balas, efectos): agrupados se ven en una línea; la diferencia de principio a fin muestra si la cuenta crece
  Descartado: Lista plana por id; solo la cuenta

**Prueba:** En 4.7.2: run_all 526/0, con el test nuevo test_game_monitors: stats con p95; informe de 5 frames con tiempos, conteos de principio a fin y huérfanos agrupados («LeakedBullet (Node) ×5»); sin lista con orphans false; clase y script de un huérfano, que desaparece al liberarlo; formato de las diferencias (+N, -N, MB). Pasa también en 4.8-beta2. run-test en Xvfb (4.7.2 en y es, 4.8-beta2): game_monitors en el juego de playtest da tiempos, conteos y lista «ProbeLeak (Node2D)», un nodo que dejó huérfano un game_script; con orphans false no la lista; run_scene con monitors trae «Performance during the run: Sampled …»; con un juego que termina solo dice que no se pudieron leer. Los checks nuevos pasan siempre. Las corridas que fallaron lo hicieron solo en «game_input text», que también falla en una base sin cambios (m13-30); la última de 4.7.2 en en pasó entera.

**Notas:** Commit 7d93675 en sm/m11-43 (desde cd5901d). Runtime nuevo playtest/runtime/monitors.gd (sin código de editor). Toma una muestra por frame: el tiempo de frame se mide entre process_frame (promedio, p95, máximo); de TIME_PROCESS y TIME_PHYSICS_PROCESS solo el máximo (Godot los actualiza una vez por segundo con el más lento); draw calls, objetos y primitivas dibujados, cuerpos de física despiertos y pares de colisión 2D/3D (promedio y máximo; los que dan 0 no aparecen). Nodos, huérfanos, objetos, recursos y memoria estática y de video van de principio a final con la diferencia; la memoria de video se omite si da 0 (headless). Los huérfanos salen de Node.get_orphan_node_ids() (está en 4.7.2 y 4.8-beta2/3; solo en builds de debug), agrupados por nombre, clase y script, los 20 grupos más grandes. La probe tiene tres operaciones nuevas: monitors (una ventana, con steps opcionales), monitors_start y monitors_stop. La tool godot.game_monitors (seconds hasta 30, orphans, steps) está en GAME_TOOLS: extendida, con la guarda del juego entre sesiones, repetible en el detector de loops y con título en el dock (es: «Medir el rendimiento del juego»). run_scene acepta monitors: true: muestrea toda la corrida y agrega «Performance during the run:»; si el juego terminó o se frenó en el debugger, lo dice. Prompt de sistema: se nombra junto a game_watch/game_frames. Wiki en y es (Editor tools/Herramientas del editor) y CHANGELOG › Added. Encontré que el check «game_input text: escribe en el LineEdit» de run-test es inestable también sin estos cambios (m13-30).

**Bloquea a:** Invariantes por frame y presupuestos de rendimiento en las regresiones

### Invariantes por frame y presupuestos de rendimiento en las regresiones · Revisión

**Prioridad:** baja · **Tamaño:** M · **Etiquetas:** `idea`, `playtest`, `performance`

De dónde: Beckett v1.9 (perf asserts y baselines, p. ej. frame_ms_p95 max 16.7: https://beckettlabs.itch.io/beckett-godot-mcp/devlog/1585432/godot-mcp-beckett-v19-the-ai-measures-your-game-perf-asserts-baselines-and-a-locked-down-channel) y v1.16 (invariantes «checked on every physics frame»: https://beckettlabs.itch.io/beckett-godot-mcp/devlog/1695575/beckett-v1160-strict-at-the-door-honest-in-the-answer). Cómo se adapta: una regresión guardada suma `invariants` (expresiones que el probe evalúa en cada physics frame, fallan con el frame y el valor) y `budgets` (frame_ms p95, draw calls, nodos huérfanos al final) con una línea base que se guarda en el primer run verde y se compara con tolerancia; usa game_monitors. Por qué: las regresiones de hoy solo miden el final del script; un objeto que atraviesa una pared un frame o un juego que se volvió el doble de lento pasan.

**Decisiones:**
- ! La base de los presupuestos va por máquina (runner + procesador) dentro del JSON de la regresión, solo para métricas sin límite escrito, y no se pisa una vez guardada. · sin revisar
  Por qué: Así «2.1× la base de esta máquina» es literal: cada PC o CI compara contra la suya. Con límite escrito no hace falta base y no se ensucia el JSON versionado. No pisarla mantiene la base de cuando andaba bien.
  Descartado: Una sola base compartida (comparaciones entre máquinas distintas); guardar todas las métricas medidas; actualizar la base en cada run verde (la deriva se volvería invisible).
- ! Revisión del coordinador: base de conteo única en el JSON de la regresión; base de tiempo por máquina en user://godot_agent/regression_time_baselines.json («regresión|runner»). Reemplaza la base por máquina en el JSON. · sin revisar
  Por qué: El JSON se versiona: con una base por máquina, cada PC sumaba su entrada (ruido y conflictos en git) y el nombre del procesador quedaba en el repo. Los conteos son deterministas; los tiempos solo avisan, así que perderlos en un CI limpio no importa.
  Descartado: Base por máquina dentro del JSON (lo que había antes).

**Prueba:** tests/unit/test_regression_checks.gd (invariante roto una vez con frame y valor, null cuenta como roto, finish desconecta; judge: límite, mutante, base de tiempo solo avisa con «2.1× this machine's baseline», conteo sobre base falla, base 0, sin base, headless; declaración y línea de medido; passed() con violaciones; record_baselines por máquina sin pisar; kill_reason y «caught 2 (1 by invariants or budgets)»). tests/regressions_cli_check.sh: la regresión del fixture invariants pasa, el mutante « + »→« - » de mover.gd la hace fallar con killed_how invariant, y la base de nodes_max se guarda en el primer run verde y no con --no-baselines. Commit d62bd54.

**Notas:** Hecho en sm/m11-44 (d62bd54 + 475f15d + ff5376c). Con el plan aprobado: un presupuesto de tiempo sin límite solo avisa. Hacen fallar los invariantes, cualquier presupuesto con límite escrito, y los de conteo (nodes_max, orphans_end, draw_calls_max) por encima de su base ×1.25.
Bases, según la revisión:
- Conteo: una sola base compartida, en el campo `baselines` del JSON de la regresión ({métrica: valor}).
- Tiempo: base de esta máquina en user://godot_agent/regression_time_baselines.json, con clave «<archivo>|<runner>» (headless/window). Queda fuera del repo y sin el nombre del procesador.
- Ninguna se pisa.
- A la probe le llegan {counts, times: {runner: {...}}} vía PlaytestRegressions.baselines_for.
La lógica está en playtest/runtime/regression_checks.gd y ScriptKit delega. Bajo --mutant los presupuestos de tiempo avisan y no matan, y la medición pasa --no-baselines. Mutación: killed_how y by_checks. Docs en la descripción de game_script.

**Bloqueada por:** game_monitors: monitores de Performance y nodos huérfanos del juego

### Texto del juego y de archivos en sobres marcados como no confiables · Revisión

**Prioridad:** media · **Tamaño:** S · **Etiquetas:** `idea`, `security`

De dónde: Godot MCP Toolkit (NPGameDev) envuelve lo que devuelve el editor en «per-call nonce-tagged envelopes, which mitigates prompt injection from file contents» (https://github.com/NPGameDev/godot-mcp-toolkit). Cómo se adapta: hoy m15-01 solo pide en el prompt tratar textos y logs del juego como datos. Envolver en <untrusted nonce="…">…</untrusted nonce="…"> (nonce por llamada, que el texto no puede adivinar para cerrar el sobre) lo que viene de afuera del harness: textos de game_ui, game_get de strings, Output del juego, errores con mensajes del usuario, get_resource/scene_tree con strings, @output; y una línea en el prompt de sistema que lo explique. Por qué: un juego o un asset de la Asset Store puede traer texto que le hable al agente; con permisos en Auto eso es un riesgo real. Medir que no rompa el parseo de los prompts de playtest.

**Decisiones:**
- ! Sobres con un marcador por proceso que el registry reemplaza por un nonce nuevo por llamada. Las tools del juego, get_errors y run_scene envuelven las partes que vienen de afuera; scene_tree, get_node, get_resource, animation_get, asset_search, asset_details y addons_list van enteras. class_info/search_api, project_info, list_files, sessions, la salida de build/test_extension y las líneas Detector quedan fuera. · sin revisar
  Por qué: El nonce tiene que ser por llamada, pero las tools arman el texto lejos del registry y pueden correr a la vez: un marcador al azar por proceso, que el texto no puede traer, se resuelve en un solo lugar (call_tool / run_for_user). Además se escapa cualquier «<untrusted» del texto. Envolver resultados enteros en las tools de pura lectura de datos evita tocar cada formateador. En las tools mixtas solo va en sobre lo de afuera, así las indicaciones del harness siguen siendo indicaciones. Las líneas Detector las relee ReviewStore. La documentación de clases es mayormente del motor, y los nombres de archivo o de proyecto tienen poco espacio para inyectar. Los errores del propio script del agente también van en sobre: no se pueden distinguir de los del juego por la fuente, y siguen siendo datos a revisar.
  Descartado: Envolver cada string dentro del JSON (mucho ruido); un nonce global por sesión (adivinable si se filtra); envolver todos los resultados de todas las tools (las instrucciones del harness pasarían a ser datos); agregar también class_info y la salida del compilador nativo.

**Prueba:** Unit tests:
- run_all 4.7.2: 550 tests / 4318 checks, 0 fallos. En una primera corrida test_composer falló de forma intermitente; solo pasa, y la corrida siguiente salió entera en 0.
- untrusted, tool_registry, run_error_watcher y review_store también pasan en 4.8-beta2.

Xvfb 4.7.2: mcp-test, run-test y run-error-test con 0 fallas.

test_untrusted_text (nuevo):
- wrap/seal, con las etiquetas del texto escapadas en mayúsculas y con espacios, y el marcador inalcanzable;
- strip;
- close_cut (sobre cortado, etiqueta a medias);
- el registry pone un nonce nuevo por llamada:
  - ENVELOPE_ALL envuelve todo;
  - PARTS solo lo de afuera;
  - una tool sin sobres y los errores del harness quedan igual;
  - la nota va en la descripción;
  - run_for_user también sella;
- el tope de caracteres cierra el sobre antes del aviso de truncado;
- el aviso de errores nuevos lleva el mensaje en un sobre;
- la auditoría del playtest ignora un «Detector …» y un «Recording:» impresos por el juego.

Tests ajustados:
- test_tool_registry.test_new_errors_in_each_response;
- test_run_error_watcher (el prompt de m11-55 con sobres).

**Notas:** a02b834 en sm/m11-45, sobre sm/next2 322ebb2 como pidió agent-harness-50 (incluye m11-47 y m11-55).

untrusted_text.gd:
- wrap pone un marcador al azar por proceso y desarma «<untrusted»/«</untrusted» del texto (también en mayúsculas o con espacios) y el marcador;
- seal pone el nonce de la llamada: 12 hex de Crypto;
- strip saca el contenido de los sobres;
- close_cut arregla un sobre cortado por max_output_chars.

McpTool.envelope:
- ENVELOPE_PARTS: la tool envuelve lo de afuera;
- ENVELOPE_ALL: el registry envuelve el texto de un resultado bueno;
- las dos suman UntrustedText.NOTE a la descripción.
ToolRegistry.sealed corre en call_tool y en run_for_user (menciones @errors, @game).

Cubierto:
- run_scene: errores y Output del juego, errores salteados con continue_on_error;
- todas las game_* que pasan por _game_request: texto y error del probe, errores del juego;
- get_errors: las líneas;
- el aviso de errores nuevos en cualquier tool: el mensaje;
- enteras: scene_tree, get_node, get_resource, animation_get, asset_search, asset_details, addons_list;
- @output;
- el prompt «Arreglar con el agente» de m11-55 (RunErrorWatcher.prompt).

Explicación al agente en tres lugares:
- la descripción de cada tool con sobres;
- INSTRUCTIONS del server MCP;
- una regla en system_prompt.md. Ojo: es USER_EDITABLE, así que un prompt editado por el usuario no la recibe; los otros dos lugares sí llegan.

Parseo del playtest: ReviewStore.playtest_audit lee las líneas Detector, «Recording:», «Filming:» y «The recording was not written» del texto sin sobres. Antes, el Output del juego podía imitarlas. «not by input» de game_ui_act viene del probe (dentro del sobre), así que se sigue leyendo del texto entero.

Fuera (ver decisión):
- class_info/search_api;
- project_info, list_files, sessions;
- la salida de build/test_extension;
- validate_scripts.

No probé en vivo si Claude Code respeta los sobres (costo de modelo). La defensa es de formato e instrucción y no garantiza nada; la wiki lo dice.

### Tools propias del proyecto en GDScript · Revisión

**Prioridad:** media · **Tamaño:** M · **Etiquetas:** `idea`, `mcp`

De dónde: NPGameDev («register your own tools in GDScript», con hot reload: https://github.com/NPGameDev/godot-mcp-toolkit); Toolset Registry del MCP de Unreal 5.8 con clases Python o C++ (https://dev.epicgames.com/documentation/en-us/unreal-engine/unreal-mcp-in-unreal-editor); Custom tools del Assistant de Unity (https://docs.unity3d.com/Packages/com.unity.ai.assistant@2.21/manual/integration/integration-landing.html); execute_custom_tool de MCP for Unity (https://coplaydev.github.io/unity-mcp/reference/tools). Cómo se adapta: scripts @tool en res://.godot_agent/tools/ (o una carpeta configurable) que extienden una clase base con name, description, schema y run(args); el registry los carga como métodos extendidos (godot.methods/godot.run) con su propio grupo de permisos que pregunta siempre, y los recarga al cambiar el archivo. Por qué: cada juego tiene operaciones propias (armar un nivel, poblar una tabla de items) que hoy el agente hace en muchas llamadas o a mano.

**Decisiones:**
- ! Los hooks de tool (m11-24) pueden correr tools del proyecto: project_tools se suma a ProjectHooks.TOOL_GROUPS · sin revisar
  Por qué: El coordinador pidió que una tool aprobada se pueda llamar desde un hook. El hook está aprobado por máquina con su definición entera y la tool con su código; un hook de comando ya corre cualquier programa, así que no es una escalada. Sin aprobar el código, la tool no está registrada y el hook falla con «There is no tool». run_for_user ahora valida los args contra el schema y tool_group sincroniza las tools del proyecto.
  Descartado: Dejar project_tools fuera de los hooks (solo read/diagnostics/run); pedir el permiso Project tools en cada corrida del hook (no hay tarjeta sin turno)

**Prueba:** - Unit: tests/unit/test_agent_tools.gd (8 tests) y test_export_presets_patcher.test_project_tools_filter. Cubren que una tool sin aprobar no se carga (un static que dejaría una marca), que la clave sigue al código y a los helpers, las tools rotas con su error, el registro (godot.methods / godot.run / catálogo / tools/list), la recarga de helpers y el grupo project_tools.
- Editor (Xvfb): el check «checks», paso 6 de turn_checks_check. El agente falso escribe tests/tmp/agent_tools/echo_probe.gd; la tool sale frenada en el aviso y en el catálogo y godot.run no la conoce. «Aprobar…» muestra el código; aprobada, godot.run la corre con el permiso de project_tools. Editada, vuelve a quedar frenada y avisa de nuevo.
- Hooks (m11-24): paso 6 de hooks_check. Un hook de tool que nombra una tool del proyecto sin aprobar falla con «There is no tool» y no corre; con el código aprobado, el hook la corre con sus args.
- Export: export_check pone una tool con un helper en todos los escenarios y suma uno con project_tools_dir="tools/agent".
- Con next4 mergeado (00e88bc): tests/suite.sh ci 19/19 PASS en 4.7.2 y CI 43116310115 en verde (4.7.2 y 4.8-beta2).

**Notas:** CÓMO QUEDÓ (sm/m11-46: d46fa2d núcleo, bc24dad resto). Plan aprobado por el coordinador, con estas respuestas: carpeta res://agent_tools/ configurable en Settings → MCP → Advanced, grupo propio project_tools que pregunta también en Auto, y el export obligatorio.

Declaración
- Cada <carpeta>/<nombre>.gd es godot.<nombre>. La carpeta sale de project_tools_dir; ProjectToolLoader.normalize_dir no deja usar la raíz, "..", carpetas con punto ni addons/godot_agent.
- Los archivos con _ adelante y las subcarpetas son helpers.
- La base es api/agent_tool.gd: _description(), _parameters() (JSON schema) y _run(args, ctx). ctx es api/agent_tool_context.gd (undo_redo, project_dir, note()); el método se llama note y no log porque log() es una función global.
- Se rechaza una tool sin @tool, con class_name, que no extiende la base, con la descripción vacía o con un schema mal armado; el error sale en la pestaña Tools.

Aprobación
- MachineApproval, KIND_TOOL. La clave cubre la ruta, el sha256 del texto y el hash de todos los helpers de la carpeta.
- Una tool sin aprobar nunca se carga.
- Las aprobadas se cargan con CACHE_MODE_IGNORE, y los helpers que cambiaron se recargan en la caché con REPLACE. IGNORE_DEEP recompilaba la base del addon en cada carga.
- El handler es un método de ToolRunner, que guarda la entrada, en vez de un lambda. Con el lambda, una tool recargada dejaba el contexto vivo al salir.
- El aviso lo da SessionController.held_tools_notice: al empezar la sesión, con filesystem_changed y con la señal changed del loader (cuando una llamada encuentra algo nuevo). Cada tool frenada se avisa una vez por clave.
- El diálogo muestra el código en un TextEdit "Code".

Registro
- registry.project_tools: sync_project_tools() corre antes de godot.methods, godot.run, catalog y list.
- Las tools del proyecto nunca van en tools/list. methods y run van en tools/list también con la lista no compacta si hay tools del proyecto.
- godot.methods las marca con [project tool].
- El catálogo trae también las frenadas y las que tienen error. La pestaña Tools muestra «Project tools» y el botón "AllowTool", que abre dock.confirm_on_machine.

Export
- agent_export_plugin hace skip de la carpeta que dice la config.
- ExportPresetsPatcher.wanted_filters suma "<carpeta>/*" cuando la carpeta existe; el banner y «Add to the presets» la incluyen.

Prompt
- system_prompt.md tiene una línea con la variable {project_tools_dir}.

Hallazgos
- test_project_tools.gd ya existía (tests de project_tools.gd, m4-09): los tests nuevos van en test_agent_tools.gd.
- Falsa fuga de un contexto en run_all, en más o menos la mitad de las corridas por la suite: el test seguía corriendo dentro de la emisión de process_frame que reanudó la tool. Se arregla con un frame más en el test después de la llamada.
- El SCRIPT ERROR de agent_process.gd:134 al cerrar el check «checks» ya estaba (stop() en PREDELETE al salir); no es de este cambio.

Pendiente con m11-30 (agent-harness-41): core/project_dirs.gd está en sm/m11-30 con las mismas reglas. Cuando estén mergeados los dos, normalize_dir y resolve_dir de ProjectToolLoader pueden delegar ahí.

### Anotaciones MCP (readOnlyHint, destructiveHint) y heartbeats de progreso · Revisión

**Prioridad:** media · **Tamaño:** S · **Etiquetas:** `idea`, `mcp`

De dónde: MCP de Unreal 5.8: cada tool declara AIAccessMode Read/Write/Execute y lo mapea a readOnlyHint «so clients can decide whether to ask for confirmation»; y aconseja mandar progressToken para recibir notifications/progress porque algunos clientes cortan llamadas largas («Claude Code after about 120 seconds») (https://dev.epicgames.com/documentation/en-us/unreal-engine/unreal-mcp-in-unreal-editor). Cómo se adapta: tools/list con annotations (readOnlyHint, destructiveHint, idempotentHint, openWorldHint para asset_*) sacadas de los grupos de permisos que ya existen (no hay ninguna hoy: grep sin resultados); y notifications/progress cada ~10 s si el request trae progressToken en build_extension, test_extension, run_scene largos, profile_run, game_wait y asset_install. Por qué: los clientes que no son el dock (Claude Code por terminal, Cursor) preguntan menos para lecturas y no cortan una compilación larga. Verificar primero si el corte de 120 s aplica al MCP HTTP de Claude Code.

**Decisiones:**
- ! SSE solo para los tools/call que pasan de 2 s, sin lista de tools largas; anotaciones por grupo con overrides en la propia tool · sin revisar
  Por qué: El tiempo decide mejor que una lista (cualquier tool puede esperar una tarjeta de permiso), y lo corto sigue siendo JSON con keep-alive. Las anotaciones salen de GROUP_HINTS por el mismo grupo que decide el permiso; un test exige hints para cada grupo de PermissionPolicy.GROUPS. Los pocos casos que el grupo no describe bien (session_send, asset_*, godot.run) se marcan en la definición de la tool, no en una lista aparte.
  Descartado: SSE en todos los tools/call con progressToken (cierra la conexión en cada llamada); lista fija de tools largas; anotaciones a mano por tool; _meta anthropic/requiresUserInteraction en asset_install (duplicaría la tarjeta del dock).

**Prueba:** run_all 4.7.2: 527 tests / 4161 checks, 0 fallos. mcp_server y tool_registry también en 4.8-beta2. mcp-test en Xvfb 4.7.2: 0 fallas. Tests nuevos: test_mcp_server.test_long_call_streams_progress (SSE con progressToken, progress creciente, respuesta como último evento; sin token comentarios; corta o sin Accept → JSON) y test_progress_event_format; test_tool_registry.test_annotations_from_group (por grupo, overrides de session_send/asset_*/godot.run, todo grupo de PermissionPolicy.GROUPS tiene anotaciones) y test_stdio_shim_prints_sse_events (UTF-8 cortado, CRLF). Real, Claude Code 2.1.321 por HTTP: con un server Python, 75 s en JSON plano → «The operation timed out» y con SSE + progreso → ok; con el McpServer del addon en un Godot headless y una tool de 75 s → «slow ok after 75 s».

**Notas:** 6a877e6 + d56e424 en sm/m11-47 (desde main cd5901d).
Hallazgo: Claude Code manda _meta.progressToken en cada tools/call. A un server HTTP le aplica un timer hasta el primer byte de max(60 s, timeout del server, MCP_TIMEOUT). Nuestro server no mandaba nada hasta terminar, así que fallaba cualquier llamada de más de ~60 s:
- run_scene/profile_run con seconds > 60 (el máximo es 120);
- build/test_extension;
- un validate_scripts de C# largo;
- una descarga de la Asset Store;
- cualquier llamada con la tarjeta de permiso esperando más de un minuto.
Docs: https://code.claude.com/docs/en/mcp (Time limits on MCP tool calls).

Cambio: un tools/call de un cliente que manda Accept text/event-stream Y progressToken, y que pasa de 2 s, se responde como SSE:
- headers enseguida;
- notifications/progress cada 10 s con su token;
- la respuesta como último evento, con Connection: close.
Lo corto, o sin token, sigue en JSON. No hay lista de tools «largas»: lo decide el tiempo.

d56e424, pedido de agent-harness-50: SSE solo con progressToken (antes: comentarios SSE sin token). Sin token no hay progreso que mandar, y así un cliente que anuncia SSE pero lo lee mal no se rompe.

Clientes:
- Antigravity (antigravity-acp 1.4.3, el adapter que instala el harness) verificado en vivo por ACP con mcpServers http y un proxy que registra headers:
  - manda Accept: application/json, text/event-stream y progressToken (sessionId:n);
  - recibió 8 progresos y devolvió «slow ok after 75 s»;
  - usa protocolo 2025-11-25 y antes de initialize manda server/discover (le contestamos -32601 y sigue bien).
- Sin verificar (no instalados): Codex, Gemini CLI, OpenCode.
  - Gemini CLI y OpenCode usan el SDK TS (StreamableHTTPClientTransport lee SSE en la respuesta de un POST; solo manda progressToken si el llamador pasó onprogress).
  - Codex usa rmcp (también lee SSE). Su tool_timeout_sec es de 60 s por defecto, de memoria y sin verificar, y el progreso no lo extiende. Por ACP el harness no puede subirlo, así que un run_scene de más de 60 s en Codex probablemente corte igual.
  - Sin token, estos clientes quedan como antes de m11-47.

Límites que documenté en la wiki:
- El progreso reinicia la ventana de inactividad de 5 min de Claude Code.
- No extiende el límite total (MCP_TOOL_TIMEOUT o el timeout del server; sin configurar es ~28 h), que hay que dejar por encima de 120 s.

Anotaciones:
- McpTool.GROUP_HINTS por grupo de PermissionPolicy:
  - read/diagnostics: solo lectura e idempotentes;
  - escritura: destructiva;
  - run: no destructiva;
  - addons: openWorld.
- `hints` en la propia tool donde el grupo no alcanza:
  - session_send: es grupo read pero manda un mensaje, así que no es readOnly ni idempotente; si lo fuera, Claude Code lo correría en paralelo y lo repetiría al cortarse la conexión;
  - asset_search/asset_details/addons_list: openWorld;
  - godot.run: no es readOnly.
- Un grupo desconocido (other, mcp:) va sin anotaciones, con los defaults prudentes de la spec.
- Claude Code usa readOnlyHint para correr en paralelo y para repetir una vez una llamada cortada; idempotentHint, solo para repetir.
- No usé _meta anthropic/requiresUserInteraction: duplicaría la tarjeta de permiso del dock.

Shim stdio: con SSE escribe cada evento al llegar y renueva su plazo de 600 s con cada chunk.

De paso: el helper _request de test_mcp_server lee código y headers antes del cuerpo (con Connection: close, HTTPClient los pierde).

### Plan editable antes de construir y «Denegar con motivo» · Revisión

**Prioridad:** media · **Tamaño:** M · **Etiquetas:** `idea`, `ui`

De dónde: Roblox Assistant Planning Mode: el plan es un Markdown editable, al guardar le manda al agente el diff de lo que cambió el usuario y nada corre hasta «Build» (https://create.roblox.com/docs/assistant/guide); Plan con botón Build en Bezi (https://discussions.unity.com/t/released-bezi-ai-powered-game-development-assistant-for-unity/1708451) y en Unity AI (https://docs.unity3d.com/Packages/com.unity.ai.assistant@2.11/manual/about/assistant-modes.html); Ludus: una denegación puede llevar un motivo que el agente usa en el siguiente intento (https://docs.ludusengine.com/agent/approvals-safety). Cómo se adapta: (1) la tarjeta de permiso de salir del modo plan (ExitPlanMode de Claude Code; ver qué mandan otros agentes) suma «Editar plan»: el texto queda editable y al confirmar se rechaza el permiso con el diff como feedback para que el agente lo rehaga, o se aprueba tal cual; (2) toda tarjeta de permiso suma «Denegar con motivo…»: rechaza y manda el motivo como mensaje del usuario al terminar el turno. Hoy plan_view.gd es solo lectura y permission_view.gd no tiene motivo. Por qué: corregir un plan hoy es escribir otro prompt describiendo los cambios.

**Notas:** Absorbida por m11-22 (rama sm/m11-22, 2026-11-11): las dos partes están hechas ahí.
(1) La tarjeta del plan de ExitPlanMode tiene «Editar» con contador +N −M; al mandar los cambios se rechaza y el agente recibe el diff y el plan entero (prompt PLAN_EDIT) para rehacerlo. También tiene «Aprobar y construir» y «Seguir planeando…».
(2) Toda tarjeta de permiso tiene «Denegar con motivo…». El motivo sale como prompt del harness (DENY_REASON, línea plegada) y corta el turno apenas el agente recibió el rechazo, porque Claude Code seguía el turno y el motivo no llegaba.
Se cierra con m11-22.

**Relacionadas:** Plan aprobable antes de construir (fuera del One-shot)

### Playtest: cortar al detectar el agente en loop · Revisión

**Prioridad:** baja · **Tamaño:** S · **Etiquetas:** `idea`, `playtest`

De dónde: el Playtest Agent de Roblox corta a los 50 turnos y termina antes si ve varias llamadas idénticas seguidas; veredictos Pass/Fail/Inconclusive/Error; y avisa que puede dar falsos pass (https://devforum.roblox.com/t/studio-beta-studio-assistant-mcp-playtest-agent/4566767). Cómo se adapta: ya hay blocked (m15-02) y tope blando de tiempo (m15-19). Falta el detector: K llamadas godot.* iguales (misma tool y argumentos) seguidas en un playtest o en el evaluador del One-shot → aviso al agente en el resultado de la tool («estás repitiendo la misma llamada») y, a la siguiente, cancelar el turno y dejar el veredicto blocked con el motivo. Por qué: un agente trabado en un menú quema el tope de tiempo entero repitiendo el mismo clic.

**Decisiones:**
- ! «Sin progreso» = el mismo ciclo de 1 a 3 llamadas a tools del juego (misma tool y argumentos) con el mismo resultado: texto del probe sin nonce, reloj ni tiempo restante, más los bytes de la captura. Aviso a la 3.ª vuelta y corte a la 4.ª. El One-shot queda fuera. · sin revisar
  Por qué: El ciclo cubre el patrón real (tecla → captura igual), no solo llamadas idénticas seguidas. Con el resultado en la huella, repetir algo que hace avanzar el juego no se corta: es mejor no cortar que cortar de más. El evaluador del One-shot no corre como turno de playtest, así que no tiene el handler.
  Descartado: Solo K llamadas idénticas sin mirar el resultado (cortaría un agente que avanza apretando la misma tecla). Mirar también el estado del probe aparte (ya va en el texto del resultado). Incluir el evaluador del One-shot.

**Prueba:** Headless: tests/run_all.gd -- test_playtest_loop_guard (la misma llamada con el mismo resultado, con nonce, reloj y tiempo restante distintos: aviso a la 3.ª y corte a la 4.ª; un cambio o una llamada distinta lo resetea; ciclo input → captura igual corta y con la captura cambiando no; el mismo error; reset; veredicto y aviso). Editor: tests/suite.sh run playtest-loop (ci, editor): el agente falso llama de verdad por MCP a run_scene y 5 veces game_input; el 3.er resultado avisa, el 4.º es «Stopped», el turno se cancela, no hay 5.º y el veredicto es «could not test · stopped: the agent kept repeating game_input…» con la evidencia; el «pass» del agente no cuenta.

**Notas:** Hecho en sm/m11-49 (f9b914e).
- mcp/tools/playtest_loop_guard.gd: huella por llamada (tool+args, resultado normalizado + bytes de imagen), ciclos de periodo 1–3, WARN 3 / CUT 4.
- RunTools envuelve las tools game_* y capture_game_frame (LOOP_GUARDED). Solo vigila con LOOP_HANDLER_META puesto. SessionController lo pone en los turnos de playtest; al cortar cancela, y al volver session/prompt manda ReviewStore.loop_playtest al _report_playtest.
- Hallazgo del check: cada resultado del juego trae un nonce nuevo en el sobre y el reloj «[game time…, physics frame…]»; sin normalizarlos nunca hay dos resultados iguales.
- fake_agent: paso «mcp» que llama de verdad al server MCP del harness (HTTP, JSON o SSE).
- Fuera de alcance: el evaluador del One-shot (no corre como turno de playtest).

### run_scene con varias instancias: multijugador y playtests en paralelo · Revisión

**Prioridad:** baja · **Tamaño:** L · **Etiquetas:** `idea`, `playtest`, `multiplayer`

De dónde: StudioTestService de Roblox: un server con hasta 8 clientes, sumar jugadores durante la sesión y forzar desconexiones (https://devforum.roblox.com/t/new-studio-testing-apis-and-assistant-improvements/4657854); el Verification Agent de Aura corre 3 casos de prueba en paralelo (https://www.tryaura.dev/updates/aura-1-0-launches-today). Cómo se adapta: Godot ya lanza varias instancias (Debug → Customize Run Instances) y cada una es una sesión del debugger. run_scene con `instances` (y argumentos por instancia, p. ej. --server/--client), las tools game_* con `instance` para elegir a cuál, y game_disconnect para cortar una. El probe ya distingue sesiones por id (session_started_id de m13-27). Por qué: hoy un juego multijugador no se puede probar con el agente; godot-multiplayer está entre las skills que el agente usa.

**Prueba:** - run_all: 819 tests, 0 fallos. test_game_instances (7 tests, 46 checks) cubre:
  - normalize y el tope de 4, contando las que corren;
  - launch_args: --remote-debug, ventana, headless, los args del juego después de --;
  - el mosaico sin solapes y con otra columna;
  - el entorno de cada instancia;
  - el user:// por instancia;
  - el mapa sesión → instancia (InstanceSessions);
  - el autoload primero.
- Check del editor instances (Xvfb, fixture ENet en tests/fixtures/instances), PASS en 4.7.2 y en 4.8-beta2. Cubre:
  - run_scene con un cliente;
  - el error de la 2 sale como game#2;
  - el server ve al cliente;
  - user:// distinto en cada una;
  - la captura de la 2 es de 640x360;
  - list;
  - stop 2: el server ve la desconexión;
  - add vuelve a conectar;
  - la 3 da error;
  - ningún PID queda vivo y el autoload no queda en project.godot.
- suite.sh ci: 21/21 PASS. El check está en ci.yml (grupo editor).

**Notas:** HECHO (sm/m11-50, 0551a10, desde origin/sm/next4 95bdbdf). Plan aprobado con ajustes del coordinador: tope de 4, game_instance como tool nueva, user dir propio desde la 2, y el autoload nunca queda en project.godot.

Spike (4.7.2 y 4.8-beta2):
- Un proceso con --remote-debug tcp://<remote_host>:<remote_port> entra como sesión nueva del debugger. Su probe dice ready y tiene editor_runtime=true sin args extra.
- El plugin saca el autoload de playtest en session_started. Para cada instancia extra se vuelve a registrar justo antes de lanzarla y se saca en su session_started (instance_event "started"), o si no llega a arrancar.

Diferencias con el plan:
- Sin autoload aparte: el mismo de playtest se registra primero (PlaytestAutoload.register(first) → first_order) y su _init llama a InstanceEnv.apply. Probado: el _init de un autoload del juego ya ve <user>/instances/2.
- Sin stdout por pipe: el Output del editor junta las sesiones. Los errores salen por instancia porque ErrorCollector toma la sesión del orden de las pestañas del debugger, con fuente game#N. run_error_watcher y game_script aceptan "game*".
- game_debug, game_stack y game_breakpoint no suman `instance`: actúan sobre la instancia parada, y los breakpoints van a todas las sesiones del harness (session_started_id sale también para las extra).

Puntos de diseño:
- PlaytestDebugger: las señales sin número (session_started/stopped/breaked/continued, probe_ready) quedan para la instancia 1, y las extra salen por instance_event(n, event). Antes el ready de otra sesión pisaba _probe_session, y su fin habría cortado el run.
- target_instance + _with_instance en run_tools: las llamadas a una instancia van a la vez, y una a otra instancia espera a que terminen las en curso. send(msg, data, instance) explícito para el "paused" de la instancia 1.
- GameInstances: launch con el entorno solo alrededor del lanzamiento (número, dispositivo, gamepads, shared). Los PIDs van a AgentProcess.track_pid. stop_all cuando termina la instancia 1 o con un run_scene nuevo.
- Bug encontrado por el check: RunTools._until no devuelve nada, y `not await _until()` mataba la instancia apenas lanzada.

--- PLAN original ---
(abajo, sin cambios)

Cómo se lanzan N instancias
- La 1 es la de siempre: EditorInterface.play_custom_scene. Sigue con el Stop del editor, el embebido, record, film y monitors.
- Las 2..N las lanza el harness como procesos propios con --remote-debug al server del debugger del editor; cada una es una sesión nueva del debugger.
- Puertos: el debugger no necesita puertos nuevos; los del juego van en los args de cada instancia (OS.get_cmdline_user_args()).
- Descarté «Customize Run Instances» de Godot (debug_options: multiple_instances_enabled, run_instance_count, run_instances_config): el editor lo lee de su diálogo y todas las instancias comparten el entorno.

User dirs aparte
- La 1 usa el de siempre; desde la 2, <user dir>/instances/<n>/ (custom_user_dir en caliente, sin guardar). shared_user_dir:true lo apaga.

Cómo se dirige cada tool
- run_scene suma instances [{args, device?, inputs?, headless?, shared_user_dir?}]. Las game_* y capture_game_frame suman `instance` (por defecto 1); stop_scene corta todas o una; game_instance list|add|stop.
- record, film_fps y monitors: solo la instancia 1.

Ventana o embebido (4.7 y 4.8)
- La 1 hace lo de hoy (GameEmbedding de m11-51). Las 2..N van en su propia ventana, en mosaico con --position/--resolution sobre el área útil de la pantalla.
- Cuando termina la 1 o con Stop, el harness mata las demás; los PIDs entran en AgentProcess.stop_all.

Límite
- Hasta 4 instancias en total. Todo sigue dentro del run de una pestaña.

Fuera de esta tarea
- Playtests en paralelo entre pestañas.
- record/film/monitors por instancia.
- Simular latencia o pérdida de red.

### run_scene con dispositivo simulado: resolución, aspecto, táctil e idioma · Revisión

**Prioridad:** media · **Tamaño:** S · **Etiquetas:** `idea`, `playtest`

De dónde: StudioDeviceSimulatorService de Roblox (resolución, DPI, orientación y perfiles de dispositivo, para revisar layouts con capturas: https://devforum.roblox.com/t/new-studio-testing-apis-and-assistant-improvements/4657854). Cómo se adapta: run_scene con `device` ({size: [w,h], orientation, scale, touch: true, locale}) o presets (phone-portrait 1080x2400, tablet, 4k, steam deck): se pasa por argumentos de línea de comandos y el probe (DisplayServer.window_set_size, emulate_touch_from_mouse, TranslationServer.set_locale), sin tocar project.godot. Así el agente revisa un HUD en varios aspectos con capture_game_frame y game_ui. Por qué: los bugs de UI anclada y de textos traducidos que no entran aparecen recién en otro dispositivo, y hoy cada prueba corre en la ventana del editor.

**Decisiones:**
- ! El dispositivo va al juego por la variable de entorno GODOT_AGENT_DEVICE (JSON), puesta solo alrededor de play_custom_scene, en vez de argumentos de línea de comandos · sin revisar
  Por qué: El juego hereda el entorno del editor (como RealGamepads); los argumentos solo se pueden pasar con editor/run/main_run_args, que es un ajuste del proyecto y se mezcla con los argumentos del usuario. Así no se toca project.godot y el run siguiente no lo hereda
  Descartado: editor/run/main_run_args con «-- --godot-agent-device=…» (ajuste del proyecto, choca con los del usuario); mandarlo por el debugger después de PROBE_READY (la escena ya hizo su _ready con el tamaño y el idioma de siempre)
- ! Con un tamaño pedido, run_scene destilda «Embed Game on Next Play» en el menú de la vista Game para ese lanzamiento y lo vuelve a tildar; el ítem se busca por texto (inglés o traducido con el dominio godot.editor) dentro del nodo GameView · sin revisar
  Por qué: Embebido (lo normal desde 4.4) el tamaño de la ventana lo pone el editor. Leí game_view_plugin.cpp: embed_on_play solo se lee en NOTIFICATION_READY y solo lo cambia ese menú; probé game_embed_mode=-1 (con mark_setting_changed y settings_changed) y el metadato embed_on_play, y ninguno cambia un lanzamiento con el editor abierto. Si el menú no aparece (otra versión), el informe dice que el tamaño no se simuló y cómo apagarlo
  Descartado: Solo avisar que hay que apagar el embebido (el caso por defecto quedaría sin funcionar); cambiar run/window_placement/game_embed_mode (no tiene efecto hasta reabrir el editor); buscar el ítem por id (implícito en un enum, cambia entre versiones)
- ! Presets: phone 1080×2400 y tablet 2048×1536 (con táctil), steam-deck 1280×800, 1080p y 4k; `orientation` da vuelta el tamaño. El táctil es emulate_touch_from_mouse: DisplayServer.is_touchscreen_available() sigue en false y el informe lo dice · sin revisar
  Por qué: Cubren los aspectos de la descripción con pocos nombres; orientación aparte en vez de phone-portrait/phone-landscape. No hay forma de que el juego crea que hay pantalla táctil sin un dispositivo de verdad
  Descartado: Presets por modelo (iPhone 15, Pixel…); phone-portrait y phone-landscape como presets separados

**Prueba:** Rama sm/m11-51 (0ab8433). test_device_sim (presets, orientación, validación, entorno, informe sin traducción). run-test en Xvfb en 4.7.2 y 4.8-beta2: preset desconocido rechazado; device {size 480×800, touch, locale xx} → ventana 480×800, táctil e idioma sin traducción informados, el entorno del editor queda sin GODOT_AGENT_DEVICE, el run siguiente no lo hereda y «Embed Game on Next Play» queda como estaba. run_all 617/4809/0. suite.sh ci en 4.7.2: 13/13 PASS.

**Notas:** DeviceSim (playtest/runtime/device_sim.gd) valida y pasa el dispositivo por el entorno; el probe lo aplica en _ready y lo repite en los primeros frames (en el _ready de un autoload la ventana vuelve al tamaño del proyecto) y contesta el pedido «device». GameEmbedding (playtest/game_embedding.gd) destilda «Embed Game on Next Play» para ese lanzamiento: la vista Game lee el embebido solo al arrancar el editor (game_view_plugin.cpp), así que ni game_embed_mode ni el metadato embed_on_play sirven en caliente. Busca el ítem por texto dentro de GameView: si una versión de Godot lo cambia, el informe lo dice y el tamaño no se simula. Sin probar: dispositivos más grandes que la pantalla (el informe dice el tamaño real que tomó la ventana) y Wayland.

### Capturas desde una cámara elegida y desde varios ángulos · Revisión

**Prioridad:** baja · **Tamaño:** S · **Etiquetas:** `idea`

De dónde: screen_capture del MCP de Roblox Studio con posición de cámara y objetivo opcionales (https://create.roblox.com/docs/studio/mcp.md); CaptureMultiAngleSceneView (4 ángulos) y Capture2DScene (región ortográfica) del Assistant de Unity, según lectura de terceros del código (https://gamedevllm.com/en/unity-mcp-builtin-tools-reference-en/, sin confirmar en la doc oficial). Cómo se adapta: capture_editor_viewport con `look_from`/`look_at`, `angles: 4` o `rect` 2D, renderizando en un SubViewport fuera de pantalla con una cámara temporal (sin mover la del usuario), y lo mismo en el juego con una Camera temporal desde el probe. Por qué: hoy el agente ve la escena 3D solo desde donde quedó la cámara del editor, y para revisar un nivel tiene que pedirle al usuario que la mueva.

**Prueba:** tests/unit/test_camera_views.gd: la órbita mira al centro, a la distancia pedida y desde arriba; el plan desde una cámara elegida con su lente, angles alrededor del centro de lo dibujado, los errores (cámara inexistente, angles fuera de rango, angles con look_from, cantidad de números, mismo punto, angles en 2D) y la vista 2D con look_at y zoom. run_check (_check_camera_views), con un juego 3D real: la cámara del juego ve la caja roja, camera «Side» y look_from/look_at ven la verde, angles 4 da 4 vistas de la roja, la cámara del juego no se movió, y los errores llegan por la tool.

**Notas:** Hecho en sm/m11-52. Solo el lado del juego, como lo pidió agent-harness-81. capture_editor_viewport queda en una tarea aparte.
- playtest/runtime/camera_views.gd: plan() valida y arma las vistas; render() las dibuja en un SubViewport que comparte world_3d o world_2d con el juego. La cámara temporal copia la lente y el entorno de la de referencia.
- La probe tiene un op "views" y run_tools usa request() directo para traer los PNG.
- Las vistas no incluyen las capas de UI del juego, porque son otro viewport.

### Horneado (navmesh, lightmaps, oclusión) y export por preset · Pendiente

**Prioridad:** baja · **Tamaño:** M · **Etiquetas:** `idea`

De dónde: Bezi hornea NavMesh, luces y oclusión y arma builds (https://docs.bezi.com/get-started/changelog); manage_build de MCP for Unity (https://coplaydev.github.io/unity-mcp/reference/tools); export_project y deploy_to_android de Godot MCP Pro (https://godot-mcp.abyo.net/changelog/). Cómo se adapta: tools bake_navigation (NavigationRegion2D/3D.bake_navigation_polygon/mesh), bake_lightmaps (LightmapGI, solo editor), bake_occluders; y export_project que corre en otro proceso `godot --headless --export-debug|--export-release <preset>` con los presets de export_presets.cfg y devuelve errores y tamaño (sin tocar export_presets.cfg; error claro si faltan las plantillas). Hoy no hay nada de esto (grep sin resultados). Por qué: después de editar un nivel con add_nodes la navegación queda vieja y el agente no puede regenerarla; y «¿exporta?» es la última verificación de un One-shot.

### «Preguntar al agente» desde el menú contextual del editor · Revisión

**Prioridad:** baja · **Tamaño:** S · **Etiquetas:** `idea`, `ui`

De dónde: en Unreal 5.7, F1 sobre cualquier elemento de la UI abre el asistente sobre eso (https://www.unrealengine.com/news/unreal-engine-5-7-is-now-available); Ludus toma solo los actores, nodos y assets seleccionados como contexto (https://docs.ludusengine.com/agent/chat-context-attachments); el (+) del Assistant de Unity adjunta GameObjects, assets y mensajes de la Console (https://docs.unity3d.com/Packages/com.unity.ai.assistant@2.21/manual/reference/assistant-interface.html). Cómo se adapta: ya existen las menciones @ y arrastrar nodos al composer (m11-08). Falta el camino inverso: EditorContextMenuPlugin en el árbol de escena, el FileSystem y el viewport 2D/3D con «Preguntar al agente…» y «Arreglar con el agente…» que enfoca el dock y deja @ruta en el composer; y en el panel Errores/Debugger, un error seleccionado con su stack. Por qué: es el gesto que piden quienes vienen de esos editores; hoy hay que escribir la ruta o arrastrar.

**Decisiones:**
- ! Un solo ítem «Preguntar al agente» (sin «Arreglar con el agente…»), en FileSystem, dock Escena y Script Editor solo con selección; sin el viewport 2D (CONTEXT_SLOT_2D_EDITOR) ni el panel de Errores. Archivos y nodos van como @ruta en el caret; la selección de código como bloque ```lenguaje con «@res://x.gd (lines 3-4):», en inglés y cortada a 4000 caracteres. El dock viene al frente y no se manda nada. · sin revisar
  Por qué: Es el alcance que pidió agent-harness-81 (FileSystem, árbol de escena y Script Editor con selección). «Arreglar» sería el mismo texto con otro verbo, que el usuario escribe igual. El viewport 2D tiene slot (no hay uno para el 3D) y queda como seguimiento; Errores ya tiene «Arreglar con el agente» para runs manuales (m11-55). La @mención reusa lo que ya resuelven el composer y el arrastre; el bloque con líneas deja ver y editar lo que va antes de mandarlo.
  Descartado: Dos ítems (Preguntar / Arreglar); adjuntar la selección como chip de contexto oculto; archivos como adjunto (add_context_files) en vez de @mención; sumar el viewport 2D y Errores.

**Prueba:** test_ask_agent_menu (archivos y nodos como @ruta, nodos fuera de la escena no; selección como bloque con líneas, sin contar la línea siguiente si termina en columna 0; corte a 4000; composer inserta en el caret y el bloque en línea nueva). suite.sh ci PASS en 4.7.2 (plugin_cycle registra y saca los menús); CI verde en 4.7.2, 4.8-beta2 y C# (run 43091823746). Sin prueba del clic derecho real en el editor.

**Notas:** sm/m11-54 01db580 (desde origin/sm/next4). editor/ask_agent_menu.gd, una instancia por slot (FILESYSTEM, SCENE_TREE, SCRIPT_EDITOR_CODE; en el código solo aparece con selección). agent_plugin._ask_agent: make_visible(SIDE) + AgentDock.add_to_composer → Composer.insert_at_caret. Seguimiento posible: viewport 2D (CONTEXT_SLOT_2D_EDITOR).

**Relacionadas:** Señalar con un clic en la captura del juego: el nodo bajo el cursor como @mención (como Send element de Windsurf)

### Error en un run manual: «Arreglar con el agente» · Revisión

**Prioridad:** media · **Tamaño:** S · **Etiquetas:** `idea`

De dónde: Watch Mode de Gamedev AI: cuando el juego se cae lee los últimos ~50 bloques del log y propone un arreglo como diff (https://fredarts.github.io/gamedev_ai/core-features/watch-mode.html); Bezi cancela llamadas pendientes y sugiere próximos pasos cuando Unity se cae (https://docs.bezi.com/get-started/changelog). Cómo se adapta: cuando el usuario corre el juego a mano (F5/F6) y para en el debugger por un error de script, o el juego termina con errores, un aviso en el dock con «Arreglar con el agente» que manda a la sesión activa el error, el stack y el Output (lo que ya arman @errors y @output), sin mandar nada solo. Prendido por defecto, apagable en Settings. Hoy no hay nada (grep sin resultados). Por qué: es el momento en que más se necesita al agente y hoy hay que copiar el error a mano.

**Decisiones:**
- ! RunErrorWatcher (editor/run_error_watcher.gd) escucha las señales de la sesión de debug (started/breaked/stopped), cuenta solo errores con source «game» (no warnings ni errores del editor) desde que arrancó el run, avisa una vez por run y nunca para runs lanzados por run_scene (RunTools.harness_run, decidido al arrancar la sesión según venga de LAUNCHING). El aviso es un NOTICE de advertencia en la pestaña activa: título, motivo o primer error en el cuerpo, «Errores y pila» plegado con Copiar, y «Arreglar con el agente» (acción principal) que manda el prompt con dock.send_text y la etiqueta HarnessPrompts.RUN_ERROR. Ajuste por usuario HarnessSettings.KEY_RUN_ERROR_FIX (prendido), casilla en Ajustes › Herramientas del editor. · sin revisar
  Por qué: Los runs del agente ya reciben sus errores en cada resultado de tool: avisar también sería ruido. Solo errores del juego para no disparar por un warning del editor. Un prompt en inglés con etiqueta, como acordó agent-harness-57 (m12-44): el chat lo muestra como del harness, no como escrito por el usuario. La pila se lee 0,5 s después de la pausa porque el panel del debugger se llena después (igual que run_tools).
  Descartado: Mandar el prompt solo (el usuario pidió explícitamente que no); @errors/@output como menciones en el composer (dos pasos más y no muestra el error en el dock); un ajuste por proyecto (es una preferencia de la persona, va en EditorSettings como las actualizaciones); avisar también en runs del agente (ruido).

**Prueba:** run_all 534 tests 0 fallos (test_run_error_watcher: avisa una vez por run con motivo y errores del juego, ignora warnings/errores del editor/ruido del motor, nada en runs del agente ni apagado ni sin errores; textos del aviso y prompt en en/es; test_settings_dialog: casilla y ajuste por defecto; test_harness_prompts: etiqueta traducida). acp_session_check 203/0, oneshot_check 190/0. En Xvfb: --godot-agent-run-error-test en y es 0 fallas (run manual de run_broken.tscn → aviso de advertencia con el archivo en los detalles, «Errores y pila», botón principal; una vez por run; el botón manda a la sesión activa un prompt con harness_label RUN_ERROR que empieza «The user ran the game…»; run_scene del agente no avisa; apagado en Ajustes no avisa), y run-test 0 fallas (RunTools tocado). Captura: /tmp/claude-1000/-home-dannode-Proyectos-Godot-agent-harness--claude-worktrees-m13-17/3619cf30-0f89-4d71-9f7c-62dac5e13c95/scratchpad/m11-55/notice_es.png (y notice_en.png).

**Notas:** Rama sm/m11-55 desde sm/next2 (4895e84), commit 14ed645. Nuevo editor/run_error_watcher.gd (señales de la sesión de debug → error_found una vez por run; summary/notice_title/notice_text/notice_details/prompt estáticos). RunTools.harness_run (STARTED viniendo de LAUNCHING). plugin.gd: _run_errors, _on_game_breaked (lee la pila 0,5 s después), _on_run_error (NOTICE WARNING en la pestaña activa con title, details, details_title y acción fix_run_error), ACTION_FIX_RUN_ERROR → dock.send_text(prompt, HarnessPrompts.RUN_ERROR). ChatEntry.details_title (NoticeView lo usa; por defecto «Last lines of the log»). HarnessSettings.KEY_RUN_ERROR_FIX + offer_fix_on_run_error(); casilla en Ajustes › Herramientas del editor debajo del autoload en runs manuales. Dev: run_error_check.gd y --godot-agent-run-error-test (con --godot-agent-ui-shot), sumado a ci.yml. CHANGELOG Unreleased › Added. No se manda el Output completo: solo los errores del juego (source game) y la pila; el agente puede pedir más con get_errors/@output.

**Relacionadas:** Hooks del proyecto en eventos del editor

### Breakpoints, pila y variables del debugger como tools · Revisión

**Prioridad:** media · **Tamaño:** M · **Etiquetas:** `idea`, `playtest`

De dónde: Godot MCP Toolkit: «Breakpoints, debug state, crash diagnostics, editor console capture» (https://github.com/NPGameDev/godot-mcp-toolkit); Roblox anuncia APIs del debugger para el Assistant, todavía no publicadas (https://devforum.roblox.com/t/new-studio-testing-apis-and-assistant-improvements/4657854). Cómo se adapta: hoy run_scene sabe que el juego paró (BREAKED) pero el agente no ve la pila ni las variables y no puede poner breakpoints. Tools game_breakpoint (set/clear en res://x.gd:línea, por la sesión del debugger: EditorDebuggerSession.set_breakpoint), game_stack (frames con archivo, línea y función, y locales/miembros del frame elegido: mensajes stack_dump y stack_frame_vars del debugger, que ya escucha PlaytestDebugger) y game_continue/step. Respeta m16-05 (los breakpoints del usuario frenan). Por qué: depurar con prints es lo que hace el agente hoy; con la pila y las variables un error raro se entiende en una llamada.

**Decisiones:**
- ! Los breakpoints del agente se liberan cuando la sesión se desconecta (señal disconnected del SessionController), no por sondeo; el token principal ("") cubre a la sesión del dock y a los clientes externos juntos. · sin revisar
  Por qué: Los clientes externos comparten el token principal: un sondeo de "sesión viva" no los distingue y podría sacar breakpoints que un cliente externo sigue usando, o nunca sacarlos.
  Descartado: Sondear sesiones vivas cada N segundos; un token por cliente externo (cambio mayor fuera de alcance); expirar breakpoints por tiempo.
- ! Una pausa en un breakpoint no dispara el aviso «Arreglar con el agente» de los runs manuales; los errores de ese run se avisan al terminar. · sin revisar
  Por qué: Con breakpoints del agente en un run manual el aviso aparecía como si fuera un error; un breakpoint es intencional.
  Descartado: Ignorar solo los breakpoints del agente y avisar en los del usuario; dejarlo como estaba.

**Prueba:** tests/unit/test_debug_tools.gd (7 tests: breakpoints por sesión y los del usuario, reenvío al arrancar, no parado, release_session, stopped_at_any, snapshot de la pila, describe) + test_run_error_watcher (pausa en breakpoint no avisa). Xvfb: tests/run_in_xvfb.sh <godot> --godot-agent-debug-test PASS en 4.7.2 y 4.8-beta2 (run_scene para en el breakpoint y lo dice; game_stack con 3 frames sin addon, locales a/b/total y miembros; frame 1; next para en la línea 22; continue vuelve a parar; clear + continue → PROBE_READY; cerrar la sesión s1 con el juego parado → sigue y su breakpoint se va). run_all 569/4458 0 fallos; mcp-test PASS. Commit 7db6b59 en sm/m11-56.

**Notas:** Tools: game_breakpoint (run), game_stack (read, ENVELOPE_PARTS), game_debug (run, ENVELOPE_PARTS); extendidas en GAME_TOOLS. La pila la arma el probe (debug_stack.gd) dentro del bucle del debugger: RemoteDebugger::debug atiende las captures, y Engine.capture_script_backtraces(true) ve la función que paró debajo de los frames del addon (se filtran). Los locales solo existen con el debugger activo (siempre en runs desde el editor). Breakpoints del agente: «path:line» → caller ("" = token principal, compartido con clientes externos); se mandan a las sesiones activas y se reenvían en session_started. No se sacan los del usuario (ScriptEditor.get_breakpoints); sacar uno del agente en una línea donde el usuario tiene otro no lo apaga en el juego. Liberación por evento: controller.disconnected → plugin._on_agent_disconnected → release_session(caller), que espera hasta 30 frames a que el panel escriba el motivo (llega unos frames tarde) y continúa si el juego paró en un breakpoint de esa sesión o tras un paso suyo. BREAKED → PROBE_READY con session.continued. Extra: run_scene dice «stopped at a breakpoint» (antes «because of an error»); RunErrorWatcher ignora pausas en breakpoints; describe() ya no falla con objetos liberados; bug encontrado en test: clear no verificaba dueño. Check nuevo --godot-agent-debug-test agregado al CI.

### Diff por nodos de las escenas en los cambios del turno · Revisión

**Prioridad:** baja · **Tamaño:** M · **Etiquetas:** `idea`, `ui`

De dónde: Godot MCP Toolkit lista «diff scenes» entre sus tools, sin detalle de cómo (https://github.com/NPGameDev/godot-mcp-toolkit); Bezi muestra diffs lado a lado y un cajón de cambios pendientes y aceptados (https://docs.bezi.com/get-started/changelog). Cómo se adapta: en el diálogo de cambios del turno (m11-02) un .tscn hoy se ve como diff de texto (ids de ext_resource, unique_id, orden). Un diff semántico: nodos agregados, quitados, movidos o renombrados y propiedades cambiadas (valor antes → después), armado comparando los dos SceneState (PackedScene del snapshot y el actual); el diff de texto queda como «ver crudo». También como tool scene_diff para el agente y el evaluador. Por qué: el cambio más común del agente es en escenas y es el que menos se puede revisar hoy.

**Decisiones:**
- ! El diff sale del texto de los dos .tscn, con un parser propio (core/scene_diff.gd), y no de los SceneState de dos PackedScene cargados · sin revisar
  Por qué: Lo pidió el coordinador: parseado y sin depender de git. Además, cargar la escena de antes implica escribirla a un archivo temporal y que el loader resuelva sus recursos, que pueden ya no existir o estar renombrados; el parser no carga nada y anda headless y con escenas rotas. Los valores se muestran como están en el archivo.
  Descartado: Comparar los SceneState de los dos PackedScene, como proponía la descripción de la tarea
- ! Los nodos se emparejan por unique_id (4.6+); sin él, por ruta, y si no, por nombre y tipo cuando es único. Los ExtResource se comparan por su ruta y los SubResource por su contenido, abiertos como prop.sub hasta 2 niveles · sin revisar
  Por qué: Así un movido o renombrado no aparece como borrado más agregado, y los ids que Godot renumera al guardar no salen como cambios. Se probó con las 41 escenas del repo, cada una contra sí misma y contra una versión con los ids renumerados: 0 cambios en todas.
  Descartado: Emparejar solo por ruta; comparar los SubResource por id
- ! La vista por nodos la elige DiffDialog solo, cuando los dos textos son escenas, con «Ver crudo» para el diff de texto; así vale también para el One-shot y los conflictos. Por ahora no hay tool scene_diff para el agente · sin revisar
  Por qué: Un solo lugar y sin tocar a los que llaman. Para acotar: 200 líneas como máximo, valores cortados a 100 caracteres, un subárbol agregado o borrado en una sola línea con cuántos nodos tiene abajo, y el diff crudo armado recién al pedirlo. Con 5 MB y 5000 nodos, unos 0,3 s. La tool para el agente y el evaluador no la pidió el coordinador: queda como seguimiento.
  Descartado: Vista por nodos solo en Cambios del turno; agregar la tool godot.scene_diff ahora

**Prueba:** - tests/unit/test_scene_diff.gd (9 tests, 35 checks):
  - parseo de valores multilínea;
  - nodos agregados y borrados con su subárbol;
  - movidos y renombrados;
  - ids renumerados no cuentan como cambios;
  - escenas sin unique_id;
  - escena nueva y escena borrada;
  - raíz renombrada e instancias;
  - SubResource anidados;
  - el texto que se muestra y su cota.
- edit-test: la escena que guarda el editor después de las tools se ve por nodos, «Ver crudo» va y vuelve, y un script sigue mostrándose como texto.
- Las 41 escenas del repo, comparadas contra sí mismas y contra una versión con los ids renumerados, dan 0 cambios.
- Escena sintética de 5 MB y 5000 nodos: unos 0,3 s.
- suite.sh ci 15/15 en 4.7.2, sobre next3 435856f.

**Notas:** Rama sm/m11-57, commit f8b3205, rebasada sobre origin/sm/next3 435856f.
- Código nuevo en core/scene_diff.gd. diff_dialog.gd tiene scene_bbcode y el botón «Ver crudo».
- La vista por nodos se elige sola cuando los dos textos son .tscn, o cuando uno está vacío porque el archivo es nuevo o se borró. Por eso también se aplica a los diffs del One-shot y de los conflictos.
- Seguimientos posibles:
  - una tool godot.scene_diff para el agente y el evaluador;
  - el resumen por nodos en la fila del diálogo de cambios, en lugar de +N −N líneas;
  - el orden de los hijos (index) no se compara.

**Relacionadas:** Revisar los cambios del turno por trozo (keep/reject) y contador vivo de archivos (como Zed)

### «Planificar» y /plan para agentes sin modo plan · Revisión

**Prioridad:** media · **Tamaño:** M · **Etiquetas:** `idea`, `ui`

Fuente B del diseño de m11-22, separada por decisión (2026-11-10). m11-22 hace la aprobación del plan cuando el agente tiene modo plan (ExitPlanMode de Claude Code); esta tarea cubre los agentes que no lo tienen (Codex, Gemini por ACP) y el pedido explícito de un plan desde Construir.
- Botón «Planificar» en la fila del selector de modo (solo con sesión READY y modo distinto de One-shot) y /plan <pedido> en el composer; sin texto, toma lo que haya en el composer.
- Pasa a Preguntar y manda un prompt del harness (PLAN_REQUEST) que pide criterios jugables, diseño en términos de Godot (escenas, nodos, scripts, señales, autoloads, input map, capas de colisión) y tareas numeradas. Si el agente tiene ExitPlanMode, que lo presente con él (m11-22); si no, que termine el turno con el plan en un bloque ```plan.
- Con el bloque, la misma PlanApprovalView de m11-22 aparece debajo del mensaje; aprobar manda send_in_mode(BUILD, PLAN_APPROVED) con la ruta del plan guardado en .godot_agent/plans/.
Riesgo: no se puede verificar con agentes reales que respeten el bloque ```plan (solo están instalados Claude Code y antigravity-acp).
Por qué: sin esto, solo los agentes con modo plan propio tienen el paso de aprobar antes de construir.

**Decisiones:**
- ! «Planificar» y /plan piden el plan según lo que publique el agente, y la tarjeta reconoce un bloque ```plan. - Si el agente publica un modo "plan" (como Claude Code), PLAN_REQUEST le pide que lo presente con su herramienta de plan (ExitPlanMode) y aparece la tarjeta de m11-22. - Si no, el harness le pide que termine el turno con el plan en markdown dentro de un único bloque con lenguaje exactamente `plan`. - Al terminar un turno que mandó el harness para planear (PLAN_REQUEST, PLAN_EDIT o PLAN_KEEP_PLANNING) sin tarjeta de ExitPlanMode, el harness toma el último bloque ```plan del agente. Lo muestra en la misma PlanApprovalView con un PermissionRequest propio, que no va por ACP. En el mensaje del agente el bloque queda como una línea («Plan presented · in the card below»): el plan aparece una sola vez. - Aprobar guarda el plan en .godot_agent/plans y manda send_in_mode(BUILD, PLAN_APPROVED) con la ruta del archivo y el pedido de llevar las tareas como lista del agente. El modo se sincroniza normal (set_mode), porque ese agente no sale solo de ningún modo plan. - Editar y «Seguir planeando…» mandan los mismos prompts que en m11-22, pero piden de nuevo el bloque ```plan en lugar de ExitPlanMode. - Si el usuario manda otro mensaje con la tarjeta pendiente, la tarjeta queda cancelada. - /plan lo resuelve el harness y nunca va al agente. · sin revisar
  Por qué: ACP no tiene un mensaje para «plan a aprobar»: solo existe lo que hace Claude Code con request_permission de ExitPlanMode. Un bloque cercado con lenguaje propio es lo mismo que ya funciona con `findings` en Revisar: cualquier agente lo puede escribir y el harness lo parsea sin tools nuevas. Pedir un solo camino por agente, en lugar de «usá ExitPlanMode si la tenés y si no el bloque», le ahorra al agente decidir y evita que presente el plan por los dos lados (no lo vi pasar; es una precaución). Limitar la detección a los turnos de plan evita tomar como plan un ```plan que el agente escriba en otro contexto.
  Descartado: - Una tool MCP godot.present_plan: hay que llamarla, y los agentes no la usan de manera tan uniforme como una respuesta en texto.
  - Detectar ```plan en cualquier turno: falsos positivos.
  - Un único prompt condicional para todos los agentes.

**Prueba:** Unit:
- tests/unit/test_plan_request.gd: 10 tests (bloque ```plan, prompt según modo plan, tarjeta, aprobar, editar, seguir planeando, cancelación, /plan).
- test_composer: menú «+» e ícono.

Xvfb: --godot-agent-plan-test, que ahora suma la parte del bloque con tests/scripts/plan_block.json (agente falso sin modos), en en y es. Sin tokens.

Regresiones: queue, review, oneshot, ui_long_permission, ui_harness_prompt, auto, i18n (es). run_all 635 tests sin fallas.

suite.sh ci: 12/13. Falla edit por scope_compass en project.godot; el arreglo está en sm/suite.

**Notas:** Rama sm/m11-58, desde sm/m11-22. Commits: d77512b, c076d46 (título del plan + check con Antigravity) y f57120a. El formato quedó registrado como decisión.

Verificado con Antigravity real, antigravity-acp 1.4.3, el 2026-11-11, con --godot-agent-antigravity-plan-test (gasta tokens):
- Publica los modos default, auto_edit y yolo; ninguno es plan.
- Planificar → terminó con un bloque ```plan con la estructura pedida → tarjeta (from_block), con una línea plegada en el mensaje → Aprobar → Construir + PLAN_APPROVED.
- Su primera edición pidió permiso en edit_files; la denegué y corté.
- El plan empezaba por «### 1. Playable Criteria» y el archivo se llamó 1-playable-criteria.md. Por eso el pedido ahora pide un título «# Plan: …».
- No llevó las tareas a su lista (plan_update) antes de la primera edición.
- antigravity-acp escribe skills/system/run-workflow/SKILL.md en su carpeta de trabajo. Ojo con git add.

Arreglo de paso en SessionModel.apply_session: un session/new sin modes ya no conserva los modos del agente anterior.

/plan solo aparece en el menú de / cuando «Planificar» está disponible.

run_all termina igual que origin/main: 2 RIDs, 46 ObjectDB y 11 resources; son de main, no de la rama.

**Bloqueada por:** Plan aprobable antes de construir (fuera del One-shot)

### Rechazar por nodo en escenas, fase 2: nodos borrados o movidos, recursos nuevos y conexiones · Revisión

**Prioridad:** baja · **Tamaño:** M · **Etiquetas:** `ui`

Sigue a m11-34. En la fase 1, una .tscn deja rechazar solo propiedades cambiadas y nodos agregados. Faltan:
- devolver un nodo borrado: reinsertar su sección y la de sus descendientes en el lugar que tenían;
- deshacer un movido o renombrado;
- propiedades con un ExtResource o SubResource que no está en la escena actual: hay que rearmar las secciones ext_resource y sub_resource con ids nuevos sin chocar con los existentes;
- conexiones agregadas o quitadas.
Mientras tanto, para eso queda «Volver atrás» del archivo entero, con confirmación. Lo mismo que en la fase 1: verificar sobre el texto actual y, si cambió después del turno, el cambio queda stale y no se pisa nada.

- [x] Base: importar recursos con ids nuevos, GC de los que quedan huérfanos, validate() cargando la escena antes de escribir; nodos borrados de vuelta entre hermanos
- [x] Movidos y renombrados; encabezado (nombre de la raíz, type/instance, groups); conexiones agregadas y quitadas
- [x] Propiedades con recursos y dentro de un sub_resource (solo si no está compartido)
- [x] UI (validate en reject_hunk, «No se pudo revertir: …», textos del diálogo), prueba con las 41 escenas del repo y editor check

**Decisiones:**
- ! La validación cargando la escena usa una copia en user:// sin el uid del encabezado, ResourceLoader con CACHE_MODE_IGNORE, instantiate() y free(). Además de que cargue, busca las rutas que la operación espera presentes (el nodo devuelto, movido o con la propiedad) o ausentes (el nodo sacado; no para una sección de override de una escena instanciada). Si falla: «No se pudo revertir: así la escena no cargaría (motivo). No se escribió nada.», con el motivo técnico en inglés. · sin revisar
  Por qué: Lo pidió agent-harness-81 como red de seguridad obligatoria. Godot instancia aunque un nodo tenga un padre que no existe (lo saltea con un error), así que cargar solo no alcanza: hace falta buscar el nodo.
  Descartado: Validar con SceneDiff solamente (no ve errores de carga); comparar el árbol entero con el de antes (en producción el resto pudo cambiar a propósito después del turno).
- ! Deshacer un rechazo no guarda estado: borra los ext_resource/sub_resource que la operación dejó sin referencias y que antes de ella sí se nombraban (en cascada). Se cambió del plan, que decía guardar los ids agregados en el resultado del rechazo. · sin revisar
  Por qué: Los cambios se recalculan desde los dos textos del turno cada vez que se abre el diálogo y el aviso con «Deshacer» solo guarda {data, path, index}. Esta regla da lo mismo sin estado y nunca borra un recurso que alguien usa.
  Descartado: Guardar los ids agregados en data.hunk_state (sobrevive en el JSON del aviso, pero se desincroniza si el usuario edita).
- ! En la prueba con las escenas del repo, las 41 se comparan como texto (SceneDiff: el diff con la original queda vacío y deshacer vuelve a lo borrado). Además, 8 se cargan y su árbol se compara con el de antes: nombres, orden de hijos, propiedades guardadas (recursos locales por contenido) y conexiones. Las otras 33 son de carpetas con .gdignore o su propio project.godot (completion_eval, completion_fixture, map_fixture…): sus scripts no compilan en este proyecto. · sin revisar
  Por qué: Cargarlas en run_all da errores de parseo de sus scripts, que el runner cuenta como fallas, y no prueban nada del rechazo.
  Descartado: Cargar sin scripts (no hay forma limpia); abrir cada proyecto aparte (lento).
- ! Confirmado: el borrado de recursos al deshacer (y al rechazar un nodo agregado) solo saca secciones [ext_resource]/[sub_resource] del texto del propio .tscn (SceneRevert._collect → _drop_spans sobre el texto). Nunca borra ni toca archivos de recursos: el único archivo que se escribe es la escena, y además la copia temporal de validate() en user://, que se borra después. · sin revisar
  Por qué: Lo pidió agent-harness-81 como condición para aceptar deshacer sin estado.

**Prueba:** - run_all 701/0. Tests nuevos en tests/unit/test_scene_revert_phase2.gd:
  - ida y vuelta por cada cambio, con la escena validada;
  - rechazar todo da la escena de antes, con el mismo árbol cargado;
  - ids que chocan (sub y ext) y reuso de ext por ruta;
  - orden entre hermanos (primer hijo y después del subárbol, en cualquier orden da el mismo texto);
  - casos stale: nombre ocupado, ya está, padre que no está, padre renombrado por unique_id;
  - movido; encabezado y conexiones; type/instance;
  - sub compartido no se rechaza;
  - validate();
  - las 41 escenas del repo con semilla fija.
- Editor check (edit_check._check_removed_node_back): borrar un Sprite2D con textura+gradiente por MCP, guardar y rechazar. Vuelve entre sus hermanos con sus recursos, sin diálogos y sin quedar sin guardar; deshacer lo saca junto con los recursos. Verificado con mutación: sin la regla del hermano anterior, falla.
- suite ci pasa.

**Notas:** Hecho en sm/m11-59 (pusheada, ac18fd6). Commits: 9045f02 (core + tests), 975a6d0 (UI), 185a927 (editor check), ac18fd6 (CHANGELOG y wiki).

Implementado según el plan de abajo, con dos cambios:
- Deshacer no guarda estado. Borra los recursos que la operación dejó sin referencias y que antes sí se nombraban (ver decisión).
- validate() carga la escena antes de escribir y busca las rutas esperadas. Lo pidió agent-harness-81 como red de seguridad.

Escenas del repo: las 41 se comparan como texto y alcanza (lo confirmó agent-harness-81). Solo 8 se cargan además, porque las otras 33 son de carpetas con .gdignore o project.godot propio, donde los scripts no compilan.

Plan original:
Todo en core/scene_revert.gd, sobre el texto actual. Si cambió después del turno, queda stale y no se escribe nada. Deshacer es la inversa con la misma verificación.

1. Recursos. Se juntan los ExtResource/SubResource que nombra lo que vuelve (recursivo).
- ext: se reusa uno con la misma uid o ruta; si no, se copia.
- sub: se copia, salvo que tenga el mismo id y el mismo contenido.
- Ids: el viejo si está libre; si no, uno nuevo con formato de Godot y RNG inyectable, sin chocar.
- Las referencias se reescriben con un mapa, solo dentro de Resource("…").
- Los ext van después del último ext y los sub después del último sub, en orden de dependencia. load_steps se ajusta.

2. Nodo borrado.
- Precondiciones: el padre existe (por unique_id o ruta), el unique_id no está y no hay un hermano con el mismo nombre.
- Va después del subárbol del hermano anterior más cercano que siga ahí; si no hay ninguno, justo después del padre.
- Las rutas parent= se rebasan.
- Las conexiones vuelven si el otro extremo existe.

3. Movido o renombrado: name y parent como antes, el subárbol a la posición de antes, y se reescriben las conexiones y los [editable].

4. Encabezado (nombre de la raíz, type/instance, groups) y conexiones (sacar o volver a poner si están los dos extremos). En un sub_resource se edita solo si no está compartido; si lo está, «Solo con Volver atrás».

**Bloqueada por:** Revisar los cambios del turno por trozo (keep/reject) y contador vivo de archivos (como Zed)

### Compactación como estado propio: anunciar session.compaction y mostrar compaction_update · Revisión

Sale de m11-35. claude-agent-acp (0.106) manda la compactación como una tool call sintética «Compact conversation» (name compact, kind think) si el cliente no anuncia clientCapabilities.session.compaction. Si lo anuncia, manda sessionUpdate «compaction_update» con compactionId, status (in_progress/completed/cancelled/failed) y summary (el resumen que quedó, sin las etiquetas). Hay que anunciar la capacidad, mostrar la compactación en el chat como una fila propia con el resumen desplegable, guardarla en el historial y reproducirla, y usar el fin de la compactación para rearmar el aviso de m11-35. Cambia lo que ve el usuario en el chat y en el historial: por eso va aparte.

**Decisiones:**
- ! El aviso de la tool call «Compact conversation» (adapters sin la capacidad) también espera al fin del turno para ofrecer el traspaso, igual que compaction_update; una compactación fuera de un turno lo ofrece enseguida. · sin revisar
  Por qué: La regla de agent-harness-81 (no cortar el flujo del turno) vale igual para los dos caminos. claude-agent-acp tiene compactación en reposo (idle-compaction), que llega sin turno en curso.
  Descartado: Dejar el camino viejo como estaba (acción inmediata). Esperar siempre al próximo fin de turno, aunque la sesión esté quieta.

**Prueba:** Headless: tests/run_all.gd -- test_compaction (capacidad anunciada; los updates vivos del fixture dan una fila con el resumen y el completed repetido no lo borra; failed/cancelled; el historial graba solo el final y lo reproduce con replaying; el replay de session/load deja la fila entre los mensajes). Editor: tests/suite.sh run ui-handoff (compaction_update en medio del turno: fila con el resumen plegado después del mensaje donde llegó, sin acción mientras el turno sigue, con «Nueva sesión con resumen» al terminar; la tool call de un adapter sin la capacidad también la ofrece).

**Notas:** Captura (claude-agent-acp 0.106.0 con haiku, probe ACP en Python): tests/fixtures/acp/compaction_0106.json.
- Con la capacidad: in_progress → completed con summary → completed sin summary, con el mismo id. La respuesta del /compact es end_turn con usage en 0.
- session/load: un solo completed con summary y otro id, entre los mensajes.

Hecho en sm/m11-60 (11c21a1):
- session_controller anuncia session.compaction.
- SessionModel._apply_compaction arma una fila NOTICE por compactionId, con details y details_title, y emite compaction_changed.
- SessionHistory graba solo el estado final de cada compactación.
- agent_dock: _compaction_offers. La acción va al terminar el turno (turn_finished), o enseguida si la sesión está quieta; al reproducir, nunca. El aviso de la tool call vieja también espera al fin del turno.
- El resumen se muestra en la fuente mono del detalle de los avisos, con Copiar.

### Cerrar el editor no deja procesos del agente · Revisión

Hallazgo de m11-24: el PREDELETE de AgentProcess fallaba en el cierre («stop» en «null instance»). Comprobar si cerrar el editor deja procesos (npx, claude-agent-acp, node) y arreglarlo en AgentProcess para todos los que lo usan, con un check que cierre el editor y verifique que no quedan hijos.

**Decisiones:**
- ! stop_all() también corre al desactivar el plugin, no solo al cerrar el editor · sin revisar
  Por qué: Va en _exit_tree del plugin, que es el único punto confiable en los dos casos; con el plugin desactivado no queda nadie que lea esos procesos.
  Descartado: Escuchar NOTIFICATION_WM_CLOSE_REQUEST solo para el cierre (deja huérfanos al desactivar); mantener solo el PREDELETE (no corre o falla en el cierre).

**Prueba:** tests/suite.sh run quit (ci, grupo editor): agentes falsos con ignore_eof+spawn_child en la sesión principal, una pestaña y un AgentProcess suelto; cierra el editor con WM_CLOSE_REQUEST y mira con kill -0 que no quede ninguno de los 6 pids. test_agent_process.test_stop_all.

**Notas:** Reproducido antes del arreglo: las dos sesiones se limpiaban (el plugin las para en _exit_tree); el AgentProcess suelto, cuyo dueño se libera recién en el cierre, quedaba vivo con su hijo (sleep). Arreglo: lista estática de procesos vivos en AgentProcess (pid → weakref), stop_all() al final de agent_plugin._exit_tree; PREDELETE mata solo con OS, sin llamar a stop(). Rama sm/agent-process-quit, 5f576a7.

### Regresiones: sabotajes de escena generados (fase 2 de m11-41) · Revisión

**Etiquetas:** `idea`, `playtest`

Fase 2 de m11-41, aparte por pedido de agent-harness-81. Además de las mutaciones de GDScript en memoria, generar sabotajes de escena sobre los nodos que toca cada regresión: una propiedad exportada a 0/false/null, una señal desconectada, un nodo oculto o deshabilitado. Se corren como el sabotaje de m16-09 (código antes de la regresión, sin tocar archivos) y se suman al mismo puntaje y a la lista de sobrevivientes. Por qué: una regresión puede no mirar el código mutado pero sí el estado de la escena; Beckett v1.16 (op=mutate) muta así.

**Decisiones:**
- ! Los sabotajes se aplican sobre la escena ya asentada (después de _ready), se eligen por los nombres de nodo que aparecen en el código de la regresión, y solo cubren lo que está en el .tscn. · sin revisar
  Por qué: Es el mismo punto que el sabotaje de m16-09, y no exige tocar el .tscn ni cargarlo modificado. Filtrar por los nodos nombrados concentra la cuota en lo que la regresión toca, como pide la tarea. Las conexiones por código o los nodos de runtime no se pueden enumerar sin correr el juego.
  Descartado: Aplicar antes de _ready instanciando un PackedScene modificado en memoria (más fiel para valores que se leen en _ready, pero bastante más complejo); sabotear todos los nodos; desconectar todas las conexiones vivas de un nodo.

**Prueba:** tests/unit/test_scene_sabotage.gd: los sabotajes del fixture leídos del .tscn y serializables a JSON, el filtro por el código de la regresión, apply en memoria (propiedad, ocultar, señal, deshabilitar diferido, inválido si el nodo falta o la señal ya no está conectada, el .tscn intacto), y el plan con los sabotajes, sus regresiones y where() sin «:0». tests/regressions_cli_check.sh: con --mutate sobre la regresión de door.tscn, los 3 sabotajes que mira quedan detectados, «root hidden» sobrevive y el hash de los .gd y .tscn no cambia. Commit 1b23c91.

**Notas:** Hecho en 1b23c91 (sm/m11-62).
- SceneSabotage (playtest/mutation/scene_sabotage.gd) lee el SceneState sin instanciar, incluidas las escenas instanciadas hasta 3 niveles.
- Sabotajes:
  - una propiedad exportada a 0, 0.0, el bool contrario, Vector ZERO o null, según el valor efectivo: el override de la escena o el default del script;
  - una conexión de la escena cortada;
  - un nodo oculto (CanvasItem o Node3D);
  - una colisión deshabilitada (CollisionShape y CollisionPolygon, que no se ocultan porque eso no cambia nada).
- Con el código de las regresiones de esa escena, solo se sabotean los nodos que nombra, la raíz y las señales que llegan a la raíz.
- Se aplican en memoria en regression_cli.run_one, después del settle. Un sabotaje que no se puede aplicar queda inválido.
- La guarda de guardado de _run_mutant los cubre.
- En el plan, cada escena es un «archivo» más de la muestra pareja. where() muestra la ruta de la escena sin línea, y Abrir abre la escena.
- No cubre: las conexiones hechas por código (connect en _ready) ni los nodos instanciados en runtime.

### Regresiones: sabotajes de escena antes de _ready (PackedScene modificado en memoria) · En curso

**Prioridad:** baja · **Etiquetas:** `idea`, `playtest`

Seguimiento de m11-62, pedido por agent-harness-81. Hoy los sabotajes de escena se aplican sobre la escena ya asentada, después de _ready. Por eso un valor que solo se lee en _ready (por ejemplo, la vida inicial) no se ve afectado. Propuesta: en el modo --mutant, cargar el PackedScene, modificar su SceneState en memoria (override de la propiedad o conexión sacada) e instanciar esa versión, sin guardar nunca y con la misma guarda de guardado. Por qué: es más fiel para los valores que se leen al arrancar. Sigue sin cubrir las conexiones hechas por código.

**Decisiones:**
- ! El sabotaje se pone sobre la instancia recién creada con PackedScene.instantiate(), antes de que entre al árbol (change_scene_to_node), y no se reescribe el SceneState. · sin revisar
  Por qué: SceneState es de solo lectura. Modificarlo exige reescribir a mano el diccionario _bundled del PackedScene (índices de nombres y variants, contadores de propiedades y conexiones, escenas instanciadas por dentro), que es frágil y depende del formato interno. Al salir de instantiate() la instancia ya tiene los valores del .tscn y las conexiones persistentes, y todavía no corrieron _enter_tree ni _ready. Por eso el resultado es el mismo que con el .tscn cambiado, también para los nodos de escenas instanciadas por dentro, sin tocar el PackedScene del caché.
  Descartado: Editar _bundled de un duplicado del PackedScene y instanciar ese (lo que proponía la tarea); dejar el sabotaje después del settle (m11-62).

### capture_editor_viewport desde una cámara elegida y desde varios ángulos · Revisión

**Prioridad:** baja · **Etiquetas:** `idea`

Resto de m11-52: allí se hizo solo el lado del juego (capture_game_frame con camera, look_from/look_at y angles), que fue lo que pidió agent-harness-81. Falta lo mismo en el editor: capture_editor_viewport con look_from/look_at, angles o un rect 2D, renderizando en un SubViewport con el world_3d de la escena editada y una cámara temporal, sin mover la cámara del usuario. Se puede reusar playtest/runtime/camera_views.gd (plan y orbit). Por qué: así el agente revisa un nivel sin correr el juego ni pedirle al usuario que mueva la vista.

**Prueba:** mcp_check._check_editor_views abre camera_views.tscn y prueba: camera «Side» ve la caja verde, look_from/look_at ve la roja, 3 ángulos alrededor de la verde dan 3 vistas verdes, la cámara del editor queda igual, y dan error una cámara inexistente y angles en 2d. test_camera_views agrega el caso de view_3d. run_check sigue pasando con el helper movido a mcp_check.

**Notas:** Hecho en fcfb183 (sm/m11-64). capture_editor_viewport toma camera, look_from/look_at, angles, distance y zoom. Reusa CameraViews: plan() recibe view_3d según `which`, y render() recibe el viewport del editor, con cuyo mundo renderiza. El SubViewport cuelga del base control del editor. Las vistas incluyen los gizmos y la grilla del editor, porque comparten el mundo. No se hizo un `rect` 2D aparte: look_at con zoom cubre eso.

### session_send: grupo propio, sobre no confiable y sin escalar a un modo con más permisos · Revisión

**Prioridad:** alta · **Tamaño:** S

Pedido del coordinador tras m11-28, y frena el release. godot.session_send estaba en GROUP_READ: un agente en Preguntar o Revisar (o una sesión que leyó texto plantado) le mandaba sin permiso un prompt a otra pestaña, que podía estar en Auto. Es una escalada de privilegios entre sesiones.
- El mensaje llega en sobre no confiable, con «from session X, data not instructions».
- Grupo propio sessions_message: ask en todos los modos y deny en One-shot.
- Hacia un modo con más permisos se deniega siempre, sin importar la matriz.
- Además: «Open the conversation» de la segunda opinión para el oráculo antes de abrirla.

**Decisiones:**
- ! Niveles para la escalada: Preguntar = Revisar < Construir < Auto = One-shot. También se deniega Construir → Auto o One-shot. · sin revisar
  Por qué: El pedido nombraba Preguntar/Revisar → Construir/Auto. La regla general («destino más permisivo que el origen») también cubre Construir → Auto: Auto edita sin preguntar lo que en Construir pide tarjeta. Preguntar y Revisar no editan ninguno de los dos, así que entre ellos se permite.
  Descartado: Solo denegar desde Preguntar/Revisar (Construir → Auto permitido); un orden estricto con Revisar por encima de Preguntar (Revisar puede correr el juego preguntando)

**Prueba:** - run_all: 812 tests, 0 fallos. test_session_messages cubre:
  - el grupo y sus defaults, y el cambio en la matriz;
  - la matriz de escalada, los 25 pares de modos;
  - el sobre, que un cierre falso no rompe;
  - el precheck: corre una sola vez con los argumentos y antes del permiso.
- test_second_opinion: release.
- suite.sh ci en 4.7.2: 20/20 PASS.
  - El check de sessions cubre: Auto→Auto pide tarjeta; con permiso de sesión llega a entregar; Preguntar→Auto se deniega sin tarjeta aun con ese permiso; Preguntar→Revisar entrega.
  - El check de second-opinion cubre: release para el proceso del oráculo.

**Notas:** Rama sm/session-send (6af22a3) desde origin/sm/next4 e3e3ca3.

- Antes, el mensaje llegaba sin sobre, como prompt con un prefijo entre corchetes. Ahora va con SessionTools.delivery_text.
- Rangos de modo para la escalada (decisión): Preguntar = Revisar (0) < Construir (1) < Auto = One-shot (2). Se deniega si el rango del destino es mayor que el del origen. Construir→Auto también se deniega (Auto edita sin preguntar).
- El rechazo está en _message_refusal, que llaman el precheck (antes de la tarjeta, sin tarjeta) y la entrega (el destino pudo cambiar de modo mientras esperaba).
- ToolRegistry.precheck ahora es (caller, tool_name, args) y se llama una sola vez por tool call.
- Las sesiones en una copia aparte siguen pudiendo mandar: session_send sale del precheck antes de la regla de copias.
- SecondOpinion.release(): cancela la pregunta, para el proceso y guarda el historial. La llama «Open the conversation» antes de abrir la pestaña.

### Marcas de keep/reject por trozo en el Script Editor · En curso

**Tamaño:** M

Seguimiento de m11-34 (punto 3 opcional de la idea). Hoy los cambios de un turno se conservan o rechazan por trozo solo en el diálogo «Ver cambios». En el Script Editor, cada trozo cambiado por el último turno debería verse en el gutter con ✓ (conservar) / ✗ (rechazar), reusando las anotaciones de Revisar y la misma lógica de rechazo por trozo (incluido stale y Deshacer). Pedido por agent-harness-81, rama desde origin/sm/next5, con su check de editor.

**Decisiones:**
- ! Marcas en un gutter propio con ✓ y ✗ clickeables en la primera línea de cada trozo (sin tarjeta) y una banda en la barra de estado; solo el último turno de la pestaña activa y solo scripts del proyecto abierto · sin revisar
  Por qué: Es lo que pidió 81 (gutter con ✓/✗ por trozo). La banda da el motivo cuando no se puede rechazar. Las escenas no se abren en el Script Editor; las copias aparte no están abiertas en el editor.
  Descartado: Tarjeta bajo la línea como las de Revisar; marcas de todos los turnos de la sesión

### Ctrl+Enter: mandar y seguir al agente · Pendiente

**Tamaño:** S

Seguimiento de m11-33. Ctrl+Enter en el composer manda el mensaje y prende «Seguir al agente» para ese turno (como Zed), sin tener que tocar el botón de la mira. Pedido por agent-harness-81, rama desde origin/sm/next5, con su check.

**Decisiones:**
- ! Ctrl+Enter deja de bajar de línea (queda solo Shift+Enter) y prende el seguimiento solo para ese pedido: se apaga al terminar ese turno y la cola, salvo que el usuario toque la mira · sin revisar
  Por qué: 81 pidió Ctrl+Enter para mandar y seguir; Shift+Enter ya baja de línea. «Para ese pedido» evita que un atajo deje prendido algo que mueve el editor en los turnos siguientes.
  Descartado: Otro atajo (Ctrl+Shift+Enter) manteniendo Ctrl+Enter como salto de línea; dejar el seguimiento prendido hasta que el usuario lo apague

## M10 — Revisión de UX  (49/49, 9 en revisión)

Arreglar lo que la revisión de UX del 29/10 encontró en el dock, Ajustes, el registro de ACP, Extensiones, One-shot, Alt+I y el Agent Log: primero el diseño roto que esconde controles, después los flujos que más se usan.

**Hecho cuando:**
- Cada hallazgo quedó hecho o descartado con su motivo en la tarjeta.
- Un recorrido de capturas de todas las superficies no muestra controles tapados ni cortados.

### La pregunta del agente aparece también como herramienta · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** baja · **Tamaño:** S · **Etiquetas:** `ux`, `dock`

Con AskUserQuestion de Claude Code, la pregunta se ve dos veces: como fila del grupo de herramientas («¿Me das permiso…? · other · output · 1 line») y como tarjeta de pregunta justo abajo.

Propuesta: ocultar del grupo el tool call que originó una elicitation (mismo toolCallId) o mostrarlo como «Pregunta · respondida».

**Prueba:** test_elicitation.test_question_tool_call_leaves_the_tool_group (headless).

**Notas:** Hecho en la sesión cloud, traído a main en 441b7b9 sin atribución. El tool call que originó una pregunta sale del grupo de herramientas (y el grupo, si queda vacío): por el toolCallId de la elicitation o, si no viene, por un tool call sin terminar del último grupo con el mismo título que la pregunta; si llega después de la pregunta, no se agrega. SessionModel: _question_calls, _hide_question_call y _detach (sacado de _reparent).

### Crash de Godot 4.8 al aprobar un permiso que guarda la escena · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** S · **Etiquetas:** `bug`, `dock`

29/10 03:56, LittleVillages con Godot 4.8-beta1: Claude pidió set_properties (light_energy 1.2) y save_scene en paralelo; al aprobar, la escena se guardó (03:56:05) y el editor abortó (SIGABRT, core en systemd).

Backtrace con los símbolos de debug de 4.8-beta1: crash dentro de BaseButton::on_action_event, procesando el clic (Viewport::_gui_input_event ← DisplayServerX11::process_events). El await del permiso se reanuda en el mismo emit de resolved, así que la tool (guardar la escena) corría dentro del manejador del clic.

Arreglo: las vistas de permiso y de pregunta del agente resuelven el pedido con call_deferred. No se pudo reproducir en Xvfb (un permiso y save_scene con un clic real sobrevive en 4.8-beta1); falta el caso con dos tools en paralelo.

**Prueba:** Xvfb con 4.8-beta1: aprobar con un clic real un permiso de save_scene no tira el editor. Sin repro del caso original (dos tools en paralelo), que quedó para probar a mano en LittleVillages.

**Notas:** Arreglo en 715fbb0: permission_view y elicitation_view resuelven el pedido con call_deferred, así la tool que esperaba el permiso no corre dentro de BaseButton::on_action_event.

### Ocultar el bloque findings del chat en Revisar · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** media · **Tamaño:** S · **Etiquetas:** `ux`, `dock`

En modo Revisar el agente contesta con un bloque ```json {"findings": …}``` que el harness ya convierte en hallazgos (panel y Script Editor), pero el chat lo sigue mostrando entero y ocupa media pantalla.

Propuesta: una vez leído, reemplazarlo en el mensaje por una línea («2 hallazgos · ver en el panel») con el JSON plegado.

Archivos: ReviewStore, agent_message_view.gd. Sale de m12-03.

**Notas:** Hecho en la sesión cloud «Godot agent improvements» (rama claude/godot-agent-improvements-dh5g01), traído a main en ed333af sin atribución. Revisado: tests de la rama 341/341.

### Migrar perfiles viejos: quitar Gemini CLI y el Codex sin comando · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** media · **Tamaño:** S · **Etiquetas:** `ux`, `ajustes`

Los perfiles preseteados se sacaron en 0.1.8, pero quien ya tenía la configuración guardada conserva «Gemini CLI» (discontinuado, reemplazado por Antigravity) y «Codex» sin comando: aparecen en Ajustes › Agentes y en el selector del dock. Visto en la configuración real de Godot 4.7 durante la revisión del 29/10.

Propuesta: al cargar los perfiles, quitar una vez el gemini-cli preseteado (command "gemini", sin args) y el codex con comando vacío, solo si siguen iguales al preset (no tocar uno editado), y avisar en el log.

Archivos: harness_settings.gd (profiles)

**Notas:** Hecho en la sesión cloud «Godot agent improvements» (rama claude/godot-agent-improvements-dh5g01), traído a main en ed333af sin atribución. Revisado: tests de la rama 341/341.

### Agent Log: ir a la línea del error desde el chat · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** baja · **Tamaño:** M · **Etiquetas:** `ux`, `log`

El log es una lista plana; desde un error se abre el panel pero no se ubica en la línea.

Propuesta: «Abrir el log» filtra por la sesión y salta a la línea del error, resaltada.

Archivos: agent_log_panel.gd

Informe: https://claude.ai/artifact/KsFLJqJYs2XKeoAc8BAPWH

**Prueba:** acp_session_check (162 checks, 0 fallos; el escenario crash verifica que la acción apunta a la línea «exited»), run_all. Sin captura: ningún check del dev plugin aprieta el botón.

**Notas:** Hecho en la sesión cloud, traído a main en 253ac05 sin atribución.
UX: «Abrir el log abajo» desde un error salta a su línea del Agent Log, resaltada (m12-36)
Nota: los avisos de error (sesión que no abre, agente que no arranca o se cae,
turno con error) guardan en su acción el `seq` de la línea del log que les
corresponde (AgentLog.last_seq; el turno con error ahora también deja su línea en
el log). Al apretarla, el dock emite show_log_requested(seq): el plugin abre el
panel y AgentLogPanel.focus_entry prende todos los canales (para que un filtro no
la esconda), la resalta en amarillo y la lleva a la vista. Lo que no se hizo:
filtrar por sesión, porque el log es uno solo para todas las sesiones y sus
líneas no dicen de cuál son (habría que etiquetar cada llamada a add).

### Dos cosas se llaman «Agent» · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** baja · **Tamaño:** S · **Etiquetas:** `ux`, `oneshot`

La pantalla principal «Agent» abre One-shot y la pestaña del dock también se llama Agent.

Propuesta: La pantalla principal como «One-shot».

Archivos: plugin.gd (_get_plugin_name)

Informe: https://claude.ai/artifact/KsFLJqJYs2XKeoAc8BAPWH

**Notas:** Hecho en la sesión cloud «Godot agent improvements» (rama claude/godot-agent-improvements-dh5g01), traído a main en ed333af sin atribución. Revisado: tests de la rama 341/341.

### One-shot: una tarjeta chica en una pantalla vacía · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** media · **Tamaño:** M · **Etiquetas:** `ux`, `oneshot`

900 px al medio de 1920, objetivo de 400 px de alto y presupuestos de 290 px para valores como «8».

Propuesta: Dos columnas: objetivo con ejemplos a la izquierda; agente, presupuestos compactos y opciones a la derecha.

Archivos: agent_main_screen.tscn

Informe: https://claude.ai/artifact/KsFLJqJYs2XKeoAc8BAPWH
Lienzo: https://claude.ai/artifact/3WiCtTnZP94EADbreh18ny (pantalla 7)

**Prueba:** --godot-agent-oneshot-test en Xvfb (0 fallas, antes 1), --godot-agent-screenshot con el formulario en columnas, test_oneshot_* (headless).

**Notas:** Hecho en la sesión cloud, traído a main en 4508998 sin atribución.
UX: el formulario del One-shot en dos columnas, con ejemplos de objetivo y presupuestos compactos (m12-34)
Nota: a la izquierda el objetivo (más alto) con tres ejemplos que se cargan con
un clic («Pong de 2 jugadores…», un shooter de oleadas, un plataformas de tres
niveles); a la derecha, el agente, los presupuestos como etiqueta y valor (antes
tres columnas de 290 px para valores como «8»), las casillas, la regla de cuota
e «Iniciar One-shot». Con el formulario por debajo de 820 px se apilan
(BoxContainer.vertical), así sigue entrando en el centro angosto de m12-09.

De paso:
- m12-33: el nombre del agente sale del perfil de la sesión abierta y, si no hay,
  del elegido en Ajustes (con el agente del run y sin perfiles guardados, Iniciar
  quedaba apagado). El check oneshot_ui_check le pasa «Agente falso».
- Dock vacío con un One-shot a medias y sin perfiles: el botón es «Retomar
  One-shot» (antes «Configurar un agente…»/«Otros agentes…») y no se muestran
  los sugeridos. Era la falla que el check ya tenía antes de este hito.

### One-shot: «Iniciar» deshabilitado sin decir por qué · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** S · **Etiquetas:** `ux`, `oneshot`

Botón apagado casi ilegible, sin texto de qué falta ni con qué agente corre.

Propuesta: El agente elegido arriba y, junto al botón, lo que falta («Escribí el objetivo»); sin agentes, el selector del dock.

Archivos: agent_main_screen.gd

Informe: https://claude.ai/artifact/KsFLJqJYs2XKeoAc8BAPWH
Lienzo: https://claude.ai/artifact/3WiCtTnZP94EADbreh18ny (pantalla 7)

**Prueba:** test_oneshot_form.test_start_blocker (headless). Sin captura nueva.

**Notas:** Hecho en la sesión cloud, traído a main en e289169 sin atribución. El formulario dice con qué agente corre («Corre con X (el agente elegido en el dock)»); sin agente, aviso en amarillo y «Configurar un agente…» que abre Ajustes (no el selector del dock de la propuesta). Junto a «Iniciar One-shot» va lo que falta (objetivo, agente o un One-shot en curso), también como tooltip; el plugin refresca al cambiar los perfiles o el elegido.

### Extensiones › Instrucciones: qué agente lee cada archivo · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** baja · **Tamaño:** S · **Etiquetas:** `ux`, `extensiones`

Para saber qué lee Antigravity hay que abrir el desplegable archivo por archivo.

Propuesta: Lista de archivos con quién lo lee al lado y el editor a la derecha.

Archivos: instructions_tab.gd

Informe: https://claude.ai/artifact/KsFLJqJYs2XKeoAc8BAPWH
Lienzo: https://claude.ai/artifact/3WiCtTnZP94EADbreh18ny (pantalla 6)

**Prueba:** --godot-agent-extensions-shots en Xvfb (pasa; captura de Instrucciones), test_claude_extensions y test_i18n (headless).

**Notas:** Hecho en la sesión cloud, traído a main en c7e0c61 sin atribución.
UX: Extensiones › Instrucciones con la lista de archivos y quién lee cada uno (m12-32)
Nota: el desplegable de archivos pasa a una lista a la izquierda (Tree) con dos
líneas por archivo: el nombre (o «(nuevo)» si todavía no existe, en gris) y qué
agente lo lee (CLAUDE.md · Claude Code, AGENTS.md · Codex, Antigravity…, las
reglas y workflows encontrados con el suyo). El editor y sus botones van a la
derecha, con «CLAUDE.md · Lo lee Claude Code.» arriba. «+ Regla o workflow» abre
el mismo diálogo de antes.

### Extensiones › Addons de Godot no es del agente · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** baja · **Tamaño:** M · **Etiquetas:** `ux`, `extensiones`

La tienda de addons de Godot comparte ventana con skills y MCP; el editor ya tiene su Tienda de Assets.

Propuesta: Solo lo del agente; como mucho «Del proyecto» con lo instalado.

Archivos: godot_addons_tab.gd

Informe: https://claude.ai/artifact/KsFLJqJYs2XKeoAc8BAPWH
Lienzo: https://claude.ai/artifact/3WiCtTnZP94EADbreh18ny (pantalla 6)

**Notas:** Hecho en la sesión cloud, traído a main en 375d9a2 sin atribución.
Tests: la pestaña de addons se llama «Project addons» (m12-31)
Arreglo del test test_claude_extensions.test_window_builds_offline, que seguía
esperando «Godot addons» después del cambio de nombre de m12-31.

### Extensiones: pestañas vacías o con mensajes confusos · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** media · **Tamaño:** S · **Etiquetas:** `ux`, `extensiones`

Cargando: una línea chica y 450 px vacíos. Sin agentes, Servidores MCP en blanco y Plugins dice «el perfil activo es otro agente» sin haber ninguno.

Propuesta: Filas fantasma mientras carga; sin agente, un mensaje y un botón para agregar uno.

Archivos: extensions_window.gd

Informe: https://claude.ai/artifact/KsFLJqJYs2XKeoAc8BAPWH

**Prueba:** --godot-agent-extensions-shots en Xvfb sin agentes (pasa; capturas de Plugins y Servidores MCP con la tarjeta), test_i18n.

**Notas:** Hecho en la sesión cloud, traído a main en 6764b5b sin atribución.
UX: Extensiones sin agente dice qué falta y mientras carga muestra filas fantasma (m12-30)
Nota: sin ningún perfil de agente, Plugins, Marketplaces y Servidores MCP muestran
una tarjeta «Todavía no hay un agente configurado…» con «Configurar un agente…»
(cierra Extensiones y abre Ajustes › Agentes), en vez de «el perfil activo es
otro agente» o la pestaña en blanco; en MCP siguen abajo los servidores del addon.
Mientras se cargan plugins, marketplaces o el estado de los servidores, en lugar
de una línea chica y 450 px vacíos van el texto y 2 o 3 filas grises
(ExtensionsUi.skeleton). Con un agente que no es Claude Code queda el aviso de antes.

### Extensiones › Skills: acciones como íconos sueltos · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** media · **Tamaño:** S · **Etiquetas:** `ux`, `extensiones`

Cuatro íconos sin texto por skill; el selector dice «En este proyecto» y la lista muestra «Usuario».

Propuesta: Acciones en un menú «⋯» con texto; el selector como filtro con «Todas» y secciones con su alcance.

Archivos: skills_tab.gd

Informe: https://claude.ai/artifact/KsFLJqJYs2XKeoAc8BAPWH

**Prueba:** --godot-agent-skills-test en Xvfb (crea en el proyecto, copia, importa un zip; pasa) con su captura; test_i18n.

**Notas:** Hecho en la sesión cloud, traído a main en 3e45bcf sin atribución.
UX: Extensiones › Skills con un filtro por alcance, «+ Skill» que pregunta dónde y acciones en «⋯» (m12-29)
Nota: el desplegable «En este proyecto / Para todos los proyectos» decía dónde
iban Nueva e Importar, pero parecía un filtro de la lista (y la lista mostraba
«Usuario»). Ahora es un filtro de verdad: Todas, Este proyecto, Todos mis
proyectos, De plugins. «+ Skill» es un menú con «Skill nueva en este proyecto»,
«… para todos mis proyectos» y lo mismo para importar una carpeta o zip. En cada
skill, Abrir SKILL.md, Mostrar en el gestor de archivos, Copiar a este proyecto y
Borrar… van con su nombre en un menú «⋯»; el interruptor queda a la vista. El
check del dev plugin elige el destino con `_target_scope`.

### Registro de ACP: descripciones en inglés · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** baja · **Tamaño:** S · **Etiquetas:** `ux`, `registro`

Las descripciones del registro vienen en inglés.

Propuesta: Texto propio en es.po para los sugeridos.

Archivos: acp_registry_dialog.gd, es.po

Informe: https://claude.ai/artifact/KsFLJqJYs2XKeoAc8BAPWH

**Prueba:** test_acp_registry.test_description_of, test_i18n (headless).

**Notas:** Hecho en la sesión cloud, traído a main en e27adce sin atribución.
UX: los agentes sugeridos del registro de ACP tienen descripción propia y traducida (m12-28)
Nota: el registro solo trae descripciones en inglés. Para los sugeridos (Claude
Code, Codex, Google Antigravity) la tarjeta usa un texto propio de
core/suggested_agents.gd, marcado para i18n y con su traducción en es.po; el
resto sigue con la descripción del registro (traducir decenas de textos que
cambian con cada versión del registro no se sostiene). SuggestedAgents.matching
reconoce un agente del registro por id o nombre.

### Registro de ACP: orden alfabético con lo menos útil primero · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** media · **Tamaño:** M · **Etiquetas:** `ux`, `registro`

Abre en Agoragentic, Amp y Auggie; nada dice si ya está agregado, qué cuenta pide o cuánto pesa.

Propuesta: Sugeridos y agregados arriba, después el resto; tipo de instalación y tamaño en cada tarjeta.

Archivos: acp_registry_dialog.gd

Informe: https://claude.ai/artifact/KsFLJqJYs2XKeoAc8BAPWH

**Prueba:** test_acp_registry.test_grouped_and_install_summary, test_settings_dialog, test_i18n (headless). Sin captura: el registro necesita red y acá el proxy la corta.

**Notas:** Hecho en la sesión cloud, traído a main en 43c040a sin atribución.
UX: el registro de ACP muestra primero lo agregado y lo sugerido, y cómo se instala cada uno (m12-27)
Nota: la lista se agrupa en «Ya agregados» (ids de los perfiles de Ajustes),
«Sugeridos» (Claude Code, Codex, Google Antigravity: los de
core/suggested_agents.gd, por id o nombre) y «Todos los agentes» por nombre;
el filtro se aplica antes de agrupar. Un agregado dice «✓ agregado» y su botón es
«Agregar de nuevo» (reemplaza el perfil) o «Reinstalar» si es un binario en
disco; al agregar uno, la lista se rearma y pasa arriba. Cada tarjeta dice cómo
se instala: «npx <paquete> · Node.js lo baja la primera vez», lo mismo con uvx, o
«programa para esta plataforma · se bajan 912 MB» cuando el registro trae el
tamaño (si no: «lo baja el harness»). El autor solo si lo hay.

### Ajustes: Guardar y Cancelar lejos y sin aviso de cambios · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** baja · **Tamaño:** S · **Etiquetas:** `ux`, `ajustes`

Botones separados en el medio del pie; nada marca la sección con cambios; Export deshabilitado sin decir por qué.

Propuesta: Botones juntos a la derecha, un punto en la sección con cambios, y en Export «Creá un preset de export primero».

Archivos: settings_dialog.gd

Informe: https://claude.ai/artifact/KsFLJqJYs2XKeoAc8BAPWH
Lienzo: https://claude.ai/artifact/3WiCtTnZP94EADbreh18ny (pantalla 5)

**Prueba:** test_settings_dialog.test_dirty_sections, test_i18n; captura en Xvfb (--godot-agent-settings-shots, pasa: Permisos y Servidores MCP con «•» después de que el check los cambia).

**Notas:** Hecho en la sesión cloud, traído a main en 9bd8e21 sin atribución.
UX: Ajustes con Guardar y Cancelar juntos, «•» en las secciones cambiadas y Export que dice qué falta (m12-26)
Nota: los botones del diálogo quedan juntos a la derecha (los espaciadores del
AcceptDialog dejan de estirarse y uno solo, al principio, los empuja). Al abrir se
guarda un resumen de cada sección (valores de sus controles, más los perfiles y
los servidores MCP); cada 0,3 s, mientras está abierto, la sección que difiere
lleva «• » en la lista y el tooltip «Cambiado: todavía sin guardar»; si se
vuelve al valor de antes, la marca se va. Export sin presets: «creá uno primero
en Proyecto → Exportar…», y el botón apagado dice por qué en su tooltip (también
cuando todos ya tienen el filtro).

### Ajustes › One-shot repite la pantalla de One-shot · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** baja · **Tamaño:** S · **Etiquetas:** `ux`, `ajustes`

Presupuestos y checkpoint repetidos; los umbrales de cuota quedan abajo de los criterios.

Propuesta: Acá «Valores iniciales de cada One-shot»; la cuota en su propia sección.

Archivos: settings_dialog._build_oneshot

Informe: https://claude.ai/artifact/KsFLJqJYs2XKeoAc8BAPWH
Lienzo: https://claude.ai/artifact/3WiCtTnZP94EADbreh18ny (pantalla 5)

**Prueba:** test_settings_dialog (el umbral de pausa ahora apunta a QUOTA), test_i18n; capturas de las 8 secciones en Xvfb (--godot-agent-settings-shots, pasa).

**Notas:** Hecho en la sesión cloud, traído a main en ee0c73e sin atribución.
UX: Ajustes › One-shot son los valores iniciales y la cuota tiene su sección (m12-25)
Nota: «One-shot y cuota» se parte en dos secciones. «One-shot» titula
«Valores iniciales de cada One-shot (por proyecto)» con una línea que dice que
la pantalla One-shot arranca con esos y ahí se cambian por corrida; sigue con
loops, vueltas de QA y criterios. «Cuota del plan» (nueva, después de
One-shot) tiene aviso, pausa y qué hacer al reiniciarse, con una línea sobre el
anillo; la validación de los umbrales lleva ahí. Wiki (en y es) al día.

### Ajustes › Completado: perillas de ajuste fino a la vista · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** media · **Tamaño:** S · **Etiquetas:** `ux`, `ajustes`

Umbral del ranker, margen y debounce al nivel de «Activado».

Propuesta: Activado, modo y fuentes arriba; los números en «Avanzado» plegado.

Archivos: completion_settings_page.gd

Informe: https://claude.ai/artifact/KsFLJqJYs2XKeoAc8BAPWH

**Prueba:** test_settings_dialog.test_completion_advanced_folded, test_completion_section y test_completion_save, los test_completion_* (headless); captura de Ajustes › Completado en Xvfb (--godot-agent-settings-shots, pasa).

**Notas:** Hecho en la sesión cloud, traído a main en f9086fe sin atribución.
UX: Ajustes › Completado con lo de uso arriba y las perillas en «Avanzado» (m12-24)
Nota: arriba quedan activado (usuario y proyecto), modo, atajos, las fuentes
locales, sugerencias de varias líneas y los perfiles LLM (con «marcar las
sugerencias del LLM»). En un «Avanzado: umbrales, tiempos, corpus y log»
plegado: umbral del ranker, margen, debounce local, máximo de líneas, corpus
extra y exclusiones, debounce del LLM, prefijo, sufijo, contexto del proyecto y
el log «raw». Los contadores de la sesión siguen al final. Los helpers de la
página agregan en `_target` (la página o el plegado).

### Ajustes › Servidores MCP mezcla tres temas · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** media · **Tamaño:** S · **Etiquetas:** `ux`, `ajustes`

Servidores externos con dos párrafos largos, el servidor del editor (puerto, token, máximo) y las carpetas fuera del proyecto en la misma página.

Propuesta: Solo los externos con una línea y enlace a la guía; el servidor del editor y las carpetas en «Avanzado».

Archivos: mcp_servers_page.gd, settings_dialog.gd

Informe: https://claude.ai/artifact/KsFLJqJYs2XKeoAc8BAPWH
Lienzo: https://claude.ai/artifact/3WiCtTnZP94EADbreh18ny (pantalla 5)

**Prueba:** test_settings_dialog, test_external_mcp_servers, test_i18n (headless); captura de Ajustes › Servidores MCP con un servidor en Xvfb (--godot-agent-settings-shots, pasa).

**Notas:** Hecho en la sesión cloud, traído a main en ed2126e sin atribución.
UX: Ajustes › Servidores MCP muestra solo los de otros programas y lo demás va en «Avanzado» (m12-23)
Nota: los dos párrafos del principio pasan a una línea («Herramientas de otros
programas… Se aplican desde la próxima sesión.») con un enlace «Guía» a la
sección de la wiki (Settings#other-mcp-servers, o Settings-es en español), que
ya explicaba $VAR, los servidores propios de Claude Code y /mcp. El servidor
MCP del editor (URL, puerto, token, límites), las comprobaciones de cada turno
(lista compacta, validar scripts, snapshots, PR de GitHub) y las carpetas fuera
del proyecto quedan en un «Avanzado» plegado al final. La wiki (en y es) lo dice.

### Ajustes › Permisos: 45 desplegables sin puntos de partida · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** media · **Tamaño:** M · **Etiquetas:** `ux`, `ajustes`

Matriz de 9 grupos por 5 modos con desplegables iguales; «Subagentes a la vez 0» ambiguo; nota de MCP cortada.

Propuesta: Celdas con color e ícono que cambian con un clic, marcar lo que difiere del default, «Restaurar» por columna, «0 = sin límite».

Archivos: settings_dialog._build_permissions

Informe: https://claude.ai/artifact/KsFLJqJYs2XKeoAc8BAPWH

**Prueba:** test_settings_dialog.test_matrix_cells_and_column_reset y test_matrix_overrides, test_i18n; captura de Ajustes › Permisos en Xvfb (--godot-agent-settings-shots, pasa).

**Notas:** Hecho en la sesión cloud, traído a main en ea3ae4b sin atribución.
UX: Ajustes › Permisos con celdas de color, lo cambiado resaltado y «↺» por columna (m12-22)
Nota: cada celda de la matriz dice «✓ Permitir», «? Preguntar» o «✕ Denegar» en
verde, amarillo o rojo; la que difiere del valor por defecto lleva fondo y borde
de acento y un tooltip con el default («Cambiado: por defecto es Preguntar»), y
una nota debajo lo explica. Cada columna tiene «↺», que la vuelve a los valores
por defecto (también el límite de subagentes). «Subagentes a la vez (0 = sin
límite)». Decisión: las celdas siguen siendo desplegables (dos clics) en vez de
cambiar con un clic: con tres valores, ciclar a ciegas lleva a dejar «Permitir»
sin querer; el color y el ícono ya dan el vistazo rápido. Sirve igual para las
filas de servidores MCP de terceros.

### Ajustes › Agentes: vacío sin guía y el formulario lejos · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** M · **Etiquetas:** `ux`, `ajustes`

Sin agentes, una línea sobre $VAR y dos botones. «Predeterminado» es texto que es botón, y Editar abre el formulario debajo de la lista.

Propuesta: Sin agentes, los tres sugeridos. Con agentes, lista a la izquierda y formulario a la derecha; estrella de predeterminado; la nota de $VAR junto al campo de entorno.

Archivos: settings_dialog._build_agents

Informe: https://claude.ai/artifact/KsFLJqJYs2XKeoAc8BAPWH
Lienzo: https://claude.ai/artifact/3WiCtTnZP94EADbreh18ny (pantalla 5)

**Prueba:** test_settings_dialog.test_agents_page, test_i18n (headless); captura de Ajustes › Agentes sin agentes en Xvfb (--godot-agent-settings-shots), que pasa.

**Notas:** Hecho en la sesión cloud, traído a main en ebb6759 sin atribución.
UX: Ajustes › Agentes con sugeridos, lista y formulario lado a lado y estrella (m12-21)
Nota: sin agentes, la página muestra Claude Code, Codex y Google Antigravity
con lo que pide cada uno y «Agregar» (core/suggested_agents.gd, que va a usar
también el dock en m12-15): Claude Code se arma directo (npx, queda
predeterminado si es el primero); Codex y Antigravity abren el registro de ACP
filtrado por su nombre, porque el registro da el comando de cada plataforma. Con
agentes: la lista a la izquierda (clic en la tarjeta la edita y la marca), el
formulario a la derecha, una estrella para el predeterminado (☆ → ★) y quitar
como ícono; la nota de $VAR va debajo del campo de entorno.

### Pie de turno con los cambios · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** baja · **Tamaño:** S · **Etiquetas:** `ux`, `dock`

El reporte del turno es un aviso más y se pierde.

Propuesta: Pie: «Este turno cambió 1 archivo · Ver cambios · Deshacer turno».

Archivos: SessionController._report_turn_changes

Informe: https://claude.ai/artifact/KsFLJqJYs2XKeoAc8BAPWH
Lienzo: https://claude.ai/artifact/3WiCtTnZP94EADbreh18ny (pantalla 1)

**Prueba:** test_notice_view.test_turn_footer, test_turn_snapshots, test_i18n (headless). Sin captura: ningún check del dev plugin produce un turno con cambios.

**Notas:** Hecho en la sesión cloud, traído a main en 643175a sin atribución.
UX: lo que cambió un turno va en un pie de línea con «Ver cambios» y «Deshacer el turno» (m12-20)
Nota: el aviso de los cambios del turno deja de ser una caja centrada como los
demás: es un pie (ChatEntry.footer) con una línea arriba, el texto a la izquierda
(«Este turno cambió 1 archivo (+3 −1): player.gd», con singular) y las acciones
como enlaces del color de acento: «Ver cambios», «Deshacer el turno» (antes
«Volver a antes de este turno», ahora en el tooltip) y «Guardar el reporte».

### Avisos del editor repetidos por sesión · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** baja · **Tamaño:** S · **Etiquetas:** `ux`, `dock`

«Sesión 1 espera tu permiso» y «espera tu respuesta» se apilan para la misma sesión.

Propuesta: Un aviso por sesión que se actualiza y se va al responder.

Archivos: session_tabs.gd

Informe: https://claude.ai/artifact/KsFLJqJYs2XKeoAc8BAPWH

**Notas:** Hecho en la sesión cloud «Godot agent improvements» (rama claude/godot-agent-improvements-dh5g01), traído a main en ed333af sin atribución. Revisado: tests de la rama 341/341.

### Ocho controles en la barra del composer · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** media · **Tamaño:** M · **Etiquetas:** `ux`, `dock`

@, imagen, /, anillo, 38k/200k, modo, modelo y Enviar en una fila; «Construir» parece un enlace.

Propuesta: Un «+» con archivo o nodo, captura y comando; el modo como píldora; un anillo con contexto y cuota en el tooltip.

Archivos: composer.gd

Informe: https://claude.ai/artifact/KsFLJqJYs2XKeoAc8BAPWH
Lienzo: https://claude.ai/artifact/3WiCtTnZP94EADbreh18ny (pantalla 1)

**Prueba:** test_composer.test_add_menu_and_meter (test_prompt_history con ancho fijo: con la fila más corta «segundo» se partía en dos líneas visuales), test_quota_ring, test_i18n; en Xvfb, --godot-agent-remote-test (incluye que el dock entra en su panel) y la captura de --godot-agent-ui-test=basic, que pasan.

**Notas:** Hecho en la sesión cloud, traído a main en 9aa5563 sin atribución.
UX: la barra del composer con «+», el modo como píldora y el contexto en el anillo (m12-18)
Nota: @, imagen y / pasan a un «+» con «Nodo o archivo (@)», «Imagen del juego»
(apagada si el agente no acepta imágenes) y «Comando del agente (/)»; los
botones viejos quedan ocultos. El modo es una píldora con el color de acento
(borde y fondo) en vez de texto que parecía un enlace. «38k / 200k» deja la
fila: el contexto va primero en el tooltip del anillo de cuota («Contexto: 38k
de 200k (19 %)») y vuelve a la fila solo desde el 80 %, en amarillo. Con esto la
fila queda en «+», anillo, modo, modelo y Enviar. De paso (m12-14): el check de
Remote Control busca el botón en el menú «⋯» (el botón vive oculto).

### Todo va en una caja y las herramientas se cortan · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** media · **Tamaño:** L · **Etiquetas:** `ux`, `dock`

Texto, plan, herramientas y respuesta en cajas iguales; nombres técnicos cortados (godot.connect_sig…), salida y spawner.gd:13 sueltos.

Propuesta: Texto del agente sin caja; grilla de tres columnas con nombres para personas y la salida anidada.

Archivos: conversation_view.gd, tool_group_view.gd

Informe: https://claude.ai/artifact/KsFLJqJYs2XKeoAc8BAPWH
Lienzo: https://claude.ai/artifact/3WiCtTnZP94EADbreh18ny (pantalla 1)

**Prueba:** test_tool_group_view.test_short_names_for_people, run_all; en Xvfb la captura de --godot-agent-ui-test=docs_build (antes y después) y --godot-agent-remote-test, que verifica que el dock entra en su panel.

**Notas:** Hecho en la sesión cloud, traído a main en 1b83347 sin atribución.
UX: el texto del agente sin caja y las herramientas en grilla con nombres para personas (m12-17)
Nota: el mensaje del agente ya no va en un recuadro (el estilo del RichTextLabel
del editor): se lee como texto, y las cajas quedan para el código, las
herramientas y las tarjetas. En el grupo de herramientas, las godot.* muestran un
nombre para personas («Connect signal», «Scene tree», «Set properties»; el técnico
en el tooltip) y ninguno pasa de 22 caracteres; la columna del nombre toma el
ancho del más largo del grupo, así estado, nombre y resumen quedan alineados en
tres columnas (antes el nombre era un 40 % fijo que cortaba «godot.connect_sig…»).
La salida, los diffs y los enlaces («spawner.gd:13») van anidados bajo la fila.
Decisión: la sangría de lo anidado es la de la columna de estado y no la del
resumen: con la del resumen, un diff (que ya pide su ancho) ensanchaba el dock.

### Formulario del agente: «Rechazar» y «Cancelar» confunden · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** media · **Tamaño:** S · **Etiquetas:** `ux`, `dock`

Enviar, Rechazar y Cancelar (decline y cancel en ACP); la lista obligatoria arranca en «—»; ícono de documentación.

Propuesta: «Enviar» y «No responder», Cancelar con Esc; listas con la primera opción o «Elegí…»; ícono de pregunta.

Archivos: entries/elicitation_view.gd

Informe: https://claude.ai/artifact/KsFLJqJYs2XKeoAc8BAPWH

**Prueba:** test_elicitation (el enum de 2 opciones ahora es radio y conserva el default). Sin captura nueva: el recorrido no incluye un formulario.

**Notas:** Con 6 opciones o menos, se muestran como radio con su descripción (antes: desplegable que arrancaba en «—»); la ayuda del campo va una vez (no también de placeholder); «No responder» (decline) y Esc con el foco en la tarjeta cancela; ícono NodeInfo en vez del libro de Help. Visto con un AskUserQuestion real de Claude Code.

### Primer arranque: el composer activo sin agente y la elección en Ajustes · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** media · **Tamaño:** M · **Etiquetas:** `ux`, `dock`

Sin agentes, el composer tiene main.tscn y «Construir» como si se pudiera usar; «Configurar un agente…» lleva a una lista vacía en Ajustes.

Propuesta: Los tres agentes más usados en el dock con lo que piden y «Agregar»; composer deshabilitado con «Agregá un agente para empezar».

Archivos: agent_dock._refresh_empty_state

Informe: https://claude.ai/artifact/KsFLJqJYs2XKeoAc8BAPWH
Lienzo: https://claude.ai/artifact/3WiCtTnZP94EADbreh18ny (pantalla 4)

**Prueba:** test_composer.test_unavailable_without_agent, test_i18n (headless); capturas en Xvfb: el dock sin agentes (--godot-agent-screenshot) y el login desde el dock (--godot-agent-login-test, pasa).

**Notas:** Hecho en la sesión cloud, traído a main en d7f3a99 sin atribución.
UX: primer arranque con los agentes sugeridos en el dock y el composer apagado (m12-15)
Nota: sin agentes, el dock vacío muestra «Agregá un agente para empezar:» con
Claude Code, Codex y Google Antigravity (lo que pide cada uno y «Agregar»):
Claude Code se guarda directo y queda elegido; los otros abren Ajustes y el
registro de ACP filtrado por su nombre. El botón de abajo pasa a «Otros
agentes…» (abre Ajustes). El composer queda apagado con el placeholder
«Agregá un agente para empezar» (Composer.set_unavailable; set_enabled no lo
reabre) mientras no haya ningún perfil. De paso (m12-11): si la sesión no abrió
porque falta iniciar sesión, la línea de estado dice «○ <agente> · falta
iniciar sesión» en gris, no «✗ · error» en rojo (SessionModel.login_required).

### Tres filas de controles antes del chat · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** media · **Tamaño:** M · **Etiquetas:** `ux`, `dock`

Pestañas de sesión, agente con cuatro íconos sin texto y la línea de estado que repite el agente. Dos «+» casi pegados (pestaña y sesión). Sin agentes el selector es solo «⌄».

Propuesta: Una fila: chip del agente con estado, título, historial, «+» (sesión o pestaña) y «⋯» con extensiones, ajustes, cuenta y Remote Control.

Archivos: agent_dock.tscn, session_tabs.gd

Informe: https://claude.ai/artifact/KsFLJqJYs2XKeoAc8BAPWH
Lienzo: https://claude.ai/artifact/3WiCtTnZP94EADbreh18ny (pantalla 1)

**Prueba:** run_all (351 tests; solo fallan los 4 de test_git_checkpoints que fallan como root), test_i18n; captura del dock con el agente falso en Xvfb (--godot-agent-ui-test=basic, pasa).

**Notas:** Hecho en la sesión cloud, traído a main en d6b7975 sin atribución.
UX: el dock arranca con una sola fila de controles (m12-14)
Nota: header de una fila: el chip del agente con su estado (antes la línea de
estado aparte; clic: elegir el perfil o «Administrar agentes…»), el título, el
historial, «+» con «Sesión nueva», «Pestaña nueva» y «Pestaña nueva en una copia
aparte» (el «+» de las pestañas ya no está al lado), y «⋯» con Extensiones,
Ajustes, Remote Control y Cerrar sesión (los dos últimos cuando el agente los
ofrece). La fila de pestañas aparece recién con dos sesiones. Los botones viejos
(perfil, ajustes, extensiones, la fila de estado) quedan ocultos porque los usan
los checks del dev plugin. Con una sola pestaña no hay doble clic para renombrar
(sí desde que hay dos).

### Un error del agente es un párrafo rojo sin qué hacer · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** M · **Etiquetas:** `ux`, `dock`

Todo en rojo con la ruta partida, y solo Reintentar y Abrir el log.

Propuesta: Título y causa en lenguaje claro, las últimas líneas del log con Copiar, y la acción que lo arregla. «Reinstalar» un agente del registro tiene que borrar la versión instalada antes (hoy Agregar reutiliza lo que está en disco).

Archivos: SessionController._fail, notice_view.gd, acp_registry.gd

Informe: https://claude.ai/artifact/KsFLJqJYs2XKeoAc8BAPWH
Lienzo: https://claude.ai/artifact/3WiCtTnZP94EADbreh18ny (pantalla 3)

**Prueba:** acp_session_check (161 checks, 0 fallos; el escenario crash pide título y causa), test_notice_view.test_agent_error_card, test_acp_registry.test_is_registry_binary, test_i18n. Sin captura.

**Notas:** Hecho en la sesión cloud, traído a main en 22b7990 sin atribución.
UX: un error del agente dice qué pasó, muestra el log y ofrece cómo arreglarlo (m12-13)
Nota: no arranca el comando, no contesta initialize o el proceso se cae: el
aviso trae un título («No se pudo iniciar Claude Code», «… no arrancó»,
«… se detuvo»), la causa en una línea y, en una caja monoespaciada con
«Copiar», las últimas 8 líneas del stderr del agente (ChatEntry.title y
details). Acciones: si el comando no corre, «Editar el agente» (abre Ajustes ›
Agentes) y Reintentar; si se cae, Reintentar (principal), «Reinstalar…» si el
comando es un binario bajado por el registro (abre el registro de ACP) y Abrir el
log. En el registro, un binario que ya está en disco muestra «Reinstalar»:
borra esa versión antes de bajarla (antes «Agregar» reutilizaba lo instalado).
El mensaje técnico sigue en el log y en el tooltip del estado.

### Al abrir, mostrar las sesiones anteriores y opción para continuar la última · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** M · **Etiquetas:** `ux`, `dock`, `ajustes`

Con agente configurado, el dock abre en «Sin sesión» con «Iniciar sesión». Seguir lo anterior requiere el ícono de historial, y no hay forma de que reabra la última sesión solo.

Propuesta: Lista de sesiones del proyecto (título, agente, cuándo, turnos, Continuar) con «Nueva sesión» arriba. En Ajustes › Interfaz: «Al abrir el editor: mostrar las sesiones / continuar la última».

Archivos: agent_dock._refresh_empty_state, SessionHistory.list, harness_settings.gd

Informe: https://claude.ai/artifact/KsFLJqJYs2XKeoAc8BAPWH
Lienzo: https://claude.ai/artifact/3WiCtTnZP94EADbreh18ny (pantalla 9)

**Prueba:** test_settings_dialog.test_on_open_setting, test_dock_recent.test_recent_meta, test_i18n (headless). Sin captura.

**Notas:** Hecho en la sesión cloud, traído a main en 3cb7898 sin atribución.
UX: el dock vacío muestra las sesiones anteriores y puede continuar la última al abrir (m12-12)
Nota: sin sesión, debajo de «Nueva sesión» (antes «Iniciar sesión») van las
últimas 5 sesiones del historial del proyecto: título, «agente · 29/10 03:56 ·
4 turnos» y «Continuar» (open_history_session). No con un One-shot a medias ni
sin agentes. Ajustes › Interfaz › «Al abrir el editor»: mostrar las sesiones
anteriores (default) o continuar la última (setting de usuario ui/on_open);
el plugin la retoma después de restaurar el One-shot, solo si no quedó uno activo.

### Pedir el login se ve como un error con seis botones · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** M · **Etiquetas:** `ux`, `dock`

Tarjeta roja «Authentication required (-32000)» con cuatro métodos que repiten «Sign in · Log in with…», más Retry y Open the log below.

Propuesta: Tarjeta neutra «Iniciá sesión en <agente>» con el método principal como botón y los demás bajo «Otras formas de entrar», sin código ni Reintentar.

Archivos: SessionController._login_actions, notice_view.gd

Informe: https://claude.ai/artifact/KsFLJqJYs2XKeoAc8BAPWH
Lienzo: https://claude.ai/artifact/3WiCtTnZP94EADbreh18ny (pantalla 8)

**Prueba:** tests/unit/test_notice_view.gd (headless) y acp_session_check actualizado. Sin captura.

**Notas:** Hecho en la sesión cloud, traído a main en 78f6424 sin atribución.
UX: pedir el login es una tarjeta neutra con el método principal y «Otras formas de entrar» (m12-11)

### El permiso repite el diff y el botón riesgoso va primero · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** M · **Etiquetas:** `ux`, `dock`

El mismo diff en la herramienta y en la tarjeta de permiso; «Siempre en esta sesión» primero y sin atajos.

Propuesta: Resaltar la herramienta que espera y una barra de decisión fija sobre el composer: Permitir, Denegar y «siempre» como enlace. Enter/Esc solo con el foco en la barra (en el composer Enter encola y Esc detiene el turno).

Archivos: entries/permission_view.gd

Informe: https://claude.ai/artifact/KsFLJqJYs2XKeoAc8BAPWH
Lienzo: https://claude.ai/artifact/3WiCtTnZP94EADbreh18ny (pantalla 2)

**Prueba:** test_permission_view.test_sorted_options; captura de la guía (permission) en Xvfb.

**Notas:** Hecho: orden fijo de botones por kind (sorted_options), foco en «Permitir una vez» al aparecer salvo que se esté escribiendo (Enter acepta), Esc deniega solo con el foco en la tarjeta (shortcut_context), y el diff plegado detrás de «Ver el cambio» cuando la herramienta ya lo muestra. No hecho: la barra fija sobre el composer (cambia el layout del dock; queda para cuando se rehaga el dock).

### One-shot no se adapta al ancho y se corta · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** M · **Etiquetas:** `ux`, `roto`, `oneshot`

Con el dock ancho, al centro le quedan unos 320 px: el texto se corta a los dos lados y «Iniciar One-shot» no se ve.

Propuesta: La tarjeta usa el ancho disponible y, angosta, apila las columnas con el botón siempre visible.

Archivos: agent_main_screen.tscn

Informe: https://claude.ai/artifact/KsFLJqJYs2XKeoAc8BAPWH
Lienzo: https://claude.ai/artifact/3WiCtTnZP94EADbreh18ny (pantalla 7)

**Prueba:** Captura de One-shot con el dock a 1230 px (centro de ~380 px) en Xvfb: todo visible, Iniciar One-shot incluido.

**Notas:** El formulario va en un ScrollContainer y se achica hasta 280 px (FORM_NARROW_WIDTH) en vez de quedar fijo en 640 dentro de un CenterContainer; presupuestos en HFlowContainer con SpinBox de 110 px mínimo; las casillas con autowrap.

### Alt+I: esperando no dice qué se pidió ni muestra avance · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** media · **Tamaño:** S · **Etiquetas:** `ux`, `alt-i`

«Asking the agent…» fijo en un panel vacío.

Propuesta: El pedido entre comillas, «Claude Code · líneas 15–16», indicador animado y tiempo.

Archivos: editor/inline_edit.gd

Informe: https://claude.ai/artifact/KsFLJqJYs2XKeoAc8BAPWH
Lienzo: https://claude.ai/artifact/3WiCtTnZP94EADbreh18ny (pantalla 10)

**Prueba:** test_inline_edit.test_waiting_texts (headless); test_i18n. Sin captura.

**Notas:** Hecho en la sesión cloud, traído a main en 889a52d sin atribución.
UX: Alt+I esperando muestra el pedido, el agente, un indicador y el tiempo (m12-08)

### Alt+I: «Reject» cuando no hay nada que rechazar · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** S · **Etiquetas:** `ux`, `alt-i`

Esperando, «Reject» solo esconde el panel y el turno sigue en el dock. Sin sesión, el aviso no ofrece iniciarla.

Propuesta: Esperando: «Cancelar» que cancela el turno. Sin sesión: «Iniciar con Claude Code» y el pedido sale al conectar. Propuesta: Aceptar (Enter) y Descartar (Esc).

Archivos: editor/inline_edit.gd

Informe: https://claude.ai/artifact/KsFLJqJYs2XKeoAc8BAPWH
Lienzo: https://claude.ai/artifact/3WiCtTnZP94EADbreh18ny (pantalla 10)

**Prueba:** test_inline_edit.test_where_label. Sin probar en el editor con un agente.

**Notas:** Botón según estado: Cancelar (cancela el turno con controller.cancel), Cerrar o Rechazar. Sin sesión: «Iniciar sesión» abre la de la pestaña activa (agent_dock._start_session) y reenvía el pedido. El panel repite el pedido y las líneas (where_label), parte de m12-08.

### El panel de Alt+I queda gigante y tapa el código · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** S · **Etiquetas:** `ux`, `roto`, `alt-i`

Mínimo fijo de 520 × 220 y no se achica al reabrirse: hereda el alto de la propuesta anterior (700 px negros para una línea).

Propuesta: reset_size() antes de cada popup en _show_proposal, sin alto mínimo sin diff, abrirlo debajo de la selección.

Archivos: editor/inline_edit.gd

Informe: https://claude.ai/artifact/KsFLJqJYs2XKeoAc8BAPWH
Lienzo: https://claude.ai/artifact/3WiCtTnZP94EADbreh18ny (pantalla 10)

**Notas:** reset_size() antes de cada popup en _show_proposal; el RichTextLabel del diff pide 200 px solo cuando hay diff.

### La barra del Agent Log se corta · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** media · **Tamaño:** S · **Etiquetas:** `ux`, `roto`, `log`

Con el ancho por defecto «Limpiar» queda en «Limp». Los canales son palabras de colores sin estado visible y el «3» no dice qué cuenta.

Propuesta: Canales como chips con estado, «3 entradas», Copiar/Limpiar como íconos con tooltip.

Archivos: agent_log_panel.gd

Informe: https://claude.ai/artifact/KsFLJqJYs2XKeoAc8BAPWH

**Prueba:** Captura del Agent Log en Xvfb.

**Notas:** Barra como HFlowContainer (baja de línea en vez de cortarse), canales con ● / ○ según estén prendidos, «N entradas», Copiar y Limpiar como íconos del editor con tooltip.

### El panel de Revisar tapa la conversación y no se va · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** M · **Etiquetas:** `ux`, `roto`, `dock`

Ocupa unos 230 px fijo arriba del chat, sigue después de cerrar la sesión, tapa tarjetas nuevas y muestra un hallazgo y medio cortado. El JSON de findings se ve crudo en el chat.

Propuesta: Plegarlo a una fila («Revisión · 1 bug, 1 rend · Ver»), cerrarlo con la sesión y ocultar el bloque findings ya leído.

Archivos: review_panel.gd, ReviewStore

Informe: https://claude.ai/artifact/KsFLJqJYs2XKeoAc8BAPWH

**Prueba:** Captura de la guía (docs_review) en Xvfb: una fila y el chat a la vista; review_check del plugin de dev actualizado al título del FoldableContainer.

**Notas:** Panel plegado por defecto en un FoldableContainer: el título resume alcance, archivos y contadores; se abre con un clic. La lista calcula su alto con la fila real (con 26 px fijos se veía un hallazgo y medio). Ocultar el bloque findings del chat quedó en m12-38. Cerrar el panel con la sesión no hizo falta: plegado ocupa una fila.

### «Buscando actualizaciones…» se dibuja en vertical en Addons de Godot · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** S · **Etiquetas:** `ux`, `roto`, `extensiones`

El aviso es un Label con autowrap en una columna de ancho cero: una letra por línea, y el título de la sección queda centrado en el vacío.

Propuesta: El aviso en la fila del título («En este proyecto (3) · buscando actualizaciones…»), sin autowrap o con ancho mínimo.

Archivos: godot_addons_tab.gd

Informe: https://claude.ai/artifact/KsFLJqJYs2XKeoAc8BAPWH

**Prueba:** Captura de Addons de Godot en Xvfb.

**Notas:** ExtensionsUi.muted tiene autowrap: en una fila al lado de un título expandido queda con ancho 0. Sin autowrap en «Buscando actualizaciones…» y en los «+N −M» de turn_changes_dialog.

### «Cerrar» tapa el contenido y esconde «Guardar» en Extensiones y el registro · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** S · **Etiquetas:** `ux`, `roto`, `extensiones`

En el registro de ACP y en Extensiones la lista sigue por debajo de «Cerrar». En Instrucciones el área de texto llega abajo y «Guardar» y «Agregar los datos del proyecto» quedan fuera de la ventana.

Propuesta: Que el contenido de cada pestaña quepa en el alto disponible (se encogen el scroll y el área de texto) y las acciones de la pestaña en su propia barra arriba.

Archivos: extensions_window.gd, instructions_tab.gd, acp_registry_dialog.gd

Informe: https://claude.ai/artifact/KsFLJqJYs2XKeoAc8BAPWH
Lienzo: https://claude.ai/artifact/3WiCtTnZP94EADbreh18ny (pantalla 6)

**Prueba:** Recorrido de capturas en Xvfb (Extensiones › Instrucciones y registro de ACP); prueba headless de AcceptDialog con y sin wrap_controls.

**Notas:** Causa: con wrap_controls = false, AcceptDialog acomoda su contenido solo al cambiar de tamaño; un Label con autowrap se mide primero con ancho ~0 y deja el contenido de 1873 px de alto, debajo de los botones. ExtensionsUi.refit_dialog manda NOTIFICATION_THEME_CHANGED un frame después de abrir (y al cambiar de pestaña). Verificado con captura en Xvfb: Instrucciones muestra Guardar y el registro su estado.

### Las pestañas de Extensiones no entran en la ventana · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** media · **Tamaño:** M · **Etiquetas:** `ux`, `roto`, `extensiones`

Seis pestañas en 640 px: Instrucciones queda detrás de las flechas y al llegar desaparecen Plugins y Marketplaces. Los contadores cambian mientras carga.

Propuesta: Barra lateral como la de Ajustes, con los contadores solo cuando cargaron.

Archivos: extensions_window.gd

Informe: https://claude.ai/artifact/KsFLJqJYs2XKeoAc8BAPWH
Lienzo: https://claude.ai/artifact/3WiCtTnZP94EADbreh18ny (pantalla 6)

**Prueba:** Capturas de Extensiones en Xvfb: las seis secciones a la vista.

**Notas:** TabContainer con tabs_visible = false y un ItemList a la izquierda (como Ajustes) que lo maneja; los títulos con contadores se copian a la lista. Ventana de 820 × 760 (mínimo 720 × 600). Los contadores siguen mostrando (0) mientras carga.

### One-shot: la pantalla se sigue cortando con el dock ancho (reabre m12-09) · Revisión

**Prioridad:** media · **Tamaño:** S · **Etiquetas:** `ux`

Tour de UX de v0.1.19 (cd5901d): con el dock del ancho por defecto del tour, la pantalla principal One-shot queda con ~370 px y se corta por los dos lados: «‑shot», «gent makes a plan…», los ejemplos, «Configurar un agen…» y el aviso de agente. m12-09 está en done pero el caso sigue. Propuesta: debajo de un ancho mínimo, la columna del One-shot entra en un ScrollContainer horizontal o colapsa a una sola columna con márgenes chicos; nunca recortar texto. Capturas: /tmp/claude-1000/-home-dannode-Proyectos-Godot-agent-harness--claude-worktrees-m13-17/3619cf30-0f89-4d71-9f7c-62dac5e13c95/scratchpad/ux/en/31_oneshot_angosto.png y es/31_oneshot_angosto.png.

**Decisiones:**
- ! Los ejemplos de objetivo pasan de tres LinkButton a un RichTextLabel con un [url] por ejemplo: el LinkButton no parte el texto y su ancho (unos 440 px con la escala por defecto) era el mínimo del formulario, que con el centro a ~380 px se centraba desbordando por los dos lados. · sin revisar
  Por qué: Es la única pieza del formulario sin ajuste de línea; con RichTextLabel el formulario baja de verdad hasta FORM_NARROW_WIDTH (280 px) y nada se recorta. El check del One-shot ahora angosta el centro a 340 px (no fija el ancho del dock: el centro resultante depende del dock izquierdo y de la escala) y mide con LayoutCheck.form_fits.
  Descartado: Botones planos con autowrap (sin subrayado de enlace); un ScrollContainer horizontal (el usuario pidió nunca recortar y scrollear de lado es peor); bajar FORM_NARROW_WIDTH (no arregla el mínimo real).

**Prueba:** Antes: con --godot-agent-oneshot-test angostando el centro a 340 px el dock no podía ensancharse (el formulario pedía 368 px por los LinkButton). Después: oneshot-test en Xvfb 0 fallas en en y es con el centro a 340 px (LayoutCheck.form_fits: el panel no pide más que el área y ningún control sale de ella); tests/ux_tour.sh en y es 0 fallas; run_all 524 tests 0 fallos; acp_session_check 203/0; oneshot_check 186/0. Capturas: antes /tmp/claude-1000/-home-dannode-Proyectos-Godot-agent-harness--claude-worktrees-m13-17/3619cf30-0f89-4d71-9f7c-62dac5e13c95/scratchpad/ux/es/31_oneshot_angosto.png; después …/scratchpad/m12-41/after/tour_es/31_oneshot_angosto.png y …/m12-41/after/oneshot_form_narrow.png (centro a 340 px).

**Notas:** Rama sm/m12-41, commit b580527. Los ejemplos de objetivo pasan a un RichTextLabel con [url] por ejemplo (meta_clicked pone el objetivo); los LinkButton no parten texto y su ancho era el mínimo real del formulario. LayoutCheck gana form_fits(form) y set_dock_width(dock, px) (antes era privado de ux_tour); oneshot_ui_check mide el formulario con el centro normal y angostado a 340 px (NARROW_CENTER_WIDTH, no un ancho fijo del dock: el centro depende del dock izquierdo y de la escala) y guarda <shot>_form_narrow.png. CHANGELOG Unreleased › Fixed.

### El veredicto de un playtest fallido es un bloque rojo de 15 líneas · Revisión

**Prioridad:** media · **Tamaño:** S · **Etiquetas:** `ux`

Tour de UX de v0.1.19: el aviso «Playtest: failed — …» muestra evidencia, cambios directos, detectores y pasos para reproducir todo en rojo y con el mismo peso (guia/playtest.png en y es). Es el caso que m12-13 arregló para los errores del agente, sin aplicar a los veredictos. Propuesta: tarjeta con título rojo («Playtest: falló · Los asteroides dejan de acelerar…»), cuerpo en color normal con secciones plegables (Evidencia, Detectores, Para reproducir) y las acciones (Reproducir la grabación, Ver hallazgo) abajo; el mismo molde para «Playtest: pasó» con «Guardada como regresión». Capturas: /tmp/claude-1000/-home-dannode-Proyectos-Godot-agent-harness--claude-worktrees-m13-17/3619cf30-0f89-4d71-9f7c-62dac5e13c95/scratchpad/ux/en/guia/playtest.png y es/guia/playtest.png.

**Decisiones:**
- ! El veredicto se arma como ChatEntry NOTICE con title (resultado · motivo), text (solo «Antes de confiar en esto» y el video) y sections [{title, text}] nuevas en ChatEntry, que NoticeView dibuja como FoldableContainers plegados con la cantidad en el título («Evidencia · 3»); el mismo molde para pasó/explorado/no se pudo probar. · sin revisar
  Por qué: Reusa la tarjeta con título de m12-13 y el plegado del panel de Revisar; las secciones plegadas dejan el dock legible (en 320 px la tarjeta entra entera) y lo importante para decidir (resultado, motivo, avisos) queda a la vista. ReviewStore.playtest_notice_plain() conserva el texto plano en orden para el log y las pruebas.
  Descartado: Evidencia abierta por defecto solo en «falló» (más alto en el dock, se descartó por consistencia); una sola sección «Detalles» (mezcla cosas de distinto peso); mantener todo en texto con colores (Label no mezcla estilos).

**Prueba:** run_all 523 tests 0 fallos (test_review_store: título «Playtest: failed · no salta», texto vacío sin avisos, secciones «Evidence · 1» / «To reproduce · 2», cambios directos y detectores en su sección, avisos del agente y video en el texto). acp_session_check 203/0. tests/docs_shots.sh en y es 0 fallas, con el check nuevo de DocsShots (_check_verdict_card: la tarjeta tiene título «Playtest: failed», las secciones de evidencia y pasos, un FoldableContainer por sección, plegados, y ninguno sale del dock) en ancho (480) y angosto (320). tests/ux_tour.sh es 0 fallas. Capturas: antes …/scratchpad/m12-42/before_es_playtest.png (= docs/images/es/playtest.png en cd5901d); después docs/images/{en,es}/playtest.png (commiteadas), …/scratchpad/m12-42/tour_es/guia/playtest.png (ancho) y …/tour_es/guia/playtest_angosto.png (320 px). Base: /tmp/claude-1000/-home-dannode-Proyectos-Godot-agent-harness--claude-worktrees-m13-17/3619cf30-0f89-4d71-9f7c-62dac5e13c95

**Notas:** Rama sm/m12-42 desde cd5901d, commit 6cdbf8c. ChatEntry.sections [{title, text}]; ReviewStore.playtest_notice devuelve {title, text, sections, level} y playtest_notice_plain(); SessionController._report_playtest pone title/sections y notify_entry_changed; NoticeView dibuja las secciones como FoldableContainers plegados y oculta el Label si el texto está vacío. es.po: los títulos de sección sin los dos puntos. DocsShots: _check_verdict_card y playtest_narrow_path (el tour guarda guia/playtest_angosto.png); _widen_dock(width). CHANGELOG Unreleased › Fixed. Independiente de sm/m12-41.

### Panel de Revisar: «2 bug» sin plural y chips abreviados («rend», «orden») · Revisión

**Prioridad:** baja · **Tamaño:** S · **Etiquetas:** `ux`

Tour de UX de v0.1.19: el título del panel dice «Review of tests/docs_demo/ · 1 file · 2 bug» / «2 bug» en español (review_panel.gd arma el título con la etiqueta de la categoría sin pluralizar), y los chips de categoría dicen «0 orden · 0 rend · 0 estilo»: «rend» no se entiende y «orden» tampoco sin contexto. Propuesta: plural por cantidad («2 bugs», «1 bug») con msgids separados como en «%d file»/«%d files», y nombres completos en los chips («rendimiento», «orden del código») o un tooltip con la definición. Captura: /tmp/claude-1000/-home-dannode-Proyectos-Godot-agent-harness--claude-worktrees-m13-17/3619cf30-0f89-4d71-9f7c-62dac5e13c95/scratchpad/ux/es/guia/playtest.png.

**Decisiones:**
- ! Contadores con el número adentro y dos msgids por categoría (COUNTER_ONE / COUNTER_MANY, como «%d file» / «%d files»): «1 bug» / «2 bugs», «2 order», «2 performance», «2 style»; en español «2 bugs», «2 de orden», «2 de rendimiento», «2 de estilo». Los chips van en un HFlowContainer para que bajen de línea en un dock angosto. · sin revisar
  Por qué: I18n solo tiene t(); el patrón del proyecto para plurales son msgids separados. Nombres enteros en vez de «rend»/«perf» porque los chips se leen sin pasar el mouse; «de orden» en lugar de «orden de ejecución» para que los cuatro chips entren en una fila en un dock de 480 px.
  Descartado: Ocultar los chips en cero (se pierde la leyenda); solo tooltip con el nombre entero (ya existía y no alcanzaba); «orden de ejecución» completo (demasiado largo para la fila).

**Prueba:** tests/unit/test_review_panel.gd: counter_label en en («1 bug», «2 bugs», «0 bugs», «3 performance») y es («2 bugs», «0 de rendimiento», «1 de orden», «4 de estilo»); test_i18n sigue verde (es.po sin «order»/«perf» sueltos). review-test en Xvfb en y es 0 fallas (los chips coinciden con counter_label y el título cuenta los que no son cero). Captura después: /tmp/claude-1000/-home-dannode-Proyectos-Godot-agent-harness--claude-worktrees-m13-17/3619cf30-0f89-4d71-9f7c-62dac5e13c95/scratchpad/m12-41/after/tour_es/guia/playtest.png («2 bugs · 0 de orden · 0 de rendimiento · 0 de estilo»); antes …/scratchpad/ux/es/guia/playtest.png.

**Notas:** Rama sm/m12-41, commit 1162f74. COUNTER_ONE/COUNTER_MANY con «%d …» por categoría y counter_label(severity, count) estática; _counters es HFlowContainer. es.po: «%d bug(s)», «%d de orden/rendimiento/estilo»; borrados «order» y «perf». CHANGELOG Unreleased › Fixed.

### Los prompts que manda el harness parecen escritos por el usuario (y van en inglés) · Revisión

**Prioridad:** baja · **Tamaño:** S · **Etiquetas:** `ux`

Tour de UX de v0.1.19, dock en español tras la guía: la burbuja «Keep going with the plan: the next pending task is “Movimiento y disparos de la nave”. Verify with run_scene…» (One-shot) se muestra con el mismo globo azul que un mensaje del usuario, en inglés en una UI en español. Lo mismo pasa con los prompts de reanudación, la verificación automática y los arreglos de Revisar. Propuesta: marcar las entradas de usuario que generó el harness (un rótulo «Harness» o «One-shot» chico, color apagado, texto plegado a una línea con «ver prompt»), sin traducirlas (las lee el agente). Captura: /tmp/claude-1000/-home-dannode-Proyectos-Godot-agent-harness--claude-worktrees-m13-17/3619cf30-0f89-4d71-9f7c-62dac5e13c95/scratchpad/ux/es/40_dock_tras_la_guia.png.

**Decisiones:**
- ! Prompt del harness: línea atenuada a todo el ancho del chat con «⚙ etiqueta» (cortada con «…», entera en el tooltip) y «Ver prompt»; no la burbuja del usuario a la derecha · sin revisar
  Por qué: En un dock angosto la etiqueta dentro de la burbuja ocupaba 3 líneas; a todo el ancho queda plegada en una y se distingue de lo que escribió el usuario
  Descartado: Burbuja del usuario atenuada a la derecha (se partía); aviso tipo NOTICE (se pierde que fue un prompt al agente)
- ! Criterio único: todo prompt que no es exactamente lo que escribió el usuario lleva etiqueta, vía controller.label_prompt(texto, etiqueta); la entrada y el historial guardan el msgid en inglés y se traduce al mostrar · sin revisar
  Por qué: Un registro texto→etiqueta en el controller sirve también para lo que pasa por la cola del dock o el prompt pendiente sin pasar un parámetro por cada camino; con el msgid el chat sale en el idioma de quien lo reabre
  Descartado: Parámetro harness_label en send_prompt/cola/pending (muchos caminos); inferir la etiqueta por el prefijo del texto (frágil); guardar la etiqueta ya traducida
- ! Lo que el usuario escribe tal cual sale como suyo; envuelto por el harness (pedido con el spec sin aprobar, plan editado) sale como del harness con su etiqueta · sin revisar
  Por qué: Lo que recibe el agente ya no es su texto; «Ver prompt» lo muestra entero
  Descartado: Mostrar siempre como del usuario lo que tiene texto suyo adentro

**Prueba:** Sobre cd5901d, en 4.7.2: run_all 529/0, con el test nuevo test_harness_prompts (plegado, traducido y desplegado; la entrada del usuario sin cambios; todas las etiquetas traducidas; el historial guarda y recupera la etiqueta en disco; registro del controller; la fila de la cola muestra la etiqueta). oneshot_check 190/0: inicio, cierre, cambio al spec, aprobación, QA y correcciones salen con su etiqueta y la guía del usuario sin. acp_session_check 203/0. En Xvfb, el ui-test nuevo ui_harness_prompt (tests/scripts/ui_harness_prompt.json) pasa en es y en con el ancho por defecto del dock: las dos etiquetas (chequeo del turno, supervisor) se ven enteras en hasta 2 líneas sin «…», el botón queda dentro del chat, «Ver prompt» muestra el texto en inglés y el agente recibe el mismo texto. Capturas en <shot>_harness.png y <shot>_harness_open.png. ui_demo y ui_long_permission siguen pasando en es.

**Notas:** Commits 4ba0be6 y 7c64641 (ajuste) en sm/m12-44. Ajuste pedido en la revisión: la etiqueta parte en hasta dos líneas (autowrap, max_lines_visible 2; si es más larga, «…» y la entera en el tooltip). «Ver/Ocultar prompt» va al lado si entra en una línea con la etiqueta; si no, baja a la derecha. Etiquetas más cortas en es: «Chequeo automático tras el turno», «Lo que vio el supervisor con el editor cerrado», «Edición en línea del Script Editor». HarnessPrompts (session/harness_prompts.gd) tiene las etiquetas como msgids con «# i18n». SessionController.label_prompt(texto, etiqueta) las registra y send_prompt las consume, así que también funcionan para lo que sale por la cola del dock o por el prompt pendiente. ChatEntry.harness_label queda guardado en el historial como "harness". Las etiquetas cubren: One-shot (objetivo, retomar, resumen, siguiente tarea, seguir con el objetivo, spec aprobado, cambio al spec, plan editado, informe final, aviso de bucle, evaluación de QA, correcciones de QA, apagar Remote Control), el chequeo después del turno (m11-04), las preguntas, correcciones y playtest de Revisar, la edición en línea, lo que vio el supervisor y los mensajes de otra sesión. El /usage oculto sigue sin mostrarse. Límites: si la sesión se reabre con session/load del agente, el agente devuelve user_message_chunk sin etiqueta y esos prompts vuelven a verse como del usuario; solo el replay del historial del harness las conserva. Lo que el run tenía en la cola al cerrarse el editor vuelve con la etiqueta genérica «One-shot».

### Dock angosto con pestañas: la línea de comando en el estado vacío, «(copy)» cortado y el aviso de la copia como párrafo · Revisión

**Prioridad:** baja · **Tamaño:** S · **Etiquetas:** `ux`

Capturas del sessions-test con el dock a ~220 px (varias pestañas en un monitor chico): (1) el estado «Sin sesión» muestra «npx -y @agentclientprotocol/claude-agent-acp» partido en tres líneas, un dato técnico que no ayuda a decidir nada; (2) la pestaña de la copia queda «Session 4 (co…» y se pierde justo lo que la distingue; (3) el aviso de la copia aparte es un párrafo centrado de 8 líneas con la ruta absoluta entera. Propuesta: en el estado vacío solo el nombre del agente (la línea de comando al tooltip); las copias con un ícono o badge en la pestaña en vez del sufijo; el aviso como tarjeta corta («Trabaja en una copia aparte · carpeta · rama agent/copy-…») con la ruta en un botón «Copiar ruta» o tooltip. Capturas: /tmp/claude-1000/-home-dannode-Proyectos-Godot-agent-harness--claude-worktrees-m13-17/3619cf30-0f89-4d71-9f7c-62dac5e13c95/scratchpad/ux/tabs/s_two_tabs.png y s_copy.png.

**Decisiones:**
- ! Las copias se llaman «Session N» (sin «(copy)») y se marcan con el ícono Duplicate en la pestaña, la rama en el tooltip y una marca en godot.sessions (SessionCoordinator.mark_copy) que sobrevive al renombrar · sin revisar
  Por qué: El sufijo era lo primero que se cortaba en un dock angosto y además se perdía al renombrar; los agentes que se mandan mensajes por nombre siguen viendo cuál es una copia en godot.sessions
  Descartado: Badge de texto en la pestaña (ocupa más que un ícono); dejar el sufijo y solo achicarlo; nombre de las copias «Copy N»
- ! Aviso de la copia: título «Works in a separate copy», la rama y qué pasa al cerrar en el texto, y la carpeta en el bloque plegado de la tarjeta (details) con su botón «Copiar»; los avisos INFO con título alinean el texto a la izquierda · sin revisar
  Por qué: Reusa lo que NoticeView ya tiene (título, details plegado con Copiar) sin un botón nuevo; centrado bajo un título alineado a la izquierda parecía un párrafo suelto. Cambia también la alineación del texto de otros avisos INFO con título (veredicto de playtest que pasó)
  Descartado: Botón «Copiar ruta» como acción del aviso (necesita un id de acción y su manejo en el plugin); la ruta solo en tooltip (no se puede copiar); texto centrado como antes
- ! Sin sesión, el texto bajo «No session» es el nombre del agente (display_name), con la línea de comando en el tooltip · sin revisar
  Por qué: Lo pedía la tarea; la línea de comando es un dato técnico que no ayuda a decidir. Repite el nombre del chip del agente que está arriba
  Descartado: Ocultar la línea del todo (el chip ya dice el agente); «Con Claude Code»

**Prueba:** Rama sm/m12-45 (c9599b1). test_sessions (copia marcada tras renombrar), test_session_tabs (ícono y tooltip), sessions-test en Xvfb (pestaña con ícono y rama en el tooltip, godot.sessions dice la copia, aviso como tarjeta con la carpeta plegada, estado vacío con el nombre del agente y el comando en el tooltip; capturas revisadas). suite.sh ci en 4.7.2: 13/13 PASS.

**Notas:** Las copias se llaman «Session N»: el sufijo «(copy)» se sacó (y su msgid de es.po). SessionCoordinator.mark_copy/is_copy y SessionTabs.set_copy/is_copy. PluginMain.copy_notice arma la tarjeta. NoticeView: los avisos INFO con título alinean el texto a la izquierda (afecta también al veredicto de playtest que pasó). No toca permission_broker, permission_view ni session_controller.

### Ver qué puede hacer el agente: una lista de las 80 tools godot.* en la UI · Revisión

**Prioridad:** media · **Tamaño:** M · **Etiquetas:** `ux`

Tour de UX de v0.1.19: no hay ningún lugar del editor donde el usuario vea qué tools tiene el agente (la tabla está solo en la wiki Editor-tools). Lo único visible es la casilla «Lista de tools compacta» en Ajustes › Servidores MCP › Avanzado, que presupone saber qué hay. Con 80 tools y funciones nuevas (profile_run, write_regressions_workflow, install_extension), descubrirlas depende de leer el changelog. Propuesta: pestaña «Tools» en Extensiones (o un botón en Ajustes › Servidores MCP) con la lista por grupo (leer, escena, archivos, juego, proyecto, GDExtension…), el grupo de permisos de cada una, si entra en la lista compacta, y un filtro; cada fila con la descripción que ve el agente. Captura de referencia: /tmp/claude-1000/-home-dannode-Proyectos-Godot-agent-harness--claude-worktrees-m13-17/3619cf30-0f89-4d71-9f7c-62dac5e13c95/scratchpad/ux/en/12_ajustes_2.png.

**Decisiones:**
- ! Pestaña «Tools (N)» en Extensiones (última de la navegación), con un Tree: grupos por proveedor (ToolRegistry.category_of, que sale del nombre del script del proveedor: read, scene_edit, file, run, diagnostic, validate, project, resource, tilemap, animation, api, asset, profile, session), y por tool: nombre godot.*, la primera oración de la descripción (tooltip con la entera), el grupo de permisos y una columna por modo (Preguntar, Revisar, Construir, Auto, One-shot) con ✓/?/✗ según la política del proyecto (PermissionPolicy con los overrides de project_config, sin los concedidos en sesión). Filtro por nombre, descripción, categoría y permiso. Las tools que esconde la lista compacta llevan «⋯» y una nota al pie. Accesos: menú «…» del dock («Qué puede hacer el agente (tools)…») y un botón en Ajustes › Herramientas del editor. · sin revisar
  Por qué: Extensiones ya es el lugar de «qué tiene el agente» (plugins, MCP, skills, instrucciones); un Tree plegable entra en la ventana con 80 filas y en su tamaño mínimo. La categoría sale del proveedor para no mantener una tabla aparte de 80 nombres; los permisos se leen de la misma política que usa el server, así nunca se desfasan.
  Descartado: Una página en Ajustes › Servidores MCP (está lleno y no es «qué puede hacer»); una tabla a mano en la wiki (ya existe y nadie la encuentra); exponer también las tools de MCP externos (no hay descripción sin sesión; queda para otra tarea).

**Prueba:** run_all 566 tests 0 fallos (test_tools_tab, test_tool_summaries, test_tool_registry.test_catalog, test_claude_extensions con 7 pestañas, test_i18n). tests/ux_tour.sh en y es 0 fallas; tras los ajustes, es 0 fallas: capturas /tmp/claude-1000/-home-dannode-Proyectos-Godot-agent-harness--claude-worktrees-m13-17/3619cf30-0f89-4d71-9f7c-62dac5e13c95/scratchpad/m12-46/tour4_es/26_extensiones_6.png (normal) y 27_extensiones_tools_angosto.png (min_size), con «Qué hace» en español y las categorías enteras. Antes: no existía la pestaña (ux/en/12_ajustes_2.png); primer intento con cinco columnas (m12-46/tour_es/26_extensiones_6.png) y con resumen en inglés (tour2_es/26_extensiones_6.png).

**Notas:** Rama sm/m12-46 desde sm/next2 (34f7541), commit cf07d6f (integrado). Ajustes en sm/m12-46b desde sm/next2 (e24b94d): mcp/tool_summaries.gd con una línea corta por tool (81, # i18n, es.po) que la pestaña muestra traducida, con «Lo que lee el agente:» y la descripción entera en el tooltip; test_tool_summaries exige una línea por cada McpTool.create de mcp/tools/ y ninguna de más; las columnas Tool y Qué hace se reparten el ancho (mínimos 172/120) y las categorías largas se acortaron («Correr el juego», «Proyecto», «API de Godot», «Sesiones») para que entren enteras en la ventana mínima. ToolRegistry: _categories por proveedor (provider_category: «read_tools.gd» → «read»), category_of(), catalog() {name, category, group, summary, description, extended}. ui/extensions/tools_tab.gd: Tree con Tool · Qué hace · Permiso · Por modo (✓/?/✗ en orden Preguntar, Revisar, Construir, Auto, One-shot; tooltip modo por modo), categorías plegables con cantidad, filtro, contador, ⋯ y nota para las que esconde la lista compacta. ExtensionsWindow: ExtensionsTab.TOOLS (última), providers, título «Tools (N)». plugin: providers (PermissionPolicy con project_config.permissions), _open_extensions(tab), dock.tools_requested, settings_dialog.show_tools. Dock: «Qué puede hacer el agente (tools)…» en el menú …. Ajustes › Herramientas del editor: «Ver la lista de tools…». ux_tour: captura extra con la ventana en min_size. CHANGELOG Added. Fuera de alcance: tools de servidores MCP externos.

### El estado del juego y del One-shot solo se ve en el tooltip del chip · Revisión

**Prioridad:** baja · **Tamaño:** S · **Etiquetas:** `ux`

Tour de UX de v0.1.19: el tooltip del encabezado (m13-29) dice «Game: running · 12 s», pero nada invita a pasar el mouse por el chip del agente, y la línea de estado arriba del composer solo habla de la sesión («Working…»). Propuesta: mientras hay un juego lanzado por run_scene, la línea de estado suma su estado («● Working… · game running 12 s»; «game stopped in the debugger» en ámbar), y un aviso corto cuando el juego queda parado en el depurador más de unos segundos; el tooltip queda para el detalle. Captura de referencia: /tmp/claude-1000/-home-dannode-Proyectos-Godot-agent-harness--claude-worktrees-m13-17/3619cf30-0f89-4d71-9f7c-62dac5e13c95/scratchpad/m13-29_en_header_tooltip.png.

**Decisiones:**
- ! Un chip por máquina en marcha junto a la línea de estado de arriba del composer (fila HFlowContainer: en un dock angosto bajan de línea): «Game · running · 12 s», «One-shot · fase · etapa · N s». Salen del mismo proveedor machine_states del tooltip (m13-29), que gana dos claves: live (se muestra: juego en LAUNCHING/STARTED/PROBE_READY/BREAKED, One-shot activo) y alert (ámbar: juego parado en el debugger; One-shot en pausa por cuota, limitado o esperando confirmación). Un Timer de 1 s del dock los refresca (la antigüedad corre y el estado del juego cambia sin que la sesión cambie). Tooltip = el del encabezado. Sin máquinas en marcha, sin chips. · sin revisar
  Por qué: La línea de estado es el lugar que ya se mira; un chip aparte de la Label evita mezclar colores y se pliega en angosto. Reusar el proveedor (sin copias) cumple D61: los estados se leen de las máquinas en el momento. «Ended» no se muestra: un chip que dice «terminó» durante 40 s es ruido; el tooltip lo conserva.
  Descartado: Texto dentro de la misma Label de estado (un solo color, se corta con ellipsis en angosto); un aviso en el chat cuando el juego queda parado en el debugger (m11-55 ya lo hace para runs manuales; para runs del agente el agente lo resuelve y el chip en ámbar alcanza); refrescar solo con el tick de cuota (no corre sin datos de cuota).
- ! El chip de estado del juego también aparece en los runs manuales (F5/F6), con «corriendo, lanzado a mano sin la sonda de playtest» si no hay probe · sin revisar
  Por qué: El usuario ve en el chip el mismo estado que el agente lee con describe_run_state; ocultarlo en los runs manuales escondería un juego parado en el debugger. El CHANGELOG y la wiki lo dicen (revisión de sm/next2, #12)
  Descartado: Ocultar el chip cuando el run no es del harness (harness_run = false)

**Prueba:** run_all 562 tests 0 fallos (test_machine_chips: solo las máquinas live, texto «Game · running · 12 s», alerta del One-shot esperando, sin edad sin segundos, sin máquinas sin chips). acp_session_check 203/0. En Xvfb, --godot-agent-ui-test=ui_markdown en y es PASS con el check nuevo _check_machine_chips: sin juego no hay chip; con un run (manual, el debugger lo ve igual) aparece un chip «Game · … · N s» con el tooltip del encabezado; LayoutCheck.dock_fits pasa con el dock a 480 y a 300 px; al parar el juego el chip se va. Capturas en /tmp/claude-1000/-home-dannode-Proyectos-Godot-agent-harness--claude-worktrees-m13-17/3619cf30-0f89-4d71-9f7c-62dac5e13c95/scratchpad/m12-47/: ui_{en,es}_game_chip.png (480 px) y ui_{en,es}_game_chip_narrow.png (300 px); antes: ui_{en,es}_state.png (línea de estado sola) y m13-29_en_header_tooltip.png (solo tooltip).

**Notas:** Rama sm/m12-47 desde sm/next2 (a25b11b), commit 89353de. plugin._machine_states suma live (juego en LAUNCHING/STARTED/PROBE_READY/BREAKED; One-shot activo) y alert (BREAKED; One-shot en PAUSED_QUOTA/LIMITED/WAITING_CONFIRM). AgentDock: _state_row (HFlowContainer) con _state_line y _machine_chips; machine_chips(states) estática; _refresh_machine_chips desde _refresh_state_line y un _machines_timer de 1 s; tooltip = header_tooltip(); color WARNING en alerta, MUTED si no; «ended»/«no game launched» no se muestran (quedan en el tooltip). Dev plugin: _check_machine_chips en el ui-test (ui_markdown) con capturas _game_chip y _game_chip_narrow. CHANGELOG Added. No agregué el aviso en el chat cuando el juego queda parado en el debugger: m11-55 ya lo hace para runs manuales y en runs del agente el chip en ámbar alcanza (decisión registrada).

### Regresiones y CI workflow: nada los anuncia hasta que aparecen en el panel · Revisión

**Prioridad:** baja · **Tamaño:** S · **Etiquetas:** `ux`

Tour de UX de v0.1.19: «Correr regresiones (N)» y «CI workflow…» solo existen en el panel de hallazgos cuando ya hay regresiones guardadas; el veredicto de un playtest que pasa no dice que dejó una, así que el usuario no sabe que la función existe hasta que la ve. Propuesta: el aviso «Playtest: pasó» termina con «Guardado como regresión · Correr regresiones · CI workflow…» (acciones del aviso), y la primera vez que se guarda una regresión un aviso de una línea explica qué son y dónde quedan. Captura de referencia: /tmp/claude-1000/-home-dannode-Proyectos-Godot-agent-harness--claude-worktrees-m13-17/3619cf30-0f89-4d71-9f7c-62dac5e13c95/scratchpad/ux/en/guia/playtest.png.

**Decisiones:**
- ! El aviso «Playtest: pasó» suma la línea «Guardado como regresión: el harness puede repetirlo sin el agente» y dos acciones del aviso: «Correr regresiones (N)» (una repetición) y «CI workflow…», con los mismos ids que el panel de hallazgos (SessionController.ACTION_RUN_REGRESSIONS / ACTION_REGRESSIONS_WORKFLOW, que AgentDock ahora alias; el plugin ya los maneja). La primera regresión del proyecto deja además un aviso INFO de una vez que explica qué son, que corren sin tokens, dónde viven (.godot_agent/playtests/regressions) y qué hace el workflow de CI. · sin revisar
  Por qué: Es el momento en que la función aparece: anunciarla ahí evita que el usuario la descubra solo cuando el panel ya la muestra. Una vez por proyecto (cuando list() queda en 1) y no por sesión, para no repetir.
  Descartado: Solo el texto sin acciones (hay que ir al panel); un aviso cada vez que se guarda una (ruido); una guía en la wiki (nadie la ve en el momento).

**Prueba:** run_all 567 tests 0 fallos (test_regression_notice: regression_notice_parts con ids, etiqueta «Run regressions (N)», data 1, traducción; y el flujo entero por SessionController._report_playtest con un run_scene en el modelo y una carpeta temporal de regresiones: el veredicto «Playtest: passed · …» dice «Saved as a regression» con las dos acciones, la primera vez deja el aviso «First regression saved…» (INFO), la segunda solo el veredicto con «Run regressions (2)», y un playtest fallido no deja nada). acp_session_check 203/0. Sin captura: ningún guion del agente falso tiene un playtest que pase con script de regresión (docs_playtest falla a propósito).

**Notas:** Rama sm/m12-48 desde sm/next2 (e24b94d), commit 55e6f80. SessionController: ACTION_RUN_REGRESSIONS/ACTION_REGRESSIONS_WORKFLOW (AgentDock los alias), regression_notice_parts(saved) estática, regressions_dir inyectable (PlaytestRegressions.new(regressions_dir)), _report_playtest suma la línea y las acciones al veredicto y el aviso INFO de la primera regresión. es.po: el msgid viejo «Saved: «Run regressions»…» se reemplaza por «Saved as a regression: the harness can replay it without the agent.» más el de la primera regresión. CHANGELOG Added.

### Primer uso: verificar que «Agregar» lleve directo al login y al primer mensaje · Revisión

**Prioridad:** media · **Tamaño:** S · **Etiquetas:** `ux`

Tour de UX de v0.1.19: la pantalla sin agentes es clara (tres sugeridos, «Agregar», tres pasos). Lo que no se pudo verificar con el agente falso es el camino real después de «Agregar»: ¿arranca la sesión sola o hay que tocar «Iniciar sesión»? ¿la descarga de npx muestra progreso «acá» como promete el paso 1? ¿la tarjeta de login aparece sin otro clic? Contado a mano, el camino mínimo instalar → login → primer mensaje son 6 interacciones (activar plugin, Agregar, Iniciar sesión, Sign in, pegar código, escribir) si «Agregar» no arranca la sesión, y 4 si la arranca. Hacer: probar a mano con Claude Code sin login (cuenta nueva), anotar los pasos reales y, si son más de 4, que «Agregar» arranque la sesión y que el estado «Descargando…» se vea en la lista de pasos. Captura: /tmp/claude-1000/-home-dannode-Proyectos-Godot-agent-harness--claude-worktrees-m13-17/3619cf30-0f89-4d71-9f7c-62dac5e13c95/scratchpad/ux/en/01_dock_sin_agentes.png.

**Decisiones:**
- ! Verificado en el código: «Agregar» guardaba el perfil y lo dejaba activo, pero no arrancaba la sesión (add_suggested_agent sin start_session), así que el camino real era 6 interacciones (activar plugin, Agregar, Iniciar sesión, Sign in, pegar código, escribir) y el paso 1 de la guía prometía un progreso que recién aparecía al iniciar la sesión. Cambio: «Agregar» llama a start_session() (npx descarga y la tarjeta de login llegan solos) y el paso 1 dice que la sesión arranca sola y que la primera vez se descarga. Camino: 5 interacciones (4 en el dock). Verificación en vivo sin tokens con tests/first_run_check.sh: Godot self-contained sin agentes, CLAUDE_CONFIG_DIR vacío y sin API key, el check --godot-agent-first-run-test aprieta Add, exige STARTING enseguida y LOGIN_REQUIRED con la tarjeta y su botón principal, y guarda tres capturas. · sin revisar
  Por qué: Era la única interacción sin valor propio del primer uso; arrancar la sesión al agregar es lo que el paso 1 ya describía. El login no se puede evitar (es del agente) ni probar más allá de la tarjeta sin una cuenta.
  Descartado: Mostrar el progreso de npx línea por línea en el chat (va al Agent Log; la línea de estado «conectando…» alcanza); dejar «Iniciar sesión» como estaba y solo corregir el texto (seguía siendo un clic de más).

**Prueba:** tests/first_run_check.sh godot <prefijo> en|es: Godot self-contained, proyecto limpio sin agentes, HOME y CLAUDE_CONFIG_DIR vacíos, sin variables CLAUDE*/ANTHROPIC*. «Add» arranca la sesión sola (STARTING al toque, READY en ~7 s con npx en caché vacía), el primer mensaje recibe authRequired y aparece la tarjeta de login con «Claude Subscription» a la vista. Pasa en en y es. acp_session_check: escenario login_at_prompt (auth_turn.json) verifica que el prompt se reenvía después del login. run_all 573/0, acp_session_check 212/0, ui-test ui_markdown ok.

**Notas:** Commit e6d6eed en sm/m12-49 (desde sm/next2 08baece). Hallazgo: claude-agent-acp 0.105 abre la sesión sin credenciales y pide login recién en el primer prompt. Por eso ahora el prompt que pidió login se guarda y se reenvía solo al iniciar sesión («Signed in. Sending your message again.»). Camino mínimo: activar el plugin, Add, primer mensaje, «Claude Subscription» (navegador), pegar el código: 5 interacciones (antes 6), 4 en el dock. Con el dock angosto, mientras conecta solo se ve el punto ámbar: la línea de estado con la pista de descarga aparece con el dock ancho.

## M11 — Revisiones de seguridad, patrones y arquitectura  (31/31, 21 en revisión)

Después de la revisión de UX: revisar el addon entero en seguridad (lo que el agente puede hacer en la máquina y en el proyecto), patrones de Godot y arquitectura, y dejar cada hallazgo como tarea con su arreglo.

**Hecho cuando:**
- Las tres revisiones tienen su informe y cada hallazgo quedó como tarea hecha o descartada con su motivo.

### Dejar de soportar Godot 4.6 · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** media · **Tamaño:** M · **Etiquetas:** `compatibilidad`

Pedido del usuario (29/10): el mínimo pasa a 4.7. Sacar lo que solo existe por 4.6 (la recarga de escenas sin EditorInterface.get_unsaved_scenes, la API vieja de docks donde 4.7 ya tiene EditorDock), la matriz de CI (4.6.3), README, CONTRIBUTING, la wiki y la spec; decisión nueva en docs/decisions.md que reemplaza a D34. Con 4.7 se puede usar Control.custom_maximum_size.

**Prueba:** run_all 369/369 en 4.7.2 y 4.8-beta1; external-test y ux_tour en Xvfb en 4.7.2 (dock, Agent Log y One-shot montados); plugin_cycle_check pasa en 4.8 y en 4.7.2 falla igual que antes del cambio («3 resources still in use at exit»)

### API pública del dock y EditorInterface inyectado (A5, A6) · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** baja · **Tamaño:** S · **Etiquetas:** `arquitectura`

plugin.gd llama dock.call(&"_on_new_session_pressed") y dock.call(&"_start_session"): hacerlos públicos. acp_registry, i18n, asset_store y error_collector leen EditorInterface solos: que el plugin se lo pase.

Informe: docs/revisiones/arquitectura.md

**Prueba:** run_all 372 (solo test_completion_local); acp_session_check 162; oneshot_check 130; plugin_cycle_check 4.8 pasa (4.7 falla igual que antes); en Xvfb con el editor en «es», el sistema en inglés y sin GODOT_AGENT_LANGUAGE, el dock sale en español

**Notas:** A5: start_session/new_session públicos en el dock; también ensure_identity/add_pathspec de GitCheckpoints. A6: I18n recibe el idioma del editor (y se arregló que con «auto» usaba el del sistema en 4.7+, porque la clave pasó a localization/); AcpRegistry recibe install_root; ErrorCollector se mudó a editor/ (lee el Output y el Debugger: es un adaptador del editor). AssetStore queda como está: su paso de instalar es por definición una acción del editor (prender plugins, scan) y lo puro (plan, manifiesto, releases compatibles) ya es estático y tiene tests.

### Una vista por sección del dock (A4) · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** media · **Tamaño:** M · **Etiquetas:** `arquitectura`

agent_dock.gd arma encabezado, estado, historial, revisión, Remote Control, diálogos de login y exportar e importación de GitHub. Cada sección en su script con señales hacia el dock.

Informe: docs/revisiones/arquitectura.md

**Prueba:** run_all 372 (solo test_completion_local); en Xvfb 4.7.2: remote-test, review-test (0 fallas tras el arreglo), history-test y ux_tour pasan; la captura del primer arranque es idéntica

**Notas:** agent_dock.gd 1615 → 1310 líneas. Vistas nuevas: remote_control_banner.gd, first_run_guide.gd, recent_sessions.gd; review_panel.gd suma exportar a CLAUDE.md e importar de GitHub. Se fueron los botones Remote/Sign out ocultos que guardaban estado. Quedan en el dock, por ser su núcleo o estar en el .tscn: header y chip, estado, historial, cola, contexto del prompt, el aviso de export presets y el diálogo del código de login. De paso: review_check fallaba desde m12-03 (panel plegado); arreglado.

### plugin.gd solo arma (A3) · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** media · **Tamaño:** M · **Etiquetas:** `arquitectura`

Sacar del plugin la coordinación del One-shot con el dock, los cambios por turno y las pestañas de sesión hacia sus dueños (OneShotRun/pantalla, TurnSnapshots, SessionTabs/SessionCoordinator); el plugin crea y conecta.

Informe: docs/revisiones/arquitectura.md

**Prueba:** run_all 372 (solo test_completion_local); oneshot_check 130; acp_session_check 162; en Xvfb 4.7.2: sessions-test, oneshot-test y external-test pasan; plugin_cycle_check 4.8 pasa

**Notas:** plugin.gd 1420 → 1265 líneas. Siguen en el plugin, por ser armado: _make_controller, abrir/cerrar pestañas y el destino de una copia (diálogos del editor). sessions-test pasa con la copia del proyecto como repo git (sin git falla igual con el código anterior: no puede crear el worktree).

### Un adaptador por agente (A1) · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** L · **Etiquetas:** `arquitectura`

Lo propio de cada agente (comando y lectura de la cuota, cómo saber la cuenta, tipo de extensiones, archivos de instrucciones, «¿es Claude?») está repartido entre session_controller, quota_monitor, skill_catalog, claude_extensions, plugin y agent_dock, con ramas por nombre. AgentAdapter (RefCounted, estrategia) con matches(agent_info, profile) y lo que cambia por agente, más uno genérico; el controller lo pide al conectar. Sumar un agente = un archivo.

Informe: docs/revisiones/arquitectura.md

**Prueba:** test_agent_adapters (4 tests); run_all 368; acp_session_check 162/0; contra agy 1.4.3 real: adaptador antigravity, /usage leído al abrir y tras el turno (semana 18 %, 5 h 0 %).

**Notas:** Hecho en 482e020. session/agents/: agent_adapter.gd (genérico), claude_adapter.gd, antigravity_adapter.gd, codex_adapter.gd y agent_adapters.gd (elige por perfil y, después de initialize, por agentInfo.name). El controller usa adapter.quota_command/read_quota/model_changed/reads_account_from_cli; el plugin, adapter.session_meta y kind para Extensiones; el dock, adapter.api_key_variable. La detección por comando sigue en ClaudeExtensions.agent_kind (la usan las extensiones). Sin probar contra agy real: la instalación pide login.

**Bloquea a:** SessionController como fachada (A2)

### Revisión de arquitectura · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** media · **Tamaño:** L · **Etiquetas:** `revision`, `arquitectura`

Revisar la estructura del addon: el tamaño y las responsabilidades de session_controller.gd, plugin.gd y agent_dock.gd, el acoplamiento entre sesión, dock y plugin, dónde vive el estado (EditorSettings, project_config.tres, user://), cómo se suman agentes nuevos (Claude, Antigravity, Codex) sin ramas por nombre, y la cobertura de tests por capa. Informe con propuestas y una tarea por cambio.

**Prueba:** Revisión: medición por carpeta (líneas, uso de EditorInterface y de UI), ramas por nombre de agente, accesos a privados, funciones más largas de plugin.gd, tests por capa.

**Notas:** Informe en docs/revisiones/arquitectura.md (A1–A8). Las capas están limpias (acp, transport, oneshot y extensions no tocan el editor). Propuestas cargadas como tareas: m13-04 (adaptador por agente), m13-05 (controller como fachada, bloqueada por m13-04), m13-06 (plugin solo arma), m13-07 (una vista por sección del dock), m13-08 (API pública del dock y EditorInterface inyectado). Estado (A7) y tests (A8) sin cambios necesarios.

### Revisión de patrones de Godot · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** media · **Tamaño:** L · **Etiquetas:** `revision`, `patrones`

Revisar el GDScript del addon contra los patrones de Godot 4: ciclo de vida de nodos y RefCounted (ciclos de referencias como el del crash de 4.8), await y señales que sobreviven al nodo, call_deferred, @tool y recarga de scripts en caliente, Resources compartidos, Window/AcceptDialog y layout (wrap_controls, autowrap), y rendimiento en el editor. Informe y una tarea por hallazgo.

**Prueba:** run_all: 364 tests (test_atomic_file, test_acp_client.test_cancelled_requests_are_capped, el runner probado con un test que falla a propósito); un error de script ahora falla el test.

**Notas:** Informe en docs/revisiones/patrones.md (P1–P7). Arreglados P2–P7 en df66c50 y P1 en parte (preautorización en session/preauthorizations.gd, siguiente commit). P2: lo que espera un permiso o una pregunta sigue en el frame siguiente (salvo pedido retirado por el agente). P3: run_all falla los tests con errores de script (Logger). P4: guardas tras los await del dock. P5: AtomicFile.write_text. P6: tope de 256 en _cancelled_outgoing. P7: el completado apaga _process cuando está apagado. El resto de P1 pasa a m13-03 con el orden propuesto en el informe.

### Revisión de seguridad del addon · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** L · **Etiquetas:** `revision`, `seguridad`

Revisar todo lo que el agente o un tercero puede hacer a través del harness: terminales y preautorización (como el command_key de eae1e13), fs/*, permisos por modo y reglas de Auto, el servidor MCP local (token, puerto, límites), instalación de agentes del registro (descargas, sha256, permisos de archivos), elicitation (URLs), extensiones y marketplaces, secretos en perfiles y en el log, y el export. Informe con hallazgos ordenados por gravedad y una tarea por hallazgo.

**Prueba:** test_fs_handler.test_symlinks_out_of_the_project, test_tool_registry.test_copy_from_outside_asks_as_shell, test_acp_registry.test_safe_relative_paths, test_asset_store (entradas nuevas), run_all (362 tests; solo los 4 de root), acp_session_check 162/0.

**Notas:** Hecho en la sesión cloud, traído a main en d3b48c6 sin atribución.
Seguridad: informe de la revisión y arreglos de rutas, permisos y log (m13-01)
Informe en docs/revisiones/seguridad.md (S1–S14). Arreglados:
- S1: fs/* y godot.move_file/delete_file ya no siguen enlaces simbólicos que
  salen del proyecto (FsHandler.link_escape).
- S2: godot.copy_file desde fuera del proyecto pide como un comando de shell
  (McpTool.group_resolver): en Auto pregunta.
- S4: registro de ACP: entradas del zip con «\» y un `cmd` que sale de la
  carpeta de instalación se descartan (AcpRegistry.is_safe_relative).
- S5: Asset Store: entradas del zip con «\» o con unidad se descartan.
- S6: el token MCP de cada pestaña también se tapa en el Agent Log.
A decidir: S3 (en Auto, `godot --headless *` permitido + edición permitida
corre cualquier código sin preguntar); el informe propone opciones.

### SessionController como fachada (A2) · Hecho

**Terminada:** 2026-10-29 · **Prioridad:** alta · **Tamaño:** L · **Etiquetas:** `arquitectura`

Separar en colaboradores inyectados, en este orden y con los tests pasando en cada paso: PermissionBroker (authorize, _ask_user, _on_request_permission, autorizador de terminales, Preauthorizations), UsageQuery sobre el adaptador de A1, SessionLifecycle (new, load, resume, list, close, delete, historial). La API pública del controller no cambia.

Informe: docs/revisiones/arquitectura.md

**Prueba:** run_all 370 en 4.7.2 (solo test_completion_local, conocido) y 4.8-beta1 (0 fallos); acp_session_check 162, oneshot_check 130, subagents_session_check; plugin_cycle_check en 4.8 sin huérfanos; test nuevo test_usage_query

**Notas:** Hecho en tres pasos: PermissionBroker (2d955e7), UsageQuery (ffbe7c8) y SessionCatalog (e37865d). session/new, load y resume siguen en el controller: dependen del proceso, la generación de la conexión, los errores y el login; separarlas pediría una referencia de vuelta al controller (ciclo de RefCounted) o una docena de callables. SessionController: 1566 → 1137 líneas. La API pública no cambió, salvo los estáticos normalize_agent_session y merge_session_lists, que ahora son de SessionCatalog (dos llamadas actualizadas).

**Bloqueada por:** Un adaptador por agente (A1)

### plugin_cycle_check falla en 4.7.2: «3 resources still in use at exit» · Revisión

tests/plugin_cycle_check.gd (habilita y deshabilita el plugin 5 veces en un editor headless) falla en 4.7.2 con «ERROR: 3 resources still in use at exit»; en 4.8-beta1 pasa. Ya fallaba antes de m13 (probado con el código anterior). El CI no corre este check: sumarlo a la matriz cuando pase. Con --verbose se ve qué recursos quedan.

**Prueba:** plugin_cycle_check pasa en 4.7.2 (antes: 3 resources still in use); run-test en Xvfb 0 fallas; run_all 372 (solo test_completion_local)

**Notas:** Causa: RunTools conectaba las señales del PlaytestDebugger a lambdas que lo capturan; el debugger guardaba las lambdas y RunTools al debugger, y el ciclo no se liberaba (se veía en 4.7.2; 4.8-beta1 no lo reportaba). Arreglo: métodos en lugar de lambdas. El ciclo del plugin entra al CI.

### Máquina de estados explícita del run del juego (run_tools) · Revisión

**Prioridad:** alta · **Tamaño:** M · **Responsable:** agent-harness-f3

run_tools.gd lleva el ciclo de vida de un run_scene en `_busy` + claves de un Dictionary (`started`, `ready`, `stopped`, `breaked`) y un escape por tiempo (`busy_is_stale`) porque si un run muere nadie baja `_busy`: el agente queda bloqueado minutos con «already in progress». Hacer un enum GameRunState (IDLE, LAUNCHING, RUNNING, BREAKED, STOPPED…) con un solo setter, tabla de transiciones permitidas (una transición ilegal se loguea en el Agent Log, no se bloquea), `_busy` derivado del estado y bajado siempre al salir de _run_scene. El error de run_scene dice el estado y hace cuánto («launching, 3 s»). busy_is_stale queda como red. Test unitario que recorre la tabla. Sin cambio de comportamiento para lo que ya anda.

**Decisiones:**
- ! GameRunState con tabla de transiciones; busy_is_stale se conserva como red de seguridad; un LAUNCHING nuevo siempre reinicia el run y espera el stop del juego anterior (registrado por a3 en el cierre del tablero, a partir de las notas de f3 y la revisión de 3c) · sin revisar
  Por qué: El ciclo de vida del run vivía en _busy más claves sueltas de un Dictionary, y si un run moría nadie bajaba _busy: el agente quedaba bloqueado con «already in progress». Un enum con su tabla hace explícito cada paso y el canal state del Agent Log deja rastro de lo que no estaba previsto. busy_is_stale queda igual: si algo se pierde, el escape por tiempo sigue destrabando. La revisión de 3c sumó que un LAUNCHING nuevo reinicie siempre y espere el session_stopped del juego anterior (una carrera que ya existía), y que el texto al agente diga el estado y el tiempo («game: running (3 s)»).
  Descartado: Quitar busy_is_stale al tener la tabla (descartado: es la red si un estado no llega); mantener el Dictionary y solo arreglar el caso del run muerto.

**Prueba:** tests/unit/test_run_tools.gd: test_game_run_transitions (la tabla cubre cada estado, run_state se asigna en un solo lugar, sin claves de ciclo de vida en _state) y test_game_run_reached. En sm/integration con flock: run_all 453/3336, acp_session_check 175, oneshot_check 140, y en Xvfb run-test, review-test, external-test, oneshot-test, queue-test, login-test e i18n-test (es): todos PASS. run-test sin transiciones inesperadas en el canal state.

**Notas:** Rama worktree-m13-11 (392f20e) + 55c41e6 en sm/integration con la revisión de 3c: un LAUNCHING nuevo siempre reinicia el run, run_scene espera el session_stopped del juego que paró antes de pasar a LAUNCHING (había una carrera que ya existía antes), y el texto para el agente es «game: running (3 s)». busy_is_stale queda como red. Se agregó el canal state del Agent Log (CH_STATE, color #ff8fb8), que comparten m13-12 y m13-13. Hallazgo de infraestructura: user:// es el mismo para todos los worktrees, así que los checks se pisan en paralelo → m13-17.

### One-shot: tabla de transiciones de RunPhase y flags que son fases · Revisión

**Prioridad:** alta · **Tamaño:** L · **Responsable:** agent-harness-d5

oneshot_run.gd tiene RunPhase (11 fases) pero el estado real se reparte en flags: `_awaiting_spec`, `_resume_qa`, `_continue_after_cancel`, `_suspended`, `_generator_session_id` (evaluador activo), `_quota_checkpoint_done`, y `_turn_running` duplica el PROMPTING de la sesión. Cargar un run guardado asigna `phase` directo (línea ~1543) sin pasar por `_set_phase` (no guarda ni emite). Hacer: tabla de transiciones permitidas junto al enum, `_set_phase` loguea una transición ilegal en el Agent Log sin bloquearla, la carga pasa por el setter, `_awaiting_spec` y `_resume_qa` como estado persistido coherente, `_turn_running` derivado de la sesión si es posible sin romper. Test unitario que recorre la tabla; oneshot_check.gd tiene que seguir pasando.

**Decisiones:**
- ! _awaiting_spec y _resume_qa pasan a un enum RunStage {SPEC_APPROVAL, BUILDING, EVALUATION} con setter, STAGE_TRANSITIONS y "stage" en el guardado (los guardados viejos se leen con awaiting_spec/resume_qa) · sin revisar
  Por qué: Son excluyentes (la QA solo llega después de aprobar el spec) y describen en qué parte del trabajo está el run, no si corre o espera: como fases nuevas multiplicarían PAUSED/LIMITED por etapa. Un solo valor persistido evita combinaciones incoherentes.
  Descartado: Dejar los dos bools con invariantes documentadas; fases nuevas (PAUSED_QA, SPEC_WRITING…)
- ! _turn_running se queda como flag propio (documentado), no se deriva de SessionState.PROMPTING · sin revisar
  Por qué: send_prompt espera cuota, snapshot y modo antes de pasar a PROMPTING y el run sigue en el turno hasta que vuelve el await; derivarlo abriría un hueco donde entra un segundo _run_turn. Además m13-13 cambia SessionState en paralelo.
  Descartado: Derivarlo de model.state == PROMPTING/CANCELLING
- ! _continue_after_cancel, _quota_checkpoint_done, _suspended y _generator_session_id quedan como flags: no son fases · sin revisar
  Por qué: Son datos de un paso puntual (seguir tras el corte del turno, un solo cpN-quota por límite, no escribir mientras el editor cierra, a qué sesión volver tras la QA), no un estado en el que el run espera o corre.
  Descartado: Convertirlos en fases o en otra etapa
- ! Las transiciones inesperadas van a un canal nuevo `state` del Agent Log (acordado con f3 para las 4 tareas; color #ff8fb8) · sin revisar
  Por qué: Ningún canal existente encaja (acp/proc son del proceso del agente); el mismo canal y las mismas líneas en las 4 ramas se juntan sin conflicto.
  Descartado: push_warning solo; reusar CH_ACP

**Prueba:** En el worktree (rama sm/m13-12, 39e42a6): godot --headless --import; tests/run_all.gd 446 tests/3072 checks 0 fallos (incluye tests/unit/test_oneshot_phases.gd: recorre PHASE_TRANSITIONS y STAGE_TRANSITIONS, un cambio fuera de tabla se anota y se aplica, y un escaneo del código verifica que phase y _stage solo se asignan en _set_phase/_set_stage); acp_session_check 171/0; oneshot_check 140/0 y ninguna transición inesperada en su log (la tabla coincide con los flujos reales).

**Notas:** - PHASE_TRANSITIONS junto a RunPhase; las transiciones fuera de la tabla van al canal nuevo `state` del Agent Log (CH_STATE en agent_log.gd + color en agent_theme.gd, mismas líneas en las 4 ramas m13-11..14), o push_warning sin controller. Contadores unexpected_transitions/last_unexpected_transition para diagnóstico.
- _apply (carga) pasa por _set_phase: IDLE/FINISHED → PAUSED/PAUSED_QUOTA están en la tabla.
- _awaiting_spec + _resume_qa → RunStage {SPEC_APPROVAL, BUILDING, EVALUATION} con _set_stage y STAGE_TRANSITIONS; se guarda como "stage"; _saved_stage lee los guardados viejos (awaiting_spec/resume_qa).
- Comportamiento igual al anterior, incluso en restore() durante una evaluación (deja la etapa en BUILDING, como antes quedaba _resume_qa en false).
- Hallazgo previo, no arreglado (fuera de alcance): restore() en medio de una evaluación no vuelve a la sesión del que construye (_after_qa sale sin _back_to_generator); al retomar, el turno de construcción va a la sesión del evaluador. Igual si se pausa durante _back_to_generator después de un veredicto: «Retomar» repite la vuelta de QA. Merece su propia tarea.
- _turn_running, _continue_after_cancel, _quota_checkpoint_done, _suspended y _generator_session_id quedan como flags (ver decisiones).

### Sesión: LOGIN_REQUIRED como estado y tabla de transiciones · Revisión

**Prioridad:** alta · **Tamaño:** M · **Responsable:** agent-harness-a3

session_model.gd SessionState (DISCONNECTED, STARTING, READY, PROMPTING, CANCELLING, FAILED) acepta cualquier transición, y hay estado escondido en flags: `FAILED + login_required` es en realidad «falta iniciar sesión»; `replaying` y `_closing_previous` (session_controller) son subestados. Hacer: tabla de transiciones permitidas, set_state loguea una transición ilegal en el Agent Log sin bloquearla, y LOGIN_REQUIRED como estado propio (agregado al final del enum para no cambiar valores) sin cambiar lo que ve el usuario. Revisar a todos los que leen `login_required` y `SessionState.FAILED` (dock, oneshot, tests). Test unitario que recorre la tabla; acp_session_check.gd tiene que seguir pasando.

**Decisiones:**
- ! Transiciones inesperadas: señal del modelo que el controller anota en el canal `state` del Agent Log; `login_required` desaparece (LOGIN_REQUIRED + has_failed()); `replaying` y `_closing_previous` siguen como flags · sin revisar
  Por qué: SessionModel no hace IO: en vez de darle el AgentLog, set_state emite `unexpected_transition(from, to)` y el SessionController lo anota en el canal nuevo `state` del Agent Log con el formato común acordado con f3/d5 («session: unexpected transition READY -> CANCELLING»); si nadie escucha (tests sueltos), push_warning. El flag `login_required` desaparece: LOGIN_REQUIRED es un estado y `has_failed()` agrupa FAILED y LOGIN_REQUIRED para los lectores que trataban a los dos igual (stop() los conserva, el dock reabre la sesión desde ambos). `replaying` y `_closing_previous` quedan como flags: son ortogonales al estado (replaying pasa en DISCONNECTED o READY; _closing_previous vive dentro de STARTING) y convertirlos en estados cambiaría los lectores del historial y del One-shot sin que la tarea lo pida.
  Descartado: Darle al modelo una referencia al AgentLog y loguear desde set_state (más simple, pero el modelo pasa a conocer el log). Mantener `login_required` como getter de compatibilidad: descartado, la tarea busca sacar el estado escondido. Convertir `replaying` y `_closing_previous` en estados del enum: fuera del alcance. Loguear en el canal proc en lugar de uno nuevo: descartado, f3 y d5 ya usan `state`.

**Prueba:** tests/unit/test_session_state.gd (tabla completa y sin huérfanos; todo par se aplica y los que no están en la tabla se anotan; el controller lo manda al canal `state` del log; nadie asigna `state` fuera de set_state, escaneando addons/). run_all 445 tests/0 fallos; acp_session_check 175 checks/0 fallos (ahora también verifica que basic, cancel, crash y login no salen de la tabla, y que el login termina en LOGIN_REQUIRED); oneshot_check 140 checks/0 fallos. Godot 4.7.2.

**Notas:** Rama worktree-m13-13, commit af98a6c (sin push, sin merge). LOGIN_REQUIRED al final del enum (FAILED sigue en 5); SESSION_STATE_TRANSITIONS junto al enum con los caminos documentados; set_state único setter, emite unexpected_transition y aplica igual; SessionController lo loguea como «session: unexpected transition A -> B» en el canal nuevo `state` (CH_STATE + color en AgentTheme, convención común con f3/d5). Flag login_required eliminado: dock (línea de estado, chip, cola, historial, enviar sin sesión) y controller leen el estado; has_failed() agrupa FAILED y LOGIN_REQUIRED; stop() conserva los dos. _fail() recibe el estado final. Lo que ve el usuario no cambia (mismos textos, sin CHANGELOG). merge-tree contra worktree-m13-14 sin conflictos.

**Relacionadas:** UI: composer y dock leen el estado del modelo en vez de copias

### UI: composer y dock leen el estado del modelo en vez de copias · Revisión

**Prioridad:** media · **Tamaño:** M · **Responsable:** agent-harness-3c

composer.gd guarda `_busy` y `_oneshot_active` y agent_dock.gd `_oneshot_active`: copias empujadas del estado de la sesión y del One-shot (set_busy, set_oneshot_active). Esc, el placeholder y el estado vacío dependen de que estén sincronizadas. Hacer que lean el estado real (model.is_busy(), el run del One-shot) o una sola fuente, sin cambiar lo que ve el usuario. Test de UI del dev plugin si existe para el composer; unit tests y checks tienen que pasar.

**Decisiones:**
- ! El composer y el dock leen el estado por Callables (`is_busy` = model.is_busy, `oneshot_active` = run activo en esa pestaña); set_busy/set_oneshot_active pasan a refresh_state()/refresh_oneshot(), que solo invalidan · sin revisar
  Por qué: Mismo patrón que can_switch_session y retry_interceptor: el run del One-shot vive en el plugin y se consulta por id de pestaña para no capturar el dock ni el controller (ciclos al cerrar). El composer sigue sin conocer SessionModel y los tests le prestan un Callable fijo.
  Descartado: Darle al composer una referencia al SessionModel y que se suscriba a state_changed (más acoplado, y el One-shot igual necesita un Callable); conservar los bools y sincronizarlos mejor (seguían siendo copias).

**Prueba:** Rama worktree-m13-14. Headless 4.7.2: run_all 440 tests/2949 checks, acp_session_check 171, oneshot_check 140, 0 fallos. Xvfb: --godot-agent-oneshot-test (dock en modo run, «Resume One-shot», solo la pestaña del run en modo One-shot), --godot-agent-i18n-test con es (LayoutCheck.composer_fits con y sin turno en curso) y --godot-agent-queue-test (composer con turno largo, Esc/cancel), todos PASS. test_composer.test_enter_while_busy_and_insert_text le presta un Callable al composer.

**Notas:** composer.gd: fuera _busy y _oneshot_active; entran `busy_provider: Callable` y `oneshot_provider: Callable` (el dock le da model.is_busy y su _is_oneshot_active; nombres como mention_provider, por revisión de a3, commit cea9a51) y refresh_state() en lugar de set_busy/set_oneshot_active. _update_placeholder solo escribe si cambia el texto (refresh_oneshot llega con cada `changed` del run). agent_dock.gd: fuera _oneshot_active; entra `oneshot_active: Callable` que pone el plugin en _wire_oneshot (por id, como can_switch_session), _is_oneshot_active() y refresh_oneshot() (el listener de _oneshot.changed lo llama). Commits: 415ca35 + cea9a51 en worktree-m13-14; revisada por a3 (aprobada). Quedan como copias empujadas, fuera de alcance: set_enabled (STARTING), set_unavailable, set_locked y set_screenshot_available del composer; y can_switch_session en el plugin es el complemento de oneshot_active (podrían unificarse). No toca oneshot_run.gd ni las líneas de FAILED/login_required del dock.

**Relacionadas:** Sesión: LOGIN_REQUIRED como estado y tabla de transiciones

### One-shot: restore() durante una evaluación no vuelve a la sesión del que construye · Revisión

**Prioridad:** alta · **Tamaño:** S · **Responsable:** agent-harness-d5

Lo encontró d5 mientras hacía m13-12: si se hace «Volver acá» (restore) con el evaluador corriendo, el run no vuelve a la sesión del generador (`_generator_session_id`) y queda en la sesión del evaluador. Arreglarlo sobre sm/m13-12 (RunStage ya hace explícita la evaluación), con test en oneshot_check.gd o unitario.

**Decisiones:**
- ! La vuelta a la sesión del que construye se hace al empezar el próximo turno del que construye (_run_turn), no dentro de restore(); la vuelta de QA abandonada no cuenta (qa_round = vueltas con resultado), y la guía espera mientras se evalúa · sin revisar
  Por qué: restore() puede caer mientras _evaluate abre la sesión del evaluador: cambiar de sesión ahí competiría con esa apertura. En _run_turn cubre «Retomar», guiar y aprobar por un solo lugar, y también guiar con la QA en pausa. Una vuelta sin veredicto no debería gastar una de las qa_max_rounds.
  Descartado: Volver al generador dentro de restore(); reabrir como run de disco (_recovered_session_id), que crea otra pestaña con prepare_session; contar la vuelta abandonada

**Prueba:** Rama sm/m13-12, commit 447c521 (encima de 39e42a6). Escenario nuevo «evaluador y volver acá» en tests/oneshot_check.gd: restore() con el evaluador jugando → PAUSED + BUILDING, la vuelta no cuenta, el evaluador deja sus permisos, se guarda la sesión del que construye; «Retomar» reabre esa sesión (sin session/load, con el resumen) y no le habla al evaluador. Sin el arreglo fallan 4 de esos checks. import ok; run_all 446/3072 0 fallos; acp_session_check 171/0; oneshot_check 151/0 (dos corridas solas; una corrida en paralelo con sm/integration dio fallos falsos por user:// compartido, ver la regla de flock de f3).

**Notas:** - La vuelta al generador va en _run_turn (un solo lugar para Retomar, guiar y aprobar), no en restore(): restore puede caer mientras _evaluate abre la sesión del evaluador.
- restore() en EVALUATING: etapa BUILDING y qa_round = qa_results.size().
- guide() en EVALUATING encola (antes, sin turno en vuelo, mandaba el texto del usuario a la sesión del evaluador).
- También van las dos notas de la revisión de f3 a m13-12: _finish → etapa BUILDING; _apply → _phase_since_ms = 0.
- Sigue abierto, no arreglado: pausar durante _back_to_generator después de un veredicto deja la etapa en EVALUATION, y «Retomar» repite la vuelta (el veredicto ya está en qa_results). Lo mismo si se pausa mientras _run_turn vuelve al generador: el turno se manda igual.

### One-shot: pausar mientras _after_qa vuelve al generador repite la vuelta de QA · Revisión

**Prioridad:** media · **Tamaño:** S · **Responsable:** agent-harness-d5

Lo dejó abierto d5 en m13-15: si el usuario pausa justo cuando _after_qa ya tiene el veredicto y está volviendo a la sesión del que construye, «Retomar» repite la vuelta de QA en vez de seguir construyendo con el veredicto. Arreglarlo sobre sm/m13-12 con un escenario en oneshot_check.gd.

**Decisiones:**
- ! Con el veredicto guardado, la etapa vuelve a BUILDING antes de volver al que construye. Si se pausa en ese momento, la corrección queda primera en la cola de guía (sale después del turno de «Retomar»); si el veredicto cierra el run (pasa, sin vueltas o sin presupuesto), termina igual aunque se haya pausado · sin revisar
  Por qué: La vuelta ya tiene resultado en qa_results: repetirla gasta una vuelta y tokens. La cola de guía ya se guarda con el run y es como salen los otros avisos del harness después de una pausa; un campo nuevo para la corrección pendiente sería otro flag.
  Descartado: Guardar la corrección pendiente en un campo propio y mandarla como prompt de «Retomar»; quedar en pausa también cuando el veredicto cierra el run

**Prueba:** Rama sm/m13-12, commit 23726ee (encima de 447c521). Escenario nuevo «evaluador y pausa después del veredicto» en tests/oneshot_check.gd: se pausa mientras se vuelve al que construye con la vuelta 1 ya decidida → PAUSED + BUILDING, la vuelta 1 tiene su veredicto; «Retomar» manda la corrección y la siguiente evaluación es la vuelta 2 (sin repetir la 1), termina «QA round 2: the game passes.». Sin el arreglo fallan 5 checks (se repite la vuelta 1). Con flock: import ok; run_all 446/3072 0 fallos; acp 171/0; oneshot_check 158/0 (159 con el commit 9c67aa0 de la revisión de a3 a m13-15).

**Notas:** - Con el veredicto en qa_results, la etapa pasa a BUILDING antes de _back_to_generator.
- Pausado mientras volvía: la corrección (con el resumen si la sesión es nueva) queda primera en la cola de guía; sale después del turno de «Retomar». Si el veredicto cierra el run, termina igual.
- String nuevo con su traducción en es.po: "QA round %d: the fixes are sent to the builder when the run resumes".
- Aparte, 9c67aa0 aplica la revisión de a3 a m13-15: _run_turn no manda el turno si se pausó o se detuvo mientras volvía al que construye, y _evaluate no abre la sesión del evaluador si se pausó mientras reabría la del agente.

### Tests: cada checkout usa su propia carpeta en user:// · Revisión

**Prioridad:** media · **Tamaño:** S · **Responsable:** agent-harness-a3 · **Etiquetas:** `tests`

user:// es la misma carpeta para todos los worktrees del proyecto (~/.local/share/godot/app_userdata/<nombre>), así que oneshot_check, acp_session_check, los unit tests (temp_dir) y los checks del dev plugin se pisan cuando dos copias corren a la vez: dieron entre 2 y 17 fallos falsos de cuota, checkpoints y recuperación. Hacer que cada checkout use una subcarpeta propia (p. ej. user://<carpeta>/<md5 de res://>/…) con un helper común, sin cambiar lo que prueban. Mientras tanto se corre con `flock /run/user/1000/agent-harness-tests.lock`.

**Decisiones:**
- ! Redirigir user:// de todo el proceso con use_custom_user_dir en tiempo de ejecución (helper tests/test_user_dir.gd llamado por cada punto de entrada) en lugar de cambiar cada ruta user:// de los tests · sin revisar
  Por qué: Godot lee use_custom_user_dir/custom_user_dir_name en cada resolución de user:// (comprobado en 4.7.2 y 4.8-beta2), así que un set_setting al arrancar basta y cubre también lo que el addon escribe en user:// (historial, store del One-shot, shim) y las carpetas de los 30 tests sin tocarlos. La carpeta es <por defecto>/checkouts/<md5 de res://>-<major.minor>: la misma para los procesos hijos del checkout (agente falso, login), y distinta por versión de Godot. set_initial_value evita que ProjectSettings.save() (autoload de playtest, run_check) escriba el override en project.godot; test_user_dir lo vigila. En el editor lo aplica el plugin de dev solo con argumentos --godot-agent-*, cargando el helper por ruta (sin dependencia dura de tests/), así el editor abierto a mano no cambia.
  Descartado: Helper que devuelve user://<hash>/… y reemplazar las ~35 rutas en tests y checks (más diff, se olvida fácil en tests nuevos y no cubre lo que escribe el addon). Reordenar los plugins para aplicar antes en el editor: toca project.godot del test bed, y no hace falta porque las rutas del addon se resuelven al usarlas (el shim en cada session/new). Mantener el flock: mitiga pero no aísla.

**Prueba:** tests/unit/test_user_dir.gd: user:// termina en checkouts/<md5>-<major.minor> bajo la carpeta por defecto del proyecto, lo escrito cae adentro, apply() es idempotente, y ProjectSettings.save_custom() no guarda el override. Las tres suites a la vez y SIN flock, en el worktree: run_all 457 tests/3348 checks 0 fallos; acp_session_check 175/0; oneshot_check 140/0 (4.7.2). test_user_dir también en 4.8-beta2 (4/13, 0 fallos). Editor en Xvfb: --godot-agent-login-test PASS (el editor y el agente falso comparten el marcador user://fake_login_ok en la carpeta nueva). Carpeta creada: ~/.local/share/godot/app_userdata/Godot Agent Harness (dev)/checkouts/8277b675-4.7/.

**Notas:** Rama sm/m13-17 (base sm/integration 55c41e6), commit 9125c7a. Helper tests/test_user_dir.gd (apply() y checkout_tag()); lo llaman run_all, acp_session_check, oneshot_check (solo la const y la primera línea de _initialize, avisado a d5), fake_agent, claude_smoke_check, extensions_cli_check, skills_session_check, subagents_session_check, run_completion_eval, plugin_cycle_check y export_check; el plugin de dev lo carga por ruta en _enter_tree cuando hay un argumento --godot-agent-*. Sin cambios en lo que prueban: las rutas user:// de los tests quedan como estaban. CONTRIBUTING.md lo explica en el párrafo de los checks. Sin CHANGELOG (no cambia nada para el usuario). Después de integrar, el flock deja de hacer falta.

### oneshot_check y los checks de Xvfb fallan si queda algo en el canal state · Revisión

**Prioridad:** media · **Tamaño:** S · **Responsable:** agent-harness-3c · **Etiquetas:** `tests`

Hoy solo acp_session_check (por escenario) y los unit tests comprueban que un flujo real no deje transiciones inesperadas en el canal `state` del Agent Log. Agregar el mismo _check_transitions a oneshot_check.gd (por escenario) y a los checks del dev plugin que corren en CI o tocan las máquinas (run-test, review-test, external-test, oneshot-test, login-test, queue-test), para que una tabla incompleta salga en CI y no en el uso real. Lo encontró 3c escribiendo D61.

**Decisiones:**
- ! _check_transitions por run en oneshot_check (desde _make, al final de la corrida) y _finish_checking_state solo en los checks del dev plugin que mueven las máquinas (run, review, external, oneshot, login, queue); los demás siguen con _finish (registrado por a3 en el cierre del tablero, a partir de las notas de 3c) · sin revisar
  Por qué: Guardar {scenario, log} en _make cubre cualquier escenario nuevo sin tocarlo; el AgentLog es RefCounted y sobrevive al run. En el editor, el chequeo lee el log acumulado de toda la corrida, así que se aplica solo donde el flujo mueve sesión, juego o One-shot; i18n, sessions, history, crash y cycle no mueven las máquinas o producen transiciones a propósito y fallarían sin motivo.
  Descartado: Chequear dentro de cada escenario (se olvida en los nuevos); aplicar _finish_checking_state a todos los checks del dev plugin (falsos positivos en los que fuerzan transiciones).

**Prueba:** Rama sm/m13-18 (b286b54, rebaseada sobre sm/integration 3c7efe3). Headless 4.7.2: oneshot_check 176 checks, 0 fallos (17 nuevos: uno por run que arma _make, incluidos los escenarios de m13-15/16). Xvfb: run-test, review-test, external-test, oneshot-test, login-test y queue-test PASS, ninguno dejó líneas en el canal state. Para ver que falla: una transición fuera de tabla en cualquiera de esos flujos imprime "[<tag>] FALLA canal state: <máquina>: unexpected transition A -> B" y el check sale con 1.

**Notas:** oneshot_check.gd: _make guarda {scenario, log} de cada run en _logs (el AgentLog es RefCounted y sobrevive al run) y _initialize, después del último escenario, llama _check_transitions(log, scenario) por cada uno, con el mismo label que acp_session_check. Nada cambia dentro de los escenarios: cualquier escenario nuevo que use _make queda cubierto. Si un escenario armara su propio SessionController sin _make, no se revisa. Dev plugin: _finish_checking_state(code, message, tag) lee _log del plugin principal (MAIN_PLUGIN_SCRIPT) y, si hay entradas en CH_STATE, las imprime con el tag del check y termina con 1 aunque el resto haya pasado; reemplaza el _finish final de run, review, external, oneshot, login y queue. Los demás checks (i18n, sessions, history, crash, cycle…) siguen con _finish a secas: no mueven las máquinas o producen transiciones a propósito. Lee el log acumulado de toda la corrida del editor, así que una transición inesperada de otro flujo anterior en el mismo editor también cuenta (en estos checks es el único flujo).

### Los checks del editor dejan project.godot como estaba · Revisión

**Prioridad:** baja · **Tamaño:** S · **Responsable:** agent-harness-a3 · **Etiquetas:** `tests`

Correr los checks de Xvfb (run-test y otros) reescribe project.godot del checkout: saca scope_compass de editor_plugins/enabled y, en 4.8, cambia config/features a "4.8". Pasa en 4.7.2 y en 4.8-beta2; cada sesión lo tenía que restaurar a mano con git checkout, y es fácil commitearlo sin querer (me pasó en la integración). Hacer que el dev plugin guarde el contenido de project.godot al empezar un check y lo restaure al terminar (también si falla), sin tocar el autoload temporal de playtest ni el override de user:// de m13-17.

**Decisiones:**
- ! Restaurar project.godot desde el lanzador (tests/run_in_xvfb.sh y plugin_cycle_check.gd), no desde el dev plugin; external-test guarda los ajustes antes de leer project.godot · sin revisar
  Por qué: Probé primero guardar el texto en _enter_tree del dev plugin y reponerlo en _finish/_exit_tree: en 4.7.2 funciona, pero en 4.8 el editor guarda project.godot (config/features "4.8") antes de cargar los plugins, así que la foto ya está cambiada y queda el archivo sucio. El lanzador corre antes y después del editor, cubre todas las escrituras (arranque, checks que guardan, cierre) y también el timeout o un fallo, con trap EXIT. Además, con el archivo siempre restaurado apareció un fallo preexistente en 4.7.2: external-test leía project.godot con un plugin que el checkout no tiene (en los worktrees falta el symlink de scope_compass) mientras la memoria ya no lo tenía, y EditorSync aplicaba también editor_plugins/enabled; antes pasaba porque la primera corrida dejaba el disco "arreglado". Un ProjectSettings.save() antes de leer lo sincroniza.
  Descartado: Solo el dev plugin (lo que pedía la tarea): insuficiente en 4.8. Dev plugin + lanzador: dos mecanismos para lo mismo, y el del plugin daría un mensaje engañoso en 4.8. git checkout en el lanzador: ata los checks a git y pisaría cambios locales no commiteados. Quitar scope_compass de project.godot: es del test bed del usuario, no de los checks.

**Prueba:** Con el commit, cada check seguido de `git status` sin cambios en project.godot: 4.8-beta2 external-test PASS y run-test PASS; 4.7.2 external-test PASS, run-test PASS y plugin_cycle_check PASS (5 ciclos sin huérfanos); run_all -- addon_scripts 0 fallos. Control: sin el ProjectSettings.save() de external-test, el check falla en 4.7.2 de forma determinista sobre bd54ee1 («tenía que aplicar solo lo que cambió», con editor_plugins/enabled de más).

**Notas:** Rama sm/m13-19 (base bd54ee1), commit 5519a22. tests/run_in_xvfb.sh copia project.godot antes de abrir el editor y lo repone con trap EXIT si cambió (también por fallo o timeout; sin exec, conserva el código de salida); plugin_cycle_check.gd hace lo mismo alrededor del editor que lanza; el dev plugin solo suma un ProjectSettings.save() en _run_external_test antes de leer project.godot. No va en el dev plugin como pedía la descripción: en 4.8 el editor guarda config/features antes de cargar los plugins (ver la decisión). No toca el autoload de playtest ni el user:// de m13-17 (son ajustes en memoria). Sin CHANGELOG: solo tests.

### queue-test y login-test fallan con GODOT_AGENT_LANGUAGE=es · Revisión

**Prioridad:** baja · **Tamaño:** S · **Responsable:** agent-harness-d5 · **Etiquetas:** `tests`

Los dos checks del dev plugin buscan botones por su texto en inglés, así que con la interfaz en español fallan (igual en main que en sm/integration: no es regresión de M13). Por eso esas pantallas no tienen captura en español en el tour de UX. Buscar los botones por nombre de nodo o por el msgid traducido con I18n.t(), para que los dos checks corran en ambos idiomas. Lo encontró 3c en el tour de UX de M13.

**Decisiones:**
- ! Los checks del dev plugin buscan los botones por I18n.t() del msgid del addon, no por nombre de nodo; «Cuenta falsa» (nombre del método de auth falso) no se traduce (registrado por a3 en el cierre del tablero, a partir de las notas de d5) · sin revisar
  Por qué: Comparar con I18n.t() del mismo msgid que usa el addon hace que el check pase en cualquier idioma sin cambiar la UI ni agregar nombres de nodo solo para tests; si el addon cambia el texto, la copia del check queda desfasada, y para eso m13-23 hace que test_i18n lo detecte en los unit tests. «Cuenta falsa» es un dato del agente falso, no un texto del addon.
  Descartado: Nombrar los nodos de los botones para buscarlos por nombre (toca la UI por los tests); forzar GODOT_AGENT_LANGUAGE=en en esos checks (dejaba la UI en español sin cobertura).

**Prueba:** Xvfb con GODOT_AGENT_LANGUAGE=en y =es: login-test, queue-test y oneshot-test PASS en los dos. run_all 457 tests/3352 checks 0 fallos, acp_session_check 175/0, oneshot_check 176/0.

**Notas:** Rama sm/m13-20, commit fd18a55 (base bd54ee1). plugin.gd: 3 líneas con I18n.t ("Paste code…", "Open link", "Send now"); "Cuenta falsa" es el nombre del método de auth falso y no se traduce. oneshot_ui_check.gd: 35 comparaciones con I18n.t (formatos con % args o el prefijo antes de %s). Banner y regla de cuota ahora se comparan enteros (antes, prefijo).

### El globo del usuario se parte letra por letra en el dock · Revisión

**Prioridad:** media · **Tamaño:** S · **Responsable:** agent-harness-d5 · **Etiquetas:** `ux`

En las capturas del tour de UX de M13 (d5), el globo del mensaje del usuario con «hola» se muestra partido («h / ol / a»): el ancho del globo colapsa. Pasa igual en main (074267d) y en sm/integration, así que es anterior a M13. Capturas: scratchpad de d5, ux/out/{main,int}/{en,es}/d5_03..05 y d5_08. Reproducir con el agente falso, encontrar por qué el ancho mínimo del globo es casi cero y arreglarlo, con un chequeo en layout_check.

**Decisiones:**
- ! El ancho mínimo del globo del usuario suma get_minimum_size().x del stylebox del Label; LayoutCheck.user_bubble_fits lo verifica en i18n-test y remote-test (registrado por a3 en el cierre del tablero, a partir de las notas de d5) · sin revisar
  Por qué: _fit_width ponía el mínimo en ancho del texto + 2 px, pero el estilo `normal` del Label en el tema del editor tiene 6 px de margen por lado: el texto quedaba con ~11 px y WORD_SMART lo partía letra por letra. En headless (tema por defecto, sin márgenes) no se reproduce, por eso el chequeo va en los checks de Xvfb y no en un unit test.
  Descartado: Un margen fijo mayor (se rompe con otro tema); desactivar el autowrap en globos cortos (cambia el comportamiento de los largos).

**Prueba:** Xvfb: remote-test en/es PASS e i18n-test (es) PASS con el chequeo nuevo LayoutCheck.user_bubble_fits; sin el arreglo, remote-test/en falla: "3 líneas (lugar para el texto 11 px, el texto pide 21)". run_all 457/3352 0 fallos, acp_session_check 175/0, oneshot_check 176/0. Capturas antes/después: scratchpad d5 m1321_antes_despues.png.

**Notas:** Rama sm/m13-21, commit 2bcd174 (base bd54ee1). Causa: _fit_width de user_message_view ponía el mínimo del Label en ancho del texto + 2 px, pero el estilo `normal` del Label en el tema del editor tiene 6 px de margen por lado; el texto quedaba con ~11 px y WORD_SMART lo partía. En headless (tema por defecto, sin márgenes) no se reproduce. Arreglo: sumar get_minimum_size().x del stylebox. Línea en CHANGELOG (Fixed).

### La tarjeta de crash del agente vuelca el prompt de sistema entero · Revisión

**Prioridad:** baja · **Tamaño:** S · **Responsable:** agent-harness-a3 · **Etiquetas:** `ux`

Cuando el agente se cae, la tarjeta muestra la cola de su stderr (_stderr_tail en session_controller), y con claude-agent-acp eso incluye el prompt de sistema entero en JSON: es demasiado largo para una tarjeta de error y tapa la causa. Lo vio d5 en el tour de UX de M13 (d5_02, igual en main). Recortar los detalles a las últimas líneas útiles, o plegar las líneas JSON largas, y dejar el texto completo en el Agent Log.

**Decisiones:**
- ! Recortar cada línea del stderr a 160 caracteres (principio de la línea + «… N more characters, see the Agent Log»), sin plegado ni filtro por contenido; ui-test=crash con rama propia en vez de un check nuevo · sin revisar
  Por qué: El principio de una línea larga es lo que dice qué es («fake_agent: prompt {…», «initialize {…»); plegar/desplegar en la tarjeta exigiría UI nueva para un caso raro, y la línea entera ya está en el Agent Log a un clic («Open the log below»). Filtrar por «parece JSON» se rompe con stack traces largos o líneas de log con JSON útil; el recorte por largo vale para todas. 160 caracteres son dos o tres renglones de monoespaciada en el dock. El ui-test genérico esperaba una respuesta del agente y con el guion crash cortaba por timeout: una rama al principio para ese guion (prompt → FAILED → captura → verificación) es más chica que otro flag del plugin de dev.
  Descartado: Plegar las líneas JSON largas con un botón «ver más» en la tarjeta; descartar las líneas que parecen JSON; mostrar solo la última línea; un flag --godot-agent-crash-card-test aparte.
- ! Revisión de d5: la cola de stderr se guarda ya redactada (AgentLog.redact(), el mismo reemplazo que add()) y sin líneas vacías; las líneas del log en la tarjeta empiezan plegadas con Show/Hide; Copy copia lo que se ve (recortado) · sin revisar
  Por qué: Redactar al guardar en _on_stderr deja un solo lugar sin secretos (tarjeta, Copy y cualquier uso futuro de _stderr_tail) y evita el caso en que el recorte a 160 caiga en medio del token y deje su principio a la vista; redactar después de recortar no lo cubriría. Plegado por defecto (preferencia de d5 y f3): en una caída real la causa va en el texto de la tarjeta (Segmentation fault, Cannot find module) y cuatro líneas recortadas seguían ocupando unas 25 filas en el dock angosto; Show las abre sin salir del chat. Copy copia el texto recortado y redactado: la línea entera está en el Agent Log a un clic y guardar una copia sin recortar en ChatEntry duplicaría estado por una comodidad menor.
  Descartado: Redactar solo en la tarjeta al mostrar (dejaba _stderr_tail con el token); menos líneas y más cortas (4 de 100) en vez del plegado; un campo details_full en ChatEntry para que Copy copie las líneas enteras redactadas.

**Prueba:** tests/unit/test_agent_crash_card.gd (6 tests): recorte de una línea JSON de 3000 caracteres con el principio y «… N more characters, see the Agent Log»; las cortas tal cual y las vacías fuera; solo las últimas STDERR_TAIL; por _fail_agent la tarjeta tiene 3 líneas con la causa visible y el Agent Log conserva la línea entera; un token registrado con add_secret no aparece en la tarjeta ni entero ni su principio (caso con el token cruzando el corte en la posición 150), ni en _stderr_tail ni en el log; las líneas vacías no ocupan lugar en la cola. test_notice_view: las líneas empiezan plegadas, Show las abre y pasa a Hide, un refresh no las vuelve a plegar. run_all 463 tests/3382 checks 0 fallos; acp_session_check 175/0; test_i18n ok. Xvfb 4.7.2: --godot-agent-ui-test=crash PASS (717 caracteres, 4 líneas; verifica además que ni la tarjeta ni la cola del controller tienen el token del server MCP y que la cola tiene la línea de session/new redactada). Capturas en el scratchpad de la sesión a3 (/tmp/claude-1000/-home-dannode-Proyectos-Godot-agent-harness/3619cf30-0f89-4d71-9f7c-62dac5e13c95/scratchpad/): m13-22_before.png (la tarjeta ocupa el dock con el JSON del prompt), m13-22_after.png (recorte sin plegar, versión 70384a4) y m13-22_after_v2.png (plegada: título, causa, «Last lines of the log · Show · Copy» y las acciones). Se regeneran con tests/run_in_xvfb.sh godot --godot-agent-ui-test=crash --godot-agent-ui-shot=<ruta.png>.

**Notas:** Rama sm/m13-22 (base bd54ee1), commits 70384a4 + c467b69 (revisión de d5). SessionController.stderr_summary() estática y STDERR_LINE_CHARS = 160; _on_stderr guarda la cola ya redactada con AgentLog.redact() (lo mismo que aplica add()) y sin líneas vacías; _fail_agent usa el resumen en entry.details. NoticeView: «Last lines of the log» plegadas por defecto con botón Show/Hide (msgids Show/Hide nuevos en es.po); Copy copia lo que se ve. ui-test=crash: rama al principio de _run_ui_test (_check_crash_card), antes cortaba por timeout. CHANGELOG (Unreleased › Changed). Fuera de alcance, visto por d5: en la misma caída salen dos tarjetas («The turn ended with an error … (-32000)» y «<agente> stopped»); viene de antes.

### test_i18n también revisa los textos del dev plugin · Revisión

**Prioridad:** baja · **Tamaño:** S · **Responsable:** agent-harness-d5 · **Etiquetas:** `tests`

Desde m13-20 los checks del dev plugin (addons/godot_agent_dev) comparan con I18n.t("…") textos copiados del addon. test_i18n solo recorre addons/godot_agent, así que si el addon cambia un texto, la copia del check queda desfasada sin que ningún unit test lo vea (el check falla recién en Xvfb). Hacer que test_i18n recorra también addons/godot_agent_dev y exija que cada msgid usado con I18n.t() exista en es.po, sin pedir traducción para lo que el dev plugin no muestra. Lo propuso 3c en la revisión de m13-20.

**Decisiones:**
- ! test_i18n recorre también addons/godot_agent_dev: cada I18n.t() del dev plugin tiene que estar en es.po, pero no cuenta como uso para la regla de entradas sin usar, y el test exige más de 30 llamadas para no pasar vacío (registrado por a3 en el cierre del tablero, a partir de las notas de d5) · sin revisar
  Por qué: Desde m13-20 los checks comparan con copias de textos del addon; si el addon cambia uno, la copia quedaba desfasada y el check fallaba recién en Xvfb. Que el dev plugin no cuente como uso evita que un texto que el addon dejó de usar sobreviva en es.po solo porque un check lo nombra. El mínimo de 30 detecta un barrido vacío (ruta mal escrita). No compara formatos porque el test del addon ya lo hace sobre la misma entrada.
  Descartado: Que los checks importen las constantes del addon en vez de copiar textos (no hay constantes: son literales en I18n.t); un test aparte en el dev plugin (los unit tests no corren el dev plugin).

**Prueba:** run_all 458 tests/3354 checks 0 fallos (test nuevo test_i18n.test_dev_plugin_texts_are_in_the_catalog). Prueba de desfase: con I18n.t("Review the spec") en oneshot_ui_check.gd el test falla y nombra el texto y el archivo; revertido. acp_session_check 175/0, oneshot_check 176/0.

**Notas:** Rama sm/m13-23, commit 27b1c0b (base 650e2ef). Solo tests/unit/test_i18n.gd: DEV_DIR = addons/godot_agent_dev; cada msgid de I18n.t("…") del dev plugin tiene que estar en es.po con traducción. No cuentan como uso para la regla de entradas sin usar: si el addon deja de usar un texto, salta igual como sin usar. Hoy el dev plugin usa 60 llamadas (auto, review, oneshot_ui, remote, plugin); el test exige más de 30 para no pasar vacío. No compara formatos (eso ya lo hace el test del addon sobre la misma entrada).

### Una caída del agente muestra dos tarjetas de error · Revisión

**Prioridad:** media · **Tamaño:** S · **Responsable:** agent-harness-d5 · **Etiquetas:** `ux`

Cuando el proceso del agente se cae en medio de un turno, el chat muestra dos tarjetas: «The turn ended with an error: The agent exited (code 9). (-32000)» con Retry/Open the log, y «<agente> stopped» con el stderr, Retry y Open the log. Es la misma causa dicha dos veces, con dos Retry. Pasa igual en main. Dejar una sola (la del crash, que tiene la causa y el log) y que el fin del turno por la caída no agregue la suya. Test en acp_session_check (escenario crash) contando las tarjetas de error. Lo vio d5 revisando m13-22; va encima de m13-22 porque toca session_controller.gd.

**Decisiones:**
- ! Sin flag: _on_process_exited pone FAILED con la tarjeta antes de fallar los requests pendientes, y send_prompt, si model.has_failed(), solo anota el turno cortado y llama a finish_turn("error") sin cambiar el estado (PROMPTING → FAILED, sin READY intermedio) (registrado por a3 en el cierre del tablero, a partir de las notas de d5; «sin flag» lo pidió f3) · sin revisar
  Por qué: La misma caída producía dos tarjetas con dos Retry: la del turno cortado y la del proceso. Ordenar las cosas (primero el estado y la tarjeta de la caída, después los requests) deja que quien recibe el error pregunte por el estado en vez de llevar un flag más, que es justo el tipo de estado escondido que M13 saca. Evitar el READY intermedio mantiene la máquina de estados fiel a lo que pasó.
  Descartado: Un flag «ya se avisó la caída» consultado en send_prompt (descartado por f3: estado escondido); suprimir la tarjeta del proceso y dejar la del turno (pierde el stderr y el título con la causa).

**Prueba:** acp_session_check 179/0: el escenario crash exige una sola tarjeta de error (la de la caída), turn_finished una vez con "error", la tarjeta después del mensaje del usuario y los estados PROMPTING → FAILED sin READY. Sin el arreglo falla con las dos tarjetas. run_all 463/3382/0, oneshot_check 176/0, ui-test=crash PASS en en y es (captura: una sola tarjeta, plegada).

**Notas:** Rama sm/m13-24, commit 76ca585 (rebasada sobre 64ed939, el m13-22 final de a3). _on_process_exited llama a _fail_agent (FAILED y la tarjeta) antes de client.fail_all_pending. En send_prompt, si model.has_failed(), el turno cortado solo se anota en el log y llama a finish_turn("error"), que emite turn_finished y no cambia el estado. Sin flag (lo pidió f3). La caída durante initialize va en m13-26. Línea en CHANGELOG (Fixed).

### Barrido: ¿por dónde más puede salir un secreto sin redactar? · Revisión

**Prioridad:** alta · **Tamaño:** M · **Responsable:** agent-harness-a3 · **Etiquetas:** `security`

La tarjeta de crash mostraba el stderr del agente sin pasar por la redacción del Agent Log, y podía exponer el token del servidor MCP (con botón Copy). Pasaba en v0.1.17 publicada; m13-22 lo arregla con AgentLog.redact(). Revisar el resto de los caminos por donde texto del agente, de su proceso o del harness llega a la UI, al portapapeles o al disco sin redactar: failure_message y su tooltip, el historial de sesiones (session_history), los informes y la actividad del One-shot, el export de Settings, los avisos y las notices con details, el Copy de los bloques, los logs de los checkpoints o de git. Por cada camino: redactar con AgentLog.redact() o justificar por qué no hace falta, con un test por cada arreglo. Si algo es grave, avisar antes de seguir.

**Decisiones:**
- ! Redactar en un solo punto de entrada (AcpClient) las notificaciones y respuestas del agente, nunca los params de sus requests; lo que de un request se muestra se redacta en la copia (PermissionBroker); los mensajes de fallo y el historial reproducido se redactan en destino; las keys del entorno del perfil se registran como secretos · sin revisar
  Por qué: Lo que el agente cuenta o repite (chunks, tool results, errores que citan la configuración) llega por JSON-RPC a muchos destinos (modelo/UI, historial en disco, One-shot, tarjetas); redactarlo al entrar cubre todos con un cambio. Pero un request del agente al cliente (fs/write_text_file, terminal/create, elicitation) es una acción: redactar sus params habría escrito «secret» en un .env con la key del usuario o corrido un comando alterado (bloqueante de f3, señalado también por 3c). Por eso los requests entran intactos y solo se redacta su copia visible (tool call del modelo, título, descripción y diff de la tarjeta de permiso; también en authorize(), que es la tarjeta de las escrituras del fs y de los comandos). failure_message/_fail/_fail_agent no vienen todos del agente (error del proceso, stderr): se redactan ahí. Un historial grabado antes se reproduce redactado. Las variables de entorno del perfil (API keys resueltas de $VAR) no eran secretos registrados: se registran al arrancar si el nombre dice key/token/secret/password/auth y el valor tiene ≥ 8 caracteres. Las tools MCP (godot.*) entran por mcp_server.gd y escriben el proyecto por diseño, igual que fs/write_text_file: no se redactan; sus resultados al log sí (add). El export de Settings no es un volcado de ajustes y los perfiles guardan nombres de variables, no valores; git no imprime credenciales en lo que leemos; el shim y session/new llevan el token al agente por diseño.
  Descartado: Redactar todo mensaje al entrar, requests incluidos (descartado: rompe trabajo legítimo). Redactar en cada destino por separado (modelo, historial, One-shot, informe…): más lugares que olvidar. Redactar el contenido de fs/write_text_file (descartado: corrompe el archivo sin avisar). No registrar las keys del entorno del perfil (descartado: el agente las repite en stderr y en errores).

**Prueba:** tests/unit/test_secret_redaction.gd (9 tests): redact_data recorre diccionarios, arrays y PackedStringArray sin tocar el original; AcpClient redacta una notificación (tool result con el token), una respuesta de error que lo cita y el log, y deja intactos los requests (fs/write_text_file, terminal/create, request_permission); _fail y _fail_agent redactan tarjeta y failure_message; start() registra las keys del entorno del perfil (≥ 8, nombre con key/token/secret/password/auth) y no las cortas ni las que no parecen secretas; un historial viejo se reproduce redactado; la tarjeta de permiso de session/request_permission muestra «secret» y responde con la opción elegida con los params originales intactos; de punta a punta con el FsHandler real: la tarjeta de la escritura muestra el diff redactado, el .env queda con la key de verdad y la notificación del tool call llega redactada. run_all 471 tests/3453 checks 0 fallos; acp_session_check 175/0; oneshot_check 176/0 (4.7.2). La verificación de los escritores de disco (historial .jsonl, store e informe del One-shot, commits de checkpoints) la hace 3c con tests en sm/m13-25-disk sobre esta rama.

**Notas:** Rama sm/m13-25 sobre 64ed939 (m13-22): 76f8b1c + 5b1546e. Docs en sm/m13-25-docs (72b654e): PRIVACY en/es (sección Secretos), wiki How-it-works/Editor-tools en/es, SECURITY (aviso ≤ 0.1.17). Verificación de disco de 3c en sm/m13-25-disk (0cdbfa3, solo tests): escenarios «secrets» en acp_session_check (9 checks: modelo, .jsonl e index del historial, replay, Agent Log) y «secretos» en oneshot_check (10: etiquetas y git log de checkpoints, JSON del store e informe, RunReport.to_markdown, actividad, archivos del run, chat); sobre c467b69 fallaban 5 y 7 aserciones, sobre 5b1546e 0. Hallazgo real abierto en v0.1.17: todo lo que el agente mandaba por JSON-RPC (un error que cita los mcpServers con el header Authorization, un tool result que muestra GODOT_AGENT_MCP_TOKEN del shim, texto que repite una key) llegaba sin redactar al modelo/UI, al historial en disco, al One-shot (actividad, informe, run guardado) y a las tarjetas. Arreglo: AgentLog.redact_data() y AcpClient.receive_line la aplica a notificaciones y respuestas; los params de los requests del agente nunca se tocan (bloqueante de f3: escribir «secret» en un .env o correr un comando alterado); la copia visible de un request se redacta en PermissionBroker (on_request_permission y authorize()). _fail/_fail_agent redactan; reopen() reproduce el historial con redact_data(); AgentProfile.secret_env_values registra las keys del entorno del perfil al arrancar. Justificados sin cambio: Agent Log y sus Copy, Copy de la tarjeta de caída (m13-22), export de Settings (no es un volcado; los perfiles guardan nombres de variables), checkpoints/git, shim stdio y session/new (llevan el token al agente por diseño), tools MCP godot.* (escriben el proyecto por diseño, resultados al log redactados), elicitation (el enlace tiene que seguir sirviendo). Nota de 3c, a propósito: record_prompt guarda el texto del usuario tal cual (si pega su propia key en el chat queda en el .jsonl: es su texto; PRIVACY lo dice). CHANGELOG: Unreleased › Fixed.

### Una caída del agente durante initialize muestra dos tarjetas de error · Revisión

**Prioridad:** baja · **Tamaño:** S · **Responsable:** agent-harness-d5 · **Etiquetas:** `ux`

Si el proceso del agente termina mientras el harness espera la respuesta de initialize, _on_process_exited falla el request pendiente y start() suma «<agente> didn't start», además de la tarjeta «<agente> stopped» de _fail_agent. Es la misma causa dos veces. Con m13-24, _fail_agent ya va antes de fail_all_pending, así que start() puede preguntar model.has_failed() y no sumar la suya. Pero hay que revisar qué ven quienes llaman a start() (failure_message, el estado). Hace falta un paso en fake_agent para caerse en initialize (p. ej. "initialize": {"exit": true}) y un escenario en acp_session_check que cuente las tarjetas. Lo encontró d5 en m13-24. Va encima de m13-24 porque toca session_controller.gd.

**Decisiones:**
- ! start(), open_session() y _load_session() preguntan model.has_failed() después del chequeo de generación y devuelven false sin sumar su tarjeta; _load_session evita el stop() que pasaba la sesión caída a DISCONNECTED; fake_agent con "exit_on": "<método>" (registrado por a3 en el cierre del tablero, a partir de las notas de d5) · sin revisar
  Por qué: Con el orden de m13-24, cuando el request cortado vuelve, _fail_agent ya puso FAILED y la tarjeta: alcanza con preguntar por el estado en los tres puntos donde un request de arranque puede fallar por la caída, sin flag. El stop() de _load_session borraba el motivo (DISCONNECTED sin tarjeta); conservar FAILED deja Retry a la vista. "exit_on" en el agente falso reproduce la caída en initialize, session/new y session/load con un guion cada uno.
  Descartado: Un flag compartido con m13-24 (descartado: estado escondido); filtrar la segunda tarjeta en el modelo al agregarla (esconde el problema en vez de evitarlo).

**Prueba:** acp_session_check 194/0. Escenario nuevo crash_starting: el agente falso se cae en initialize, session/new y session/load (exit_on). En los tres, start() devuelve false con la sesión en FAILED y su failure_message, hay una sola tarjeta (la de la caída) y ninguna transición fuera de la tabla. Sin el arreglo fallan los tres con una segunda tarjeta («didn't start», «Could not open the session…», «Could not resume…»). run_all 463/3388/0, oneshot_check 176/0, ui-test=crash PASS en en y es (pila m13-22 + m13-24 + m13-26).

**Notas:** Rama sm/m13-26, commit af34a03, encima de sm/m13-24 (76ca585), que a su vez va sobre 64ed939 (m13-22 final). Sin flag: con el orden de m13-24, _fail_agent ya puso FAILED y la tarjeta cuando el request cortado vuelve, así que start(), open_session() y _load_session() preguntan model.has_failed() después del chequeo de generación y devuelven false sin sumar su tarjeta. En _load_session, además, evita el stop() que pasaba la sesión caída a DISCONNECTED y borraba el motivo. fake_agent: clave "exit_on": "<método>" y tres guiones crash_*.json. Amplié la línea de CHANGELOG de m13-24 («during a turn or while the session starts»).

### godot.profile_run: las funciones de GDScript más calientes de un run (API interna del editor) · Revisión

**Prioridad:** baja · **Tamaño:** M · **Etiquetas:** `idea`

Idea a partir de github.com/DasDarki/grit (AOT de GDScript a C++): darle al agente las funciones más calientes de un run (tiempo propio y total, llamadas, y si están tipadas), para que proponga tipos o mover loops a APIs del motor con medición antes y después. Investigación de 3c en 4.7.2 y 4.8-beta2: hoy no se puede. ScriptEditorDebugger consume servers:profile_frame y no lo pasa a EditorDebuggerPlugin._capture, EditorDebuggerSession no tiene señal con esos datos, y desde el juego GDScript no puede leer los tiempos del ScriptsProfiler. El profiler duplica el costo de cada llamada (~95→190 ns). Caminos: (i) PR a Godot para que EditorDebuggerSession emita los frames del profiler, o que los plugins capturen mensajes ya manejados (primer paso recomendado); (ii) leer el Tree del panel Profiler: frágil, no; (iii) servidor de debug propio con --remote-debug: otra arquitectura de run_scene, no por ahora. Si está tipada se deduce leyendo el script (res://ruta.gd::línea::nombre). Integrar Grit mismo: no por ahora (motor parcheado, muy experimental).

**Decisiones:**
- ! profile_run deja el juego corriendo al terminar (como run_scene), con el profiler apagado · sin revisar
  Por qué: Coherente con run_scene: el agente puede seguir con capture_game_frame/game_* o stop_scene, y el profiler apagado no le cobra overhead
  Descartado: Cerrar el juego al final (lo que decía el diseño de las notes)
- ! Sin parámetro include_native en profile_run por ahora; la tool siempre registrada (error claro sin la API) en vez de no registrarla · sin revisar
  Por qué: include_native no lo pedía el pedido y suma overhead y ruido; registrarla siempre deja que el agente sepa por qué no puede perfilar en vez de no encontrar la tool
  Descartado: include_native como arg (internal_time por función); no registrar la tool si falta ScriptEditorDebugger al habilitar

**Prueba:** 4.7.2: run_all (505 tests, 0 fallos, incluye tests/unit/test_script_profile.gd), acp_session_check y oneshot_check en 0 fallos. Xvfb: tests/run_in_xvfb.sh <godot> --godot-agent-profile-test en 4.7.2 y 4.8-beta2 (profile_check.gd: workaround y overhead; profile_tool_check.gd: la tool por HTTP real), más cycle-test, run-test y mcp-test en 4.7.2.

**Notas:** IMPLEMENTADA (d5, rama sm/m13-27-tool desde sm/next 8511d2a, commit ad0241b, sin push).

- addons/godot_agent/playtest/script_profile.gd (parte pura): parsea ServersProfilerFrame. Descarta el primer frame después del toggle y cualquier frame donde una función dure más que frame_time + 10 ms. Agrega solo desde frames (nunca desde profile_total). Arma el top por tiempo propio (llamadas por frame, ms propios y totales, % del script_time) y el tipado leído del .gd: yes/partial/no, o "" si es built-in o el archivo no está. OJO: la línea de la firma del profiler es la primera del cuerpo, no la del func (::28::_hot, cuando el func está en la 27). Se busca la declaración hacia atrás, sin pasar de otra func, y al agente se le da la línea del func.
- addons/godot_agent/mcp/tools/profile_tools.gd: tool profile_run (grupo run, extendida, así que aparece en godot.methods). Args: scene, seconds, inputs y continue_on_error (los de run_scene), top (20, máx. 100), max_functions (128, 16–512).
  - Orden de chequeos: otro profile_run en curso; run_tools.is_busy() (el error dice el GameRunState); fuente de datos (EditorDebuggerSession.debug_data si existe, si no ScriptEditorDebugger.debug_data, si no error claro). La detección es por llamada: la tool siempre está registrada y sin la API contesta por qué no puede, sin romper nada.
  - Prende el profiler solo en el session_started del juego que lanzó run_scene (run_state == STARTED y run_tools busy); un run manual no se toca.
  - Lo apaga al final pase lo que pase. Hay un timer de seguridad atado a un contador de runs (uno viejo no apaga uno nuevo), y shutdown() se llama en _exit_tree del plugin.
- RunTools: run_scene() e is_busy() públicos. PlaytestDebugger: active_session_id().
- El juego sigue corriendo después, como con run_scene (el diseño decía stop; cambié para ser coherente con run_scene). Quedó afuera include_native (no lo pedía el pedido; se puede sumar).
- Tests: tests/unit/test_script_profile.gd (8 tests: parseo, descartes, top, firmas, tipado con cabeceras multilínea, de una línea y static, informe, rechazo con run_scene en curso). addons/godot_agent_dev/profile_tool_check.gd por HTTP real, verifica:
  - _step en :32 con 2000.0 calls, typed: yes;
  - _hot en :27;
  - la nota del overhead;
  - 0 frames después de apagar con el juego vivo;
  - el rechazo con run_scene de fondo;
  - un juego frenado en el debugger contesta "No usable profiler frames" y no queda perfilando.
  Pasa en 4.7.2 y 4.8-beta2.
- Wiki en/es (Herramientas del editor), CHANGELOG Added (aclara la API interna), etiqueta "Profile the game" con su traducción en es.po.
- Borrador de issue upstream: tests/upstream/issue_profiler_inflight_calls_first_frame.md. Causa: gdscript_vm.cpp mira el flag profiling por separado al entrar y al salir, y line_poll() atiende el toggle cada 2048 líneas. Fix sugerido: flag local profile_this_call. No había issue (búsqueda del 2026-11-10). No publicado.

Sin verificar: que el botón del panel Profiler no refleje que un plugin lo prendió. Si el usuario tenía el Profiler del editor corriendo, profile_run lo apaga al terminar (no se detecta).

---
INVESTIGACIÓN PREVIA (resumen). El editor no pasa servers:profile_frame a EditorDebuggerPlugin._capture, porque tiene handler propio en ScriptEditorDebugger::_parse_message. Ese nodo interno emite debug_data(msg, data) para todo mensaje antes de manejarlo (4.7.2 y master). El profiler se prende con la API pública session.toggle_profiler("servers", true, [max_funcs, include_native]). Proposal upstream (tests/upstream/proposal_debugger_session_debug_data.md): que EditorDebuggerSession reenvíe debug_data, unas 8 líneas.

Overhead medido con profile_check: 4.7.2 ×1.64–1.74 (78–101 ns por llamada); 4.8-beta2 ×1.82–1.95 (83–98 ns).

Formato de profile_frame: [frame, frame_time, process, physics, physics_frame, script_time, n_servers, (nombre, 2n, (fn, t)…)…, 5n, (sig_id, calls, self, total, internal)…], en segundos. Relacionados: godot#96210, #102972, PR #66938, #86721, proposals #13631 y #8777.

### Redacción de secretos: detalles que quedaron de m13-25 · Revisión

**Prioridad:** baja · **Tamaño:** S · **Etiquetas:** `security`

No bloqueantes, de la revisión de d5 de m13-25.
1) SECRET_ENV_NAME (agent_profile.gd) busca «key|auth|…» sin límites de palabra: GIT_AUTHOR_NAME o KEYBOARD_* en el env del perfil registran su valor como secreto, y p. ej. el nombre del usuario se taparía en todo el chat. Usar límites (^|_)(KEY|TOKEN|…)($|_) o una lista.
2) elicitation/create es un request y no se redacta (bien para lo que se ejecuta), pero su formulario se muestra tal cual. Redactar la copia que se muestra, como en la tarjeta de permiso.
3) Los session/update entran redactados, pero el MCP del harness recibe los args reales. find_godot_tool_call(tool_name, args) puede no emparejar una tool call cuyos args tengan un secreto. Revisar también que una regla «permitir siempre» no se guarde con «secret» (sale del ToolCall redactado del modelo) y después no coincida con el comando real.
4) authMethods de la respuesta de initialize (args/env del login por terminal) entra redactado y se usa para ejecutar el login: confirmar que no puede llevar un secreto registrado.

**Prueba:** 4.7.2: run_all 481 tests/3516 checks 0 fallos; acp_session_check 203/0; oneshot_check 186/0; login-test en Xvfb PASS. Tests nuevos: test_secret_names (palabras enteras, GIT_AUTHOR_NAME no es secreto ni en el entorno del agente ni en la validación de MCP), test_secret_redaction.test_elicitation_form_shows_a_redacted_copy, test_godot_tool_call_matches_with_a_secret_in_its_args, test_no_shell_rule_with_a_secret, y test_agent_login.test_redacted_env_does_not_replace_the_real_key.

**Notas:** Rama sm/m13-28, commit 7296af7 (base main 9501d7f). Hecho en el worktree m13-12 con una rama nueva desde main, no en un worktree aparte.
1) core/secret_names.gd: SecretNames.is_secret(name) compara palabras enteras del nombre, separadas por _ - . y camelCase, contra KEY, APIKEY, TOKEN, SECRET, PASSWORD, PASSWD, AUTH, AUTHORIZATION, CREDENTIAL(S), BEARER y COOKIE. Reemplaza las tres copias del regex suelto: agent_profile (redacción del entorno), external_mcp_servers y settings_dialog (las dos validaciones, que también rechazaban GIT_AUTHOR_NAME como «key escrita a mano»).
2) Elicitation: se redacta el message, y del schema solo title, description y enumNames (AgentLog.redact_fields). Las claves dentro de properties son nombres de campo, no campos del schema: una propiedad llamada «title» no se redacta entera. Los default, enum y const y el url quedan reales, porque vuelven al agente o se abren.
3) find_godot_tool_call acepta un redact y plugin._match_pending_undo le pasa _log.redact_data, así el undo de una tool godot.* con un secreto en los args se une a su tool call. En Auto, si la regla de shell sugerida tiene un secreto no se propone ninguna (la tarjeta la mostraría y Ajustes la guardaría en disco). «Siempre en esta sesión» es por grupo, no por comando, así que no lo afecta.
4) Sí podía pasar: los secretos del entorno se registran antes de initialize y el agente los tiene en su env. AgentLogin.command_for ya no pisa una variable del env del método con «secret»: queda la real del perfil, o la del editor que el login hereda.
Queda afuera: ExternalMcpServers.secret_values registra cualquier valor que salga de un $VAR del config MCP, sin mirar el nombre (deliberado: un $VAR en ese config es explícito). Y si un permiso llega sin rawInput, los guards usan el raw_input redactado del modelo; eso solo afecta la clasificación.

### Tooltip del encabezado con el estado de cada máquina · Revisión

**Prioridad:** baja · **Tamaño:** S · **Responsable:** agent-harness-a3 · **Etiquetas:** `ux`

Las máquinas de D61 (sesión, game run, fase y etapa del One-shot) ya tienen nombres de estado, pero el usuario y el agente solo ven el canal state cuando algo sale mal. Mostrar en el tooltip del encabezado del dock el estado actual de cada una con su antigüedad (p. ej. «juego: corriendo 12 s · One-shot: evaluando vuelta 1»), leído por providers y sin copias del estado (D61). Igual que describe_run_state() en run_tools.gd. Traducir EN/ES.

**Decisiones:**
- ! Un provider `machine_states` por pestaña (el plugin devuelve {machine, label, age} del juego y del One-shot) y el dock arma el tooltip con la sesión; etiquetas traducibles en cada máquina (SESSION_STATE_LABELS, GAME_RUN_STATE_NAMES con # i18n, STAGE_LABELS); el tooltip se refresca con el tick de la cuota · sin revisar
  Por qué: D61: el dock no copia el estado del juego ni del One-shot, que viven en el plugin; un Callable que se lee al armar el tooltip es el mismo patrón que oneshot_active y can_switch_session. Los nombres del juego para el agente (describe_run_state) y para el usuario son los mismos textos, así que se traducen con I18n.t() en vez de duplicar un diccionario; la sesión y la etapa no tenían etiquetas y se agregan. La antigüedad cambia con el tiempo y el tooltip de Godot lee tooltip_text al mostrarse: se recalcula en el tick de un segundo que ya existe para la cuota, sin un timer nuevo. describe_state() y describe_phase() quedan en inglés para el agente, como describe_run_state().
  Descartado: Que el dock conozca RunTools y OneShotRun y lea sus estados directo (acopla el dock a cosas del plugin); un segundo diccionario de nombres del juego solo para la UI; un timer propio para el tooltip; recalcular el tooltip en _make_custom_tooltip (más código para el mismo resultado).

**Prueba:** Unit (4.7.2): test_session_model.test_state_labels_and_age (etiqueta por estado, describe_state «session: ready (N s)», edad), test_oneshot_dock.test_describe_phase («one-shot: idle, building (0 s)», etiquetas por etapa), test_mentions.test_machine_line («Game: running · 12 s»); test_i18n cubre las etiquetas nuevas (# i18n) con traducción. run_all 476 tests/3481 checks 0 fallos; acp_session_check 203/0; oneshot_check 186/0. Xvfb: tests/run_in_xvfb.sh godot --godot-agent-ui-test=basic PASS en inglés y en español (GODOT_AGENT_LANGUAGE=es); el check nuevo _check_header_tooltip exige que el tooltip del chip empiece con «Session: working», tenga la línea «Game: …» y la antigüedad en segundos, y con --godot-agent-ui-shot abre el tooltip de verdad con el mouse encima. Capturas (scratchpad de a3): /tmp/claude-1000/-home-dannode-Proyectos-Godot-agent-harness--claude-worktrees-m13-17/3619cf30-0f89-4d71-9f7c-62dac5e13c95/scratchpad/m13-29_en_header_tooltip.png (muestra «Session: ready · 0 s / Game: no game launched · 6 s / Click to choose the agent») y m13-29_es_header_tooltip.png.

**Notas:** Rama sm/m13-29 (base main 9501d7f), commit a9cadea, en el worktree m13-17. SessionModel: SESSION_STATE_LABELS (# i18n), _state_since_ms en set_state, state_age_seconds(), describe_state() para el agente. RunTools: GAME_RUN_STATE_NAMES con # i18n (el mismo texto para el agente y traducido para el usuario), run_state_age_seconds(). OneShotRun: STAGE_LABELS (# i18n), phase_age_seconds() (0 si el run se cargó de disco y no cambió), describe_phase() para el agente. AgentDock: provider machine_states (() -> Array[Dictionary] {machine, label, age}), header_tooltip() (sesión + máquinas + error o cuenta + ayuda), machine_line() estática, refresco en _on_quota_tick. plugin.gd: _machine_states(id) en _wire_oneshot: el juego (si hay _run_tools) y el One-shot de esa pestaña (si _runs_in(id) y activo), con phase_label() y la etapa. 17 msgids nuevos en es.po. CHANGELOG: Unreleased › Added. Dev plugin: _check_header_tooltip en _run_ui_test (todos los guiones salvo crash) y _tooltip_windows para componer la ventana del tooltip sobre la captura. La ventana del tooltip sale en la captura algo desplazada respecto del chip (coordenadas de ventana nativa bajo Xvfb); el texto se lee entero.

### run-test: «game_input text: escribe en el LineEdit» falla a veces · Hecho

**Terminada:** 2026-11-10 · **Prioridad:** media · **Tamaño:** S · **Etiquetas:** `tests`

El check de run_check.gd que escribe texto con game_input en el LineEdit del juego de playtest falla de forma intermitente: last_text queda vacío. Pasó 4 veces entre m11-42, m11-43 y una base sin cambios en el juego (sm/m12-44), en 4.7.2 y 4.8-beta2, en es y en; en esa base falla 1 de 2 en 4.8-beta2. Probablemente es timing: el foco del LineEdit o el texto llegan antes o después de la lectura. Hace fallar la suite de release sin un bug real. Mirar cuándo toma el foco el LineEdit y si game_input espera el frame en que se procesa el texto.

**Notas:** Duplicada de m16-11, que se queda con el trabajo: el mismo flake más test_composer y game_script/ui_right. Lo que se vio acá está en m16-11.

**Relacionadas:** run-test inestable: «game_input text: escribe en el LineEdit»

### MCP servers del proyecto: aprobación por máquina antes de lanzarlos · Revisión

**Prioridad:** media · **Etiquetas:** `security`

Encontrado el 2026-11-11 al diseñar m11-31. Los MCP servers con alcance «This project» viven en project_config.tres, que se versiona con el proyecto. Los de tipo stdio se lanzan con su `command` y sus `args` al abrir cada sesión, sin ninguna aprobación local (plugin.gd, ExternalMcpServers.merge con _project_config.mcp_servers). Un proyecto clonado puede traer un server con un comando arbitrario.

Matiz: abrir en Godot un proyecto que no es de confianza ya ejecuta código (scripts @tool, plugins del editor). Esto es defensa en profundidad, no un agujero nuevo. Igual vale: el usuario espera que el harness pregunte antes de lanzar comandos.

Qué hacer: el mismo esquema que los checks de m11-31.
- Un server del proyecto se lanza solo si en esta máquina se aprobó su definición exacta: command, args, env, url y headers. La aprobación se guarda en los ajustes del usuario, con la ruta del proyecto y un hash.
- Agregarlo o editarlo en Settings cuenta como aprobarlo.
- Si no está aprobado, no se pasa en mcpServers, y un aviso en el dock lo dice y ofrece «Aprobar…».
- Que reuse la tienda de aprobaciones y el «Aprobar…» de turn_checks (m11-31): una sola tienda y un solo diálogo.
- Los servers del usuario («All my projects») no cambian.

Va después de m11-31, en la misma línea de ramas.

**Decisiones:**
- ! Qué se aprueba de un server del proyecto y cuándo: transport, command, args, env, url y headers (con $VAR sin resolver; sin el nombre ni el interruptor); importar de .mcp.json no aprueba; el aviso largo sale la primera vez por usuario y después una línea, siempre con «Aprobar…» por server y «Aprobar todos (N)…». · sin revisar
  Por qué: El nombre y el on/off no deciden qué corre. .mcp.json viene del repo igual que project_config.tres, así que importarlo no es haber escrito el comando. El aviso aparece en cada sesión mientras haya servers frenados (nada queda roto en silencio al actualizar), pero la explicación del cambio basta una vez; es la línea de CHANGELOG › Changed.
  Descartado: - Aprobar también el nombre: renombrar pediría aprobar de nuevo sin cambiar nada de lo que corre.
  - Importar .mcp.json como aprobado: el usuario aprieta un botón sin ver los comandos.
  - Aviso largo en cada sesión: ruido; o solo la primera vez y después nada: quedaría roto en silencio.
  - Reiniciar la sesión al aprobar: corta el turno; se avisa que entran en la próxima sesión.

**Prueba:** - tests/unit/test_mcp_approval.gd (4 tests): qué cuenta en la clave (nombre/interruptor/orden de env no; command, args, env, transport, url, headers y proyecto sí), descripción del diálogo, aviso largo/corto con «Aprobar…» por server y para todos, approve_on_machine, página de Settings (aviso, marca que no se guarda, editado aprueba, importado de .mcp.json no).
- Check de editor «checks» (suite ci): dos servers del proyecto sin aprobar no entran en external_mcp_names, el aviso largo los nombra con 3 acciones, «Approve all» abre el diálogo con los dos comandos y los aprueba (tienda en memoria; restaura el flag del aviso y los Callables del controller).
- Settings shots: el server importado pide aprobación y «Allow on this machine» lo aprueba al guardar (se borra después de los EditorSettings reales).
- suite.sh ci 15/15 en 4.7.2.

**Notas:** Hecho en sm/m13-31 (19862b3, sobre sm/m11-31 934da58).
- core/machine_approval.gd: la clave común (sha256 de carpeta del proyecto + texto) y MachineApproval.request {kind, items}. TurnChecks.approval_key delega ahí.
- El controller tiene is_command_approved/approve_command (antes venían en turn_checks_provider) y approve_on_machine para checks y servers; el dock tiene un solo _confirm_on_machine.
- plugin._external_mcp_servers marca los del proyecto con held/approval_key; _mcp_servers los deja afuera y agrega el aviso; _external_mcp_names no los cuenta. Extensions los muestra apagados con «not approved on this machine».
- HarnessSettings security/mcp_approval_explained: el aviso largo una vez por usuario.
- Al aprobar, entran en la próxima sesión (mcpServers va en session/new); no se reinicia la sesión.

## M12 — Que el agente se verifique solo  (8/8, 8 en revisión)

Ideas de godot-ai y Ziva (revisión del 29/10) para que el agente se verifique solo: input por frame, diagnóstico en cada respuesta, playtest con veredicto, validadores de dominio y mover archivos sin romper referencias.

**Hecho cuando:**
- El agente se entera de los errores en la misma tool que los causó, prueba el juego con input reproducible y valida física y TileMaps sin que el usuario lo pida.

### Input del juego por frame: secuencias reproducibles · Revisión

Como godot-ai (game_manage op=input_sequence): una tool que recibe una línea de tiempo de input por frame ({at_frame, action/key/mouse, pressed, strength} y settle_frames) y la reproduce en el juego. Las teclas sueltas de hoy se desfasan con el framerate y las pruebas del evaluador del One-shot no se repiten igual. Devolver el estado al final (captura opcional).

**Prueba:** test_run_tools.test_normalize_by_frame; run-test en Xvfb 4.7.2 y 4.8-beta1: ui_accept sostenido exactamente 9 frames con fuerza 0.40 (las pulsaciones por tiempo dieron 12 y 6 frames en la misma corrida)

**Notas:** game_input y los inputs de run_scene aceptan frame (frames de física desde el inicio), hold_frames (default 6) y settle_frames; strength para acciones. No se mezclan t y frame en una llamada. El probe espera physics_frame en vez de timers.

### Errores nuevos en cada respuesta y estado del editor · Revisión

Como godot-ai: cada respuesta de una tool godot.* trae los errores y warnings nuevos desde la llamada anterior (sin esperar al fin del turno), y las tools que escriben scripts devuelven el diagnóstico de ese archivo. Además, rechazar o esperar con un código claro cuando el editor está importando, corriendo el juego o sin escena abierta (EDITOR_IMPORTING, EDITOR_PLAYING, EDITOR_NO_SCENE), y que run_scene diga 'break' si un error de parseo frena el arranque.

**Prueba:** test_tool_registry.test_new_errors_in_each_response; mcp-test en Xvfb 4.7.2 y 4.8-beta1: un script roto aparece en la respuesta siguiente de editor_state y una sola vez; edit-test, run-test y sessions-test pasan

**Notas:** Cada respuesta de una tool godot.* trae los errores y warnings nuevos desde la respuesta anterior a esa sesión (marca por sesión en ToolRegistry); las tools que ya los traen (run_scene, game_*, get_errors, validate_scripts) solo avanzan la marca. Las tools que escriben esperan hasta 8 s si el editor importa y si no responden EDITOR_IMPORTING. No se hizo: diagnóstico en la misma escritura de un script, porque el agente escribe con fs/write_text_file de ACP y su respuesta no lleva datos; lo cubren el aviso en la tool siguiente y la verificación al terminar el turno. run_scene ya informa 'break' (el juego paró en el debugger por un error).

### Playtest con veredicto: pass, fail o blocked con evidencia · Revisión

Como el Full Game Playtest Agent de Ziva: un playtest que corre la escena, manda input (usar m14-01), toma capturas y lee errores de runtime, y devuelve pass, fail o blocked con evidencia y pasos para reproducir, sin editar el proyecto. Reusar el evaluador del One-shot; que se pueda pedir suelto desde Revisar. Grabación opcional con --write-movie (idea de walker) en .godot_agent/.

**Prueba:** test_findings_parser.test_playtest_verdict, test_review_store.test_playtest_prompt_and_notice; en Xvfb 4.7.2 y 4.8-beta1: review-test (el veredicto del agente falso queda como aviso con evidencia y pasos) y run-test (record: AVI válido, juego cerrado, Movie Maker apagado)

**Notas:** Revisar suma «Playtest…» (pregunta qué comprobar y si grabar) y manda un prompt que pide jugar sin tocar el proyecto y contestar {"playtest": {verdict, summary, evidence, repro}}; el parser lo lee con alias y el controller lo deja como aviso (info si pasó, error si falló, warning si no se pudo). run_scene con record: true usa el Movie Maker del editor (AVI, 30 fps fijos, en res://.godot_agent/playtests/), cierra el juego desde el probe para que el video quede terminado y deja el Movie Maker como estaba. No se reusó el evaluador del One-shot: su rúbrica es de puntajes por criterio; acá hace falta pass/fail/blocked sobre un pedido.

### Validadores de física y de TileMaps · Revisión

Como Ziva (validate-physics-setup, validate-tilemap-structure): tools de solo lectura que revisan capas y máscaras de colisión que no se cruzan, cuerpos sin shape o con shape vacío, y TileMapLayers con celdas fuera del TileSet, huecos o tiles sin colisión donde se espera. El prompt de sistema le pide al agente correrlas después de tocar física o mapas.

**Prueba:** test_validate_tools (física y tilemap sobre árboles armados en el test); mcp-test en Xvfb 4.7.2 las llama por godot.run

**Notas:** validate_physics y validate_tilemap (diagnostics, métodos extendidos por godot.run). Física: cuerpo o área sin forma habilitada, forma sin shape o fuera de un cuerpo, máscara 0, máscara que no cruza ninguna capa de la escena (cuenta las capas de física de los TileSets), capa 0 en un cuerpo. TileMapLayer: sin TileSet, celdas con fuente o tile que el TileSet no tiene, collision_enabled apagado con capas de física, tiles puestos sin polígonos de colisión. El prompt de sistema pide correrlas después de tocar física o mapas.

### Mover y renombrar archivos sin romper referencias · Revisión

Como godot-ai (filesystem_manage move/rename): mover o renombrar desde una tool godot.* llevando el .uid y el .import, buscando referencias por ruta literal en .tscn/.tres/.gd/project.godot; si hay alguna que no se puede actualizar sin riesgo, rechazar. Resultado con outcome (unchanged, rolled_back, partial) y si es seguro reintentar.

**Prueba:** test_file_tools (relative_path y relative_rewrites con archivos, carpeta y script movidos); edit-test en Xvfb 4.7.2: preload("hero.tscn") pasa a preload("actors/hero.tscn")

**Notas:** move_file ya mantenía uid, .uid/.import y referencias res:// (m4-10). Se sumó: rutas relativas de scripts (preload, load, ResourceLoader.load/exists, extends "…") recalculadas desde las carpetas nuevas cuando se mueve el script o lo que nombra; resultado PARTIAL con la lista si un archivo no se pudo escribir, y 'Nothing changed: safe to retry' si el movimiento en sí falla. No se hizo: rechazar por referencias que no se pueden actualizar (rutas armadas en código como "res://levels/" + name no se pueden detectar con certeza; las con prefijo literal de carpeta ya se reescriben).

### Guía de Godot headless en GDScript (lo de walker, sin C#) · Revisión

walker (github.com/nikbearbrown/walker, MIT, engines/godot.md) trae una guía de Godot para agentes en C#; pasarla a GDScript y sumarla a lo que lee el agente (prompt de sistema o una skill en Extensiones), sobre todo para las sesiones en una copia aparte (m11-09), que no tienen las tools godot.* del editor:
1. Cadena de verificación headless: godot --headless --import después de tocar assets, y godot --headless --quit (o --check-only por script) para errores de parseo.
2. Escenas armadas por un script: un 'extends SceneTree' corrido con --headless --script que arma el árbol, le pone owner a cada nodo, lo empaqueta con PackedScene.pack y lo guarda con ResourceSaver; validar contando nodos antes de empaquetar y después de instanciar, y guardar solo si coinciden (sin _ready ni _process en el builder).
3. Catálogo de fallas silenciosas, versión GDScript: owner sin poner (el nodo no se guarda), .gdignore que esconde una carpeta, recursos .tres compartidos que se mutan, no recorrer los hijos de un GLB instanciado, enums adivinados, amortiguar con exp(-rate * delta) para no depender del framerate.
4. Captura determinística: --write-movie con --fixed-fps y --quit-after, en Xvfb, como evidencia en video (se cruza con m14-03).
Verificar cada regla en 4.7.2 y 4.8 antes de escribirla; citar walker (y Godogen) como fuente.

**Prueba:** cada regla probada en 4.7.2 y 4.8-beta1 (owner, .gdignore con PNG y .gd, --check-only exit 1/0, --import con script roto, set_script queda como ext_resource, --write-movie en Xvfb); el builder de la guía corre tal cual en las dos; test_system_prompt (ruta y sin variables sin reemplazar); sessions-test

**Notas:** addons/godot_agent/config/godot_headless.md: cadena de verificación (--import no parsea scripts; --check-only --script sale con 1 si hay error), escenas armadas por un script SceneTree con owner y conteo de nodos (un nodo sin owner se pierde sin error), fallas silenciosas (owner, .gdignore: los assets no se importan pero los scripts sí cargan, recursos compartidos, APIs adivinadas, suavizado dependiente del framerate) y video (--write-movie necesita ventana: en el editor, run_scene record). El prompt de sistema da la ruta ({headless_guide}); las sesiones en una copia la reciben entera en su nota, que antes decía que --quit reportaba errores de scripts. Cita a walker (MIT).

### C# con el mismo soporte que GDScript · Revisión

Pedido del usuario (29/10): que un proyecto en C# tenga lo mismo que uno en GDScript. Hoy el addon da por hecho .gd en:
- Verificación al terminar el turno y get_errors (mcp/tools/diagnostic_tools.gd:66, 111, 200): solo mira .gd. Para C#: dotnet build del proyecto (con el SDK detectado) y sus errores con archivo y línea; si no hay SDK o el editor no es la versión .NET, avisarlo una vez.
- Adjuntar un script a un nodo (mcp/tools/scene_edit_tools.gd:583) y abrir con godot.* (project_tools.gd:182): aceptar .cs.
- Sincronizar el buffer del Script Editor (editor/editor_sync.gd:374): sin editor externo configurado (el default, «None»), Godot .NET abre los .cs en el Script Editor interno (comprobado en 4.7.2 mono, 29/10), así que hay que sincronizarlos igual que los .gd; con Rider o VS Code, recargar el assembly después del build.
- Mover archivos (file_tools.gd:108) y la búsqueda de referencias (m14-05): los .cs referencian por namespace y clase, no por ruta.
- Menciones @ (ui/editor_context.gd:8) y Revisar (hallazgos en el Script Editor; con editor externo, el link debe abrir file:line ahí).
- Completado predictivo para C#: en m14-08.
- Remote watch (session/remote_watch.gd:13): sumar cs y csproj.
- Prompt de sistema y Alt+I: reglas de C# en Godot (clases partial, señales con [Signal] y EventHandler, [Export], nombres en PascalCase, GD.Print), con lo de m14-06 en su versión C# (de walker, engines/godot.md).
- Tests: un proyecto de prueba en C# en la matriz de CI con la versión .NET de Godot (4.7.2 y 4.8).

**Prueba:** test_csharp_build (parser y compilación real del fixture si hay dotnet); test_system_prompt (reglas solo con .csproj); en el editor Godot .NET 4.7.2 (Xvfb): create_scene con Hero.cs nuevo, validate_scripts sin errores, .cs roto → 'line 7: CS0103' en validate_scripts y en la verificación de fin de turno

**Notas:** Hecho: core/csharp_build.gd (dotnet build en inglés, errores ruta(línea,col) a res://); validate_scripts acepta .cs y, sin paths, compila el C# si hay .csproj (avisa si hay .cs sin .csproj); la verificación de fin de turno compila si cambió algún .cs; attach_script/create_scene crean .cs como partial class con el nombre del archivo (y avisan si el editor no es .NET); set_autoload acepta .cs; menciones @ y Remote Control suman .cs; move_file avisa que la clase tiene que llamarse como el archivo; abrir un hallazgo en un .cs no salta a la pestaña Script si se abre en un editor externo; reglas de C# en el prompt solo con .csproj; job de CI con Godot .NET 4.7.2 + dotnet 8. De paso: validate_scripts sin paths saltea los scripts del harness (con el addon instalado no entraba en 60 s). La sincronización de buffers ya era genérica (por Script) y cubre los .cs abiertos.

### Completado predictivo para C# en el Script Editor · Revisión

Comprobado en Godot 4.7.2 .NET (29/10, Xvfb, editor externo en «None», el default): un .cs se abre en el Script Editor interno como un CodeEdit común (ScriptTextEditor), pero sin nada para C#: resaltado EditorPlainTextSyntaxHighlighter (texto plano), code_completion_enabled = false, 0 opciones al pedir completado después de 'Velocity.', y el panel de métodos vacío. El predictivo llenaría un hueco real.
- completion_controller.gd:246 solo se engancha a .gd: sumar .cs.
- El proveedor LLM sirve tal cual (le llega el texto); el local (project_index.gd, context_rules.gd) está hecho para GDScript: índice de símbolos C# (clases partial, métodos, [Export], señales [Signal]) y la API de Godot en PascalCase (GetVector, MoveAndSlide).
- De paso, ver si conviene un resaltado de C# propio (el de Godot es texto plano), con un CodeHighlighter y las palabras clave que ya da CSharpLanguage.
- Probar con Godot .NET 4.7.2 y 4.8 en Xvfb, con una copia autocontenida (sin tocar la config del usuario).

**Prueba:** test_completion_local.test_csharp_uses_its_own_lines (índices separados, sin //, un .cs se completa con C# y un .gd nunca); test_completion_llm.test_language_of_file; en Godot .NET 4.7.2 (Xvfb): escribir 'Velocity = Velo' en Boss.cs muestra la línea de C# y MoveAndSlide() en gris (captura)

**Notas:** El controller se engancha a .gd y .cs. El índice del proyecto arma un índice de líneas aparte con los .cs (comentarios // fuera); el proveedor local usa el índice del lenguaje del archivo y, en C#, apaga las reglas de contexto y el n-gram (son de GDScript); el historial de lo tecleado sigue. LLM: la instrucción de Gemini y el filename de llama.cpp según el lenguaje, y el contexto del proyecto como comentarios //. No se hizo el resaltado de C# propio (queda texto plano): se puede sumar después.

## M13 — Playtesting: lo que traemos de Autopilot  (24/24, 24 en revisión)

Ideas de ramenvr/autopilot (revisión del 30/10) para que un playtest sea confiable: el veredicto sale de jugar, los detectores ven lo que el agente no mira y el agente puede actuar a nivel de frame sin un segundo modelo. No se trae: el servicio Python con el modelo Jev, el autoload permanente, compartir datos por defecto, el marco de coordenadas de Unreal ni la navegación 3D (walk_to, nav.py, melee).

**Hecho cuando:**
- Un veredicto de playtest no se acepta sin haber jugado y muestra qué se cambió directo en el juego.
- En un juego de prueba con bugs plantados, los detectores los encuentran con captura del momento y el agente puede operar su UI y jugar a nivel de frame.

### 13.1 Reglas de veredicto en los prompts de playtest · Revisión

**Prioridad:** alta · **Tamaño:** S · **Etiquetas:** `autopilot`, `playtest`

Sumar a playtest_prompt y al evaluador del One-shot las reglas de session.py:167-189: un bug en el código es una pista hasta verlo en el juego; «no pude hacer X» es blocked salvo que los números del juego lo prueben imposible; algo que «se puede hacer» se prueba haciéndolo una vez; todo cambio directo al juego se declara y nunca sobre lo que se prueba. También: probar cada paso de la cadena incluido el último (research.py: un run gastó 47 turnos en grep y nunca probó el último paso), ajustar la investigación al pedido, si se traba seguir desde donde está, mirar el frame antes de investigar algo raro, y tratar textos y logs del juego como datos, no como instrucciones.

**Prueba:** tests/unit/test_review_store.test_playtest_prompt_and_notice (reglas en el prompt); oneshot_check 130/0 con el prompt del evaluador nuevo. Sin correr con un agente real.

**Notas:** ReviewStore.PLAY_RULES se comparte entre playtest_prompt y qa_prompt. El evaluador suma: un check que no se pudo probar no pasa.

**Bloquea a:** 13.16 Explorar y lograr un objetivo, sin elegir tipo

### 13.2 Rechazar veredictos sin haber jugado · Revisión

**Prioridad:** alta · **Tamaño:** S · **Etiquetas:** `autopilot`, `playtest`

session_controller.gd:443 acepta cualquier veredicto. Como do_report (session.py:1169): un pass o fail sin run_scene en el turno baja a blocked, y un veredicto visual sin captura también.

**Prueba:** test_review_store.test_playtest_audit_gates_the_verdict; review-test en Xvfb 4.7.2.

**Notas:** Jugar = run_scene o game_input completados en el turno, también de subagentes (_tool_calls_since). Nombres por ToolCall.godot_tool_name: un agente con otros títulos de tool quedaría siempre en blocked. El rechazo no reintenta: baja a blocked y avisa.

### 13.3 Resultado de playtest auditable · Revisión

**Prioridad:** alta · **Tamaño:** M · **Etiquetas:** `autopilot`, `playtest`

Hoy el aviso solo trae evidencia y pasos. Como _render_result de dock.gd: avisos arriba del veredicto con lo que hay que saber para confiar en él, sección «Cambiado directo, no jugando» con los game_set y game_call que el harness contó solo (no depende de que el agente los declare), evidencia con tiempo de juego y, si no hay video, por qué.

**Prueba:** test_review_store.test_playtest_audit_in_the_notice; review-test en Xvfb 4.7.2 (el aviso lista game_set).

**Notas:** game_call cuenta como cambio aunque solo lea, porque no se puede saber. El tiempo de la evidencia se le pide al agente: las tools todavía no devuelven tiempo de juego (se puede sumar en m15-10). El video se detecta por el texto de run_tools (Recording: / The recording was not written).

### 13.4 Input: mouse-look y texto en game_input · Revisión

**Prioridad:** alta · **Tamaño:** S · **Etiquetas:** `autopilot`, `playtest`

Por lectura de _event en playtest_probe.gd (falta reproducirlo): InputEventMouseMotion va sin relative, así que un juego en primera persona que lea event.relative recibe cero; InputEventKey va sin unicode, así que probablemente no se pueda escribir en un LineEdit. Autopilot carga ambos (playtest.gd:658). Reproducir con un test y arreglar.

**Prueba:** tests/run_in_xvfb.sh --godot-agent-run-test en 4.7.2, función _check_playtest_game: texto en un LineEdit y mira con relative; test_run_tools.test_normalize_look_and_text.

**Notas:** Se confirmó: faltaban relative y unicode. Pasos nuevos {look} y {text}; un {move} también calcula relative.

### 13.5 Seguir tras un error de script durante un playtest · Revisión

**Prioridad:** alta · **Tamaño:** S · **Etiquetas:** `autopilot`, `playtest`

Hoy un error deja el juego frenado en el debugger y run_tools.gd:478 pide continuar a mano, así que la primera falla termina el playtest. Autopilot manda continue solo mientras el agente corre (debugger.gd:42) y el error sigue llegando. Hacerlo en Playtest y en el evaluador; en Construir sigue frenando, porque ahí conviene arreglarlo en el momento. Un run manual tampoco cambia.

**Prueba:** tests/run_in_xvfb.sh --godot-agent-run-test en 4.7.2, función _check_playtest_game y run_broken con continue_on_error.

**Notas:** Parámetro continue_on_error de run_scene, que el prompt de Playtest y el del evaluador piden. Construir no lo pasa, así que frena. Tope de 30 pausas por run: un error por frame deja el juego parado. También saltea breakpoints del usuario mientras está activo.

### 13.6 Juego de prueba con bugs plantados · Revisión

**Prioridad:** alta · **Tamaño:** M · **Etiquetas:** `autopilot`, `playtest`

Sin esto, los cambios a detectores y prompts no se pueden medir. Como Orchard Walk (plugin/godot/tests/game): un script que llama un método sobre null, algo que se hunde en el piso, un HUD «12/10», UI con menú. Más una suite de pedidos con resultado esperado, como bench/example.json.

**Prueba:** La usa run_check. tests/fixtures/playtest_game y tests/playtest_suite.json.

**Notas:** La suite se corre a mano con un agente real: no entra en CI porque gasta cuota. Todavía no se corrió.

**Bloquea a:** 13.7 Detectores dentro del juego

### 13.7 Detectores dentro del juego · Revisión

**Prioridad:** alta · **Tamaño:** M · **Etiquetas:** `autopilot`, `playtest`

lib/detectors.gd: NaN en transforms, cuerpos fuera del mundo, caídas de más de 8 s, frames de más de 0,75 s, textos de HUD como 12/10. Con deduplicación por firma normalizada (avisar en 1, 10, 100, 1000). Salen junto a los errores [game]. No hace falta su Logger: ya está ErrorCollector. Apagar el de frames largos al grabar, porque Movie Maker distorsiona los tiempos. autopilot es Apache 2.0: si se copia código, conservar el aviso de licencia.

**Prueba:** tests/run_in_xvfb.sh --godot-agent-run-test en 4.7.2, función _check_playtest_game: hud_fraction, out_of_world, hitch; nan silenciado.

**Notas:** Sin probar long_fall en vivo (tarda 8 s). hitch se descarta justo después de una pausa del debugger y con Movie Maker.

**Bloquea a:** 13.8 Captura automática al detectar un problema

**Bloqueada por:** 13.6 Juego de prueba con bugs plantados

### 13.8 Captura automática al detectar un problema · Revisión

**Prioridad:** media · **Tamaño:** S · **Etiquetas:** `autopilot`, `playtest`

La foto sale en el momento del hallazgo, con un mínimo de tiempo entre capturas y una por firma (runtime.py:594). Va junto con los detectores.

**Prueba:** tests/run_in_xvfb.sh --godot-agent-run-test en 4.7.2, función _check_playtest_game: la foto queda en disco.

**Notas:** Una foto por firma, 5 s entre fotos, se guardan las últimas 50.

**Bloqueada por:** 13.7 Detectores dentro del juego

### 13.9 game_ui y game_ui_act · Revisión

**Prioridad:** alta · **Tamaño:** M · **Etiquetas:** `autopilot`, `playtest`

Hoy el agente adivina los píxeles de click: [x, y]. lib/ui.gd lista los controles visibles con id, tipo, texto, habilitado y posición, y actúa con un clic real en el viewport, así que un overlay encima lo bloquea igual que a un jugador. No copiar su salida: si nadie toma el clic emiten pressed igual; nosotros lo reportamos como problema. Marcar los atajos que no son input real (OptionButton y set cambian el valor directo, ui.gd:207). Probar con stretch: coordenadas de viewport contra ventana. autopilot es Apache 2.0: si se copia código, conservar el aviso de licencia.

**Prueba:** tests/run_in_xvfb.sh --godot-agent-run-test en 4.7.2, función _check_playtest_game: clic, overlay que bloquea, opción marcada como no input.

**Notas:** Sin fallback a emitir pressed: si nadie toma el clic es un error. Sin drag de Autopilot. Sin probar con stretch.

### 13.10 Foto inicial en run_scene · Revisión

**Prioridad:** media · **Tamaño:** S · **Etiquetas:** `autopilot`, `playtest`

run_scene devuelve solo errores y Output. Sumar escena, jugador, controles, textos y botones en pantalla (session.py:976: «la primera prueba de cada run buscaba esto»).

**Prueba:** tests/run_in_xvfb.sh --godot-agent-run-test en 4.7.2, función _check_playtest_game.

**Notas:** Además todas las respuestas game_* llevan tiempo de juego y frame, así la evidencia puede citarlo.

### 13.11 game_find: buscar nodos por clase, grupo o nombre · Revisión

**Prioridad:** baja · **Tamaño:** S · **Etiquetas:** `autopilot`, `playtest`

game_tree corta a 300 líneas y profundidad 4. find en lib/world.gd:110: clase (también class_name), group:<nombre> y parte del nombre.

**Prueba:** tests/run_in_xvfb.sh --godot-agent-run-test en 4.7.2, función _check_playtest_game.

### 13.12 game_script: scripts cortos dentro del juego · Revisión

**Prioridad:** alta · **Tamaño:** L · **Etiquetas:** `autopilot`, `playtest`

Versión de su probe y sus ejecutores: el agente escribe un GDScript corto que corre dentro del juego, con lecturas, inputs y esperas, y devuelve lo que imprimió. Da reflejos a nivel de frame sin un segundo modelo y muchas comprobaciones en un turno; evita lecturas en lote y un expect en game_input. Kit mínimo: press, hold, release, wait, until, look_at. Cada helper devuelve Result(ok, why, data) con diagnóstico, como kit/control.py, porque eso separa fail de blocked. Medir antes de asumir (calibrate_look). Tiempo máximo: al vencer suelta las teclas y pausa (session.py:744-760). Registrar lo apretado y soltarlo siempre. No portar _Pace, _lead ni on_way: compensan correr fuera del juego.

**Decisiones:**
- ✓ ¿Cómo se evita que game_script escriba archivos cuando el evaluador tiene prohibido editar?
  Por qué: Un GDScript dentro del juego puede usar FileAccess, y eso esquiva el «no editar» del evaluador, que es justo donde más sirve la tool.
  Descartado: Comprobar con git que el turno no cambió nada y fallar si cambió; no habilitarla en el evaluador; ejecutarla sin FileAccess (no parece posible en GDScript).
  Respuesta: Resuelto sin consultar para no frenar el hito: game_script rechaza por nombre FileAccess, DirAccess, ResourceSaver, ConfigFile, OS.execute y similares, y queda disponible para el evaluador. Frena descuidos, no a quien quiera esquivarlo. Revisar si hace falta algo más fuerte.

**Prueba:** tests/run_in_xvfb.sh --godot-agent-run-test en 4.7.2, función _check_playtest_game: input, say, movement, no compila, API bloqueada, error propio, vencimiento que suelta y pausa; test_blocked_api.

**Notas:** look_at probado en 3D sin verificar la precisión exacta. La guarda de archivos es una lista de nombres: frena descuidos, no a quien quiera esquivarla.

### 13.13 Pausa con avance por frames · Revisión

**Prioridad:** alta · **Tamaño:** S · **Etiquetas:** `autopilot`, `playtest`

Que el juego no siga mientras el agente piensa: pausa, input, N frames, pausa. El probe ya corre en PROCESS_MODE_ALWAYS. Autopilot pausa solo entre tool calls y sacó los runs por turnos (dock.gd:2353), con motivo sin documentar: probarlo pronto con un juego real. Los juegos que miden tiempo con Time.get_ticks_* siguen corriendo durante la pausa.

**Prueba:** tests/run_in_xvfb.sh --godot-agent-run-test en 4.7.2, función _check_playtest_game: 10 frames exactos, sigue en pausa, input por frame llega.

**Notas:** Probado con el juego de prueba, no con un agente real ni un juego real como pedía la tarea. Autopilot sacó los runs por turnos sin decir por qué.

### 13.14 Números de movimiento del jugador · Revisión

**Prioridad:** baja · **Tamaño:** S · **Etiquetas:** `autopilot`, `playtest`

movement() (lib/world.gd:348) y peak = v²/2g permiten probar con datos del juego que un salto es imposible, que es lo que pide la regla de veredicto. Solo si apuntamos a juegos con salto.

**Prueba:** tests/run_in_xvfb.sh --godot-agent-run-test en 4.7.2, función _check_playtest_game: movement lee JUMP_VELOCITY.

**Notas:** En el kit de game_script: game.movement().

### 13.15 Memoria por juego · Revisión

**Prioridad:** media · **Tamaño:** M · **Etiquetas:** `autopilot`, `playtest`

Hoy no hay nada parecido. notes.md con hechos verificados (controles, mecánicas, trampas) y los scripts que sirvieron, más qué archivos cambiaron desde el último run y la regla de volver a comprobar una nota sobre código cambiado (memory.py, codex.py:changes).

**Prueba:** test_review_store.test_playtest_memory; review-test.

**Notas:** review/playtest_memory.gd. El agente pasa notes y stale_notes en su JSON y el harness escribe: un playtest no modifica el proyecto.

**Bloquea a:** 13.17 Not a bug persistente, Verify a fix y Run again

### 13.16 Explorar y lograr un objetivo, sin elegir tipo · Revisión

**Prioridad:** media · **Tamaño:** S · **Etiquetas:** `autopilot`, `playtest`

Sumar explorar y objetivo al veredicto actual. Una sola caja de texto: el agente devuelve kind en su JSON. Un hallazgo es algo que se vio al juego hacer mal, no algo que el agente no logró.

**Prueba:** test_review_store.test_playtest_kinds_and_limits.

**Notas:** verdict explored; goal usa pass/fail.

**Bloqueada por:** 13.1 Reglas de veredicto en los prompts de playtest

### 13.17 Not a bug persistente, Verify a fix y Run again · Revisión

**Prioridad:** media · **Tamaño:** M · **Etiquetas:** `autopilot`, `playtest`

Verify a fix rellena el prompt y Run again repite el pedido exacto. Not a bug se guarda por firma en la memoria del juego para que no vuelva a aparecer: en el código público de Autopilot el feedback solo se encola (editor_bridge.gd:257), así que no se copia tal cual. review_store.gd:65 ya tiene dismiss.

**Prueba:** review-test: Not a bug saca el hallazgo y queda en memoria.

**Notas:** Verify a fix y Run again sin probar por UI. review/playtest_memory.mark_not_a_bug: los detectores dejan de reportar la firma.

**Bloqueada por:** 13.15 Memoria por juego

### 13.18 Mostrar el hallazgo en la escena · Revisión

**Prioridad:** media · **Tamaño:** S · **Etiquetas:** `autopilot`, `playtest`

_show_in_level de dock.gd: busca el nodo por nombre o el más cercano y avisa cuál fue, lo selecciona y encuadra la cámara.

**Prueba:** review-test: el botón contesta en el chat.

**Notas:** ui/dock/finding_locator.gd. Encuadrar la cámara sin comprobar a ojo.

### 13.19 Tope de tiempo por playtest · Revisión

**Prioridad:** baja · **Tamaño:** S · **Etiquetas:** `autopilot`, `playtest`

El Playtest de Revisar pregunta solo qué comprobar y si grabar. Sumar minutos máximos, recordados por proyecto, y que cada resultado de tool diga cuánto queda.

**Prueba:** test_review_store.test_playtest_kinds_and_limits.

**Notas:** Tope blando: se le avisa al agente en cada resultado, el turno no se corta. Default 15 min, por proyecto.

### 13.20 game_watch: cambios durante una ventana de tiempo · Revisión

**Prioridad:** media · **Tamaño:** M · **Etiquetas:** `autopilot`, `playtest`

watch_* en lib/sight.gd registra con marca de tiempo: se movió, giró, cambió de tamaño, se mostró u ocultó una parte, una luz, una animación. Hoy un flash de 0,3 s pasa entre dos tool calls. autopilot es Apache 2.0: si se copia código, conservar el aviso de licencia.

**Prueba:** tests/run_in_xvfb.sh --godot-agent-run-test en 4.7.2, función _check_playtest_game: ve Flash hidden/shown de 0,2 s.

### 13.21 Descripción visual a ciegas · Revisión

**Prioridad:** media · **Tamaño:** M · **Etiquetas:** `autopilot`, `playtest`

Antes de mirar, el agente escribe cómo se vería si es cierto y si es falso; va en el prompt y ayuda al criterio visual del evaluador. Después, según el backend, un subagente que recibe frames y preguntas abiertas, nunca qué se comprueba (frame-describer.md, vision.py).

**Prueba:** Solo texto de prompt (PLAY_RULES).

**Notas:** Sin subagente propio: el prompt pide usarlo si el backend puede, con las rutas de game_frames y preguntas abiertas. Sin correr con un agente real.

### 13.22 Búfer de frames recientes · Revisión

**Prioridad:** media · **Tamaño:** M · **Etiquetas:** `autopilot`, `playtest`

Hoy el agente no puede ver qué pasó hace 2 s. Lectura asíncrona para no trabar el juego (lib/media.gd), con tiempo de juego por frame. autopilot es Apache 2.0: si se copia código, conservar el aviso de licencia.

**Prueba:** tests/run_in_xvfb.sh --godot-agent-run-test en 4.7.2, función _check_playtest_game bajo Compatibility (Xvfb sin GPU).

**Notas:** El camino asíncrono de Forward+/Mobile no se ejecutó: solo el fallback get_image. Frames en disco del editor en vez de memoria del juego.

**Bloquea a:** 13.23 Reproductor de la grabación en el dock

### 13.23 Reproductor de la grabación en el dock · Revisión

**Prioridad:** baja · **Tamaño:** M · **Etiquetas:** `autopilot`, `playtest`

El AVI solo llega como una ruta y obliga a cerrar el juego. Flipbook (ui/widgets.gd:570) reproduce JPEG cargando solo los frames cercanos. Va después del búfer. autopilot es Apache 2.0: si se copia código, conservar el aviso de licencia.

**Prueba:** tests/run_in_xvfb.sh --godot-agent-run-test en 4.7.2, función _check_playtest_game: abre, avanza, muestra. review-test: el aviso ofrece la acción.

**Notas:** ui/flipbook_dialog.gd.

**Bloqueada por:** 13.22 Búfer de frames recientes

### PlaytestMemory.brief() mete firmas not-a-bug con nombres de nodos en el prompt de playtest sin sobre · Revisión

**Prioridad:** baja · **Tamaño:** S · **Etiquetas:** `security`

Quedó afuera de los arreglos de sobres <untrusted> de la revisión de sm/next2 (fix-a, puntos #2/#16–#18).
- PlaytestMemory.brief() arma la parte del prompt de playtest con las firmas marcadas como not-a-bug. Esas firmas traen nombres de nodos del juego, y van sin sobre.
- Un nodo con un nombre armado puede meter texto que el agente lee como instrucciones del harness.
- Arreglo: envolver con UntrustedText (wrap/close_cut) lo que viene del juego en brief(), como run_scene y format_finding.
- Test: una firma con un nombre de nodo malicioso sale dentro de un sobre en el prompt, y ReviewStore/la memoria la siguen leyendo bien.

**Prueba:** - `godot --headless --script res://tests/run_all.gd -- review_store`: test_playtest_memory_not_a_bug_in_envelope pasa. Sin el arreglo falla («las firmas van en sobre»).
- run_all completo en 4.7.2 (613 tests): 0 fallos. En un worktree recién creado, test_resource_values falla hasta que el editor importa el proyecto, porque no hay clases globales todavía.
- review-test: el check «Not a bug: el brief del playtest la lleva en sobre» pasa. El review-test da 4 fallas más, que también salen en sm/next2 sin este cambio (recursión infinita de m12-49 en agent_dock).

**Notas:** Commit en la rama sm/m15-24 (desde sm/next2 1a8be90), sin mergear: entra en el release siguiente.
- PlaytestMemory.brief() pone cada firma not-a-bug en su línea dentro de un sobre (UntrustedText.wrap) y sella el bloque con un nonce nuevo (seal + new_nonce), como run_error_watcher y el aviso de regresiones. El prompt no es resultado de una tool, así que el registry no lo sella. Las instrucciones del servidor MCP ya explican los sobres.
- not_a_bug.json guarda las firmas tal cual, y run_scene las silencia por igualdad, igual que antes.
- Las notas de playtests anteriores quedaron sin sobre: las escribe el agente como hechos verificados, no vienen directo del juego.
- Al probarlo apareció un bug ajeno en sm/next2 (avisado a agent-harness-81): _refresh_machine_chips ↔ _refresh_state_line se llaman sin fin mientras la sesión está en STARTING (e6d6eed, m12-49). Da stack overflow y 4 fallas en review-test.

## M14 — Playtesting confiable y regresiones  (17/17, 17 en revisión)

Validar M13 con un agente real y en CI, cerrar lo que aún puede engañar (evaluador sin controlar, breakpoints salteados) y convertir un playtest que pasó en un test de regresión que corre sin agente.

**Hecho cuando:**
- run-test y review-test corren en CI; los tests no dependen de la configuración local.
- La suite de playtest se corrió con un agente real y sus resultados están registrados.
- Un playtest que pasó se puede repetir sin agente.

### 14.1 Aislar los tests de la configuración local · Revisión

**Prioridad:** alta · **Tamaño:** S · **Etiquetas:** `playtest`

Los 3 checks de run manual de run-test dependen de project_config.tres y test_completion_local falla en una copia con archivos locales.

**Prueba:** run_all 393/0 y run-test 0 fallas en la copia local.

**Notas:** Causa de test_completion_local: la recencia baja el puntaje a medida que los archivos del fixture envejecen (mtime), y a los ~9 días una línea que aparece una sola vez deja de sugerirse; en CI el checkout siempre es nuevo. El test ahora fija la hora (ProjectContext.fixed_now). El comportamiento de producto queda aparte en m16-07.

### 14.2 run-test y review-test en CI · Revisión

**Prioridad:** alta · **Tamaño:** S · **Etiquetas:** `playtest`

Las herramientas de M13 solo corrieron en local con 4.7.2.

**Prueba:** CI en 4.7.2 y 4.8-beta2: run-test y review-test en verde (a53c78d).

**Notas:** Paso nuevo en ci.yml con xvfb y mesa.

### 14.3 Runner de la suite de playtest con un agente real · Revisión

**Prioridad:** alta · **Tamaño:** M · **Etiquetas:** `playtest`

tests/playtest_suite.json nunca se corrió: manda cada pedido a un agente real y compara con el resultado esperado. Gasta cuota, fuera de CI.

**Prueba:** tests/run_in_xvfb.sh <godot> --godot-agent-claude-playtest-suite: 7/7 con Claude Code real en 4.7.2, fixture sin pistas; regresiones 2 de 2, repetidas sin agente y detectando su sabotaje. 25 a 63 s por pedido.

**Notas:** Encontró dos bugs de v0.1.12 que el agente falso no ve: el modo plan trababa el Playtest y el static var del tope de tiempo hacía caer el editor al segundo run_scene. También _busy trabado tras un error interno. La causa del static var quedó entendida en m16-08 (el set marca el recurso GDScript como editado y el play lo reescribe y recarga). Salvedad resuelta: sin los comentarios «Bug plantado» en el fixture, la suite completa volvió a dar 7/7 (2026-10-31), y las dos regresiones que dejó el agente (A, E) pasan sin él y fallan con el sabotaje de cada pedido (m16-09).

### 14.4 Controlar al evaluador del One-shot · Revisión

**Prioridad:** alta · **Tamaño:** S · **Etiquetas:** `playtest`

El rechazo de veredictos y la lista de cambios directos solo aplican al Playtest: el evaluador puede aprobar sin jugar.

**Prueba:** oneshot_check, escenario «evaluador sin jugar»: 134/0.

**Notas:** Sin jugar, el reporte no cuenta sea que apruebe o falle: el run termina como «couldn't reach a verdict», los checks no quedan verificados y qa-N.md lo dice.

### 14.5 continue_on_error no saltea breakpoints · Revisión

**Prioridad:** media · **Tamaño:** S · **Etiquetas:** `playtest`

Hoy también pasa por encima de los breakpoints del usuario.

**Prueba:** run-test: stop_here frena el run con continue_on_error.

**Notas:** Se distingue por el texto del debugger (empieza con Breakpoint).

### 14.6 Repetir un playtest sin agente · Revisión

**Prioridad:** alta · **Tamaño:** L · **Etiquetas:** `playtest`

Un playtest que pasó deja su game_script: volver a correrlo sin agente da regresiones sin gastar tokens, también en CI.

**Prueba:** test_playtest_regressions; run-test (una pasa, una falla, dice cuál, juego cerrado); suite real A,E: el agente dejó 2 de 2 y volvieron a pasar sin él.

**Notas:** review/playtest_regressions.gd. El agente deja `regression` en su JSON al pasar; run_tools.run_regression lo corre con game_script. Solo desde el editor: correrlas en CI por línea de comandos no está hecho, porque el probe necesita el debugger del editor. Un script puede no fallar nunca si está mal escrito: nadie revisa que detecte el bug.

### 14.7 Una línea que aparece una vez deja de sugerirse a los ~9 días · Revisión

**Prioridad:** media · **Tamaño:** S · **Etiquetas:** `completado`

Lo destapó m16-01: con recencia 0.5 + 0.5·exp(-días/7), una línea de una sola aparición en otra carpeta queda bajo el umbral cuando su archivo envejece. D27 dice que una sola aparición alcanza. Decidir si el umbral o el piso de recencia cambian, midiendo con tests/completion_eval.

**Decisiones:**
- ✓ La recencia ya no entra en la evidencia (support); umbral y piso de recencia quedan igual
  Por qué: La recencia sirve para preferir lo que se está tocando frente a otros candidatos, no para decidir si hay evidencia. Medido: con el proyecto envejecido vuelve a 17/18 sin cambiar nada a 0 días.
  Descartado: Bajar el umbral (sube los falsos positivos en todos los casos); subir el piso de recencia a ~0,7 (la recencia casi deja de distinguir); recencia relativa al archivo más nuevo (un archivo viejo en un proyecto activo sigue sin alcanzar).

**Prueba:** run_all completion: 50 tests 0 fallas; test_completion_local: «una sola aparición en un proyecto viejo alcanza» (falla sin el cambio) y evidence = 6.0 con raw = 5.5; test_completion_eval con edad fija 0. run_completion_eval --age=0/30/365: 17 exactas, 18 correctas, 2 FP en los tres.

**Notas:** Medido con tests/completion_eval y `--age=N` nuevo (todos los archivos con N días desde el más nuevo; sin eso el eval dependía de cuándo se copió el repo). Antes, rule+retrieval+ngram: 17 exactas / 18 correctas a 0 días, 14 / 16 a 30 y a 365 días. La cuenta: support = 1 − e^(−raw) y una aparición lejana da raw = recencia, que baja de ln 2 a los ~7 días. El envejecimiento parejo no cambia las proporciones entre candidatos: solo apagaba el umbral, contra D27.
Cambio: la recencia queda solo en raw/Σraw (desempata entre archivos de distinta edad) y el support usa la evidencia sin recencia (LineIndex.weight(..., false) → "evidence"). Resultado: 17/18 a 0, 30 y 365 días; a 0 días las métricas son idénticas a las de antes. Umbral y piso de recencia sin tocar. D27 actualizada en decisions.md.

### 14.8 El editor se cae al correr regresiones tras una secuencia larga de pruebas · Revisión

**Prioridad:** alta · **Tamaño:** M · **Etiquetas:** `playtest`, `bug`

Se reproduce siempre: en run_check, llamar _check_regressions al final de _check_playtest_game (después de pausa, game_script, watch, frames y el reproductor). Antes del SIGSEGV aparecen errores progress_dialog.cpp «!tasks.has(p_task)» dentro de play_custom_scene, y el stack de GDScript mezcla corrutinas: parece una iteración anidada mientras se lanza el juego, que reanuda corrutinas. No se cae con un run_scene por HTTP en ese mismo punto, ni con las regresiones al principio. El check se movió al principio para no tapar el resto: esto sigue sin resolver. Puede ser la misma causa de fondo que la caída que se fue al sacar el static var de run_tools.gd.

**Prueba:** run-test con las regresiones al final, justo después de liberar el reproductor (el orden que se caía siempre), check de rescate con reimport y regresiones con sabotaje: 0 fallas y sin «p_I->data» en 4.7.2 y 4.8-beta2. Sin los arreglos: SIGSEGV. review-test 0, run_all 396/0, plugin_cycle_check, export_check y crash_check bien.

**Notas:** Eran tres causas, todas en 4.7.2.
1) ProgressDialog. ProgressDialog::_reparent_and_show() de Godot (4.7.2 y master) cuelga el ProgressDialog del editor de la última ventana exclusiva y no lo devuelve. El reproductor de filmaciones era exclusivo y el test lo liberaba en el mismo frame en que las regresiones lanzaban el juego; la iteración anidada del progreso procesaba ese queue_free y se llevaba puesto al ProgressDialog («!tasks.has(p_task)» y SIGSEGV). No dependía de la secuencia larga. En uso real pasa con cualquier diálogo nuestro abierto mientras el editor muestra un progreso (play, reimport por archivos del agente). Arreglo: ui/editor_windows.gd (free_later / rescue_progress) en los diálogos que se liberan solos y en _exit_tree del plugin; el reproductor ya no es exclusivo.
2) Autoload de playtest. add_autoload_singleton/remove_autoload_singleton en _build() y al arrancar o parar el juego pasan por el UndoRedo y update_autoload del editor; en 4.7.2 cada play después del primero imprimía «List::erase: p_I->data != this» (lista del editor corrupta, no en 4.8) y tras varios runs el editor se caía. Aislado con experimentos: play/stop puro sin el probe no lo da; con el probe sí, en cada play. Ahora el alta y la baja son ProjectSettings.set_setting + save (el juego lee project.godot del disco). crash_check y export_check siguen bien.
3) static var de m16-03, otra causa ya entendida: asignar RunTools.playtest_deadline_ms desde otro script es un set sobre el recurso GDScript, que en el editor lo marca como editado; el play siguiente guarda los recursos editados, reescribe run_tools.gd (mtime cambiado durante el test) y lo recarga con _run_scene a mitad de camino. Reproducido con la versión vieja. Ahora run-test falla si el editor reescribe algún .gd del addon.
De paso: look_at fallaba en 4.8 en la copia local porque game.mouse() mandaba el movimiento donde había quedado el mouse tras un clic (sobre HUD/Overlay) y la GUI se lo comía; GameUi.free_point lo manda a un punto libre (también el paso look del probe). Y los checks ya no dejan main_run_args guardado en project.godot.

### 14.9 Regresiones por línea de comandos y control de que detectan el bug · Revisión

**Prioridad:** alta · **Tamaño:** M · **Etiquetas:** `playtest`

Lo que dejó abierto m16-06: las regresiones solo corrían desde el editor (el probe necesitaba el debugger), y nadie comprobaba que el script del agente detecte el bug (uno mal escrito pasa siempre).

**Decisiones:**
- ✓ El control de "detecta el bug" es un sabotaje escrito a mano (suite y fixtures); al agente no se le pide escribir uno
  Por qué: Pedirle al agente el sabotaje suma tokens y cambia el prompt del playtest, que habría que volver a medir; y un sabotaje del agente puede ser tan vacío como su script. La suite mide si sus regresiones discriminan.
  Descartado: Pedir `sabotage` en el JSON del agente y verificarlo al guardar; heurística de correr el script sin inputs (falla con invariantes que no necesitan jugar).

**Prueba:** tests/regressions_cli_check.sh (paso nuevo en CI): pass → 0, fail → 1, vacuous (pasa también con el sabotaje) → 1, en 4.7.2 y 4.8-beta2. run-test: con el sabotaje, la de start detecta y la vacía no. test_review_store: detects.

**Notas:** playtest/regression_cli.gd: SceneTree para `godot --headless --path . --script ...`; abre cada escena, espera lo mismo que el botón y corre el game_script con el probe en modo standalone (sin debugger: los errores del juego no frenan, como continue_on_error). Exit 0/1/2. Formato: `sabotage` opcional, un script que rompe en el juego lo que la regresión prueba; con él tiene que terminar sin devolver true (PlaytestRegressions.detects: un error o un vencimiento no cuentan). Lo usan el CLI, run_regression(entry, setup) en el editor y la suite real (sabotajes para A y E en playtest_suite.json). El agente no escribe sabotajes: el control de sus regresiones es el de la suite. Documentado en wiki Review/Revisar.

### Correr las regresiones de playtest en el CI del juego del usuario · Revisión

**Prioridad:** media · **Tamaño:** M · **Responsable:** agent-harness-a3 · **Etiquetas:** `idea`

M14 convierte un playtest que pasó en un test de regresión que corre sin agente («Correr regresiones»). Falta que el usuario lo corra en su CI: una acción (botón en el panel de regresiones y tool MCP para el agente) que genere .github/workflows/godot-agent-regressions.yml en el proyecto del juego, con la versión de Godot del editor, headless (o Xvfb si las regresiones necesitan render), que corra las regresiones grabadas y suba capturas y el informe como artifacts cuando fallen. Nunca pisar un workflow existente sin confirmación. Documentarlo en la wiki. Verificar el yml con actionlint si está y con un run real en un repo de prueba solo si el usuario lo autoriza.

**Decisiones:**
- ! Generador estático RegressionsWorkflow (yml como texto, sin plantilla externa) con la versión del editor y descarga directa del release de Godot; headless por defecto y `render` opcional bajo Xvfb; artifacts solo al fallar; el botón pide confirmación con un aviso «Overwrite» y la tool exige overwrite: true; validación local solo estructural · sin revisar
  Por qué: El workflow repite lo que ya hace el CI del propio repo (install-godot.sh: estables de godotengine/godot, betas de godot-builds) pero inline, porque el proyecto del juego no tiene ese script. Headless es lo que corre regression_cli.gd hoy; las regresiones que capturan o dibujan necesitan Xvfb, así que es una opción y no el default (tarda más y pide apt). Subir el informe y las capturas solo al fallar evita artifacts en cada push verde. No pisar un workflow existente: desde el botón, un aviso con la acción Overwrite (el mismo patrón que las demás confirmaciones del dock); desde la tool, un argumento explícito. actionlint no está instalado y bajar js-yaml con npx fue denegado por el clasificador: el test comprueba sangría par, sin tabs y el orden de las claves, y el yml generado se revisó a ojo (un escalar que empezaba con comillas y seguía se pasó a bloque |).
  Descartado: Un archivo .yml de plantilla en el addon con placeholders (otro archivo que viaja con el addon y que el export plugin tendría que excluir); usar una action de terceros para instalar Godot (dependencia externa, versión a seguir); subir artifacts siempre; Xvfb siempre; un diálogo modal de confirmación en vez del aviso del chat; correr el workflow en un repo de prueba real (8c: no crear repos ni correr workflows reales).

**Prueba:** tests/unit/test_regressions_workflow.gd (6 tests, 4.7.2): editor_version() y download_url() (estables de godotengine/godot, betas de godot-builds); texto headless y con render (Xvfb, opengl3); write() sin pisar / con overwrite; proyecto en una subcarpeta de un repo git real (git init en una carpeta temporal): repo_info() da la raíz, «game» y la carpeta ignorada; el yml va a <repo>/.github/workflows y no al proyecto, Godot corre con --path "game", las capturas van como game/.godot_agent/playtests/**, y avisa que .godot_agent está ignorado; en la raíz, --path . y sin avisos; sin git, repo_info() vacío y los tres avisos tienen texto; la tool está registrada (edit_files, overwrite y render); forma del YAML (sangría par, sin tabs, orden de claves). run_all 479 tests/3682 checks 0 fallos. Sin actionlint local y con la descarga de js-yaml denegada por el clasificador: el yml generado se revisó a ojo (copia en /tmp/claude-1000/-home-dannode-Proyectos-Godot-agent-harness--claude-worktrees-m13-17/3619cf30-0f89-4d71-9f7c-62dac5e13c95/scratchpad/godot-agent-regressions.yml, versión raíz). No se corrió ningún workflow real en GitHub (pedido de 8c).

**Notas:** Rama sm/m16-10 (base main 9501d7f), commits cac159a + 4da067e (revisión de 8c). regressions_workflow.gd: repo_info(project_root) con git -C (rev-parse --show-toplevel, --show-prefix, check-ignore -q sobre .godot_agent/ y addons/godot_agent/ con barra final para que cuente como carpeta aunque no exista); write() escribe en <raíz del repo>/.github/workflows/godot-agent-regressions.yml (sin git: en el proyecto, con WARN_NO_GIT) y devuelve {ok, path, existed, error, root, project_dir, warnings}; workflow_text(version, render, project_dir) usa --path "<subcarpeta>" y capturas relativas a la raíz; target_path()/exists() miran la raíz. Avisos (WARN_NO_GIT, WARN_IGNORED_REGRESSIONS, WARN_IGNORED_ADDON): en inglés en la respuesta de la tool (WARNING_TEXTS) y como avisos WARNING del dock traducidos (plugin.REGRESSIONS_WORKFLOW_WARNINGS). Botón «CI workflow…» del panel de hallazgos → ACTION_REGRESSIONS_WORKFLOW → aviso con la ruta absoluta o «already exists… Overwrite?»; tool godot.write_regressions_workflow (edit_files, overwrite y render) con nombre visible en tool_group_view. Wiki Review.md/Revisar.md (raíz del repo y avisos), CHANGELOG Unreleased › Added, 10 msgids nuevos en es.po. El botón genera headless; render solo por la tool. Pendiente para la prueba a mano: correr el yml en un repo de prueba con regresiones grabadas.

### run-test inestable: «game_input text: escribe en el LineEdit» · Revisión

**Prioridad:** media · **Tamaño:** S · **Etiquetas:** `test`

agent-harness-57 lo vio fallar una vez en Xvfb (2026-11-10, sm/m11-42 sobre 4.7.2) con last_text vacío, y pasar en las dos repeticiones siguientes. No tiene relación con m11-42. Probable carrera: el texto se manda antes de que el LineEdit tenga foco o antes de un frame de proceso. Reproducir corriendo run-test 20 veces, encontrar la espera que falta (en el check o en game_input si es del addon) y arreglarla; si es del addon, un agente real también lo sufriría.

**Decisiones:**
- ! Los juegos que lanza run_scene (y profile_run y las regresiones, que pasan por él) ignoran los gamepads reales con SDL_GAMECONTROLLER_IGNORE_DEVICES_EXCEPT=0x0000/0x0000, que el juego hereda del editor. Hay una opción real_gamepads:true para jugar a la par. run_all y regression_cli se relanzan sin ellos si detectan uno. · sin revisar
  Por qué: Los tres flakes de m16-11 tenían la misma causa: el Pro Controller conectado del usuario tenía el stick izquierdo en ±1. SDL lo lee en todo proceso de Godot, también headless y sin foco, y deja ui_up/ui_left… apretados. Pasan dos cosas. Un LineEdit que toma el foco con una flecha apretada no entra a editar, y el texto se pierde. El movimiento del joystick mueve el foco de la UI, que es lo que pasaba con el CodeEdit del composer. Un agente real lo sufre: ve que su input falla al azar.
  Descartado: (a) Solo avisar en las respuestas del probe que hay un gamepad real mandando input: no lo arregla. (b) Un ajuste en Settings: más UI para un caso raro, y el parámetro de la tool alcanza. (c) input_devices/joypads/ignore_joypad_on_unfocused_application: no sirve, porque el juego lanzado sí tiene el foco. (d) Sacar los eventos de joypad del InputMap en el probe: cambia el juego y rompe los eventos de joy que manda el agente.

**Prueba:** Con un gamepad conectado (real o virtual por uinput):
- `godot --headless --script res://tests/run_all.gd` dice «relaunched without the real gamepads» y test_real_gamepads pasa.
- run-test (`tests/run_in_xvfb.sh godot --godot-agent-run-test`) da 0 fallas. El check de game_script ve, dentro del juego, la variable puesta y 0 joypads, y el entorno del editor vuelve a como estaba.
- `tests/regressions_cli_check.sh godot` pasa: el relanzamiento conserva el código de salida y la salida.
- Sin gamepad, run_all y run-test pasan igual.

**Notas:** Causa: el Pro Controller del usuario estaba conectado con el stick izquierdo en ±1. SDL lee los gamepads de todo el sistema en cada proceso de Godot, también en headless y sin foco, así que ui_up/ui_left… quedaban apretados. Eso explica los tres flakes:
- game_input: un LineEdit que toma el foco con una flecha apretada no entra a editar, y el texto se pierde.
- test_composer: el joystick mueve el foco fuera del CodeEdit y lo demás falla en cascada.
- game_script/ui_right: con el eje X en ±1, la acción sigue apretada después de soltar el hold.

Arreglo (commit 889266d en sm/m16-11, integrado en sm/next2):
- RealGamepads (playtest/real_gamepads.gd) pone SDL_GAMECONTROLLER_IGNORE_DEVICES_EXCEPT=0x0000/0x0000 justo antes de play_custom_scene y restaura el valor anterior. El juego lo hereda; el editor no cambia.
- Cubre run_scene, profile_run y las regresiones del editor, que pasan por run_scene.
- `real_gamepads: true` deja pasar los gamepads reales.
- run_all.gd y regression_cli.gd se relanzan sin ellos si detectan uno.

Prueba (2026-11-10): el Pro Controller ya no estaba, así que creé un gamepad virtual por uinput (045e:028e, stick centrado; programa C en el scratchpad de la sesión).
- Godot 4.7.2 headless: get_connected_joypads()=[0] sin la variable, [] con ella.
- Con el gamepad virtual conectado pasaron run_all (relanzado), run-test con 0 fallas y regressions_cli_check.sh.
- run_all completo: 563 tests, 0 fallos.
- run-test 10 veces seguidas después del arreglo: 10/10 con 0 fallas.

Lo que no se reprodujo:
- No hubo corridas de «antes»: sin el stick corrido no hay causa que reproducir.
- No incliné el stick virtual, porque uinput afecta a todo el sistema y movería el foco del editor abierto del usuario.
- Que el stick explique los flakes de test_composer y game_script sale del mecanismo, no de verlos fallar con él.

m13-30 es la misma falla, duplicada de esta.

**Relacionadas:** run-test: «game_input text: escribe en el LineEdit» falla a veces

### tests/suite.sh: una sola lista de checks para el CI, para antes de mergear y para un nightly completo · Revisión

**Prioridad:** alta · **Tamaño:** M · **Etiquetas:** `tests`

El review-test se rompió en sm/next2 (recursión de m12-49 y el aviso del veredicto de m12-42) y nadie lo vio hasta m15-24. El CI sí lo corre, pero solo con push a main, con PR o desde el release, y las ramas sm/* son locales. Cada sesión corría los checks que se acordaba. Además, el CI tenía los 5 checks de Xvfb en un solo step, así que el primero que fallaba escondía a los demás.
Qué se hace:
- tests/suite.sh con los perfiles ci y full. Corre cada check aunque falle otro e imprime una tabla PASS/FAIL con segundos. `run <check>` corre uno solo, `list` los nombra y `check-ci` comprueba que ci.yml tiene un step por cada check de ci.
- ci.yml: un step por check, todos con `tests/suite.sh run` y `if: !cancelled()`. Suma export_check, mcp-test y edit-test. Se quita el sed de scope_compass.
- edit_check deja de fallar cuando falta addons/scope_compass (en CI y en worktrees): compara project.godot sin los plugins de `enabled` que no existen, igual que hace el editor.
- nightly.yml (schedule y workflow_dispatch, 4.7.2 y 4.8-beta2) corre `tests/suite.sh full` y sube los logs si falla.
- Regla del tablero: `tests/suite.sh ci` antes de mergear a sm/next2 y `tests/suite.sh full` antes de un release (decisión en esta tarea).
Fuera a propósito: los checks que gastan tokens, los que usan red o el CLI real, y los que solo sacan capturas.
Pushear las ramas sm/* o abrir un PR draft para que el CI las vea lo decide el usuario (agent-harness-81 se lo pasa).

**Decisiones:**
- ! Regla del tablero: antes de mergear una rama a sm/next2 se corre `tests/suite.sh ci` (~9 min en 4.7.2); antes de un release, `tests/suite.sh full` en 4.7.2 y 4.8-beta2. Un FAIL se anota en la tarea con su log antes de mergear. · sin revisar
  Por qué: El CI no corre sobre las ramas sm/*, que son locales. Cada sesión elegía qué checks correr, y así review-test quedó roto en sm/next2 sin que nadie lo viera. Con una sola lista, que además el CI usa por nombre, lo de antes de mergear coincide con lo que después corre el CI.
  Descartado: (a) Que cada sesión elija los checks según lo que toca: es lo que falló. (b) Correr full antes de cada merge: ~20 min más por merge, y lo que suma son pantallas que cambian poco. (c) Pushear sm/* para que corra el CI: publica las ramas; lo decide el usuario. (d) Un hook de git pre-merge: las sesiones mergean con git directo, y un hook de 9 min sorprende y se saltea con --no-verify.

**Prueba:** - `tests/suite.sh full godot` en 4.7.2 corre los 35 checks (~19 min, más ~2 min por el check de ciclos nuevo), imprime la tabla y sale con 1 si algo falló.
- `tests/suite.sh ci godot` corre los 13 de ci (~10 min).
- `tests/suite.sh check-ci` dice «ci.yml corre los 13 checks de ci»; con un step renombrado en ci.yml, sale con 1 y lo nombra.
- `tests/suite.sh run edit godot` pasa en un worktree sin addons/scope_compass (antes: «project.godot queda como estaba»).
- `tests/suite.sh run plugin_cycle`: 10 de 10 en 4.7.2 y 10 de 10 en 4.8-beta2. godot_agent da 0 objetos por ciclo de mediana, igual que el plugin vacío. En las 20, el self-test con tests/fixtures/cycle_plugins/leaky da [1,1,…] y falla por la fuga, como debe. El ciclo dentro del editor con Xvfb (`suite.sh run cycle`) pasa en 68 s.
- CI de GitHub: verde en 5c04dba, que tiene el disparador sm/**. f6399d1 (el check de ciclos nuevo) en curso.

**Notas:** Rama sm/suite, pusheada. Va 5c04dba → f6399d1 sobre 18a571d, sin mergear; le falta el commit del release v0.1.20 (46dc03e), que solo toca CHANGELOG y plugin.cfg. Una versión rebaseada sobre 46dc03e quedó en la rama local sm/suite-rebased-backup, pero no se subió porque reemplazar el remoto necesitaba un force push y el permiso fue denegado.

Mediciones en 4.7.2 (Arch, Xvfb con llvmpipe), en segundos.
- ci: run_all 67–75, acp 19–26, oneshot_loop 45–52, regressions 24–32, export 29–36, plugin_cycle ~125 (antes 9–10), run 77–80, review 13, run-error 38–40, debug 22–23, external 27–28, edit 27, mcp 15–16.
- full suma: sync 20, oneshot 37, long 20, completion 16, login 13, queue 18, auto 14, remote 22, pending 11, profile 23–26, cycle (editor) ~68 (antes 15–17), i18n (es) 15, history 14, sessions 12, ui-basic 14, ui-crash 13, ui-markdown 14–20, ui-long-permission 14–16, ui-quota 19–21, ui-quota-busy 21–22, ui-harness-prompt 15–18, crash 71.

Check de ciclos (antes inestable, 1 de 8: «los objetos crecieron 59»).
- Causa: medía 5 frames después de cada enable, y cada ciclo duraba ~70 ms.
  - Al habilitarse, el addon crea objetos que viven hasta ~1,3 s; qué son queda en m16-13.
  - Además, cada print del check en medio de los ciclos deja una línea en el Output del editor, que es un objeto más.
  - No es una fuga del addon ni del editor. El «+3 por ciclo del editor» que parecía salió de esos dos efectos: con la medición asentada da 0.
- Ahora:
  - Espera 2,5 s y 30 frames sin cambios antes de medir.
  - Cicla intercalado un plugin vacío de control (tests/fixtures/cycle_plugins/empty).
  - Compara la mediana del crecimiento por ciclo en 9 rondas, y falla con 1 objeto por ciclo de más que el control.
  - Imprime las rondas al final.
  - Sigue mirando los huérfanos, los nodos del addon y el layout.
  - plugin_cycle_check.gd se prueba con tests/fixtures/cycle_plugins/leaky, que pierde un RefCounted por enable.
  - Con --godot-agent-cycle-target se cicla otro plugin, por nombre o por la ruta a su plugin.cfg.

Lo que falla hoy (anotado, sin arreglar):
- oneshot-test es inestable, 2 de 7: «el centro no baja a 340 px: queda en 478 (el formulario pide 454, dock 1213)».
- edit-test fallaba siempre sin scope_compass. Lo arregla esta rama.

Notas:
- En ci.yml se sacó el sed de scope_compass del paso del ciclo.
- El CI corre en push a main y a sm/**. La concurrency va por workflow y ref, y cancela solo fuera de main.
- El job nightly corre solo sobre main.

### Qué crea el addon al habilitarse que vive ~1,3 s (objetos transitorios del check de ciclos) · Revisión

**Prioridad:** baja · **Tamaño:** S · **Etiquetas:** `tests`

Encontrado en m16-12. No es una fuga: el check de ciclos nuevo los espera y el addon queda en 0 objetos por ciclo. Conviene saber qué son.
- Cada vez que se habilita godot_agent aparecen ráfagas de +13 a +35 objetos hacia los 0,35–0,6 s, que viven menos de 10 frames.
- Unos 15 objetos viven hasta ~1–1,3 s y después se liberan.
- No son nodos, ni recursos (Performance OBJECT_NODE_COUNT y OBJECT_RESOURCE_COUNT quietos), ni Tweens (get_processed_tweens vacío). Son RefCounted u Objects de algo asíncrono.
- Un plugin vacío no lo hace: el conteo queda plano.
- Descartado: el índice del completado (ProjectContext). Con REFRESH_DELAY_MS en 600000 las ráfagas siguen.
- Candidatos para bisecar apagándolos uno por uno: el chequeo de versión al arrancar (_check_updates diferido), el servidor MCP (_start_mcp_server), _restore_oneshot y _report_supervisor_events diferidos, y los timers de 1 s del dock (máquinas, cuota).
- Cómo medir: la instrumentación de m16-12 (muestras cada 10 frames con ms después del enable) está en /tmp/claude-1000/-home-dannode-Proyectos-Godot-agent-harness/6a75c1f6-1e4e-480a-bf5d-1af264408d32/scratchpad/cycle/diag-final.patch (temporal), o con el check de ciclos y --godot-agent-cycle-target.
- Si es trabajo que corre aunque el plugin ya se deshabilitó (un timer o un pedido que sobrevive a _exit_tree), revisar que no toque objetos liberados.

**Prueba:** - Probe temporal (un plugin que deshabilita y habilita godot_agent y muestrea objetos y nodos cada frame durante 2,5 s), en 4.7.2 headless:
  - Antes: churn de −11 a +42 objetos entre 0,5 y 1,4 s, y ~15 objetos liberados de una vez hacia 1,6–2 s (último cambio a 1,5–2,1 s).
  - Después: pico +0 y último cambio a ~0,5 s, que es cuando termina el enable.
- Bisección: apagando la entrada al árbol de CompletionService desaparece todo. El servidor MCP y el chequeo de versión no cambian nada.
- completion-test: abre el script y el índice está listo en 0,2 s. Comprueba que sin scripts abiertos ni el arranque ni un scan de archivos construyen el índice. Sin el arreglo falla con las dos FALLA.
- run_all: 637 tests, 0 fallos. plugin_cycle: PASS (0 objetos por ciclo), y el self-test con el plugin con fuga falla como debe.

**Notas:** Rama sm/m16-13 (desde origin/sm/next3 e558600), pusheada, sin mergear.

Causa: CompletionService._ready → apply_settings() arrancaba el primer build del índice (ProjectContext.start_build en un worker) apenas se habilitaba el plugin, aunque no hubiera scripts abiertos.
- El churn eran los objetos temporales del worker.
- La caída de ~15 objetos era la publicación del índice.
- Postergar REFRESH_DELAY_MS (lo que se había probado en m16-12) no cambiaba nada, porque el primer build no pasa por ese retardo.

Arreglo:
- needs_index() = completado prendido y al menos un CodeEdit con controller. El primer build arranca en apply_settings cuando se engancha el primer script.
- _process solo llama a context.poll() si needs_index() o si hay un build en curso. Sin scripts, los cambios de archivos solo marcan el índice como viejo; el próximo build los cubre (start_build limpia _dirty).
- Si al abrir el editor ya hay un script abierto, el build arranca enseguida, igual que antes.
- CHANGELOG: entrada en Unreleased › Changed.

No cambiado: habilitar el addon bloquea ~480 ms en el hilo principal (el probe recién ve el primer frame a esa altura). Es otro tema; si interesa, conviene abrirle una tarea.

### run_all sin fugas al salir, y un check que falle si aparecen · Revisión

**Prioridad:** media · **Etiquetas:** `tests`

run_all en main (46dc03e) termina con 2 RIDs de CanvasItem leaked, 46 ObjectDB instances leaked y «11 resources still in use». No hace fallar nada, así que una fuga nueva (por ejemplo, un ciclo de referencias en el controller) pasa desapercibida.

Qué hacer:
- Encontrar con --verbose, bisecando por archivo de test, qué las deja.
- Arreglar las del addon en el código y las del test en el test. Anotar las del motor.
- Que run_all falle si quedan fugas, y sumarlo a suite.sh cuando sm/suite esté en main.

Pedido de agent-harness-81, 2026-11-11.

**Prueba:** - suite.sh ci 14/14, con el gate de fugas en run_all.
- run_all: 639 tests, sin avisos de fugas al salir.
- test_model_lifetime.gd: falla con el session_model anterior.
- El gate se probó con un test que deja un Node (exit 1) y con un archivo que no compila (FAIL «no se pudo cargar»).
- ui_long_permission, remote y queue: PASS.

**Notas:** Rama sm/run-all-leaks (a40da1a), desde origin/sm/next3.

Bisectado por archivo y por test. En main quedaba esto: 2 RIDs de CanvasItem, 46 ObjectDB y 11 resources still in use.

Del addon:
- SessionModel.add_permission y add_elicitation: una lambda capturaba el pedido, la entrada y el modelo. Mientras el pedido estaba pendiente era un ciclo, y aparecía en test_elicitation, test_permission_view y test_subagents.
- En producción, stop() cancela los pendientes, así que el impacto era menor: lo que no pasa por stop() queda.

De los tests:
- test_acp_client y test_sessions: un handler que capturaba a su dueño.
- test_resource_values: dos Sprite2D sin liberar; eran los 2 RIDs.

Del motor: ninguna.

De paso:
- run_all salteaba en silencio un archivo de test que no compila.
- suite.sh: without_leaks() en el check run_all.

### Habilitar el addon bloquea el editor ~480 ms: llevarlo a menos de 150 ms · Revisión

**Prioridad:** media · **Tamaño:** M · **Etiquetas:** `performance`

Visto en m16-13: set_plugin_enabled("godot_agent", true) tarda ~480 ms en el hilo principal (headless 4.7.2, scripts ya cargados). Eso pasa al abrir el editor y cada vez que se habilita el plugin.
- Medir qué se lleva el tiempo con Time.get_ticks_usec alrededor de cada pieza de _enter_tree.
- Postergar lo que no hace falta para que el dock aparezca (diálogos, ventanas, servicios que se usan después), sin cambiar lo que ve el usuario.
- Meta: menos de 150 ms. Entregar la tabla antes y después.

**Decisiones:**
- ! plugin.gd queda como cáscara EditorPlugin sin tipos; el plugin entero pasa a agent_plugin.gd (Node hijo, cargado con load()) · sin revisar
  Por qué: Al habilitar, el editor compila plugin.gd sin caché y cuesta ~1,8 ms por script que nombra (~170 ms de ~430). Heredar de otro script o alias vía un script de dependencias cuesta lo mismo (medido: 116–161 ms); solo un load() en runtime es gratis (0,4 ms). Los checks de dev buscan ahora agent_plugin.gd; scene_saved y PlaytestAutoload van por el EditorPlugin (_plugin).
  Descartado: plugin.gd delgado con extends "agent_plugin.gd" (161 ms); consts preload movidas a un script deps con alias (116 ms); set_script en _init (frágil); dejar la recompilación y solo postergar UI (no llega a 150 ms)
- ! Ajustes y Extensiones se arman la primera vez que se abren (no en un frame posterior) · sin revisar
  Por qué: Costaban ~135 y ~20 ms del enable y no se ven hasta abrirlos; armarlos en idle solo mueve el tirón a otro frame. La primera apertura tarda ~0,15 s más.
  Descartado: crearlos con call_deferred después del enable; postergar también el server MCP (~10 ms) o la main screen (~13 ms): no hacía falta para la meta

**Prueba:** tests/unit/test_plugin_entry.gd: plugin.gd no nombra scripts, se recompila sin caché en <25 ms (medido 0,4 ms; antes ~170) y agent_plugin.gd tiene build/make_visible/has_main_screen/plugin_name/plugin_icon y _init(plugin). Medición: probe temporal que deshabilita/habilita 3 veces con set_plugin_enabled (4.7.2 headless): 407–456 ms → 71–77 ms. suite ci verde en 4.7.2; pending, profile, sessions, i18n, auto, remote, ui-basic, cycle y crash verdes; plugin_cycle, edit y run_all verdes en 4.8-beta2.

**Notas:** Commit 8e4a18f en sm/enable-time.
Antes (por enable): recompilar plugin.gd ~176–193 ms (el editor lo carga con CACHE_MODE_IGNORE; ~1,8 ms por script nombrado; heredar de otro script o aliasar consts cuesta lo mismo) + _enter_tree ~229–260 (SettingsDialog ~145–154, dock _ready ~45–54, ExtensionsWindow ~23, main screen ~13–17, server MCP ~10–14, resto <3) + ~2,4 después.
Después: recompilar ~1,5 + _enter_tree ~68–74 (dock ~41–44, main screen ~13, MCP ~10) + ~2,4. Primera apertura de Ajustes 134 ms, de Extensiones 20 ms.
Preexistentes, no de este cambio (iguales en fc2514f): oneshot-check falla «el centro no baja a 340 px: queda en 1471»; al deshabilitar sale «A Thread object is being destroyed without its completion» (probable TurnSnapshots._run_with_index de setup()).

### oneshot-check: «el centro no baja a 340 px: queda en 1471 (el formulario pide 912, dock 220)» · Revisión

**Tamaño:** S · **Etiquetas:** `tests`

Visto en m16-15: oneshot-check falla igual en fc2514f (sin el cambio de enable). Es un número distinto del flake que arregló agent-harness-41 en sm/oneshot-flake (c189254: mínimo fijo del área + scroll horizontal AUTO); puede ser una regresión de ese arreglo con el dock angosto. Encontrar la causa, arreglarla con test y avisarle a agent-harness-41.

**Prueba:** oneshot-test pasa 3 de 3 en 4.7.2 y en 4.8-beta2. Forzando la pestaña Animation con un AnimationPlayer editado, sin hide falla («queda en 464… el centro 463») y con hide pasa (mínimo de la columna 234).

**Notas:** 54b7ed4 en sm/enable-time. Causa: EditorBottomPanel comparte la columna del centro. Con Animation abierta y un AnimationPlayer editado pide ~457–472 px (escala 0,75) y frena el centro en ~464–497. No es c189254: el área del One-shot pide 234. Fix: hide_bottom_panel() antes de angostar, y el mensaje de falla dice el mínimo de la columna del centro. La variante «1471, dock 220» no se reprodujo; un layout con dock_hsplit_3=-6328 pasa porque el editor clampa al cargar, así que no agregué clamp_split_offset. Avisado a agent-harness-41.

### Deshabilitar el addon destruye un Thread sin completarse (TurnSnapshots) · Revisión

**Tamaño:** S · **Etiquetas:** `tests`

Visto en m16-15: en cada disable sale «A Thread object is being destroyed without its completion having been realized» (también en fc2514f). Probable: el git de TurnSnapshots.setup() corre en un Thread que se suelta con el plugin. _exit_tree tiene que esperarlo (wait_to_finish) o cancelarlo, con test.

**Prueba:** test_git_checkpoints.test_run_outlives_its_owner: un run cuyo GitCheckpoints se libera termina igual y GitCheckpoints.pending() vuelve a 0. Con la espera de instancia falla y sale el warning. Probe en el editor deshabilitando un frame después de habilitar: antes salía el warning, ahora no.

**Notas:** 78da267 en sm/enable-time. Causa: deshabilitar mientras TurnSnapshots.setup() todavía corría un git. Al liberar el objeto, Godot descarta su coroutine con el Thread adentro y nadie llama wait_to_finish. Solo pasa si se deshabilita al poco de habilitar (el probe de m16-15 lo hacía a 1 frame). Fix: la espera es una función estática (GitCheckpoints.execute) que no depende de ninguna instancia; la usan GitCheckpoints.run, TurnSnapshots._run_with_index y GithubReviews._run. Elegí esto en lugar de esperar en _exit_tree, que bloquearía el disable y solo cubría TurnSnapshots. CHANGELOG Unreleased › Fixed.

## M15 — Revisión de features: lo que no estaba correcto  (27/27, 27 en revisión)

Lo que encontró la revisión de features del 31/10 con las pruebas y Claude Code real: una caída del editor sin resolver, textos que dicen algo falso o viejo, y lo que quedó sin verificar.

**Hecho cuando:**
- external-test corre en CI y el editor no se cae al guardar una escena recargada.
- README, wiki y privacidad dicen lo que el addon hace hoy, y lo no probado figura como sin verificar.
- Un One-shot real llegó al evaluador con un presupuesto suficiente.

### 15.1 El editor se cae al guardar una escena recargada · Revisión

**Prioridad:** alta · **Tamaño:** M · **Etiquetas:** `bug`

En external-test, en el segundo y medio después de EditorInterface.save_scene() sobre una escena recién recargada: SIGSEGV en el motor, sin rastro de GDScript. Pasa en alrededor de 1 de cada 3 corridas en 4.7.2, también en v0.1.13 y en un commit anterior. Sigue pasando con el sondeo de EditorSync apagado en ese tramo, pero no se descartó ni al addon ni a Godot. Impacto probable: aceptar la recarga de una escena que cambió el agente y después Ctrl+S. Reproducir en un proyecto sin el addon para separar causas.

**Decisiones:**
- ✓ El external-test guarda con save_scene_as(path, false) en lugar de save_scene(); el bug de Godot queda en un borrador de issue sin publicar
  Por qué: La caída es del motor (camino de guardado con vista previa) y el addon no la puede evitar en Ctrl+S. Lo que prueba E (que un guardado del editor no cuente como cambio del agente) no depende de la vista previa. Publicar el issue es hacia afuera: lo decide el usuario.
  Descartado: Dejar save_scene() y no sumar el check a CI (fallaría 3 de 4 veces en 4.7.2); sacar 4.7.2 de la matriz; buscar en el addon un workaround para Ctrl+S (no se encontró ninguno: el error sale aun sin el addon).
  Qué hacer: Usuario (31/10): documentarlo, sin abrir issue en Godot. Queda en D60.

**Prueba:** external-test en Xvfb con el plugin de dev del repo: 16/16 en 4.7.2 y 8/8 en 4.8-beta2, en copias aisladas. Antes del cambio: 9 caídas en 12 en 4.7.2. Repro mínimo: tests/upstream/save_preview_list_erase con -- --repro, 3 errores con vista previa y 0 sin ella.

**Notas:** Corrección (revisión de M15, m17-11): lo comprobado sin el addon es el error, no la caída. Sin el addon: 96 guardados con vista previa, el error en cada uno y ninguna caída. Que la caída venga del mismo bug del motor es probable, sin confirmar. La tool save_scene y el guardado antes de actualizar ya no usan la vista previa (m17-11); Ctrl+S del usuario sigue sin poder evitarse.

Todo guardado por _save_scene_with_preview (Ctrl+S, EditorInterface.save_scene()) deja «p_I->data != this» en list.h:228. Pasa en un proyecto sin el addon, con una escena Node2D vacía y sin cambios en disco (tests/upstream/save_preview_list_erase). save_scene_as(path, false), que no hace vista previa ni EditorProgress, no lo deja. Con el external-test entero, 9 caídas en 12 corridas guardando con vista previa y 0 en 16 sin vista previa. Hacen falta las fases A (project.godot escrito desde afuera), B (recarga) y algo de tiempo antes del guardado: sin cualquiera de las tres, 0 en 12. 4.8-beta2 deja el error (p_element->data != this) y no se cayó en 12 corridas. Hipótesis sin confirmar (falta un build con símbolos; compilarlo lo bloqueó el clasificador de permisos): ProgressDialog::_reparent_and_show reparenta un Control raíz y su RI se borra de la lista gui.roots de otro viewport. El external-test guarda sin vista previa: lo que comprueba E es scene_saved, que ese camino también emite. Borrador del issue en tests/upstream/issue_save_preview_list_erase.md, sin publicar (decisión del usuario).

**Bloquea a:** 15.2 external-test en CI

### 15.2 external-test en CI · Revisión

**Prioridad:** alta · **Tamaño:** S · **Etiquetas:** `ci`

Ese check no corre en CI y por eso la caída no se veía. Sumarlo al paso de checks del editor, una vez resuelta la caída.

**Prueba:** En CI, run 41214552472 (push de 3d2dab1): external-test: 0 fallas en Godot 4.7.2 y en 4.8-beta2. En local, el mismo comando pasa 16/16 en 4.7.2 y 8/8 en 4.8-beta2.

**Notas:** Sumado al paso «Editor checks (run, review, external)» de ci.yml con XRUN_TIMEOUT=120. Corre después del paso que saca scope_compass de project.godot, igual que en las copias aisladas donde se probó.

**Bloqueada por:** 15.1 El editor se cae al guardar una escena recargada

### 15.3 Textos falsos o viejos en README, privacidad y progreso · Revisión

**Prioridad:** media · **Tamaño:** S · **Etiquetas:** `docs`

README.md y PRIVACY.md dicen que nunca hace push, pero existe la opción de Pushear y abrir un PR (apagada por defecto, la inicia el usuario): aclararlo, también en español. El README dice «M0–M8c» y su descripción de CI no incluye run-test, review-test ni regresiones. docs/progress.md no cambia desde el 22/10 y menciona 4.4.1 como mínimo.

**Prueba:** Revisión de texto contra el código: ci.yml, plugin.gd:1171, project_config.gd:54, settings_dialog.gd:501 y es.po:3090-3097. No hay tests que lean estos archivos.

**Notas:** Push: README, PRIVACY y la wiki (Home/Inicio) ahora dicen que el harness nunca pushea por su cuenta. La única excepción es «Push and open a PR», apagado por defecto (ProjectConfig.github_pull_requests), que el usuario elige al cerrar una copia aparte (plugin.gd _ask_copy_fate, core/github_reviews.gd). El estado del README pasó de «M0–M8c» a M0–M14 implementados (M12–M14 en revisión), con M15 y M16 abiertos. El CI del README suma regresiones por línea de comandos y run-test, review-test y external-test en Xvfb, según ci.yml. En progress.md el mínimo es 4.7, no 4.6: lo subió 9a5e25b (m13-09, D59). Los binarios del encabezado están al día, las menciones a 4.4.1 quedan como historia y hay una sección nueva con un resumen por hito del 22/10 al 31/10. Sumé un problema conocido de 4.7.2 (m17-01) en el README y en Problemas frecuentes.

### 15.4 Huecos en la wiki de tools y One-shot · Revisión

**Prioridad:** media · **Tamaño:** S · **Etiquetas:** `docs`

Editor-tools: run_scene no menciona continue_on_error ni film_fps, y faltan sessions y session_send. One-shot: no dice que un informe del evaluador sin haber jugado no cuenta. En inglés y español.

**Prueba:** Revisión de texto contra run_tools.gd:236-237 y 120-145, session_tools.gd, review_store.gd:47 y oneshot_run.gd:1208-1246.

**Notas:** En Editor-tools y Herramientas-del-editor, la fila de run_scene suma continue_on_error y film_fps. continue_on_error frena igual en un breakpoint y deja de saltear errores después de 30 por run (CONTINUE_MAX). Lo usan los playtests y el evaluador; Construir no. film_fps no fija el framerate como record. Hay una fila nueva «Sessions/Sesiones» con sessions y session_send: mensaje de hasta 4000 caracteres que llega al terminar el turno. En One-shot se agregó que un informe del evaluador sin haber jugado no cuenta: alcanza con cualquier tool de ReviewStore.PLAY_TOOLS en su turno, también de subagentes. Si no hubo ninguna, la vuelta no es concluyente, las verificaciones no se aplican y el run termina con «couldn't reach a verdict» (oneshot_run.gd:1208-1246).

### 15.5 Marcar lo no probado como sin verificar · Revisión

**Prioridad:** media · **Tamaño:** S · **Etiquetas:** `docs`

En README y wiki: Codex y macOS figuran como soportados sin ninguna prueba real; Ollama y llama.cpp nunca se probaron contra un modelo real. Decirlo. Windows y Antigravity se prueban en M16: actualizar lo que digan los textos según ese resultado.

**Prueba:** Revisión de texto: README.md/README.es.md, docs/wiki/{en,es}/Home|Inicio, Settings e Inline-completion|Completado-inline.

**Notas:** Marcado como sin verificar en el README (intro y requisitos) y en la wiki (Home/Inicio y Settings): Codex, Google Antigravity, macOS y Windows. Windows y Antigravity llevan la nota «se prueban en M16». En Completado: Ollama y llama.cpp, sin verificar contra un modelo real. Cuando se haga M16, actualizar estos textos con el resultado. No marqué Codestral, OpenAI-compatible ni Gemini: no sé si se probaron.

### 15.6 One-shot real que llegue al evaluador · Revisión

**Prioridad:** alta · **Tamaño:** M · **Etiquetas:** `playtest`, `one-shot`

En la revisión, el One-shot real terminó por el presupuesto de 5 playtests del test, así que el evaluador no corrió y «sin jugar no cuenta» solo está probado con agente falso. Correrlo con más presupuesto. Gastó 245k tokens contra 114k de la versión anterior, sin comparación controlada: medir si el consumo subió por los prompts y tools de M13.

**Prueba:** XRUN_PROJECT=<sandbox de make_sandbox.sh --dev> XRUN_TIMEOUT=3800 tests/run_in_xvfb.sh godot --godot-agent-claude-oneshot-test: PASS, 0 fallas.

**Notas:** One-shot real (Claude Code, Pong, Godot 4.7.2, Xvfb), con presupuesto de 40 min, 3M tokens y 20 playtests: llegó al evaluador dos veces. Cuatro turnos: construir (76 tools), QA 1 (36 tools, no pasa: «Paletas inactivas fuera de juego», paddle.gd:16), arreglo (42 tools) y QA 2 (35 tools, pasa con ponderado 8.7). Total: 12,1 min, 8 playtests, 299.705 tokens, 7 checkpoints. El evaluador jugó: en QA 1 hizo 11 godot.run y 3 capture_game_frame, y no salió el aviso de veredicto sin jugar. «Sin jugar no cuenta» con un agente real que no juega sigue probado solo con el agente falso (oneshot_check «evaluador sin jugar»): forzarlo con uno real no tiene sentido. Consumo: no hay comparación controlada, porque haría falta correr la versión anterior a M13 más de una vez y eso gasta cuota. Lo que se midió sin correr nada, de 1f936eb^ a HEAD: descripciones y esquemas de tools de 18,4k a 22,0k caracteres (de 64 a 72 tools) y system_prompt.md de 6,9k a 7,4k, unos +1k tokens por turno antes de la caché. Los 245k de la revisión no llegaron al QA; estos 300k incluyen dos rondas de QA. Los informes qa-*.md se perdieron con el «Volver acá» final del test (.godot_agent no se versiona, cp7 se descartó); quedan los hallazgos en el log. Cambios al test: CLAUDE_BUDGETS a 40 min y 20 playtests, timeout de 3600 s, check «el evaluador no corrió» e impresión de cada ronda de QA.

### 15.7 Detalles menores de la revisión · Revisión

**Prioridad:** baja · **Tamaño:** S · **Etiquetas:** `ui`, `tests`

validate_physics y validate_tilemap sin nombre legible en el chat. get_errors muestra el error de ruido de Godot 4.7 (@implicit_new), que el One-shot real citó como errores del harness: run_tools ya lo filtra, get_errors no. i18n-test falla porque no encuentra «Iniciar sesión»: probablemente quedó viejo tras el rediseño del dock, sin confirmar en la interfaz.

**Prueba:** run_all 398/0 en 4.7.2, con test_tool_group_view.test_every_godot_tool_has_a_name y test_diagnostic_tools.test_get_errors_hides_engine_noise. i18n-test en Xvfb sobre el repo: 411 textos, PASS.

**Notas:** validate_physics y validate_tilemap ya tienen nombre: «Validate physics/tilemap», en español «Validar física/tilemap». Eran las únicas dos de las 72 tools sin nombre. Un test nuevo lo comprueba leyendo los McpTool.create. El filtro del ruido de 4.7 (@implicit_new) pasó de run_tools a ErrorCollector.is_engine_noise y ahora lo usan get_errors y run_tools. El conteo de get_errors tampoco lo cuenta. Lo de i18n-test era el test, no la UI: el botón dice «Nueva sesión» cuando hay sesiones recientes en el historial. En una copia sin historial el test pasaba y en el repo fallaba. Ahora acepta las dos.

### 15.8 Filmación con GPU real · Revisión

**Prioridad:** media · **Tamaño:** S · **Etiquetas:** `playtest`

El camino asíncrono de Forward+ y Mobile en playtest/runtime/film.gd nunca se ejecutó: bajo Xvfb solo corre el respaldo con get_image. Correr run_scene con film_fps en una máquina con GPU y mirar los frames.

**Prueba:** Lo de arriba, en una copia aislada del proyecto con el addon actual. Sin GPU en CI, así que no entra.

**Notas:** Probado en esta máquina (AMD RX 580, RADV), sin abrir ventanas en el escritorio: gamescope --backend headless corre el editor y el juego en Vulkan sobre la GPU. Xvfb no sirve para Vulkan: «None of the devices supports both graphics and present queues». Hice dos pruebas. (1) Un proyecto aparte usa film.gd tal cual a 10 fps durante 3 s: 28 frames en Forward+ y 28 en Mobile, todos por texture_get_data_async y ninguno por fall_back. Los colores están bien: el fondo 0.3 sale #4D4D4D (sin doble gamma) y la caja se mueve entre frames. (2) run-test entero en gamescope con GODOT_AGENT_TEST_RUN_ARGS="--rendering-driver vulkan --display-driver x11 --audio-driver Dummy": PASS. El juego corrió en Vulkan Forward+ y quedaron 68 JPEG de 640×360 en .godot_agent/playtests/film_*, que se ven bien. En (2) no instrumenté qué camino tomó cada frame; que haya sido el asíncrono sale de (1). Comando: gamescope --backend headless -W 1920 -H 1200 -- godot --display-driver x11 --rendering-driver vulkan --path <copia> -e -- --godot-agent-run-test.

### 15.9 Checks que no corrieron en la revisión · Revisión

**Prioridad:** baja · **Tamaño:** S · **Etiquetas:** `tests`

Los de assets, skills, sesiones e historial piden argumentos y quedaron afuera de la revisión del 31/10. Correrlos y anotar el resultado.

**Prueba:** Los cuatro corridos de a uno en Xvfb 4.7.2: asset-test ok, historial ok, sessions-test ok, skills-test ok.

**Notas:** Resultados en 4.7.2. asset (tests/asset_check.sh, con red): PASS. history (run_in_xvfb --godot-agent-history-test=<png>): PASS. sessions (--godot-agent-sessions-test=<prefijo>): PASS sobre el repo. En una copia sin git falla con «no se abrió la sesión en una copia», porque la copia de la sesión es un git worktree, así que hay que correrlo sobre un repo. skills (tests/skills_check.sh): fallaba con «_meta de la sesión: {}» y el test estaba viejo: desde m13-04 el _meta lo arma controller.adapter y el test solo ponía _profile. Ahora pone también el adaptador de Claude Code y lo restaura después: PASS. Ojo: corridos en paralelo, xvfb-run a veces devuelve exit 1 aunque el test imprima PASS (kill de un Xvfb que ya terminó); hay que correrlos de a uno.

### game_input por frame no era exacto con el juego lento · Revisión

**Prioridad:** baja · **Tamaño:** S · **Etiquetas:** `playtest`

En el CI del push de M15 (run 41214552472, 4.8-beta2) falló una vez el check «game_input por frame: 9 frames y fuerza 0.4 en el juego» (run_check.gd:191): el input se jugó (el check anterior pasó), pero en 0,3 s no apareció «ui_accept sostenido 9 frames» en el Output. Al relanzar el job pasó. Parece timing del runner: esperar la línea con un plazo en lugar de un timer fijo de 0,3 s.

**Prueba:** run-test con un check nuevo a 8 fps: sin el arreglo, 11 frames duran 15; con el arreglo, 11 exactos en 3 de 3 corridas.

**Notas:** El diagnóstico anterior estaba mal: no era el retraso del Output. El release de a66d86d falló con «sostenido 10 frames» en vez de 9, con la espera de 5 s puesta. Input guarda el evento hasta el próximo frame de proceso, y con pocos fps entran varios frames de física antes. Arreglo: Input.flush_buffered_events() después de cada evento en modo frame (Autopilot hace lo mismo).

### Los guardados del addon sin vista previa, y textos de la caída de 4.7.2 sin exagerar · Revisión

**Prioridad:** alta · **Tamaño:** S · **Etiquetas:** `bug`

Revisión de M15: la tool save_scene seguía guardando con EditorInterface.save_scene() (con vista previa, el camino que deja «p_I->data != this» en 4.7.2), y lo mismo el save_all_scenes antes de actualizar el addon. Los textos (README, CHANGELOG, wiki, D60, borrador del issue) decían que la caída pasa también sin el addon, cuando sin el addon solo se vio el error; y mencionaban M15/M16, que solo existen en el tablero.

**Prueba:** Unitarias 399/0: test_addon_scripts.test_no_save_with_preview falla con la tool vuelta a save_scene() o a save_scene_as(path) (probado). edit-test en Xvfb (4.7.2): PASS; con la tool y _save_all_scenes saboteados, 2 fallas (probado). Los checks nuevos: save_scene emite scene_saved, deja la escena guardada, EditorSync no avisa ni recarga, y ni la tool ni _save_all_scenes escriben la miniatura resthumb-<md5>.png (el control con save_scene() sí la escribe). Además: acp 162/0, oneshot_check 134/0, plugin_cycle PASS, regressions_cli bien, run/review/external-test PASS.

**Notas:** - Tool save_scene: save_scene_as(path, false). Si la carpeta no existe da error; si después de guardar la escena sigue en get_unsaved_scenes(), también. La escena que nunca se guardó sigue con el mismo error de antes.
- plugin._save_all_scenes(), antes de instalar una actualización: save_all_scenes() solo usa la vista previa para la escena activa con cambios (EditorNode::_save_all_scenes en 4.7.2). Por eso primero guarda esa sin vista previa y después llama a save_all_scenes(), que guarda las demás sin vista previa y le pide ruta a las que nunca se guardaron.
- Hallazgo: el error «p_I->data != this» no sale en todos los guardados con vista previa. En el edit-test, un save_scene() no lo dejó, ni en el Output ni en stderr. Los textos ya no dicen «en cada guardado»: dicen que sin el addon salió en cada guardado del proyecto vacío. Por eso el check usa la miniatura y no el error.
- Textos: README, CHANGELOG, la wiki (Troubleshooting, Problemas frecuentes, Home, Inicio), D60, progress y el borrador del issue. Ahora dicen que la caída solo se vio con un agente cambiando el proyecto y que su origen en el motor es probable, sin confirmar. Sobre 4.8-beta2: el error sigue, sin caída en 12 corridas. M15 y M16 salieron de los textos públicos.

### Una cuenta por pestaña del dock, para cualquier agente · Revisión

**Prioridad:** media · **Tamaño:** S · **Responsable:** Claude

Pedido del usuario (01/11): dos pestañas/sesiones, una con una cuenta de Claude Code y otra con otra, sin pasar por Ajustes del plugin. De paso: agents/profiles en EditorSettings era texto JSON (molesto de editar) y el formulario de Ajustes › Agentes aplastaba los campos en un diálogo angosto.

**Decisiones:**
- ! Las pestañas nuevas arrancan con el último agente elegido en cualquier pestaña, no con el de la pestaña desde la que se abrieron · sin revisar
  Por qué: Reusa agents/last_profile, que ya es el del próximo arranque del editor; un solo concepto de «el último».
  Descartado: Heredar el de la pestaña que abre la nueva; preguntar el agente al abrir la pestaña.
- ! Las cuentas se descubren solas en ~/.claude, ~/.claude-profiles/* y CLAUDE_CONFIG_DIR del editor; otras se agregan con «Otra carpeta…» · sin revisar
  Por qué: Es donde ya las tiene el usuario; no hay que configurar nada para elegir entre las existentes.
  Descartado: Lista manual en Ajustes; crear la carpeta con un nombre desde el dock.
- ! También mcp/servers y completion/llm/profiles pasan de texto JSON a Array de Dictionary, no solo agents/profiles · sin revisar
  Por qué: Mismo problema (texto plano molesto en Editor Settings) y mismo código; dejarlos distintos sería inconsistente.
  Descartado: Convertir solo agents/profiles.
- ! Cuentas genéricas: cada adaptador dice la variable de su carpeta de configuración; para agentes desconocidos, un campo opcional del perfil. Búsqueda en ~/.<carpeta>-profiles/* para todos · sin revisar
  Por qué: El usuario pidió que no sea solo para Claude Code; la carpeta de configuración es el mecanismo común (Claude, Antigravity, Codex). La regla -profiles generaliza la convención que ya usa.
  Descartado: Pisar HOME para cualquier agente (rompe npx, cachés y PATH); conjuntos de variables arbitrarios por cuenta (más UI).

**Prueba:** En el dock, chip del agente ▾ con Claude Code: «Cuenta de Claude Code» lista personal, ~/.claude, openrouter, trabajo con email. Con Google Antigravity: «Cuenta de Google Antigravity» lista ~/.gemini (y ~/.gemini-profiles/*). Pestaña 1 en Claude personal; + › Nueva pestaña, elegir trabajo (o Antigravity con otra carpeta): las dos sesiones conectan con su cuenta y la pestaña 1 no cambia. Un agente cualquiera con «Variable de la carpeta de cuentas» en su perfil también muestra la sección. Automático: run_all 405/405 (test_agent_accounts), sessions-test en Xvfb con Claude y Antigravity (capturas de los dos menús), settings-shots.

**Notas:** - session/agents/agent_accounts.gd (genérico): cuenta = carpeta de configuración en una variable. Adaptadores: account_variable/default_account_dir/account_email. Claude CLAUDE_CONFIG_DIR ~/.claude (email de .claude.json); Antigravity GEMINI_HOME ~/.gemini (del binario agy_acp_server); Codex CODEX_HOME ~/.codex. Otro agente: campo account_variable del perfil.
- AgentAccounts.apply/choice/menu: la lógica de cuentas salió del dock (que solo arma el menú). apply ignora una carpeta que ya no existe.
- Búsqueda: la carpeta del perfil, la por defecto, ~/.<carpeta>-profiles/* y las agregadas con «Otra carpeta…» (agents/accounts, por variable).
- AgentProfile: account_dir + account_env (runtime); account_variable se guarda.
- Historial: guarda account; una sesión sin el dato (anterior a esto) se reabre con la cuenta del perfil; las que lista el agente traen la cuenta del agente que corre. Borrar solo le pide al agente si es el mismo perfil y la misma cuenta (SessionController.owns_session).
- Windows: normalize pasa \\ a /; el email de ~/.claude usa USERPROFILE si no hay HOME.
- Revisión de código (02/11) con godot-code-review: 5 hallazgos, todos arreglados con test (run_all 408/408, sessions-test y settings-shots ok).
- Sin probar: dos cuentas reales a la vez. openrouter: su env file no se lee.

### One-shot con archivos de referencia (GDD, arte…) · Revisión

**Prioridad:** media · **Tamaño:** S · **Responsable:** Claude

Pedido del usuario (02/11): a la pantalla One-shot se le tienen que poder dar archivos, como un GDD, además del objetivo en texto.

**Decisiones:**
- ! Los archivos de afuera del proyecto se copian a .godot_agent/oneshot/<id>/refs/ en vez de pasarle al agente la ruta original · sin revisar
  Por qué: El agente trabaja dentro del proyecto (permisos de lectura, worktrees, otra máquina al retomar), y la copia viaja con el run en la rama del agente.
  Descartado: Pasar la ruta original (puede pedir permiso o no existir al retomar); copiar a una carpeta visible del proyecto (ensucia el FileSystem y el export).

**Prueba:** Pantalla One-shot: «+ Archivos de referencia…» abre un diálogo de archivos (cualquier carpeta); soltar archivos del FileSystem en el formulario también los suma. Cada uno es un chip con ✕. Al iniciar, el primer prompt los lista antes de los pasos; los de afuera del proyecto quedan copiados en .godot_agent/oneshot/<id>/refs/. La barra del run muestra «📎 N» y el tooltip las rutas. Automático: test_oneshot_files.test_add_references, test_oneshot_references, oneshot_check (copia, primer prompt, recuperación y retomar), oneshot-test en Xvfb (formulario, chips, run).

**Notas:** - OneShotFiles.add_references: los del proyecto en su lugar, los de afuera copiados a refs/ (nombre libre si se repite), tope 50 MB por archivo (viajan en la rama del agente con los checkpoints); los que no se pueden usar van como aviso en la actividad.
- OneShotRun.references: en el prompt inicial (antes de la spec; si chocan con el objetivo gana el objetivo), en el del evaluador de QA y al retomar; se guarda en to_dict.
- agent_main_screen: botón + chips + drop desde el FileSystem en todo el panel del formulario. No toma archivos soltados desde el sistema operativo (files_dropped es de toda la ventana del editor).
- Leer PDF o imágenes depende del agente (Claude Code los lee con Read).

### El tooltip del anillo de cuota se cierra al segundo de aparecer · Revisión

**Prioridad:** media · **Tamaño:** S

Bug reportado por el usuario (02/11): al pasar el mouse por el anillo de cuota del dock, el tooltip aparece y se esconde al segundo.

Causa probable (sin verificar): AgentDock._on_quota_tick corre cada 1 s con _quota_timer (agent_dock.gd ~515-548) y llama a QuotaRing.refresh(), que hace tooltip_text = describe() (quota_ring.gd:56). El texto incluye la cuenta regresiva del reinicio, que cambia cada segundo, y Godot cierra el tooltip abierto cuando cambia tooltip_text.

Arreglo posible: asignar tooltip_text solo si el texto cambió y redondear el reinicio a minutos; o armar el texto en _get_tooltip() para que se calcule al abrir. Revisar también la fila de cuota del One-shot (agent_main_screen.gd:882), que se refresca con quota.changed.

Probar con el editor abierto: el tooltip queda visible mientras el mouse está encima, con y sin límite alcanzado.

**Prueba:** En tu editor, pasá el mouse por el anillo de cuota (abajo del dock): a los 0,35 s se abre el detalle en un panel arriba del anillo y queda abierto mientras el mouse esté encima, también con un turno en curso. Se cierra al sacar el mouse. Automático: tests/run_in_xvfb.sh <godot> -- --godot-agent-ui-test=ui_quota y =ui_quota_busy, en 4.7.2 y 4.8-beta2: PASS. Comprueban el panel abierto 4 s, arriba del anillo, sin tapar el mouse y dentro de la ventana, que no se abra además el tooltip de Godot y que se cierre al salir. Captura <shot>_quota_hint.png. run_all 410/0.

**Notas:** Causa (la encontró el usuario el 02/11): el anillo está abajo de todo y el tooltip es alto. Godot lo corre hacia arriba para que entre en la pantalla, queda debajo del mouse y se cierra solo. En Xvfb no se veía porque ahí el tooltip entraba.
Arreglo: QuotaRing ya no usa tooltip_text. hint_text guarda el detalle, y un PanelContainer top_level (mouse_filter IGNORE, estilo TooltipPanel del tema) se abre con mouse_entered después de HOVER_DELAY_S, siempre arriba del anillo, centrado y dentro de la ventana (abajo solo si arriba no entra). Se cierra con mouse_exited o al ocultarse. Si el detalle cambia con el panel abierto, se actualiza en el lugar.
Además, el tick de 1 s ya no toca nada si no cambió: refresh compara texto y estado del dibujo, set_context ignora valores iguales y Composer.set_locked ignora el mismo texto.
Tests: test_quota_ring usa hint_text. El dev plugin tiene _check_ring_tooltip y el guion tests/scripts/ui_quota_busy.json.

### One-shot: dejar claro que el spec se puede cambiar desde el chat · Revisión

**Prioridad:** media · **Tamaño:** S

Pregunta del usuario (02/11): con el spec en revisión, ¿se le pueden pedir cambios al agente desde el chat? Sí se puede, pero no está claro.

Hoy: en SPEC_REVIEW, lo que se escribe en el chat del dock se manda ya (OneShotRun, oneshot_run.gd:534) y al terminar el turno vuelve a SPEC_REVIEW porque _awaiting_spec sigue en true (línea 756). Problemas:
1. La pantalla no lo dice: la barra del spec (agent_main_screen.gd ~486) solo tiene «Editar» y «Aprobar spec». Solo lo menciona el aviso de cuando falta spec.md.
2. El mensaje va crudo: la orden de no construir estaba solo en el prompt inicial, así que «cambiá los controles a WASD» puede hacer que el agente construya antes de la aprobación.

Arreglo:
- Una nota bajo la barra del spec: «¿Querés cambios? Pedíselos en el chat: el agente actualiza el spec y vuelve a esperar tu aprobación». Que el aviso del chat de _enter_spec_review lo diga también.
- Si phase es SPEC_REVIEW o _awaiting_spec, envolver la guía: «Apply this to spec.md and end the turn without building: the user still has to approve it.» También la que queda en cola.
- i18n es.po, wiki One-shot en/es y CHANGELOG.

Prueba: oneshot_check con un mensaje en revisión de spec (el prompt sale envuelto y el run vuelve a SPEC_REVIEW) y la nota visible en oneshot-test.

**Prueba:** One-shot con «Revisar el spec antes de construir». Cuando aparece «Spec para revisar», la columna dice «¿Querés cambios? Pedíselos en el chat del agente…» y el aviso del chat también lo dice. Escribí en el chat «sumá power-ups»: el agente actualiza spec.md, no construye y el run vuelve a «Spec para revisar». Automático: oneshot_check 140/0 (escenario spec: el pedido sale envuelto con la ruta de spec.md y «without building», y el run vuelve a SPEC_REVIEW). oneshot-test en Xvfb PASS.

**Notas:** - OneShotRun._user_prompt(text): mientras _awaiting_spec, el mensaje del usuario sale como «The user hasn't approved the spec yet and asks for this: … Apply it to <dir>/spec.md (answer in the chat if it's a question) and end the turn without building anything». Vale para el mensaje que sale ya y para el que estaba en cola (_pop_guidance).
- Pantalla: _plan_note cambia de texto en la revisión (antes se ocultaba). Aviso del chat de _enter_spec_review ampliado. es.po, wiki One-shot en/es y CHANGELOG.

### Turno colgado: el agente terminó pero el dock queda trabajando y Stop se queda en «cancelling» · Revisión

**Prioridad:** alta · **Tamaño:** M

Bug del usuario (02/11, Project Epiphany, Godot 4.8-beta2, Claude Code · personal, modo Build). El agente terminó su respuesta a las 05:30:55 UTC: es el último mensaje del transcript de Claude y el proceso quedó ocioso, sin hijos. El dock siguió en «The agent is working», con un mensaje en cola. Stop lo deja en «cancelling…» para siempre.

Lo que se vio:
- user://godot_agent/sessions/5ac56c68….jsonl solo tiene el primer turno: el segundo nunca llegó a record_turn_end. O la respuesta de session/prompt no llegó, o send_prompt cortó entre el request y model.finish_turn.
- SessionController.cancel() pasa a CANCELLING y solo manda la notificación session/cancel. Si el agente no tiene un turno abierto, no contesta nada y no hay ningún tiempo límite.
- El log del editor no sirve: el godot.log lo pisó la corrida del juego.

Para hacer:
1. Cancelar sin colgarse: si a los ~5 s de session/cancel no llegó la respuesta del prompt, cerrar el turno local («cancelled»), guardar el historial y avisar en el chat. Si el agente igual no responde, ofrecer reiniciarlo, retomando la sesión.
2. Encontrar la causa: registrar en AgentLog la llegada de la respuesta de session/prompt (id y stopReason) y cualquier error de script entre el request y finish_turn (send_prompt, session_controller.gd ~450-490). Mirar también la lectura de líneas del ACP client con mensajes grandes.
3. Que el historial no dependa del fin de turno: hoy save() solo corre en turn_end, así que un turno colgado no deja nada.

Prueba: un agente falso que nunca responde session/prompt y tampoco el cancel → Stop vuelve a idle en ≤5 s y el mensaje en cola sale.

**Prueba:** Con un agente que se cuelgue (o el falso con el paso «hang»), apretá Stop. A los 8 s el turno se cierra solo, sale el mensaje en cola y aparece un aviso con «Reiniciar el agente», que reabre la misma sesión. Automático: el escenario «hang» de tests/acp_session_check.gd (171/0) comprueba que el prompt queda en el historial antes de que termine el turno, el cierre en menos de 10 s, la vuelta a READY, el aviso, el log y que el turno siguiente funcione. run_all 410/0.

**Notas:** - SessionController: _prompt_request_id es el session/prompt en vuelo. cancel() arranca _watch_cancel (CANCEL_TIMEOUT_SEC = 8). Si el estado sigue en CANCELLING, despierta el request con client.cancel_request y send_prompt cierra el turno como «cancelled». Si el request ya no está (llegó la respuesta y algo cortó antes de finish_turn), cierra el turno ahí mismo. Ese caso agrega un aviso con ACTION_RESTART_AGENT y el log.
- Dock: ACTION_RESTART_AGENT llama a open_history_session(session_id): proceso nuevo y la misma sesión. Si no puede, usa start_session.
- Log: «Turn ended: <stopReason>» en cada fin de turno, y AcpClient ya registraba «← session/prompt #N ok». Con eso, la próxima vez se ve si la respuesta llegó.
- SessionHistory: guarda en record_prompt y cada 15 s durante el turno (SAVE_INTERVAL_MSEC), no solo en turn_end.
- La causa del caso de Epiphany sigue sin confirmar: no quedó log. Elegí 8 s y no 5 para que un cancel real con una tool larga alcance a confirmar.

### Con una sesión trabajando, «Nueva sesión» y el historial la abren en otra pestaña en vez de bloquearse · Revisión

**Prioridad:** media · **Tamaño:** S

Reporte del usuario (02/11): «si una sesión está trabajando, no puedo abrir otra».

Hoy, en agent_dock.gd, mientras el turno está en STARTING, PROMPTING o CANCELLING:
- _new_session_button queda deshabilitado (línea ~733).
- El menú del historial deshabilita todos sus ítems (~873) y _on_history_selected no hace nada (~933).
Las dos acciones reemplazan la sesión de la pestaña actual, por eso se bloquean. La única salida es el «+» de las pestañas, y eso no es evidente.

Arreglo propuesto:
- Con la pestaña ocupada, «Nueva sesión» y elegir una sesión del historial abren una pestaña nueva, con el mismo agente y la misma cuenta, en vez de quedar deshabilitados.
- El tooltip lo dice: «Se abre en otra pestaña: esta sigue trabajando».
- Una sesión que ya está abierta en otra pestaña enfoca esa pestaña y no se abre dos veces.
- Se respeta can_switch_session: con One-shot corriendo sigue el aviso.

Prueba: sessions-test en Xvfb con la pestaña 1 en PROMPTING (agente falso). «Nueva sesión» y el historial crean la pestaña 2 y la 1 sigue en su turno.

**Prueba:** Con un turno en curso en una pestaña, tocá «+» › «Nueva sesión»: se abre una pestaña nueva con el mismo agente y cuenta, y arranca una sesión ahí. El tooltip lo avisa. En el historial, arriba aparece «Esta pestaña está trabajando: la sesión se abre en una nueva», y elegir una sesión la abre en otra pestaña. Si esa sesión ya está abierta en otra pestaña, la elige en lugar de abrirla de nuevo. Lo mismo en la pestaña de un One-shot en curso. Automático: sessions-test en Xvfb PASS. Con la primera en PROMPTING comprueba: el botón habilitado, que «Nueva sesión» y el historial emitan open_elsewhere_requested ("" y el id), que session_focuser elija la pestaña que tiene la sesión, y que _open_elsewhere cree y elija la pestaña. run_all 410/0.

**Notas:** - AgentDock: señal open_elsewhere_requested(session_id) y _must_open_elsewhere() (STARTING/PROMPTING/CANCELLING o can_switch_session falso). «Nueva sesión» ya no se deshabilita por estar ocupada, solo en STARTING. El historial ya no deshabilita los ítems: muestra un separador con el aviso. session_focuser(id) evita abrir dos veces la misma sesión, también con la pestaña libre.
- plugin: _wire_elsewhere en la primera pestaña y en las extra. _open_elsewhere usa _create_session_tab + copy_agent_from + select y después start_session u open_history_session. _focus_session recorre las pestañas por model.session_id.
- Saqué el aviso «A One-shot is running: stop it before opening another session.»: ahora se abre en otra pestaña.

**Relacionadas:** One-shot ligado a su sesión: una pestaña propia, sin tomar el dock entero

### Imágenes pegadas en el chat que quedan cargadas y no le llegan al agente · Revisión

**Prioridad:** alta · **Tamaño:** S

Reporte del usuario (02/11): «las imágenes pegadas no se las da al agente, quedan cargadas y no se usan».

En agent_dock.gd, las imágenes se juntan en _images y se consumen en _take_context_blocks() cuando el mensaje sale (_send), o pasan a la cola si el agente está ocupado. Estos caminos dejan el chip cargado sin mandar la imagen:
1. One-shot activo: submit_interceptor → OneShotRun.take_dock_prompt(text) → guide(text) recibe solo el texto (agent_dock.gd ~953, oneshot_run.gd:492). Las imágenes no entran en la guía del run.
2. Mensajes que empiezan con «/»: van solos a propósito (send_prompt), y los adjuntos quedan para el próximo mensaje sin avisar.
3. Arranque fallido: en STARTING o DISCONNECTED solo se guarda _pending_prompt (el texto). Si start falla, la imagen queda en el chip.
Falta confirmar con el usuario en qué caso le pasó.

Arreglo:
- La guía del One-shot acepta bloques (guide(text, blocks)), tanto encolada como enviada ya.
- Con un comando «/», un aviso: «La imagen va con tu próximo mensaje».
- Pruebas: oneshot_check con una guía con imagen; test del dock con imagen + comando.

**Prueba:** Con un One-shot corriendo, pegá una imagen en el chat del dock y escribí algo. El chip se va y el mensaje del run muestra la imagen adjunta. Si el agente estaba en un turno, la actividad dice «queued: … · 📎 1 attachment» y la imagen sale con la guía al terminar el turno. Automático: oneshot_check 140/0 (escenario de presupuestos: la guía encolada con una imagen llega al agente con la imagen), run_all 410/0, oneshot-test en Xvfb PASS.

**Notas:** - OneShotRun.guide(text, blocks) y take_dock_prompt(text, blocks). _guidance_blocks va en paralelo a _guidance (_push_guidance y _pop_guidance devuelven [prompt, blocks]). _run_turn y send_in_mode pasan los bloques a send_prompt.
- Dock: submit_interceptor(text, take_blocks). El plugin llama a take_blocks (que saca los adjuntos del composer) solo si el One-shot está activo y se queda con el mensaje.
- Los adjuntos encolados no se guardan con el run: si el editor se cierra, el texto queda y la imagen se pierde.
- Casos 2 y 3 de la descripción (comando «/», arranque fallido): sin cambios. El usuario confirmó que le pasó con el One-shot.

**Relacionadas:** One-shot ligado a su sesión: una pestaña propia, sin tomar el dock entero

### One-shot ligado a su sesión: una pestaña propia, sin tomar el dock entero · Revisión

**Prioridad:** alta · **Tamaño:** M

Pedido del usuario (02/11): «el modo debería estar ligado a la sesión, no a todas».

Hoy (plugin.gd ~225-245) el One-shot corre en la sesión de la primera pestaña (_model/_controller):
- submit_interceptor manda todo lo que se escribe ahí a OneShotRun.guide().
- can_switch_session bloquea abrir otra sesión mientras corre el run.
- set_oneshot_active cambia el composer.
Mientras dura el run, la primera pestaña deja de ser un chat normal. Las pestañas extra (allow_oneshot = false) no se ven afectadas, pero no es evidente cuál es la del run.

Propuesta:
- El run abre su propia pestaña, «One-shot · <objetivo>», con su sesión. Esa pestaña lleva el interceptor (con imágenes, ver m17-18), el retry y el composer en modo One-shot.
- Las demás pestañas, incluida la que estaba abierta, siguen siendo chats normales: pueden cambiar de sesión, abrir el historial y elegir modo.
- Al terminar o detener el run, su pestaña queda como sesión normal, para leerla o seguir charlando.
- Retomar un run (recover/resume) reabre su pestaña.
- El modo del agente (Build/Plan/…) también es por pestaña: confirmar que el run no cambia el de las otras.

Prueba: oneshot-test con dos pestañas. La guía de la pestaña del run llega al run, y la otra manda prompts normales y puede abrir el historial durante el run.

**Decisiones:**
- ! Cada run abre una pestaña nueva (no reusa la del run anterior), con el agente y la cuenta de la pestaña activa al lanzarlo · sin revisar
  Por qué: Reusar la pestaña del run anterior seguiría su sesión (start reusa la sesión conectada) y mezclaría dos runs en una conversación. Tomar el agente de la pestaña activa respeta la cuenta elegida por pestaña (m17-12).
  Descartado: Reusar la pestaña del run anterior reiniciando su sesión; usar siempre el último agente elegido; preguntar el agente en el formulario del One-shot.

**Prueba:** Con dos pestañas, lanzá un One-shot desde la pantalla One-shot. Aparece una pestaña nueva «One-shot · <objetivo>», ya elegida, con el agente y la cuenta de la pestaña desde la que lo lanzaste. Lo que escribís ahí va al run, y en la primera pestaña podés chatear, cambiar de sesión y abrir el historial como siempre. Cerrar la pestaña del run con el run en curso no se puede (sale un aviso). Al terminar queda como sesión común y se puede cerrar. Retomar un run a medias, después de reabrir el editor, abre su pestaña. Automático: oneshot-test en Xvfb PASS, con el tramo nuevo _check_run_tab (pestaña nueva, el run en su controller, interceptor y can_switch_session por pestaña, composer en modo One-shot solo en la del run, guía que llega, no se cierra en curso, al cerrarla el run vuelve a la primera). run_all 410/0, oneshot_check 140/0, sessions-test PASS.

**Notas:** - OneShotRun.bind(controller) mueve las conexiones al modelo nuevo y emite controller_changed (la pantalla se reconecta a la cuota y al plan). prepare_session es un hook async que se llama en start() y al retomar un run que vino de disco.
- plugin: _prepare_oneshot_tab crea la pestaña con _create_session_tab(null, «One-shot · objetivo», for_oneshot = true), copia agente y cuenta de la pestaña activa (AgentDock.copy_agent_from) y hace bind + select. _open_session_tab ahora usa _create_session_tab.
- _wire_oneshot(dock, id) arma, por id, el interceptor, el retry, can_switch_session, after_login y el modo One-shot del composer, que valen solo si _oneshot.controller es el de esa pestaña (_runs_in). Va en la primera y en todas las pestañas que no son copias. Sin capturar controller ni dock, para no armar ciclos; el listener de changed se desconecta al cerrar.
- _close_session_tab: con el run activo en esa pestaña no la cierra y avisa. Si el run ya terminó, lo vuelve a la primera sesión.
- restart_session usa _oneshot.controller y el perfil de su pestaña. agent_name de la pantalla: el del run en curso o el de la pestaña activa.
- Los tramos viejos del test corren con prepare_session apagado, como antes, en la primera sesión.

**Relacionadas:** Con una sesión trabajando, «Nueva sesión» y el historial la abren en otra pestaña en vez de bloquearse; Imágenes pegadas en el chat que quedan cargadas y no le llegan al agente

### El JSON de checks del One-shot sale crudo en el chat: mostrarlo plegado como resumen · Revisión

**Prioridad:** media · **Tamaño:** S

Reporte del usuario (02/11, Road Fighter 3D, informe de QA ronda 1): «no entiendo ese json largo que largó luego de una sesión de QA».

El One-shot pide al agente y al evaluador de QA que cierren cada turno con un bloque ```json {"checks":[…]}```. El harness lo lee para el estado de los checks, pero el chat lo muestra como un bloque de código largo, aunque no está pensado para que lo lea una persona.

Ya hay un mecanismo igual para Revisar: los bloques `findings` se pliegan. SessionController._fold_findings pone entry.findings_count, y agent_message_view.gd (~71, 137) dibuja SegmentKind.FINDINGS como un resumen en lugar del código.

Arreglo:
- Un SegmentKind.CHECKS en agent_message_view, para mensajes del agente con un bloque `{"checks": …}` válido. Se dibuja como una línea plegada: «Checks: 6 ✓ · 1 ✗ · 0 sin verificar — ver en One-shot».
- Al expandirla aparece la lista legible: ícono de estado + label, y el detalle en el tooltip o en una segunda línea. El JSON crudo queda detrás de «ver JSON», para depurar.
- Lo mismo para los mensajes del evaluador de QA. Revisar si el informe trae otros bloques para la máquina (el veredicto) y plegarlos igual.
- La detección usa el mismo parser del run (OneShotRun / checks), para no tener dos.
- Funciona también al reabrir una sesión del historial.

Prueba: test de agent_message_view con un mensaje que trae un bloque de checks → se ve el resumen y no el código. oneshot-test en Xvfb con una captura del chat.

**Prueba:** run_all 412/0. tests/unit/test_agent_message_view.gd: bloque checks+scores+findings → resumen plegado (cuenta ✓/✗/sin verificar, puntajes, hallazgos), lista legible con detalle y BBCode escapado, JSON detrás de «Ver JSON»; un JSON cualquiera o a medio llegar sigue como código.

**Notas:** FindingsParser.report_block(code) reusa parse() (el mismo parser del run). La vista detecta el bloque por su contenido, no por un flag de la entrada: anda en cualquier modo y al reabrir del historial. Durante el streaming se ve como código hasta que el JSON cierra. En Revisar, un bloque findings leído sigue plegándose como antes (tiene prioridad). No verificado con captura en Xvfb.

### Chat: adjuntar imágenes y archivos de fuera del proyecto desde «+ context» · Revisión

**Prioridad:** media · **Tamaño:** S

Pedido del usuario (02/11): poder darle al agente imágenes de fuera del proyecto.

Hoy el diálogo de «+ context › Archivos…» del dock (agent_dock.gd ~1284) usa EditorFileDialog.ACCESS_RESOURCES, así que solo navega res://. add_context_files ya acepta imágenes de cualquier ruta (Image.load_from_file). Los demás archivos de fuera del proyecto se rechazan con «Only images and project files can be attached».

Arreglo:
- El diálogo pasa a ACCESS_FILESYSTEM, abriendo en la carpeta del proyecto y recordando la última carpeta usada.
- Las imágenes de afuera se adjuntan como ya se hace hoy.
- Los textos de afuera (.md, .txt, .json, .pdf…): adjuntarlos como resource_link file:// con la ruta absoluta, para que el agente los lea, o como bloque de texto si son chicos. Elegir según lo que acepte el agente (capabilities: embeddedContext). Que no queden rechazados.
- Opcional: soltar archivos desde el explorador del sistema en el dock. files_dropped es de la ventana; ver si se puede limitar al dock que tiene el mouse encima.
- i18n y wiki (Chat/Context).

Prueba: un test de add_context_files con una imagen y un .md en tests/tmp fuera de res://. La imagen sale como bloque image y el .md como resource_link o texto en el prompt.

**Decisiones:**
- ! Archivos de afuera como resource_link con ruta absoluta, sin embeber el texto · sin revisar
  Por qué: Funciona con cualquier agente y tamaño (PDF incluido) y no depende de embeddedContext; Claude Code lee la ruta absoluta.
  Descartado: Embeber como bloque resource/texto si es chico y el agente acepta embeddedContext.

**Prueba:** ui-test ui_quota PASS (Xvfb, 4.7.2): un .md en user:// (fuera de res://) queda como resource_link file://<ruta absoluta> con mimeType text/markdown; una ruta que no existe no se adjunta; el chip se limpia al enviar. Las imágenes de afuera ya estaban cubiertas en el mismo test.

**Notas:** Diálogo con ACCESS_FILESYSTEM, abre en la carpeta del proyecto; la misma instancia recuerda la última carpeta mientras el editor está abierto (no se guarda entre sesiones). Fuera del proyecto siempre resource_link (no texto embebido): no dependo de embeddedContext y sirve también para PDF. mimeType según extensión. Menú: «Archivo…» en lugar de «Archivo del proyecto…». No hice el soltar archivos desde el explorador del sistema (era opcional).

### Composer del chat: que crezca con el texto y se pueda agrandar a mano · Revisión

**Prioridad:** media · **Tamaño:** S

Pedido del usuario (02/11, captura con un prompt largo pegado): el cuadro donde se escribe queda chico, con unas 3 líneas y una barra de scroll, y no se puede agrandar.

Hoy composer.gd:110-111 fija _input.custom_minimum_size.y = 72 px y scroll_fit_content_height = false: el alto es fijo.

Arreglo:
- Crecer con el contenido: el alto sigue al texto (scroll_fit_content_height, o la cuenta de líneas visuales con wrap × line height) entre el mínimo actual y un tope de ~40 % del alto del dock. A partir del tope aparece el scroll.
- Una manija para arrastrar en el borde de arriba del composer, que fija el alto a mano entre el mínimo y ~70 % del dock. Doble clic vuelve al automático. El alto elegido se guarda en EditorSettings (godot_agent/ui/composer_height) y vale para todas las pestañas.
- Al mandar el mensaje vuelve al alto de reposo, salvo que el alto se haya fijado a mano.
- Cuidar _fit_row y los chips de contexto de arriba, para que la fila de botones no salte. El historial del chat se achica, no se superpone.
- Funciona igual en el dock y en el panel inferior.

Prueba: en Xvfb, pegar 30 líneas → el composer crece hasta el tope. Arrastrar la manija → cambia el alto y se guarda. Mandar el mensaje → vuelve al alto de reposo. Captura antes y después.

**Prueba:** run_all 413/0 (test_composer.test_height_follows_text_and_grip: tope 40 %/70 %, mínimo, 30 líneas crecen al tope, clear vuelve al reposo, arrastrar la manija agranda y queda fijado, fijado no sigue al texto, doble clic vuelve a automático). ui-test ui_quota en Xvfb 4.7.2 y 4.8-beta2: 30 líneas → crece >1,5× y ≤41 % del dock, el chat no queda debajo del composer, vuelve al alto de reposo al limpiar; captura <shot>_composer.png revisada (el texto llena el cuadro hasta la última línea).

**Notas:** Manija de 6 px arriba de los chips (cursor VSIZE). Alto fijado en EditorSettings godot_agent/ui/composer_height sin la escala del editor; se aplica a todas las pestañas vía grupo godot_agent_composers. text_changed no sale cuando el texto se pone por código: update_height se llama también en clear, insert_text y al recorrer el historial. Al crecer, el CodeEdit dejaba el scroll del alto viejo (líneas arriba, aire abajo): _fit_scroll en resized lo corrige. El panel inferior usa el mismo composer: no lo probé ahí aparte. De paso, sessions-test fallaba en 4.8 porque dependía de la cuenta guardada en las EditorSettings de quien lo corre: ahora la limpia y la restaura.

### Detalle del anillo de cuota con barras de progreso en lugar de texto · Revisión

**Prioridad:** media · **Tamaño:** S

Pedido del usuario (02/11): el panel que abre el anillo de cuota (m17-14) lista los porcentajes como texto. Tiene que mostrar una barra de progreso por ventana (sesión de 5 h, semanal, grupos por modelo) y para el contexto, con el color del anillo según el uso, y el reinicio al lado. Se trabaja en un worktree porque el usuario tiene el editor abierto con el addon enlazado.

**Prueba:** run_all 414/0 (test_quota_ring.test_hint_rows_are_bars: contexto + 2 ventanas como barras, valores, detalle «36 % · resets in 1 h», color del anillo, 3 ProgressBar en el panel). ui-test ui_quota_busy en Xvfb 4.7.2 y 4.8-beta2: PASS, captura revisada (barras de contexto, ventana y semana arriba del anillo).

**Notas:** Hecho en el worktree .claude/worktrees/quota-bars (rama quota-bars), sin commitear, porque el usuario tiene el editor abierto con el addon enlazado. QuotaRing.hint_rows() da filas title/text/bar; el panel las arma con ProgressBar (fondo TRACK_COLOR, relleno color_for). hint_text sigue siendo el texto (tests, chequeo del límite). Contexto con color propio: acento, amarillo ≥80 %, rojo ≥95 %. QuotaMonitor.reset_in(data). De paso: el chequeo del composer del ui-test fallaba en 4.8 por el alto fijado a mano en las EditorSettings del usuario; ahora lo guarda, prueba en automático y lo restaura.

### Antigravity: la allowlist no se aplica y la tarjeta de permiso no ofrece recordar · Revisión

**Prioridad:** alta · **Tamaño:** S

Reporte del usuario (02/11, Road Fighter 3D con Antigravity): «cat * está en la allowlist pero antigravity pide permiso siempre, y no da opción de recordar el permiso».

Causa: Antigravity manda el comando en rawInput.CommandLine (y command_line en el update), no en rawInput.command. El broker leía command vacío: ShellRules no lo encontraba en la allowlist, no podía proponer regla (por eso sin «recordar» en Auto), y ProjectWriteGuard/GodotWindowGuard tampoco veían el comando. En los otros modos, Antigravity solo ofrece allow_once/reject_once, así que no hay «siempre».

**Prueba:** run_all 416/0. tests/unit/test_shell_command.gd: ShellCommand.of con command/CommandLine/command_line/lista; con el formato de Antigravity, en Auto `cat a b` pasa sin tarjeta, escribir main.tscn por shell se rechaza, `npm test` pregunta y propone la regla «npm test» (sin «siempre en la sesión»); en Build la tarjeta trae «Siempre en esta sesión» aunque el agente solo ofrezca «una vez», al agente se le contesta allow_once y el siguiente comando de la sesión pasa sin preguntar. acp_session_check 171/0. Para probar en tu editor: Antigravity en Auto, pedirle `cat` de dos archivos → no pregunta.

**Notas:** Nuevo session/shell_command.gd (ShellCommand.of): claves command, CommandLine, command_line, commandLine, cmd, o lista. Lo usan PermissionBroker (allowlist, sugerencia de regla, GodotWindowGuard, descripción de la tarjeta), ProjectWriteGuard (bloqueo de escrituras por shell, que con Antigravity tampoco andaba) y el resumen de tool_group_view. PermissionBroker._offer_session_allow suma la opción godot_agent_allow_always cuando el agente no trae allow_always (no en la shell en Auto, donde va la regla). La allowlist sigue siendo solo del modo Auto, como dice la wiki. En el worktree quota-bars, sin commitear.

### El estado de la sesión (listo, trabajando) va abajo, arriba del composer · Revisión

**Prioridad:** media · **Tamaño:** S

Pedido del usuario (02/11): «el indicador de estado (ready, working) debería estar abajo, arriba de donde va el chat». Hoy la palabra del estado va en el chip del agente del header (m12-14), lejos de donde se mira al escribir.

**Prueba:** run_all 416/0. ui-test ui_quota_busy en Xvfb 4.7.2 y 4.8-beta2: con un turno en curso la línea dice «Working…», está visible y termina arriba del composer, y el chip del agente ya no lleva el estado; captura <shot>_state.png revisada. sessions-test y oneshot-test PASS (4.7.2).

**Notas:** AgentDock._state_line (Label en composer_column, justo antes del composer): ◌ Conectando…, ● Listo, ● Trabajando… · N subagentes, ● Cancelando…, ○ Falta iniciar sesión / ✗ Error; con una tarjeta pendiente, «● Te está esperando» en el color de acento. Sin sesión (desconectado) no se ve. Tooltip: el mismo que el estado (cuenta, subagentes, error). El chip queda con el nombre y el punto/borde del color del estado. Strings viejas en minúscula reemplazadas en es.po. En el worktree quota-bars, sin commitear.

### Tarjeta de permiso con un comando largo: los botones quedaban fuera de la vista · Revisión

**Prioridad:** alta · **Tamaño:** S

Reporte del usuario (02/11, Antigravity): «me apareció un super coso que no sé cómo aprobar». Antigravity pidió permiso para un `python3 - << 'EOF'` de cientos de líneas (escribía un informe en ~/.gemini). El título de la tarjeta era el comando entero, así que ocupaba todo el dock y Allow once/Deny quedaban muy abajo.

**Prueba:** run_all 417/0 (test_permission_view.test_long_command_is_folded: short_text corta a la primera línea / 140 caracteres; con 202 líneas el título es una línea, «Show all (202 lines)» plegado, los botones visibles, al abrir aparece el comando entero). ui-test ui_long_permission (guion nuevo tests/scripts/ui_long_permission.json, 152 líneas con CommandLine) en Xvfb 4.7.2: «Allow once» queda dentro del dock y se aprueba; captura revisada.

**Notas:** PermissionView: título y descripción pasan por short_text (primera línea, hasta TITLE_MAX_CHARS, con «…»); lo que no entra va en un ScrollContainer de 220 px, plegado detrás de «Ver todo (N líneas)», en fuente mono. En el worktree quota-bars, sin commitear.

### Skills para todos los agentes: «Para todos los agentes» en Extensiones · Revisión

**Prioridad:** media · **Tamaño:** M

Pedido del usuario (02/11): «no pueden estar las skills para todos los agentes? que no sea exclusivo de claude».

Hoy las skills del usuario están solo en la carpeta de Claude (<CLAUDE_CONFIG_DIR>/skills). Antigravity, Codex, opencode, etc. leen el mismo formato (carpeta con SKILL.md) desde sus carpetas (~/.agents/skills compartida, ~/.gemini/config/skills…), que están vacías: Antigravity no tiene ninguna skill.

Arreglo: en Extensiones, cada skill de usuario o de proyecto tiene «Para todos los agentes». Mueve la skill a la carpeta compartida (~/.agents/skills o <proyecto>/.agents/skills) y deja un symlink en la de Claude (que no lee .agents). Una sola copia: editarla cambia para todos. Se puede deshacer (vuelve a la carpeta de Claude). La lista muestra si una skill está compartida.

Lo del marketplace (publicar las skills de Godot también como plugin de Antigravity) va en el repo godot-agent-plugins, en otra sesión.

**Prueba:** run_all 419/0 (test_share_with_all_agents, test_antigravity_plugin_manifest_locations). En el editor: Extensiones › Skills › ⋯ de una skill tuya › «Usar con todos los agentes»: queda en ~/.agents/skills, enlace en la carpeta de Claude, la tarjeta dice «Compartida con todos los agentes». Con Antigravity aparece en Skills. «Solo para Claude Code» la devuelve.

**Notas:** SkillCatalog.share/unshare/is_shared; scan marca "shared". En el proyecto el enlace es relativo (../../.agents/skills/x). No pisa una compartida con el mismo nombre ni una skill propia de Claude. Las de plugins no se comparten. También: manifiesto de plugins de Antigravity en .antigravity-plugin/ y .gemini-plugin/ (docs de Antigravity, aviso de la sesión godot-agent-plugins). En Windows los enlaces de carpeta pueden requerir modo desarrollador: sin probar.

## M16 — Pruebas manuales: Windows y Antigravity  (1/5, 1 en revisión)

Probar en una máquina real lo que el README promete y solo se comprobó en Linux con Claude Code. Las hace Daniel, que tiene con qué probarlas.

**Hecho cuando:**
- El recorrido se hizo en Windows y con Antigravity, y lo que falló quedó cargado como bug.

### 16.1 Recorrido completo en Windows · Pendiente

**Prioridad:** alta · **Tamaño:** M · **Responsable:** Daniel · **Etiquetas:** `manual`, `windows`

CI es solo Linux y una nota del tablero dice «sin probar en Windows». Con Claude Code, para aislar lo que sea de la plataforma.

- [ ] Instalar el zip del último release en un proyecto de prueba y habilitar el plugin
- [ ] Iniciar sesión y conversar en Preguntar
- [ ] Construir: editar una escena y un script, con Ctrl+Z en cada paso
- [ ] Tarjeta de permiso: permitir una vez, en la sesión y denegar
- [ ] Revisar: hallazgos marcados en el Script Editor
- [ ] Playtest con grabación: veredicto, Reproducir la grabación y Correr regresiones
- [ ] One-shot corto: plan, checkpoints, evaluador y Volver acá
- [ ] Agente con npx: que lo encuentre el editor abierto desde el menú, sin el PATH de la terminal
- [ ] Cerrar la sesión y el editor: sin procesos colgados ni errores de PeekNamedPipe en Output
- [ ] Rutas con espacios y acentos en el proyecto
- [ ] Actualizar el addon desde el aviso del dock

### 16.2 Recorrido completo con Antigravity · En curso

**Prioridad:** alta · **Tamaño:** M · **Responsable:** Daniel · **Etiquetas:** `manual`, `antigravity`

Figura como agente sugerido sin ninguna prueba real registrada. Hacerlo en Linux para aislar lo que sea del agente. El Playtest sale del modo plan por su id `default`: comprobar que Antigravity publica ese modo, porque si no se queda en plan.

- [ ] Instalar el zip del último release en un proyecto de prueba y habilitar el plugin
- [ ] Iniciar sesión y conversar en Preguntar
- [ ] Construir: editar una escena y un script, con Ctrl+Z en cada paso
- [ ] Tarjeta de permiso: permitir una vez, en la sesión y denegar
- [ ] Revisar: hallazgos marcados en el Script Editor
- [ ] Playtest con grabación: veredicto, Reproducir la grabación y Correr regresiones
- [ ] One-shot corto: plan, checkpoints, evaluador y Volver acá
- [ ] Agregarlo desde los agentes sugeridos o el registro ACP
- [ ] Modos del agente: qué ids publica y que Revisar, Construir y Playtest caigan en el correcto
- [ ] Cuota: el anillo y el límite con su /usage
- [ ] Sin skills ni plugins: que Extensions lo diga bien

**Decisiones:**
- ! Las tools MCP con _meta.mcp.server == "godot" cuentan como propias del harness (permiso lo decide el server MCP) y se muestran como server.tool · sin revisar
  Por qué: Antigravity titula godot_run_scene y solo _meta.mcp dice el server; por título sin _meta no se asume (un godot_algo cualquiera no se trata como propio)
  Descartado: Reconocer por prefijo de título godot_ (falsos positivos con tools de otros); dejar la tarjeta extra

**Prueba:** Automated tour against the real agent: `AGY_TOUR_WRAP=<agy_wrap.py> AGY_TOUR_LOG=<log> tests/run_in_xvfb.sh godot --godot-agent-antigravity-tour` (Linux, 4.7.2, antigravity-acp 1.4.3), plus `--godot-agent-antigravity-plan-test` for the ```plan block. Both give 0 failures. Unit tests: run_all 832/0, including test_permission_policy (Antigravity cases).

**Notas:** Run with the probe (dev check agy_tour_check.gd) and a wrapper that logs ACP in both directions and proxies MCP over HTTP (rewrites the url in mcpServers of session/new and session/load). Small requests on tests/docs_demo/player.gd (a copy in tests/tmp).

WORKS
- Start: 4.9 s. Capabilities: loadSession, sessionCapabilities list+resume, mcp http+sse, image/audio/embeddedContext.
- Agent modes: default, auto_edit, yolo; the current one is default. There's no plan mode of its own, so the harness uses its ```plan block. Playtest lands in `default` (the id exists, so it doesn't get stuck in plan).
- Ask: 12.6 s. It reads with client_view_file (ACP fs/read_text_file), doesn't edit, stop end_turn.
- Build: each edit asks with the card "Run client_edit_file?" (group edit_files, options allow_once/reject_once/allow_always). Allow once applies the edit through fs/write_text_file; deny blocks it. It also used godot.validate_scripts on its own.
- Plan (m11-58): Plan mode → a ```plan block (15 lines, WHEN/SHALL criteria) → "Plan ready to build" card → saved to .godot_agent/plans → building asks for the first edit_files card.
- Short playtest (Review, from the panel): 82 s, verdict pass in JSON. It uses godot.run_scene, capture_game_frame, game_input, game_script and stop_scene; each asks for the MCP server's card in group run (Review = ask), as with Claude Code.
- Cancel mid-turn: free in 72 ms, stop cancelled.
- History: session/list includes the current session. Resume in a new process with session/load: 6 s, notice "Session resumed… session/load", and the agent remembers what it did (first edit applied, second denied).
- Quota: usage_update arrives (46k / 1,048,576 at the end).

DIDN'T WORK (fixed in sm/m18-02, 49a9e49)
- The harness's MCP tools reached Antigravity as `godot_run_scene` with `_meta.mcp.server = "godot"`. PermissionPolicy didn't recognise them as its own, so every godot tool raised an extra card in group "other", and a playtest waited until someone answered it. Now is_godot_mcp_tool and mcp_server_of read _meta.mcp. Tools from other servers fall in their server's group, and the chat shows them as godot.run_scene.

DIFFERENCES FROM CLAUDE CODE
- Its own titles: "Run client_edit_file?" / "Running client_view_file" instead of Edit/Read, with no diff in the permission card's title.
- After a deny, Antigravity marks the earlier edit, which was applied, as failed ("denied by pre-tool hook"). The dock shows it as failed → m18 task.
- When building a plan it doesn't send ACP `plan` updates (0 tasks): the plan card doesn't follow progress the way it does with Claude Code's TodoWrite.
- The playtest message carries the open scene's path at the start (attached context), same as with other agents.

NOT COVERED (manual, still in the checklist)
- release zip install, Ctrl+Z, "for the session" permission, Review markers in the Script Editor, recording / Replay / regressions, one-shot, adding it from the registry, Extensions without skills, quota ring + /usage limit (only usage_update was seen).
- Antigravity leaves skills/system/run-workflow/SKILL.md in the cwd (deleted, not committed).

### Antigravity escribe skills/ en la carpeta del proyecto · Revisión

**Prioridad:** media · **Etiquetas:** `bug`, `antigravity`

Visto el 2026-11-11 con antigravity-acp 1.4.3 (corrida de m11-58). Al abrir una sesión (session/new con cwd = el proyecto), antigravity-acp crea skills/system/run-workflow/SKILL.md dentro de esa carpeta: es una skill genérica suya, de run_workflow. A cualquier usuario le queda una carpeta skills/ suelta en el proyecto, que puede terminar commiteada o exportada. En el repo ya se coló una vez en un commit.

Qué hacer:
- Ver si se puede evitar: otro cwd (¿respeta las rutas absolutas de fs/* y MCP si el cwd no es el proyecto?), una opción o variable del adapter, o su _meta en session/new.
- Si no se puede, avisarlo: un aviso la primera vez, o sumar skills/system/ al filtro de export o al .gitignore sugerido.
- Documentarlo en Troubleshooting (wiki en/es).

Por qué: le pasa a todo el que use Antigravity y no lo pidió.

**Prueba:** test_agent_adapters::test_antigravity_skills_notice_once (aviso solo si existe el archivo, una vez, WARNING; Claude no avisa). suite.sh ci PASS en 4.7.2; CI verde en 4.7.2, 4.8-beta2 y C# (run 43086848249).

**Notas:** sm/m18-03 b98be91 (desde origin/sm/next4). Lo escribe el Materializer de skills de localharness_external (antigravity-acp 1.4.3) en session/new, sin prompt, en <cwd de la sesión>/skills/system/run-workflow/SKILL.md; no depende del cwd del proceso. SkillsConfig.materialized_skills_dir existe en el proto pero el servidor ACP nunca lo setea; no hay opción, variable de entorno ni _meta. No se puede evitar sin romper Antigravity (la sesión tiene que tener el proyecto como cwd). Arreglo: hook AgentAdapter.notice_after_session; el controlador avisa una vez por proyecto (metadato del proyecto godot_agent/notices_seen); Troubleshooting/Problemas-frecuentes con la sección y .gitignore; CHANGELOG Added.

### Antigravity: edición aplicada que queda marcada como fallida tras un deny · Pendiente

**Prioridad:** baja · **Tamaño:** S · **Etiquetas:** `antigravity`

Visto en m18-02 (antigravity-acp 1.4.3): en un turno con dos ediciones, se permite la primera (aplicada vía fs/write_text_file) y se deniega la segunda; Antigravity manda tool_call_update failed también para la primera («denied by pre-tool hook: Denied by user»). El dock la muestra fallida aunque el archivo cambió. Ver si el harness puede no degradar a failed un tool call cuyo fs/write_text_file ya se aplicó, o al menos avisarlo; si no, reportarlo a Antigravity.

### Antigravity: seguir el avance del plan aprobado sin updates ACP plan · Pendiente

**Prioridad:** baja · **Tamaño:** S · **Etiquetas:** `antigravity`

Visto en m18-02: al construir un plan aprobado, Antigravity no manda session/update plan (0 tareas), así que la tarjeta del plan no marca el avance como con el TodoWrite de Claude Code. Opciones: pedirle en el mensaje de construir que marque las tareas en texto (- [x]) y leerlas, o dejarlo así.

## M17 — GDExtension  (6/6, 6 en revisión)

Que el agente pueda hacer GDExtensions sin poner en riesgo el editor: build con errores parseados, prueba en un proceso descartable, un supervisor fuera del editor para crashes y reinicios, y una skill de scaffolding. No se trae: hot reload dentro del editor ni builds multiplataforma para export (eso es CI).

**Hecho cuando:**
- El agente crea una GDExtension (godot-cpp o gdext), la compila con errores por archivo y la prueba en un Godot headless aparte sin cargarla en el editor.
- Una build que crashea el editor al arrancar no lo deja en un loop: el supervisor vuelve a la última build buena, relanza el editor y el agente retoma la sesión con el backtrace.

### Build nativo con errores por archivo · Revisión

**Prioridad:** alta · **Tamaño:** M

Una tool que haga para GDExtension lo que core/csharp_build.gd hace para C#: detectar SConstruct, CMakeLists.txt o Cargo.toml, compilar y devolver {ruta: errores} para que el agente se entere en la misma tool. rustc tiene --message-format=json; gcc/clang tienen un formato de diagnóstico estable. El timeout de 180 s del build de C# no alcanza para la primera compilación de godot-cpp (varios minutos): hay que subirlo o hacerlo incremental. Si falta el toolchain (compilador, scons/cmake, cargo), avisar como se hace hoy con dotnet.

**Decisiones:**
- ! Las tareas de GDExtension van en un hito nuevo, M17 (m19), creado a mano en compass/milestones/m19.json · sin revisar
  Por qué: Ningún hito existente encaja, y scompass no tiene un comando para crear hitos.
  Descartado: Meterlas en M12 (m14, «Que el agente se verifique solo») o en M9 (m11, ideas de otros harness).
- ! build_extension pide permiso como la shell (grupo shell), no como diagnóstico · sin revisar
  Por qué: Un SConstruct es Python y un build.rs es Rust: compilar ejecuta código del proyecto, como un comando de shell.
  Descartado: El grupo diagnostics (allow en todos los modos), como validate_scripts con dotnet build.
- ! build_extension es una tool extendida (godot.methods / godot.run), y el contexto del agente explica cómo usarla solo si el proyecto tiene SConstruct, CMakeLists.txt o Cargo.toml · sin revisar
  Por qué: Solo la usan los proyectos con GDExtension: así no gasta contexto en los demás (D56).
  Descartado: Dejarla en el tools/list compacto, al lado de validate_scripts.
- ! La verificación al terminar el turno no recompila la extensión cuando cambian .cpp o .rs · sin revisar
  Por qué: Un build de godot-cpp puede tardar minutos y bloquearía el cierre del turno. El agente la llama cuando hace falta.
  Descartado: Compilar en verify_changed_scripts, como se hace con C#.

**Prueba:** tests/unit/test_native_build.gd (parser gcc/clang/rustc/MSVC, layouts, comandos, build real con scons+gcc y con cargo) y test_system_prompt (reglas solo con sistema de build): run_all 427 tests, 0 fallos en 4.7.2. --godot-agent-mcp-test en Xvfb: 0 fallas (build_extension fuera del tools/list compacto y listada en methods). De punta a punta contra una copia de godot-cpp-template (layout demo/): detectó el SConstruct desde demo/, compiló en 63 s y, con un error plantado, devolvió register_types.cpp línea 11 en 3,5 s.

**Notas:** En main desde 1e2acdc. core/native_build.gd: find_project mira la carpeta del proyecto, la de arriba y rust/ en cada una; SCons > CMake > Cargo. scons -C raíz target=…; cmake configura siempre (el target es una opción de configuración; -G Ninja solo la primera vez) y después --build; cargo build --manifest-path --message-format=short (--release con template_release). Timeout de 1200 s. Mensajes en inglés y sin color (LC_MESSAGES=C). Si falla sin errores de archivo (por ejemplo, del linker), devuelve las últimas 20 líneas. ~/.cargo/bin se agregó a las carpetas de CommandResolver. Las skills (godot-agent-plugins a11a5d4) dan por sentado el layout de godot-cpp-template con project/, que find_project cubre.

**Bloquea a:** Probar la extensión en un Godot headless descartable

**Relacionadas:** Skill de scaffolding de GDExtension

### Probar la extensión en un Godot headless descartable · Revisión

**Prioridad:** alta · **Tamaño:** M

Un segfault en código nativo mata el proceso que cargó el .so, y si ese proceso es el editor, también se cae la sesión del agente. La prueba tiene que correr en un Godot headless aparte (reusando lo de playtest/headless): carga la build, verifica que las clases aparecen en ClassDB, corre tests o playtest y devuelve el resultado, o el código de salida y el backtrace si crashea. Solo las builds que pasan se instalan en la ruta que lee el editor ("promover").

**Decisiones:**
- ! Sin paso de «promover» en m19-02: test_extension prueba la build donde la deja el SConstruct, y llevar la build probada al juego queda para una tarea aparte · sin revisar
  Por qué: La ruta que carga el editor la definen el SConstruct y el .gdextension, no el harness; moverla implica reescribir el build del usuario. El aislamiento real es que el proyecto de prueba (project/ o demo/) no sea el que tiene abierto el editor, y copiar el addon al juego es el paso «Package as an addon» de la skill.
  Descartado: Compilar a una carpeta de staging y copiar a bin/ solo si los tests pasan.
- ! test_extension pide permiso como correr el juego (grupo run), y el runner vive en el addon: se pasa por ruta absoluta, así que el proyecto de prueba no necesita el addon · sin revisar
  Por qué: Carga y ejecuta código del proyecto en un proceso aparte, como run_scene. Usa el mismo formato de tests que el runner de la skill gdextension-cpp.
  Descartado: El grupo shell, o exigir que el proyecto de prueba tenga copiado el extension_tests.gd de la skill.
- ! El backtrace de un crash solo muestra los frames de la extensión (resueltos con addr2line) y el backtrace de GDScript; los del motor y libc se cuentan en una línea · sin revisar
  Por qué: Son unos 20 frames por crash que no le dicen nada al agente y gastan contexto.
  Descartado: Mostrar el backtrace completo.

**Prueba:** tests/unit/test_native_test.gd (salida del runner, resumen de un crash, proyecto de prueba en los layouts de godot-cpp y gdext, .gdextension registrados y recargables, corrida real sin extensión → código 2): run_all 432 tests, 0 fallos en 4.7.2. --godot-agent-mcp-test en Xvfb: 0 fallas. De punta a punta contra una copia de godot-cpp-template compilada con debug_symbols=yes: un check que falla a propósito sale como ✗ con código 1; un método C++ que desreferencia null crashea solo el proceso de prueba (signal 11) y el frame queda resuelto a «ExampleClass::crash_now(int) const at src/example_class.cpp:15»; una clase que falta sale con código 2. También probó el import automático del proyecto de prueba.

**Notas:** Código en el worktree .claude/worktrees/m19-02, rama m19-02-extension-test, sin commitear. core/native_test.gd + native/extension_tests.gd (runner; mismo formato que el de la skill: PASS/FAIL/DONE y códigos de salida 0/1/2, y sin carpeta de tests solo chequea la carga). Detecta un crash por «handle_crash:»: el código de salida no sirve (134 con core dump). El import (--headless --import) solo corre si falta registrar un .gdextension, y nunca sobre el proyecto abierto en el editor. Pendiente aparte: llevar la build probada al juego (ver decisión).

**Bloquea a:** Llevar la extensión probada al juego

**Bloqueada por:** Build nativo con errores por archivo

**Relacionadas:** Supervisor del editor: rollback de builds que crashean y reinicios

### Supervisor del editor: rollback de builds que crashean y reinicios · Revisión

**Prioridad:** alta · **Tamaño:** L

Godot carga .godot/extension_list.cfg antes que cualquier plugin. Si una build crashea al cargar, el editor no abre, el addon no corre y el agente (que es hijo del editor) muere: desde adentro no se puede salir del loop. Además, a veces hay que reiniciar para cargar una versión nueva. La solución es un proceso chico fuera del editor (GDScript con godot --headless -s, para seguir 100 % GDScript) que lanza el editor y lo vigila. Guarda la última build buena antes de cargar una nueva, captura el backtrace de stderr y, si el editor murió al arrancar, vuelve a la build buena (o saca la entrada) y lo relanza. Al abrir, el addon retoma con session/load y le pasa al agente qué build crasheó y el backtrace. Los reinicios voluntarios usan EditorInterface.restart_editor(true) y pasan por el mismo camino. No es el harness standalone: el supervisor no sabe nada de ACP ni de MCP.

**Decisiones:**
- ! El supervisor lanza el editor sin pipes, con --log-file, y lo vigila por pid; corre con --path en .godot/agent_supervisor (sin project.godot), así no carga ninguna GDExtension · sin revisar
  Por qué: Si el editor escribiera a un pipe del supervisor y el supervisor muriera, el editor recibiría SIGPIPE y se caería. Con --log-file igual queda el backtrace del crash (probado).
  Descartado: Leer stdout y stderr del editor con execute_with_pipe, como AgentProcess.
- ! «Arranque bueno» quiere decir que el plugin marcó ready y el editor duró 30 s. Un crash antes de eso hace rollback a la última build buena; una extensión sin build buena se desactiva renombrando el .gdextension a .disabled. La build que crasheó queda como *.crashed. Después de 3 crashes en 5 minutos, el supervisor deja de relanzar. · sin revisar
  Por qué: Una extensión puede crashear al abrir una escena, apenas después de que cargan los plugins; los 30 s cubren eso sin tomar como buena una build que tira abajo el editor enseguida. Sin el tope, una falla que no viene de la extensión quedaría en loop.
  Descartado: Que la marca ready sola ya cuente como arranque bueno, o no desactivar nunca una extensión nueva.
- ! Después de un crash o de un reinicio, el plugin retoma la última sesión y le manda al agente un mensaje con lo que pasó y el backtrace, aunque «continuar la última sesión» esté apagado · sin revisar
  Por qué: Lo pide el criterio del hito: el agente sigue con el backtrace. El evento existe solo si hubo un crash bajo el supervisor o un reinicio pedido con restart_editor.
  Descartado: Mostrar solo un aviso con un botón «Contarle al agente».
- ! Para entrar al supervisor hay tres caminos: un aviso en el dock (solo en proyectos con SConstruct, CMakeLists.txt o Cargo.toml) con «Reiniciar bajo el supervisor» y «Copiar el comando», o restart_editor (supervise, por defecto true). Bajo el supervisor, cualquier reinicio del editor (Proyecto › Recargar, el updater) se vuelve un pedido al supervisor. · sin revisar
  Por qué: El reinicio propio de Godot lanzaría un editor que no es hijo del supervisor y se perdería la supervisión; el plugin cancela set_restart_on_exit al salir y escribe restart.json.
  Descartado: Una opción en Ajustes, o un lanzador de escritorio (.desktop o .cmd).

**Prueba:** tests/unit/test_editor_supervisor.gd: bibliotecas de los .gdextension, snapshot, cambios y rollback (.crashed y .disabled), backtrace del log, mensajes al agente, drivers que se repiten, y el supervisor de verdad con un editor falso en tres casos: crash al arrancar con rollback, reinicio pedido y corte después de 3 crashes. run_all: 440 tests, 0 fallos. --godot-agent-cycle-test y --godot-agent-mcp-test en Xvfb: PASS. De punta a punta con el editor real (Xvfb, opengl3) y una copia de godot-cpp-template con dos builds reales, una buena y otra que desreferencia null en initialize: (1) un editor sin supervisión hizo el handoff y el editor nuevo quedó supervisado; (2) a los 30 s estable, el supervisor guardó la build buena; (3) se instaló la build que crashea y EditorInterface.restart_editor pasó por el supervisor; (4) el editor crasheó al arrancar (signal 11), volvió la build buena (igual byte a byte), la que crasheó quedó como .crashed, el editor se reabrió y el plugin leyó los eventos (reinicio y startup_crash, con los frames de la extensión); (5) al cerrar normal, el supervisor terminó. Sin probar: que la sesión de un agente real se retome con el mensaje (sin agente en la prueba).

**Notas:** Código en el worktree .claude/worktrees/m19-03, rama m19-03-supervisor, sin commitear. supervisor/: editor_supervisor.gd (SceneTree headless), supervisor_state.gd (archivos en .godot/agent_supervisor), extension_snapshot.gd (good/, rollback), supervisor_client.gd (plugin), restart_guard.gd. Tres cosas que salieron probando: (a) OS.is_process_running solo sirve para procesos hijos, así que la vida del supervisor se mide con un latido en supervisor.json y la espera del editor viejo, con su closed.json; (b) Godot descarga los plugins (_exit_editor) antes de set_restart_on_exit, y el plugin no puede cancelar el reinicio: lo hace restart_guard, un nodo en la raíz que sale al finalizar el árbol; (c) OS.get_cmdline_args no trae --rendering-driver ni --display-driver, así que los drivers se repiten desde lo que está en uso. Límite conocido: el editor relanzado no recibe los otros flags originales (por ejemplo --single-window).

**Relacionadas:** Probar la extensión en un Godot headless descartable

### Skill de scaffolding de GDExtension · Revisión

**Prioridad:** media · **Tamaño:** M

Una skill en el repo de marketplace dannroda/godot-agent-plugins (no en este repo) con plantillas de godot-cpp y gdext fijadas a 4.7, el .gdextension con compatibility_minimum, el flujo de godot --dump-extension-api desde el binario abierto para que godot-cpp coincida con el editor, y el ciclo build → prueba headless → promover → reiniciar con supervisor.

**Prueba:** Revisado el commit 3286997 de godot-agent-plugins (gdextension 0.1.1): gdextension-cpp, gdextension-build y gdextension-debug explican cómo encontrar las tools (godot.methods / godot.run), el ciclo build_extension → test_extension → restart_editor y los archivos .crashed y .gdextension.disabled del supervisor, y sin las tools siguen con la shell. La otra sesión no corrió las tools desde la skill.

**Notas:** Las skills: a11a5d4 (versión inicial) y 3286997 (usan las tools de la v0.1.17), las dos en origin/main de godot-agent-plugins. Hay una diferencia entre los runners: sin carpeta de tests, el de test_extension solo comprueba la carga y sale con 0, mientras que el de la skill sale con 2 si no corrió ningún test. Se dejó así a propósito: test_extension también sirve para comprobar solo que una extensión carga.

**Relacionadas:** Build nativo con errores por archivo

### Llevar la extensión probada al juego · Revisión

**Prioridad:** media · **Tamaño:** S

m19-02 prueba la build en el proyecto de prueba de la extensión (project/ o demo/), pero el juego que el usuario tiene abierto la usa como addon (addons/<ext>/ con el .gdextension y bin/). Falta una tool, o un paso documentado, que copie el addon probado al juego solo si test_extension pasó, verifique con check_gdextension.py de la skill y le pida al usuario que reinicie el editor. Esto se cruza con el supervisor (m19-03): la build nueva entra al editor recién en ese reinicio.

**Decisiones:**
- ! install_extension no copia al juego: prepara en .godot/agent_supervisor/pending/ y los archivos entran en el reinicio (el supervisor antes de abrir el editor; sin supervisor, el plugin justo antes de reiniciar) · sin revisar
  Por qué: El editor abierto registra y carga un .gdextension nuevo al escanear, y recarga uno reloadable cuando cambia su biblioteca: copiar directo cargaba la build en el editor sin pasar por el reinicio ni por el rollback del supervisor. Entrar por rename deja intacta la biblioteca que el editor tiene mapeada.
  Descartado: Copiar directo con el aviso de reiniciar; dejar los archivos como *.pending dentro de addons/ (el FileSystem los muestra y podrían exportarse).
- ! install_extension vuelve a correr los tests de test_extension antes de instalar, en vez de recordar el último test que pasó · sin revisar
  Por qué: Garantiza que lo copiado es exactamente lo probado (una build en el medio cambiaría la biblioteca); cuesta lo que tarda la prueba, que corre en un Godot aparte.
  Descartado: Guardar el md5 de las bibliotecas cuando test_extension pasa y exigir que coincidan al instalar.
- ! La revisión del .gdextension es un port a GDScript de check_gdextension.py, y solo frena lo que impide que este editor la cargue; lo demás (falta la release, otras plataformas, debug/release cruzados) son avisos · sin revisar
  Por qué: El addon no puede depender de que la skill y python3 estén instalados. Con la regla de la skill, el godot-cpp-template real (solo template_debug de linux, lo que compila build_extension por defecto) no se instalaba: el script es para publicar, la instalación es para iterar.
  Descartado: Correr check_gdextension.py si está; tratar todo lo que marca el script como bloqueante.
- ! Qué se lleva: el .gdextension con las bibliotecas, íconos y dependencias que nombra (desde bin/), o la carpeta addons/<x>/ entera si el proyecto de prueba ya la tiene así; destino res://addons/<nombre>/ o donde el juego ya tiene ese .gdextension; rutas res:// reescritas · sin revisar
  Por qué: bin/ del template junta basura de build (.lib, .exp, .crashed); addons/<x>/ puede traer un plugin.cfg y scripts que son parte del addon. Es el paso «Package as an addon» de la skill gdextension-build.
  Descartado: Copiar siempre la carpeta entera del .gdextension.

**Prueba:** sm/m19-05-fix 2c619cb.
- run_all 4.7.2: 511 tests, 3936 checks, 0 fallos.
- 4.8-beta2: native_install (17 tests), editor_supervisor (12) y file_tools (2), 0 fallos.
- Xvfb 4.7.2: --godot-agent-pending-test (en y es) PASS: el aviso de falla, Reiniciar pasa por restart_editor(true), Descartar. --godot-agent-mcp-test PASS. --godot-agent-i18n-test es PASS (410 textos).
- Tests nuevos:
  - test_target_guard_variants: res:///, //, /.godot, \, .., C:, ocultas, raíz, mayúsculas con ignore_case, la misma lista que FileTools.
  - test_target_guard_symlinks: enlace al harness, afuera, y uno válido.
  - test_plan_addon_with_gdextension_in_a_subfolder.
  - test_nested_project_in_the_game_is_skipped.
  - test_pick_gdextension_by_folder_name.
  - test_check_uses_the_key_this_editor_loads (más etiquetas, empate, solo release).
  - test_failed_restage_keeps_the_previous_one.
  - test_apply_is_all_or_nothing (revierte, falla avisada una vez, project_info).
  - test_apply_validates_manifest_paths.
  - test_tool_says_what_a_crash_would_do.
  - test_editor_supervisor: test_rollback_restores_the_gdextension_text, test_nested_project_is_not_an_extension_of_the_game y test_real_wait_timeout_holds_the_pending_install.

**Notas:** Rama sm/m19-05 (worktree .claude/worktrees/m19-05), commit 26e8a18 desde 9501d7f, integrada en sm/next. Código: core/native_install.gd (plan, check, stage/apply_pending), tool install_extension en diagnostic_tools.gd (GROUP_PROJECT, extendida), supervisor _launch y plugin _restart_now aplican lo preparado, NATIVE_RULES y descripción de restart_editor la nombran.
Arreglo del hueco «lo preparado queda en pending/ sin que nadie lo sepa»: rama sm/m19-05-pending desde sm/next, commit f24729d. Aviso en el dock con Reiniciar y Descartar; godot.project_info lo nombra.
Arreglos de la revisión (#1-#7, #9-#14): rama sm/m19-05-fix desde sm/next 7ff2c6b (worktree .claude/worktrees/m19-05-fix), commit 2c619cb.
- #1: core/protected_paths.gd tiene la lista PROTECTED de file_tools (que ahora la usa), normalize_relative (res:///, //, \, .., unidades), write_error (protegidas, carpetas ocultas, mayúsculas en Windows/macOS, enlaces resueltos con resolve_links). Se valida el target, cada destino y las rutas del manifest (#13).
- #2/#3/#6/#12: target desde la carpeta del addon (gdext_sub). Si el juego ya la tiene, se reemplaza esa; con un target en otro lado, otra estructura o dos copias, error. _gdextension_files saltea subcarpetas con project.godot (también en el snapshot). pick_gdextension elige por nombre de carpeta y da error si hay ambigüedad. Todos los .gdextension del addon van reescritos (file.text); planned.gdextension es el elegido.
- #4: check(text, dir, root, has_feature) usa loaded_key (la clave con más etiquetas que son features, la primera en un empate, como find_extension_library).
- #5: el snapshot guarda el .gdextension; rollback lo restaura primero y relee sus bibliotecas (aunque falten en disco). Snapshot.restorable da full, libraries o none, y _crash_note de la tool no promete volver atrás si no hay a qué.
- #7: ACTION_PENDING_INSTALL_RESTART llama a restart_editor(true). plugin.restart_override es la costura para pending_check.
- #9: stage arma en pending.new/ y pending.json.new y cambia con .prev (el manifest sale primero y entra último).
- #10/#11: apply_pending es todo o nada: copia a .installing, rename con backup .old, deshace si algo falla; limpia .old y .installing viejos; last_install.json. take_install_failure da el aviso del dock una vez; pending_line lo dice en project_info hasta la próxima preparación o el descarte.
- #14: el supervisor marca _pending_blocked si el wait-pid vence sin CLOSED (log). Lo despeja el reinicio pedido por su editor. --wait-timeout es para los tests.
Límites: el caso Windows (DLL cargada, .old que no se puede borrar) sigue sin probarse en Windows. Las carpetas vacías que crea una instalación fallida quedan.

**Bloqueada por:** Probar la extensión en un Godot headless descartable

### ProtectedPaths: rutas absolutas y ciclos de enlaces · Revisión

**Prioridad:** baja · **Tamaño:** S · **Etiquetas:** `security`

De la revisión independiente de install_extension (m13-17-ed, 2026-11-10), sin riesgo hoy. (a) normalize_relative quita las barras iniciales: "/tmp/evil" pasa a res://tmp/evil y una ruta absoluta del propio proyecto a res://home/…; aceptar una ruta con "/" inicial solo si está bajo la raíz del proyecto (y convertirla), si no error. Ojo: file_tools comparte la función; revisar si «/x» = «res://x» es convención que algún agente usa. (b) Un ciclo de enlaces se acepta como target tras 16 saltos (después mkdir falla): rechazarlo con un error claro.

**Decisiones:**
- ! «/x» no es sinónimo de res://x en install_extension: una absoluta vale solo bajo la raíz del juego (se convierte); sin entrada de CHANGELOG · sin revisar
  Por qué: Ni file_tools (_normalize deja «/x» absoluta y _check_target la rechaza) ni los prompts o skills usan esa convención; solo install_extension la aceptaba vía normalize_relative. install_extension todavía no salió, así que no hay cambio visible para el usuario.
  Descartado: Mantener «/x» = res://x y rechazar solo absolutas de otro lado (ambiguo: /home/… del propio proyecto pasaba a res://home/…).

**Prueba:** run_all 4.7.2: 523 tests / 4128 checks, 0 fallos; native_install en 4.8-beta2: 17/178, 0 fallos. test_target_guard_variants (absolutas: /, /tmp/evil, /addons/godot_agent, otra carpeta y ../ afuera; la del juego se convierte; la raíz del juego es «root of the game»; mayúsculas Win/mac) y test_target_guard_symlinks (ciclo loop_a↔loop_b rechazado, resolve_links devuelve "").

**Notas:** f0b40f2 en sm/m19-06. normalize_relative(path, root, ignore_case): absoluta (barra o unidad) solo bajo root, convertida; sin root, error. resolve_links devuelve "" pasados MAX_LINK_HOPS (16) y write_error dice «goes through a loop of symbolic links». file_tools no usa normalize_relative y ya rechazaba «/x»: sin cambios. La comparación con root es textual (una absoluta que pase por un enlace a la raíz del juego no se reconoce).
