# Evaluación del completado inline

Conjunto de evaluación para el completado inline (ghost text) del addon. `project/` es un
juego chico de plataformas 2D (Godot 4.4+, GDScript con tipado estático): jugador, enemigos,
pickups, HUD, menús, mejoras, niveles, guardado y ajustes. El código se escribió para esta
evaluación; no es código de terceros.

El motor indexa todo `project/` como corpus. Para cada caso ve el archivo del caso cortado en
el cursor (se borra todo lo que sigue) y tiene que predecir el resto de la línea.

## `cases.txt`

Un caso por línea; las líneas que empiezan con `#` son comentarios:

```
file | line | cut
```

- `file`: ruta relativa a `project/`.
- `line`: número de línea (desde 1).
- `cut`: el comienzo de la línea sin la indentación, hasta el cursor. Lo esperado es el resto
  de la línea. Si está vacío, es predicción de línea siguiente (la línea solo tiene la
  indentación y se espera la línea entera).
- Se recortan los espacios alrededor de `|`. Si el corte termina en espacio, se marca con `⏎`
  justo después (`@onready var ⏎`); el runner quita el `⏎`.

## Detalles

- El `.gdignore` evita que el editor del repo importe esta carpeta (sus `class_name` y
  autoloads no se registran en el proyecto del addon).
- `project/project_settings.cfg` tiene el formato de `project.godot` (autoloads y acciones de
  input). Todas las rutas `res://` apuntan a `res://tests/completion_eval/project/...`.
- Los archivos de `art/`, `sounds/` y `music/` están vacíos: solo existen para que las escenas
  tengan a qué referirse.
