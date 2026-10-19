# Decisiones arquitectónicas tras auditoría

Origen: informe íntegro recibido por el usuario en esta conversación, auditor Claude Opus 5.5 / @Claudio, 18 de octubre de 2026; HEAD auditado `3e5f18351421eef1a855a24b30352cf7c42deda8`. No hubo comunicación automática con Claude. La segunda revisión estática de Claude aprobó con condiciones documentales. El usuario resolvió el alcance técnico Windows x64, pero la integración de la PR y el inicio de Fase 1 mantienen autorización separada.

## ADR-0001 — perfiles y matemáticas para Windows x64

**Estado: decisión de producto del usuario, sustituye la puerta numérica estricta anterior.** El proyecto es personal y exclusivo Windows x64. `native` usa inicialmente `math` de Go y preserva reglas históricas, RNG, calendario e invariantes, **sin exigir paridad matemática bit a bit Go/V8**. El HTML y corpus v0.6 continúan inmutables como `v06-compat`, referencia diagnóstica, no un segundo motor obligatorio.

**Historial:** la primera propuesta exigía `internal/jsmath` puro basado en V8/Node 24.19.0, vectores exactos, licencias, controles FMA y builtins especiales para `hypot`. Claude consideró coherente esa exigencia bajo un contrato de equivalencia bit a bit. Tras definir el alcance personal Windows x64, el usuario retiró la exigencia; jsmath queda opcional ante una necesidad futura demostrada. `GOAMD64=v1` no garantiza por sí solo identidad entre CPUs; validar lo requerido para el entorno usado.

Las referencias de V8 conservan sus golden históricos y no se reajustan para disimular divergencias. Las diferencias nativas se caracterizarán con invariantes, hitos y semillas reproducibles, no igualdad obligatoria de hashes. Ver NUMERIC_COMPATIBILITY.md.

## ADR-0002 — año atómico y propiedad del estado

Estado: año atómico adoptado como contrato propuesto; estrategia de ejecución pendiente de prueba y aprobación. No replicar yield del navegador en Go. Un único propietario del estado en ambas opciones: secuencial o goroutine dedicada.

Prueba futura 4–8 horas, con autorización de la siguiente fase técnica: ejecutar años completos sobre fixture tardío, comprobar latencia percentil 95/99 de entradas/vistas, throughput, memoria de snapshots, cancelación al cerrar, comandos ordenados y race detector. Comparar ejecución secuencial y goroutine con el mismo replay y hashes. No decidir por estética ni por la suposición de que Go siempre tarda menos de un frame. No dejar que Draw espere un lock durante el año. Si se elige goroutine, cola ordenada y snapshots inmutables con propiedad de buffers; `atomic.Pointer` no vuelve inmutable un buffer que luego se reutiliza.

UI: comparar ebitenui con una solución mínima propia, candidatos sin selección definitiva. Prototipo de crónica enlazada y scroll, reglas, mapa y tipografía; validar Windows amd64/DPI antes de estimar la interfaz completa. Ninguna biblioteca se instala en Fase 0.

## ADR-0003 — comandos y persistencia

Estado: diseño mínimo propuesto para aprobación. Cambios de reglas/defaults y sandbox pasan a frontera anual, diferencia intencional y registrada. IDs estables y relaciones por identificador, preservando índices/centinelas legados. Guardado v1 completo separado de replay e historial de mapa; RNG semilla/contador. Los detalles están en COMMANDS_AND_PROFILES.md y EVENTS_AND_SAVE.md. Implementación y migraciones pendientes.

## ADR-0004 — equivalencia de eventos y narrativa

Estado: propuesta explícita, pendiente de segunda aprobación. Comparar datos causales, nombres generados, RNG y eventos estructurados para diagnosticar diferencias, sin exigir igualdad bit a bit Go/V8; localizar texto fuera del core. No exigir igualdad entre ICU y formato Go. Mantener el smoke histórico completo e intacto, y diseñar una proyección Go/JS distinta y versionada. No declarar causas estructuradas que el adaptador original no puede observar. Cualquier campo excluido deberá quedar enumerado y justificado al definir esa proyección.

## ADR-0005 — QA y evolución

Estado: herramientas de oráculo implementadas en Fase 0. Node/V8 exactos para el oráculo legado; CI rápida obligatoria en Windows exige golden originales y corpus fijo, y Linux queda como diagnóstico estricto no bloqueante; pruebas extensas en workflow manual separado. El fixture tardío se genera desde el original y se exige que tenga estados y guerras. Su primera generación es una baseline nueva, no reemplaza valores para esconder discrepancias. Semántica de colecciones documentada con inventario AST completo; codificación exacta v2 para diagnóstico preserva −0/orden/alias sin cambiar el smoke.

Decisiones de producto tomadas: Windows x64, Go math para native, paridad V8 estricta no exigida. La estrategia secuencial/goroutine y UI siguen pendientes de prototipo. Guardado, comando/frontera y eventos siguen como diseños a implementar. Integración y Fase 1 requieren aprobación humana explícita; ya no existe una puerta jsmath obligatoria.

## ADR-0006 — discrepancia `Math.pow` y política de CI

**Estado: observación técnica conservada, no bloqueante por decisión de alcance.** La CI observó 3/2 273 diferencias de 1 ULP en `pow` entre Windows y Linux con versión Node/V8 fijada; el golden histórico pasó. No se corrigió ni ocultó la discrepancia y no se atribuyó a una causa sin pruebas.

El usuario seleccionó exclusivamente Windows x64. El workflow Windows sigue siendo obligatorio; Linux permanece como job diagnóstico opcional (`continue-on-error`), **sin desactivar su comprobación estricta ni alterar corpus**. El port `native` usará inicialmente `math` de Go, con comprobaciones de estabilidad y reproducibilidad aplicadas durante su desarrollo. Reabrir una puerta numérica solo si un defecto real del producto lo exige.

La aprobación de Fase 0 no acredita compilación Go, port de mecánicas ni equivalencia Go/V8; esas pruebas no existen todavía.
