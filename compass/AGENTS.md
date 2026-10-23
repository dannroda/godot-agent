# Tablero del proyecto — guía para agentes

Las tareas y los hitos de este proyecto viven en `compass/`, en el formato de Scope Compass. Esta guía alcanza para operar el tablero; no hace falta leer el código de Scope Compass.

## Reglas

- **Usá la CLI `scompass`, no edites los JSON a mano.** Valida, escribe en formato canónico, regenera el export markdown y, si hay un hub corriendo, avisa al instante a la UI web y al dock de Godot.
- Corré los comandos desde cualquier carpeta del proyecto (busca `compass/` hacia arriba) o con `--dir <proyecto>`.
- Si `scompass` no está en el PATH: `node <carpeta de scope-compass>/hub/bin/scompass.js`.
- Agregá `--json` para leer la salida desde un programa. Código de salida 0 si anduvo; el error va por stderr.
- No hace falta que el hub esté corriendo: sin hub, la CLI escribe directo en `compass/`. Con el Inicio corriendo (`scompass home`), la CLI pasa por él solo (lo encuentra en el registro).
- Si la CLI avisa que el hub es de otra versión, reinicialo con `scompass restart` antes de seguir: un hub viejo puede no conocer campos nuevos.
- Los cambios quedan como archivos modificados en `compass/` (y en el export markdown). Commitealos solo si te lo piden. `scompass list` termina con cuántos hay sin commitear (`uncommitted` en `--json`).

## MCP

Si en tus herramientas aparece el servidor `scompass` (`list_tasks`, `show_task`, `add_task`, `move_task`, `check_step`…), usalo en lugar de correr `scompass` por Bash: son los mismos comandos con `--json`, con los parámetros tipados, y no piden permiso por cada llamada. Lo que sigue vale igual (modelo, etags, pasos desde 1); los nombres de las herramientas siguen a los comandos (`set` es `update_task`, `step add` es `add_step`, `decide` es `add_decision`, `decision ok` es `review_decision`, `playtest pass` es `set_playtest_result`). Listas, sesiones de playtest (crear, ordenar), capturas e `init`/`serve` siguen por la CLI.

Para tenerlo en Claude Code en todos los proyectos (toma el de la carpeta de la sesión; `dir` en cada herramienta apunta a otro):

```sh
claude mcp add --scope user scompass -- node <carpeta de scope-compass>/hub/bin/scompass.js mcp
```

Los hitos (`compass://milestone/<id>`), las tareas (`compass://task/<id>`) y los documentos (`compass://doc/<alias>`) se adjuntan con `@scompass:…`.

## Chat

La web del tablero tiene un chat (botón *Chat*, solo en el mismo equipo) con el Claude Code instalado. Lanza `claude` en la carpeta del proyecto con el MCP `scompass` y las herramientas de lectura (`Read`, `Grep`, `Glob`), permitidas de antemano: no edita archivos ni corre comandos, y lo demás se niega sin preguntar. Si sos ese agente:

- Un mensaje puede empezar con `Tarea abierta: <código> <título> (compass://task/<id>)`: es la tarea que el usuario tiene abierta; leela con `show_task` si hace falta.
- Lo que haya que editar o correr, decilo para hacerlo en la terminal.
- Las reglas de esta guía valen igual: registrá las decisiones, pasá a `review` lo que termines.

Las conversaciones son sesiones de Claude Code (se pueden seguir con `claude --resume <id>`, con el mismo perfil); el hub solo guarda la lista y una copia para mostrarlas, fuera de `compass/`. Cada conversación usa un perfil de Claude Code (`~/.claude` o una carpeta de `~/.claude-profiles/`, que se lanza con `CLAUDE_CONFIG_DIR`), y el panel muestra su cuenta, el uso de sus límites y los tokens de cada respuesta.

## Modelo

