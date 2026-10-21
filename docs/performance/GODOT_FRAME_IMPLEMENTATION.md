# Fase 2 — implementación del rendimiento del cliente Godot

**Estado: implementación preparada; fase abierta y pendiente de validación del usuario y ChatGPT.** No se ha ejecutado Godot, el editor, el juego, suites, pruebas headless, benchmarks, CI ni compilaciones/exportaciones para esta fase. No hay un ZIP nuevo ni resultados de FPS. Los 30/60 FPS siguen siendo objetivos.

## Base y diagnóstico

Rama: `perf/godot-frame-optimization`, creada exclusivamente desde `consolidation/asabiya-native-windows-x64-20261020` en `79035761f1e61041a3ccbf74b648577e53ba7150`. Al comenzar, main estaba en `714d06c3a9d3ce9d69dbb184161a99b2c78e82f1`. No se integraron ramas adicionales. La consolidación y main no se modifican.

La [auditoría previa](GODOT_FRAME_AUDIT.md) describe el recorrido inspeccionado y separa hechos de hipótesis. Los 16–17 FPS sostenidos y P95 de 100–115 ms son las cifras Windows aportadas por el usuario; no son mediciones nuevas de esta implementación.

Hechos encontrados en código:

- Cámara: muestreo de altura y aplicación de pose cada frame, incluso en reposo; cola de interpolación sin final explícito.
- Mapa: peticiones repetidas a listeners y propiedades visuales con vista inmóvil. El terreno ya tenía caché de LOD y comprobación de texturas iguales: se conservaron.
- Vegetación: worker para generar transformaciones, seguido de conversión/envío de cada instancia en el hilo gráfico; búsqueda y poda aun después de completar el área.
- Asentamientos: cambiar una entidad o renombrarla reconstruía todas las bandas y todas las etiquetas.
- Etiquetas territoriales: centroides recalculados por cambios de nombre y seno/coseno repetidos para cada celda de una misma columna.
- Capas: colores y validación del vector cultural calculados por provincia aunque dependieran de la entidad.
- HUD: refresh duplicado por los eventos frames_changed/status_changed; disponibilidad de mapas invalidada por cada objeto HistoryFrame nuevo.
- Perfil: sólo métricas globales, con flush por registro. No separaba subsistemas.

Estos hechos justifican eliminar trabajo redundante; **no prueban qué proporción de los 60–80 ms de procesamiento corresponde a cada sistema**. Los shaders de relieve, sombras, MSAA y SSAO pueden seguir limitando el resultado. No se han modificado para intentar conseguir una cifra de FPS.

## Archivos y cambios técnicos

| Archivo bajo `client/godot/scripts/` | Implementación |
|---|---|
| `camera/strategy_camera.gd` | Cierra la interpolación en su extremo; evita `_apply` y muestreo de relieve al quedar inmóvil; conserva sondeo de entrada. Invalida ante parámetros de superficie/proyección y resize. La cámara se procesa antes que el mapa. |
| `map/map_view.gd` | Actualiza listeners por cambios de transform, proyección, viewport o invalidación explícita. Niebla/sombras sólo al cambiar distancia; minor_rivers sólo al cambiar su valor. Hover sigue respondiendo a ratón, cámara y cambios de control UI bajo el puntero. |
| `map/terrain_renderer.gd` | Conserva geometría y cachés de texturas. Añade histéresis de LOD: refinamiento inmediato, simplificación con 8% de margen; nunca elige menos detalle que el criterio anterior. Invalida al cambiar parámetros y mide LOD/subidas de overlays. |
| `map/vegetation_layer.gd` | Bombea su único worker independientemente de la cámara; deja de procesarse cuando no falta trabajo. Busca/poda al cambiar foco o contenido. Prepara buffers numéricos en worker. Publica como máximo un tile por frame, incluidos callbacks repetidos en ese frame. |
| `map/instance_bands.gd` | Empaqueta transformaciones en el formato 3×4 de MultiMesh y usa una asignación de buffer por modelo, en vez de llamadas por instancia. Recursos gráficos sólo en main thread. Conserva colores, wrap, sombras y rangos; propaga cambios de calidad a bandas ya existentes. |
| `map/settlement_layer.gd` | Mantiene layouts por asentamiento y pertenencia por tile. Recompone sólo tiles afectados por altas, bajas, movimientos o cambios geométricos. Renombrar conserva las mallas. Reutiliza etiquetas por ID y cambia sólo su presentación. |
| `map/history_overlay.gd` | Cachea centroides según la distribución de celdas y trigonometría por longitud del mundo. Reutiliza materiales de marcadores/rutas. Evita recolocar anotaciones si wrap/zoom y contenido no cambian; las firmas incluyen relieve. |
| `map/map_layers.gd` | Paletas/colores culturales y agrupaciones calculados una vez por entidad antes del recorrido de celdas; consulta de disponibilidad de población fuera del bucle tecnológico. Mantiene fórmulas, colores y leyendas. |
| `ui/hud.gd` | Firmas por entradas reales para mapas, timeline, figuras, desastres y contadores. Conserva filtros, navegación y estado de pausa. No reasigna botones de escala, brújula ni posición del tooltip si no cambian. Quita el interruptor Fluido como solicitó previamente el usuario. |
| `data/performance_trace.gd` | Un solo propietario del archivo, scopes por subsistema y agregación por ventanas; sesiones añadidas al archivo sin borrarlo al crear otro mundo. |
| `app/main.gd` | Comparte el profiler, conecta invalidaciones de año/capa/ajustes y añade scopes de aplicación de frames, HUD, capas y poll. El flujo de comandos/publicaciones sigue igual. |

