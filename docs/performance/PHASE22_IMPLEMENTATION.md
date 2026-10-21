# Fase 2.2 — índices históricos, escena diferencial y picking

**Entrega para validación; no aprobada experimentalmente.** Base verificada: `perf/godot-frame-optimization@238085832ea8fdd8d43e753908699d1810e40337`. Se continúa la misma rama y la PR #22, abierta y draft al comenzar. Main sigue en `714d06c3a9d3ce9d69dbb184161a99b2c78e82f1` y consolidación en `79035761f1e61041a3ccbf74b648577e53ba7150`. Ninguna integración ni modificación de esas ramas.

El usuario aporta una sesión Windows/Iris Xe de unos 7 min 39 s: 17.5 FPS medianos, cerca de 16 FPS en zoom cercano, ventanas de 8–12 FPS en épocas avanzadas, hover de unos 4.35 ms y frame-apply de unos 44.3 ms. No se recibió el JSONL completo en esta petición: no se recalcularon medias, percentiles ni atribución causal a partir de esas cifras. No se promete alcanzar 30/60 FPS.

## A. Diagnóstico y correcciones

En la tabla, L = celdas terrestres, N = celdas totales, F = frames retenidos (hasta 24), G = grupos/etiquetas, E = eventos visibles, C = asentamientos, R = filas del inspector y Δ = elementos visuales modificados. Complejidades de código, no mediciones de tiempo.

