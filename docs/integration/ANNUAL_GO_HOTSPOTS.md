# Avance anual: perfil y optimización de Go

Base: `feature/godot-command-interventions-v2` en `9e6ee0a433dc840256cb66ae8451f5b152dac0a3`, descendiente de los cambios de publicación `perf/deep-throughput-v2`. La rama `main` todavía contiene sólo los primeros bloques; no representa el cliente actual. Esta entrega no integra ninguna rama.

## Cuello de botella medido

En Linux amd64, AMD EPYC 7763, Go 1.27.2, GOAMD64=v1, GOMAXPROCS=3, mundo procedural 400×200, detalle 4, semillas Asabiya/1:

- Cálculo causal puro, primeros 40 años: 7,70 ms/año en la muestra inicial.
- Publicación con columnas y JSON, SHA anual exacto: mediana de 92,48 ms/año antes de esta entrega.
- Codificación y SHA del estado: mediana de 71,68 ms/año, aproximadamente el 77,5 % de ese tiempo.

El perfil CPU identifica `sha256.blockSHANI` y el escritor canónico como trabajo dominante. La biblioteca estándar ya utiliza aceleración SHA de la CPU; no se trata de una llamada accidental al SHA genérico. Godot no participa en estas mediciones.

## Cambio

El escritor numérico guarda la etiqueta de tipo y los bits del valor en una sola pasada. Para mundos de al menos 10 000 celdas con más de un procesador Go disponible, la codificación se solapa con un único trabajador SHA que recibe bloques en el mismo orden. Tres buffers de 1 MiB acotan el trabajo pendiente y se reciclan sólo después de que SHA haya terminado de leerlos. Un pool reutiliza almacenamiento temporal; no reutiliza estados SHA ni resultados de campos causales. Consultas simultáneas reciben buffers propios.

La simulación mantiene su bloqueo durante toda la operación. El trabajador recibe únicamente bytes codificados, nunca referencias a la historia. El cálculo termina antes de publicar la huella. Los mundos pequeños y GOMAXPROCS=1 conservan el camino secuencial. No cambia el protocolo, la frecuencia de SHA, los años observados, la referencia HTML, los fixtures, el calendario ni el RNG.

Se probaron primero buffers de 64 KiB: su coordinación entre hilos empeoró los tiempos. No se utiliza esa configuración en producción.

## Antes y después

Tres repeticiones por revisión, ejecutadas secuencialmente y sin benchmarks competidores, 40 años por repetición, generación inicial excluida del cronómetro. Las cifras comparan el mismo trabajo y los mismos años. Son medianas; la máquina cloud no representa la laptop Windows del usuario.

| Métrica | Base | Optimizado |
|---|---:|---:|
| Publicación Go + JSON | 92,48 ms/año | 81,23 ms/año |
| Avance | 10,81 años/s | 12,31 años/s |
| Codificación + SHA | 71,68 ms/año | 59,55 ms/año |
| Bytes JSON medios | 716 275/año | 716 275/año |
| Bytes asignados, mediana | 3 947 037/año | 4 196 739/año |

Reducción de tiempo del **12,2 %**, equivalente a aproximadamente **13,8 % más años/s**. Las muestras de publicación fueron 91,79/92,48/93,51 ms antes y 81,23/81,66/78,66 ms después. El almacenamiento adicional puede aumentar las asignaciones y la memoria retenida: hasta 3 MiB de buffers por digest paralelo activo, recuperables por GC. La ganancia depende de CPU, memoria y concurrencia; no se presenta como una reducción equivalente de FPS o tiempo total de Godot.

Las seis ejecuciones terminan en el año -8960, con 623 216 sorteos históricos y SHA `9ecde205aabeef5815ee375e58aa21e1ddc0daa6fb5e4563e40d1f4317ac7de0`. La huella del primer año también coincide. Los resultados crudos están en `benchmarks/annual-go-hotspots-2026-10-20/`.

## Verificación y reproducción

```sh
go test -count=1 ./...
go vet ./...
go test -race -count=1 ./internal/sim -run '^(TestDigestPipelinePreservesCanonicalBytes|TestConcurrentDigestPipelines)$'
go test ./internal/interop -run '^$' -bench '^BenchmarkAnnualThroughput/400x200/columns$' -benchtime=40x -count=3 -benchmem
go test ./internal/sim -run '^$' -bench '^BenchmarkStateDigestPipeline$' -benchtime=20x -count=3 -benchmem
```

La suite Go completa y `go vet ./...` pasan. El detector de carreras dirigido también pasa (13,29 s). La suite cubre la publicación por campos utilizada por el cliente, replay, RNG, comandos y comparación canónica original. Los nuevos tests comparan los bytes contra el escritor legado con buffers desalineados y pequeños, NaN y ceros con signo; también contrastan varias consultas concurrentes de un mundo completo contra el SHA legado. El benchmark fijo de digest permite comparar ambos caminos sin cambiar el año entre iteraciones; se incluye para futuras mediciones, sin atribuirle resultados de esta campaña.

Se compila por separado el servidor para Windows amd64 con CGO desactivado y GOAMD64=v1. La ejecución Windows y la validación gráfica quedan pendientes; compilar no acredita esas pruebas.

## Límite pendiente

El SHA completo sigue siendo el coste dominante. Esta corrección no convierte 12 años/s en cientos. Aumentar sustancialmente el avance observado requiere revisar por separado la obligación de generar una huella histórica completa en cada publicación, preservando marcadores explícitos y las garantías del archivo anual. Esta entrega conserva esa obligación y no activa checkpoints implícitos.
