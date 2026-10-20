# Publicación exacta, campos provinciales y estabilidad

Esta entrega continúa `perf/deep-throughput-v2` desde `8ebaadf198190cf14320a488c1346973116f3ff7`, sin merge. Se inspeccionó la secuencia de commits heredada y la ejecución Windows [39384327276](https://github.com/Jesejojo3/asabiya-native/actions/runs/39384327276): el job y todos sus pasos obligatorios terminaron correctamente. Sus cifras no son mediciones del equipo del usuario.

## Integridad y digest

`native/history-state-v1` conserva sus bytes, orden, exclusiones y SHA-256. El nuevo escritor reserva bloques de pares `[kind, bits]` y admite todos los slices numéricos soportados por el escritor original. No se utiliza digest incremental, estado de SHA reutilizado ni caché de campos causales. Se compara el flujo de bytes original con todos los tipos numéricos, tipos con nombre, arrays, slices anidados, buffers desalineados, NaN de distintos payloads, infinitos y ceros con signo. La prueba histórica existente conserva además el escritor original por reflexión como referencia independiente.

Los checkpoints heredados son una proyección opcional, no un archivo de huellas anuales. Un consumidor que guarda un frame sin SHA no puede recuperar después su huella mediante una consulta del estado actual: necesitaría reconstruir ese año mediante replay. Por ello el cliente de observación deja de activar checkpoints automáticamente. Conserva un SHA exacto por año publicado; Fast-Forward mantiene sus avances anuales completos y snapshots exactos a los intervalos solicitados.

El servidor conserva compatibilidad con `digestMode=checkpoint-v1`. Una publicación diferida lleva `deferred-v1` y cadena vacía, y `HistoryFrame.digest_mode` conserva esa ausencia explícita. Los snapshots nunca pueden diferir su SHA; el adaptador rechaza huellas ausentes o mal formadas, y la igualdad entre dos cadenas vacías ya no permite descartar un frame. Replay, exportación y consultas de snapshot siguen calculando el SHA completo del límite actual.

## Protocolo por campos, negociado

`get_catalog.mapFieldChangesV1=true` habilita esta petición opcional:

```json
{"view":"map-columns-v1","entityMode":"changed","provinceMode":"changed-fields-v1"}
```

La respuesta usa `asabiya/map-fields-delta-v1`. `provinces` contiene únicamente los campos modificados; cada campo tiene `id` (CellID en orden creciente) y `values` del mismo tamaño. Campos omitidos conservan su valor. Los siete campos son `ownerPolityId`, `peopleId`, `religionId`, `population`, `carryingCapacity`, `fortification` y `era`. No se eliminan ni cuantizan valores. Las comparaciones float32 conservan sus bits, incluido el signo del cero.

La base privada de sesión se actualiza tanto en modo columnas como campos. Ante una base ausente, inválida o de otro año, la respuesta vuelve a `asabiya/map-columns-delta-v1` con filas modificadas completas. El adaptador admite ambos esquemas en una misma sesión. Un avance de estado sin mapa o una orden invalida la base; `get_state`/`start_history` de mapa la reponen. Se mantienen los clientes anteriores y el modo de entidades dispersas. Se corrige además su comparación recursiva: `reflect.DeepEqual` equiparaba +0 y -0, pudiendo omitir un upsert distinto. El adaptador aplica los upserts recibidos sin volver a deduplicarlos mediante igualdad de Variant por la misma razón.

`worldPopulation` suma los float32 de la base provincial actual en float64, en orden CellID, igual que el recorrido anterior de Godot. Es un agregado de presentación recalculado, no una nueva variable causal. Los formatos anteriores conservan su recorrido de compatibilidad en el cliente.

## Trabajo eliminado y límites

- La captura previa del año reutiliza almacenamiento privado. Todas las celdas, incluido el mar, se vuelven a capturar: no se presupone qué sistemas modifican una provincia. Ninguna publicación comparte este buffer.
- Las columnas modificadas se cuentan antes de reservarlas, evitando crecimiento y copias repetidas.
- Godot valida y prepara un patch en una pasada, sin aplicarlo parcialmente si es inválido. Se mantienen objetos PackedArray separados mediante `duplicate()`. Asignarlos directamente por referencia falló la prueba de inmutabilidad y se descartó. Modificar solo las columnas necesarias también permite que Godot conserve internamente el almacenamiento de las columnas inalteradas entre frames.
- Las capas del atlas comparan sus entradas visuales antes de volver a calcular colores. Ruler, crónicas o población no invalidan un mapa de territorios cuyo propietario/color no cambió. Una geografía nueva invalida siempre la base. Etiquetas, marcadores y asentamientos ya tenían sus propios filtros; no se duplican.
- El ensamblador TCP busca el delimitador solo en el bloque recién recibido. Admite fragmentación en cualquier byte UTF-8 y rechaza registros extra/datos después del LF. Conserva un solo request pendiente, límite de memoria, plazo absoluto, escritura parcial y ausencia de reintentos de años inciertos.

El perfil identifica SHA como coste dominante. No se introducen compresión ni transporte binario: no resolverían ese coste y agregarían un contrato nuevo. Las mejoras por campos se justifican en ventanas tempranas; no se afirma una aceleración universal para campañas con miles de entidades o cambios densos de todos los campos.

## Diálogo y comprobaciones

La prueba renderizada detectó que el primer cálculo de altura de labels con autowrap podía ampliar el diálogo por encima de 3000 píxeles y ocultar los botones. Se reemplaza por tres líneas de descripción y labels sin autowrap en ese diálogo. Se verifica la primera apertura en 1366×768, 1600×900 y 1920×1080 a 100 %, 125 % y 150 %: 27 comprobaciones de límites. Las capturas locales usan OpenGL/llvmpipe en Linux; no son validación gráfica de Windows ni benchmark de Iris Xe. El smoke de arranque real 48×24 también produjo las cinco capturas previstas y cerró el servidor; ese backend software emitió avisos de MSAA y no representa el renderer Windows.

Verificaciones locales: suite Go completa, bytes canónicos y reconstrucción por campos en mundos 24×16 y 400×200; 141 checks de protocolo/adaptador/capas, 23 de geometría, 85 de UX, 203 de sesiones y 148 checks de observación, Fast-Forward, pausa, replay y pérdida de conexión. Referencia HTML verificada sin cambios. El workflow Windows de esta entrega está configurado para comprobar además los golden originales, exportación y regresiones del cliente.

## Reproducción

Usar Go 1.27.2 y Godot oficial 4.7.2 con los hashes de `client/tools/godot-pins.txt`. Mantener semillas `Asabiya`/`1`, dimensiones 400×200 y exactamente la misma cantidad de años. No ejecutar benchmarks competidores a la vez.

```sh
go test ./...
go test -run '^$' -bench BenchmarkFieldWirePublication -benchtime=50x -count=3 -cpu=2 ./internal/interop
```

`tools/benchmark-publication.ps1 -Editor <godot> -Server <asabiya-server> -Samples 50 -Repeats 3` compara columnas y campos con SHA anual exacto, aplicación completa, capas Terreno/Pueblos y trazas por etapa. Comprueba el digest final y la ventana anual de todas las muestras. El tiempo de la consulta final de replay queda fuera de la medida. El contador `staticBytes` es memoria estática de Godot, no RSS ni VRAM.

Para medir el equipo objetivo con la interfaz gráfica, el paquete conserva `measure-throughput.ps1`. No equiparar años/s de un benchmark headless con FPS o rendimiento de la laptop.

## Resultados locales comparables (Linux cloud, no GPU)

Tres repeticiones alternadas, mundo 400×200, 50 años consecutivos, SHA completo en ambos lados, Godot 4.7.2, aplicación completa headless. Medianas de tiempo; no se comparan SHA anual y checkpoint como si fueran el mismo trabajo:

| Mapa | Base 8ebaadf con SHA anual | Esta entrega con SHA anual | Reducción de tiempo |
|---|---:|---:|---:|
| Terreno | 140,06 ms/año | 128,46 ms/año | 8,3 % |
| Pueblos | 172,04 ms/año | 152,55 ms/año | 11,3 % |

Pueblos pasa de 5,81 a 6,56 años/s (12,8 % de aumento de throughput). La memoria estática reportada por Godot con Pueblos baja de 145.503.895 a 119.254.098 bytes (18,0 %); con Terreno baja de 135.063.723 a 108.484.410 bytes (19,7 %). Hay variación entre muestras: Terreno base 138,52–172,02 ms y optimizado 127,64–128,74 ms; Pueblos base 168,59–198,29 ms y optimizado 149,82–172,21 ms. Tres muestras no eliminan la variabilidad del host compartido.

El benchmark Go de 50 años después de 20 de calentamiento compara columnas y campos dentro de la misma implementación, con entidades dispersas y SHA anual: 659.584 frente a 549.366 bytes/año (~16,7 % menos), medianas 95,21 frente a 95,96 ms/año (sin aceleración Go adicional demostrada). La reserva de columnas por tamaño exacto también reduce asignaciones. El benchmark de publicación completa Go conserva el mismo SHA y reduce las asignaciones aproximadamente a la mitad al reutilizar la captura previa.

Desglose de una ejecución perfilada comparable con Pueblos, excluyendo inicialización (ms por año; porcentajes del tiempo completo). Es una muestra independiente de las medianas anteriores:

| Etapa | Base | Optimizado | % optimizado |
|---|---:|---:|---:|
| Cálculo causal del año | 6,84 | 6,30 | 4,4 % |
| Captura previa | 3,15 | 2,47 | 1,7 % |
| SHA canónico completo | 86,37 | 79,53 | 55,9 % |
| Detección provincial posterior | 3,18 | 2,98 | 2,1 % |
| Entidades | 0,19 | 0,18 | 0,1 % |
| Resto de preparación de sesión | 1,56 | 1,87 | 1,3 % |
| Serialización JSON Go | 4,24 | 2,99 | 2,1 % |
| Escritura del socket | 0,15 | 0,17 | 0,1 % |
| Parseo JSON Godot | 7,20 | 4,14 | 2,9 % |
| Validación y aplicación del delta | 11,97 | 13,68 | 9,6 % |
| Construcción del frame | 5,71 | 0,74 | 0,5 % |
| Aplicación en UI/mapa | 25,24 | 14,87 | 10,4 % |
| Entrega, espera y planificación restantes | 9,38 | 12,39 | 8,7 % |

La validación estricta por campos cuesta algo más que el adaptador antiguo; el ahorro se concentra en SHA, memoria, JSON, publicación del frame y capas. La categoría restante es la diferencia contra el intervalo completo, no una medición independiente de la red. No se suman métricas anidadas de request/handle con sus propias etapas. Los digests finales de todas las muestras son `a7ffe7b3bd9b66d6605add0e9c41ce0a9e0be455bc0840950b902b16bde52933`.

La medición causal acotada encontró el primer estado natural en el año -4023, tras 4977 avances del mundo 400×200. `ASABIYA_MATURE_PUBLICATION=1 go test -v -count=1 ./internal/interop -run '^TestMatureFieldPublicationWindow$'` permite repetir una ventana de publicación tras 5500 años completos, con reconstrucción provincial, metadatos y replay comparados; no forma parte del arranque normal de las suites.

La ventana de 5500–5550 años también pasó la reconstrucción provincial, comparación de metadatos y replay: año final -3450, un estado vivo, SHA `5a8caede2fbaa7245eebc58fd86285a989a5070346af0bbf247278b4203134b7`. En esa muestra Go, columnas y campos tardaron ~110,5 ms/año ambos; los bytes bajaron de 826.275 a 703.766. No demuestra aceleración del cálculo ni cobertura de guerras masivas. La reducción de bytes no se presenta como reducción proporcional del tiempo.
