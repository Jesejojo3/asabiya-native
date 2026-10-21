# Zoom cercano: primero medir la base de PR #22

## Estado y alcance

Base exacta: `2193a9d92400e7398c73c79105e311aae6397d3b`. Rama independiente
`perf/close-zoom-30fps`; no modificar PR #22 ni main, ni fusionar ninguna PR.
La petición actual autoriza perfiles, pruebas y una PR independiente y sustituye
las restricciones históricas de Fase 2.2 sobre esas acciones.

**Todavía no hay capturas de este experimento en el equipo objetivo.** No hay
comparativa antes/después ni optimización del renderizador. Los 13 FPS comunicados
son una observación del usuario, no una distribución nueva medida. No se atribuye
el límite a GPU, CPU, sombras, LOD o sincronización sin datos.

Objetivo confirmado por capturas del responsable: HP Pavilion Plus 14-eh1xxx,
Intel Core i5-1340P, Intel Iris Xe, RAM 16 GB, Windows 11 Home Single Language x64
build 26200. Controlador observado: 31.0.101.4575, WDDM 3.1. La reserva gráfica
dedicada de 128 MB no es el límite total de la GPU integrada: comparte RAM.
El archivo de paginación mostrado tampoco prueba por sí solo presión de memoria
durante el juego. Mantener ese controlador para la primera comparación.

El entorno de desarrollo es Linux sin dispositivo GPU expuesto. Se descargan las
herramientas fijadas para verificar código y contratos; headless no mide el
renderer de la Iris Xe. El backend y los recursos protegidos permanecen iguales.

## Captura en Windows sin programar

1. Descargar el artefacto `asabiya-close-zoom-baseline-2193a9d-windows-x64` del
   workflow **Close zoom profiling kit** de esta PR. Es un kit de medición, no una
   versión optimizada ni una certificación gráfica del juego.
2. Descomprimir completamente en una carpeta nueva. El kit incluye Godot oficial
   4.7.2, servidor Go Windows x64 y fuentes exactas del cliente de #22. No requiere
   instalar Go, Godot, Python ni Node.
3. Conectar el portátil a corriente, cerrar programas pesados y ejecutar
   `PERFILAR.cmd`. Dejar la ventana visible. No tocar ratón/teclado, minimizar,
   redimensionar ni cambiar de aplicación durante una captura. La pérdida de foco
   y la entrada manual invalidan esa ejecución.
4. Esperar las 12 ejecuciones: 3 repeticiones de 1080p/720p y pausada/activa.
   Cada una calcula previamente 10000 años, calienta 20 s en pausa y captura
   60 s. La preparación puede tardar varios minutos por ejecución. El orden de
   condiciones se invierte en la segunda repetición para observar deriva térmica.
5. Entregar la carpeta `results-*` completa: manifiestos, JSONL, CSV, PNG y logs.
   El kit no envía datos por red. No sobrescribe resultados anteriores.

La ventana debe disponer de 1920x1080 píxeles reales. Si no caben en la pantalla
activa, esa condición se rechaza: no se presenta una ventana menor como 1080p.
Se usa la misma provincia inicial más poblada (desempate por CellID), mundo
Asabiya/1 de 400x200, detalle 4, cámara a distancia 18, calidad Media y relieve
normal, inspector seleccionado y capa terreno. Todos los inicios deben tener el
mismo SHA causal. Los ajustes personales no se guardan ni sustituyen.

La simulación activa usa Máxima y Fluido como la base; no oculta años. El
calentamiento es pausado en ambos casos, de modo que el estado inicial coincide.
En la ventana activa se registran los años publicados y el ritmo alcanzado;
una ejecución más rápida puede terminar en otro año. Conservar esa diferencia
al interpretar comparaciones de duración fija; repetir con un ritmo acotado si
el crecimiento de la carga impide una comparación justa.

Variantes explícitas (PowerShell de Windows incluido; desde la carpeta del kit):