| Función y evidencia estática | Causa / antes | Implementación / después | Límites y riesgos |
|---|---|---|---|
| `main._show_people` recorría `source.years()` y todas las celdas de cada frame para cada refresh. | O(F×L) en el hilo gráfico, incluso al volver a consultar frames inmutables. Coste amplificado si el pueblo sigue seleccionado durante reproducción. | `FrameVisualIndex.build` prepara totales por pueblo en el worker. El panel consulta F resultados: O(F) en main. Los frames publicados retienen su propio índice. | El cómputo no desaparece: se añade O(L) por publicación al worker, compartido entre todos los grupos; medir su coste y competencia por CPU. No se atribuyen los 44.3 ms completos a este panel sin el registro. |
| `main._show_state`, `_show_cell` y `HistoryFrame.settlement_by_id`. | Recorridos O(L), O(C), O(C) respectivamente durante consultas o actualización de selección. | Totales por Estado y diccionarios de asentamientos por ID/celda, derivados en worker. Consultas O(1), O(1+k) y O(1), con k = asentamientos de la celda. Fallback exacto para frames manuales sin índice. | Totales sólo de celdas terrestres, como los recorridos sustituidos; conserva orden de suma. No hay balance ni historia nuevos. |
| `HistoryOverlay.rebuild/_build_labels`: una distribución distinta destruía todas las Label3D y calculaba centroides en main. | O(L) más G creaciones/liberaciones por una frontera o renombre. Asignación de texto/tamaño incluso si sólo se movía el centro. | Worker calcula centroides sólo cuando cambia el array de pertenencia. Caché por contenido, también para snapshots del mismo año. Main conserva nodos por grupo y cambia únicamente texto, tamaño o ancla realmente distintos. O(G) de comparación y O(Δ) de cambios de nodos. | Arrays iguales aún requieren comparación PackedArray O(N) en código nativo; no es una revisión O(1). Si cambian fronteras, el cálculo O(L) sigue existiendo en worker. Verificar centros, tamaños, renombres y cambios de modo. |
| `HistoryOverlay._build_markers`. | Entrar/salir un evento de la ventana de 50 años recreaba todos los marcadores. | Diccionarios por ID de evento/guerra: altas/bajas por ID; reutilización de raíz, mesh y material. Altura sólo si cambia celda/relieve. O(E) para resolver vigencia y O(Δ) de recursos. | El recorrido de eventos sigue siendo necesario para su expiración. Verificar eventos simultáneos y frentes; fallbacks por posición de lista sólo para fixtures sin ID. |
| Firma de rutas y publicación anual de vista. | Cambios en metadatos de una ruta podían reconstruir malla. Cada año llamaba `map_view.invalidate_view`, invalidando cámara/hover y listeners ajenos al contenido. | Firma sólo de paths y volumen visual normalizado. Se colocan asentamientos/anotaciones inmediatamente dentro de `_load_frame`, sin invalidar geografía/LOD/hover cada año. Cambios de cámara, proyección, viewport, calidad y relieve sí invalidan lo necesario. | Una modificación real de paths/anchura todavía reconstruye la malla conjunta de rutas; no se multiplicaron nodos/draw calls creando una malla por ruta. |
| `Hud.show_info`: cambio de subtítulo anual vaciaba el árbol completo. | O(R) construcciones y liberaciones de controles, además del cálculo de sus datos. Pérdida de scroll durante actualizaciones. | Secciones y filas conservadas por estructura. Actualiza valores/etiquetas, recrea únicamente una fila cuyo tipo cambie y reconecta acciones actuales aunque el caption sea igual. Notas históricas pasan como datos, sin crear Labels antes de saber si hacen falta. Conserva pestaña y scroll si la estructura no cambia. | Todavía compara O(R) valores. Controles arbitrarios suministrados por callers conservan su estilo y pueden reemplazarse individualmente. Verificar enlaces, tabs, cambio de entidad y renombres. |
| `select_entity/_request_province_details/_show_engine_entity`. | Refresh del mismo año podía vaciar detalles y duplicar queries; caché de entidad sólo por año podía conservar una respuesta anterior a una intervención del mismo año. | Peticiones por selección+año+SHA. No vacía datos de la misma consulta válida; descarta callbacks de una huella/selección anterior. Los errores recuperables permiten reintentar. | Comprobar pausas, intervenciones, consultas rápidas y errores de petición. No se cambian comandos, esquema ni condiciones de aceptación de Go. |
| `MapMath.raycast/_surface_gap`. | Hasta 160 evaluaciones completas de relieve más 14 de bisección por consulta: bicúbica, pendientes y varias octavas de ruido. | Conserva marcha, clipping, orden y bisección. Usa cotas superiores conservadoras de bloques 8×8 con halo para evitar evaluar relieve en puntos ciertamente superiores. Al/bajo nivel del mar usa el signo matemáticamente conocido. Puntos ambiguos ejecutan el evaluador original. | Misma complejidad peor caso O(160+14); reduce evaluaciones costosas según terreno. Construcción fría de bloques tiene coste. No se aceleró bajando muestras, precisión ni frecuencia del hover. |
| `StrategyCamera.ground_at_screen` y `MapView._process`. | Hover, clic y rueda repetían raycasts con la misma geometría; una invalidación histórica obligaba a repetir hover. | Caché del punto/null con cursor, transform, proyección, parámetros exactos de superficie y revisión geográfica. Cambios de relieve/viewport invalidan explícitamente picking. Se recalcula inmediatamente al cambiar inputs. | Verificar costuras, polos, provincias pequeñas, zoom inverso, cámara inclinada y foco sobre mar con relieve cambiado. No existe throttle temporal. |

### Cota de picking y precisión

Los pesos negativos de Catmull-Rom suman como máximo 1/8 por eje. En dos dimensiones la masa negativa queda acotada por `2×(9/8)×(1/8) = 9/32`. Por ello `max + (9/32)×(max-min)` limita la bicúbica de los texels del bloque y su halo. Se añade un margen conservador de redondeo. La mezcla con bilineal y sus clamps no supera esa cota.

El ruido normal está acotado por [-1,1], el ridged por [-0.9,1.1], y la amplitud de relieve por `abs(relief_detail)×(0.10+1.30+0.35)`. Esto da un límite superior de altura, no una altura aproximada. Sólo permite devolver un **signo positivo seguro**; la búsqueda anterior usa signos, sin interpolar con las magnitudes del gap. Para casos ambiguos se llama al mismo `height_at`. Los parámetros de picking se comparan sin convertir sus doubles a Vector4. La resolución final y el warp de provincia siguen iguales.

