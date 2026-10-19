# internal/sim

Bloques 1–2: mundo procedural, clima, agregación, geometría esférica, vecinos/costas/masas, drenaje, aptitud ecológica, viajes, enlaces marítimos, interpolación 40×20 y prepEco. World es inmutable y las consultas devuelven valores/copias. Surface opcional conserva el detalle visual fuera de World, sin dependencias de render.

Bloque 3: catálogo v0.6 extraído del HTML (`catalog_v06.json`), reglas versionadas, lenguas/nombres, newHistory, pueblos (newEth/ethPass), climateStep y computeK completos. El estado histórico vive en `history` dentro de Simulation; World no se modifica. No hay AdvanceYear: faltan weather, growth, migración, tecnología y el resto del calendario anual (ver docs/phase-1/BLOCK3.md).

Contratos: `tests/native/language-contract.v06.json` (exacto) e `history-contract.v06.json` (newHistory original sobre un mundo nativo). Go math, native/world-v2, native/history-init-v1.

Diseño: [arquitectura](../../docs/phase-0/ARCHITECTURE.md).
