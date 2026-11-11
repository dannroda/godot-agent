# Settings y perfiles

[Inicio](Inicio.md) · [English](../en/Settings.md)

**Settings** se abre desde el menú **⋯** del header del dock.

| Sección | Qué hay |
|---|---|
| **Agentes** | Perfiles de agentes (ver abajo). |
| **Completado** | [Completado inline](Completado-inline.md). |
| **Permisos** | La [matriz de permisos](Modos-y-permisos.md#permisos) por modo, el tiempo para contestar y las listas de comandos de shell del [modo Auto](Modos-y-permisos.md#modo-auto). |
| **Servidores MCP** | [Otros servidores MCP](#otros-servidores-mcp) para el agente; del servidor del addon: puerto, **Regenerar token**, límites de los resultados, lista de tools compacta, verificación de scripts y checks del proyecto al terminar cada turno, snapshot del proyecto en cada turno, carpetas extra. |
| **One-shot** | Los valores iniciales de cada One-shot (presupuestos, checkpoints, revisión del spec), repeticiones para los loops, vueltas de QA, criterios del juego (peso y mínimo). |
| **Cuota del plan** | Umbrales de aviso y pausa de la cuota, qué hacer cuando se reinicia la cuota. |
| **Interfaz** | Color de acento, ubicación del dock, idioma, [actualizaciones](#actualizar-el-addon). |
| **Export** | Revisa que cada preset de export excluya el addon. |

## Dónde se guarda cada cosa

| Qué | Dónde | Alcance |
|---|---|---|
| Perfiles de agentes, puerto MCP, servidores MCP de todos tus proyectos, cuota, color de acento, ubicación del dock, idioma, completado (incluidos los perfiles LLM, sin keys) | `EditorSettings`, prefijo `godot_agent/` (las listas, como perfiles y servers, son arrays de diccionarios; hasta 0.1.15 eran texto JSON y se convierten al cargar) | tu usuario, todos los proyectos |
| Permisos, servidores MCP del proyecto, presupuestos, checkpoints, umbral de loops, criterios, límites de las tools, carpetas extra, completado del proyecto | `res://addons/godot_agent/config/project_config.tres` | el proyecto (se puede commitear) |
| Historial de sesiones | `user://godot_agent/sessions/` | tu usuario, este proyecto |
| Runs del One-shot (estado, última captura, informes; los últimos 20) | `user://godot_agent/oneshot/` | tu usuario, este proyecto |
| Spec, progreso y QA de cada run | `.godot_agent/oneshot/<id>/` en el proyecto | el proyecto (viaja en la rama del agente) |

El puerto, el color de acento, la ubicación del dock y el idioma se aplican al reabrir el editor. Desde Godot 4.8 el editor recuerda dónde dejaste el dock, así que el setting es solo la ubicación inicial.

## Perfiles de agentes

**Settings → Agentes**: agregar, editar, quitar y marcar el predeterminado. Cada perfil tiene un comando, sus argumentos (uno por línea) y variables de entorno.

- **Claves**: en el entorno, `NOMBRE=$VARIABLE` toma el valor de `VARIABLE` del entorno del editor al lanzar el agente. Settings no acepta un valor literal en variables con nombre de secreto (`*KEY*`, `*TOKEN*`, `*SECRET*`, `*PASSWORD*`). Ejemplo: `ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY`.
- No viene ningún agente preconfigurado. Sin ninguno, el dock y esta página sugieren **Claude Code** (`npx -y @agentclientprotocol/claude-agent-acp`), **Codex** y **Google Antigravity** (estos dos del registro de ACP, que da el comando para tu plataforma). Codex y Antigravity todavía no se verificaron con el harness.
- El agente siempre recibe `GODOT`/`GODOT_BIN` con el binario del editor; un perfil puede pisarlas.
- **Modelo por modo**: los modelos recordados para cada modo del harness, elegidos en el composer; **Olvidar** hace que ese modo deje de cambiar el modelo. Ver [Modos y permisos](Modos-y-permisos.md#un-modelo-para-cada-modo).
- **Una cuenta por pestaña**: el chip del agente arriba de cada pestaña del dock elige el agente de esa pestaña y su cuenta. Una cuenta es la carpeta de configuración del agente, donde guarda su login, pasada en una variable del entorno: `CLAUDE_CONFIG_DIR` (Claude Code), `GEMINI_HOME` (Google Antigravity) o `CODEX_HOME` (Codex). Para otro agente, completá **Variable de la carpeta de cuentas** en su perfil. El menú lista la carpeta por defecto del agente y cada carpeta de `~/.<carpeta>-profiles/` (por ejemplo `~/.claude-profiles/trabajo` o `~/.gemini-profiles/trabajo`), con el email en las cuentas de Claude Code; **Otra carpeta…** agrega cualquier otra (una carpeta vacía es una cuenta nueva: la sesión te pide iniciar sesión). Así una pestaña trabaja con tu cuenta personal y otra con la del trabajo a la vez. Una pestaña nueva arranca con el último agente y la última cuenta que elegiste, y una sesión del historial se reabre con su cuenta. En el entorno de un perfil, `~/` es tu carpeta de usuario.

### Del registro de ACP

**+ Del registro de ACP…** lista los agentes del [registro de ACP](https://agentclientprotocol.com/registry) público que usan Zed y JetBrains (Claude, Codex, Gemini CLI, Copilot, Cursor, Google Antigravity, Goose, OpenCode…), con un filtro. **Agregar** crea el perfil: los agentes publicados en npm o PyPI corren con `npx` o `uvx`, y los demás bajan un programa para esta plataforma a la carpeta de datos del editor (`godot_agent/agents/<id>/<versión>/`), compartida por todos los proyectos. La descarga se verifica con el sha256 del registro; si el registro no lo trae, **Agregar** pide un segundo clic (**Agregar sin checksum**). Volver a agregar el mismo agente reemplaza su perfil por la versión nueva. Algunos agentes pesan mucho: el de Google Antigravity, unos 900 MB.

Google Antigravity pide iniciar sesión la primera vez (cuenta de Google, Gemini Enterprise, una API key de Gemini o Agent Platform); el dock ofrece los métodos que publica.

## Otros servidores MCP

**Settings → Servidores MCP** lista servidores MCP de otros programas (Blender, una base de datos, un servicio web…). El addon se los pasa al agente al abrir la sesión, junto a su servidor `godot`, así que sirven con cualquier agente ACP. Los cambios valen desde la próxima sesión.

- **+ Agregar servidor**: un nombre (letras, números, `-` y `_`), dónde se guarda, y un comando con argumentos y entorno (stdio) o una URL con headers (HTTP; solo con agentes que aceptan servidores HTTP; si no, queda afuera con un aviso).
- **Guardado en**: *Este proyecto* va a `project_config.tres` (se puede commitear); *Todos mis proyectos* va a `EditorSettings`. Si los dos tienen un servidor con el mismo nombre, gana el del proyecto.
- **Claves**: en argumentos, entorno y headers, `$VARIABLE` o `${VARIABLE}` toma el valor del entorno del editor al abrir la sesión, por ejemplo `Authorization: Bearer $SENTRY_TOKEN`. Los valores con nombre de secreto tienen que usar una variable, y el Agent Log tapa los valores resueltos.
- **Importar .mcp.json** agrega los servidores del `.mcp.json` del proyecto que todavía no están en la lista.
- **Aprobación en cada máquina**: un servidor de *Este proyecto* viene con el proyecto, así que solo arranca en una máquina donde se aprobó su definición (comando, argumentos, entorno, URL y headers). Uno que agregás o editás acá queda aprobado al guardar. Uno que vino con el proyecto, o que importaste de `.mcp.json`, muestra **No está aprobado en esta máquina** y una casilla **Permitir en esta máquina**. Hasta que lo permitas, el agente no lo recibe: al arrancar una sesión, un aviso nombra los servidores que quedaron afuera, con **Aprobar «nombre»…** para cada uno y **Aprobar todos…**, y cada uno muestra exactamente qué corre antes de permitirlo. Arrancan desde la próxima sesión. Si la definición cambia, vuelve a preguntar. Las aprobaciones son por usuario, en los ajustes del editor. Los servidores de *Todos mis proyectos* no la necesitan.
- La casilla apaga un servidor sin quitarlo.
- **Avanzado**, plegado al final de la página: el servidor MCP propio del editor (puerto, token, límites), las comprobaciones de cada turno, los [hooks del proyecto](Modos-y-permisos.md#hooks-del-proyecto), la carpeta de las [herramientas del proyecto](Herramientas-del-editor.md#herramientas-del-proyecto) (`res://agent_tools` por defecto) y las carpetas fuera del proyecto. También tiene **Usar el autoload de playtest también al correr el juego a mano**, el interruptor del aviso con **Arreglar con el agente** cuando un juego que corrés a mano para con un error (prendido por defecto; ver [Primeros pasos](Primeros-pasos.md#3-el-dock)), **Con el editor en segundo plano, avisarme cuando el agente termina o me espera** (prendido por defecto: la ventana del editor pide atención y, en Linux con `notify-send` o en macOS, aparece una notificación del sistema; con el editor enfocado no pasa nada), la lista de tools compacta y **Ver la lista de tools…**, que abre la pestaña **Tools** de [Extensiones](#extensiones).

Claude Code además carga los servidores de su propia configuración (`claude mcp add`, `.mcp.json`, `~/.claude.json`). Escribí `/mcp` en el chat para ver su estado, reconectarlos o apagarlos.

Las tools de cada servidor piden permiso hasta que las permitas: ver [Servidores MCP de otros programas](Modos-y-permisos.md#servidores-mcp-de-otros-programas).

## Extensiones

**Extensiones**, en el menú **⋯** del header del dock, abre una ventana con los plugins y marketplaces de Claude Code, todos los servidores MCP que ve el agente, las skills, los addons de Godot y las instrucciones del proyecto, y la lista de las herramientas del editor que tiene el agente. Los cambios se aplican al toque por el CLI de Claude Code (`claude`), con el entorno del perfil del agente (por ejemplo `CLAUDE_CONFIG_DIR`). Si `claude` no está en el `PATH`, la ventana usa el que baja el adaptador ACP con npx.

- **Plugins**: los instalados con un interruptor, **Actualizar** y **Desinstalar**, su alcance y los servidores MCP que trae cada uno (con el color de su estado); abajo, los disponibles de tus marketplaces, primero los más instalados, con buscador e **Instalar** (en el alcance elegido arriba: usuario, proyecto o local). Si un plugin necesita correr un comando de su marketplace para instalarse, la ventana muestra el comando y pregunta antes.
- **Marketplaces**: agregar uno (un `dueño/repo` de GitHub, una URL o una carpeta), actualizarlo o quitarlo.
- **Servidores MCP**: los del addon de [Otros servidores MCP](#otros-servidores-mcp) y los que carga Claude Code (usuario, `.mcp.json` del proyecto, local, claude.ai y plugins), cada uno con su estado: conectado, falta autenticar, falló, falta aprobarlo, sin configurar. **Autenticar** corre `claude mcp login`, que abre el navegador. En una sesión, `/mcp` en el chat reconecta o apaga un servidor.
- **Skills**: las skills de Claude Code, agrupadas por dónde viven: las del proyecto (`.claude/skills`, que tu equipo recibe por git), las tuyas (`skills` en la carpeta de configuración de Claude Code, para todos los proyectos) y las que traen los plugins instalados, cada una con su descripción, un botón para abrir su `SKILL.md` y otro para mostrar su carpeta. El interruptor de una skill del proyecto o tuya la apaga **en este proyecto** (queda en la config del proyecto): desde la próxima sesión el agente no la ve y sale del menú `/`. Las de plugins no tienen interruptor: se prenden y apagan con su plugin en **Plugins**. **+** crea una skill con una plantilla y abre su `SKILL.md`; el botón de carpeta importa la carpeta de una skill, una carpeta con varias o un zip; las dos la dejan en este proyecto o en tus skills, según lo elegido arriba. Una skill tuya se puede copiar al proyecto, y las del proyecto y las tuyas se pueden mandar a la papelera. **Usar con todos los agentes** pasa una skill del proyecto o tuya a `.agents/skills` (en el proyecto, o `~/.agents/skills`), la carpeta que leen Google Antigravity, Codex y otros agentes, y deja un enlace en la carpeta de Claude Code: una sola copia para todos; la tarjeta dice que está compartida. **Solo para Claude Code** la devuelve. Borrar una compartida manda a la papelera la carpeta y saca el enlace. Las dos opciones salen solo en una pestaña de Claude Code, porque el enlace va en la carpeta de su cuenta. Una skill del proyecto compartida se sube como enlace simbólico: un clon en Windows necesita `core.symlinks=true` (y el modo desarrollador), si no Claude Code no la ve. Mientras no estén instaladas las skills de Godot del [marketplace godot-agent](https://github.com/dannroda/godot-agent-plugins), una tarjeta ofrece agregar el marketplace e instalar sus plugins `gdscript` y `shaders`. Con otro agente, la pestaña lista las skills que lee ese agente (`.agents/skills` en el proyecto y sus carpetas de usuario, como `~/.agents/skills` o `~/.gemini/config/skills` para Google Antigravity) y, con Antigravity, las de sus plugins.
- **Addons del proyecto**: los plugins del editor de `addons/` del proyecto con un interruptor (el harness no tiene) y **Actualizar** cuando el Asset Store tiene una versión nueva. **Buscar en el Asset Store…** abre una búsqueda en el [Asset Store de Godot](https://store.godotengine.org) para esta versión de Godot, por relevancia, actualizados hace poco, mejor valorados o más nuevos. **Instalar** baja la última release estable y muestra qué va a escribir antes de tocar el proyecto: solo la carpeta `addons/` (los zips suelen traer demos, un README y hasta un `project.godot`; una casilla los suma), sin pisar ningún archivo que ya exista, y **Activar sus plugins** los prende cuando el editor terminó de importar los archivos. Los assets pagos se compran en la web del store.
  - **Actualizaciones**: al abrir la pestaña (y con el botón ↻) le pregunta al store por versiones nuevas de los plugins del proyecto; un plugin con una muestra **Actualizar a X**. Actualizar reemplaza la carpeta del addon (se pierden los cambios que le hayas hecho adentro), borra los archivos que la versión nueva ya no trae y deja sus plugins como estaban. Cada instalación queda anotada en `.godot_agent/assets.json` (commitealo para que tu equipo reciba las mismas actualizaciones); un plugin instalado a mano se busca en el store por el nombre, y solo si su `plugin.cfg` tiene versión.

- **Tools**: todo lo que el agente puede hacer con las herramientas del editor del addon, agrupado por función (leer el proyecto, editar escenas, archivos, correr y jugar el juego, diagnóstico, validación, ajustes del proyecto, recursos, TileMaps, animación, documentación de la API, Asset Store, profiler, sesiones). Cada tool muestra la descripción corta que ve el agente, su grupo de permisos y qué pide en cada modo, en el orden Preguntar, Revisar, Construir, Auto, One-shot (✓ corre sin preguntar · ? te pregunta · ✗ no se permite). El filtro busca por nombre, descripción y permiso. Con la lista de tools compacta, quedan marcadas las que el agente alcanza por `godot.methods` y `godot.run`. También se abre desde el menú **⋯** del dock (**Qué puede hacer el agente (tools)…**) y desde Settings → Servidores MCP → Avanzado. La lista completa con los parámetros está en [Herramientas del editor](Herramientas-del-editor.md).
- **Instrucciones**: las instrucciones del proyecto para los agentes, para leerlas y editarlas: `CLAUDE.md` (Claude Code), `AGENTS.md` (Codex, Copilot, Cursor, OpenCode…) y `GEMINI.md` (Gemini CLI). **Agregar los datos del proyecto** escribe lo que el harness puede leer solo (versión de Godot, escena principal, autoloads, capas con nombre, acciones de input que no son `ui_*`, carpetas de primer nivel) entre marcadores `<!-- godot-agent:project-facts -->`: agregarlo de nuevo actualiza esa parte y deja el resto como lo escribiste. Cambiar de archivo guarda el que estabas editando. Los agentes lo leen desde su próxima sesión.
- **Memoria**: lo que se recuerda del proyecto, por entrada: lo que guardaste con `/remember <dato>` (alias `/recordar`; una sección entre marcas `<!-- godot-agent:remembered -->` en el archivo de instrucciones del agente activo, sin tocar el resto), lo que aprendieron los playtests (notas, hallazgos marcados como que no son bugs, scripts guardados), traspasos y planes aprobados en `.godot_agent/`, y las memorias propias de Claude Code de este proyecto con la cuenta de la pestaña activa. Las de Claude Code se leen solo al abrir esta pestaña (solo los `.md` de `<carpeta de configuración>/projects/<proyecto>/memory/`); no se editan desde acá, y borrar una la manda a la papelera después de preguntar. La memoria propia de otros agentes no se puede leer.

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
