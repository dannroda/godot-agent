# Cómo funciona

[Inicio](Inicio.md) · [English](../en/How-it-works.md)

```
┌──────────────── Editor de Godot ─────────────┐
│  Dock / pantalla Agent      Script Editor    │
│        │                          ▲          │
│  SessionController ── EditorSync ─┘          │
│     │       ▲                                │
│     │ ACP   │ MCP (HTTP, 127.0.0.1 + token)  │
└─────┼───────┼────────────────────────────────┘
      ▼       │
   Proceso del agente (Claude Code, Gemini CLI…)
```

## El proceso del agente y ACP

El agente corre como un proceso hijo del editor. El harness habla con él por stdin/stdout con el [Agent Client Protocol](https://agentclientprotocol.com) (JSON-RPC):

- `initialize` y `session/new` abren una sesión en la carpeta del proyecto;
- `session/prompt` manda lo que escribís, más un contexto corto del harness: la versión de Godot, el proyecto, el modo y sus reglas;
- el agente devuelve en streaming texto, pensamientos, tool calls, diffs y su plan, y el dock los muestra a medida que llegan;
- `session/request_permission` pide permiso antes de actuar, y el harness contesta según la [política de permisos](Modos-y-permisos.md);
- `fs/read_text_file` y `fs/write_text_file` pasan por el editor, así se respetan los scripts abiertos y los buffers sin guardar;
- `session/cancel` corta un turno (Esc).

Los pipes se leen en el hilo principal del editor, sin threads, así que recargar un script del addon nunca tira el editor.

El agente recibe además la ruta del binario del editor abierto, en `$GODOT` y en sus instrucciones. Cuando corre Godot por línea de comandos (`--headless`, `--import`, tests) usa la misma versión que tu editor, y no otro `godot` del PATH.

## El servidor MCP: las herramientas del editor

El harness levanta un servidor MCP en `127.0.0.1` (nunca en otra interfaz), con un token Bearer que cambia en cada arranque, y se lo pasa al agente al abrir la sesión. Si un agente no soporta MCP por HTTP, un puente stdio que corre con el mismo binario de Godot hace de intermediario.

Por ahí el agente llama a las tools `godot.*`: leer el árbol de la escena, editar nodos, correr el juego, capturar frames, leer errores. Ver [Herramientas del editor](Herramientas-del-editor.md). Cada llamada pasa antes por la política de permisos.

## El editor al día

Claude Code también escribe archivos con sus propias herramientas, directo al disco. El harness lo detecta y actualiza el editor, sin el diálogo de "modificado fuera de Godot":

- los scripts abiertos se actualizan en el Script Editor;
- las escenas abiertas sin cambios sin guardar se recargan. En Godot 4.6, que no puede saber si una escena tiene cambios sin guardar, aparece un aviso con **Recargar escena**;
- los cambios a `project.godot` (acciones de input, autoloads, escena principal…) se aplican a la configuración del proyecto en el editor, y el editor los guarda.

Una escena o un script con cambios sin guardar nunca se pisa: aparece un aviso de conflicto con el diff.

## Sesiones e historial

Cada sesión se guarda en `user://godot_agent/sessions/` una vez por turno, sin imágenes y con los resultados largos recortados. **Historial** en el dock lista las sesiones de este proyecto:

- si el agente soporta `session/load` (Claude Code sí), la sesión se reanuda de verdad: el agente recupera su contexto;
- si no, la conversación se ve en modo solo lectura, y escribir abre una sesión nueva.

## La cuota del plan

Claude Code informa el uso de las ventanas de tu plan (5 horas y semanal). El harness lo muestra, avisa al 75 %, pausa el One-shot al 90 % y, al llegar al límite, bloquea el envío con una cuenta regresiva hasta que la ventana se reinicia. No estima la cuota con tokens, no consulta endpoints no documentados y no lee archivos del agente. Ver [One-shot → cuota](One-shot.md#cuota-del-plan).

## El Agent Log

El panel inferior muestra todo por canal:

- `proc`: el proceso del agente;
- `acp`: los mensajes del protocolo;
- `mcp`: las tool calls;
- `fs`: lecturas y escrituras por el editor;
- `perm`: las decisiones de permisos;
- `quota`;
- `cmp`: las latencias del completado.

Los secretos se enmascaran. Es el primer lugar donde mirar cuando algo no anda: ver [Problemas frecuentes](Problemas-frecuentes.md).
