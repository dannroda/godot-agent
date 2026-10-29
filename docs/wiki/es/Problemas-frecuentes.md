# Problemas frecuentes

[Inicio](Inicio.md) · [English](../en/Troubleshooting.md)

Lo primero es mirar el **Agent Log**: el canal `proc` muestra el comando con el que arrancó el agente y sus errores, y `acp` muestra los mensajes del protocolo.

## El agente no arranca

- **"Command '…' not found"** (el error del proceso, en inglés): el editor lanzado desde el escritorio no hereda el PATH de tu shell (fnm, nvm, volta…). El harness busca además en las carpetas habituales (`~/.local/bin`, `~/.nvm/…`, `/usr/local/bin`, `/opt/homebrew/bin`…). Si tu `npx` está en otro lado, poné su ruta absoluta en el comando del perfil.
- **"El agente pide autenticarse"**: usá los botones de login del aviso (ver [Primeros pasos](Primeros-pasos.md#2-abrir-una-sesión)), o iniciá sesión con `claude` en una terminal y tocá **Reintentar**.
- **El primer arranque tarda**: `npx` está descargando el adapter.

## El agente corre otra versión de Godot

El agente recibe la ruta del binario del editor abierto en `$GODOT`, en sus instrucciones y en `project_info`, y un shim `godot` va primero en su PATH. Si aun así usa otro, recordáselo: "usá $GODOT".

## "Límite del plan alcanzado"

Llegaste al límite de la ventana de tu plan. Esperá el reinicio (la cuenta regresiva dice cuándo), o usá **Cambiar de cuenta** en la pantalla One-shot durante un One-shot (ver [One-shot → cambiar de cuenta](One-shot.md#cambiar-de-cuenta)). Fuera del One-shot, iniciá sesión con otra cuenta y abrí una sesión nueva o retomala desde **Historial**.

## Una escena no se actualizó después de que el agente la cambió

Las escenas abiertas sin cambios sin guardar se recargan solas. Una escena con cambios sin guardar nunca se pisa: en su lugar aparece un aviso con **Recargar escena**.

## Los anillos de cuota están grises

Claude Code informa la cuota del plan con el primer mensaje de cada sesión, así que una sesión nueva muestra los anillos grises hasta que mandás algo. Lo que se manda desde Remote Control no la informa al dock: esos turnos no pasan por ACP. Otros agentes pueden no informarla nunca. El harness nunca la estima, así que sin ese dato el One-shot no pausa por cuota.

## Limitaciones por versión de Godot

| Versión | Qué pasa | Cómo lo maneja el addon |
|---|---|---|
| 4.7 | `EditorDock` existe, pero la main screen como dock llega en 4.8. | Dock y panel con `EditorDock`; la main screen con la API vieja. |
| 4.8 (betas) | `_has_main_screen()` deja un `EditorDock` huérfano al deshabilitar, y cerrar el editor con la pantalla One-shot activa da un error de foco. | Main screen con `add_dock`; antes de cerrar, el editor pasa a la pantalla 2D. |

Quedan dos rastros conocidos e inofensivos en los exports: rutas del addon en `uid_cache.bin` y el plugin en la lista de plugins habilitados de `project.binary`.

## Reportar un problema

Incluí las líneas relevantes del **Agent Log**, tu versión de Godot y el agente (y su versión).
