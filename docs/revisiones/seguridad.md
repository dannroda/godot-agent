# Revisión de seguridad del addon (M11, m13-01)

Fecha: 2026-10-29. Alcance: lo que el agente, o un tercero que le pasa datos (el registro de ACP,
el Asset Store, un zip, una página), puede hacer a través del harness en la máquina y en el
proyecto. Se revisó el código de `addons/godot_agent/` en la rama de la revisión de UX (M10).

Gravedad: **alta** (el agente o un tercero hace algo grave sin que el usuario lo vea), **media**
(se saltea un permiso o una frontera que el usuario cree que existe), **baja** (hace falta una
condición poco común o el daño es acotado), **info** (riesgo aceptado o para tener en cuenta).

## Resumen

| # | Gravedad | Hallazgo | Estado |
|---|---|---|---|
| S1 | media | `fs/*` y las tools de archivos siguen enlaces simbólicos que salen del proyecto | arreglado |
| S2 | media | `godot.copy_file` desde fuera del proyecto se permitía en Auto sin preguntar | arreglado |
| S3 | media | En Auto, `godot --headless *` está en la allowlist y editar archivos se permite: ejecutar cualquier cosa sin preguntar | **a decidir** |
| S4 | baja | Registro de ACP: entradas del zip con `\` y un `cmd` que sale de la carpeta | arreglado |
| S5 | baja | Asset Store: entradas del zip con `\` o con unidad (`C:`) | arreglado |
| S6 | baja | El token MCP de las pestañas extra no se tapaba en el Agent Log | arreglado |
| S7 | info | La allowlist de Auto (`cat *`, `grep *`…) lee fuera del proyecto | aceptado |
| S8 | info | Los `.tar.*` del registro se descomprimen con el `tar` del sistema | aceptado |
| S9 | info | El actualizador confía en HTTPS y en los releases del repo, sin firma | aceptado |

Lo que se revisó y está bien: el servidor MCP (S10), las terminales (S11), las preguntas y enlaces
del agente (S12), los secretos en perfiles y en el log (S13) y el export (S14).

## Hallazgos

### S1 · media · `fs/*` y las tools de archivos siguen enlaces que salen del proyecto (arreglado)

`FsHandler._check_path` y `FileTools._check_target` decidían con el texto de la ruta
(`simplify_path`). Un enlace simbólico dentro del proyecto que apunta afuera pasaba el chequeo, y
`fs/read_text_file`, `fs/write_text_file`, `godot.move_file` y `godot.delete_file` trabajaban del
otro lado del enlace. No es raro: este mismo repo tiene `addons/scope_compass` como enlace a
`../../scope-compass`.

Arreglo: `FsHandler.link_escape` recorre la ruta desde su raíz permitida y, si un componente es un
enlace (sigue hasta 8 saltos) que lleva fuera del proyecto y de las carpetas extra de Settings,
rechaza la ruta con el nombre del enlace. Lo usan `fs/*` y `FileTools._check_target`. Un enlace que
queda adentro sigue valiendo.

Prueba: `test_fs_handler.test_symlinks_out_of_the_project` (en Windows se saltea: crear enlaces
pide permisos de administrador).

### S2 · media · `godot.copy_file` desde fuera del proyecto, sin preguntar en Auto (arreglado)

`copy_file` acepta una ruta absoluta de afuera como origen (para traer assets bajados). Estaba en
el grupo «Editar archivos», que Auto y One-shot permiten sin preguntar: el agente podía copiar
cualquier archivo de la máquina (`~/.ssh/id_rsa`, un `.env`) al proyecto y leerlo.

Arreglo: `McpTool.group_resolver` deja que el grupo de permiso dependa de los argumentos.
`copy_file` desde fuera de `res://` pide como un comando de shell, que en Auto pregunta (y en
Preguntar y Revisar se deniega); desde `res://` sigue en «Editar archivos». El mensaje de permiso
denegado dice el grupo real.

Prueba: `test_tool_registry.test_copy_from_outside_asks_as_shell`.

### S3 · media · Auto: `godot --headless *` ejecuta cualquier cosa sin preguntar (a decidir)

La allowlist por defecto de Auto tiene `godot --headless *`, y en Auto editar archivos se permite.
Juntos, el agente puede escribir `tools/x.gd` y correr `godot --headless --script tools/x.gd`, que
llama a `OS.execute` con lo que quiera: lo mismo que un `rm` o un `curl` que Auto pregunta. También
`--import` y `-e` corren los scripts `@tool` del proyecto.

Es a propósito en parte: Auto existe para que el agente corra los tests del proyecto sin preguntar,
y casi todos son `godot --headless --script …`. Por eso no se cambió sin consultar. Opciones:

1. Dejarlo y decirlo en Settings › Permisos › Auto: «`godot --headless` corre código del proyecto:
   con esta regla, Auto corre lo que el agente escriba».
2. Sacar `godot --headless *` de la allowlist por defecto y dejar `godot --headless --check-only *`
   y `godot --version`; quien quiera los tests sin preguntar agrega su comando exacto (por ejemplo
   `godot --headless --script tests/run_all.gd *`) con «Permitir siempre».
3. Pasarlo a la lista «preguntar» y que el usuario lo permita por proyecto.

Recomendación: la 2, con la línea de la 1 en la sección de Auto.

### S4 · baja · Registro de ACP: zip con `\` y `cmd` que sale de la carpeta (arreglado)

`AcpRegistry.extract` descartaba entradas del zip con `..` separado por `/`, pero no con `\`: en
Windows `..\..\x` escribía fuera de `<datos del editor>/godot_agent/agents/<id>/<versión>/`. Además
el `cmd` del registro no se validaba: con un binario sin comprimir, `cmd: "../../.bashrc"` copiaba
lo bajado fuera de la carpeta de instalación y le daba permiso de ejecución. El registro es un JSON
público de terceros.

Arreglo: `AcpRegistry.is_safe_relative` (sin `..`, sin raíz ni unidad, con `/` o `\`) para las
entradas del zip y para el `cmd`; un agente con un `cmd` que sale se descarta al leer el registro.

Prueba: `test_acp_registry.test_safe_relative_paths`.

### S5 · baja · Asset Store: zip con `\` o con unidad (arreglado)

`AssetStore.plan_install` tenía el mismo chequeo con `/` solamente. Ahora normaliza `\` a `/` y
descarta las entradas con `:` (una unidad de Windows).

Prueba: `test_asset_store.test_plan_with_root_folder` (dos entradas nuevas con `..\..\` y `C:\`).

### S6 · baja · El token MCP de las pestañas extra no se tapaba en el log (arreglado)

El Agent Log tapa los secretos que conoce. Se le pasaba el token MCP de la primera sesión, pero no
el de cada pestaña extra (`McpServer.session_token`), que va en el JSON crudo de `session/new`: en
modo «raw» se veía, y se copiaba con «Copiar». Ahora `_mcp_servers` lo registra para cada sesión.

### S7 · info · La allowlist de Auto lee fuera del proyecto (aceptado)

`cat *`, `head *`, `grep *`, `rg *`, `find *` no miran rutas: `cat ~/.ssh/id_rsa` corre sin
preguntar en Auto. Se acepta porque el agente ya puede leer eso con sus propias herramientas (por
ejemplo Read de Claude Code), que el harness no controla; restringirlo acá no cierra nada. Vale la
pena decirlo en la guía de Auto.

### S8 · info · `.tar.*` con el `tar` del sistema (aceptado)

Los binarios del registro que vienen en `.tar.gz` se descomprimen con `tar -xf`. GNU tar y bsdtar
sacan la `/` inicial y no escriben miembros con `..` por defecto; un enlace dentro del tar que
apunta afuera depende de la versión. El riesgo es acotado: la carpeta es propia del harness, el
archivo viene del registro y, si el registro trae `sha256`, se verifica antes (sin `sha256` hay que
confirmar con un segundo clic).

### S9 · info · El actualizador confía en HTTPS y en los releases del repo (aceptado)

`AddonUpdater` baja el zip del último release de `dannroda/godot-agent` por HTTPS, solo escribe lo
que está bajo `addons/godot_agent/`, descarta rutas con `..`, comprueba la versión de `plugin.cfg` y
guarda una copia de lo que reemplaza. No hay firma: quien controle el repo o el release controla el
addon. Es lo mismo que instalarlo a mano desde la página de releases.

## Lo que está bien

- **S10 · Servidor MCP**: escucha solo en `127.0.0.1`, token Bearer de 24 bytes aleatorios
  (`Crypto`) comparado en tiempo constante, un token por pestaña, `Origin` local o ausente (contra
  DNS rebinding), tope de 16 conexiones, de 16 KB de headers y 8 MB de body, sin chunked.
- **S11 · Terminales**: el comando se muestra y se autoriza tal como se ejecuta (cada argumento
  citado para sh), las variables de entorno que pide el agente siempre preguntan, el `cwd` tiene que
  estar en el proyecto, en Windows se rechazan argumentos con comillas o saltos de línea, y la salida
  tiene tope. Las reglas de Auto parten el comando en `&&`, `;`, `|`, saltos de línea, frenan la
  sustitución de comandos y las redirecciones a archivos, y la lista «preguntar» gana siempre.
- **S12 · Preguntas y enlaces del agente**: solo enlaces http/https, con la dirección a la vista
  antes de abrir.
- **S13 · Secretos**: los perfiles guardan `$VARIABLE` (Settings rechaza un valor literal con
  nombre de secreto), los servidores MCP de terceros tapan sus valores en el log, y el código del
  login no llega al log.
- **S14 · Export**: el export plugin saltea `addons/godot_agent/` y saca el autoload de playtest si
  quedó; el botón de Settings agrega el filtro a los presets.

## Pendiente

- Decidir S3.
- Las pruebas de rutas en Windows (S1 con enlaces, S4 y S5 con `\`) son de lógica: no hay un CI en
  Windows que las corra contra el sistema de archivos real.
