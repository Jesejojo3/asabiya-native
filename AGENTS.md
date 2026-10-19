# Asabiya Native — alcance y preservación

- Estado de esta entrega: Fase 0 para revisión. La Fase 1 requiere autorización humana expresa; no inferirla de la existencia de esta estructura.
- No editar, reformatear ni normalizar `reference/v0.6/Asabiya History Engine (Copy).html`. Ejecutar `node tools/verify-reference.mjs` al trabajar con la referencia.
- No escribir directamente en `main`, integrar PR ni crear `legacy-v0.6` sin la aprobación solicitada. La política de tag está en `docs/phase-0/README.md`.
- Consultar `docs/phase-0/SOURCE_AUDIT.md` antes de portar: prioridades mapa, pueblos, estados, guerras, presagios; conservar dependencias causales de clima, tecnología y ecología.
- El core futuro no depende de Ebitengine, DOM, reloj real ni render. Preservar RNG, orden, datos e identidad numérica del legado antes de optimizar.
- Separar compatibilidad, ajustes de balance y mecánicas nuevas en PR distintas; no actualizar evidencia para ocultar divergencias.
- Colaboración: implementador previsto GPT-6 Astra/Codex, auditor independiente previsto Claude Opus 5.5/Claude Code. Entrega manual por el usuario; no afirmar mensajes, revisión o aprobación externa sin evidencia.
- Documentar pruebas ejecutadas y pendientes; no afirmar equivalencia ni benchmarks Go antes de disponer del port y resultados.
- Correcciones posteriores a auditoría: conservar la rama y PR #1 y todos los commits previos. No integrar ni iniciar Fase 1 sin segunda aprobación de Claude y autorización explícita del usuario.
- Oráculo Node/V8 exactos en tools/oracle-runtime.json y .node-version. El smoke, verificador y evidencia originales se conservan; los nuevos wrappers deben exigir los hashes originales. No regenerar fixtures para esconder divergencias.
- Consultar NUMERIC_COMPATIBILITY.md, COMMANDS_AND_PROFILES.md, COLLECTION_SEMANTICS.md y SYSTEM_CALENDAR.md antes de la siguiente fase técnica. jsmath, FMA, persistencia y UI no están implementados.
