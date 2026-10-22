# Fase 2.3 — Diagnóstico del render 3D, Forward+ frente a Mobile y optimizaciones

Rama `claude/bold-carson-smo9r9`, apilada sobre PR #24 (`perf/close-zoom-30fps`,
`431a7dd633bc1b02bf42fa68fd233ff8b0896a6b`), que a su vez se apoya en PR #22
(`perf/godot-frame-optimization`, `2193a9d92400e7398c73c79105e311aae6397d3b`). Ambos HEAD se
comprobaron el 22-10-2026 y coinciden con los SHA de referencia. No se modifica main, #22 ni #24;
no se fusiona nada. Go, protocolo TCP, RNG, calendario, replay, SHA, golden y HTML v0.6 quedan
intactos (CI lo comprueba con `git diff --exit-code 2193a9d -- internal cmd go.mod go.sum reference tests/native client/exporter`).
Forward+ sigue siendo el renderizador por defecto.

## Cómo leer las cifras

Cada número lleva su origen:

| Etiqueta | Significado |
|---|---|
| **[Iris Xe]** | Medido en el equipo objetivo (HP Pavilion Plus 14, i5-1340P, Iris Xe 31.0.101.4575, Windows 11). Única fuente válida para FPS. |
| **[lavapipe]** | Vulkan por software (llvmpipe 20.1.2, 4 núcleos x86) en el contenedor cloud, Xvfb. **Otro hardware.** Sirve para comprobar que todo funciona, para comparar imágenes píxel a píxel y como orientación de costes relativos. Sus milisegundos (≈1,2 s por frame) no se extrapolan a la Iris Xe. |
| **[estático]** | Recuento de operaciones por lectura del código del shader. |
| **pendiente** | Requiere ejecutar el kit en el equipo objetivo. |

Ningún resultado de este documento afirma 30, 45 ni 60 FPS en la Iris Xe.

## 1. Base de partida [Iris Xe]

Captura válida del kit de #24 (`results-20261021-180421-826`, 1080p, simulación pausada, 60 s,
Forward+, Vulkan 1.3.250, VSync desactivado sólo para medir):

| Indicador | Valor |
|---|---|
| Frames | 991 |
| FPS P50 | 16,54 |
| Frame P50 / P95 / P99 | 60,47 / 63,60 / 66,03 ms |
| GPU P50 / P95 / P99 | 59,91 / 62,96 / 65,22 ms |
| Render CPU P50 | 1,56 ms |
| Draw calls visibles / sombras | 24 / 28 |
| Primitivas visibles / sombras | 746 557 / 1 001 232 |
| Frames > 33,33 ms | 100 % |
| Mínimo de frames en un segundo completo | 15 |
| Memoria estática de Godot | ≈ 3,0 GB (contador `MEMORY_STATIC`, no VRAM) |

El intervalo entre frames coincide casi exactamente con el tiempo GPU y la CPU de render es
1,6 ms: el cliente está limitado por GPU en esta vista. Año 1000, SHA
`e7df456c262d6bf4f01918de79a8ff1b3eb8f736f347c7d5c3cf12e44d1c27e9` sin cambios durante la captura.

## 2. Sistema de perfilado: problemas encontrados y corregidos

### Problema A — `processes.csv` medía el proceso equivocado

Evidencia en los resultados entregados:

* Ejecución fallida: 434 muestras, todas del PID 21464 `Godot_v4.7.2-stable_win64_console`,
  working set máximo 6 MB y CPU ≈ 0. El servidor Go no aparece.
* Ejecución válida: 691 muestras de `…_console` (6 MB, CPU ≈ 0) y 61 de `asabiya-server`
  (sólo desde que existía `ready.json`). El proceso gráfico de Godot (`clientPid` 15708 en
  `run.json`) **no tiene ninguna muestra**.

Causa: `Godot_v4.7.2-stable_win64_console.exe` es un lanzador que crea el proceso gráfico
`Godot_v4.7.2-stable_win64.exe` y se limita a reenviar su consola. El runner muestreaba el PID de
`Start-Process`, es decir, el lanzador. Además, la limpieza final buscaba al servidor Go como hijo
del lanzador, cuando su padre es el proceso gráfico.

Corrección (`tools/diagnose-render.ps1`):

* Árbol de procesos por parentesco (`Win32_Process.ParentProcessId`): lanzador → `godot-graphical`
  → `go-server`, contrastado con `clientPid`/`serverPid` que el propio arnés escribe; cualquier
  discrepancia se anota en `process-notes.txt`.