### Publicación coherente

Se mantiene el pipeline existente: Go completa un año → worker recibe/decodifica y prepara índices → main recibe un HistoryFrame completo → `_load_frame` aplica escena y HUD sin `await` → poll puede solicitar el siguiente año. No se introdujo una cola de años visuales diferidos ni un calendario que avance antes de terminar la aplicación. Los índices son datos de presentación, no campos del protocolo ni entradas de SHA/replay.

Se preservaron duplicaciones de arrays provinciales que garantizan inmutabilidad. La nueva caché sólo lee arrays de publicaciones ya separadas del decoder; reemplaza diccionarios derivados y no muta los conservados por frames anteriores. No se usaron sumas incrementales que pudieran alterar el orden numérico de los totales mostrados.

## B. Archivos, funciones y commits

Cambios de Fase 2.2 bajo `client/godot/scripts/`:

- `data/frame_visual_index.gd` (nuevo): `build`, `_group_shapes`, índices inmutables y caché de pertenencia por contenido.
- `data/history_frame.gd`: sidecar opcional, `people_totals`, `state_totals`, `settlements_in_cell`, lookup de asentamiento.
- `data/native_frame_decoder.gd`: preparación del sidecar al finalizar `_publish`, sobre datos de Go ya decodificados.
- `app/main.gd`: consumo de índices, actualización anual granular, selección/query por huella, conexión Fluido, probe y gauges.
- `map/history_overlay.gd`: etiquetas/marcadores diferenciales y firma de rutas con inputs visuales.
- `ui/hud.gd`: filas/secciones reutilizables, controles actuales de acciones y Fluido explicado/activado por defecto.
- `map/map_math.gd`: cotas de picking lazy y contadores de muestras.
- `camera/strategy_camera.gd`: caché exacta de picking y su invalidación.
- `map/map_view.gd`: invalidación de picking separada del contenido y contadores de hover.
- `data/performance_trace.gd`: esquema v3, scopes anidados, métricas de worker, contadores e identificador de sesión.
- `data/profile_frame_probe.gd` (nuevo): cierre del intervalo observado del hilo principal, creado sólo si el perfil está habilitado.
- `data/bridge_source.gd`: métricas internas de recepción/parseo/decoder entregadas a main; no modifica bytes de petición, operaciones ni validación del protocolo.
- `map/instance_bands.gd`, `map/settlement_layer.gd`, `map/vegetation_layer.gd`, `map/terrain_renderer.gd`: contadores de reconstrucción/publicación y tiempo de preparación de vegetación separado de main.

Aceptación preparada: `client/godot/tests/phase22_contracts.gd` (nuevo, **no ejecutado**) y expectativa Fluido restaurada en `atlas_ux_regressions.gd`. También `AGENTS.md`, el párrafo vigente de README, LEEME y este informe. Los informes previos permanecen como registro de la primera iteración.

| Commit | Subsistema |
|---|---|
| `273b4d3` | Índices derivados e inmutables de HistoryFrame en worker. |
| `247c987` | Scopes exclusivos, recepción/decoder y sesión de telemetría. |
| `07b3b37` | Recursos publicados y preparación de vegetación. |
| `8de9ee4` | Etiquetas/marcadores por ID estable. |
| `d6d1f29` | Inspector diferencial, consumo de índices y control Fluido. |
| `3f339d7` | Cotas conservadoras y caché de picking. |
| `839f1dd` | Invalidación de relieve/viewport y claves exactas. |
| `f047dfa` | Contratos de aceptación listos para ejecución del usuario. |

El commit final de documentación/entrega contiene `[skip ci]` para evitar ejecutar suites automáticamente al actualizar PR #22. Su SHA completo se proporciona en el mensaje de entrega; también se obtiene con `git rev-parse HEAD`.

## C. Telemetría v3 e interpretación

