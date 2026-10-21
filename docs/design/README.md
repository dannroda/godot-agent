# Diseño de UI (mockup de referencia)

Fuente: artifact de diseño "Godot Agent Harness UI", https://claude.ai/chat/f88dea66-401f-4ccc-92af-c85b98fcf7d1?artifact=c94c1e9f-2037-475f-830c-e0671d0ef62d (copia en `mockup/`, versión 1792552961-9a9d). Los `.dc.html` son el formato del canvas de diseño: se leen como HTML; `support.js` no está incluido.

La spec manda (§9): respetar la **estructura** del mockup. Los estilos salen del theme del editor (`EditorInterface.get_editor_theme()`), con **un solo color de acento** para lo del agente: `#f0a85a` (ámbar) por defecto. El mockup ofrece `#d97757`, `#6cb4ff` y `#7fd98b` como alternativas.

## 1 · Dock del agente, modo Construir (`Main.dc.html`) → M1/M2

Dock a la derecha, como pestaña junto a Inspector/History/Signals, con un punto de acento en la pestaña cuando hay actividad.

- **Header**: botón de perfil (✦ "Claude Code" ▾), título de sesión ("Oleadas de asteroides") y botones de icono: historial, nueva sesión y ajustes (con `aria-label`/tooltip).
- **Selector de modo**: control segmentado de 4: Preguntar · Revisar · **Construir** · One-shot.
- **Mensajes**:
  - burbuja del usuario a la derecha (fondo `#33405a`);
  - texto del agente sin burbuja, con `code` en mono y color de acento;
  - **grupo de tool calls** colapsable: "4 herramientas · 1,2 s", cada fila con ✓/✗, nombre (tools MCP `godot.*` en violeta `#b493ff`, las del agente en gris claro), resumen y "↶ undo" a la derecha;
  - **tarjeta de diff**: ruta, `+14` verde, `−3` rojo, botón "Abrir en Script", primeras líneas con fondo rojo/verde y "⋯ 11 líneas más";
  - **tarjeta de permiso**: borde y fondo ámbar, escudo + "Permiso: ejecutar la escena", descripción y botones "Permitir una vez" (relleno de acento), "Siempre en esta sesión" y "Denegar" (texto rojo).
- **Composer**:
  - chips: escena actual, "Selección: Spawner" y "+ contexto";
  - textarea con placeholder "Pedile algo… @ para nodos y archivos, / para comandos";
  - fila inferior: iconos de mencionar, adjuntar captura y comandos, medidor "41k / 200k", botón de modelo ("Opus") y enviar (cuadrado de acento con flecha).
- **Agent Log** (panel inferior): mono, `hora · canal · mensaje`. Colores por canal: `acp` azul `#6cb4ff`, `mcp` violeta `#b493ff`, `fs` blanco, `perm` acento. La pestaña lleva un punto de acento.

Extras del mockup que tocan docks del editor (no son del dock propio; evaluar en M4/M7):
- chip de estado "Claude Code · trabajando" junto a los botones de play (`add_control_to_container(CONTAINER_TOOLBAR)`);
- marcas "editado" / "+ agente" en el árbol de escena y puntos en FileSystem para archivos tocados;
- toast sobre el viewport: "El agente agregó HUD/WaveLabel · Ctrl+Z para deshacer".

## 2 · Pantalla principal Agent, One-shot (`OneShot.dc.html`) → M6

- **Barra superior**: "Objetivo · one-shot", estado "En curso · fase 4 de 7", el texto del objetivo, tres presupuestos con barra (Tiempo 18/45 min, Tokens 412k/1,5M, Playtests 3/8) y botones Pausar y Detener.
- **Columna Plan**: ✓ hechas, ● en curso (con subtítulo "corrigiendo tras playtest #3"), ○ pendientes, cada una con detalle en gris. Nota: "Podés editar el plan mientras corre: el agente lo relee al terminar cada tarea."
- **Columna Actividad**: eventos con hora, nombre de tool y resumen, más el razonamiento del agente en texto. Input "Guiar al agente" + Enviar.
- **Columna derecha**:
  - Último playtest: captura con pie "Playtest #3 · frame 1820 · 30 s";
  - Verificaciones: checklist ✓/✗;
  - Checkpoints: `cpN` + nombre + "Volver acá".
- **Barra inferior**: "11 archivos cambiados · 4 escenas · 7 scripts", `+486 −37`, "Revisar cambios" y "Aceptar todo".
- El FileSystem muestra marcas A/M en los archivos tocados.

## 3 · Revisión en el Script Editor (`Review.dc.html`) → M5

- **Script Editor**: banda "Revisión del agente · solo lectura". Las líneas con hallazgo llevan un ● en el gutter y color de fondo. La tarjeta del hallazgo va **inline debajo de la línea**: etiqueta de severidad (BUG), título, explicación, sugerencia en mono y botones "Aplicar arreglo", "Preguntar" y "Descartar".
- La lista de scripts abiertos muestra la cantidad de hallazgos por archivo.
- **Dock en modo Revisar**: título "Revisión de src/ · 7 scripts", aviso "Herramientas de escritura deshabilitadas…", contadores por severidad (2 bugs, 1 orden de ejecución, 1 rendimiento) y una lista de hallazgos (`archivo:línea`, severidad, texto). Botones "Exportar a CLAUDE.md" y "Arreglar en modo Construir".

## 4 · Settings (`Settings.dc.html`) → M7

Sección "Project Settings › Agent Harness" con navegación: Agentes · Herramientas · Permisos · Contexto y CLAUDE.md · Checkpoints · Registro.

- **Agentes** (ACP sobre stdio): tarjetas por perfil con comando, estado ("conectado · v1" / "sin iniciar") y "Editar", más "+ Agregar agente".
- **Permisos**: la matriz grupo × modo de la spec §7 con pastillas sí / preguntar / no, y la URL del server MCP (`http://127.0.0.1:<puerto>/mcp`).
- Toggle "Crear un checkpoint git antes de cada tarea de One-shot". Botones Cancelar y Guardar.

## Diferencias con la spec (a resolver cuando toque)

| Mockup | Spec | Decisión |
|---|---|---|
| El perfil Claude Code usa `npx @agentclientprotocol/claude-agent-acp` | `@zed-industries/claude-agent-acp`, a verificar con `npm view` | Se resuelve en M1 con `npm view`; gana el paquete real. |
| Perfil "Agente propio" con `sidecar/run.sh` | Nada de bash-isms; comandos configurables | Solo es un ejemplo; los perfiles no traen scripts `.sh`. |
| Severidades: bug, orden, rendimiento | `bug \| order \| perf \| style` | Se usan las cuatro de la spec; la UI las traduce (bug, orden, rendimiento, estilo). |
| Settings dentro de Project Settings | Diálogo propio o sección en Project Settings | En M7. Una sección real en Project Settings escribiría en `project.godot` (prohibido): probablemente un diálogo propio con la misma navegación. |