- **Hito** (`compass/milestones/<id>.json`): id `m00`, `m01`, …; campos `code` ("M0"), `title`, `order`, `goal`, `done_when` y `due` (fecha objetivo opcional; atrasado si pasa con tareas sin terminar).
- **Tarea** (`compass/tasks/<id>.json`): el id es el nombre del archivo. `scompass add` le da el siguiente número de su hito (`m5-12` en `m05`) y lo imprime; las tareas de antes pueden tener ids al azar como `sd3tg577`. No se renombra, aunque la tarea cambie de hito. Campos:
  - `milestone` (id del hito), `title`, `code` (número visible, por ejemplo "5.2"; opcional);
  - `description`: qué hay que hacer y por qué, el enunciado de la tarea, que se escribe al crearla (opcional);
  - `status`: `todo` (Pendiente), `paused` (Pausado: empezada y dejada de lado por ahora), `doing` (En curso), `review` (Revisión), `done` (Hecho);
  - `checklist`: pasos `{ text, done, detail? }`. `text` es una línea corta; el cómo y el porqué van en `detail`;
  - `due`: fecha límite opcional, `YYYY-MM-DD` o `YYYY-MM-DDTHH:MM` (hora local);
  - `priority`: prioridad opcional, `high`, `medium` o `low`;
  - `size`: estimación opcional, `s`, `m` o `l` (chica, mediana, grande);
  - `assignee`: responsable opcional, texto libre (una persona o un agente);
  - `tags`: etiquetas opcionales, textos cortos sin comas (`["arte", "audio"]`). Si `compass/config.json` › `description_templates` tiene una plantilla para la etiqueta (por ejemplo `bug`), etiquetar una tarea sin descripción la arranca con ese texto: completalo. Los bugs cargados desde el dock de Godot llegan así, con la etiqueta `bug`, esa plantilla sin completar y, casi siempre, una captura del juego o del editor en `images`;
  - `test`: cómo se comprueba que la tarea está terminada;
  - `notes`: lo que va saliendo al trabajarla: decisiones, hallazgos, lo que el siguiente necesita saber. El pedido va en `description`, no acá;
  - `refs`: documentos del proyecto que la tarea cita, enteros (`{ doc }`) o una sección (`{ doc, section }`);
  - `files`: archivos del repo que la tarea toca (scripts, escenas, recursos), con la ruta desde la raíz del proyecto (`["player/player.gd"]`);
  - `images`: capturas de la tarea (PNG, JPEG, GIF o WebP), con la ruta desde la raíz; las pegadas en la web quedan en `compass/images/`;
  - `links`: vínculos con otras tareas (ver "Vínculos entre tareas");
  - `playtest`: cómo salió al probarla, `{ result?, note? }` (ver "Playtest"); lo escriben `playtest pass`, `fail` y `reset`;
  - `decisions`: las decisiones tomadas al trabajarla, en orden, `{ text, why?, alternatives?, asked?, reply?, review?, promoted?, at }`. Sin `asked`, se decidió sin consultar y queda sin revisar hasta que el usuario pone `review` (`ok`, `revert`; `reverted` cuando ya se revirtió); con `asked`, es una pregunta abierta hasta que tiene `reply`;
  - `created_at`, `updated_at` y `done_at` (cuándo pasó a Hecho): los pone la CLI; no hace falta escribirlos.
- En los textos, `` `así` `` se muestra como código.

## Leer

```sh
scompass milestone list                      # hitos, en orden
scompass list                                # todas las tareas, por hito
scompass list --milestone m05 --status doing # filtros (se pueden combinar)
scompass list --q "menú pausa"               # todas las palabras en código, título o id (sin tildes)
scompass list --status todo,doing --priority high --assignee Claude
scompass list --size l,none                  # estimación: s, m, l o sin estimar
scompass list --due overdue                  # overdue | today | week | none (las hechas no vencen)
scompass list --tag arte,audio               # con alguna de esas etiquetas
scompass list --blocked                      # o --unblocked; también --pending-steps y --with-refs
scompass list --json                         # { "tasks": [ { "id", "etag", "title", "status", "checklist", … } ] }
scompass show m5-02                          # una tarea, con los pasos numerados desde 1
scompass show m5-02 --json
scompass history m5-02                       # qué cambió en la tarea en cada commit (desde git)
```

## Escribir