* Cada muestra lleva `role` y `phase` (preparación, calentamiento, `measure:<experimento>`…), para
  separar la preparación de las capturas.
* CPU en núcleos equivalentes, working set y memoria privada por rol, cada segundo.
* Contadores WDDM por proceso (`Win32_PerfFormattedData_GPUPerformanceCounters_*`, nombres no
  traducidos): uso del motor 3D y memoria GPU dedicada/compartida **que el driver atribuye al
  proceso**. Se registran con ese nombre; no se presentan como VRAM ni se deducen del working set.
  Si no están disponibles, se anota y se dejan vacíos.
* La limpieza sólo detiene procesos de la propia sesión identificados por parentesco.

### Problema B — timeout durante la preparación

Evidencia: la ejecución válida tardó ≈ 10,6 min desde el lanzamiento hasta el inicio de la
medición (00:04:34 → 00:15:13 UTC); la fallida agotó los 1200 s de espera del avance de 10 000
años (`Timeout waiting for an exact complete state`) y además registró un error de audio WASAPI
(dispositivo de salida invalidado).

Causa raíz: el arnés de #24 llamaba a `BridgeSource.advance(10000)`, que encadena cada año desde
`poll()`, es decir, **un año por frame renderizado**. Con frames de ≈ 60 ms (GPU), 10 000 años
cuestan ≥ 10 min, y cualquier ralentización (otra pantalla, térmica, el dispositivo de audio) los
lleva por encima del límite. No es un fallo de Go ni de IPC: el mismo cálculo sin cliente tarda
**55 s** [lavapipe-host, Go 1.27.2 linux/amd64, `asabiya-headless --years 10000`] y produce el
mismo SHA `e7df456c…` que la captura de Windows.

Corrección (`client/godot/diagnostics/render_diagnosis.gd`):

* Preparación con `BridgeSource.start_fast_forward(10000, 100)`, el avance rápido que ya existe
  en el cliente: mismas peticiones `advance` de un año (`publication: status`), encadenadas por el
  hilo de red sin esperar al hilo gráfico. No cambia la simulación ni el protocolo.
* Latido cada segundo en `prepare-progress.jsonl` (año calculado, año visual, restantes, servidor
  vivo, último error, frames, memoria) y fallos con causa concreta: error del puente, servidor
  terminado, «sin progreso anual durante N s (año X)», o límite total superado.
* Verificación obligatoria del estado: `get_replay` antes de medir debe dar el SHA esperado
  (`--expected-sha`; el kit lo exige para 10 000 años). Sesiones pausadas deben terminar con el
  mismo SHA. CI recalcula el SHA de 10 000 años con el binario Windows antes de empaquetar.
* Audio con `--audio-driver Dummy` en las capturas (elimina la variable WASAPI).

Resultado [lavapipe]: preparación completa de 10 000 años en 143 s con frames de ≈ 1,3 s (el
avance ya no depende del FPS). En la Iris Xe se espera del orden de 1–3 min; **pendiente**.

### Reutilizar una historia preparada

Se evaluó guardar el estado de 10 000 años en disco. El servidor no tiene una orden para cargar
un estado (sólo `--replay-in` en la herramienta headless); añadirla cambiaría el contrato TCP, que
esta fase no puede tocar. Con la preparación desacoplada del FPS el coste es ≈ 1 min por sesión, y
además **una sesión prepara una vez y mide muchos experimentos** en el mismo proceso, con capturas
de referencia intercaladas para detectar deriva. Cada sesión prueba que parte del mismo estado
(SHA esperado), así que no hace falta una caché.

## 3. Diagnóstico de GPU

### 3.1 Método

`render_diagnosis.gd` aplica y revierte en caliente una variable por experimento, con capturas
`base` intercaladas cada 3–4 variantes. El analizador (`tools/analyze-render-diagnosis.mjs`)
compara cada variante con la media de las dos `base` que la rodean y declara «dentro del ruido»
cualquier diferencia menor que la deriva entre esas dos bases (mínimo 3 %). Cada variante guarda
captura PNG para medir también el cambio visual.

Misma escena que la captura de #24, comprobada: 24/28 draw calls y 746 557 / 1 001 232
primitivas idénticas en lavapipe y en la Iris Xe.

### 3.2 Resultados [lavapipe] — orientativos, no Iris Xe

