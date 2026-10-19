# Plan de benchmarks — pendiente de implementación

No hay benchmarks Go ni objetivos de rendimiento validados en Fase 0. Los tiempos del smoke sólo documentan el coste de la caracterización JS y no permiten afirmar una mejora de velocidad.

| Medición futura | Fixture y trabajo medido | Métricas |
|---|---|---|
| Construir mundo generado / Tierra | Resoluciones originales y semillas/recursos/reglas con hash; separar carga/inflado de generación/clima | ms/operación, bytes y asignaciones, memoria máxima. |
| Crear historia | Mundo preconstruido, semilla fija; incluir población, pueblos y snapshots iniciales | ms/operación y asignaciones. |
| Año completo | Checkpoint inicial, agrícola, con varios estados y con guerras; años y comandos idénticos | ns/año, años/s, B/op, allocs/op; percentiles de lotes repetidos. |
| Sistemas | `computeK`, tecnología, política, BFS, presagios/cataclismos, snapshots | Tiempo y asignaciones por sistema, tamaño de entidades y fronteras. |
| Historia extensa | 1 000 años desde checkpoints fijados; sin dibujar y con registro histórico activado | Tiempo total, crecimiento de memoria y volumen de eventos. |
| Presentación | Snapshot fijo con mapa, pueblos, estados, guerras y overlays | Tiempo de frame, subida de texturas, memoria GPU; separado del throughput del core. |

Procedimiento propuesto: registrar CPU/RAM/OS, versión Go/Ebitengine/Node, commit, modo energético y concurrencia; calentar; repetir al menos cinco veces; guardar resultados crudos y dispersión. Para Go usar benchmarks con `-benchmem` y número fijo de repeticiones. Para JS fijar runtime y fixture; excluir DOM y hashing del tramo medido. Si el fixture muta durante una iteración, restaurar fuera del tramo o medir esa restauración por separado; nunca comparar años cada vez distintos sin declararlo.

Antes de optimizar, verificar equivalencia del estado final. Comparar JS/Go con igual mapa, reglas, periodo, comandos, eventos y política de snapshots. No quitar clima, tecnología, ecología, religión o enfermedad para mejorar cifras. Primero establecer baseline; después acordar presupuesto de rendimiento y umbral de regresión en una PR revisada. Las resoluciones mayores y nuevas mecánicas quedan fuera del benchmark de compatibilidad inicial.

Pendientes: fixtures tardíos con estados/guerras, restauración reproducible del RNG original, máquina de referencia Windows y ejecución sin GPU. Perf del render sólo puede medirse al existir la app nativa.
