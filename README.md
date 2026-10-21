# Godot Agent Harness

Addon de editor para Godot 4 que conecta un agente de código (Claude Code, Gemini CLI, Codex o cualquier agente que hable [ACP](https://agentclientprotocol.com)) con el editor. El agente conversa en un dock y puede ver y tocar el proyecto con las herramientas del editor:
- leer escenas;
- editar nodos con undo;
- correr el juego y capturar frames;
- leer los errores.

Tiene cuatro modos: Preguntar, Revisar, Construir y One-shot.

- 100 % GDScript con tipos estáticos, sin GDExtension ni dependencias.
- Solo vive en el editor: nada del addon llega a un juego exportado.
- El harness nunca hace merge ni push, y no guarda claves.

> Estado: hitos M0–M7 de [`GODOT_AGENT_HARNESS_SPEC.md`](GODOT_AGENT_HARNESS_SPEC.md). El completado inline en el Script Editor (M8) todavía no está. El avance y cómo se verificó cada parte están en [`docs/progress.md`](docs/progress.md); las decisiones de diseño, en [`docs/decisions.md`](docs/decisions.md).

## Requisitos

- **Godot 4.4 o más nuevo.** Se prueba en 4.4.1, 4.7.2 y 4.8-beta1.
- **Un agente ACP.** Para Claude Code:
  - Node.js con `npx`; el perfil por defecto corre `npx -y @agentclientprotocol/claude-agent-acp`;
  - una sesión de Claude Code ya iniciada (`claude` en una terminal), o una API key en una variable de entorno (ver [Perfiles](#perfiles-de-agentes)).
- **git**, solo para los checkpoints del modo One-shot.
- Linux, macOS o Windows. El desarrollo es en Linux; no hay comandos atados a un shell.

## Instalación

1. Copiá `addons/godot_agent/` a la carpeta `addons/` de tu proyecto. No copies `addons/godot_agent_dev/`: es el plugin de pruebas del repo.
2. **Proyecto → Configuración del proyecto → Plugins**: habilitá **Godot Agent Harness**.
3. Aparecen tres superficies:
   - el dock **Agent** (a la derecha);
   - el panel inferior **Agent Log**;
   - la pantalla **Agent** (arriba, junto a 2D/3D/Script), que es la del One-shot.
4. En el dock, **Iniciar sesión**. Con Claude Code, la primera vez `npx` descarga el adapter.

El addon no escribe nada en `project.godot`. La única excepción es un autoload de playtest temporal: se agrega solo cuando el harness corre el juego y se quita en cuanto el juego arranca.

## Uso

### El dock

- **Header**: perfil de agente, título de la sesión, **Historial**, **Nueva sesión** y **Settings**.
- **Modos**: Preguntar · Revisar · Construir · One-shot.
- **Conversación**: Markdown, tool calls agrupados, diffs, tarjetas de permiso y el plan del agente.
- **Composer**:
  - `@` menciona archivos del proyecto y `/` lista los comandos del agente;
  - **+ contexto** adjunta la escena abierta, la selección o una captura del viewport;
  - también hay selector de modelo y medidor de contexto.
- **Cuota del plan**: si el agente la informa, aparece debajo del estado (ver [Cuota](#cuota-del-plan)).

### Modos

| Modo | Qué hace el agente |
|---|---|
| **Preguntar** | Responde sobre el proyecto. Puede leer, no puede editar ni correr nada. |
| **Revisar** | Revisa escenas y scripts y devuelve hallazgos (bug, orden, rendimiento, estilo). Las marcas aparecen en el Script Editor, con "Aplicar arreglo", "Preguntar" y "Descartar". La revisión se puede exportar a `CLAUDE.md`. |
| **Construir** | Edita escenas y scripts y corre el juego, pidiendo permiso según la matriz. |
| **One-shot** | Persigue un objetivo con presupuestos, checkpoints git y playtests, en la pantalla Agent (ver [One-shot](#one-shot)). |

Cambiar de modo cambia también el modo del agente, si lo publica: Preguntar y Revisar usan `plan`, y Construir y One-shot usan `default`.

### Permisos

Cada acción cae en un grupo, y cada grupo tiene una decisión por modo: **sí**, **preguntar** o **no**. "Preguntar" muestra una tarjeta en el chat. Si nadie contesta en 5 minutos (configurable), se deniega. Valores de la spec:

| Grupo | Preguntar | Revisar | Construir | One-shot |
|---|---|---|---|---|
| Lectura | sí | sí | sí | sí |
| Diagnóstico | sí | sí | sí | sí |
| Editar escenas | no | no | preguntar | sí |
| Editar archivos | no | no | preguntar | sí |
| Ejecutar el juego | no | preguntar | preguntar | sí |
| Shell / comandos | no | no | preguntar | preguntar |
| Project settings, export y addons | no | no | preguntar | preguntar |

La matriz se cambia en **Settings → Permisos**. Se guarda solo lo que difiere de la spec.

### Herramientas del editor (MCP)

El addon levanta un servidor MCP en `127.0.0.1` (nunca en otra interfaz), con un token Bearer que cambia en cada arranque, y se lo pasa al agente al abrir la sesión. Si el agente no soporta MCP por HTTP, usa un puente stdio que corre con el mismo binario de Godot. Las herramientas:

| Grupo | Herramientas |
|---|---|
| Lectura | `project_info`, `list_files`, `scene_tree`, `get_node`, `editor_state` |
| Diagnóstico | `get_errors`, `validate_scripts`, `capture_editor_viewport` |
| Editar escenas | `add_node`, `set_properties`, `remove_node`, `reparent_node`, `rename_node`, `connect_signal`, `instantiate_scene`, `open_scene`, `save_scene` |
| Editar archivos | `create_scene`, `attach_script` |
| Ejecutar el juego | `run_scene`, `stop_scene`, `capture_game_frame` |

- Cada edición de escena es un paso de undo del editor. La tarjeta del tool call tiene **↶ undo** mientras nadie haya tocado la escena después.
- Las ediciones de archivos del agente (`fs/*` de ACP) pasan por el editor: si tenés un script abierto con cambios sin guardar, no se pisan, y aparece un aviso de conflicto con el diff.
- **Settings → Servidor MCP**:
  - puerto fijo (por defecto, uno libre al azar);
  - **Regenerar token**;
  - límite de caracteres por resultado y lado máximo de las capturas;
  - carpetas fuera del proyecto que el agente puede leer y escribir.

### One-shot

1. Elegí **One-shot** en el dock: se abre la pantalla **Agent**.
2. Escribí el objetivo (por ejemplo "Pong de 2 jugadores con puntaje"), revisá los presupuestos y si querés checkpoints, y tocá **Iniciar One-shot**. Si hay cambios sin commitear, el harness pregunta antes. Esos cambios quedan en un commit "WIP" en la rama del agente, nunca en la tuya.
3. El agente arma un plan, trabaja y verifica con playtests (`run_scene` + `capture_game_frame`). Reporta checks en `pass`, `fail` o `pending`. La pantalla muestra:
   - el plan, que se puede editar;
   - la actividad, con "Guiar al agente";
   - la última captura, las verificaciones y los checkpoints.
4. **Checkpoints**: cada tarea del plan (o cada playtest, si el agente no informa un plan) es un commit `cpN` en la rama `agent/<fecha>`. **Volver acá** deja el proyecto exactamente como en ese checkpoint y pausa el run; **Retomar** sigue desde ahí.
5. **Presupuestos** de tiempo, tokens y playtests: avisa al 80 % y, al 100 %, pide el reporte final y termina.
6. Al final:
   - **Revisar cambios** lista los archivos; con doble clic se ve el diff contra el inicio.
   - **Aceptar todo** hace un commit final en `agent/<fecha>`. El merge lo hacés vos.

Nunca corras un One-shot sobre un repo donde no quieras ramas nuevas. Para probar, `tests/make_sandbox.sh <carpeta>` arma un proyecto aparte.

### Cuota del plan

Si el agente informa la cuota de su plan (Claude Code lo hace: ver D22 en las decisiones), el dock muestra la ventana actual y la semanal, con la hora de reinicio.
- **Aviso** al 75 %.
- **Pausa del One-shot** al 90 %, en el próximo checkpoint, sin cortar una tarea a la mitad.
- **Limitado**: cuando el agente informa que se alcanzó el límite, el envío queda bloqueado con una cuenta regresiva. Al reiniciarse la ventana, el One-shot retoma solo o espera confirmación.

Todo se configura en **Settings → One-shot y cuota**. El harness no estima la cuota con tokens, no consulta endpoints no documentados y no lee archivos ni credenciales del agente. Si el agente no la informa, el medidor lo dice y no inventa un número.

### Historial

Cada sesión se guarda en `user://godot_agent/sessions/` (la carpeta de datos del editor para este proyecto). Se guarda una vez por turno, sin capturas y con los resultados largos recortados. **Historial** en el dock lista las sesiones de este proyecto.
- Si el agente soporta `session/load` (Claude Code sí), la sesión se reanuda de verdad: el agente recupera su contexto.
- Si no, la conversación se ve en modo solo lectura, y escribir abre una sesión nueva.

### Completado inline

Todavía no está: llega en el hito M8 de la spec.

## Perfiles de agentes

**Settings → Agentes**: agregar, editar, quitar y marcar el predeterminado. Cada perfil tiene un comando, sus argumentos (uno por línea) y variables de entorno.

- **Claves**: en el entorno, `NOMBRE=$VARIABLE` toma el valor de `VARIABLE` del entorno del editor al lanzar el agente. Settings no acepta un valor literal en variables con nombre de secreto (`*KEY*`, `*TOKEN*`, `*SECRET*`, `*PASSWORD*`), y el log del harness enmascara el token MCP. Ejemplo: `ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY`.
- Perfiles incluidos:
  - Claude Code (`npx -y @agentclientprotocol/claude-agent-acp`);
  - Gemini CLI (`gemini`; agregá el argumento que tu versión use para ACP, por ejemplo `--experimental-acp`);
  - Codex, sin comando: configuralo con el adapter ACP que uses.

## Settings: dónde se guarda cada cosa

| Qué | Dónde | Alcance |
|---|---|---|
| Perfiles, puerto MCP, cuota, color de acento, ubicación del dock | `EditorSettings`, prefijo `godot_agent/` | tu usuario, todos los proyectos |
| Permisos, presupuestos, checkpoints, límites de las tools, carpetas extra | `res://addons/godot_agent/config/project_config.tres` | el proyecto (se puede commitear) |
| Historial de sesiones | `user://godot_agent/sessions/` | tu usuario, este proyecto |

El puerto, el color y la ubicación del dock se aplican al reabrir el editor. Desde 4.8 el editor recuerda dónde dejaste el dock, así que la ubicación de Settings es solo la inicial.

## Export

El addon no llega a un juego exportado: un export plugin saltea todo `addons/godot_agent/` y quita el autoload de playtest. Como red de seguridad, por si exportás con el plugin deshabilitado, agregá `addons/godot_agent/*` al **filtro de exclusión** de cada preset (diálogo de Exportar, pestaña Recursos). **Settings → Export** muestra qué presets no lo tienen y lo agrega, previa confirmación. Como el editor tiene los presets en memoria, reinicialo después de usar ese botón.

Quedan dos rastros conocidos e inofensivos: rutas del addon en `uid_cache.bin` y el plugin en la lista de plugins habilitados de `project.binary` (D8).

## Actualizar sin perder la config

La config del proyecto vive dentro de la carpeta del addon. Para actualizar:

1. Guardá `addons/godot_agent/config/project_config.tres`, si existe. Si editaste `config/system_prompt.md` o `config/quota_patterns.txt`, guardalos también.
2. Borrá `addons/godot_agent/` y copiá la versión nueva.
3. Volvé a poner esos archivos en `config/`.

Los settings de usuario (`EditorSettings`) y el historial (`user://`) no se tocan al reemplazar la carpeta.

## Limitaciones conocidas por versión

| Versión | Qué pasa | Cómo lo maneja el addon |
|---|---|---|
| 4.4.x | Cerrar los pipes de un proceso hijo cierra descriptores equivocados, incluido el stdin del editor (D11). | No cierra los pipes de un agente terminado hasta que se cierra el editor: quedan unos pocos descriptores por sesión. |
| 4.4.x | No existe `Logger`. | `get_errors` lee el panel Output, con los mensajes un poco demorados. |
| 4.4–4.6 | No existe `EditorDock`. | Usa la API vieja de docks y main screen (D9). |
| 4.7 | `EditorDock` existe, pero la main screen como dock llega en 4.8. | Dock y panel con `EditorDock`; main screen con la API vieja. |
| 4.8-beta1 | `_has_main_screen()` deja un `EditorDock` huérfano al deshabilitar, y cerrar el editor con la pantalla Agent activa da un error de foco. | Main screen con `add_dock`; antes de cerrar, pasa a la pantalla 2D (D9). |

## Desarrollo

```sh
G=/ruta/a/godot   # 4.4.1, 4.7.2 o 4.8
$G --headless --path . --import
$G --headless --path . --script tests/run_all.gd            # unitarios
$G --headless --path . --script tests/acp_session_check.gd  # ACP contra el agente falso
$G --headless --path . --script tests/oneshot_check.gd      # loop del One-shot
tests/run_in_xvfb.sh $G --godot-agent-cycle-test             # editor en Xvfb: habilitar/deshabilitar 5 veces sin huérfanos
```

`docs/progress.md` tiene la lista completa por hito, incluidas las pruebas con Claude Code real (gastan tokens). El tablero de tareas está en `compass/` ([`docs/tareas.md`](docs/tareas.md) es su export).
