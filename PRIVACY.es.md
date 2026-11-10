# Privacidad y uso de datos

[English](PRIVACY.md) · **Español**

Godot Agent Harness es un addon del editor. No tiene servidor, ni cuenta, ni telemetría. No manda el proyecto a ningún lado por su cuenta: lo hace el agente que elegís, a su proveedor y con las condiciones de ese proveedor. Esta página dice qué va adónde, qué queda en tu computadora y cómo borrarlo.

## Lo que recibe el agente

El agente (Claude Code, Codex, Google Antigravity u otro agente ACP) corre en tu computadora como un programa aparte y habla con su propio proveedor (Anthropic, OpenAI, Google…). Todo lo que recibe puede llegar a ese proveedor:

- lo que escribís en el dock y lo que adjuntás: archivos, nodos de la escena, imágenes, capturas del juego o del editor;
- el contexto que el dock agrega a un prompt: la escena abierta y los nodos seleccionados (los podés sacar antes de mandar);
- lo que lee con las tools `godot.*`: escenas, scripts, ajustes del proyecto, errores del editor y del juego, el panel Output, frames del juego corriendo;
- las instrucciones del harness: nombre y carpeta del proyecto, versión de Godot y la ruta del binario del editor;
- todo lo que el agente lee por su cuenta con sus propias herramientas (archivos, comandos de shell), según los permisos que configures.