También se actualizan `client/godot/tests/atlas_ux_regressions.gd` (expectativa del interruptor eliminado, **sin ejecutarlo**), `AGENTS.md`, `README.md`, `docs/integration/LEEME.txt`, `docs/integration/FLUID_PLAYBACK.md` y los dos documentos de esta carpeta.

`bridge_source.gd`, NativeFrameDecoder y el protocolo TCP quedan sin cambios: ya decodifican en worker. No se añaden lotes, descarte de publicaciones, concurrencia causal ni nuevos comandos. La reproducción conserva cada año, checkpoints cada 25 años y comprobación exacta al pausar o dar un paso. El control interno de SHA anual sigue disponible para las herramientas diagnósticas existentes, sin un selector de modo en el juego.

## Instrumentación optativa

Sin `ASABIYA_PROFILE_PATH` no se abre archivo ni se consultan monitores de rendimiento. Los scopes devuelven inmediatamente con inicio cero y no acumulan muestras. Con la variable activa:

- JSONL, esquema `asabiya/client-profile-v2`; cada fila identifica `traceSession`.
- Cabecera con CPU, sistema, Godot y renderer. Se añade una cabecera nueva al recrear mundo; no se trunca la sesión anterior.
- Ventanas de aproximadamente 2 segundos con los campos compatibles `fps`, `frameP50Ms`, `frameP95Ms`, `frameP99Ms`, `processMs`, memoria estimada, draw calls, objetos, nodos y huérfanos.
- Contexto: año, capa, reproducción, calidad, relieve, distancia/zoom y tamaño del viewport. Es el último contexto observado de la ventana; una ventana puede cruzar cambios de año o vista.
- `cpuScopes`: `camera`, `map-view`, `terrain-lod`, `hover-pick`, `vegetation`, `vegetation-publish`, `settlements-view`, `annotations-view`, `bridge-poll`, `frame-apply`, `settlements-apply`, `annotations-apply`, `chronicle`, `overlays`, `terrain-overlay-upload`, `hud-refresh`, `hud-process`.
- Por scope: llamadas, tiempo total, media, máximo y P50/P95/P99 por llamada. Hasta 3,600 muestras por scope/ventana, con `sampledCalls` y `unsampledCalls`; totales y máximo cuentan todas las llamadas. Frametime también limita sus muestras a 3,600 por ventana.
- Se ordenan copias al cerrar la ventana; no hay JSON ni flush por scope/frame. El archivo hace flush al cerrar la ventana o la sesión. `trace-end.partialWindowFrames` indica el tramo final que no llegó a formar otra ventana completa.

Los scopes miden **tiempo transcurrido en código del hilo principal**, no ciclos de CPU ni tiempo GPU. Son anidados: por ejemplo `bridge-poll` puede contener `frame-apply`, y éste contener `overlays`. **No sumar los totales de scopes ni restarlos de TIME_PROCESS para inventar un coste residual.** `vegetation` mide planificación/publicación en main thread, no la ejecución del worker. `terrain-overlay-upload` mide la llamada de preparación/envío, no su finalización GPU.

