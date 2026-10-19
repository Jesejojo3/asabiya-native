# Validación — Bloque 3

## Correcciones de revisión de GPT-6

- Summary copia también cada slice EraShare de Stats: modificar una consulta no alcanza el historial ni otra consulta. Prueba específica con dos registros y dos vistas independientes.
- Digest distingue las cuatro combinaciones de ShuffleNames/Sandbox aun manteniendo el resto del estado idéntico. False/false conserva la codificación implícita v1; las opciones activas añaden un trailer etiquetado `rules/options-v1` y dos bits. Así se corrige la identidad de reglas sin cambiar los golden predeterminados ni consumir RNG.
- Ambas pruebas fallan sobre el HEAD anterior y pasan con las correcciones. No se modifican HTML, golden ni mecánicas de inicialización. La continuación del núcleo completo se desarrolla en otra rama dependiente, después de verificar estas correcciones y su CI; no forma parte de esta PR.

## Contratos contra el HTML original (Node 24.19.0 / V8 13.6.233.17 fijados)

| Contrato | Qué se compara | Resultado en Go |
| --- | --- | --- |
| `tools/extract-history-catalog.mjs` | Las tablas del catálogo coinciden con el HTML evaluado | Verificado |
| `language-contract.v06.json` (`tools/check-language-oracle.mjs`) | 594 aplicaciones de reglas fonéticas, `tidy`, `join` y 81 casos (27 estilos × 3) de `makeLang` → `childLang` ×2 → `hybridLang` + `personName`/`placeWord`/`cityWord`, **con el número de sorteos** | Idéntico, sin tolerancia |
| `history-contract.v06.json` (`tools/check-history-oracle.mjs`) | El `newHistory` **original** ejecutado sobre un mundo nativo de 128×64 exportado por Go (`history-contract-input.v06.json`). En memoria sólo cambian `W`/`H`; el HTML no se toca | Idénticos: 5 416 sorteos RNG, asignación pueblo/celda, 25 pueblos (nombres, lenguas, linajes, colores), focos, crónica y nombres de lugar. Floats (K, población, AG, cultura, `gT`, órbita) dentro de `max(1e-9, 2e-6·|x|)` |

La comparación exacta del comportamiento discreto es posible porque, en este caso, las diferencias de `math` de Go no cambiaron ninguna decisión. No se promete para todo mundo o semilla. Mutación de prueba: desplazar un año base de foco en Go hace fallar el contrato.

## Pruebas nativas

- Invariantes con tres semillas (incluida una Unicode) a 160×80 y con el mundo por defecto. La población es finita, no negativa y sólo existe donde hay pueblo. La densidad inicial es exactamente 0,55·K (float32). K ≥ 1 en tierra y 0 en océano. No hay pueblos en celdas con T ≤ −9. Linajes, familias y profundidad son coherentes. La cultura está en 0..1. Los focos son tierra con sF > 0,45 y años dentro de sus rangos. La historia no altera el digest del mundo.
- Reproducibilidad: la misma semilla da el mismo digest y estado; otra historia da otro digest.
- Reglas: se rechazan valores fuera de rango, no enteros, `NaN`, claves desconocidas o faltantes, versión distinta y modo de focos inválido. `startYear`/`bands` se aplican, y las reglas no comparten memoria con el llamador.
- Consultas: los nombres de lugar son estables y no consumen el RNG histórico, y las vistas no comparten memoria con el estado.
- CLI: `--peoples`, `--bands` y `--start-year` (múltiplo de 500), con rechazo de entradas inválidas.

## Ejecutado en este entorno

Linux x64, Go 1.24.7 en una copia con la directiva `go` bajada a 1.24 (el toolchain 1.27.2 no se puede descargar aquí): `go vet` y `go test -count=1` de `internal/...` y `cmd/asabiya-headless` pasan. Golden de mundo v1 (`6f763794…`) y v2 (`04f336d8…`) sin cambios. Historia por defecto: `3a1a781a…`, 12 631 sorteos y ~1,1 s en total. Node 24.19.0 fijado: los cuatro oráculos, `verify-reference` y `check-reference-golden` pasan. El HTML, el tag y los fixtures históricos no cambiaron.

**No ejecutado aquí:** compilar con Go 1.27.2 para Windows, la ventana Ebitengine y `check-native-repro.ps1`. Los cubre el CI de Windows de la PR. El golden `history-v1.windows-go1.27.2.json` se generó en Linux/Go 1.24.7, como los golden anteriores que luego coincidieron en Windows. Si el CI de Windows lo rechaza, se investiga la causa; no se regenera a ciegas.