Cómo guarda o usa esos datos el proveedor lo deciden el proveedor y tu cuenta con él, no el harness. Mirá sus políticas: [Anthropic](https://www.anthropic.com/legal/privacy), [OpenAI](https://openai.com/policies/privacy-policy/), [Google](https://policies.google.com/privacy).

Remote Control (de Claude Code) comparte la sesión a través de claude.ai, con tu cuenta de Claude. Está apagado hasta que lo prendés.

## Conexiones que hace el addon

| Cuándo | Adónde | Qué se manda |
|---|---|---|
| Al abrir el editor, una vez por día (Ajustes → Interfaz → *Buscar una versión nueva al abrir el editor*) | `api.github.com` (los releases de este repositorio) | Un pedido de la lista de releases. Nada del proyecto. Actualizar baja el zip de GitHub. |
| Abrís el registro de ACP o agregás un agente desde ahí | `cdn.agentclientprotocol.com` y la URL de descarga del agente | Un pedido de la lista y, al agregar uno, su descarga (verificada con el sha256 del registro cuando lo trae). |
| Buscás, mirás o instalás un addon del Asset Store | `store.godotengine.org` | Tu búsqueda y tu versión de Godot. |
| Completado inline con un LLM (opcional, apagado por defecto) | El endpoint del perfil de LLM que configures | El código alrededor del cursor y un resumen del proyecto (rutas de nodos, clases, autoloads, acciones de input). Los perfiles locales (Ollama, LM Studio, llama.cpp) usan `127.0.0.1`; los remotos (Mistral, Gemini) necesitan una key y le mandan el código a ese proveedor. |
| Importás comentarios de un PR de GitHub, o subís una copia aparte como PR | GitHub, con tu CLI `gh` y su login | Lo que `gh` manda para esos comandos. |
| Servidores MCP que agregás en Ajustes | Esos servidores | Lo que el agente le manda a sus tools, con sus propios permisos. |

El completado inline local (el que viene por defecto) nunca sale del editor.

## El servidor MCP del editor

El servidor MCP del addon escucha solo en `127.0.0.1`, con un token que cambia cada vez que arranca el editor, así que otras computadoras no llegan. El token se enmascara en todos los lugares donde podría verse (ver [Secretos](#secretos)). Un programa chico para los agentes que usan MCP por stdio vive en `user://godot_agent_mcp_shim/`; el agente recibe el token por ese programa o en la configuración MCP de la sesión, porque lo necesita para llamar al editor.

## Secretos

El harness trata como secretos estos valores (de 8 caracteres o más): el token del servidor MCP (y el que recibe cada pestaña del dock); en el perfil del agente, las variables de entorno cuyo nombre parece un secreto (`key`, `token`, `secret`, `password`, `passwd`, `auth`…), escritas o tomadas de una `$VARIABLE`; la variable de API key del agente (`ANTHROPIC_API_KEY` en Claude Code) cuando está en el entorno del editor, porque el agente hereda ese entorno; y, en los servidores MCP que agregás, todo valor de entorno o de header tomado de una `$VARIABLE`, se llame como se llame. Donde uno de ellos podría verse aparece `«secret»` en su lugar: en el Agent Log, en el chat (lo que dice el agente, los resultados de sus herramientas, los diffs y comandos de las tarjetas de permiso), en las tarjetas de error y el tooltip del estado, en el historial de sesiones en disco, y en la actividad, el informe y los runs guardados del One-shot. Una sesión guardada antes de registrar un secreto se enmascara al reabrirla.

Dos cosas no se enmascaran, a propósito. Lo que el agente escribe o ejecuta lleva el valor real: un archivo que escribe o un comando que lanza se romperían con `«secret»` adentro (lo que de esa escritura o ese comando se ve en el chat sí va enmascarado). Y los formularios y enlaces de login que el agente manda como pedidos para que respondas quedan como están, porque tienen que seguir funcionando (un enlace dentro de un mensaje del agente se enmascara como el resto del mensaje). El agente recibe el token y las claves, y lo que hace con ellos es cosa suya: mirá su documentación. Lo que escribís vos queda como lo escribiste, en el chat y en el historial de sesiones: no pegues claves en el chat.

## Lo que queda en tu computadora

`user://` es la carpeta del proyecto en los datos de usuario del editor (en Linux, `~/.local/share/godot/app_userdata/<proyecto>/`).

| Qué | Dónde | Notas |
|---|---|---|
| Historial de sesiones (las conversaciones, para reabrirlas) | `user://godot_agent/sessions/` | Las últimas 100 sesiones. Las capturas no se guardan; los textos largos se recortan; los secretos se enmascaran antes de escribir. |
| Prompts que mandaste (↑ en el composer) | `user://godot_agent/prompt_history.json` | |
| Runs del One-shot | `user://godot_agent/oneshot/` | Los últimos 20. Los secretos se enmascaran. |
| Actualizaciones del addon y descargas del Asset Store en curso | `user://godot_agent/update/`, `user://godot_agent/assets/` | En `update/` quedan copias de la versión anterior del addon. |
| Perfiles de agentes, ajustes de MCP, del completado e idioma | Ajustes del editor, prefijo `godot_agent/` | Los perfiles nombran variables de entorno, nunca sus valores (Ajustes rechaza un valor literal en una variable con nombre de secreto). |
| Agentes bajados del registro de ACP | La carpeta de datos del editor, `godot_agent/agents/` | Compartidos por todos los proyectos. |
| Permisos, reglas, presupuestos y servidores MCP del proyecto | `res://addons/godot_agent/config/project_config.tres` | Es parte del proyecto: commitealo o no, como prefieras. Sin keys. |
| Reportes de turno, videos y frames de playtest, lo que los playtests aprendieron del juego (notas, scripts, regresiones guardadas, hallazgos marcados como que no son bugs), spec y avance del One-shot, lista de assets instalados | `res://.godot_agent/` | Dentro del proyecto. Nunca se exporta con el juego. |
| Snapshots de cada turno, para ver qué cambió y volver atrás | refs de git `refs/godot-agent/turns/*` en el repositorio del proyecto | Refs locales: no se suben salvo que las subas vos. Las últimas 60 por sesión. |
| Agent Log | Solo en memoria | Hasta 2000 entradas, se borra al cerrar el editor. Sale del editor solo si lo copiás. |

## Lo que el harness nunca hace

- Nunca guarda API keys ni lee los archivos de credenciales del agente. Para mostrar qué cuenta usa un agente le pregunta al propio CLI del agente (en Claude Code, `claude auth status`); el email se ve en el dock pero no se escribe en el log. Para nombrar las cuentas en el menú del agente lee solo el email del `.claude.json` de Claude Code en cada carpeta de configuración (nunca `.credentials.json` ni tokens).
- Nunca hace merge en git, y nunca hace push por su cuenta. La única excepción es **Pushear y abrir un PR**: apagado por defecto (Settings, «Ofrecer pushear y abrir un pull request de GitHub al cerrar una copia aparte»), y solo si lo elegís al cerrar una copia aparte. Pushea la rama de esa copia a `origin` y abre el pull request con `gh`.
- Nunca manda estadísticas ni datos de uso.
- Nada del addon llega a un juego exportado.

## Borrar tus datos

- Conversaciones: borralas una por una desde el historial de sesiones del dock, o borrá `user://godot_agent/sessions/`.
- Todo lo que el addon guarda de un proyecto: borrá `user://godot_agent/` y `res://.godot_agent/`.
- Snapshots de turnos: `git for-each-ref --format='%(refname)' refs/godot-agent/ | xargs -n1 git update-ref -d`.
- Agentes bajados: borrá `godot_agent/agents/` de la carpeta de datos del editor.
- Lo que guardó el proveedor del agente: pedíselo al proveedor, con la cuenta que usaste.

Problemas de seguridad: ver [SECURITY.md](SECURITY.md).
