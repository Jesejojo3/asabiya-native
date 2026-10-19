# Matriz completa de hallazgos de Claude — primera revisión

Informe íntegro leído en la conversación y contrastado con HTML/documentación. Autor comunicado: Claude Opus 5.5 / @Claudio, 18 oct 2026. HEAD auditado `3e5f18351421eef1a855a24b30352cf7c42deda8`. Veredicto recibido: **APROBADA CON CORRECCIONES**. Sus mediciones Go/Linux y otras CPU no se presentan como pruebas ejecutadas por Codex. Los 17 hallazgos se evalúan individualmente; aceptar el problema no implica adoptar automáticamente su solución.

| ID | Disposición | Contraste, decisión y evidencia |
|---|---|---|
| C1 | **Modificado** | Se acepta el defecto de compatibilidad del plan previo. Se acepta el defecto numérico, pero el usuario retiró la exigencia de equivalencia bit a bit para native personal Windows x64. Usar math de Go; jsmath queda opcional. Corpus original preservado y no existe paridad Go/V8 demostrada. NUMERIC_COMPATIBILITY.md, ADR-0001. |
| I1 | **Aceptado** | Verificadas escrituras inmediatas P (2974–2975), sandbox/favor (3135) y aviso UI (3165). ChangeRules/defaults/SetSandbox se registran en replay y aplican en frontera; diferencia intencional del dominio de entradas, no cambio al HTML. COMMANDS_AND_PROFILES.md. |
| I2 | **Aceptado** | Cadena exacta 1658→1663→civilWar→1288→1240 confirmada. Iteración por índice/longitud viva sobre único campo, evitando alias de cabeceras Go. Prueba mínima y transparencia RNG aprobadas; inventario AST de 130 ForOfStatement y reglas por familia. Frecuencia en partida real y port Go pendientes. COLLECTION_SEMANTICS.md. |
| I3 | **Aceptado** | Node 24.19.0/V8 exactos fijados. CI exige los cinco hashes y continuación de ambos escenarios contra evidencia original sin editarla, además de repetibilidad original. Smoke/verificador intactos. Herramienta check-reference-golden.mjs. |
| I4 | **Aceptado** | Semilla/contador reconstruye Mulberry32; wrapper externo y comparación con ejecución no contada prueban transparencia. Fixture tardío nuevo Tierra/historia 1, sin comandos, hasta −3500; debe tener estados/guerras. Coste fuera del CI rápido. Resultado exacto en CORRECTION_VALIDATION.md. No se equipara posición RNG a guardado completo. |
| I5 | **Aceptado** | Diseño mínimo de IDs estables, centinelas, referencias por ID, contadores, alias y contenedor versionado; internal/save separado de history/replay. Sin código de persistencia ni oráculo legado para guardado. EVENTS_AND_SAVE.md, ADR-0003. |
| I6 | **Modificado** | Se acepta dependencia de texto/ICU. Propuesta: comparaciones diagnósticas de causalidad/nombres/eventos con invariantes e hitos; narrativa localizada fuera, sin paridad bit a bit obligatoria. Smoke histórico full-S no cambia. El adaptador chron no expone todas las causas: no inventarlas parseando frases. Proyección futura versionada requiere revisión. EVENTS_AND_SAVE.md, ADR-0004. |
| I7 | **Modificado** | AdvanceYear atómico, sin máquina de estados de yield. No se impone la goroutine ahora: comparar secuencial y propietario dedicado con mismo replay, latencia, snapshots y race detector. La elección necesita prueba/aprobación, como pide el usuario. ADR-0002. |
| I8 | **Modificado** | Candidato ebitenui y alternativa mínima propia; prueba futura de 4–8 h de crónica enlazada/scroll, mapa, reglas, texto y DPI. No instalar UI ni comprometer fechas antes de probar Windows. ADR-0002, ARCHITECTURE.md. |
| O1 | **Aceptado** | Resto negativo confirmado; se nombran poolPass/caravanPass y sus condiciones. Preservar v06-compat; native/calendar-v2 como propuesta separada, sin implementar. SYSTEM_CALENDAR.md y R09 corregido. |
| O2 | **Aceptado** | Sort sin comparador en 2041/2054: claves lexicográficas, p.ej. 10:9. No ordenar numéricamente durante el port compatible. COLLECTION_SEMANTICS.md. |
| O3 | **Aceptado** | Orden Object.entries(CATA) en 2226 afecta el sorteo. Catálogos causales como listas ordenadas con ID; no mapas Go. COLLECTION_SEMANTICS.md. |
| O4 | **Aceptado** | Int16Array al decodificar Tierra, 414–417, usa endianidad local. Propuesta Go LE explícita, acumulación float64/redondeo float32 al escribir para ámbito fijado. No se valida big-endian. COLLECTION_SEMANTICS.md. |
| O5 | **Aceptado** | Codificador histórico pierde orden/−0; se conserva intacto y se añade formato diagnóstico v2 que distingue orden, alias, ceros y arrays, con pruebas de esos casos. No reemplaza golden ni equivale a persistencia. tools/lib/exact-state.mjs. |
| O6 | **Aceptado** | CI corregido: PR + push sólo a main (sin duplicado por push de rama), acciones por SHA comprobado, Node exacto; pruebas extensas manuales en archivo separado. Matriz Windows/Linux no es evidencia hasta completar jobs. |
| O7 | **Aceptado** | Se documenta ICU y formato en narrativa/diagnóstico; detector original de nombres sigue siendo comprobación estática limitada, no certificación de pureza. Metadatos runtime/ICU se registran en validación correctiva. |
| O8 | **Aceptado** | Un paquete sim inicial, archivos por sistema y calendario causal con cadencias internas. No crear decenas de paquetes ni mecanismos de extensión prematuros. SYSTEM_CALENDAR.md. |

No se rechaza ninguno de los problemas observados. C1 conserva evidencia, pero ya no bloquea: la paridad V8/Go se retiró como requisito de producto, y jsmath queda opcional. I6/I7/I8 conservan decisiones futuras. No se afirma equivalencia matemática ni funcional del port Go aún inexistente.

## Bloqueos antes de integrar o comenzar mecánicas

La segunda revisión estática de Claude emitió APROBADA CON CONDICIONES; la condición era actualizar la documentación al alcance personal Windows x64. El usuario tomó esa decisión. Las pruebas esenciales se harán durante la implementación, sin puerta jsmath. Integrar/crear tag/iniciar Fase 1 exige autorización humana explícita distinta; este cambio documental no la supone.

## Evidencia adicional que afecta C1/I3

La CI reforzada detectó 3 diferencias de un ULP en Math.pow entre Windows y Linux con el mismo Node/V8 fijado. Se documentan como diferencia de portabilidad no bloqueante para Windows x64; no se atribuye causa no medida y las pruebas y fixtures siguen estrictos. Ver NUMERIC_COMPATIBILITY.md y evidencia de bits. C1 no se declara solucionado como paridad matemática: la segunda auditoría aceptó retirar ese requisito. Windows CI obligatoria; Linux diagnóstico opcional no bloqueante.