Forward+ con el shader de #22, 1080p, pausa, mediana de GPU. Base ≈ 1 345 ms (deriva entre bases
≤ 4 %). Cambio visual medido en el área 3D frente a la base (píxeles con cualquier cambio / con
cambio > 8 niveles, y percentil 99 del cambio).

| Experimento | Δ GPU | Cambio visual | Lectura |
|---|---|---|---|
| terreno oculto | −76 % | total | el terreno es el coste dominante |
| fragmento del terreno mínimo (mismo vértice) | −47 % | total | el **shader de fragmentos del terreno** es el mayor subsistema |
| ruido eliminado del fragmento (normales, moteado, nieve) | −32 % | 71 % / 0 %, p99 4 | casi todo ese coste es el ruido de las normales por píxel |
| normales con elevación filtrada por hardware sin ruido | −33 % | 66 % / 0 %, p99 3 | ídem |
| capa de provincias/fronteras desactivada | −7 % | 11 % / 9 % | coste moderado |
| vértice del terreno mínimo | −11 % | 27 % / 3 % | el vértice se ejecuta en prepass, color y 4 cascadas |
| SSAO desactivado | −24 % | 20 % / 0,03 %, p99 2, máx 40 | incluye el buffer de normales del prepass (repite el ruido) |
| SSAO a resolución completa | +8 % | — | ya se usa media resolución |
| MSAA 2x → sin AA | −21 % | 7 % / 2,5 % (bordes) | |
| MSAA 2x → FXAA | −24 % | 11 % / 3 % | |
| MSAA 2x → SMAA | −21 % | 14 % / bordes | |
| sombras desactivadas | −21 % | 3 % / 2 %, p99 58 | |
| el terreno no proyecta sombra | −12 % | 0,03 % en esta vista | en relieve abrupto sí se vería |
| 2 cascadas / 1 cascada | −7 % / −9 % | 5 % / 2 % | |
| distancia de sombra ½ | −6 % | 2 % | |
| atlas 4096 / 2048 | −6 % / −4 % | 12 % / 65 % (bordes más blandos) | |
| filtro duro | −3 % | 2 % | |
| sin mezcla de cascadas | −1 % | 2 % | |
| agua oculta | −10 % | **0 %** en esta vista | el plano de mar se sombrea bajo tierra |
| vegetación oculta | −10 % | 17 % / 7 % | 491 607 de las 746 557 primitivas visibles |
| asentamientos ocultos | −5 % | 7 % / 5 % | |
| UI, etiquetas, niebla, tonemapping | ≤ ±2 % | — | despreciables |
| LOD más grueso / más fino | 0 % | 0 % | los chunks visibles ya están en LOD0 a esta distancia |
| escala 3D 0,75 / 0,5 | −26 % / −50 % | difuminado | coste proporcional a píxeles |
| 1280×720 / con LOD igualado | −34 % / −35 % | — | |

Con la escala 0,5 (25 % de píxeles, geometría igual) el tiempo cae a la mitad: en lavapipe ≈ 65 %
del coste es proporcional a píxeles.

### 3.3 Análisis estático del fragmento del terreno [estático]

Por píxel de tierra, en el shader de #22: 9 interpolaciones bilineares manuales de elevación
(36 `texelFetch`), **43 evaluaciones de ruido de valor** — 30 de ellas sólo para la normal (5 alturas
× 6 octavas de relieve y crestas) — que suman 172 hashes enteros (516 multiplicaciones de 32 bits)
y **≈ 96 módulos enteros** (`%` con divisor variable: en GPU se emulan con varias instrucciones).
Con SSAO activo, el prepass de Forward+ ejecuta otra vez el cálculo de la normal para el buffer
de normales/rugosidad.

### 3.4 Conclusión del diagnóstico

* **Cuello de botella identificado [lavapipe + estático]:** el shader de fragmentos del terreno,
  y dentro de él el ruido procedural que reconstruye la normal por píxel, ejecutado dos veces con
  SSAO. Le siguen, a distancia, SSAO, MSAA 2x y sombras (≈ 20–25 % cada uno en lavapipe), el plano
  de mar sombreado bajo la tierra, el vértice del terreno y la vegetación (≈ 10 % cada uno).
* **Descartado [lavapipe]:** LOD y número de chunks en esta vista, UI, etiquetas, niebla,
  tonemapping y draw calls (24 visibles) como límite; la CPU de render (1,6 ms [Iris Xe]).
