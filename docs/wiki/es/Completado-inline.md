# Completado inline

[Inicio](Inicio.md) · [English](../en/Inline-completion.md)

Sugerencias en gris mientras escribís en el Script Editor. Por defecto son **solo locales**: sin IA, sin el agente, y nada sale del editor. Un LLM es opcional.

## Teclas

| Tecla | Qué hace |
|---|---|
| **Tab** | Acepta la sugerencia (un solo paso de deshacer). Sin sugerencia, o con el popup de autocompletado de Godot abierto, Tab funciona como siempre. |
| **Ctrl+→** | Acepta palabra por palabra. |
| **Esc** | La descarta. |
| **Alt+\\** | Pide una a mano (en modo híbrido, directo al LLM). |
| **Alt+Shift+\\** | Prende o apaga el completado. |

## De dónde salen las sugerencias

- **Reglas de Godot**:
  - `@onready var ` propone los nodos hijos de la escena con tipo y ruta;
  - `func _` propone los métodos virtuales de la clase base con su firma;
  - `$` y `%` proponen rutas de nodos;
  - hay reglas para acciones de input, grupos, `.connect(`, `func _on_`, `preload("` y `extends `.
- **Líneas del proyecto**: una línea que se repite en otros scripts se sugiere al escribir su comienzo. Si se repite con otro nombre (`enemy_` en lugar de `player_`), se adapta. En una línea vacía se sugiere lo que suele seguir a la de arriba, o un bloque corto si el proyecto siempre lo escribe igual.
- **n-gram**: un modelo de los tokens del proyecto completa la línea mientras está seguro.
- **Historial**: lo que escribiste en esta sesión.

Las sugerencias de varias líneas muestran la primera en el lugar y el resto en una caja debajo. Si dos opciones están demasiado cerca, no se muestra nada.

El índice del proyecto se arma en segundo plano y deja `addons/` fuera de las líneas sugeridas.

## Settings

**Settings → Completado** edita todo y muestra la latencia (p50/p95) y la tasa de aceptación de cada fuente en la sesión. Los cambios se aplican sin reiniciar.

- encendido o apagado;
- debounce, umbral y margen;
- varias líneas y máximo de líneas;
- cada fuente por separado;
- corpus extra: carpetas de otros proyectos tuyos que solo entrenan el n-gram.

El indicador **● Completado** en la barra del Script Editor muestra el estado: verde activo, ámbar esperando al LLM, rojo error, gris apagado. Un clic lo prende o lo apaga.

## Con un LLM (opcional)

Elegí el modo en **Settings → Completado**:

- **Solo local** (por defecto): sin red.
- **Híbrido**: lo local sale como siempre. Si no hay nada local, después de 200 ms sin tipear se le pide al LLM.
- **Solo LLM**.

| Perfil | URL por defecto | Notas |
|---|---|---|
| Ollama | `http://127.0.0.1:11434` | `ollama pull qwen2.5-coder:1.5b-base` (los modelos `-base` traen FIM). |
| llama.cpp (`llama-server`) | `http://127.0.0.1:9931` | Endpoint `/infill`; cargá un modelo con FIM. |
| Codestral | `https://api.mistral.ai` | Key en `MISTRAL_API_KEY`. |
| OpenAI-compatible (LM Studio, vLLM…) | `http://127.0.0.1:1234` | `/v1/completions` con la plantilla FIM del modelo. |
| Gemini (experimental) | Google | Key en `GEMINI_API_KEY`; sin FIM, más lento. |

- Las keys nunca se guardan: el perfil tiene el **nombre** de la variable de entorno, y el valor se lee del entorno del editor en cada pedido.
- Un perfil remoto avisa que el código alrededor del cursor, y un resumen del proyecto (nodos, autoloads, acciones), se envía a ese servidor.
- Las sugerencias del LLM terminan con un punto chico; se puede apagar.
- El Agent Log (canal `cmp`) registra latencias y tamaños, nunca código, salvo que prendas **Log "raw"**.

## Pedirle un cambio al agente (Alt+I)

A diferencia de las sugerencias de arriba, esto va al agente. Seleccioná código (o dejá el cursor donde tiene que ir algo) y apretá **Alt+I**, o clic derecho → **Pedirle un cambio al agente…**. Escribí lo que querés («hacé constantes estas variables», «agregá un salto con coyote time») y apretá Enter.

El pedido va a la sesión de la pestaña activa del dock, con el archivo, las líneas y el código seleccionado, y el agente contesta solo con el código nuevo. Aparece como diff junto al código: **Aceptar** reemplaza la selección (o inserta en el cursor) como un solo paso de Ctrl+Z, sin guardar el archivo; **Rechazar** lo deja como estaba. Si cambiaste ese código mientras el agente contestaba, la propuesta no se aplica. El pedido y la respuesta quedan también en el chat. Tiene que haber una sesión iniciada en el dock, y libre (no en medio de un turno).
