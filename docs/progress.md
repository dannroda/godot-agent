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
- **Todavía no se puede iniciar una sesión**: M0 es solo el esqueleto. Lanzar el agente y conversar llega en M1.
- Reportar a Godot los dos problemas de 4.8-beta1 que el addon esquiva (tarea en M7).
- `project.godot` del anfitrión quedó con `config/features=("4.4")` porque lo abrió el 4.4.1. Sirve para marcar el mínimo; el 4.8 lo actualiza si se guarda desde ahí.
- Repo git inicializado (rama `main`, sin commits todavía). `.gitignore` excluye `.godot/`; los `.uid` se versionan.