* **Pendiente [Iris Xe]:** el reparto real en la GPU objetivo. La sesión `diag-forward-base` del
  kit repite exactamente esta tabla en la Iris Xe; las proporciones de lavapipe (CPU) pueden
  diferir de las de una GPU (enteros, filtrado de texturas, MSAA, early-z).
* **Limitaciones:** lavapipe no tiene early-z jerárquico ni la misma relación ALU/texturas;
  algunas cifras de sombras/MSAA/agua pueden cambiar de orden en la Iris Xe. Los temporizadores
  GPU de Godot son asíncronos y se usan por medianas.
* Una variante probada y retirada: desactivar el depth prepass en caliente
  (`rendering/driver/depth_prepass/enable`) deja Forward+ sin terreno (sólo niebla). No es una
  medida válida y no se incluye.

## 4. Optimizaciones implementadas

### 4.1 Ruido compartido en las normales del terreno (exacto)

* **Problema:** 30 evaluaciones de ruido por píxel para cinco alturas a 0,25 unidades; 120 hashes
  y 60 módulos enteros sólo para la normal, repetidos en el prepass.
* **Solución:** `vnoise_cross()` evalúa cada octava en el centro y en los cuatro vecinos
  compartiendo los hashes de la red (8 en lugar de 20 por octava; como la distancia es menor que
  media celda, a lo sumo un vecino por eje sale de la celda). Cada valor usa las mismas
  coordenadas, hashes e interpolación que `vnoise()`. Además, `posmod_i` usa cociente en coma
  flotante con corrección (mismo entero, sin división entera), las octavas de crestas se omiten
  cuando su peso es exactamente 0 (`mix(a, b, 0.0) == a`), el ruido de la nieve se omite donde la
  nieve es exactamente 0 (bajo 3300 m o sobre 2 °C, demostrable porque |ruido| ≤ 1 y |cavidad| ≤ 1),
  y `land_cell` lee una vez la textura de remapeo.
* **Archivos:** `client/godot/shaders/map_common.gdshaderinc`, `client/godot/shaders/terrain.gdshader`.
  `map_math.gd` (picking) no cambia: la función matemática es la misma.
* **Recuento [estático]:** hashes por píxel de tierra 172 → 64 (terreno suave) u 88 (abrupto);
  divisiones enteras ≈ 96 → 0.
* **Evidencia de equivalencia:** `tests/render_optimization_contracts.gd` (174 237 comprobaciones,
  0 fallos: la lógica de red de `vnoise_cross` reproduce `vnoise` en 5 puntos, incluidos bordes de
  celda, costura longitudinal y cruces exactos; `posmod` en ±60 000 y bordes). En imagen
  [lavapipe]: **0 píxeles distintos de 2 073 600** frente a la copia literal del shader de #22, en la
  vista de medida y en las vistas de costa, relieve extremo, polos y zoom mundial; la vista de la
  costura se descarta si sus dos capturas de control no coinciden (ver `equivalence.json`).
* **Evidencia de rendimiento [lavapipe]:** −10 % a −15 % de GPU frente al shader de #22 en el mismo
  proceso (dos sesiones, 3 pares A/B intercalados en cada una). **Pendiente [Iris Xe]**; allí las divisiones enteras pesan
  previsiblemente más que en una CPU, pero no se afirma.
* **Riesgos:** diferencias de último bit si un driver contrae de forma distinta las mismas
  operaciones; por eso el kit repite la comparación de píxeles en la Iris Xe.

### 4.2 Mar sólo donde puede verse (visualmente equivalente, no bit a bit)

* **Problema:** el mar era un plano de 1600×800 por copia longitudinal; el shader del agua
  descarta los píxeles con elevación > 0, pero se ejecuta antes en toda la pantalla aunque la vista
  sea de interior. [lavapipe]: −10 % al ocultarlo con 0 píxeles de cambio en la vista de medida;
  cambiar sólo el orden de dibujo no lo evitó.
* **Solución:** `_sea_mesh()` crea teselas de 16×16 muestras y omite las que el shader descartaría
  por completo (todas las muestras de la tesela y de sus vecinas > 0 m). Mismo plano y altura.
  Para el mundo Asabiya quedan 4413 de 5000 teselas por copia.
* **Archivos:** `client/godot/scripts/map/terrain_renderer.gd`.
* **Evidencia visual [lavapipe]:** vista de medida, polo norte y relieve: 0 píxeles distintos.
  Costa, polo sur y zoom mundial: diferencias de 1 nivel de 255 por redondeo de la interpolación
  (otros triángulos) y 3–13 píxeles de la línea de costa que cambian de lado. Ver `equivalence.json`.
