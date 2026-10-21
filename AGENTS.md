# Misión actual: perfilado de zoom cercano, 30 FPS (21 de octubre de 2026)

La nueva petición autoriza perfiles/pruebas y rama/PR independientes desde
`2193a9d92400e7398c73c79105e311aae6397d3b`, sin actualizar PR #22 ni main ni merges.
Primero capturar 1080p/720p, pausado/activo, en i5-1340P + Iris Xe + 16 GB Windows.
Optimizar sólo costes justificados por mediciones; conservar fidelidad CKIII,
Go/Godot y determinismo. Las restricciones anteriores de no ejecutar pruebas,
no crear otras ramas y publicar con skip-ci quedan sustituidas en esta misión.
Sin GPU objetivo accesible, preparar el circuito y declarar medición pendiente;
no usar headless/software render como evidencia del portátil. Ver
`docs/performance/CLOSE_ZOOM_30FPS.md`. No añadir Earth/edificios/ruinas.

# Historial: Fase 2.2 (20 de octubre de 2026, hora del usuario)

Continuar `perf/godot-frame-optimization` desde `238085832ea8fdd8d43e753908699d1810e40337`, actualizar sólo PR #22; no merge ni otras ramas. Priorizar índices derivados de HistoryFrame, escena diferencial, picking y telemetría inclusiva/exclusiva. Sin modificar Go, protocolo TCP, RNG, calendario, SHA, replay, golden o HTML. No ejecutar juego, editor, pruebas, headless, benchmarks, simulaciones ni CI. Sólo revisión estática e instrucciones de compilación Windows; no ZIP. La petición 2.2 autoriza restaurar el control visible Fluido, activado por defecto y explicado. Publicar commits con `[skip ci]` en el HEAD final para no disparar suites al actualizar la PR. La aprobación y mediciones corresponden al usuario/ChatGPT.

# Fase 2 vigente: cliente Godot (21 de octubre de 2026)

Trabajar sólo en `perf/godot-frame-optimization`, desde la consolidación `79035761f1e61041a3ccbf74b648577e53ba7150`. Auditar y optimizar exclusivamente presentación e instrumentación. No ejecutar juego, pruebas, benchmarks, headless, CI ni capturas: validación a cargo del usuario y ChatGPT. No producir ZIP, no merge y no modificar consolidación. Esta instrucción sustituye las autorizaciones de testing y entrega anteriores. Conservar Go, RNG, calendario, SHA, replay, referencia, golden, todos los años y calidad visual. La reproducción fluida es automática, sin selector de modo, como pidió el usuario. No declarar FPS alcanzados sin medidas comparables.

# Continuación: reproducción fluida y entrega tangible

Tras la PR #19, el usuario indica «eso no es tangible para mi, continúa». Esta continuación añade un modo visible Fluido que mantiene cada año publicado, negocia checkpoints explícitos cada 25 años y verifica el snapshot al pausar. La opción de verificación anual se conserva. Los frames diferidos no tienen una huella histórica exacta y deben seguir marcados como tales. No activar diferimiento oculto ni inventar huellas para años pasados. Preparar un paquete Windows para probar; no integrar automáticamente. Esta decisión de presentación sustituye la obligatoriedad de SHA anual en el modo Fluido descrita abajo; conserva las mecánicas, referencia, fixtures, calendario y RNG.

# Misión vigente: rendimiento e integridad (20 de octubre de 2026)

El usuario autoriza expresamente perfilar, ejecutar pruebas Go/Godot, validar gráficamente, comprobar CI y producir un paquete Windows. Esta misión sustituye las restricciones de testeo r3–r5 de abajo. Continuar en `perf/deep-throughput-v2`; no hacer merge. Conservar referencia, fixtures, calendario, RNG y formato/valores de los digests. Las huellas diferidas requieren marcador explícito y no son huellas históricas válidas; la observación normal retiene SHA anual exacto. No afirmar validación de Windows ni rendimiento en el equipo del usuario sin evidencia de esa plataforma.

# Instrucción vigente de entrega

Actualización r5: el usuario precisa que el avance de años es lento. Aumentar los ritmos disponibles y quitar trabajo repetido de publicación/render, manteniendo todos los años consecutivos, pausa y mecánicas. No volver a lotes con años ocultos. Se conserva el testeo a cargo del usuario: compilar/exportar, sin ejecutar nuevas pruebas, partidas ni CI. No hacer merge a main.

