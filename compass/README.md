# compass — datos del tablero

Estos archivos **son** las tareas del proyecto, en el formato de [Scope Compass](https://github.com/dannroda/scope-compass). Se pueden leer, editar y versionar solo con git y un editor de texto; ninguna app es obligatoria.

- `milestones/<id>.json`: un hito (`m00` = M0, …).
- `tasks/<id>.json`: una tarea. El nombre del archivo es su id.
- `images/`: capturas de las tareas que se pegaron en la web o se agregaron con `scompass image add` desde fuera del proyecto. Cada tarea las cita en `images`.
- `lists/<id>.json`: una lista (pendientes, compras…), con sus ítems `{ text, done, due? }` adentro. Tildar uno es cambiar `"done"` a `true`.
- `playtests/<id>.json`: una sesión de playtest: tareas en el orden de prueba, `{ task }`. Cómo salió cada prueba (`result` `"pass"` o `"fail"`, y `note`) va en la tarea, en `playtest`, y se ve igual en todas las sesiones que la tienen.
- `schema/`: JSON Schema de cada tipo y de `config.json`, para validar una edición a mano. Es una copia del de Scope Compass: `scompass update` la pone al día.
- `config.json`: nombre del proyecto, documentos referenciables, export markdown, puerto del hub y `views` (las pestañas de la web en orden, la primera es la que abre: `board`, `lists`, `playtest`, `docs`, `files`).
- `.gdignore`: hace que Godot ignore esta carpeta.
- `.gitattributes`: estos archivos siempre con LF, también en Windows (`scompass update` lo pone al día).
- `AGENTS.md`: guía del tablero para agentes de IA (se pone al día con `scompass update`).

Con la CLI: `scompass list`, `scompass show <id>`, `scompass move <id> doing`, `scompass --help`.

## Manejo sin la app

| Quiero… | Qué hacer |
|---|---|
| Ver las tareas | Abrir `docs/tareas.md` (último export legible) o los JSON de `tasks/` |
| Mover una tarjeta | Cambiar `"status"` a `"todo"`, `"paused"`, `"doing"`, `"review"` o `"done"` |
| Tildar un paso | Cambiar `"done": false` a `true` en `checklist` |
| Crear una tarea | Copiar un JSON de `tasks/` con otro nombre de archivo y editarlo |
| Borrar una tarea | Borrar el archivo |
| Ver el historial de una tarea | `git log -p compass/tasks/<id>.json` |
| Recuperar algo borrado | `git checkout <commit> -- compass/tasks/<id>.json` |

## Formato

- JSON con 2 espacios de indentación, claves en orden alfabético, UTF-8, salto de línea al final.
- Los archivos no guardan número de versión: no hay nada que incrementar al editar a mano.
- `updated_at` es opcional en ediciones a mano.
- En los textos, `` `así` `` se muestra como código.
- `links` vincula tareas: `{ "type": "blocks", "task": "<id>" }` en la tarea que bloquea a la otra, o `"related"`. "Bloqueada por" no se guarda: se calcula.
- `refs` apunta a secciones de documentos por su id estable (`<!-- id: ... -->` debajo de cada título).
- `priority` (`"high"`, `"medium"`, `"low"`), `assignee` (texto) y `tags` (lista de textos sin comas) son opcionales: sin el campo, la tarea no tiene ese dato.