* **Evidencia de rendimiento [lavapipe]:** ≈ −10 % en esta vista (3 pares A/B). **Pendiente [Iris Xe]**:
  con early-z de hardware el ahorro puede ser menor.
* **Riesgo:** ≈ 0,4 s más al construir el mundo (bucle sobre 1,28 M muestras; se registra en la
  traza `terrain-sea-tiles`).

### 4.3 Ambas juntas [lavapipe]

Mismo proceso, tres repeticiones intercaladas: candidato ≈ 1 070 ms frente a ≈ 1 320 ms con el
render de #22 (shader + plano de mar): **−19 %** en lavapipe. En la Iris Xe, **pendiente**: si la
proporción se mantuviera, 60 ms pasarían a ≈ 49 ms, todavía por encima de 33,3 ms. No se afirma.

### 4.4 Lo que no se ha cambiado y por qué

SSAO, MSAA, resolución del atlas, cascadas, distancia y filtro de sombras, sombra del terreno,
vegetación y escala 3D cambian la imagen. El kit cuantifica su coste en la Iris Xe y su cambio
visual; la decisión de un perfil «medio» distinto corresponde al responsable del producto.

## 5. Forward+ frente a Mobile

Sesión de diagnóstico con el mismo arnés, `--rendering-method mobile`, sin cambiar el proyecto.

| Aspecto | Forward+ (referencia) | Mobile |
|---|---|---|
| Compilación de shaders del terreno/agua/modelos | sí | sí, sin errores [lavapipe] |
| SSAO | sí | **no soportado** (aviso del motor); no hay SSIL ni SDFGI |
| Depth prepass | sí (ejecuta el fragmento del terreno 2 veces con SSAO) | no |
| MSAA 2x, sombras direccionales 4 cascadas, niebla, tonemapping | sí | sí |
| Terreno, costas, provincias, ríos, selección | correcto | correcto en la vista de medida [lavapipe] |
| Diferencia de imagen frente a Forward+ [lavapipe] | — | 64 % de píxeles cambian, 8,5 % en más de 8 niveles; árboles y tejados notablemente más oscuros, sombras más duras, sin oclusión ambiental |
| GPU base [lavapipe], mismo shader candidato | ≈ 1 155 ms | ≈ 815 ms (**−29 %**) |
| Sin sombras | −21 % | −39 % |
| Sin MSAA | −22 % | −19 % |
| Vértice del terreno mínimo | −12 % | −25 % |
| Fragmento del terreno mínimo | −37 % | −44 % |
| Rendimiento, memoria y estabilidad [Iris Xe] | pendiente | pendiente |

Lectura: en lavapipe la mayor parte de la ventaja de Mobile procede de no tener prepass ni SSAO;
la imagen no es equivalente sin adaptar materiales (vegetación/edificios) y sin una alternativa a
SSAO. **Coste de adaptación estimado:** revisar materiales `StandardMaterial3D` de modelos y luz
ambiental para Mobile, aceptar la pérdida de SSAO, y repetir la validación visual completa. Un
FPS mayor en Mobile no equivale a la misma calidad. Forward+ se mantiene; la sesión
`diag-mobile-base` del kit cuantifica ambos en la Iris Xe (comparación con la máxima equivalencia:
mismos ajustes salvo SSAO, que Mobile no tiene).

## 6. Kit Windows (Fase 2.3)

Artefacto de CI `asabiya-render-diagnosis-kit-windows-x64` (workflow *Render diagnosis kit*).
Contiene Godot oficial 4.7.2 (hash fijado), las fuentes de #22 (`source-base`) y de esta rama
(`source-candidate`), el **ejecutable exportado** candidato (`exported/AsabiyaNative.exe`, preset de
producto sin cambios, con el arnés incluido y activable sólo con `-- --render-diagnosis`), el
servidor Go Windows y el runner. No hay que instalar nada.

* `PERFILAR-COMPLETO.cmd` (≈ 75–100 min): diagnóstico Forward+ de #22; diagnóstico Mobile;
  A/B base↔candidato en orden ABBA-AB (pausado 60 s + activo 60 s, cada sesión con su propia
  historia de 10 000 años y SHA verificado); A/B en proceso con comparación de píxeles en 7 vistas;
  ejecutable exportado ×3 (capacidad, VSync desactivado) y ×1 con su sincronización de producto;
  diagnóstico Forward+ del candidato (qué queda por optimizar).
