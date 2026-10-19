# Determinismo, oráculo y pruebas de equivalencia

Contrato corregido: [NUMERIC_COMPATIBILITY.md](NUMERIC_COMPATIBILITY.md), [COMMANDS_AND_PROFILES.md](COMMANDS_AND_PROFILES.md) y [EVENTS_AND_SAVE.md](EVENTS_AND_SAVE.md). Dos perfiles permanentes; objetivo estricto condicionado a prueba técnica, sin equivalencia Go/V8 afirmada. El smoke y sus hashes originales permanecen intactos.

## Identidad de una ejecución

La semilla sola no identifica una historia. El futuro replay incluirá: versión del motor/esquema, hash de reglas efectivas (`P`, `CL` y tablas), semilla del mundo, semilla histórica como cadenas sin conversión numérica, tipo de mundo, hash y dimensiones de recursos importados, ajuste climático, modo de focos agrícolas, nombres mezclados, sandbox, año inicial y lista ordenada de comandos. Registrar también runtime/plataforma del oráculo. El enlace de UI del legado no sustituye este manifiesto.

Propuesta compatible: primero reproducir exactamente los RNG existentes. No introducir generadores independientes por sistema ni paralelizar el núcleo: incluso cambiar los sorteos para nombres puede alterar guerras futuras. Los RNG derivados ya existentes, como nombres de lugares, se conservan con sus cadenas exactas.

## Compatibilidad numérica por resolver

| Aspecto JS | Contrato para el port / prueba futura |
|---|---|
| `hashStr`, UTF-16 y `Math.imul` | Emular unidades UTF-16, incluidos pares sustitutos; no iterar sobre bytes UTF-8 o runas Go. Probar vacío, ASCII, acentos, emoji, y cadenas largas. |
| `mulberry32`, `|0`, `>>>`, overflow | Operaciones de 32 bits con wrap exacto; división final por 2^32. Vectores para semillas 0, 1, 2^31−1 y 2^32−1; secuencia y continuación exactas. |
| `Number` y `Float32Array` | Expresiones JS son normalmente float64 y se redondean a float32 al escribir arrays. Emular cada frontera de escritura; no convertir todos los cálculos a float32. |
| Enteros tipados y centinelas | Distinguir `-1`, `0`, 65535 y cambios de ancho en snapshots. Probar overflow y conversión, sin introducir valores inválidos. |
| `Math.round`, floor y truncamiento | JS redondea empates hacia +∞; `|0` trunca tras conversión de 32 bits. No sustituir indiscriminadamente por `math.Round` Go. Probar negativos y −0 cuando afecte. |
| `Map`, `Set`, orden y sort estable | Conservar el orden de inserción observado del legado y desempates. No recorrer mapas Go en transiciones causales; usar slices ordenados o estructura de inserción explícita. |
| Resto con años negativos | Preservar JS `%`; no normalizar a módulo positivo. Incluir años alrededor de cero y todas las cadencias. |
| exp/log/sin/cos/pow/atan2/asin/acos/log10/hypot y comparaciones | Backend jsmath propuesto, fuentes V8 fijadas, comparación bit a bit por vector, controles FMA/AST y fixtures causales antes de afirmar compatibilidad. math de Go no es sustituto aprobado. Ver NUMERIC_COMPATIBILITY.md. |

