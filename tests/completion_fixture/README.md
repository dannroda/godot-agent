# Fixture del completado

Proyecto chico para probar las reglas del completado (spec §16.9) sin depender del proyecto real.
El `.gdignore` evita que el editor del repo lo importe (sus `class_name` no se registran);
ProjectContext lo indexa igual porque es la raíz del índice en los tests.
`project_settings.cfg` tiene el formato de `project.godot` (input map y autoloads).