El registro tiene coste al estar activo y crecerá en disco según la duración; la memoria de muestras está acotada. Comparar también ejecuciones sin perfil. No ejecutar dos procesos que escriban al mismo archivo; usar rutas distintas por revisión y repetición. Descartar ventanas de carga inicial, resize, cambio de calidad o menú al comparar un mismo escenario.

## Revisión estática realizada

- Lectura de los flujos de frame, entrada, cámara, geometría, async de vegetación, capas, decoder/TCP y HUD antes de editar.
- Revisión manual de invalidación: alta/baja/movimiento/renombre/tier de asentamientos, cambios de relieve y calidad, frames consecutivos, snapshot exacto tras pausa, seek de timeline, modo de etiquetas, viewport y wrap.
- Parseo sintáctico externo con `gdtoolkit 4.5.0` de los 12 `.gd` modificados. Esto **no valida el tipado/API de Godot 4.7.2 ni sustituye su compilación**.
- `git diff --check` y revisión del alcance contra la base. Go, productores, decoder, bridge, shaders, project.godot, referencia, golden, recursos visuales y workflows se mantienen sin cambios.

No se ha ejecutado ningún test ni se afirma corrección experimental o una mejora de rendimiento. No se abre una PR que dispare suites automáticas: la entrega es la rama con sus commits.

## Compilación Windows x64 — a ejecutar por ustedes

Requisitos: Windows x64, PowerShell 7, Git, Go de `.go-version` (1.27.2) en PATH y espacio para el editor/templates oficiales Godot 4.7.2. El script verifica descargas fijadas. Se puede pasar `-GodotPath` con la ruta del editor console ya instalado.

```powershell
git fetch origin perf/godot-frame-optimization
git switch perf/godot-frame-optimization
$revision = (git rev-parse HEAD).Trim()
pwsh -NoProfile -File .\tools\package-windows.ps1 `
  -OutputDirectory "$PWD\build\phase2" `
  -SourceRevision $revision -ValidationSummary "Fase 2: revision estatica; testing pendiente"
```

El comando produce una **carpeta** Windows completa; no crea ZIP. Realiza importación/compilación/exportación del cliente y compilación de Go, sin lanzar una partida ni suites. Revisar los logs de import/export y el manifiesto. Si ya existe una rama local del mismo nombre, confirmar que corresponde a esta entrega antes de compilar. Para conocer el SHA final: `git rev-parse HEAD`; cotejarlo con el mensaje de entrega y `BUILD-MANIFEST.json.sourceRevision`.

Para una comparación limpia con la base, usar otro checkout y otra carpeta de salida; no sustituir binarios aislados:

```powershell
git worktree add --detach ..\asabiya-phase2-base 79035761f1e61041a3ccbf74b648577e53ba7150
pwsh -NoProfile -File ..\asabiya-phase2-base\tools\package-windows.ps1 `
  -OutputDirectory "$PWD\build\phase2-base" `
  -SourceRevision "79035761f1e61041a3ccbf74b648577e53ba7150" `
  -ValidationSummary "Base de comparacion"
