# One-shot

[Inicio](Inicio.md) · [English](../en/One-shot.md)

El One-shot le da al agente un objetivo entero ("Pong de 2 jugadores con puntaje", "un shooter top-down con tres tipos de enemigos") y lo deja trabajar solo. El harness lo mantiene en carril con:

- un plan y un spec;
- presupuestos;
- checkpoints git a los que podés volver;
- playtests con capturas;
- verificaciones que tiene que reportar.

## Arrancar un run

1. Elegí **One-shot** en el dock: se abre la pantalla **Agent**.
2. Escribí el objetivo. El editor crece con la pantalla, así que entran objetivos largos.
3. Revisá los presupuestos (tiempo, tokens, playtests) y las opciones:
   - **Crear un checkpoint git antes de cada tarea de One-shot**: un commit por tarea en una rama del agente;
   - **Revisar el spec antes de construir**: el agente escribe primero el spec y te espera.
4. Arrancá. Si hay cambios sin commitear, el harness pregunta antes; esos cambios quedan en un commit "WIP" en la rama del agente, nunca en la tuya.

Nunca corras un One-shot sobre un repo donde no quieras ramas nuevas. Para probarlo, `tests/make_sandbox.sh <carpeta>` arma un proyecto descartable.

## Cómo avanza un run

1. **Spec**: el agente escribe `spec.md`, una descripción de alto nivel del juego: mecánicas, loop de juego, dirección visual y qué es "terminado". Con **Revisar el spec antes de construir**, el run espera en "Spec para revisar": la columna del plan muestra el spec, **Editar** lo abre y **Aprobar spec** arranca la construcción. Si en cambio escribís en el chat, el agente lo corrige y vuelve a esperar.
2. **Plan**: el agente convierte el spec en tareas. Podés editar el plan mientras corre; el agente lo relee al terminar el turno. Cada tarea muestra cuánto tardó, y la que está en curso cuenta en vivo.
3. **Construir y verificar**: en cada tarea, el agente edita, corre el juego (`run_scene`), mira frames (`capture_game_frame`), lee errores y reporta **verificaciones** (`pass`, `fail`, `pending`). Mantiene `progress.md` al día.
4. **Checkpoints**: cada tarea (o cada playtest, si el agente no informa un plan) es un commit `cpN` en la rama `agent/<fecha>`.
   - **Volver acá** deja el proyecto exactamente como en ese checkpoint y pausa el run;
   - **Retomar** sigue desde ahí.
5. **Fin**: cuando el plan está hecho y las verificaciones pasan, o se agota un presupuesto, el agente escribe un reporte final y el run termina.
   - **Revisar cambios** lista los archivos; con doble clic se ve el diff contra el inicio;
   - **Aceptar todo** hace un commit final en `agent/<fecha>`. El merge lo hacés vos;
   - **Informe** muestra lo que midió el harness (ver abajo).

## La pantalla Agent