```sh
scompass add "Título de la tarea" --milestone m05 --code 5.9 --description "Qué y por qué"   # imprime el id nuevo
scompass move m5-02 doing                                     # todo | paused | doing | review | done
scompass set m5-02 --title "…" --notes "…" --test "…"          # cambia solo esos campos (--description "" la quita)
scompass set m5-02 --due 2026-10-10                           # fecha límite (--due "" la quita)
scompass set m5-02 --priority high --size m --assignee Claude --tags arte,nivel  # "" quita cada uno; --tags reemplaza la lista
scompass step add m5-02 "Paso corto" --detail "Cómo y por qué"
scompass step set m5-02 2 --text "…" --detail "…"              # --detail "" quita el detalle
scompass step rm m5-02 2
scompass check m5-02 2                                        # tilda el paso 2
scompass check m5-02 2 --undo
scompass set m5-02 --file tarea.json                          # reemplazo completo (--file - lee stdin); vale la salida de show --json, y su etag protege de pisar un cambio
scompass milestone set m08 --file hito.json                   # crea o reemplaza un hito
scompass milestone set m08 --due 2026-11-01                   # fecha objetivo del hito ("" la quita)
```

- Los pasos se numeran desde 1, como los muestra `scompass show`.
- Para no pisar un cambio ajeno, pasá `--etag <etag>` (el que devuelve `--json`): si la tarea cambió, falla con conflicto. Volvé a leerla y reintentá.
- Una tarea se borra borrando su archivo en `compass/tasks/`.

## Vínculos entre tareas

Una tarea puede bloquear a otra o estar relacionada con otra. Se guarda en un solo lado (`links` de la tarea que bloquea); "bloqueada por" se calcula.

```sh
scompass link add m5-02 blocked-by m5-01   # m5-02 no puede avanzar hasta que m5-01 esté hecha
scompass link add m5-01 blocks m5-02       # lo mismo, dicho desde la otra tarea
scompass link add m5-02 related m4-03      # relacionadas, sin orden
scompass link rm m5-02 m5-01               # quita el vínculo entre las dos
scompass link list m5-02 --json            # { "links": [ { "id", "blocks", "blocked_by", "related" } ], "broken": [] }
scompass link list                         # todos; sale con 1 si hay vínculos a tareas que no existen
```

- Entre dos tareas hay un solo vínculo: agregar otro reemplaza al anterior. Un `blocks` que cerraría un ciclo se rechaza.
- `scompass list` marca `[bloqueada por <ids>]` en las tareas que tienen delante una tarea sin terminar; `scompass show` lista los vínculos.
- Antes de empezar una tarea, mirá si está bloqueada. Si descubrís que una depende de otra, vinculalas en lugar de anotarlo en `notes`.

## Decisiones

El usuario quiere ver qué decidiste sin preguntarle. **Cada vez que elijas entre alternativas razonables que el usuario podría haber querido distinto, registralo en la tarea:** un formato o un nombre visible, dejar algo afuera, sumar una dependencia, un comportamiento por defecto, una simplificación de lo que pedía. No hace falta para lo que tiene una sola respuesta razonable (seguir el estilo del código, arreglar un typo). Ante la duda, registralo: revisar una de más le cuesta un clic.

```sh
scompass decide m5-02 "Guardar en JSON" --why "se lee en el diff" --alternatives "binario"   # tomada sin consultar
scompass decide m5-02 "¿JSON o binario?" --ask      # le preguntaste al usuario (queda abierta hasta que responda)
scompass decision reply m5-02 2 "JSON"               # la respuesta, si te la dio en el chat
scompass decision reverted m5-02 1                   # ya deshiciste la que el usuario marcó a revertir
scompass list --decisions open,pending,revert        # tareas con preguntas abiertas, sin revisar o a revertir
scompass decisions --revert                          # las de todo el proyecto (--open, --pending, --revert)
```

- Las decisiones se numeran desde 1, como los pasos, y `show` las lista con su estado: `?` pregunta abierta, `!` sin revisar, `↺` a revertir, `✓` resuelta.
- Las preguntas también se registran (`--ask`), con la respuesta cuando llega: así queda por qué la tarea quedó como quedó. Desde Claude Code, `--ask` guarda solo la sesión que pregunta (`CLAUDE_CODE_SESSION_ID`): si el usuario responde en la web, puede mandarte la respuesta a esa misma sesión por el chat.
- Revisar (`decision ok`, `revert`) es del usuario. Antes de seguir con una tarea, mirá si tiene alguna a revertir: deshacela siguiendo `reply`, marcala `reverted` y, si en su lugar decidiste otra cosa, registrala como decisión nueva.
- Las de diseño grandes del proyecto (las que cambian la spec) van además al documento de decisiones: `scompass decision promote m5-02 1` agrega una resuelta como entrada `D<n>` al final del documento `decisiones` (o el de `config.json › decisions_doc`) y la marca en la tarea. Hacelo cuando te lo pidan o cuando la decisión cambie la spec; no commitea.