* `PERFILAR-RAPIDO.cmd` (≈ 30 min): diagnóstico base, un A/B y el exportado.
* `JUGAR-OPTIMIZADO.cmd`: abre el exportado para revisar la imagen a mano.
* Resultados: `results-*/` con `machine.json`, `campaign.json`, `summary.csv` y una carpeta por
  sesión (`run.json`, `experiments.json`, `frames-*.jsonl`, PNG por variante, `processes.csv`,
  `prepare-progress.jsonl`, `equivalence.json`, logs). Una sesión fallida queda en
  `session-error.txt` y la campaña continúa. Nunca sobrescribe resultados.
* Análisis: `node tools/analyze-render-diagnosis.mjs results-…` (en el repositorio).

## 7. Informe de aceptación

| Indicador (1080p, Forward+, calidad media) | Base #22 [Iris Xe] | Candidato [Iris Xe] |
|---|---|---|
| FPS P50 (pausa / activa) | 16,54 / no medida | pendiente |
| Frame P50 / P95 / P99 | 60,47 / 63,60 / 66,03 ms | pendiente |
| GPU P50 / P95 / P99 | 59,91 / 62,96 / 65,22 ms | pendiente |
| Render CPU P50 | 1,56 ms | pendiente |
| Draw calls / primitivas (visibles, sombras) | 24 / 746 557; 28 / 1 001 232 | pendiente (≈ +17 k primitivas visibles por las teselas de mar [lavapipe]) |
| RAM del proceso gráfico | no medida (problema A) | pendiente |
| Estabilidad (3 repeticiones, segundos < 30 frames) | 15 frames mín. | pendiente |
| Calidad visual | referencia | terreno idéntico en píxeles [lavapipe]; mar equivalente; Iris Xe pendiente |
| Ejecutable exportado | no medido | pendiente |

Puerta estricta: en las tres repeticiones pausadas y activas, P99 ≤ 33,33 ms y ningún segundo
completo con menos de 30 frames, más aceptación visual. **No alcanzada ni declarada.** Con los
datos actuales es improbable que estas dos optimizaciones exactas basten por sí solas.

## 8. Pruebas ejecutadas

* `node --test tools/test-render-diagnosis.mjs` (6) y `tools/test-close-zoom.mjs`.
* Godot 4.7.2 headless: `run_tests` (252), `atlas_ux_regressions` (145), `phase22_contracts`
  (2400), `performance_regressions` (23), `deep_publication_regressions` (146),
  `fluid_playback_regressions` (135), `annual_throughput_regressions` (148),
  `bridge_stability_regressions` (203), `render_optimization_contracts` (174 237): 0 fallos.
* Gráficas [lavapipe, Xvfb]: diagnóstico completo de 45 experimentos con historia de 10 000 años
  y SHA verificado al inicio y al final; A/B en proceso; equivalencia de píxeles; Mobile; captura
  activa (publicaciones anuales consecutivas 1001–1014, pausa y prueba final).
* PowerShell 7 (Linux): análisis sintáctico del runner.
* Configurado en CI Windows (resultado en la PR): export del candidato, autocomprobación del arnés
  dentro del `.exe`, SHA de 10 000 años con Go Windows y ejecución del runner completo sobre el
  adaptador virtual (D3D12/WARP, sólo funcional).
* No ejecutado: ninguna medida en la Iris Xe tras estos cambios; PresentMon; sesiones largas.

## 9. Siguientes experimentos propuestos

1. Ejecutar `PERFILAR-COMPLETO.cmd` y fijar el reparto real del tiempo GPU en la Iris Xe.
2. Si el vértice del terreno pesa en la Iris Xe (variante `terrain-vertex-min`): cachear las
   alturas de todos los vértices (todas las LOD están sobre la rejilla de 0,5 unidades) en una
   textura horneada una vez en GPU; quita el ruido del vértice de prepass, color y 4 cascadas.
3. Con los costes de SSAO, MSAA, sombras y vegetación medidos en la Iris Xe, proponer un perfil
   «medio» con sus diferencias visuales explícitas, para decisión del responsable.
4. Mobile sólo si la Iris Xe confirma una ventaja grande y se acepta adaptar materiales y perder SSAO.
5. Si tras lo anterior Godot no alcanza la puerta, documentar la evidencia para comparar con
   Unity URP (no en esta fase).