Se conserva `ASABIYA_PROFILE_PATH`, JSONL y las métricas principales anteriores: `fps`, `frameP50Ms`, `frameP95Ms`, `frameP99Ms`, `processMs`, memoria estimada, draw calls y nodos. `traceSession` combina PID, hora y nonce aleatorio de 128 bits generado con Crypto (independiente de la simulación); se renueva al recrear escena/proceso. El archivo sigue añadiendo sesiones, sin truncar al crear mundo.

### Scopes

- `cpuScopes`: por scope, los campos existentes `totalMs/meanMs/maxMs/p50Ms/p95Ms/p99Ms` son **inclusivos**. Los nuevos `exclusiveTotalMs/exclusiveMeanMs/exclusiveMaxMs/exclusiveP50Ms/exclusiveP95Ms/exclusiveP99Ms` restan los spans hijos instrumentados mediante una pila. Todos son tiempo transcurrido, no ciclos de CPU.
- Ejemplo: `frame-apply` contiene HUD, selección y anotaciones; `selection-refresh` puede contener `inspector`. No sumar inclusivos. El exclusivo deja el trabajo sin un hijo nombrado, incluido el coste de instrumentación que quede entre spans.
- `workerScopes.receive`: lectura de TCP y append de buffers, **sin** espera de red ni cálculo Go. `json-parse`: conversión UTF-8/parseo. `decode-publication`: construcción de frame; su exclusivo resta `visual-index`. `visual-index`: índices derivados. `vegetation-compute` y `vegetation-pack`: preparación en worker, sin render. No sumar worker y main para obtener frametime: se solapan.
- `main-unclassified-observed`: gap entre el primer span instrumentado de un frame y un probe de prioridad final, menos los spans exteriores completos. Sólo cubre ese tramo observado de callbacks. **No** es `TIME_PROCESS - sum(scopes)` ni representa GPU, VSync o todo el motor. Work antes/después del tramo observado no queda medido ahí.
- `scopeStackErrors` y `abandonedScopes`, si aparecen, indican un stack incompleto/desparejado: descartar la interpretación exclusiva de esa ventana e investigar.

Muestras por scope/ventana limitadas a 3,600, con llamadas muestreadas/no muestreadas; los totales/máximos incluyen todas las llamadas. Ventanas de unos 2 s; el tramo final incompleto no genera percentiles. La cabecera declara `asabiya/client-profile-v3`. Sin variable de entorno no se abre el archivo, no se acumulan scopes ni se crea el probe.

### Contadores y contexto

- Índices: `shapesRebuilt`, `shapesReused`, `totalsCellsScanned`.
- Anotaciones: `annotationsPublications`, `labelsCreated/Updated/Reused/Removed`, `markersCreated/Reused/Removed`, `labelLayerCacheHits`, `markerLayerCacheHits`, `routeLayerCacheHits`.
- Asentamientos: `settlementsConsidered`, `settlementCacheHits`, `settlementLayoutsBuilt`, `settlementTilesDirty`.
- Publicación: `bandsPublished/Removed`, `multiMeshesPublished`, `instancesPublished`, `instanceSourceBytes`, `overlayColorUploads`, `overlayKeyUploads`, `overlaySourceBytes`.
- Inspector: `inspectorRowsCreated`, `inspectorRowsReused`. Reutilizar una fila no significa que su valor no haya cambiado: evita reconstruir el control.
- Hover: `hoverQueries`, `pickCacheHits`, `pickSamples`, `pickFullHeights`, `pickBoundsSkipped`, `pickBoundsBuilt`, `pickNonpositive`. Para casts no cacheados, las muestras dentro del mapa se reparten entre alturas completas, descartes por cota y signos al/bajo mar. Fuera del slab Z no se cuenta muestra. Los clics/rueda aprovechan la misma caché, pero estos contadores de consultas corresponden al camino de hover.
- Transporte: `responseBytes` cuenta NDJSON de respuestas completas entregadas a poll. En el modo rápido existente, las respuestas de status procesadas sólo dentro del worker no se incluyen: no interpretarlo como tráfico total de ese modo.
- `framesApplied` cuenta aplicaciones completas, no el refresh de un frame idéntico. `vegetationTasksDiscarded` identifica trabajo obsoleto. `context` conserva año, capa, reproducción, cámara/viewport/calidad/relieve y cantidades de asentamientos, etiquetas, marcadores e instancias de rutas. Es el último contexto de la ventana, que puede cruzar varios años/vistas.