```

## Procedimiento de validación — usuario y ChatGPT

1. Compilar ambas revisiones; detenerse ante errores de importación/exportación. El parser externo no garantiza que el compilador Godot acepte el proyecto. Ejecutar las regresiones existentes de atlas, publicación profunda, reproducción fluida, throughput y rendimiento cuando ustedes decidan; no se ejecutaron en esta fase.
2. Mantener equipo conectado a corriente, mismo modo de energía, monitor, resolución, escalado UI, renderer Forward+, calidad y relieve. Registrar revisión, GPU/driver y configuración. Usar Asabiya, history seed 1, 400×200 y detail 4 en ambas. Los ajustes persistentes deben coincidir.
3. Comparar primero una historia pausada en el mismo año: 60 s de cámara quieta, acercamiento continuo, paneo/rotación por el mismo recorrido y otros 60 s quietos. Repetir en continente, región y provincia. Confirmar que la vegetación termina de aparecer con cámara quieta y no desaparece al estabilizar la vista.
4. Reproducir a 1 año/s para comparar un mismo tramo histórico por tiempo; luego medir Máxima por separado comparando también años equivalentes. Incluir una sesión sostenida de al menos 11 min 48 s. Una revisión más rápida puede llegar a una época más costosa: no atribuir esa diferencia de carga a una regresión gráfica sin controlar el año.
5. Durante reproducción y cálculo: cámara/rueda de precisión/zoom inverso, arrastre, selección y apertura de paneles deben responder. Pausar entre checkpoints; comprobar la huella exacta y reanudar sin perder/duplicar años. Dar un paso manual, consultar años anteriores y volver al directo. Comprobar comandos/intervenciones existentes y replay con las herramientas previas en un mismo escenario.
6. Revisar capas estáticas e históricas, leyendas, filtros, cifras, figuras y desastres. Con cámara quieta, observar nuevas ciudades, renombres, cambios de tier/features, abandono y movimientos; sus edificios/etiquetas deben cambiar sin afectar asentamientos ajenos. Para bajas/movimientos no presentes en la partida inicial, usar las fixtures/herramientas de ustedes.
7. Cambiar calidad y relieve en pausa y reproducción; redimensionar, cruzar la costura longitudinal en ambos sentidos y acercarse a los polos. Buscar saltos, grietas de LOD, árboles/edificios girados o desplazados, etiquetas congeladas, rutas o marcadores duplicados y hover que quede sobre un panel.
8. Repetir el recorrido tras varias idas/vueltas y crear otro mundo. Vigilar memoria, objetos, huérfanos y retorno de tiles al alejarse. Cerrar durante una generación de vegetación y durante cálculo anual.
9. Recoger al menos tres repeticiones comparables por revisión. Comparar ventanas por escenario/año: FPS sostenidos y frametimes P95/P99, no sólo el mejor intervalo. No promediar percentiles para presentarlos como un percentil global. Si el perfil altera el resultado, informar el coste y priorizar la comparación sin perfil para FPS.

Para capturar el perfil desde PowerShell, antes de iniciar el cliente:

```powershell
New-Item -ItemType Directory -Force .\captures | Out-Null
$env:ASABIYA_PROFILE_PATH = "$PWD\captures\phase2-repeticion1.jsonl"
Start-Process -FilePath "$PWD\build\phase2\AsabiyaNative.exe" -Wait
Remove-Item Env:\ASABIYA_PROFILE_PATH
```

Usar otro nombre y ejecutable para la base. Guardar los JSONL junto con el manifiesto, logs y la secuencia de acciones. Una medición GPU específica requiere el profiler gráfico correspondiente; los scopes de esta entrega no la reemplazan.

## Riesgos y puntos pendientes

- El formato de buffer MultiMesh debe validarse visualmente en Forward+ Windows: transformación, colores, wrap, AABB y culling. Se preservaron las mismas matrices, modelos y rangos; el camino de publicación es distinto.
- La vegetación sigue limitada a un worker y un tile publicado por frame. No hay garantía de milisegundos máximos para una asignación grande ni una subida de GPU; los scopes permitirán detectar esos picos.
- La histéresis retiene detalle fino algo más de tiempo y puede incrementar transitoriamente triángulos cerca de un umbral. No rebaja calidad; verificar su coste y ausencia de oscilaciones visuales.
- El cierre de easing usa una tolerancia pequeña (mínimo 0.00025 unidades para el foco y relativa a distancia), para superar la precisión de Vector3. Verificar zoom al cursor, límites y cruces de costura con la resolución objetivo.
- Las cachés dependen de publicaciones inmutables y de invalidar mundo/contenido/ajustes. Se revisaron las rutas actuales, pero errores de etiquetas o geometría obsoleta requieren validación funcional.
- Algunas tareas anuales siguen atómicas en main thread, como un overlay completo o una reconstrucción territorial. No se introdujo un pipeline asíncrono nuevo que cambie el orden de visualización/comandos. Su coste pendiente se podrá separar con la instrumentación.
- No hay mediciones nuevas de CPU/GPU. Si continúa un límite gráfico en shaders/sombras, harán falta datos específicos antes de otra intervención.

El SHA completo final de la rama se entrega en el mensaje de cierre. La fase permanece pendiente hasta recibir mediciones y validación funcional comparables.
