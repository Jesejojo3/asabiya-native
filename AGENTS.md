# Asabiya Native — alcance y preservación

- Estado actual: Bloque 1 integrado en main 7fb42f9e. Bloque 2 autorizado: drenaje, geografía, ecología y capas finas, en rama/PR nuevas, sin merge automático. Ver docs/phase-1/BLOCK2.md. No newHistory ni población/estados en este bloque.
- No editar, reformatear ni normalizar `reference/v0.6/Asabiya History Engine (Copy).html`. Ejecutar `node tools/verify-reference.mjs` al trabajar con la referencia.
- No escribir directamente en `main`, integrar PR ni crear `legacy-v0.6` sin la aprobación solicitada. La política de tag está en `docs/phase-0/README.md`.
- Consultar `docs/phase-0/SOURCE_AUDIT.md` antes de portar: prioridades mapa, pueblos, estados, guerras, presagios; conservar dependencias causales de clima, tecnología y ecología.
- El core futuro no depende de Ebitengine, DOM, reloj real ni render. Preservar RNG, orden y datos relevantes del legado; la paridad numérica bit a bit no es obligatoria en native.
- Separar compatibilidad, ajustes de balance y mecánicas nuevas en PR distintas; no actualizar evidencia para ocultar divergencias.
- Colaboración: implementador previsto GPT-6 Astra/Codex, auditor independiente previsto Claude Opus 5.5/Claude Code. Entrega manual por el usuario; no afirmar mensajes, revisión o aprobación externa sin evidencia.
- Documentar pruebas ejecutadas y pendientes; no afirmar equivalencia ni benchmarks Go antes de disponer del port y resultados.
- Historial de Fase 0: correcciones conservadas en PR #1 e integradas tras aprobación. La autorización explícita actual inicia Fase 1 en una rama y PR nuevas; no autoriza su merge.
- Oráculo Node/V8 exactos en tools/oracle-runtime.json y .node-version. El smoke, verificador y evidencia originales se conservan; los nuevos wrappers deben exigir los hashes originales. No regenerar fixtures para esconder divergencias.
- Consultar NUMERIC_COMPATIBILITY.md, COMMANDS_AND_PROFILES.md, COLLECTION_SEMANTICS.md y SYSTEM_CALENDAR.md antes de la siguiente fase técnica. jsmath no es obligatorio; persistencia y UI no están implementadas.

Decisión de producto: Asabiya Native será personal y exclusivo de Windows x64. Usar inicialmente math de Go, mantener el legado y fixtures inmutables, y verificar estabilidad y reproducibilidad práctica en el entorno objetivo sin exigir paridad Go/V8.