Actualización r4: el usuario reasigna también el trabajo del cliente a Codex y solicita corregir la interfaz, el zoom irregular y la reproducción a saltos. Mantener terreno 3D y simulación Go; implementar presentación sobria, rueda de precisión coherente y reproducción continua con años atómicos. El testeo visual y de juego sigue a cargo del usuario; compilar/exportar sin lanzar el juego, suites ni CI. No integrar a main.

Actualización r3: el usuario autorizó expresamente pruebas específicas de serialización/deserialización del protocolo Go–Godot para corregir los enteros JSON decimales. Ejecutar sólo esa cobertura y las regresiones esenciales del protocolo. El testeo visual y de juego, las suites históricas extensas y CI siguen reservados al usuario. No lanzar el juego exportado ni integrar a main.

El usuario asignó a Codex la integración del cliente Godot y el motor, y reservó todo el testeo para sí. No ejecutar pruebas, oráculos, simulaciones de comprobación ni CI sin una nueva instrucción. Se permite compilar/exportar para producir el paquete; no abrir el juego. Trabajar en integration/go-godot-windows, conservando los historiales y sin merge a main. La propiedad anterior del cliente se ha ampliado explícitamente por el usuario; se puede adaptar conservando el trabajo de Claude.

# Asabiya Native — alcance y preservación

- Estado actual: misión autónoma autorizada para completar todo el núcleo v0.6. Rama integration/v06-historical-core depende de PR #6 corregida en d19e27ef. Ver docs/mission/STATUS.md. No hacer merge en main; no esperar auditorías intermedias; no exponer AdvanceYear hasta integrar todo stepG.
- No editar, reformatear ni normalizar `reference/v0.6/Asabiya History Engine (Copy).html`. Ejecutar `node tools/verify-reference.mjs` al trabajar con la referencia.
- No escribir directamente en `main`, integrar PR ni crear `legacy-v0.6` sin la aprobación solicitada. La política de tag está en `docs/phase-0/README.md`.
- Consultar `docs/phase-0/SOURCE_AUDIT.md` antes de portar: prioridades mapa, pueblos, estados, guerras, presagios; conservar dependencias causales de clima, tecnología y ecología.
- El core futuro no depende de Ebitengine, DOM, reloj real ni render. Preservar RNG, orden y datos relevantes del legado; la paridad numérica bit a bit no es obligatoria en native.
- Dirección vigente: Go + Godot 4. Claude posee el cliente Godot; no tocar sus proyectos, escenas, recursos ni shaders. Codex posee núcleo, productor de datos y contrato versionado neutral. Conservar Ebitengine provisional sin condicionar sim. Exportar solo entidades reales y publicar consultas/deltas en fronteras anuales.
- Separar compatibilidad, ajustes de balance y mecánicas nuevas en PR distintas; no actualizar evidencia para ocultar divergencias.
- Colaboración: implementador previsto GPT-6 Astra/Codex, auditor independiente previsto Claude Opus 5.5/Claude Code. Entrega manual por el usuario; no afirmar mensajes, revisión o aprobación externa sin evidencia.
- Documentar pruebas ejecutadas y pendientes; no afirmar equivalencia ni benchmarks Go antes de disponer del port y resultados.
- Historial de Fase 0: correcciones conservadas en PR #1 e integradas tras aprobación. La autorización explícita actual inicia Fase 1 en una rama y PR nuevas; no autoriza su merge.
- Oráculo Node/V8 exactos en tools/oracle-runtime.json y .node-version. El smoke, verificador y evidencia originales se conservan; los nuevos wrappers deben exigir los hashes originales. No regenerar fixtures para esconder divergencias.
- Consultar NUMERIC_COMPATIBILITY.md, COMMANDS_AND_PROFILES.md, COLLECTION_SEMANTICS.md y SYSTEM_CALENDAR.md antes de la siguiente fase técnica. jsmath no es obligatorio; persistencia y UI no están implementadas.

Decisión de producto: Asabiya Native será personal y exclusivo de Windows x64. Usar inicialmente math de Go, mantener el legado y fixtures inmutables, y verificar estabilidad y reproducibilidad práctica en el entorno objetivo sin exigir paridad Go/V8.
