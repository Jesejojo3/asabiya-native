# Fase 1, Bloque 2 — drenaje, geografía y ecología

Base aprobada: main `7fb42f9eab9304b7bcd6811a379780ea6ca4723b`. Rama `phase-1/drainage-geography-ecology`. Relacionado con [Issue #3](https://github.com/Jesejojo3/asabiya-native/issues/3). Entrega para revisión: **no fusionar automáticamente**. Windows x64, Go 1.27.2/Ebitengine 2.10.5, Go math, sin requisito jsmath o equivalencia bit a bit con V8.

## Implementado y orden causal

El terreno/clima y la agregación del Bloque 1 no cambian. Continúa la preparación, todavía sin población:

1. Geometría esférica: x3/y3/z3, cosLon/sinLon y cosLat (con su mínimo original 0,2). cxA/cyA se derivan del CellID row-major, con rangos int16 y comprobación de acceso. Trigonometría de la esfera sobre latitud original float64; cosLat lee la latitud float32 redondeada, como JS.
2. Drenaje con el heap original y visitas n8. down, elevación rellenada, orden de extracción, acumulación y fuerza de río. Acumulación es el índice calibrado del legado, no una medición hidrológica en m³/s.
3. Biomas (IDs originales 0–9), aptitudes sF/sH/nomad, estación de crecimiento, lixiviación y tropicalidad. Mantiene dependencia de temperatura, lluvia, amplitud, relieve y ríos.
4. tcost, desierto, tsetsé y zonas monzónicas; redondeo no negativo de roughness como Math.round y reducción de coste por río.
5. Geometría de interpolación de la malla de anomalías **40×20**, con índices/pesos por celda. No crea aún AG aleatorio ni ejecuta weather: el legado los inicializa/consume dentro de newHistory, que está fuera del alcance.
6. Enlaces marítimos, con offsets/targets/distancias privados y consulta por copia. Conserva la búsqueda original y su selección de diez destinos.
7. prepEco: bosque inicial, suelo pesado, malaria, oncocercosis, circunscripción y nicho de temperatura/humedad/forma de vida/enfermedad. Se ejecuta una vez antes de publicar World; no consume RNG. El legado lo llama desde newHistory: adelantar esta preparación pura permite mantener World inmutable sin adelantar población ni sorteos históricos.

Archivos por sistema dentro de `internal/sim`. Ninguna dependencia de Ebitengine/render, reloj, disco ni concurrencia en el núcleo. Cell devuelve geometría/drenaje/ecología/interpolación por valor; SeaLinks y DrainageOrder devuelven copias. Simulation permanece sin población, sin AdvanceYear y con RNG histórico en cero llamadas.

## H1 — heap y recorridos

`drainHeap` porta hpush/hpop directamente. Push se detiene con `parent <= child`; pop sustituye raíz por el último elemento y sólo mueve un hijo estrictamente menor. Los empates **no** se ordenan por ID ni son FIFO. Se conserva preferencia de hijo izquierdo cuando los dos menores empatan. No se usa container/heap.

Costas y entradas se recorren row-major. n8: dy de −1 a 1, después dx de −1 a 1, sin centro; envolver longitud, recortar latitud. Una costa drena al primer vecino oceánico de ese orden. El relleno escribe float32 antes de encolar su clave. Acumulación invierte el orden del heap y redondea en cada escritura float32.

Mar: primeros pasos por los cuatro vecinos originales oeste/este/norte/sur; después n8 sobre agua hasta profundidad seis. Se preserva `dc >= 2`, que excluye detecciones tempranas aunque parezca una ruta razonable. Orden estable: otra masa terrestre primero, luego dc creciente, empate en orden de descubrimiento; máximo diez. La lista puede ser asimétrica. No se añade reciprocidad o un desempate por ID.

## H2 — precisión y campos derivados

Arrays privados float32; cálculo float64 al leerlos. Las comparaciones con umbrales decimales también promueven a float64: comparar un float32 con una constante Go redondeada a float32 puede cambiar una decisión del JS. Los enteros, IDs, flags y orden se prueban exactamente. No se altera intencionadamente ningún umbral, biomeOf, calendario o balance.

## H3 / ADR-016 — retener detalle visual opcional

| Alternativa | Coste / consecuencia |
|---|---|
| Retener las capas calculadas | No recalcular elevación/clima ni consumir RNG. eHi/tHi/pHi son 15 360 000 bytes; añadir aHi conserva estacionalidad: total **20 480 000 bytes, 19,53 MiB** a 1600×800. Memoria predecible durante la sesión visual. |
| Regenerarlas al mostrarlas | Ahorra ese almacenamiento mientras no hay vista, pero repite generación/clima, necesita parámetros/versión exactos y añade carga/latencia. Mantener una caché acabaría reproduciendo la primera alternativa con más ciclo de vida. |

Recomendación implementada: **retener**, usando `Surface` inmutable, separado de World y sin objetos gráficos. GenerateWorld mantiene el camino headless que descarta detalle; GenerateWorldWithSurface transfiere los arrays existentes sin copias adicionales. La ventana conserva World/Surface y construye una textura fina. Headless permite PNG fino con `--png ... --high-res`; por defecto conserva su exportación gruesa. Ambos caminos producen el mismo digest y posición RNG de simulación.

El tipo está en sim como datos de salida neutrales, no en un paquete que obligue al núcleo a importar presentación. La aplicación es propietaria de su vida útil. Una imagen RGBA fina añade 5 120 000 bytes en CPU; textura/GPU y picos reales dependen del adaptador y no se han medido. No se implementa streaming, regeneración asíncrona, LOD ni un renderer definitivo.

Los ríos/biomas se calculan sobre celdas lógicas 400×200; la textura fina conserva relieve y clima. Sus overlays y la conciliación de costas finas con propietarios por celda son trabajo visual posterior. No presentar los colores provisionales como un renderer de biomas ya terminado.

## ADR-017 — versiones y evidencia conservada

World pasa a `native/world-v2` y headless a `asabiya/headless-v2`, porque añade datos. BaseSummary/BaseDigest conservan **exactamente** la proyección v1 sobre terreno/clima/topología/semilla. El golden v1 sigue intacto y se exige junto con el nuevo v2. El fingerprint v2 incluye todas las capas nuevas de simulación, el orden de drenaje y el orden CSR de enlaces. Surface visual es opcional y queda fuera del digest causal.

Se añade un fixture pequeño nuevo ejecutado contra fragmentos del HTML inmutable, con procedencia SHA y Node/V8 fijados. No se cambia el smoke, los fixtures históricos ni el tag. No se exige identidad numérica de todo el mundo Go contra V8.

## Trazabilidad v0.6

| Líneas del HTML | Port |
|---|---|
| 503–507 | ecology.go: IDs/biomeOf |
| 562–576 | geography.go: esfera y coordenadas derivadas |
| 582–596 | drainage.go: heap, n8, relleno, acumulación/ríos |
| 597–621 | ecology.go: aptitud, viaje y cinturones |
| 622–627 | weather_grid.go |
| 628–640 | sea_links.go |
| 1927–1943 | ecology.go: prepEco |

## Fuera del alcance y siguiente bloque

Continúan pendientes Tierra/mapas importados y ajuste Köppen (sus ramas condicionales/gradeClimate no afectan este mundo procedural), UI completa, overlays de ríos, GPU/DPI interactivos y persistencia. No se implementan newHistory, pueblos, lenguas, población, capacidad de carga, estados, guerras, diplomacia, dinastías ni comercio nuevo.

Siguiente PR recomendada: nombres/lenguas y sus flujos RNG, luego newHistory y población/fundadores con capacidad de carga y dependencias tecnológicas/ecológicas. Conectar startYear a reglas antes de hacerlo configurable. No exponer AdvanceYear hasta portar climateStep/weather/computeK y todos los sistemas requeridos por una transición anual honesta. No comenzar ese bloque automáticamente.
