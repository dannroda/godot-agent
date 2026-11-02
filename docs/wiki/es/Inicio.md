# Wiki de Godot Agent Harness

[English](../en/Home.md) · **Español**

Godot Agent Harness pone un agente de código adentro del editor de Godot. El agente corre como un proceso aparte (Claude Code, Google Antigravity, Codex…). Solo Claude Code está probado de punta a punta, y solo en Linux: Codex, Antigravity, macOS y Windows todavía no se verificaron. Anda con proyectos en GDScript y en C#. El harness habla con él, muestra la conversación en un dock y le da herramientas del editor: lee escenas, edita nodos con deshacer, corre el juego y mira frames. Todo cambio pasa por el editor y por una política de permisos.

## Páginas

| Página | Qué cubre |
|---|---|
| [Primeros pasos](Primeros-pasos.md) | Instalar, iniciar sesión, el dock, los primeros prompts, el idioma de la interfaz. |
| [Cómo funciona](Como-funciona.md) | Las piezas: proceso del agente, ACP, servidor MCP, sincronización con el editor, sesiones. |
| [Modos y permisos](Modos-y-permisos.md) | Preguntar, Revisar, Construir, Auto y One-shot, la matriz de permisos y Remote Control. |
| [Herramientas del editor](Herramientas-del-editor.md) | Las tools `godot.*` que puede llamar el agente y qué hace cada una. |
| [One-shot](One-shot.md) | Construir un objetivo entero: spec, plan, presupuestos, checkpoints, cuota, cambio de cuenta, informe. |
| [Revisar](Revisar.md) | Revisión de código con hallazgos en el Script Editor. |
| [Completado inline](Completado-inline.md) | Sugerencias en gris mientras escribís, locales o con un LLM. |
| [Settings](Settings.md) | Dónde vive cada setting, perfiles de agentes, export, actualizar el addon. |
| [Problemas frecuentes](Problemas-frecuentes.md) | Problemas comunes y limitaciones por versión de Godot. |

## Reglas de base

- El harness nunca hace merge, y nunca hace push por su cuenta: la única excepción es el opcional [Pushear y abrir un PR](Revisar.md#comentarios-de-un-pull-request-de-github), apagado por defecto. El One-shot trabaja en su propia rama y vos decidís qué se mergea.
- Nunca guarda API keys: los perfiles nombran variables de entorno.
- Nunca lee las credenciales del agente. De su configuración lee solo lo que necesita: por ejemplo el email que guarda Claude Code, para nombrar las cuentas en el menú del agente.
- El servidor MCP escucha solo en `127.0.0.1`, con un token que cambia en cada arranque.
- Nada del addon llega a un juego exportado.
- Sin telemetría. Qué le llega al agente y a su proveedor, qué guarda el addon y cómo borrarlo: [Privacidad y uso de datos](https://github.com/dannroda/godot-agent/blob/main/PRIVACY.es.md).
