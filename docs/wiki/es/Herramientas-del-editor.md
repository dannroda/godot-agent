# Herramientas del editor (MCP)

[Inicio](Inicio.md) · [English](../en/Editor-tools.md)

El agente ve estas tools como `godot.<nombre>` (Claude Code las muestra como `mcp__godot__<nombre>`).

| Grupo | Tool | Qué hace |
|---|---|---|
| Lectura | `project_info` | Versión de Godot, binario del editor, nombre del proyecto, escena principal, autoloads, acciones de input, plugins, renderer. |
| | `list_files` | Archivos del proyecto con su tipo de recurso; filtro glob. |
| | `scene_tree` | El árbol de una escena: tipos, scripts, escenas instanciadas, grupos y propiedades que difieren del default. Sin `scene`, la escena abierta con sus cambios sin guardar. |
| | `get_node` | Un nodo en detalle: propiedades que difieren del default, script, grupos, conexiones de señales guardadas e hijos. |
| | `editor_state` | Escena actual y abiertas, selección, script abierto con la línea del cursor, y si el juego está corriendo. |
| | `class_info` | La API de una clase en la versión de Godot del editor abierto: herencia, firmas de métodos, propiedades con su default, señales y constantes, con descripción. Clases del motor, tipos built-in (`Vector2`…), `@GlobalScope` y `class_name` del proyecto. Con `member`, la documentación completa de un miembro. |
| | `project_settings` | Los settings bajo un prefijo con su valor y su default; sin prefijo, los que difieren del default. |
| | `search_api` | Busca clases y miembros por nombre o capacidad ("raycast", "move toward"). |
| Diagnóstico | `get_errors` | Errores y warnings del editor y de la última ejecución. Devuelve una marca: pasala como `since` para ver solo los nuevos. |
| | `validate_scripts` | Parsea los scripts en un proceso aparte (con el binario del editor) y devuelve los errores por archivo y línea, sin correr el juego. |
| | `capture_editor_viewport` | Una imagen del viewport 2D/3D. |
| Editar escenas | `add_nodes` | Un subárbol entero en una llamada y un paso de deshacer: nodos anidados con tipo, propiedades, script, grupos y escenas instanciadas. Si un item es inválido, no crea nada. |
| | `duplicate_node` | Copia un nodo con sus hijos, script, grupos y propiedades; al lado del original o bajo otro padre. |
| | `add_node`, `set_properties`, `remove_node`, `reparent_node`, `rename_node`, `connect_signal`, `instantiate_scene`, `open_scene`, `save_scene` | Ediciones sobre escenas abiertas, cada una un paso de deshacer del editor. |
| Editar archivos | `create_scene`, `attach_script` | Escenas y scripts nuevos en disco. `create_scene` también recibe el script de la raíz y sus propiedades (variables exportadas incluidas), así ninguna escena se escribe a mano. |
| Proyecto | `set_project_setting`, `set_input_action`, `remove_input_action`, `set_autoload`, `remove_autoload` | Settings del proyecto, acciones de input (teclas, mouse, joystick) y autoloads a través del editor: cada cambio es un paso de deshacer y guarda `project.godot`. Editar `project.godot` a mano se rechaza. |
| Tilemaps | `tileset_add_atlas`, `tileset_add_scenes`, `tilemap_set_cells`, `tilemap_paint_terrain`, `tilemap_clear` (+ `tilemap_get` para leer) | Sobre un `TileMapLayer`: una textura pasa a atlas (un tile por celda no transparente, colisión completa opcional), tiles por celda o rectángulo, terrenos ya armados en el TileSet, y un mapa ASCII con leyenda para leerlo. Cada cambio es un paso de deshacer. |
| Animación | `animation_create`, `animation_set_track`, `animation_remove`, `sprite_frames_set` (+ `animation_get` para leer) | Animaciones de un AnimationPlayer con pistas de valor (keys convertidas al tipo de la propiedad) y de método; SpriteFrames de un AnimatedSprite2D/3D desde imágenes o una hoja. Cada cambio es un paso de deshacer. |
| Recursos | `create_resource`, `set_resource_properties` (+ `get_resource` para leer) | Archivos `.tres` de una clase de Godot o de un `class_name` del proyecto, con sub-recursos inline (`{"type": "StyleBoxFlat", …}`) y arrays tipados. Los cambios son un paso de deshacer y se guardan. Escribir un `.tres` a mano se rechaza. |
| Archivos | `move_file`, `copy_file`, `delete_file` | Mover o renombrar manteniendo el uid y reescribiendo cada referencia `res://`; copiar como recurso nuevo (también desde fuera del proyecto); borrar solo si nada lo referencia (a la papelera). `mv`, `cp` y `rm` sobre archivos del proyecto se rechazan. |
| Ejecutar | `run_scene` | Corre una escena (con `inputs` simulados, si querés) y devuelve los errores reales. |
| | `capture_game_frame` | Un frame del juego corriendo. |
| | `stop_scene` | Lo detiene. |
| Juego en vivo | `game_tree`, `game_get` (lectura), `game_set`, `game_call`, `game_wait`, `game_input` | Con el juego corriendo (lanzado por `run_scene`, o un run manual con «Usar el autoload de playtest también al correr el juego a mano»): el árbol de nodos vivo, leer y cambiar propiedades, llamar métodos, esperar a que una expresión sea verdadera o a que se emita una señal, y mandar teclas, acciones, clicks y joystick. Los cambios son solo en vivo; los archivos de escena no cambian. Los errores del juego que aparecen mientras tanto vuelven con el resultado. |

## Detalles

- **Deshacer**: cada edición de escena es un paso del deshacer del editor. La tarjeta de la tool en el chat tiene **↶ deshacer** mientras nadie haya tocado la escena después.
- **Escenas abiertas**: al agente se le indica que edite las escenas abiertas con estas tools, nunca en disco.
- **Playtests**: `run_scene` agrega un autoload temporal que captura errores, frames e inputs simulados, y lo quita en cuanto arranca el juego. Si el editor se cae a mitad de un playtest, el próximo arranque lo limpia. El export nunca lo incluye.
- **Límites**: **Settings → Servidor MCP** fija los caracteres por resultado, el lado máximo de las imágenes y las carpetas fuera del proyecto que el agente puede leer y escribir.
- **Seguridad**: el servidor escucha solo en `127.0.0.1`, pide un token que cambia en cada arranque (**Regenerar token** en Settings), y el log lo enmascara.
