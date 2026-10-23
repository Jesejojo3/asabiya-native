# Referencia nativa

`world-v1.windows-go1.27.2.json` es el resumen de la primera generación nativa
de Asabiya (400×200, detalle 4, fracción objetivo 0,33) en Windows amd64,
Go 1.27.2 y GOAMD64=v1. No procede del oráculo V8 y no reemplaza sus fixtures.

`tools/check-native-repro.ps1` exige sus valores y dos procesos independientes.
Investigar toda diferencia; no regenerar para esconder errores. Este golden
no demuestra portabilidad entre todas las CPUs ni es una partida guardada.

Bloque 2: el archivo v1 permanece byte a byte intacto. BaseSummary/BaseDigest
conservan su contrato; la comprobación de procesos exige primero esa proyección.
`world-v2.windows-go1.27.2.json` cubre las nuevas capas y no sustituye al v1.

`geography-contract.v06.json` es un caso nuevo 16×12 evaluado con los fragmentos
del HTML original: empates/intercalado del heap, n8, drenaje, ecología y enlaces.
`node tools/check-geography-oracle.mjs` verifica el fixture sin escribirlo.
Go compara índices/orden/banderas exactamente y números con tolerancia pequeña,
sin convertirlo en una promesa de equivalencia V8. El caso incluye mesetas,
depresión, islas, borde polar y costura longitudinal.

Bloque 3: `history-v1.windows-go1.27.2.json` es la proyección estable del
newHistory nativo (Asabiya / historia 1) y su SHA-256. `language-contract.v06.json`
(exacto) e `history-contract.v06.json` vienen del HTML original con Node fijado;
`history-contract-input.v06.json` es el mundo nativo 128×64 que se le da a ese
newHistory original. El test Go comprueba que la entrada siga coincidiendo con
el generador antes de comparar resultados. Regenerar sólo con revisión:
`ASABIYA_WRITE_HISTORY_INPUT=1 go test -run WriteHistoryInput ./internal/sim`
y después `node tools/check-history-oracle.mjs --write`.
