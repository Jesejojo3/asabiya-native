# Decisiones arquitectónicas tras auditoría

Origen: informe íntegro recibido por el usuario en esta conversación, auditor Claude Opus 5.5 / @Claudio, 18 de octubre de 2026; HEAD auditado `3e5f18351421eef1a855a24b30352cf7c42deda8`. No hubo comunicación automática con Claude. Las correcciones quedan pendientes de segunda revisión y autorización del usuario.

## ADR-0001 — compatibilidad numérica y perfiles

Estado: propuesta revisada. Adoptar `v06-compat` permanente y `native` versionado. El primero preserva referencias, calendario, flujo RNG y causalidad; el segundo admite cambios explícitos con fixtures propios. Backend jsmath puro como ruta a evaluar, fijado a las fuentes de Node 24.19.0. La revisión de fuentes muestra que hypot requiere builtins adicionales al archivo ieee754; por tanto no se acepta una copia genérica de fdlibm como solución demostrada. Licencias/port/vectores/controles FMA siguen como puerta técnica previa al port de mecánicas. No se promete equivalencia bit a bit por aprobar esta documentación.

Consecuencia: no usar tolerancias para tapar cambios discretos, ni permitir que evoluciones nativas desplacen sorteos compatibles. Los corpus añadidos sólo validan estabilidad del oráculo V8 hasta que exista el comparador Go.

## ADR-0002 — año atómico y propiedad del estado

Estado: año atómico adoptado como contrato propuesto; estrategia de ejecución pendiente de prueba y aprobación. No replicar yield del navegador en Go. Un único propietario del estado en ambas opciones: secuencial o goroutine dedicada.

Prueba futura 4–8 horas, con autorización de la siguiente fase técnica: ejecutar años completos sobre fixture tardío, comprobar latencia percentil 95/99 de entradas/vistas, throughput, memoria de snapshots, cancelación al cerrar, comandos ordenados y race detector. Comparar ejecución secuencial y goroutine con el mismo replay y hashes. No decidir por estética ni por la suposición de que Go siempre tarda menos de un frame. No dejar que Draw espere un lock durante el año. Si se elige goroutine, cola ordenada y snapshots inmutables con propiedad de buffers; `atomic.Pointer` no vuelve inmutable un buffer que luego se reutiliza.

UI: comparar ebitenui con una solución mínima propia, candidatos sin selección definitiva. Prototipo de crónica enlazada y scroll, reglas, mapa y tipografía; validar Windows amd64/DPI antes de estimar la interfaz completa. Ninguna biblioteca se instala en Fase 0.

## ADR-0003 — comandos y persistencia

Estado: diseño mínimo propuesto para aprobación. Cambios de reglas/defaults y sandbox pasan a frontera anual, diferencia intencional y registrada. IDs estables y relaciones por identificador, preservando índices/centinelas legados. Guardado v1 completo separado de replay e historial de mapa; RNG semilla/contador. Los detalles están en COMMANDS_AND_PROFILES.md y EVENTS_AND_SAVE.md. Implementación y migraciones pendientes.

## ADR-0004 — equivalencia de eventos y narrativa

Estado: propuesta explícita, pendiente de segunda aprobación. Comparar rigurosamente datos causales, nombres generados, secuencia RNG y eventos estructurados; localizar texto fuera del core. No exigir igualdad entre ICU y formato Go. Mantener el smoke histórico completo e intacto, y diseñar una proyección Go/JS distinta y versionada. No declarar causas estructuradas que el adaptador original no puede observar. Cualquier campo excluido deberá quedar enumerado y justificado al definir esa proyección.

## ADR-0005 — QA y evolución

Estado: herramientas de oráculo implementadas en Fase 0. Node/V8 exactos; CI rápido exige valores originales y corpus matemático fijo; pruebas extensas en workflow manual separado. El fixture tardío se genera desde el original y se exige que tenga estados y guerras. Su primera generación es una baseline nueva, no reemplaza valores para esconder discrepancias. Semántica de colecciones documentada con inventario AST completo; codificación exacta v2 para diagnóstico preserva −0/orden/alias sin cambiar el smoke.

Decisiones aún humanas antes de migrar: aceptar alcance textual, perfiles, fronteras de comandos, guardar/IDs, selección posterior de ejecución/UI y puerta matemática. Ni el informe de primera auditoría ni esta corrección autorizan integrar o iniciar Fase 1.