Los contadores de bytes de recursos son **bytes fuente entregados a la API**, no bytes de transferencia PCIe/driver medidos. Memoria gráfica sigue siendo una estimación de RenderingServer. No hay medición de tiempo GPU.

Para combinar ventanas, una media de scope se calcula con `sum(totalMs)/sum(calls)`, separando escenario, año, carga y tiempo inclusivo/exclusivo. No promediar las medias de ventanas con pesos iguales si tienen distintas llamadas. Comparar mediana, P95/P99 y máximo por ventana; no presentar el promedio de percentiles como percentil global. Los 44.3 ms referidos a la versión anterior no pueden compararse directamente con el exclusivo nuevo.

## D. Riesgos pendientes

1. El worker tiene trabajo adicional O(L) y retiene índices pequeños por frame; puede limitar años/s en CPUs compartidas con Go o aumentar memoria de CPU. La escena reutilizada debe reducir churn de recursos, pero no se midió ese efecto.
2. Escenas densas siguen haciendo trabajo proporcional al contenido realmente cambiado. Reconstrucción de una ruta real, overlay completo y layouts nuevos no se distribuyen todavía entre varios commits visuales; permanecen atómicos en main. No se oculta esa limitación con un promedio.
3. Picking: verificar cotas en terreno extremo, márgenes/halo, costuras y polos, también caché fría. No se ejecutó la comparación con el evaluador original.
4. Inspector: comprobar tipo de fila variable, callbacks con caption igual pero ID distinto, desaparición de secciones, scroll y actualización tras intervenciones del mismo año. Controles genéricos mantienen estilos; las notas de historia usan el descriptor simple del estilo previo.
5. Los datos derivados deben permanecer inmutables. Verificar navegación al archivo y que un frame nuevo no cambie centroides/totales de frames retenidos. No se reutiliza un índice basándose sólo en año.
6. Las cifras de zoom cercano también pueden estar limitadas por shader/renderer/Iris Xe; no se alteraron resolución, sombras, MSAA, SSAO, densidad, draw distance, shaders ni reglas para buscar FPS. Se necesitan mediciones específicas para atribuirlo a GPU.
7. El perfil activo tiene coste y el archivo crece con la duración. Comparar también sin perfil y usar un archivo distinto por proceso/repetición.

## E. Revisión y aceptación

Realizado únicamente: inspección de flujo, revisión estática manual, parseo sintáctico externo `gdtoolkit 4.5.0` y `git diff --check`. El parser externo no valida tipos/API de Godot 4.7.2. No se ejecutó Godot, editor, juego, compilación/exportación, tests, benchmarks, simulaciones, capturas ni CI. Los contratos añadidos son código para que ustedes lo ejecuten, no evidencia de pruebas aprobadas.

Revisión de alcance: Go (`cmd`, `internal`, `client/exporter`), referencia HTML, golden/fixtures, shaders, project.godot, herramientas de empaquetado y workflows siguen sin cambios respecto a `2380858`. No hay cambios en operaciones/esquemas/bytes de petición ni en verificación de respuestas TCP; `_client_profile` es metadato interno posterior a la decodificación.

### Compilación Windows — ejecutar por usuario/ChatGPT

PowerShell 7, Git y Go 1.27.2 en PATH. El script existente descarga/verifica Godot 4.7.2 y templates fijados si no se aporta `-GodotPath`. Compila en una carpeta completa, sin generar ZIP:

