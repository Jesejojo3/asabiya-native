# Contrato Go/Godot — v1

Responsables: Codex mantiene `internal/sim`, `internal/interop`, el productor y este contrato; Claude mantiene el consumidor Godot. Ningún cambio del contrato modifica escenas, shaders, recursos o código de Claude. La entrega es mediante archivos/PR, sin comunicación automática entre agentes. Ebitengine queda como visor provisional independiente. La autoridad de fechas, población, RNG y entidades es Go.

## Datos y unidades

`--export <carpeta>` genera `manifest.json`, `geography.bin`, `initial-state.json`, `state.json`, `replay.json` y `control-samples.json`. El estado inicial se reconstruye con otra instancia y las reglas/semillas originales; exportar no consume RNG de la partida. `state.json` es una publicación de un año completo. No es un formato de guardado/restauración del motor. `tools/verify-godot-bundle.mjs <carpeta>` es un consumidor independiente en Node.

El binario comienza con 16 bytes: ASCII `ASABGEO` y cero; uint32 LE 1; uint32 LE reservado 0. Las capas siguen contiguas, sin relleno. El manifiesto define nombre, tipo (`f32`, `i32`, `u8`), componentes por elemento, cantidad, desplazamiento absoluto desde el primer byte y longitud. Todo es little endian. La identidad se verifica con tamaño y SHA-256. No interpretar el binario como una estructura C con alineación. Las capas lógicas incluyen océano; las conexiones marítimas usan CSR (`seaOffsets[i]..seaOffsets[i+1]` sobre `seaTargets`/`seaDistances`). Las distancias de esas conexiones son pasos heredados, no kilómetros.

Las elevaciones son metros; temperatura/amplitud, °C; precipitación, mm/año; área, km². Caudal y fuerza de río son índices heredados. Las capas finas de elevación y clima son opcionales. No existe un bioma fino independiente: el bioma causal pertenece a la provincia lógica.

## Cartografía 3D

El raster es equirectangular, fila 0 al norte y columna 0 al oeste. Para el centro de celda `(x,y)`: `u=(x+0.5)/W`, `v=(y+0.5)/H`, longitud `2πu-π`, latitud `π/2-πv`. Las columnas envuelven; los polos no. Vecinos: oeste, este, norte, sur; `-1` significa límite polar. La provincia estable es `id=y*W+x`, incluyendo océanos. IDs solo tienen sentido dentro del mundo identificado por su hash/versión; regenerar el mundo crea otra identidad.

En un mapa plano 3D, el cliente puede elegir `X=(u-0.5)*mapWidth`, `Z=(v-0.5)*mapDepth` y `Y=elevationMeters*verticalScale`, con escalas visuales configurables. Esto no modifica áreas, distancias ni fricción del motor. Para una esfera opcional, `sphereXYZ` conserva las coordenadas del modelo. La simulación usa también distancia angular por radio 6371 km para ciertos efectos, y costes de pasos para administración/movimiento: no sustituirlos por distancias de malla Godot.

Con 400×200 y detalle 4, las capas finas son 1600×800. Un píxel fino `(fx,fy)` pertenece a `floor(fy/4)*400+floor(fx/4)`. Un vértice interpolado puede tener otra resolución visual; la selección/picking debe volver a esos IDs. Duplicar la costura para la malla es una elección del cliente, sin crear otra provincia. Evitar interpolar vecinos polares inexistentes. La tierra lógica es una mayoría de muestras finas; un litoral fino puede cruzar dentro de una provincia lógica. El océano se identifica por la capa `land`, no por una prueba visual recalculada sobre elevaciones interpoladas. Un plano de mar visual no vuelve terrestre una celda marina ni cambia las elevaciones del motor.

## Estado e IDs

`asabiya/state-v1` publica provincias por índice y entidades por clase/ID. Pueblos, estados, gobernantes, figuras, ciudades, religiones, guerras, migraciones, epidemias, presagios y cataclismos son registros reales del port. Los gobernantes reciben IDs nativos al crear sus objetos originales. Las rutas mantienen un ID nativo monotónico, separado del `legacyId` que el original puede reutilizar al caducar rutas. Las dinastías son etiquetas y generaciones en estados y reinados; no se inventa un registro dinástico independiente.

En provincias, `ownerPolityId=0` significa sin estado; en pueblos/religiones/ciudades/epidemias, `-1` significa sin asignación. El pueblo 0, ciudad 0, religión 0, etc. son entidades válidas. `militaryControllerPolityId=null` declara que v0.6 no modela control militar separado; no confundirlo con propiedad ni cultura. Las tecnologías conservan el orden de `sim.TechCatalog()` (32 valores). Los censos de pueblos/estados/ciudades pueden estar atrasados respecto a la frontera recién procesada; la población provincial es la fuente actual. Cultura o métricas de estados pueden ser null por campos ausentes heredados; no convertirlos silenciosamente en valores causales nuevos.

Las consultas devuelven copias sin arrays/mapas privados. `Snapshot`, `Province`, `Entity`, `Entities`, `OwnershipHistory`, `InitialSummary` y los deltas no consumen RNG. `OwnershipHistory` reconstruye cambios observados en el registro de diez años; no afirma conocer el día o año exacto de cada conquista. `Event` lleva ID, año, clase, provincia y referencias disponibles; `EventText` conserva narración inglesa y explicación separadas. No interpretar frases para decidir mecánicas. No todas las entradas heredadas proporcionan referencias estructuradas a cada actor.

## Fronteras y cambios