- **Barra de arriba**:
  - objetivo y fase;
  - barras de presupuesto: cuota del plan, tiempo, tokens, playtests;
  - la regla de cuota activa;
  - **Presupuestos**, **Cambiar de cuenta**, **Spec y progreso**, **Pausar**/**Retomar** y **Detener**.
- **Plan**: las tareas con su estado y su duración.
- **Actividad**: todo lo que pasó, con hora:
  - tool calls con su duración;
  - turnos ("Turno 3 · 4 min 12 s · 9 tools");
  - checkpoints, playtests, eventos de cuota y de presupuesto;
  - tu guía.
- **Costado**: la última captura de playtest, las verificaciones y la lista de checkpoints.
- **Barra de abajo**: resumen de archivos cambiados, **Revisar cambios**, **Aceptar todo**.

## Guiar al agente

Con un One-shot en curso, lo que escribís en el chat del dock le llega al agente del run. Si el agente está en medio de un turno, el mensaje espera:

- la actividad muestra **guía · en cola: …** y el chat lo avisa;
- al terminar el turno sale, y la actividad muestra **guía · enviado: …**.

## Presupuestos

- **Tiempo**, **tokens** y **playtests**.
- Al 80 % avisa. Al 100 % le pide al agente el reporte final y el run termina.
- **Presupuestos**, en la barra de arriba, los cambia con el run en curso: 0 es sin límite, e **Ilimitado** los saca a todos. Si el run iba a cerrar por presupuesto y el nuevo alcanza, sigue.

## Loops

Si el agente se repite sin avanzar, el run le pide otro enfoque. Eso incluye:

- un check que falla igual;
- una tool call que falla con los mismos argumentos;
- el mismo cambio una y otra vez.

Si vuelve a pasar, el run se pausa y espera que lo guíes. Las repeticiones se ajustan en **Settings → One-shot**.

## Archivos de spec, progreso y QA

Viven en `.godot_agent/oneshot/<id>/` dentro del proyecto: `spec.md`, `progress.md` y `qa-<n>.md`.

- **Spec y progreso** los abre en pestañas, con **Mostrar en carpeta** y **Abrir con editor externo**. Tocar su ruta en el chat abre el mismo visor.
- Si el run tiene que seguir en una sesión nueva, el agente los relee.
- La carpeta tiene un `.gdignore`: no entra al dock FileSystem ni al export. Viaja en los checkpoints de la rama del agente; si no la querés en tu rama, borrala antes del merge.

## Criterios del juego

El agente sabe de entrada cómo se va a evaluar lo que hace:

- jugabilidad;
- funcionalidad;
- visual y feel;
- código.

Cada criterio tiene un peso y un puntaje mínimo de 0 a 10, que se cambian en **Settings → One-shot**.

## Cuota del plan

Si el agente informa la cuota de su plan (Claude Code lo hace):

- **Aviso** al 75 %.
- **Pausa** al 90 %: el run se pausa al terminar la tarea o el turno en curso, para no cortar una tarea a la mitad. Si nada de eso pasa en 10 minutos, o la cuota llega al 98 %, corta el turno igual y se pausa con un checkpoint `-quota`. El banner dice cuándo va a pausar.
- **Limitado**: al llegar al límite, el envío queda bloqueado con una cuenta regresiva, y un checkpoint `cpN-quota` guarda el estado. Cuando la ventana se reinicia, el run retoma solo o espera tu confirmación (**Settings → One-shot y cuota**). **Retomar** prueba enseguida.

### Cambiar de cuenta

Si tenés otra cuenta, no hace falta esperar el reinicio. Abrí **Cambiar de cuenta** en la barra de arriba:

- **Iniciar sesión con otra cuenta · <método>** corre el login del agente desde el editor. Al terminar, el run sigue;
- **Ya inicié sesión con otra cuenta (en una terminal)**: para cuando lo hiciste vos (`claude` y después `/login`).

En los dos casos, el harness relanza el agente para que tome las credenciales nuevas, olvida la cuota de la cuenta anterior y retoma **la misma sesión** (`session/load`): el agente conserva su contexto.

## Cerrar el editor con un run en curso

El run se guarda en `user://` mientras corre. Si el editor se cierra o se cae:

- al reabrirlo, el run vuelve a la pantalla Agent con su actividad y un aviso en el chat;
- si estaba esperando la cuota, sigue esperando y retoma solo a la hora del reinicio. **Retomar** o **Cambiar de cuenta** evitan la espera;
- si no, queda en pausa: **Retomar** reabre la sesión del agente (o una nueva con el resumen del plan);
- **Detener** lo da por terminado.

El botón **Reintentar** del dock, durante un One-shot, retoma el run en su propia sesión.

## El informe

Cuando el run termina, **Informe** muestra lo que midió el harness, no lo que dice el agente:

- duración por tarea;
- tiempos: trabajando, turnos (promedio y el más largo), esperando la cuota, en pausa o revisando el spec;
- tokens y playtests;
- tools con usos, fallas y tiempo;
- cuántas veces falló cada verificación;
- permisos, errores, pausas por cuota, loops, cambios de cuenta y archivos cambiados.

Se guarda en `user://godot_agent/oneshot/<id>.report.json` para comparar corridas, y **Copiar Markdown** lo copia.

## Sin git

Sin git, o con un repo sin commits, no hay checkpoints. El harness lo avisa antes de empezar.