## Uso habitual

- Al empezar una tarea: `scompass move <id> doing`. A medida que avanzás, `scompass check <id> <n>`.
- Al terminar: completá `test` si está vacío, dejá en `notes` lo que el siguiente necesite saber y pasala a `review` (o a `done` si ya se comprobó). El avance del hito cuenta las de `review` como hechas (y dice cuántas son); el hito se da por terminado cuando todas están en `done`.
- Trabajo nuevo que aparece en el camino: `scompass add` en el hito que corresponda, con `--description` (qué y por qué), en lugar de dejarlo solo en el chat.
- Si te piden "lo mío" o "lo de alta prioridad", filtrá con `--assignee` o `--priority`. Al tomar una tarea, si el proyecto usa responsables, poné tu nombre con `set --assignee`. Usá las etiquetas que ya existen (`scompass list --json` las muestra) antes de inventar otras.

## Listas

Además de las tareas, un proyecto puede tener listas (`compass/lists/<id>.json`): pendientes, compras, ideas, assets a conseguir. Cada ítem es `{ text, done, created_at, due?, repeat?, task? }`; `due` es la fecha límite (`YYYY-MM-DD` o `YYYY-MM-DDTHH:MM`, hora local), `repeat` `{ "every": "day" | "week" | "month" | "year" }` (requiere `due`) y `task` el id de la tarea creada desde el ítem.

```sh
scompass lists                                      # listas con lo que queda pendiente
scompass lists show compras --json                  # { "id", "etag", "title", "items": [ … ] }
scompass lists add "Libros para leer"               # el id sale del título: libros-para-leer
scompass item add compras "Yerba"
scompass item add pendientes "Pagar la luz" --due 2026-10-10 --repeat month
scompass item check compras 2                       # ítems numerados desde 1, como en lists show
scompass item set pendientes 1 --due ""             # quita la fecha
scompass item clear compras                         # quita los tildados
scompass item task assets 3 --milestone m06         # pasa el ítem a una tarea y lo enlaza
```

- Tildar un ítem que se repite no lo deja tildado: su `due` avanza un período desde la fecha límite (31/01 → 28/02). No se destilda; si hace falta, cambiale la fecha con `item set --due`.
- Algo con etapas o pasos va como tarea en un hito; algo que solo se tilda va en una lista. Si un ítem crece, pasalo a tarea con `item task`.

## Playtest

Una sesión de playtest (`compass/playtests/<id>.json`) junta tareas ya creadas en el orden en que se van a probar, para ordenar lo que está en Revisión. Cada ítem es `{ task }`, el id de la tarea. Cómo salió la prueba vive en la tarea, en `playtest: { result?, note? }`: `result` `pass` (anda) o `fail` (falla; sin `result`, todavía no se probó) y `note` lo que se vio al probarla (puede tener varios renglones). Así una tarea que está en varias sesiones muestra lo mismo en todas. `pass`, `fail` y `reset` escriben eso en la tarea; no cambian su estado: eso se hace aparte, con `move`.

```sh
scompass playtest                                   # sesiones, con cuántas tareas faltan probar
scompass playtest show build-0-3 --json             # { "id", "etag", "title", "items": [ { "task" } ] }; el resultado, en cada tarea
scompass playtest new "Build 0.3" --review          # el id sale del título; --review la carga con las tareas en Revisión
scompass playtest add build-0-3 m5-02 m5-07 --at 1  # agrega tareas (desde la posición 1); las que ya están no se repiten
scompass playtest add build-0-3 --review --milestone m05   # suma las de Revisión de ese hito
scompass playtest move build-0-3 m5-07 3            # la lleva a la posición 3 (por id o por número desde 1)
scompass playtest fail build-0-3 2 --note "Se traba al saltar"
scompass playtest pass build-0-3 m5-02              # reset la vuelve a "sin probar"; drop la saca de la sesión
scompass playtest rm build-0-3                      # borra la sesión; las tareas no se tocan
scompass playtest migrate                           # sesiones viejas (result y note en la sesión) → las tareas
```

