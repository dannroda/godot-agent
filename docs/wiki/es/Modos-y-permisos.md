# Modos y permisos

[Inicio](Inicio.md) · [English](../en/Modes-and-permissions.md)

## Modos

| Modo | Qué hace el agente |
|---|---|
| **Preguntar** | Responde sobre el proyecto. Puede leer; no puede editar ni correr nada. |
| **Revisar** | Revisa escenas y scripts y devuelve hallazgos (bug, estructura, rendimiento, estilo), que aparecen como marcas en el Script Editor. Ver [Revisar](Revisar.md). |
| **Construir** | Edita escenas y scripts y corre el juego, pidiendo permiso según la matriz de abajo. |
| **One-shot** | Persigue un objetivo entero con presupuestos, checkpoints y playtests, en la pantalla Agent. Ver [One-shot](One-shot.md). |

Cambiar de modo cambia también el modo del agente, si lo publica: Preguntar y Revisar usan `plan`, y Construir y One-shot usan `default`.

## Permisos

Cada acción cae en un grupo, y cada grupo tiene una decisión por modo: **Permitir**, **Preguntar** o **Denegar**.

- **Preguntar** (la decisión, no el modo) muestra una tarjeta en el chat con lo que quiere hacer el agente (y el diff, si es una edición). Si nadie contesta en 5 minutos (configurable), se deniega.
- **Denegar** deniega sin preguntar y le dice al agente por qué.

Valores por defecto:

| Grupo | Preguntar | Revisar | Construir | One-shot |
|---|---|---|---|---|
| Lectura | Permitir | Permitir | Permitir | Permitir |
| Diagnóstico | Permitir | Permitir | Permitir | Permitir |
| Editar escenas | Denegar | Denegar | Preguntar | Permitir |
| Editar archivos | Denegar | Denegar | Preguntar | Permitir |
| Ejecutar el juego | Denegar | Preguntar | Preguntar | Permitir |
| Shell / comandos | Denegar | Denegar | Preguntar | Preguntar |
| Project settings, export y addons | Denegar | Denegar | Preguntar | Permitir |

## Escrituras que se saltean el editor

En cualquier modo, el harness rechaza solo, sin tarjeta:

- comandos de shell que escriben archivos del proyecto: redirecciones (`>`), `tee`, `sed -i`, `dd of=`, y scripts de Python, Node, Ruby o Perl que abren archivos para escribir;
- escribir a mano un `.tscn`, `.uid` o `.import`, con las herramientas de archivos del agente o por el acceso a archivos del editor.

El chat muestra un aviso «Rechazado: …». Al agente se le indica que escriba los scripts con sus propias herramientas de archivos (el harness las pasa por el editor) y las escenas con las tools `godot.*`. Los comandos que escriben fuera del proyecto, por ejemplo en `/tmp`, siguen la matriz de abajo como siempre.

La matriz se cambia en **Settings → Permisos**. Se guarda solo lo que difiere de los valores por defecto, en la config del proyecto (`project_config.tres`), así se puede commitear y compartir con el equipo.
