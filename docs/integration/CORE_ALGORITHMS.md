# Optimización de algoritmos del motor anual

Base: `perf/annual-go-hotspots@13d9d82055c8ae8ed5c1e0c6d5114d0ccd8d8beb`. Esta entrega modifica los cálculos del motor Go. Mantiene la interfaz, la frecuencia de publicación y comprobación, las reglas, el calendario, los RNG y el formato de todas las huellas.

## Algoritmos

### Vecindad de salida y circunscripción

`exitPass` calculaba la calidad, densidad libre y penalización política de una misma provincia hasta 48 veces, una por cada vecino que la consultaba. Ahora construye una sola vez el campo de contribuciones del año y lo comparte entre las cuatro bandas de la pasada. Las sumas conservan su orden original fila/columna; no se usan sumas prefijas que alteren el redondeo.

La matriz lleva tres columnas de margen a cada lado, copiadas desde la longitud opuesta. Se elimina el módulo del bucle de vecinos. Los polos siguen recortados y el denominador cuenta los mismos vecinos, incluidos los oceánicos. Cada provincia mantiene su aporte y sus float32 de salida.

El trabajo numérico caro pasa de hasta 48 cálculos por consulta a un cálculo por provincia fuente y lecturas de memoria. La suma de la vecindad sigue siendo O(48N), conservando su aritmética exacta. El buffer se reconstruye cada vez y se recicla mediante un pool; no hay caché de población ni de propiedad. A 400×200 son aproximadamente 0,62 MiB por pasada activa. Se limpia antes de reutilizarlo entre mundos con costas diferentes.

### Difusión tecnológica

Cada banda construye una lista ordenada de las tecnologías conocidas al inicio de esa llamada, incluyendo navegación a vela como antes. El bucle provincial recorre esa lista en lugar de visitar las 32 entradas y descartar las desconocidas una a una. Conserva el orden ascendente, actualizaciones in situ, descubrimientos entre bandas, empates y sorteos de conversión religiosa.

### Operaciones numéricas frecuentes

Los límites mínimo/máximo de los bucles calientes usan intrínsecos del compilador con argumentos explícitamente float64. Evitan llamadas fuera de línea sin cambiar promociones ni umbrales float32. Los NaN vuelven a las funciones originales: `math.Min(-Inf, NaN)` y `math.Max(+Inf, NaN)` priorizan el infinito, a diferencia de los builtins de Go. Se comprueban infinitos, ambos ceros y 100 000 parejas de patrones float64 aleatorios.

No se aproximan exponenciales ni otras funciones matemáticas, no se omiten sistemas anuales y no se paraleliza la mutación de la historia.

## Procedimiento de comparación

Go 1.27.2, Linux amd64 cloud, AMD EPYC 7763, GOMAXPROCS=3, mundo procedural 400×200, detalle 4, semillas Asabiya/1. `cmd/asabiya-profile` mide únicamente `AdvanceYear`, excluyendo arranque, calentamiento, transporte, JSON y SHA. Se construyen dos ejecutables con el mismo instrumento: fuente base inalterada y fuente optimizada.

Hay tres ventanas tempranas consecutivas de 1000 años tras 20 años de calentamiento, y tres avanzadas de 300 años tras 10 000 años completos. No son repeticiones de un estado idéntico: cada ventana se compara exclusivamente con el mismo periodo de la otra revisión. Cada informe incluye los límites temporales, RNG inicial/final, Estados vivos, SHA causal, asignaciones y tiempo por etapa. Los benchmarks no se ejecutan simultáneamente.

```sh
go build -o build/asabiya-profile ./cmd/asabiya-profile
build/asabiya-profile -warmup 20 -years 1000 -windows 3
build/asabiya-profile -warmup 10000 -years 300 -windows 3
build/asabiya-profile -warmup 20 -years 1000 -cpu build/core.cpu
go tool pprof -top build/core.cpu
```

## Integridad y alcance

El oráculo de vecindad conserva por separado el algoritmo anterior y contrasta los resultados float32, bordes, océanos, polos, receptores omitidos y reutilización entre mundos. Otra prueba ejecuta historias concurrentes sobre el mismo mundo inmutable y exige huellas idénticas, detectando almacenamiento temporal compartido por error.

Las pruebas y los golden existentes se conservan. La igualdad de los seis puntos de control de esta campaña no es una prueba universal sobre todas las semillas. Las medidas del motor puro tampoco son FPS ni garantizan igual reducción en el tiempo total de Godot o en el PC del usuario.

## Resultados finales del núcleo

| Ventana (años astronómicos) | Estados vivos al final | Antes ms/año | Después ms/año | Menos tiempo |
|---|---:|---:|---:|---:|
| -8980 → -7980 | 0 | 8.688 | 5.857 | 32.6 % |
| -7980 → -6980 | 0 | 9.462 | 6.150 | 35.0 % |
| -6980 → -5980 | 0 | 9.272 | 6.505 | 29.8 % |
| 1000 → 1300 | 126 | 13.333 | 11.216 | 15.9 % |
| 1300 → 1600 | 133 | 13.671 | 11.330 | 17.1 % |
| 1600 → 1900 | 130 | 14.460 | 11.843 | 18.1 % |

Las seis parejas coinciden en año, contador RNG, número de Estados y SHA causal completo. Los datos crudos y las huellas están en `benchmarks/core-algorithms-2026-10-20/`. Los rangos son una reducción de tiempo del 30–35 % en las ventanas tempranas y del 16–18 % en las avanzadas; no una afirmación de esos porcentajes sobre la interfaz completa.

## Verificaciones ejecutadas

- Suite Go completa: pasa; incluye contratos originales y golden existentes.
- `go vet ./...`: pasa sobre la fuente final y el medidor.
- Detector de carreras dirigido a contratos numéricos, vecindad original y tres historias concurrentes: pasa (2,424 s).
- Verificador del HTML original: intacto; no se cambian fixtures.
- El paquete Windows conserva Fluido y todos los recursos del cliente. Su compilación y CI se comprueban por separado de estas mediciones Linux.
