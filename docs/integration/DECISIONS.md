# Decisiones de integración

| Decisión | Motivo y límite |
|---|---|
| Merge de PR #8 dentro de rama nueva desde #7 | Conserva ambos historiales, incluida dependencia #6. Ninguna integración a main. |
| Un solo servidor TCP asabiya/local-v1 | Se retira el protocolo stdio propuesto del camino activo; no se duplica el motor. |
| Enteros JSON exactos en la frontera del protocolo | Godot emite 4.0 al serializar configuraciones. Se normaliza sólo la escritura de números matemáticamente enteros, sin float64 intermedio ni redondeo, antes del decoder Go. Los tipos, rangos y validación del núcleo permanecen vigentes. Incluye sesión, comandos, consultas y metadatos de recursos. Ver JSON_INTEGER_FIX.md. |
| Endpoint JSON atómico más arranque de proceso sin consola | Godot descubre el puerto 0 sin lectura bloqueante de stdout ni configuración humana. |
| Hilo trabajador propietario del transporte/decodificación | El hilo gráfico no espera el cálculo anual ni el JSON de Go. La publicación llega terminada. |
| AdvanceYear atómico; lotes como peticiones anuales | Pausa puede cortar al terminar el año aceptado. No hay pasos parciales o simulación en Godot. |
| Vistas map-state/map-delta opcionales | Reducen campos repetidos. Los detalles se consultan por ID, en el mismo protocolo y con año. |
| Estado visible cada 50 años en lotes y al final | Evita transmitir todo por cada año de una corrida larga. El avance individual sigue aplicando delta. |
| geography-v1 como fuente activa; .asw como herramienta heredada | Son formatos distintos. Se traducen explícitamente nombres/offsets y se verifica el binario. |
| Estado 0 sin propietario; -1 en otras clases | Evita convertir el mar o un territorio sin Estado en una entidad artificial. |
| Copias de arrays y caché acotada | Mantiene publicaciones anteriores inmutables y limita memoria del cliente. |
| Rasters originales extraídos del HTML en tiempo de carga | No se inventa procedencia ni se redistribuyen recursos bajo una licencia no comprobada. |
| math de Go; native/world-v3 para fuentes extendidas | Producto Windows x64 personal. No se promete paridad bit a bit con V8. |
| Sin edificio nuevo ni dinastía artificial | Casas decorativas; fortificación y población provincial son proxies explícitos. |
| Validación final del usuario | El usuario autorizó posteriormente las pruebas específicas del contrato numérico. La comprobación visual y de juego queda al usuario; se exporta sin abrir el juego ni ejecutar suites históricas extensas. |

Riesgos pendientes: comportamiento de GPU real, carga/decodificación inicial y pausas de publicación en el hilo gráfico, memoria en historias muy largas, casos heredados NaN, importaciones transparentes/ICC, completitud de campos de eventos estructurados y reproducibilidad tras cambios de CPU/toolchain. No se ocultan con golden nuevos ni se declaran resueltos por compilar.
