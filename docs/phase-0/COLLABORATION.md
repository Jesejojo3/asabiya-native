# Protocolo de colaboración y aprobación

## Roles

- **Implementador previsto: GPT-6 Astra / Codex.** Inspecciona, propone cambios en una rama, conserva la fuente, ejecuta comprobaciones, registra evidencia y responde hallazgos mediante commits identificables. La designación describe el flujo solicitado; no certifica qué modelo está activo en una sesión.
- **Auditor independiente previsto: Claude Opus 5.5 / Claude Code.** Recibe el repositorio y la PR por intervención del usuario, trabaja desde el commit exacto, reproduce pruebas, inspecciona causalidad y busca regresiones. La disponibilidad del modelo y su acceso se verifican en su propia sesión.
- **Responsable humano del proyecto.** Entrega los paquetes entre herramientas, decide alcance y resuelve desacuerdos; aprueba integración, tag y avance de fase.

No existe comunicación automática entre Codex y Claude en este protocolo. El usuario entregó íntegro el primer informe, con veredicto APROBADA CON CORRECCIONES sobre HEAD 3e5f18351421eef1a855a24b30352cf7c42deda8. Esa revisión no aprueba los commits correctivos aún inexistentes entonces. El usuario entregará manualmente el paquete de segunda revisión.

## Flujo por rama y PR

1. Leer el alcance aprobado y la base actual. Crear rama temática desde un commit conocido. Nunca escribir cambios directamente en `main`.
2. Entregar una PR pequeña, con problema, comportamiento esperado, decisiones, pruebas ejecutadas y pendientes. Los cambios de balance o mecánicas nuevas no se mezclan con el port de compatibilidad.
3. Congelar el SHA de la versión que revisará Claude. El usuario comparte PR, SHA y `CLAUDE_REVIEW.md`. Si la rama cambia, indicar nuevos commits e invalidar la aprobación de lo modificado hasta que se revise.
4. Claude realiza revisión independiente y comunica hallazgos con severidad, ruta/línea, escenario mínimo, evidencia y resultado esperado. Si propone un arreglo, usar otra rama/PR; no modificar la rama de implementación silenciosamente ni integrar sus propios hallazgos sin revisión.
5. Codex reproduce cada hallazgo y registra: aceptado/corregido, desacuerdo con evidencia, o pendiente por decisión humana. Relacionar cada corrección con su commit y prueba. No marcar hallazgos resueltos sólo porque los revisó el implementador.
6. El usuario entrega los commits nuevos al auditor para verificar correcciones; guardar el SHA auditado y el dictamen final. La ausencia de comentarios no implica aprobación.
7. El humano aprueba la integración después de las comprobaciones requeridas y la revisión. Ningún agente autoaprueba su propio trabajo o inicia otra fase por el solo hecho de abrir una PR.

## Severidades y salida del auditor

| Nivel | Criterio | Tratamiento propuesto |
|---|---|---|
| Bloqueante | Fuente alterada, `main` modificado sin autorización, pérdida causal, determinismo falso, alcance excedido | No integrar hasta resolver y volver a revisar. |
| Alta | Arquitectura impide pruebas sin GPU, omite dependencias o acepta divergencias discretas | Corregir antes de Fase 1 o decisión humana explícita y documentada. |
| Media | Falta prueba, ambigüedad de contrato o riesgo con mitigación incompleta | Registrar responsable, criterio de cierre y fase; no declarar probado. |
| Baja | Claridad documental o mantenimiento | Corrección acotada o seguimiento documentado. |

Formato del dictamen: SHA revisado; resumen; hallazgos enumerados; comandos reproducidos y resultados; áreas no inspeccionadas; recomendación de aceptar, pedir cambios o aceptar condicionadamente. La recomendación de Claude no sustituye la aprobación humana.

## Puerta entre Fase 0 y Fase 1

Al completar Fase 0 detener implementación. No crear `legacy-v0.6` hasta integrar la importación con aprobación; no adelantar el esqueleto ejecutable Go, UI o mecánicas. El siguiente alcance debe aprobarse expresamente. Si no hay conexión a la fuente o al repositorio, solicitarla y no reconstruir contenido supuesto.

Segunda puerta obligatoria: las correcciones van en la misma rama y PR #1, conservando commits previos. No integrar ni iniciar Fase 1 hasta una segunda aprobación de Claude y autorización explícita del usuario. No crear legacy-v0.6 durante esta corrección.
