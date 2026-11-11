@tool
extends RefCounted
## Etiquetas de los prompts que manda el harness en nombre del usuario (m12-44). El agente recibe el
## texto en inglés sin cambios; en el chat esa entrada se ve como del harness: atenuada, en una
## línea con esta etiqueta (traducida al mostrarla) y el prompt plegado. La entrada y el historial
## guardan el msgid en inglés, así el chat sale en el idioma de quien lo abre.
## Criterio: todo prompt que no es exactamente lo que el usuario escribió lleva una etiqueta.

const ONESHOT_START := "One-shot · goal and instructions"  # i18n
const ONESHOT_RESUME := "One-shot · resume the run"  # i18n
const ONESHOT_SUMMARY := "One-shot · summary for the new session"  # i18n
const ONESHOT_NEXT_TASK := "One-shot · next task in the plan"  # i18n
const ONESHOT_KEEP_GOING := "One-shot · keep going with the goal"  # i18n
const ONESHOT_SPEC_APPROVED := "One-shot · spec approved"  # i18n
const ONESHOT_SPEC_CHANGE := "One-shot · your message, as a change to the spec"  # i18n
const ONESHOT_PLAN_EDIT := "One-shot · the plan you edited"  # i18n
const ONESHOT_FINAL_REPORT := "One-shot · final report"  # i18n
const ONESHOT_LOOP := "One-shot · loop warning"  # i18n
const ONESHOT_QA := "One-shot · QA evaluation"  # i18n
const ONESHOT_QA_FIX := "One-shot · fixes from QA"  # i18n
const ONESHOT_REMOTE_OFF := "One-shot · turn off Remote Control"  # i18n
## Lo que el run tenía en la cola al cerrarse el editor: al reabrir no se sabe cuál era.
const ONESHOT := "One-shot"
const TURN_CHECK := "Automatic check after the turn"  # i18n
const REVIEW_QUESTION := "Review · question about a finding"  # i18n
const REVIEW_FIX := "Review · fix the findings"  # i18n
const REVIEW_PLAYTEST := "Review · playtest"  # i18n
const INLINE_EDIT := "Inline edit from the Script Editor"  # i18n
const SUPERVISOR := "What the supervisor saw while the editor was closed"  # i18n
const OTHER_SESSION := "Message from another agent session"  # i18n
## «Arreglar con el agente» en el aviso de un run manual que paró con un error (m11-55).
const RUN_ERROR := "Fix the error of the game you ran"  # i18n
## La tarjeta del plan (m11-22): lo que el usuario cambió con «Editar», o «Seguir planeando…».
const PLAN_EDIT := "Plan · the changes you made"  # i18n
const PLAN_KEEP_PLANNING := "Plan · keep planning"  # i18n
## «Planificar» / `/plan` (m11-58): el pedido del plan, y la aprobación de un plan presentado en bloque.
const PLAN_REQUEST := "Plan · what to plan"  # i18n
const PLAN_APPROVED := "Plan · approved, build it"  # i18n
## «Denegar con motivo» en una tarjeta de permiso.
const DENY_REASON := "Denied with a reason"  # i18n
## «Nueva sesión con resumen» (m11-35): el pedido del resumen para la sesión nueva.
const HANDOFF := "Handoff · summary for a new session"  # i18n
