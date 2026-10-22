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
