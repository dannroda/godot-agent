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

- Permisos, `fs/*` y la sincronización con el editor llegan en M2. Mientras tanto, cuando Claude pide permiso para editar, el harness responde -32601 y el agente lo toma como rechazo.
- Historial de sesiones y Settings completos: M7.