```powershell
# Diagnóstico: cada variante a 1080p en pausa, además de la matriz normal.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tools/profile-close-zoom.ps1 -Diagnostics
# Una preparación corta para comprobar el circuito; NO sustituye historia madura.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tools/profile-close-zoom.ps1 -HistoryYears 0 -Seconds 10 -Repeats 1
# Control de coste de instrumentación: repetir la campaña sin timestamps GPU.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tools/profile-close-zoom.ps1 -NoGpuTiming
# Ámbitos CPU de #22 para descomponer el hilo principal y el decoder.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tools/profile-close-zoom.ps1 -CpuScopes
```

Las variantes `shadows-off`, `ssao-off`, `terrain-hidden`, `vegetation-hidden` y
`lod-coarse` sólo aíslan subsistemas; **no son optimizaciones aceptadas**. Se
ejecutan en procesos separados y no cambian ajustes del producto.

## Qué mide y qué no

`frames.jsonl` guarda todos los intervalos entre `frame_post_draw`, tiempos de
proceso y renderer CPU/GPU, draw calls y primitivas visibles/de sombras, memoria
estática de Godot y estimación de memoria gráfica. La escritura del archivo se
hace después de capturar; las capturas PNG y consultas replay quedan fuera.
Los temporizadores GPU son asíncronos, pueden tener desfase y ser cero si no hay
soporte. Cero significa no disponible, no GPU gratuita. No se llama a sync ni se
restan CPU y GPU para inventar un coste de espera: se solapan.

Los intervalos son del bucle gráfico, **no latencia de presentación al panel**.
El kit usa el editor oficial ejecutando scripts de las fuentes, no el ejecutable
exportado. Sirve para aislar costes y comparar fuentes; cualquier optimización
posterior requiere además validación del paquete exportado en este equipo.
VSync y el límite FPS se desactivan sólo en el proceso de captura para medir
capacidad; no se cambia la configuración de producción. En caso de sospechar
sincronización, contrastar con profiler de Godot/PresentMon y una reproducción
con VSync del paquete real. Un gap CPU sin explicar no demuestra espera GPU.

`processes.csv` muestrea cada segundo CPU en equivalentes de núcleos, working set
y memoria privada de Godot y Go. Los buffers de captura forman parte de la memoria
observada: se registran memoria inicial/final, filas y tamaño nominal de sus
escalares, sin restar una estimación ficticia del overhead Array/Variant.
Analizar sólo el intervalo registrado en el
manifiesto; los máximos no son memoria física VRAM y los picos subsegundo pueden
escapar al muestreo. `machine.json` identifica hardware, controlador y plan de
energía. No registra nombre de equipo ni usuario.

Los renglones crudos permiten calcular FPS P50, media, tiempos de frame P95/P99,
máximo, porcentaje sobre 33,33 ms y mínimo de frames en segundos completos.
No promediar percentiles de ventanas. La herramienta offline del repositorio:

```sh
node --test tools/test-close-zoom.mjs
node tools/summarize-close-zoom.mjs RUTA_RESULTS
# Futuro: sólo acepta pares con misma cámara, estado, GPU, API e instrumentación.
node tools/summarize-close-zoom.mjs RUTA_ANTES RUTA_DESPUES
```

El analizador rechaza muestras incompletas/no finitas, cambios de estado en
pausa, saltos de años, ausencia de avance activo y comparaciones de escenarios
distintos. Conserva cada repetición por separado; no combina colas para ocultar
deriva. `analysis.json` se crea nuevo y nunca sobrescribe otro análisis.

## Decidir a partir de resultados

