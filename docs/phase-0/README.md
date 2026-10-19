# Fase 0 — referencia y diseño para revisión

Fecha: 18 de octubre de 2026 (America/Mexico_City).

Esta entrega conserva v0.6 y propone cómo migrarla. No contiene una simulación en Go, una ventana Ebitengine ni mecánicas nuevas. La Fase 1 requiere aprobación humana expresa después de revisar esta entrega. El diseño es una propuesta revisable, no una garantía de equivalencia ya demostrada.

## Referencia preservada

- Base comprobada: `main`, commit `16e7e8adcb86e30b3b6e7487967bf636077b3403`, únicamente `README.md`.
- Acceso al repositorio privado: lectura y escritura confirmadas antes de modificarlo.
- Fuente encontrada: archivo homónimo en Descargas del usuario, 1 553 001 bytes; HTML completo, incluida la interfaz y los recursos embebidos. Identificadores visibles de versión: línea 212 y sección v0.6 en línea 2061.
- Commit dedicado de importación: `fe58bdb2ccf4db83857b02d16fa1852b54836824`. Incluye HTML, manifiesto, `SHA256SUMS` y protección de bytes con `.gitattributes`; conserva el README inicial.
- SHA-256: `988ce360e70d2d034a3898f60b9a4c38d40b0ab56dd7a147329740f15fa8e9e9`.
- Blob Git: `940af36bce0cdb05c3552f1d086ffe4290e392ac`, igual al calculado localmente a partir de los bytes originales.
- Rama de trabajo: `phase-0/legacy-baseline-architecture`. Ninguna escritura directa en `main`.

El original nunca se reformatea, normaliza, minifica ni modifica para instrumentarlo. Los adaptadores de pruebas extraen los scripts en memoria. `manifest.json` registra procedencia y tamaño; no se afirma disponer de una cadena de custodia previa a ese archivo local.

## Lectura recomendada

1. [Inventario y dependencias del JavaScript](SOURCE_AUDIT.md).
2. [Arquitectura y estructura propuestas](ARCHITECTURE.md).
3. [Determinismo y equivalencia](DETERMINISM_AND_TESTS.md).
4. [Benchmarks pendientes](BENCHMARK_PLAN.md).
5. [Decisiones, riesgos y pendientes](DECISIONS_AND_RISKS.md).
6. [Protocolo de colaboración](COLLABORATION.md).
7. [Paquete para Claude](CLAUDE_REVIEW.md).
8. [Evidencia de comprobaciones](VALIDATION.md).

## Condición de salida

La Fase 0 termina con una PR para revisión. No integrar ni crear `legacy-v0.6` durante esta tarea. Para preservar el commit dedicado, se propone integrar mediante merge que conserve sus commits; evitar squash sin una decisión explícita sobre la procedencia. Sólo después de la aprobación e integración, verificar que el commit de importación sea ancestro de `main` y, con autorización, etiquetar ese commit como `legacy-v0.6`. El tag identifica la referencia original, no una versión Go terminada.

Para iniciar Fase 1 se necesita aprobar alcance, contrato de determinismo, estrategia de equivalencia y prioridades; registrar también los hallazgos de la auditoría independiente. Nada aquí autoriza su inicio automático.