La [especificación Go](https://go.dev/ref/spec) no garantiza orden de iteración de mapas. El port no debe depender de él. En v06-compat no se aceptan tolerancias para cambiar estado causal o sorteos. Un contrato numérico distinto pertenecería a una versión explícita de native. Nunca aceptar diferencias en IDs, dueños de celdas, guerras, eventos o consumo RNG porque el error flotante parezca pequeño.

## Estrategia de oráculo propuesta

1. Mantener el HTML como verdad de referencia con SHA-256 comprobado antes de cada ejecución.
2. Extraer `assets` y `core` en memoria, sin editar el HTML. El adaptador permite inicializar, terminar un año, aplicar comandos y leer estado. Versionar el adaptador y runtime usados.
3. Capturar mundo inicial, estado inicial y fronteras por sistema/año. Serializar arrays con nombre/tipo/longitud, escalares, registros, relaciones y orden de Map/Set. Preservar alias tecnológicos y el orden de eventos. El formato de equivalencia futuro debe ser portable y explícito en endianidad.
4. Implementar después el comparador Go/JS: detener en la primera divergencia con escenario, año, sistema, celda/entidad, campo, esperado/obtenido y posición RNG. Mantener un caso mínimo reproducible. Hash global sirve para detectar, no para explicar la divergencia.
5. Mantener defectos históricos como decisiones separadas: un arreglo de balance o lógica tendrá su propia PR, pruebas y aprobación. No actualizar fixtures para ocultar una divergencia.

Mulberry32 sí se reconstruye con semilla uint32 y contador de llamadas: estado = (seed + calls × 0x6D2B79F5) mod 2^32. El adaptador externo envuelve la fábrica sin tocar el HTML; registra la semilla original y cuenta cada sorteo. tools/test-oracle-contracts.mjs confirma transparencia frente a ejecución sin contador y reproduce continuación. El smoke histórico sigue intacto con sus ocho sorteos finales; nuevos fixtures registran además la posición antes de esos sorteos.

## Cobertura disponible de Fase 0

`node tools/verify-reference.mjs [ruta-del-original]` valida longitud, SHA-256, blob Git, manifiesto y `SHA256SUMS`; con argumento también compara todos los bytes del archivo aportado.

`node tools/reference-smoke.mjs` compila los tres scripts y ejecuta únicamente el núcleo original: mundo generado `atlas-7` y Tierra con ajuste climático, semilla histórica `1`, defaults originales. Cada escenario se repite en contextos nuevos; se avanza tres años, se aplica `drought` en la primera celda poblada y se avanzan 51 años más. Se comparan hashes del mundo, estado inicial, año 3, intervención y final, además de continuación RNG. Comprueba población finita/no negativa y seguimiento del presagio. El serializador documental ordena claves de objetos, mantiene orden de Map/Set y tipos de arrays; no altera el motor.

El oráculo está fijado a Node 24.19.0 / V8 13.6.233.17-node.51, x64 LE. tools/check-reference-golden.mjs ejecuta el smoke original y exige sus hashes y continuaciones contra la evidencia original, sin permitir actualizaciones automáticas. El workflow corregido ensaya Windows y Linux con esa versión exacta. Las plataformas realmente comprobadas se registran en CORRECTION_VALIDATION.md; no inferirlas de una matriz YAML. Los tiempos incluyen generación y hashing y no son benchmarks.

Pruebas extensas separadas: tools/reference-late.mjs desde Tierra/historia 1 hasta −3500, sin comandos ni reglas alteradas, y tools/math-vectors.mjs --count 200000. El fixture tardío debe tener estados y guerras; su generación/validación se registra aparte. El generador matemático permite exportar entradas/salidas por bits; no existe comparador Go todavía.

## Matriz pendiente para el port

| Grupo | Casos necesarios | Criterio de aceptación propuesto |
|---|---|---|
| Semillas | Mundo/historia iguales; sólo cambiar una semilla; Unicode; semillas límite | Repetición exacta; primer cambio explicado y trazable. |
| Mapa | Tierra fit on/off, generado, importado con recurso fijo, costas/polos/costura | Vecinos, celdas y enteros exactos; capas float examinadas por etapa. |
| Pueblos | Fundación, expansión, división, mezcla, extinción, migraciones terrestres/marinas | IDs, parentesco, lenguas y composición por celda equivalentes. |
| Estados | Fundación, promoción, sucesión, fragmentación, colapso y fiscalidad | Misma transición y causalidad; comprobar alias, población y alcance. |
| Guerras | Declaración, alianza, incursión, conquista, paz, guerra civil y religiosa | Bandos, objetivos, bajas, propietario y cronología exactos. |
| Presagios | Los ocho, válidos e inválidos; favor insuficiente, mar, sin estado, sandbox | Rechazos y consumo RNG equivalentes; duración y seguimiento a 49/50/51 años. |
| Dependencias | Sequía, épocas, volcán, tecnología/prerequisitos/difusión/pérdida, salinidad, bosque, malaria/tsetsé, rutas/cultivos | Pruebas de efectos causales cruzados y no sólo de salidas agregadas. |
| Calendario | −9000, cambios de signo, divisibilidad 3/10/20/50/500, 1800 | Cadencias equivalentes; detener UI no altera transición del core. |
| Replay | Pausa, velocidades, frecuencia de dibujo, comandos en frontera, guardar/reanudar | Historia idéntica con mismos datos y comandos; render no consume RNG. |
| Largo plazo | Semillas fijas y estratificadas, varios milenios, mundos adversos | Sin divergencias discretas; diferencias float se investigan, no se ocultan en medias. |

Durante la futura Fase 1, comenzar por RNG y mundo, después estado y una transición anual, ampliando por sistemas. Fijar fixtures para estados/guerras ya existentes antes de portar esos sistemas. No recortar sus dependencias para conseguir que pasen pruebas superficiales.
