# Modos y permisos

[Inicio](Inicio.md) · [English](../en/Modes-and-permissions.md)

## Modos

| Modo | Qué hace el agente |
|---|---|
| **Preguntar** | Responde sobre el proyecto. Puede leer; no puede editar ni correr nada. |
| **Revisar** | Revisa escenas y scripts y devuelve hallazgos (bug, estructura, rendimiento, estilo), que aparecen como marcas en el Script Editor. Ver [Revisar](Revisar.md). |
| **Construir** | Edita escenas y scripts y corre el juego, pidiendo permiso según la matriz de abajo. |
| **Auto** | Como Construir, pero sin tarjetas para lo que se puede deshacer: edita escenas, scripts y settings del proyecto y corre el juego solo. Los comandos de shell corren solos solo si están en la allowlist; ver [Modo Auto](#modo-auto). |
| **One-shot** | Persigue un objetivo entero con presupuestos, checkpoints y playtests, en la pantalla Agent. Ver [One-shot](One-shot.md). |

Cambiar de modo cambia también el modo del agente, si lo publica: Preguntar y Revisar usan `plan`; Construir, Auto y One-shot usan `default`.

## Permisos

Cada acción cae en un grupo, y cada grupo tiene una decisión por modo: **Permitir**, **Preguntar** o **Denegar**.

- **Preguntar** (la decisión, no el modo) muestra una tarjeta en el chat con lo que quiere hacer el agente (y el diff, si es una edición). Si nadie contesta en 5 minutos (configurable), se deniega.
- **Denegar** deniega sin preguntar y le dice al agente por qué.

Valores por defecto:

| Grupo | Preguntar | Revisar | Construir | Auto | One-shot |
|---|---|---|---|---|---|
| Lectura | Permitir | Permitir | Permitir | Permitir | Permitir |
| Diagnóstico | Permitir | Permitir | Permitir | Permitir | Permitir |
| Editar escenas | Denegar | Denegar | Preguntar | Permitir | Permitir |
| Editar archivos | Denegar | Denegar | Preguntar | Permitir | Permitir |
| Ejecutar el juego | Denegar | Preguntar | Preguntar | Permitir | Permitir |
| Shell / comandos | Denegar | Denegar | Preguntar | Preguntar¹ | Preguntar |
| Project settings, export y addons | Denegar | Denegar | Preguntar | Permitir | Permitir |
| Instalar desde el Asset Store | Denegar | Denegar | Preguntar | Preguntar | Preguntar |
| Subagentes | Permitir | Permitir | Permitir | Permitir | Permitir |

¹ En Auto, primero deciden las [listas del modo Auto](#modo-auto); solo lo que no permiten muestra una tarjeta.

### Subagentes

Con Claude Code, lanzar un subagente (su tool **Agent**) pasa por el grupo **Subagentes**: podés denegarlo o hacer que pregunte en un modo.

- **Subagentes a la vez**, en la matriz de **Ajustes → Permisos**, limita cuántos corren al mismo tiempo en cada modo (0 = sin límite). Uno más se rechaza con un aviso en el chat, y al agente se le dice por qué.
- La tarjeta de un subagente en el chat muestra su prompt, las tools que corre y lo que va escribiendo, y al final su informe. Uno que corre en segundo plano sigue en curso hasta que termina, aunque ya haya terminado el tool call que lo lanzó.
- Mientras el agente trabaja, la línea de estado cuenta los subagentes en curso; su tooltip los lista.

### Servidores MCP de otros programas

Las tools de un servidor MCP que no es `godot` (un [servidor de Settings](Settings.md#otros-servidores-mcp), o uno que el agente carga de su propia configuración) van a un grupo propio, **MCP · nombre**, que es **Preguntar** en todos los modos hasta que lo cambies.

- En **Settings → Permisos**, debajo de la matriz, hay una fila por cada servidor de la lista y por cada uno que ya pidió permiso en la sesión.
- La tarjeta de una de esas tools ofrece además **Permitir siempre «nombre» en modo *modo*, en este proyecto**, que guarda **Permitir** en esa fila. **Siempre en esta sesión** vale solo para ese servidor.
- Al arrancar un One-shot, la actividad avisa qué servidores preguntarían: el run espera en cada una de sus tools.

## Modo Auto

Auto es para trabajar en el chat sin aprobar cada paso. Las ediciones se pueden deshacer (el ↶ de cada tarjeta, el undo del editor), así que pasan solas. La shell es otra cosa, así que cada comando se compara con dos listas de patrones:

- **Allowlist**: corre sin preguntar. Por defecto, comandos de lectura y de build: `ls`, `cat`, `grep`, `find`, `git status/diff/log/show`, `godot --headless …` y parecidos.
- **Preguntar siempre**: muestra una tarjeta aunque coincida un patrón más amplio de la allowlist. Por defecto: `rm`, `mv`, `sudo`, `chmod`, `git push/reset/checkout/clean/rebase`, `curl`, `wget`, `ssh`, instaladores de paquetes, `find -delete/-exec`.
- Todo lo demás muestra una tarjeta.

Cómo se revisa un comando:

- Un comando con `&&`, `||`, `;` o `|` corre solo únicamente si **cada parte** está en la allowlist.
- La sustitución de comandos (`$(…)`, backticks) y la redirección a un archivo (`> salida.txt`) muestran siempre una tarjeta. `2>&1` y `> /dev/null` no.
- En un patrón, `*` vale por cualquier texto, y `git log *` también cubre `git log` solo. Un programa con ruta (`/opt/godot/godot`) se compara por su nombre.
- Escribir archivos del proyecto desde la shell se sigue rechazando, digan lo que digan las listas (ver abajo).

Cuando un comando muestra una tarjeta, la tarjeta propone un patrón, como `npm test` para `npm test`, que se puede editar, por ejemplo a `npm test *`. **Permitir siempre** agrega el patrón a la allowlist y permite este comando. En Auto, la tarjeta de la shell no ofrece «Siempre en esta sesión», así nunca se abre todo el grupo shell de una vez.

**Revisar las listas**: **Settings → Permisos → Modo Auto: comandos de shell** muestra cada regla con su lista, su origen (default, agregada por vos, desde una tarjeta de permiso) y la fecha en que se agregó.

- **Probar un comando**: escribilo en el campo de arriba de la tabla para ver si correría o preguntaría, y por qué. La regla que decidió queda resaltada en la tabla. Usa las reglas como las estás editando, antes de guardar.
- Se puede filtrar por las que agregaste vos o las tarjetas, editar un patrón o pasarlo a la otra lista, quitar reglas y restaurar las default (las que agregaste se conservan).
- Se guardan en `project_config.tres`, con el resto de los permisos del proyecto.

Cada decisión queda además en el **Agent Log**, canal perm: el comando, si corrió o preguntó, y la regla que lo decidió.

## Escrituras que se saltean el editor

En cualquier modo, el harness rechaza solo, sin tarjeta:

- comandos de shell que escriben archivos del proyecto: redirecciones (`>`), `tee`, `sed -i`, `dd of=`, y scripts de Python, Node, Ruby o Perl que abren archivos para escribir;
- escribir a mano un `.tscn`, `.uid` o `.import`, con las herramientas de archivos del agente o por el acceso a archivos del editor;
- correr Godot desde la shell sin `--headless`: abriría el juego o un editor en una ventana aparte. Para ver el juego, el agente lo corre desde el editor (`godot.run_scene`) y lo captura (`godot.capture_game_frame`).

El chat muestra un aviso «Rechazado: …». Al agente se le indica que escriba los scripts con sus propias herramientas de archivos (el harness las pasa por el editor) y las escenas con las tools `godot.*`. Los comandos que escriben fuera del proyecto, por ejemplo en `/tmp`, siguen la matriz de arriba como siempre.

La matriz se cambia en **Settings → Permisos**. Se guarda solo lo que difiere de los valores por defecto, en la config del proyecto (`project_config.tres`), así se puede commitear y compartir con el equipo.

## Remote Control

Con Claude Code podés seguir una sesión del dock desde claude.ai/code o la app de Claude en el celular. Cuando el agente ofrece `/remote-control`, aparece el botón **Remoto** en la línea de estado; prende Remote Control con el nombre del proyecto como nombre de la sesión. Mientras está prendido, una franja debajo de la línea de estado muestra el link, **QR** (un código QR del link, para abrirlo con la cámara del celular), **Copiar link** y **Apagar**. Un clic en el título de la franja la pliega a una línea. Escribir `/remote-control` o `/remote-control off` en el composer hace lo mismo.

- Lo que escribís desde el celular, y las respuestas del agente, se ven solo en el celular: Claude Code no se los manda al harness. El dock sí ve las herramientas que piden permiso.
- Los archivos que cambian mientras Remote Control está prendido (y no hay un turno del dock en curso) aparecen en el chat como un aviso por tanda: «Desde Remote Control: modificó player.gd · creó enemy.gd». **Ver diff** muestra cada archivo antes y ahora, y **Deshacer** los deja como estaban. Deshacer aparece cuando el harness conoce el texto de antes: archivos de texto de hasta 256 KB. Lo que guardás desde el editor no cuenta, y el harness mira solo los primeros 5000 archivos del proyecto.
- Los permisos siguen el modo. Lo que la matriz permite o rechaza, las listas de Auto y las escrituras rechazadas de arriba los decide el harness en el momento, así que el celular no pregunta. Cuando el harness mostraría una tarjeta, el celular también pregunta, y se contesta de cualquiera de los dos lados. Si contestás en el celular, la tarjeta del dock se cierra con «Contestado en otro lado».
- Los comandos que Claude Code corre sin preguntar (los de solo lectura, como `git status`) ni llegan al harness.
- One-shot corre solo: en ese modo el botón no aparece, y empezar un One-shot apaga Remote Control. Una sesión nueva arranca apagado.
- Los comandos con `/` (`/remote-control`, `/compact`…) van solos, sin el contexto del harness ni adjuntos: Claude Code reconoce un comando solo cuando es el mensaje entero.
