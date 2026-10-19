# Verificación esencial — Bloque 2

Windows amd64 local, Go 1.27.2, GOAMD64=v1, CGO_ENABLED=0. Go math. Sin campaña de benchmarking ni equivalencia matemática V8/Go.

## Ejecutado localmente

- `go test -count=1 ./...`: pasa. Tests de RNG previos conservados; geografía/ecología sobre tres semillas pequeñas y mundo default completo, golden v1 congelado y golden v2, consultas y PNG.
- `go vet ./...`: pasa.
- Compilación Windows amd64 de headless y ventana Ebitengine: pasa con las versiones fijadas.
- `node tools/check-geography-oracle.mjs`: pasa. Verifica el nuevo fixture contra las funciones y fragmentos originales, con hash del HTML y runtime Node/V8 fijados, sin reescribirlo.
- `node tools/verify-reference.mjs`: pasa, 1 553 001 bytes, SHA-256 `988ce360e70d2d034a3898f60b9a4c38d40b0ab56dd7a147329740f15fa8e9e9`, blob `940af36bce0cdb05c3552f1d086ffe4290e392ac`.
- `tools/check-native-repro.ps1`: dos procesos independientes coinciden y cumplen tanto v1 como v2. El fixture v1 previo se conserva byte a byte.
- Exportación fina PNG 1600×800 examinada visualmente; no equivale a una prueba interactiva de la ventana.

## Cobertura mecánica

El fixture original 16×12 contiene mesetas costeras empatadas, terreno elevado/depresión, islas, límite polar y costura longitudinal. Se comparan exactamente pops de heap intercalados, n8/vecinos, down, orden de drenaje, biome/flags/costes, índices meteorológicos y offsets/targets/distancias de enlaces. Los floats se cotejan con tolerancia `max(2e-6, abs(ref)*3e-7)`; es un caso de mecánicas, no prueba universal de paridad de math.

Invariantes: esfera unitaria aproximada; campos finitos; rangos de aptitudes/enfermedad/bosque; biomas válidos; drenaje sin ciclos, adyacente, con relleno ascendente y acumulación no decreciente aguas abajo; toda tierra del mundo generado alcanza el océano; costas/masas consistentes; máximo diez enlaces con destino costero, profundidad 2–6 y prioridad correcta. En los mapas pequeños también se busca una ruta acuática independiente para cada enlace seleccionado. En el mapa default se comprueba estructura/orden/destinos de todos los enlaces, sin repetir búsquedas largas por cada uno.

Surface y las vistas devuelven valores/copias; la retención fina no cambia digest ni RNG. Las medias de clima fino reproducen las capas gruesas. prepEco es idempotente. No se añaden sorteos para detalle, drenaje o ecología.

## Referencia default Asabiya / historia 1

80 000 celdas, 26 124 terrestres, 3 073 costeras, 61 masas terrestres, **3 841 celdas con río**, **29 324 enlaces marítimos**. Malla de anomalías 40×20 preparada para su futura inicialización.

RNG mundo: semilla 4 037 141 429, **215 644 llamadas** (sin cambio). RNG histórico: semilla 58 464 154, **cero llamadas**. Año −9000, sesión sin población.

- SHA-256 base v1: `6f763794f922ed72f6ccfca992338ef5a731e20d0dff096c8c40ffbb385dcc22`.
- SHA-256 mundo v2: `04f336d80022d6e07f1ff9eb96559033742b98db9086164db781d2499675497f`.

## CI y pendientes

La CI Windows incorpora el contrato pequeño del JS y exige ambos golden nativos, módulos, vet, tests, builds y procesos independientes. El workflow del legado sigue intacto. Sus resultados reales se consultan en la PR; no se presupone que un job pendiente haya pasado. El diagnóstico Linux opcional puede conservar la discrepancia Math.pow ya documentada en Fase 0; no es plataforma del producto.

Pendiente: abrir la ventana real, GPU/DPI/resize/Esc; render de ríos/biomas; port Tierra/importación/Köppen; nuevos equipos/CPUs; nombres/lenguas/newHistory y población; partida guardada y primer año completo. No hay sistemas históricos nuevos ni AdvanceYear ficticio. La auditoría independiente se entrega manualmente por el usuario, no se afirma revisión automática de Claude.