- Si `playtest` avisa de sesiones del formato anterior, corré `scompass playtest migrate`: si una tarea estaba en varias, gana el resultado de la sesión más reciente que la probó y las notas distintas se juntan.
- Si una prueba falla, dejá en `note` lo que se vio y, si hay que arreglarla, volvé la tarea a `doing`; si anda, pasala a `done`.
- El dock de Godot marca ✓ / ✗ en la lista y muestra el resultado y la nota en el detalle; con hub, *Anda* / *Falla* se cambian ahí también.

## Documentos y referencias

Los documentos citables están en `compass/config.json` › `docs` (alias y ruta, o un patrón como `docs/**/*.md`). Se declaran con `doc add`, no editando la config: tiene que ser un `.md` dentro del proyecto que git no ignore (o un patrón que termine en `.md`); nada con `..`, llaves, rutas absolutas ni enlaces simbólicos que lleven afuera. Un archivo de un patrón toma el alias del patrón más su ruta bajo la carpeta del patrón, sin `.md`: `docs/notas/arte.md` es `docs/notas/arte`. Una referencia apunta a una sección por su id estable (`<!-- id: … -->` debajo del título), o al documento entero si va sin `#<id>`. En la descripción, notas, prueba y pasos, `[[alias#id]]` enlaza una sección y `[[alias]]` el documento.

```sh
scompass doc list                  # documentos con su índice de secciones
scompass doc show spec#godot --raw # el markdown de una sección (sin #godot, el documento entero)
scompass ref add m5-02 spec#godot  # la tarea cita esa sección
scompass ref add m5-02 spec        # la tarea cita el documento entero
scompass ref rm m5-02 spec#godot
scompass refs check                # referencias rotas (sale con 1 si hay), también archivos que ya no están
scompass file add m5-02 player/player.gd   # la tarea toca ese archivo (acepta res://); file rm lo quita
scompass image add m5-02 /tmp/captura.png  # captura: una de afuera se copia a compass/images/; una del repo se cita
scompass image rm m5-02 compass/images/m5-02-20261011-101500.png   # la saca (y borra el archivo si lo guardó la app)
scompass doc add enemigos docs/enemigos.md   # o un patrón: doc add docs "docs/**/*.md"
scompass doc rm enemigos                     # deja de declararlo; el archivo no se toca
scompass doc search "salto doble"            # líneas con todas las palabras, con su sección
scompass doc status                          # estado de git de cada documento y su último commit
scompass doc diff gdd                        # cambios sin commitear y las secciones que tocan
```

## Proyectos del equipo

Cada hub que se levanta anota su proyecto en `~/.config/scope-compass/projects.json` (en Windows, `%APPDATA%\scope-compass\projects.json`), para que el Inicio lo muestre aunque después se apague. Al lado, `chats/` guarda las conversaciones del chat de cada proyecto. No hace falta tocarlo para operar el tablero. Un tablero en una carpeta temporal (`/tmp`, para probar algo) no se anota solo, y el Inicio olvida al arrancar los temporales que ya no existen; para tests, `SCOMPASS_CONFIG` y `SCOMPASS_REGISTRY` apuntando a una carpeta propia aíslan todo.

```sh
scompass home list --json   # { "file", "projects": [ { "path", "name", "found", "hubs": [ { "pid", "port" } ] } ] }
scompass home add           # anota este proyecto sin levantar su hub (o: home add <carpeta>)
scompass home rm <carpeta>  # lo quita del registro; no toca sus datos
scompass home               # levanta el Inicio (uno por usuario): GET /api/today junta lo vencido, de hoy y en curso
```

## Más

- `scompass --help`: todos los comandos. Un proyecto nuevo se crea con `scompass init --template juego|personal|vacio`.
- `compass/README.md`: formato de los archivos y manejo a mano con git.
- `compass/schema/`: JSON Schema de tareas, hitos, listas, sesiones de playtest y `config.json` (`views` elige las pestañas de la web: `board`, `lists`, `playtest`, `decisions`, `docs`, `files`).
- Ajustes de la web (el engranaje del tablero y del Inicio): preferencias de quien mira, guardadas en su navegador y no en `compass/`. Por ahora, los bordes de fantasía: marcos de pixel art en botones, tarjetas y paneles, siempre con el tema oscuro.
- `scompass update`: pone al día `compass/schema/`, esta guía y `compass/.gitattributes` (LF también en Windows) cuando Scope Compass se actualizó (`--check` solo avisa). El dock de Godot lo ofrece con el botón "Actualizar", y la bandeja del hub con "Actualizar compass/".
