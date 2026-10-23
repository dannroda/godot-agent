# Settings y perfiles

[Inicio](Inicio.md) · [English](../en/Settings.md)

**Settings** se abre desde el header del dock.

| Sección | Qué hay |
|---|---|
| **Agentes** | Perfiles de agentes (ver abajo). |
| **Completado** | [Completado inline](Completado-inline.md). |
| **Permisos** | La [matriz de permisos](Modos-y-permisos.md#permisos) por modo, el tiempo para contestar y las listas de comandos de shell del [modo Auto](Modos-y-permisos.md#modo-auto). |
| **Servidores MCP** | [Otros servidores MCP](#otros-servidores-mcp) para el agente; del servidor del addon: puerto, **Regenerar token**, límites de los resultados, lista de tools compacta, carpetas extra. |
| **One-shot y cuota** | Presupuestos por defecto, checkpoints, revisión del spec, repeticiones para los loops, vueltas de QA, criterios del juego (peso y mínimo), umbrales de aviso y pausa de la cuota, qué hacer cuando se reinicia la cuota. |
| **Interfaz** | Color de acento, ubicación del dock, idioma, [actualizaciones](#actualizar-el-addon). |
| **Export** | Revisa que cada preset de export excluya el addon. |

## Dónde se guarda cada cosa

| Qué | Dónde | Alcance |
|---|---|---|
| Perfiles de agentes, puerto MCP, servidores MCP de todos tus proyectos, cuota, color de acento, ubicación del dock, idioma, completado (incluidos los perfiles LLM, sin keys) | `EditorSettings`, prefijo `godot_agent/` | tu usuario, todos los proyectos |
| Permisos, servidores MCP del proyecto, presupuestos, checkpoints, umbral de loops, criterios, límites de las tools, carpetas extra, completado del proyecto | `res://addons/godot_agent/config/project_config.tres` | el proyecto (se puede commitear) |
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

## Otros servidores MCP

**Settings → Servidores MCP** lista servidores MCP de otros programas (Blender, una base de datos, un servicio web…). El addon se los pasa al agente al abrir la sesión, junto a su servidor `godot`, así que sirven con cualquier agente ACP. Los cambios valen desde la próxima sesión.

- **+ Agregar servidor**: un nombre (letras, números, `-` y `_`), dónde se guarda, y un comando con argumentos y entorno (stdio) o una URL con headers (HTTP; solo con agentes que aceptan servidores HTTP; si no, queda afuera con un aviso).
- **Guardado en**: *Este proyecto* va a `project_config.tres` (se puede commitear); *Todos mis proyectos* va a `EditorSettings`. Si los dos tienen un servidor con el mismo nombre, gana el del proyecto.
- **Claves**: en argumentos, entorno y headers, `$VARIABLE` o `${VARIABLE}` toma el valor del entorno del editor al abrir la sesión, por ejemplo `Authorization: Bearer $SENTRY_TOKEN`. Los valores con nombre de secreto tienen que usar una variable, y el Agent Log tapa los valores resueltos.
- **Importar .mcp.json** agrega los servidores del `.mcp.json` del proyecto que todavía no están en la lista.
- La casilla apaga un servidor sin quitarlo.

Claude Code además carga los servidores de su propia configuración (`claude mcp add`, `.mcp.json`, `~/.claude.json`). Escribí `/mcp` en el chat para ver su estado, reconectarlos o apagarlos.

Las tools de cada servidor piden permiso hasta que las permitas: ver [Servidores MCP de otros programas](Modos-y-permisos.md#servidores-mcp-de-otros-programas).

## Extensiones

El botón **Extensiones** del header del dock (al lado de Settings) abre una ventana con los plugins y marketplaces de Claude Code y todos los servidores MCP que ve el agente. Los cambios se aplican al toque por el CLI de Claude Code (`claude`), con el entorno del perfil del agente (por ejemplo `CLAUDE_CONFIG_DIR`). Si `claude` no está en el `PATH`, la ventana usa el que baja el adaptador ACP con npx.

- **Plugins**: los instalados con un interruptor, **Actualizar** y **Desinstalar**, su alcance y los servidores MCP que trae cada uno (con el color de su estado); abajo, los disponibles de tus marketplaces, primero los más instalados, con buscador e **Instalar** (en el alcance elegido arriba: usuario, proyecto o local). Si un plugin necesita correr un comando de su marketplace para instalarse, la ventana muestra el comando y pregunta antes.
- **Marketplaces**: agregar uno (un `dueño/repo` de GitHub, una URL o una carpeta), actualizarlo o quitarlo.
- **Servidores MCP**: los del addon de [Otros servidores MCP](#otros-servidores-mcp) y los que carga Claude Code (usuario, `.mcp.json` del proyecto, local, claude.ai y plugins), cada uno con su estado: conectado, falta autenticar, falló, falta aprobarlo, sin configurar. **Autenticar** corre `claude mcp login`, que abre el navegador. En una sesión, `/mcp` en el chat reconecta o apaga un servidor.

Los plugins se cargan al abrir la sesión: después de un cambio, la ventana ofrece **Nueva sesión**. Los plugins y marketplaces son de Claude Code; con otro perfil de agente esas pestañas lo dicen.

## Export

Un export plugin saltea todo `addons/godot_agent/` y quita el autoload de playtest, así que el addon nunca llega a un juego exportado.

Como red de seguridad, por si exportás con el plugin deshabilitado, agregá `addons/godot_agent/*` al **filtro de exclusión** de cada preset (diálogo de Exportar, pestaña Recursos). **Settings → Export** muestra qué presets no lo tienen y lo agrega, previa confirmación. Reiniciá el editor después de usar ese botón, porque el editor tiene los presets en memoria.

## Actualizar el addon

Al abrir el editor (como mucho una vez por día), el addon mira los [releases](https://github.com/dannroda/godot-agent/releases) de GitHub. Si hay una versión más nueva, aparece un aviso arriba del dock:

- **Novedades**: las notas del release.
- **Actualizar**: después de confirmar, baja el release, comprueba que el zip sea esa versión, guarda las escenas abiertas, cierra la sesión del agente, reemplaza `addons/godot_agent/` y reinicia el editor.
- **Después**: oculta el aviso de esa versión.

**Settings → Interfaz → Actualizaciones** tiene **Buscar ahora** y apaga la búsqueda al abrir el editor.

La actualización conserva `config/project_config.tres` (la config del proyecto). Si editaste `config/system_prompt.md` o `config/quota_patterns.txt` y la versión nueva los cambia, tu copia se guarda en `user://godot_agent/update/backup-<versión anterior>/` antes de reemplazarla (el panel Salida dice dónde). Los archivos que agregaste a la carpeta del addon y que no son código quedan. Los settings de usuario (`EditorSettings`) y el historial (`user://`) no se tocan.

Si `addons/godot_agent` es un link a un clon del repo, o está `addons/godot_agent_dev/` al lado, el addon es una copia de desarrollo: no se actualiza solo, actualizalo con git.

Para actualizar a mano: guardá `config/project_config.tres` y los archivos de `config/` que editaste, borrá `addons/godot_agent/`, descomprimí la versión nueva y volvé a poner esos archivos. La versión se ve en **Configuración del proyecto → Plugins**.
