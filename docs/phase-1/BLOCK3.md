# Fase 1, Bloque 3 — lenguas, newHistory y población fundadora

Base: `main` en el merge de la PR #4, `714d06c3a9d3ce9d69dbb184161a99b2c78e82f1`. Rama `phase-1/newhistory-founders`. [Issue #5](https://github.com/Jesejojo3/asabiya-native/issues/5). Desarrollador: Claude Opus 5.5. **No fusionar sin revisión de GPT-6 y autorización del usuario.** Windows x64, Go math, sin paridad bit a bit exigida con V8.

## Resultado

`NewSimulation` ya no crea una sesión vacía: ejecuta el port de `newHistory` y deja el mundo poblado en el año inicial. Con la semilla por defecto (Asabiya / historia 1) nacen 10 pueblos fundadores de 10 familias lingüísticas; diez pasadas de `ethPass` los dividen en 95 pueblos. Ocupan 16 797 provincias y suman 10,2 millones de personas. También quedan programados 9 focos tecnológicos: 4 agrícolas, más navegación, cobre, caballo, camello y arado. Todavía **no existe `AdvanceYear`**.

## Qué se portó, en el orden causal del original

| HTML v0.6 | Go | Notas |
| --- | --- | --- |
| 319–358, 659–693, 762–800, 919–923 (PDEF, STYLES, MACROS, LEX, RULES, TECH, ERAS, EPOCH_KINDS) | `catalog_v06.json` + `catalog.go` | Extraído del HTML por `tools/extract-history-catalog.mjs`. El CI verifica que el JSON siga coincidiendo con el HTML. El orden es parte del contrato, porque las tablas se sortean por índice. |
| PDEF + `hearthMode`/`shuffleNames`/`sandbox` | `rules.go` | `Rules` versionadas (`native/rules-v06-v1`), validadas contra los rangos de los sliders originales. `startYear` y `bands` se pueden cambiar en la CLI. Las reglas se copian al crear la simulación. |
| 693–760 `applyRule`…`roman` | `language.go` | Las regex de JS con lookahead y backreferences se implementan como recorridos explícitos, porque RE2 no las tiene. Cada sorteo ocurre en el orden original. |
| 2094 `placeName` | `history.go` | Usa el RNG derivado `hashStr(hist+':place:'+mundo+':'+celda)`, así que nunca toca el RNG histórico. Las ciudades todavía no existen. |
| 813–823 `newEth`, 1815–1840 `ethPass` | `peoples.go` | IDs por orden de creación. Cultura en float32. La deriva cultural recorre también los pueblos creados en la misma pasada. |
| 924–942 `climateStep`, 943 `epochTemp`, 958–980 `computeK` | `carrying.go` | `computeK` está completo, con todos sus términos tecnológicos y ecológicos, aunque la tecnología inicial valga 0. Se respeta el `return` temprano del original en épocas secas sin celda. |
| 801–809 `eraOf`, 1902–1909 `recordStats` | `tech.go`, `history.go` | Índices tecnológicos con alias (`metal` es el índice 3 y `admin` el 6). |
| 864–916 `newHistory` | `history.go` | Sólo la rama procedural. Tierra no está portada. |

Orden de sorteos en `newHistory`: fase orbital → 800 anomalías `gauss` de la malla 40×20 → `climateStep` → selección de semillas (separación angular, `MACRO_KEYS`) → para cada fundador, estilo, lengua y pueblo → difusión BFS (4 vecinos y anillo costero de radio 3) → 10 × `ethPass` → focos agrícolas → los otros 5 focos. `prepEco` ya corrió al construir `World` (Bloque 2). La simulación copia `forest0` y `circ` a su estado mutable y calcula `adapt = 0.5·malaria`.

## Decisiones

1. **ADR-018. `World` inmutable, historia propia.** El estado mutable vive en `history`, dentro de `Simulation`: población, K, pueblos, tecnologías, fertilidad, bosque, sal, malla AG y kMod. Comprobé que el original no escribe en `WD` durante la historia. Sólo se añaden los campos que usan los sistemas ya portados (no se crean `pols`, `wars`, etc. vacíos). `World` gana `LandCells()`/`CoastCells()` (`landIdx`/`coastIdx`), sin cambiar su digest.
2. **ADR-019. Año inicial y reglas.** `newHistory` depende de `P.startYear`, `bands`, `hearths`, `splitDist` y `epochs`, y `computeK` de las tecnologías. Las 40 reglas viajan juntas y versionadas. Cambiarlas a mitad de partida será un comando de frontera anual (ADR-0003), aún no implementado.
3. **ADR-020. Qué de `computeK`/`climateStep`/`weather` se necesita ahora.** `newHistory` llama una vez a `climateStep` y a `computeK`, pero **no** a `weather`: `wm` vale 1 y `anom` no se inicializa, exactamente igual que en v0.6. Se portaron completos los dos primeros. `weather` queda para el bloque del año.
4. **ADR-021. `snapshot` fuera del núcleo.** El historial comprimido del mapa (la barra temporal) no afecta la causalidad. Irá en `internal/history` cuando exista una vista temporal. `recordStats` sí se portó, porque su serie forma parte del estado histórico.
5. **ADR-022. Censo heredado.** `People.Cells` y `People.Pop` son, como en el JS, el censo al **inicio** del último `ethPass`, antes de que las divisiones muevan provincias. `Peoples()` añade además `currentCells` y `currentPopulation`, calculados en vivo.
6. **ADR-023. Huella nativa.** `native/history-init-v1`: SHA-256 de reglas, posición RNG, todos los arrays de estado, pueblos (lengua incluida), focos, épocas y crónica. Golden nuevo en `tests/native/history-v1.windows-go1.27.2.json`. Los golden de mundo v1/v2 no cambian.

## Plan para `AdvanceYear` (no expuesto)

Una transición anual honesta requiere todo `stepG` (1912–1923) en orden: `climateStep` ✔, `weather`, `hearthCheck`, volcanes, `computeK` ✔, `growth`, `migrate`, `seaHop`, `techStep` (cada 3 años), `disease`, `poolPass`/`caravanPass`, `omenPass`, `politicsG` completo, `ethPass` ✔/`relPass` (cada 20), y `recordStats` ✔/`cityPass`/`regionPass`/`mixPass` (cada 10). Propuesta de bloque siguiente: `weather`, `hearthCheck`, `growth`, `migrate`/`seaHop`, `techStep` y `disease`. Con ellos el mundo puede avanzar con pueblos sin Estados, y `AdvanceYear` se expondría sólo en un perfil explícito "pre-estatal" que se detenga con un error al primer punto que necesite `politicsG`. Es una decisión para el usuario.

## Límites

Sin Estados, guerras, diplomacia, dinastías, ciudades, religiones, comercio nuevo, ciclos seculares, UI Paradox ni `AdvanceYear`. Tierra/importación sigue pendiente (`EARTH_SEEDS`, focos históricos). `sandbox` se valida y versiona, pero el favor del sandbox es un comando de UI de frontera anual todavía no implementado.
