# Problemas frecuentes

[Inicio](Inicio.md) · [English](../en/Troubleshooting.md)

Lo primero es mirar el **Agent Log**: el canal `proc` muestra el comando con el que arrancó el agente y sus errores, y `acp` muestra los mensajes del protocolo.

## El agente no arranca

- **"Command '…' not found"** (el error del proceso, en inglés): el editor lanzado desde el escritorio no hereda el PATH de tu shell (fnm, nvm, volta…). El harness busca además en las carpetas habituales (`~/.local/bin`, `~/.nvm/…`, `/usr/local/bin`, `/opt/homebrew/bin`…). Si tu `npx` está en otro lado, poné su ruta absoluta en el comando del perfil.
- **"El agente pide autenticarse"**: usá los botones de login del aviso (ver [Primeros pasos](Primeros-pasos.md#2-abrir-una-sesión)), o iniciá sesión con `claude` en una terminal y tocá **Reintentar**.
- **El primer arranque tarda**: `npx` está descargando el adapter. Mientras tanto, la línea de arriba del composer dice **Conectando…**, y a los pocos segundos que la primera vez puede tardar un minuto.

## El agente corre otra versión de Godot

El agente recibe la ruta del binario del editor abierto en `$GODOT`, en sus instrucciones y en `project_info`, y un shim `godot` va primero en su PATH. Si aun así usa otro, recordáselo: "usá $GODOT".

## "Límite del plan alcanzado"

Llegaste al límite de la ventana de tu plan. Esperá el reinicio (la cuenta regresiva dice cuándo), o usá **Cambiar de cuenta** en la pantalla One-shot durante un One-shot (ver [One-shot → cambiar de cuenta](One-shot.md#cambiar-de-cuenta)). Fuera del One-shot, iniciá sesión con otra cuenta y abrí una sesión nueva o retomala desde **Historial**.

## Una llamada `godot.*` falla con "The operation timed out"

Claude Code deja de esperar una tool HTTP a los 60 segundos sin respuesta. Una llamada que tarda más de 2 segundos (un `run_scene` o `profile_run` largo, un build o test de GDExtension, o cualquier llamada mientras su tarjeta de permiso te espera) ahora responde como un stream con progreso cada 10 segundos, así que llega hasta el final. Si igual ves el error:

- pusiste un límite total con `MCP_TOOL_TIMEOUT` o un `timeout` en el server: el progreso no lo reinicia, así que dejalo por encima de 120 segundos, el `run_scene` más largo;
- el cliente no pide progreso: recibe una respuesta común y vale su propio límite;
- la llamada pasó los 30 minutos: contesta con un error, y la tool puede seguir corriendo en el editor.

Ver [Herramientas del editor → Detalles](Herramientas-del-editor.md#detalles).

## El personaje se mueve solo, o el input del agente falla al azar

Godot lee todos los gamepads conectados a la computadora, aunque otra ventana tenga el foco, así que un stick torcido o con drift deja apretadas las acciones de las flechas: el personaje camina, el foco de la UI salta a otro control y un campo de texto que tomó el foco no recibe lo que se tipea. Los juegos que lanza el agente (`run_scene`, `profile_run`, las regresiones, `regression_cli.gd`) ignoran los gamepads reales; los eventos de gamepad que manda el agente siguen andando. Para jugar a la par con el tuyo en un run que lanza el agente, pedile que pase `real_gamepads: true`. Los juegos que corrés con F5/F6 siguen leyendo tus gamepads: desconectá o recalibrá el que tiene drift.

## Una escena no se actualizó después de que el agente la cambió

Las escenas abiertas sin cambios sin guardar se recargan solas. Una escena con cambios sin guardar nunca se pisa: en su lugar aparece un aviso con **Recargar escena**.

## Los anillos de cuota están grises

Claude Code informa la cuota del plan con el primer mensaje de cada sesión, así que una sesión nueva muestra los anillos grises hasta que mandás algo. Lo que se manda desde Remote Control no la informa al dock: esos turnos no pasan por ACP. Otros agentes pueden no informarla nunca. El harness nunca la estima, así que sin ese dato el One-shot no pausa por cuota.

## Apareció una carpeta `skills/system/` en el proyecto

Antigravity (antigravity-acp) escribe su propia skill de `run_workflow` en `skills/system/run-workflow/SKILL.md` en la carpeta del proyecto cada vez que se abre una sesión, antes de que mandes nada. El adapter no tiene ninguna opción para dejarla en otro lado, así que podés borrarla, pero vuelve. El dock te avisa la primera vez en cada proyecto. Sumá `skills/system/` a tu `.gitignore` para no commitearla. Godot no la exporta: no es un recurso.

## Limitaciones por versión de Godot

| Versión | Qué pasa | Cómo lo maneja el addon |
|---|---|---|
| 4.7 | `EditorDock` existe, pero la main screen como dock llega en 4.8. | Dock y panel con `EditorDock`; la main screen con la API vieja. |
| 4.7.2 | El guardado con vista previa (Ctrl+S) puede imprimir un error del motor (`p_I->data != this` en `list.h`); en un proyecto sin el addon salió en cada guardado. En sesiones donde un agente estaba cambiando el proyecto, el editor a veces se cayó un momento después de guardar; sin el addon esa caída nunca se vio, y que venga de este error es probable, pero no está confirmado. | Los guardados del propio addon (`save_scene` y el guardado antes de actualizar) no usan la vista previa. Ctrl+S es del editor: el addon no lo puede cambiar. 4.8-beta2 y 4.8-beta3 siguen imprimiendo el error; 4.8-beta2 no se cayó en 12 corridas. |
| 4.8 (betas) | `_has_main_screen()` deja un `EditorDock` huérfano al deshabilitar, y cerrar el editor con la pantalla One-shot activa da un error de foco. | Main screen con `add_dock`; antes de cerrar, el editor pasa a la pantalla 2D. |

Quedan dos rastros conocidos e inofensivos en los exports: rutas del addon en `uid_cache.bin` y el plugin en la lista de plugins habilitados de `project.binary`.

## Reportar un problema

Incluí las líneas relevantes del **Agent Log**, tu versión de Godot y el agente (y su versión).
