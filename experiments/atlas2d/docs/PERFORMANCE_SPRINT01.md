# E4 · Informe de rendimiento del Atlas 2D (Sprint 01)

## Advertencia

Todas las cifras de este documento se midieron con **llvmpipe** (Mesa, render por software):

- máquina virtual Linux de 4 vCPU;
- Xvfb 1920×1080;
- Godot 4.7.2 con el renderer Compatibility.

**No son cifras de Iris Xe ni de Windows.** Sirven solo para comparar variantes en la misma máquina, una variable cada vez. El objetivo del sprint (≥30 FPS a 1080p en el portátil i5-1340P + Iris Xe) **sigue sin verificar**. El procedimiento para medirlo está al final.

## Configuración común

- Mundo de 400×200 con detalle 4, semilla por defecto y 10000 años de preparación por avance rápido. Go produce el SHA exacto `e7df456c…` en el año 1000, igual que Go headless y que la captura de Windows del usuario.
- Zoom 4, provincia seleccionada y capa política.
- 10 s de captura por caso:
  - «Pausado» no recibe publicaciones.
  - «Activo» recorre años consecutivos a velocidad máxima.
- Herramientas:
  - `tools/summarize.py` (P50, P95 y P99 de frame, `main_ms`, `render_cpu_ms`, `render_gpu_ms`, más los ticks del hilo principal por encima de 20 ms);
  - captura por caso, sobre Xvfb `:99`:
    `godot --path build/atlas2d/project --audio-driver Dummy -- --server=<ruta>/asabiya-server --width=1920 --height=1080 --bench-out=<caso>.jsonl --seconds=10 --prepare-years=10000 --zoom=4 [--active] [--diag=map-hidden|panel-hidden] [--release-on-main] [--no-render-timing] [--rate=5]` (sin `--active` la captura es en pausa).
- Las cifras repetidas son ejecuciones independientes.

Los JSONL comprimidos y el resumen `summary.json` están en `experiments/atlas2d/evidence/sprint01/`.

## 1. Causa principal de los tirones en modo activo

### Diagnóstico

Variables aisladas: mapa oculto (`--diag=map-hidden`) y panel oculto (`--diag=panel-hidden`).

- Con el **mapa oculto**, el modo activo seguía teniendo P95 de 110 ms y P99 de 271 ms. El coste no estaba en el dibujo.
- El tiempo del hilo principal (`main_ms`) tenía un P95 de 111–150 ms.
- La fase responsable era `BridgeSource._store`. Al retener 24 frames, cada publicación expulsa el más antiguo. Su liberación (`PackedArray`s y diccionarios de entidades de un mundo de 80000 celdas) ocurría en el hilo principal.

### Corrección

`atlas_app.gd:_retire` conserva la referencia al frame expulsado y lo libera en un `WorkerThreadPool`:

- El adaptador compartido `bridge_source.gd` no se modifica.
- El hilo principal ya no paga la destrucción.
- `--release-on-main` restaura el comportamiento anterior para el A/B.

### A/B, una variable (liberación en hilo principal frente a worker), dos repeticiones

| Caso | FPS P50 | Frame P50 / P95 / P99 (ms) | `main_ms` P95 | Ticks > 20 ms | Años/s |
|---|---:|---|---:|---:|---:|
| Hilo principal, 1 | 32.3 | 31.0 / 131.4 / 253.6 | 116.4 | 15 | 1.6 |
| Hilo principal, 2 | 36.1 | 27.7 / 139.3 / 246.8 | 126.4 | 17 | 1.7 |
| Worker, 1 | 32.5 | 30.8 / 47.5 / 56.0 | 1.5 | 3 | 1.9 |
| Worker, 2 | 35.2 | 28.4 / 41.6 / 52.9 | 1.4 | 3 | 2.0 |
| Worker, ritmo 5 | 34.1 | 29.3 / 42.8 / 57.7 | 1.6 | 3 | 2.0 |

### Resultado

- P95 de frame: de 131–139 ms a 42–48 ms.
- P99: de 247–254 ms a 53–58 ms.
- `main_ms` P95: de 116–126 ms a 1.5 ms.
- La mediana de FPS apenas cambia: el coste eran picos, no la media.

## 2. Comparación con la base (PR #27, `6f234dbe`) en la misma máquina

| Caso | FPS P50 | Frame P50 / P95 / P99 (ms) | > 33,3 ms | Años en 10 s |
|---|---:|---|---:|---:|
| PR #27 activo, 1 | 37.1 | 26.9 / 147.0 / 252.4 | 15.0 % | 17 |
| PR #27 activo, 2 | 36.5 | 27.4 / 128.3 / 260.4 | 15.3 % | 18 |
| Sprint activo, 1 | 32.7 | 30.6 / 48.2 / 64.3 | 35.0 % | 21 |
| Sprint activo, 2 | 33.5 | 29.9 / 45.4 / 61.8 | 30.8 % | 21 |
| Sprint activo, sin temporizadores de render | 32.1 | 31.1 / 47.8 / 75.1 | 34.9 % | 19 |
| PR #27 pausado, 1 | 48.6 | 20.6 / 25.2 / 30.8 | 0.6 % | — |
| PR #27 pausado, 2 | 49.3 | 20.3 / 24.4 / 26.6 | 0.2 % | — |
| Sprint pausado | 44.0 | 22.7 / 27.7 / 30.0 | 0.2 % | — |
| Sprint pausado, sin temporizadores, 1 | 45.7 | 21.9 / 27.2 / 32.2 | 0.9 % | — |
| Sprint pausado, sin temporizadores, 2 | 44.4 | 22.5 / 28.3 / 31.3 | 0.2 % | — |