```powershell
git fetch origin perf/godot-frame-optimization
git switch perf/godot-frame-optimization
git pull --ff-only
$revision = (git rev-parse HEAD).Trim()
pwsh -NoProfile -File .\tools\package-windows.ps1 `
  -OutputDirectory "$PWD\build\phase22" -SourceRevision $revision `
  -ValidationSummary "Fase 2.2: solo revision estatica; aceptacion Windows pendiente"
```

Revisar import/export y manifiesto antes de iniciar. Para comparación, construir `238085832ea8fdd8d43e753908699d1810e40337` en otro worktree/carpeta, sin sobrescribir ni mezclar ejecutables. Los resultados de revisión deben indicar el SHA del manifiesto.

### Contratos preparados — ejecutar sólo cuando ustedes decidan

```powershell
$godot = "$PWD\build\godot\4.7.2-stable\editor\Godot_v4.7.2-stable_win64_console.exe"
& $godot --headless --path client/godot --script res://tests/phase22_contracts.gd
```

Si se usó un editor instalado, ajustar `$godot` a ese editor. El script compara raycasts contra la implementación anterior sin cotas, revisa cotas en bloques/costuras/polos y comprueba totales, inmutabilidad, snapshots del mismo año y conservación de IDs de nodos. No inicia Go ni mide FPS. Su aprobación no reemplaza aceptación visual. Ejecutar también las regresiones existentes de atlas, publicación, reproducción y rendimiento según su circuito habitual.

### Sesión comparable de aceptación

- Mismo i5-1340P/Iris Xe, corriente/modo de energía, resolución, escalado, Forward+, calidad, relieve, mundo/semillas y carga de otras apps. Registrar GPU/driver y configuración. Realizar al menos tres repeticiones por revisión, controlando tramo histórico y vistas.
- Repetir una sesión de al menos 7 min 39 s, con zoom mundial/cercano y épocas tempranas/avanzadas. Comparar años equivalentes además de duración: Máxima puede llegar a un mundo más complejo en la misma cantidad de segundos.
- Repetir seleccionando un pueblo y su evolución, un Estado y una provincia. Vigilar `selection-refresh`, `inspector`, recursos creados/reutilizados y `workerScopes.visual-index`. Navegar entre frames retenidos y después reanudar.
- Mover cursor/cámara continuamente por costa, provincias pequeñas, bordes, relieve inclinado, polos y costura. Probar clic, zoom al cursor, inversión de rueda, resize y cambios de relieve con cámara enfocada en mar. Confirmar selección contra el mapa y ausencia de retraso perceptible.
- Validar etiquetas/centroides al crecer, dividirse o renombrarse grupos; eventos que entran/salen de 50 años; rutas reales; asentamientos, edificios, clearings, Atlas, leyendas, crónica, paneles y generación de otro mundo.
- Comprobar Fluido activado de inicio; desactivarlo/reactivarlo durante reproducción (afecta siguientes avances). Pausar entre checkpoints, comprobar SHA exacto y avanzar un año. Validar comandos/replay con sus herramientas existentes, también una intervención que cambie el mismo año mostrado.
- Verificar FPS sostenidos y P50/P95/P99, creación/retención de memoria, cierre durante cálculo/vegetación y ausencia de crecimiento anormal. No sumar scopes anidados ni atribuir a GPU el tiempo CPU.

Captura opcional:

```powershell
New-Item -ItemType Directory -Force .\captures | Out-Null
$env:ASABIYA_PROFILE_PATH = "$PWD\captures\phase22-repeticion1.jsonl"
Start-Process -FilePath "$PWD\build\phase22\AsabiyaNative.exe" -Wait
Remove-Item Env:\ASABIYA_PROFILE_PATH
```

Usar nombres distintos para revisión/repetición. Adjuntar JSONL, manifiesto, configuración, acciones y observaciones. La fase queda abierta hasta su aceptación Windows. PR #22 se actualiza como draft para revisión, sin merge y sin PR adicional.
