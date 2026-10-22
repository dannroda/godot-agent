# Settings y perfiles

[Inicio](Inicio.md) · [English](../en/Settings.md)

**Settings** se abre desde el header del dock.

| Sección | Qué hay |
|---|---|
| **Agentes** | Perfiles de agentes (ver abajo). |
| **Completado** | [Completado inline](Completado-inline.md). |
| **Permisos** | La [matriz de permisos](Modos-y-permisos.md#permisos) por modo, y el tiempo para contestar. |
| **Servidor MCP** | Puerto, **Regenerar token**, límites de los resultados, carpetas extra. |
| **One-shot y cuota** | Presupuestos por defecto, checkpoints, revisión del spec, repeticiones para los loops, criterios del juego (peso y mínimo), umbrales de aviso y pausa de la cuota, qué hacer cuando se reinicia la cuota. |
| **Interfaz** | Color de acento, ubicación del dock, idioma. |
| **Export** | Revisa que cada preset de export excluya el addon. |

## Dónde se guarda cada cosa

| Qué | Dónde | Alcance |
|---|---|---|
| Perfiles de agentes, puerto MCP, cuota, color de acento, ubicación del dock, idioma, completado (incluidos los perfiles LLM, sin keys) | `EditorSettings`, prefijo `godot_agent/` | tu usuario, todos los proyectos |
| Permisos, presupuestos, checkpoints, umbral de loops, criterios, límites de las tools, carpetas extra, completado del proyecto | `res://addons/godot_agent/config/project_config.tres` | el proyecto (se puede commitear) |
| Historial de sesiones | `user://godot_agent/sessions/` | tu usuario, este proyecto |
| Runs del One-shot (estado, última captura, informes; los últimos 20) | `user://godot_agent/oneshot/` | tu usuario, este proyecto |
| Spec, progreso y QA de cada run | `.godot_agent/oneshot/<id>/` en el proyecto | el proyecto (viaja en la rama del agente) |

El puerto, el color de acento, la ubicación del dock y el idioma se aplican al reabrir el editor. Desde Godot 4.8 el editor recuerda dónde dejaste el dock, así que el setting es solo la ubicación inicial.

## Perfiles de agentes

**Settings → Agentes**: agregar, editar, quitar y marcar el predeterminado. Cada perfil tiene un comando, sus argumentos (uno por línea) y variables de entorno.

- **Claves**: en el entorno, `NOMBRE=$VARIABLE` toma el valor de `VARIABLE` del entorno del editor al lanzar el agente. Settings no acepta un valor literal en variables con nombre de secreto (`*KEY*`, `*TOKEN*`, `*SECRET*`, `*PASSWORD*`). Ejemplo: `ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY`.
- Perfiles incluidos:
  - **Claude Code**: `npx -y @agentclientprotocol/claude-agent-acp`;
  - **Gemini CLI**: `gemini`; agregá el argumento que tu versión use para ACP, por ejemplo `--experimental-acp`;
  - **Codex**: sin comando; configuralo con el adapter ACP que uses.
- El agente siempre recibe `GODOT`/`GODOT_BIN` con el binario del editor; un perfil puede pisarlas.

## Export

Un export plugin saltea todo `addons/godot_agent/` y quita el autoload de playtest, así que el addon nunca llega a un juego exportado.

Como red de seguridad, por si exportás con el plugin deshabilitado, agregá `addons/godot_agent/*` al **filtro de exclusión** de cada preset (diálogo de Exportar, pestaña Recursos). **Settings → Export** muestra qué presets no lo tienen y lo agrega, previa confirmación. Reiniciá el editor después de usar ese botón, porque el editor tiene los presets en memoria.

## Actualizar el addon

La config del proyecto vive dentro de la carpeta del addon. Para actualizar:

1. Guardá `addons/godot_agent/config/project_config.tres` si existe, y `config/system_prompt.md` o `config/quota_patterns.txt` si los editaste.
2. Borrá `addons/godot_agent/` y copiá la versión nueva.
3. Volvé a poner esos archivos en `config/`.

Los settings de usuario (`EditorSettings`) y el historial (`user://`) no se tocan al reemplazar la carpeta.