### Lectura honesta

- **Activo:**
  - Los picos bajan a un tercio (P95) y a un cuarto (P99).
  - Avanza algo más rápido: 19–21 años frente a 17–18 en 10 s.
  - La mediana de FPS baja unos 4 FPS, y el porcentaje de frames por encima de 33,3 ms sube del 15 % al 31–35 %.
  - Hay dos causas probables, que siguen sin separarse en un experimento: el trabajo de liberación en el worker compite por las 4 vCPU con llvmpipe, que también rasteriza en CPU; y el sprint publica más años en el mismo tiempo.
  - En una GPU real el rasterizado no ocupa esos núcleos, por lo que este efecto debe medirse en Windows antes de sacar conclusiones.
- **Pausado:** hay una **regresión de mediana de un 8 %** (48.6–49.3 → 44.0–45.7 FPS).
  - No la causan los temporizadores de render: sin ellos el resultado es el mismo.
  - Tampoco se aisló su causa. La hipótesis es el panel más ancho (470 px) y con más texto, más las pestañas y la barra de estado ampliada; en llvmpipe la superficie de UI se rasteriza por CPU.
  - Queda como pendiente.

## 3. Desglose de subsistemas en pausa (llvmpipe, una variable)

| Variante | FPS P50 | `render_gpu_ms` P50 |
|---|---:|---:|
| Completo | 43.0 | 14.2 |
| Panel oculto | 46.5 | 13.4 |
| Mapa oculto | 57.6 | 9.8 |

En pausa, el mapa (shader de terreno con la textura de capa) es el subsistema más caro, aunque no domina por completo: con el mapa oculto todavía quedan 9,8 ms de GPU. El panel cuesta poco. Con llvmpipe estas proporciones sirven solo como orientación.

## 4. Reposo: render bajo demanda

`OS.low_processor_usage_mode` está activo fuera del banco. El mapa solo se redibuja cuando la cámara se mueve o llega una publicación (bandera `_dirty`), y los símbolos siguen la señal `redrawn` en lugar de redibujarse cada frame.

| Modo | Frames dibujados/s | Iteraciones del bucle/s |
|---|---:|---:|
| Bajo demanda (por defecto) | 1.0 | 140.8 |
| Continuo (anterior) | 57.8 | 57.8 |

Con la sesión en pausa y sin interacción, la GPU deja de dibujar unos 57 frames por segundo innecesarios, lo que debería reducir el consumo y el calor en el portátil. El banco desactiva este modo para medir el coste por frame.

## 5. Trabajo redundante eliminado

- **Liberación de frames expulsados:** pasa a un worker (sección 1).
- **Redibujo continuo del mapa y los símbolos:** pasa a ser bajo demanda (sección 4).
- **Crónica:**
  - se regenera solo cuando cambia su firma (año, filtros, número de eventos) o al abrirla;
  - se limita a 300 líneas.
- **Consultas Go del panel provincial:** se guardan por provincia, año y SHA (`_attach`) y no se repiten al refrescar.
- **Pestañas:** solo se actualiza la pestaña visible.

## 6. Limitaciones

- Nada de esto se ha medido en Windows ni en Iris Xe.
- llvmpipe comparte CPU entre el render y el trabajo del cliente, lo que penaliza cualquier hilo adicional. Eso puede favorecer o perjudicar el resultado en una GPU real.
- Las capturas duran 10 s y hay dos o tres repeticiones por caso. Sirven para diferencias grandes (picos ×3), no para diferencias del 5 %.
- La regresión en pausa y la subida del porcentaje de frames lentos en activo siguen pendientes de aislar.

## 7. Procedimiento en Windows (i5-1340P + Iris Xe + 16 GB)

1. Descargar el artefacto de Windows de la ejecución CI de la PR y descomprimirlo.
2. Conectar el portátil a la corriente y elegir el perfil de energía «Máximo rendimiento». Cerrar el navegador y otras aplicaciones.
3. Ejecutar `Medir rendimiento.cmd`: cuatro capturas, 1080p y 720p, pausado y activo.
   - `Medir completo.cmd` añade tres zooms y repeticiones.
   - No tocar la ventana durante la prueba.
4. El script es recuperable:
   - Un caso que falla deja `<caso>.error.txt` y una entrada en `fallos.json`, y los demás continúan.
   - El resumen incluye `godot_private_bytes`, `godot_cpu_ms` y `go_cpu_ms`.
5. Conservar la carpeta `mediciones-*` completa y adjuntarla. El criterio es FPS P50 ≥ 30 a 1080p, con P95 y P99 de frame y `main_ms` P95 por debajo de 33,3 ms y 20 ms respectivamente.
6. Para comparar con PR #27, repetir con el paquete de esa PR en la misma sesión de energía.