| Hipótesis | Evidencia exigible |
|---|---|
| GPU / fragmentos | Tiempo GPU dominante y respuesta a resolución, controlando que LOD y draw calls no expliquen esa diferencia. 720p tiene 44,4 % de los píxeles de 1080p. |
| Sombras / SSAO | Diferencia repetida del tiempo GPU y frame al aislar cada efecto; registrar llamadas/primitivas de sombras. |
| Terreno / LOD | Comparar diagnóstico de terreno y LOD con GPU/CPU, primitivas y llamadas. `terrainAssignedTriangles` incluye chunks asignados, no sólo triángulos realmente visibles. |
| Draw calls / envío CPU | Tiempo CPU de render y número de llamadas, corroborados por profiler. Muchos triángulos por sí solos no prueban este límite. |
| Simulación / publicación | Pausado frente a activo; CPU separada Go/Godot, scopes e índices/decodificación, años/s y picos coincidentes con publicaciones. |
| Sincronización | Descartar caps/VSync, revisar colas/esperas en profiler y presentación externa. No atribuir el residuo de frame a sincronización automáticamente. |

La resolución también influye en LOD por error proyectado y cobertura de UI.
Por tanto, 1080p/720p por sí solos no separan fill rate y geometría.

Antes de optimizar: conservar campaña base, elegir un coste dominante medido,
realizar un solo cambio y repetir condiciones/orden, incluyendo control de
instrumentación. Comparar cada repetición y revisar PNG/recorrido interactivo
en costas, polos, costura, zoom/relieve, etiquetas y asentamientos. Conservar
Go, RNG, protocolos, replay, SHA, calendario y golden.

Puerta operativa propuesta para **30 FPS sostenidos a 1080p**: en las tres
repeticiones pausadas y activas, sin variantes diagnósticas, P99 <=33,33 ms y ningún segundo
completo por debajo de 30 frames, además de aceptación visual. Informar también
P50, P95, máximo, memoria y frames fuera de presupuesto. No aceptar sólo una
mediana de 30, un resultado a 720p o un test headless. Validar finalmente la
entrega exportada con su configuración normal de sincronización.

## Tabla de resultados: pendiente de hardware

| Condición | FPS P50 | Frame P95/P99 | Memoria | Cuello de botella |
|---|---|---|---|---|
| 1080p pausada | pendiente | pendiente | pendiente | sin determinar |
| 1080p activa | pendiente | pendiente | pendiente | sin determinar |
| 720p pausada | pendiente | pendiente | pendiente | sin determinar |
| 720p activa | pendiente | pendiente | pendiente | sin determinar |

No hay porcentaje de mejora ni promesa de 30 FPS hasta recibir capturas reales.
El atlas Earth real, edificios detallados y ruinas persistentes quedan fuera.

## Verificación del circuito de captura

- Godot oficial Linux 4.7.2, archivo de descarga comprobado contra el pin: parseo
  del nuevo script tanto en este proyecto como contra un checkout separado e
  intacto de `2193a9d`. No se rebaja la versión del proyecto.
- `node --test tools/test-close-zoom.mjs`: seis pruebas del analizador, incluidas
  colas, datos truncados, publicaciones y CSV de Windows.
- Contratos existentes `phase22_contracts.gd`: 2400 comprobaciones, cero fallos,
  con el Godot fijado. Son pruebas headless, no medidas gráficas.
- Parser PowerShell y rechazo explícito de ejecución de captura en Linux;
  rechazo explícito de Godot headless como fuente de resultados.
- Servidor Windows compilado con Go 1.27.2, amd64/v1 y CGO desactivado; kit
  ensamblado localmente con editor Windows cuyo archivo coincide con el pin.
- Smoke gráfico del circuito, pausado y activo, contra el checkout original:
  Xvfb/llvmpipe/Compatibility, sin terreno y sin historia madura, únicamente
  para comprobar archivos, capturas, mismo SHA inicial, publicaciones consecutivas,
  pausa exacta y cierre. Su salida se rechaza como benchmark objetivo; no se
  utilizan sus FPS ni se extrapolan a Iris Xe/Forward+.
- Diff de Go, protocolos, shaders, escena de producto, referencia y golden frente
  a la base: vacío. La única modificación a instrucciones registra esta misión.

El lanzamiento completo del runner PowerShell y la campaña Forward+ siguen
pendientes del Windows/Iris Xe. No presentar estas verificaciones como una
comparativa de FPS del equipo objetivo.
