# Segunda revisión independiente — correcciones de Fase 0

Primera revisión recibida por el usuario: Claude Opus 5.5 / @Claudio, APROBADA CON CORRECCIONES, sobre HEAD `3e5f18351421eef1a855a24b30352cf7c42deda8`. Esta entrega atiende los 17 hallazgos en la misma rama `phase-0/legacy-baseline-architecture` y PR #1; conserva los commits anteriores. El usuario entregará manualmente el nuevo HEAD y este paquete. No existe comunicación automática entre herramientas.

## Encargo para Claude

Lee íntegramente AUDIT_FINDINGS.md y contrasta cada disposición con los cambios desde el HEAD de tu primera auditoría, el HTML y los scripts. Registra el HEAD exacto del nuevo paquete y no apruebes una rama cambiante sin indicar los commits añadidos. No integres, no crees tag y no inicies Fase 1. La segunda aprobación es necesaria, y además se requiere autorización explícita del usuario.

Prioriza C1: evalúa si el contrato corregido y la puerta técnica son suficientes para cerrar documentalmente Fase 0, sin confundirlos con una implementación de jsmath validada. NUMERIC_COMPATIBILITY.md distingue ieee754 y builtins de hypot; no concede una lista de funciones math exactas sin comprobar NaN/signo de cero. Corpus V8 no prueba equivalencia Go, y las plataformas Go siguen pendientes.

Revisa I1/I2: fronteras de ChangeRules/defaults/sandbox, diferencias intencionales y dominio de fixtures; visita viva de next/alive/civilWar/newPolity e identidad de colecciones. Hay inventario AST de 130 for-of, no una prueba de frecuencia del caso en una partida. El contador RNG debe ser transparente y su fórmula correcta.

Revisa I3/I4: versión exacta, comparación contra hashes históricos inalterados, validación de continuación/posición RNG y fixture tardío con estados/guerras. No aceptar que dos ejecuciones idénticas sustituyan los golden. Verifica que no se cambiaron el smoke, verificador, inventario original, evidencia original ni reference/. Pruebas extensas están en workflow manual separado.

Revisa I5–I8 y O1–O8: IDs y guardado v1, proyección causal y narrativa separada sin retirar campos del smoke, año atómico, elección secuencial/goroutine pendiente de prueba, UI candidata y prueba corta, calendario/archivos por sistema, cadencias negativas, claves lexicográficas, orden de catálogos, LE, serializador v2 e ICU. Las propuestas pendientes no se presentan como comportamiento implementado.

## Documentos y evidencia

- AUDIT_FINDINGS.md: matriz completa y justificaciones.
- ARCHITECTURAL_DECISIONS.md: ADR y decisiones aún humanas.
- NUMERIC_COMPATIBILITY.md: objetivos, fuentes/licencias, plataformas, FMA, vectores y límites.
- COMMANDS_AND_PROFILES.md, COLLECTION_SEMANTICS.md, SYSTEM_CALENDAR.md.
- EVENTS_AND_SAVE.md: esquema mínimo e identidad; proyección exacta futura.
- CORRECTION_VALIDATION.md y evidence/: pruebas efectivamente realizadas y pendientes.

## Reproducción desde la raíz, con Node 24.19.0

```sh
node tools/verify-reference.mjs
node tools/check-reference-golden.mjs
node tools/test-oracle-contracts.mjs
node tools/test-exact-state.mjs
node tools/math-vectors.mjs --count 2048 --verify docs/phase-0/evidence/math-vectors.quick.node24.json
```

Extensas, fuera del CI de cada PR:

```sh
node tools/math-vectors.mjs --count 200000 --verify docs/phase-0/evidence/math-vectors.extended.node24.json
node tools/reference-late.mjs --verify docs/phase-0/evidence/reference-late.earth-history1.node24.json
```

Para verificar la cadena de custodia local: `node tools/verify-reference.mjs "RUTA_DEL_ORIGINAL"`. Los comandos de verificación nunca regeneran baseline. `reference-late --out` sólo crea un archivo nuevo y falla si ya existe. Exportar vectores matemáticos completos con `--vectors-out` es opcional, no parte del CI rápido. No se necesita Go para estas comprobaciones; el futuro comparador Go y backend jsmath no están implementados.

Entrega dictamen por hallazgo, evidencia reproducida y no reproducida, severidades nuevas y SHA auditado. Distingue aprobación de estas correcciones de autorización de pruebas técnicas/mecánicas futuras. Devuelve el informe al usuario para entrega manual a Codex.

## Hallazgo nuevo que debes revisar

La nueva CI identifica diferencias concretas de pow entre Windows y Linux con Node/V8 exactos. Lee evidence/math-pow.platform-mismatch.node24.json y ejecuta tools/diagnose-pow.mjs. El test sigue siendo estricto y Linux falla; no se cambian fixtures ni se afirma que el contrato numérico esté técnicamente validado. Tu segunda revisión debe pronunciarse sobre el oráculo canónico propuesto y la puerta matemática antes de cualquier Fase 1.
