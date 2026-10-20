# Misión A: rendimiento y estabilidad

Base: `integration/go-godot-windows` en `04591260d97c7ff8a2dfcbe507aee2e9da774752`.
Rama de entrega: `mission/performance-stability`.

## Implementación

- Go obtiene las ocho propiedades provinciales de mapa bajo el mismo bloqueo anual, sin crear antes las provincias detalladas con 32 valores tecnológicos. Snapshot, delta completo, reglas, calendario, comandos, digest y replay conservan sus contratos. Las publicaciones compactas son copias independientes.
- La simulación conserva una única huella del mundo inmutable; publicar estados y replay deja de recalcular toda la geografía en cada año. Se conserva exactamente el texto del digest.
- La inicialización histórica de Go se encola antes de construir la escena 3D, permitiendo solapar ambos trabajos.
- Se conserva la adaptación r3 de enteros JSON exactos y su cobertura de sesión, loopback y argumentos inválidos.
- Vegetación conserva tiles próximos a la cámara y desaloja los lejanos. Los cambios de asentamientos invalidan sólo tiles que intersecan los claros modificados. La tarea usa copias de claros y parámetros de relieve; una invalidación descarta el resultado al terminar sin bloquear la publicación anual. El cierre del nodo sí reúne la tarea antes de liberar sus datos.
- Las mallas de terreno reservan vértices, índices y bordes una vez por LOD; desaparecen los arrays temporales por quad. Las posiciones y los índices mantienen la topología anterior.
- Con cámara, FOV, tamaño de viewport y calidad iguales, el cálculo de LOD se reutiliza. Las texturas de color y claves se suben por separado sólo si cambian. El contador de triángulos incluye las faldas.
- El muestreo bicúbico usa cuatro filas escalares sin un array auxiliar por consulta.
- El puente rechaza un segundo arranque sobre una sesión abierta, verifica la generación recibida, aplica el plazo de respuesta también si llegan fragmentos continuamente, prioriza el cierre sobre peticiones en cola y libera las publicaciones al cerrar. Los fallos terminales cierran el proceso poseído. Un avance de aceptación incierta nunca se reintenta: recuperar requiere una nueva sesión con el control existente.

Los archivos de aplicación, HUD, cámara, escenas, tema y shaders no forman parte de esta entrega.

## Validación y paquete en GitHub

El workflow `Performance and Windows package` ejecuta en Windows x64:

1. Regresiones de `internal/interop`, incluida r3.
2. Reconstrucción durante 30 años con dos semillas: publicaciones completas y compactas deben conservar metadatos, provincias, RNG, digest y replay; comprobación de inmutabilidad y signo del cero. Incluye el caso concurrente de consultas y escritor anual.
3. Benchmark de tres años de cada camino, con inicio fuera de la región medida. Publica ns/op, B/op, allocs/op y bytes de JSON. El mundo es 400×200, detalle 4, sin superficie fina porque el benchmark mide publicación anual.
4. Comprobaciones Godot headless de topología LOD, muestreo bicúbico, desalojo de tiles, claros selectivos e invalidación de una tarea real.
5. Compilación con Go 1.27.2, importación/exportación con Godot 4.7.2 fijado por SHA-256, ZIP Windows y manifest de archivos.

Los resultados de ejecución se consultan en Actions, no se deducen del análisis de código. El ZIP sólo se publica si las comprobaciones y la exportación terminan correctamente. No se lanza el juego exportado.

Las pruebas r3 ejecutadas antes de pasar a trabajo exclusivo en GitHub aprobaron la base. Esa evidencia no valida las modificaciones de esta misión.

## Primer resultado medido

[Actions 39360654237](https://github.com/Jesejojo3/asabiya-native/actions/runs/39360654237), revisión `f6104ae`, Windows x64 / Go 1.27.2 / AMD EPYC 7763:

| Camino de publicación | Tiempo por año | Bytes asignados por año | Asignaciones | Bytes JSON |
| --- | ---: | ---: | ---: | ---: |
| Provincias completas y proyección | 196,78 ms | 83.935.418 | 7.650 | 2.531.505 |
| Captura compacta | 154,12 ms | 20.813.581 | 7.629 | 2.531.505 |

Muestra preliminar de tres años por camino: ~75,2 % menos bytes asignados y ~21,7 % menos tiempo. Ambos caminos de esta comparación ya reutilizan la huella del mundo; no mide por separado el beneficio de esa caché. Los digest finales coinciden. No representa RAM máxima, FPS ni una partida prolongada. Las regresiones Go y la exportación pasaron en esa ejecución; un error de tipos del nuevo script de pruebas Godot impidió publicar el ZIP y se corrigió posteriormente.

## Medición gráfica reproducible

El trazado está desactivado por defecto. Para activarlo en una sesión Windows:

```powershell
$env:ASABIYA_PROFILE_PATH = Join-Path $PWD 'asabiya-performance.jsonl'
.\AsabiyaNative.exe
Remove-Item Env:ASABIYA_PROFILE_PATH
```

El archivo contiene entorno, tiempo de preparación de texturas y geometría, y ventanas de dos segundos con FPS, percentiles 50/95/99 de intervalo entre frames, tiempo de proceso, memoria estática, recursos de render estimados, draw calls, nodos y huérfanos. Cada ventana retiene como máximo 3600 muestras. La telemetría no cambia la interfaz.

Usar la misma GPU, controlador, resolución, calidad y cámara para comparar base y rama. Registrar al menos: vista fija cercana, desplazamiento prolongado que recorra el mapa, cambio de capas históricas, reproducción anual y diez ciclos de crear/cerrar sesión. Revisar p95/p99, memoria después de estabilizarse, número de tiles/nodos y logs de servidor. Separar arranque frío y caliente. La memoria de render que expone Godot es una estimación de recursos; la RAM de proceso y VRAM del controlador requieren además el monitor del sistema. El modo headless no sirve para certificar FPS ni VRAM.

## Pendiente de medición

El workflow verifica protocolo y publicación y produce el paquete. Quedan pendientes la comprobación gráfica en GPU real, perfiles largos de RAM/VRAM, reinicios repetidos y capturas antes/después de frametimes. No se afirma una mejora porcentual ni un FPS objetivo hasta disponer de esas mediciones. No se reduce la calidad visual ni se alteran shaders a ciegas.
