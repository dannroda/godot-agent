# Godot Agent Harness

[English](README.md) · **Español**

Addon de editor para Godot 4 que conecta un agente de código (Claude Code, Gemini CLI, Codex o cualquier agente que hable [ACP](https://agentclientprotocol.com)) con el editor. Conversás con el agente en un dock, y el agente puede ver y cambiar el proyecto con las herramientas del propio editor:

- leer escenas y scripts, la selección y los errores;
- editar nodos y propiedades, cada cambio un paso de deshacer;
- correr el juego con inputs simulados y mirar capturas de frames (un clic en el chat la abre en grande);
- revisar código y dejar hallazgos en el Script Editor.

Tiene cinco modos: **Preguntar**, **Revisar**, **Construir**, **Auto** (Construir que corre sin preguntar los comandos de shell que tus reglas permiten) y **One-shot**. El One-shot persigue un objetivo entero ("Pong de 2 jugadores con puntaje") con plan, presupuestos, checkpoints git y playtests.

- 100 % GDScript con tipos estáticos: sin GDExtension ni dependencias.
- Solo vive en el editor: nada del addon llega a un juego exportado.
- El harness nunca hace merge ni push, no guarda claves y no lee las credenciales del agente.
- La interfaz está en inglés y en español: sigue el idioma del editor y se cambia en Settings.
- El chat muestra el Markdown del agente: tablas, listas, citas y bloques de código con resaltado y botón para copiar.

> Estado: los hitos M0–M8c de [`GODOT_AGENT_HARNESS_SPEC.md`](GODOT_AGENT_HARNESS_SPEC.md) están implementados. El avance y cómo se verificó cada parte: [`docs/progress.md`](docs/progress.md). Las decisiones de diseño: [`docs/decisions.md`](docs/decisions.md).

## Documentación

La [wiki](docs/wiki/es/Inicio.md) explica cómo funciona el harness y cómo usar cada parte:

- [Primeros pasos](docs/wiki/es/Primeros-pasos.md): instalar, iniciar sesión, primera conversación.
- [Cómo funciona](docs/wiki/es/Como-funciona.md): el proceso del agente, ACP, el servidor MCP y cómo el editor se mantiene al día.
- [Modos y permisos](docs/wiki/es/Modos-y-permisos.md)
- [Herramientas del editor (MCP)](docs/wiki/es/Herramientas-del-editor.md)
- [One-shot](docs/wiki/es/One-shot.md): plan, spec, presupuestos, checkpoints, cuota, cambio de cuenta, informe.
- [Revisar](docs/wiki/es/Revisar.md)
- [Completado inline](docs/wiki/es/Completado-inline.md), local o con un LLM.
- [Settings y perfiles](docs/wiki/es/Settings.md): dónde se guarda cada cosa, perfiles de agentes, export y actualizar.
- [Problemas frecuentes](docs/wiki/es/Problemas-frecuentes.md): limitaciones conocidas por versión de Godot.

## Requisitos

- **Godot 4.6 o más nuevo.** Se prueba en 4.6.3, 4.7.2 y 4.8-beta1.
- **Un agente ACP.** Para Claude Code:
  - Node.js con `npx`. El perfil por defecto corre `npx -y @agentclientprotocol/claude-agent-acp`;
  - una cuenta de Claude Code: la que ya usa `claude` en la máquina, una con la que iniciás sesión desde el dock, o una API key en una variable de entorno.
- **git**, solo para los checkpoints del One-shot.
- Linux, macOS o Windows.

## Instalación

1. Bajá `godot-agent-harness-vX.Y.Z.zip` del [último release](https://github.com/dannroda/godot-agent/releases/latest) y descomprimilo en tu proyecto, de forma que `addons/godot_agent/` quede en su carpeta `addons/`. Desde un clon del repo, copiá `addons/godot_agent/`; no copies `addons/godot_agent_dev/`: es el plugin de pruebas del repo.
2. **Proyecto → Configuración del proyecto → Plugins**: habilitá **Godot Agent Harness**.
3. Aparecen tres superficies:
   - el dock **Agent** (a la derecha);
   - el panel inferior **Agent Log**;
   - la pantalla **Agent** (arriba, junto a 2D/3D/Script), donde corre el One-shot.
4. En el dock, **Iniciar sesión**. Con Claude Code, la primera vez `npx` descarga el adapter.

El addon no escribe nada en `project.godot`. La única excepción es un autoload de playtest temporal, que existe solo mientras el harness corre el juego.

## Para empezar

- **Preguntar** algo del proyecto: "¿cuántos nodos tiene Main.tscn?". El agente lee la escena con las herramientas del editor; en este modo no puede cambiar nada.
- **Construir**: "agregá un Label WaveLabel al HUD y conectá la señal wave_started". El cambio aparece en el árbol de la escena y Ctrl+Z lo deshace. Cada acción que cambia algo pide permiso antes.
- **Revisar** una carpeta: los hallazgos aparecen como marcas en el Script Editor, con **Aplicar arreglo**.
- **One-shot**: elegilo en el dock, escribí el objetivo en la pantalla Agent y arrancá. El agente planifica, construye, prueba el juego y deja cada paso como un checkpoint git en su propia rama.

## Desarrollo

```sh
G=/ruta/a/godot   # 4.6.3, 4.7.2 o 4.8
$G --headless --path . --import
$G --headless --path . --script tests/run_all.gd            # unitarios
$G --headless --path . --script tests/acp_session_check.gd  # ACP contra el agente falso
$G --headless --path . --script tests/oneshot_check.gd      # loop del One-shot
tests/run_in_xvfb.sh $G --godot-agent-cycle-test             # editor en Xvfb: habilitar/deshabilitar 5 veces sin huérfanos
```

Los textos de la interfaz se escriben en inglés en el código, con `I18n.t("…")`. Las traducciones están en `addons/godot_agent/i18n/<idioma>.po`, y `tests/unit/test_i18n.gd` falla si un texto no tiene traducción al español. Lo que lee el agente (prompts, descripciones y resultados de las tools) va solo en inglés.

### CI y releases

- **CI** (`.github/workflows/ci.yml`): en cada push a `main` y en cada pull request corren, headless, los unitarios, el check de ACP y el del One-shot, en Godot 4.6.3, 4.7.2 y 4.8-beta1.
- **Release** (`.github/workflows/release.yml`): se corre a mano desde **Actions → Release → Run workflow**, eligiendo `patch`, `minor`, `major` o una versión exacta `X.Y.Z`. Corre el CI, sube `version` en `addons/godot_agent/plugin.cfg`, commitea "Release vX.Y.Z" en `main` con el tag `vX.Y.Z` y publica un release de GitHub con el zip del addon y, como notas, los commits desde el tag anterior.
- La versión vive solo en `plugin.cfg`: el `clientInfo` de ACP y el `serverInfo` del MCP la leen de ahí.

El tablero de tareas está en `compass/` ([`docs/tareas.md`](docs/tareas.md) es su export).