`AdvanceYear()` es síncrono y atómico respecto a consultas/comandos. `AdvanceYearWithDelta()` devuelve `asabiya/annual-delta-v1`: año anterior/nuevo, RNG, reglas, favor, hash completo, provincias modificadas como registros reemplazables, upserts de entidades, estados nacidos/extinguidos, eventos/texto nuevos y estadísticas. Los upserts incluyen entidades existentes; el consumidor las reemplaza por `(kind,id)`. El estado no requiere borrarlas para representar extinciones. `firstRetainedEventId` permite reflejar el recorte de la crónica en una caché actual; el cliente puede mantener su propio archivo mayor.

Los deltas pueden incluir muchas provincias cuando cambia el clima/población. Esta primera versión favorece claridad y corrección sobre un protocolo de compresión temporal. No hay una promesa de un año histórico por fotograma de render. Se podrán añadir canales más compactos con versión nueva, conservando esta semántica.

`asabiya/command-v1` admite `advance_year`, `change_rules`, `set_sandbox` y `cast_omen`. Perfil implementado: `native`, con Go math; no hay promesa bit a bit con V8. El comando exige secuencia siguiente y año completo actual; opcionalmente exige hash de reglas. Un rechazo conserva RNG, estado causal y secuencia, y queda en el replay de sesión. Los parámetros de generación/inicialización exigen nueva partida. Sandbox activa favor 9 y, al desactivarse, recorta a 5. El motor no acepta cambios dentro de un año. Los hashes completos y la proyección inicial antigua son contratos distintos; `InitialSummary` conserva el golden inicial.

## Asentamientos y construcciones

La ciudad tiene ID y localización reales, pero su población es la de su provincia, no un censo urbano separado. Fortificación es un valor provincial real. Caravanas y rutas existen; conocimiento de navegación, caminos, agricultura y escritura también. Aldeas, puertos, templos individuales, redes físicas de caminos y parcelas no existen como entidades v0.6. Un icono de esos tipos sería un proxy visual explícito (por ejemplo ciudad santa o conocimiento de caminos), sin efectos nuevos en el motor. Un sistema de edificios causales queda fuera de este port.

## Transporte local validado

`asabiya-server.exe --port 0` escucha únicamente en `127.0.0.1` y escribe una línea `asabiya/local-endpoint-v1` en stdout con la dirección elegida. La conexión es TCP local, con un objeto JSON UTF-8 por línea (NDJSON). No hay conexiones externas, servicios cloud ni puerto abierto en otras interfaces. Una petición puede tener hasta 16 MiB; las respuestas de un mundo grande pueden ser mayores. Leer hasta el salto de línea completo antes de parsear. El servidor maneja una conexión y peticiones secuenciales.

Petición: `{"schema":"asabiya/local-v1","id":"1","session":0,"op":"create_world","payload":{"world":{"seed":"Asabiya","width":400,"height":200,"detail":4,"landFraction":0.33}}}`. Respuesta: mismo esquema e ID, `session`, `ok`, y `data` o `error:{code,message}`. `session=0` permite iniciar; después el cliente debe reenviar la sesión recibida. Crear mundo o historia incrementa esa identidad y exige reemplazar la caché de entidades; una sesión atrasada se rechaza.

Operaciones: `create_world` (configuración completa opcional, `fine` opcional), `start_history` (`historySeed`, `rules` opcional), `get_world`, `get_status`, `get_state`, `advance`, `pause`, `apply_command` (el objeto de comando como payload), `get_province`/`get_province_history` (`id`), `get_entity`/`list_entities` (`kind`, `id` cuando aplica), `get_historical_layer` (`year`), `get_replay`, `export` (`directory` absoluta o relativa al proceso Go) y `shutdown`. `get_status` devuelve siguiente secuencia y hash de reglas. `apply_command` devuelve resultado aceptado/rechazado más estado actual; `ok=true` solo afirma que el protocolo procesó la petición, no que se aceptó un comando inválido.

`advance` tiene payload vacío y ejecuta exactamente un año, devolviendo su delta. El cliente solicita el siguiente cuando lo necesita. No hay un reloj ni ejecución autónoma en segundo plano en el servidor: `pause` confirma ese modo y el cliente deja de solicitar avances. Una pausa en cola espera como máximo el año ya solicitado, no un lote arbitrario. Headless sí permite lotes de miles de años. Esta decisión evita introducir una goroutine propietaria o un planificador que el primer cliente todavía no necesita.

`get_historical_layer` devuelve IDs de provincias terrestres, IDs reales de pueblos/religiones y capas cuantizadas retenidas. Densidad conserva `clamp(round((log10(pop/area)+2)*63),1,255)` (0=sin población), cohesión se codifica en 0..255 y era 255 significa sin población. Las capas son aproximadamente de 50 años y se aligeran en el pasado distante, como v0.6; no representan un guardado completo.

`tools/check-local-protocol.mjs` inicia el servidor real, reconstruye estados aplicando deltas, consulta entidades/capas, pausa, exporta y hace que **otro ejecutable headless** reconstruya el replay. Compara el estado completo y su hash. `--replay-in <archivo>` vuelve a simular los comandos registrados y verifica inicialización, RNG por comando y hash/año finales. Los rechazos se registran, pero no cambian el estado causal. No es restauración rápida de una partida serializada.

## Estado de implementación

Exportador binario/JSON, consultas, deltas y transporte local están implementados y tienen pruebas de copia, reconstrucción y RNG. El consumidor Node y la reconstrucción en otro proceso pasaron en Windows x64. Los fixtures publicados se añaden con el paquete final de integración. Este documento no afirma que el cliente Godot ya exista.
