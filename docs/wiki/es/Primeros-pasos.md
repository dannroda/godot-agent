# Primeros pasos

[Inicio](Inicio.md) · [English](../en/Getting-started.md)

## 1. Instalar

1. Copiá `addons/godot_agent/` a la carpeta `addons/` de tu proyecto.
2. **Proyecto → Configuración del proyecto → Plugins** → habilitá **Godot Agent Harness**.
3. Aparecen tres superficies:
   - el dock **Agent**, a la derecha: la conversación;
   - el panel inferior **Agent Log**: lo que va y viene entre el editor y el agente, por canal;
   - la pantalla **Agent** en la barra de arriba, junto a 2D/3D/Script: la vista del One-shot.

Requisitos: Godot 4.6 o más nuevo y, para Claude Code, Node.js con `npx`.

## 2. Abrir una sesión

Tocá **Iniciar sesión** en el dock. El perfil por defecto lanza Claude Code con su adapter ACP (`npx -y @agentclientprotocol/claude-agent-acp`); la primera vez, `npx` lo descarga.

Si el agente no tiene una cuenta con sesión iniciada, el aviso de error trae un botón por cada forma de login que ofrezca. Con Claude Code son **Iniciar sesión · Claude Subscription** e **Iniciar sesión · Anthropic Console**:

- el botón corre el login del propio agente y abre el navegador;
- si el navegador no se abre, **Abrir enlace** lo abre; si la página te da un código, **Pegar código…** se lo pasa al login;
- al terminar, el agente se relanza y la sesión abre.

Las credenciales las guarda el agente, igual que `claude` en una terminal. El harness no las lee, y el código pegado no va al log.

Otros agentes (Gemini CLI, Codex, el tuyo) se configuran en **Settings → Agentes**: ver [Settings](Settings.md#perfiles-de-agentes).

## 3. El dock

- **Header**: perfil de agente, título de la sesión, **Historial**, **Nueva sesión** y **Settings**.
- **Modos**: Preguntar · Revisar · Construir · Auto · One-shot (ver [Modos y permisos](Modos-y-permisos.md)).
- **Conversación**: Markdown (tablas, listas, citas y bloques de código con resaltado y botón para copiar), tool calls agrupados (con su duración), diffs, tarjetas de permiso y el plan del agente. Lo que hace un subagente queda plegado dentro de su tarjeta `Agent`. Un clic en una captura que sacó el agente la abre en grande: rueda para el zoom, arrastrar para moverla y **Guardar PNG…** para quedártela. Los links a archivos los abren en el editor (`archivo.gd#L42` va a la línea) y los links a imágenes, en el mismo visor.
- **Composer**:
  - **Enter** envía; **Ctrl+Enter** o **Shift+Enter** bajan de línea; **Esc** detiene el turno;
  - con el agente trabajando, Enter deja el mensaje **en cola**, arriba del composer. Cada mensaje en cola se puede editar o quitar. Cuando termina el turno sale el siguiente. Si el turno se cancela o falla, la cola espera **Enviar ahora**;
  - **↑** / **↓** en la primera o la última línea recorren los prompts que enviaste en este proyecto;
  - `/` al comienzo lista los comandos del agente, y `@` los nodos de la escena y los archivos del proyecto. Arrastrar nodos desde el dock Escena los escribe como `@ruta`. Cuatro menciones traen contexto al enviar: `@errors` (los errores y warnings del editor), `@output` (el final del panel Output), `@game` (el árbol de nodos del juego en marcha) y `@docs:Clase` (la referencia de la API de una clase, por ejemplo `@docs:CharacterBody2D`);
  - **+ contexto** adjunta la escena abierta, la selección, un archivo del proyecto, una captura del viewport o una **captura del juego** que está corriendo. La del juego necesita el autoload de playtest: está en los runs que lanza el agente, y en los tuyos si activás **Usar el autoload de playtest también al correr el juego a mano** (Settings → Servidor MCP);
  - **Ctrl+V** con una imagen en el portapapeles la adjunta (por ejemplo, una captura de pantalla), igual que con archivos copiados en el gestor de archivos. Arrastrar archivos desde el panel FileSystem también los adjunta. Van hasta 6 imágenes por mensaje, achicadas a 1280 px;
  - selector de modelo y medidor de contexto. La opción por defecto de Claude Code muestra el modelo que usa, por ejemplo **Opus 5.5 (por defecto)**.
- **Cuota del plan**: los dos anillos al lado del medidor de contexto. El de afuera es la ventana de 5 horas y el de adentro, la semanal; se ponen amarillos en el umbral de aviso y rojos en el límite. Con el mouse encima se ven los porcentajes y la hora de reinicio. Claude Code informa la cuota con el primer mensaje de cada sesión, así que hasta entonces los anillos quedan grises.

## 4. Primeros prompts

- *Preguntar*: "¿qué hace el script del Player cuando lo golpean?"
- *Construir*: "agregá un Label WaveLabel al HUD que muestre la oleada actual". Mirá cómo cambia el árbol de la escena; **Ctrl+Z** deshace cada paso.
- *Construir*: "corré la escena principal, apretá espacio dos veces y decime qué errores aparecen". El agente corre el juego con inputs simulados y lee los errores reales.

## 5. Idioma de la interfaz

La interfaz está en inglés y en español, y sigue el idioma del editor (**Editor → Configuración del editor → Interfaz → Idioma del editor**). Para forzar uno, usá **Settings → Interfaz → Idioma**; el cambio se aplica al reabrir el editor.

Lo que lee el agente (sus instrucciones y las descripciones de las tools) va siempre en inglés; el agente te responde en tu idioma.
