# Revisión de arquitectura (M11, m13-03)

Fecha: 2026-10-29. Alcance: la estructura de `addons/godot_agent/` (unas 38 mil líneas de GDScript):
capas, responsabilidades de los scripts grandes, acoplamiento entre plugin, dock y sesión, dónde vive
el estado, cómo se suma un agente nuevo y qué cubren los tests. Sigue a la revisión de patrones
(`patrones.md`, P1).

Gravedad: **alta** (frena cambios o ya generó bugs), **media** (costo de mantenimiento real),
**baja** (prolijidad), **info** (está bien o es un riesgo aceptado).

## Resumen

| # | Gravedad | Hallazgo | Propuesta |
|---|---|---|---|
| A1 | alta | Lo propio de cada agente está repartido en seis lugares, con ramas por nombre | Un adaptador por agente |
| A2 | alta | `SessionController` hace de todo (1585 líneas, 80 funciones) | Fachada + colaboradores inyectados |
| A3 | media | `plugin.gd` mezcla el armado con comportamiento (1421 líneas; `_enter_tree` de 192) | El plugin solo arma; cada flujo a su dueño |
| A4 | media | `agent_dock.gd` arma y maneja todas las secciones del dock (1513 líneas) | Una vista por sección, con señales hacia arriba |
| A5 | baja | El plugin llama métodos privados del dock | API pública del dock |
| A6 | baja | Algunos objetos de dominio leen `EditorInterface` por su cuenta | Inyectarlo desde el plugin |
| A7 | info | Dónde vive el estado | Está bien separado |
| A8 | info | Cobertura de tests por capa | Buena en el dominio; fina en ACP y transporte |

## Capas: lo que está bien

`acp/`, `transport/`, `oneshot/` y `extensions/` no dependen del editor ni de la interfaz; `session/`
lo hace en un solo lugar (un valor por defecto inyectable en `session_coordinator.gd`). El dominio
(sesión, One-shot, cuota, revisión) es RefCounted y se prueba sin escena: es la base para todo lo que
sigue.

## A1 · Un adaptador por agente

Hoy, sumar o cambiar un agente toca:
- `session_controller.gd`: qué comando de cuota corre (`/usage` para Antigravity, `/status` para
  Codex, por `agentInfo.name`) y cómo lee la cuenta (Claude por su CLI, Codex por `_auth/status_update`).
- `core/quota_monitor.gd`: el parseo de la salida de cada uno (`parse_antigravity_usage`,
  `parse_codex_status`…).
- `extensions/skill_catalog.gd` y `claude_extensions.gd`: dónde guarda skills e instrucciones cada uno.
- `plugin.gd` y `agent_dock.gd`: «¿es Claude?» mirando si el comando contiene `claude`.

Propuesta: `AgentAdapter` (RefCounted, estrategia) con lo que cambia por agente —`matches(agent_info,
profile)`, el comando de cuota y su lectura, cómo saber la cuenta, el tipo de extensiones y los
archivos de instrucciones— y uno genérico por defecto. El controller pide el adaptador al conectar y
deja de preguntar por nombres. Sumar un agente pasa a ser un archivo. Además destraba A2: la consulta de
cuota que no se pudo sacar en P1 queda «correr el comando del adaptador sin mostrarlo».

## A2 · `SessionController` como fachada

Hoy maneja el protocolo ACP, los permisos, las terminales, el login, la cuota, el historial, abrir y
retomar sesiones, las preguntas del agente, Remote Control y la verificación al terminar el turno.
Propuesta, en este orden (cada paso con sus tests pasando):
1. `PermissionBroker`: `authorize`, `_ask_user`, `_on_request_permission`, el autorizador de
   terminales y `Preauthorizations` (ya separado en P1).
2. `UsageQuery` sobre A1: correr el comando del adaptador y no mostrar sus mensajes.
3. `SessionLifecycle`: `session/new`, `load`, `resume`, `list`, `close`, `delete` e historial.
El controller queda como la fachada que usan el dock y el plugin, con la misma API pública.

## A3 · `plugin.gd` solo arma

`_enter_tree` (192 líneas) y `_exit_tree` (87) están bien como raíz de composición, pero el archivo
además coordina el One-shot con el dock (líneas ~897–1012), los cambios por turno (~1013–1094) y las
pestañas de sesión (~1095 en adelante). Propuesta: que cada flujo viva con su dueño
(`OneShotRun`/la pantalla, `TurnSnapshots`, `SessionTabs`/`SessionCoordinator`) y el plugin solo cree
y conecte.

## A4 · Una vista por sección del dock

`agent_dock.gd` arma el encabezado, el estado, el historial, el panel de revisión, Remote Control, los
diálogos de login y de exportar, y la importación de GitHub, además de conectar el composer y la
conversación. Propuesta: cada sección en su script (como ya están `composer.gd`, `review_panel.gd`,
`session_tabs.gd`), con señales hacia el dock, que queda como el que reparte.

## A5 · API pública del dock

`plugin.gd` llama `dock.call(&"_on_new_session_pressed")` y `await dock.call(&"_start_session")`.
Propuesta: `new_session()` y `start_session()` públicos.

## A6 · `EditorInterface` en el dominio

`core/acp_registry.gd` (la carpeta de instalación), `core/i18n.gd` (el idioma del editor),
`core/asset_store.gd` (prender y apagar plugins) y `core/error_collector.gd` lo leen solos. Todos tienen
guardas de editor y no rompen los tests, pero el plugin es quien debería pasárselo.

## A7 · Estado

| Dónde | Qué | Alcance |
|---|---|---|
| EditorSettings `godot_agent/*` | agentes, color, cuota, completado, idioma | usuario, todos los proyectos |
| `addons/godot_agent/config/project_config.tres` | permisos, presupuestos de One-shot, criterios | proyecto (versionable) |
| `user://godot_agent/` | sesiones, historial de prompts, runs de One-shot, actualizaciones, MCP shim | usuario, por proyecto |
| `res://.godot_agent/` | `assets.json` y reportes de turno | proyecto |
| `~/.local/share/godot/godot_agent/agents/` | agentes descargados del registro | usuario, compartido |

Está bien separado. `project_config.tres` se carga con `load()`, pero es del propio proyecto.

## A8 · Tests

Archivos de test que tocan cada capa: `session` 27, `core` 26, `ui` 21, `mcp` 13, `oneshot` 7,
`completion` 7, `acp` 3, `review` 3, `transport` 2, `extensions` 2, `editor` 2. El dominio está bien
cubierto; `acp` y `transport` (el protocolo y los procesos) tienen pocos para lo que pesan, aunque los
completan los checks de integración contra el agente falso (`acp_session_check`).
