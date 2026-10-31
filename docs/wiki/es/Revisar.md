# Revisar

[Inicio](Inicio.md) · [English](../en/Review.md)

En el modo **Revisar**, el agente revisa escenas y scripts y devuelve hallazgos en lugar de editar.

1. Elegí **Revisar** en el dock y pedí: "revisá los scripts de `player/`" o "revisá la escena abierta".
2. El agente lee con las herramientas del editor y responde con sus hallazgos. Cada hallazgo tiene:
   - una categoría: bug, estructura, rendimiento o estilo;
   - un archivo y una línea;
   - una explicación y, cuando puede, un arreglo.
3. Los hallazgos aparecen:
   - como **marcas en el Script Editor**, en las líneas correctas, con una tarjeta: **Aplicar arreglo**, **Preguntar** (sigue la conversación sobre ese hallazgo) y **Descartar**;
   - en la **lista de hallazgos** del dock, para saltar a cada uno.

**Aplicar arreglo** pasa a Construir y le pide al agente ese arreglo. La edición pasa por la matriz de permisos como cualquier otra. Si el turno termina bien, el hallazgo sale de la revisión. La lista de hallazgos del dock también puede pedir varios arreglos juntos.

## Exportar a CLAUDE.md

La revisión se puede exportar al `CLAUDE.md` del proyecto como convenciones, por ejemplo "tipado estático en todos lados" o "no usar `get_parent()` para comportamiento". Antes ves una vista previa. Desde ahí, el agente las respeta en todos los modos.

## Playtest

**Playtest…** en el panel de hallazgos pregunta qué comprobar jugando («que el jugador pueda saltar a la segunda plataforma»). El agente corre el juego, manda el input por frame de física para que el run se pueda repetir, lee el estado en vivo y captura frames, y contesta con un veredicto que aparece en el chat: **pasó**, **falló** con los pasos para reproducirlo, o **no se pudo probar** con el motivo, más lo que observó. No cambia el proyecto. Con **Grabar un video del run**, `run_scene` guarda un AVI en `res://.godot_agent/playtests/`: mientras graba, el juego corre a 30 fps fijos y se cierra solo al final.

![Un veredicto de Playtest que falló en el chat, con su evidencia, lo que puede haber cambiado sin jugar, lo que vieron los detectores y los pasos para reproducirlo, y un hallazgo en el panel con Mostrar en la escena, Verificar un arreglo y No es un bug](https://raw.githubusercontent.com/dannroda/godot-agent/main/docs/images/es/playtest.png)

El harness contrasta el veredicto con lo que hizo el agente. Un **pasó** o **falló** cuenta como **no se pudo probar** si el agente nunca jugó, o si el veredicto depende de cómo se ve algo y no capturó ningún frame. El veredicto también lista lo que puede haber cambiado en el juego sin jugar (`game_set`, `game_call`, `game_script`), lo que vieron los detectores y por qué no hay video si lo pediste.

En la misma caja podés pedir tres cosas: verificar algo, lograr un objetivo o explorar («recorré este nivel y decime qué se ve mal», que contesta **explorado**). Un error de script no termina el playtest: el juego sigue y el error queda en la lista.

Los **detectores** corren dentro del juego y avisan de lo que el agente no estaba mirando, con una imagen del momento: transforms con NaN, cuerpos fuera del mundo, un jugador cayendo durante 8 s, un frame de más de 0,75 s y un texto como `12/10` en el HUD.

Los **hallazgos** del playtest y de los detectores van al panel de hallazgos, donde cada uno tiene **Mostrar en la escena**, **Verificar un arreglo** y **No es un bug**. Uno marcado como que no es un bug no vuelve a aparecer. **Repetir el playtest** repite el último tal cual, y **Reproducir la grabación** en el veredicto pasa los frames del run dentro del editor. El diálogo también fija un **tope de tiempo**, recordado por proyecto: al agente se le dice cuánto queda, pero el turno no se corta.

**Memoria**: los playtests guardan lo que verificaron de tu juego (controles, mecánicas, trampas) y los scripts que sirvieron en `res://.godot_agent/playtests/`, y al siguiente se le dice qué archivos cambiaron desde entonces, para que vuelva a comprobar lo que puede haber quedado viejo. Borrá esa carpeta para empezar de cero.

## Comentarios de un pull request de GitHub

**De un PR de GitHub…** en el panel de hallazgos trae los comentarios de revisión de un pull request como hallazgos, con el [CLI de GitHub](https://cli.github.com) (`gh`, con sesión iniciada con `gh auth login`). Escribí su número, o dejalo vacío para el pull request de la rama actual. Cada comentario en una línea de un archivo de este proyecto pasa a ser un hallazgo con su texto y su autor, marcado en el Script Editor como los del agente; las respuestas dentro de un hilo quedan afuera. Desde ahí, **Arreglar en modo Construir** le pide al agente que los resuelva. Solo lee: no publica nada en GitHub.

La otra dirección es opcional: con **Ofrecer pushear y abrir un pull request de GitHub al cerrar una copia aparte** (Settings → Servidores MCP, apagado por defecto), al cerrar una [sesión en una copia aparte](Como-funciona.md#varias-sesiones-a-la-vez) aparece **Pushear y abrir un PR**, que pushea su rama a `origin` y abre un pull request contra la rama en la que estabas.
