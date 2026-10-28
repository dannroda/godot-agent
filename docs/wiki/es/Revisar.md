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

## Comentarios de un pull request de GitHub

**De un PR de GitHub…** en el panel de hallazgos trae los comentarios de revisión de un pull request como hallazgos, con el [CLI de GitHub](https://cli.github.com) (`gh`, con sesión iniciada con `gh auth login`). Escribí su número, o dejalo vacío para el pull request de la rama actual. Cada comentario en una línea de un archivo de este proyecto pasa a ser un hallazgo con su texto y su autor, marcado en el Script Editor como los del agente; las respuestas dentro de un hilo quedan afuera. Desde ahí, **Arreglar en modo Construir** le pide al agente que los resuelva. Solo lee: no publica nada en GitHub.

La otra dirección es opcional: con **Ofrecer pushear y abrir un pull request de GitHub al cerrar una copia aparte** (Settings → Servidores MCP, apagado por defecto), al cerrar una [sesión en una copia aparte](Como-funciona.md#varias-sesiones-a-la-vez) aparece **Pushear y abrir un PR**, que pushea su rama a `origin` y abre un pull request contra la rama en la que estabas.
