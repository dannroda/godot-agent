# Revisión de patrones de Godot (M11, m13-02)

Fecha: 2026-10-29. Alcance: el GDScript de `addons/godot_agent/` (unas 25 mil líneas) contra la
checklist de revisión de Godot 4: acoplamiento, responsabilidades, ciclo de vida, señales y `await`,
recursos y archivos, colecciones sin tope, rendimiento. No aplica lo que es de juegos (FSM, pools,
recursos de gameplay) ni shaders (el addon no tiene).

Gravedad: **alta** (ya causó un bug o lo va a causar en el uso normal), **media** (falla en un caso
real pero acotado), **baja** (riesgo chico o costo de mantenimiento).

## Resumen

| # | Gravedad | Hallazgo | Estado |
|---|---|---|---|
| P1 | alta | Seis scripts de más de 1100 líneas con muchas responsabilidades | en parte (sigue en m13-03) |
| P2 | alta | Lo que espera un permiso o una pregunta corría dentro de quien la respondió | arreglado |
| P3 | media | `run_all` no contaba los errores de script como fallos | arreglado |
| P4 | media | `await` largos en el dock sin comprobar que siga en el árbol | arreglado |
| P5 | baja | Escrituras directas sin temporal (revisión, historial de prompts, One-shot, instrucciones) | arreglado |
| P6 | baja | `AcpClient._cancelled_outgoing` crece sin tope | arreglado |
| P7 | baja | El `_process` del completado corre cada frame aunque esté apagado | arreglado |

## P1 · Scripts gigantes

`session/session_controller.gd` (1657 líneas), `oneshot/oneshot_run.gd` (1552),
`ui/dock/agent_dock.gd` (1513), `plugin.gd` (1421), `ui/main_screen/agent_main_screen.gd` (1352) y
`ui/settings/settings_dialog.gd` (1118). El controller, por ejemplo, maneja el protocolo ACP, los
permisos, las terminales, el login, la cuota, el historial y las preguntas del agente. P2 salió de ahí:
la espera de un permiso, la tool que guarda la escena y el clic del dock quedaron encadenados sin que
se viera. Arreglo: sacar piezas con límites claros, empezando por los permisos del controller
(`authorize`, `_ask_user`, la preautorización y el autorizador de terminales). El resto es tema de la
revisión de arquitectura (m13-03).

Hecho: la preautorización salió a `session/preauthorizations.gd` (`command_key`, `grant`,
`consume_write`, `consume_command`, `write_paths`); el controller bajó de 1657 a 1585 líneas.
No se hizo, y queda para m13-03 con este orden: la consulta de cuota (`/usage`, `/status`) está atada
al enrutado de `session/update` (sus mensajes no van al chat) y al bloqueo de `send_prompt`, así que
sacarla pide antes decidir cómo se enrutan esas actualizaciones; después los permisos de ACP
(`_on_request_permission`, `_ask_user`, el autorizador de terminales) y, en el dock y el plugin, el
armado de cada sección en su propio script.

## P2 · Lo que sigue a una respuesta corría dentro de quien respondió

`PermissionRequest.resolved` y `ElicitationRequest.resolved` se emiten en el acto, y el `await` del
controller se reanuda dentro de ese emit: la tool que esperaba el permiso (guardar la escena, editar
nodos) corría dentro del clic del botón, o dentro de `stop()` con la sesión a medio cerrar. Con Godot
4.8-beta1 el editor se cayó en `BaseButton::on_action_event` después de un `save_scene` (m12-39).
Arreglo: `_ask_user` y `_on_create_elicitation` esperan un frame después de la respuesta, salvo
cuando el agente retiró el pedido (`$/cancel_request`), que tiene que contestarse ya. La señal sigue
siendo inmediata para lo que es estado (la lista de pendientes, la marca de la pestaña).

## P3 · Errores de script que no fallaban los tests

Un error de script (índice fuera de rango, llamada inválida) corta el test, y `run_all` lo contaba como
aprobado: `test_untouched_optional_fields_are_left_out` pasaba sin haber probado nada desde que se
escribió. Arreglo: un `Logger` (`OS.add_logger`) junta los errores de tipo script y el test en curso
falla con el mensaje y la línea. Los `push_error` y los errores del motor no cuentan: los tests los
provocan a propósito.

## P4 · `await` en el dock

Abrir una sesión, expandir una mención `@`, capturar el juego o traer los comentarios de un PR pueden
tardar; si mientras tanto se cierra la pestaña, el dock seguía después del `await` fuera del árbol.
Arreglo: `if not is_inside_tree(): return` después de cada uno.

## P5 · Escrituras atómicas

`AtomicFile.write_text` (temporal al lado y rename) reemplaza las dos copias que había
(`session_history`, `oneshot_store`) y se usa también en `review_store` (CLAUDE.md), el historial de
prompts del composer, los archivos del One-shot y la pestaña Instrucciones.

## P6 y P7

`_cancelled_outgoing` guarda las últimas 256 marcas. El completado apaga su `_process` cuando está
apagado; los controllers de pestañas cerradas se sueltan al volver a prenderlo.

## Lo que se revisó y está bien

Cada `remove_child` va con su `queue_free`; la conversación tiene tope (250 vistas) y el Agent Log
también; las lambdas de los timers no tocan objetos liberados (Godot desconecta la señal); no hay
`load()` de archivos que vengan de afuera (el caché de documentación lo escribe el editor, y el
`str_to_var` de la sonda de playtest corre en el juego del usuario con valores del agente); el
historial y el One-shot ya guardaban con temporal.
