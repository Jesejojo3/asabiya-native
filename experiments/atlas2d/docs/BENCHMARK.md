# Remedición Windows — arnés v2

Descarga el artefacto **asabiya-atlas2d-measurement-windows-x64** de Actions de la
PR del arnés, extrae **todo** a una carpeta local con permiso de escritura. No
mezcles EXE/PCK/scripts de otros paquetes: se validan todos los hashes del
`build-manifest.json`. PresentMon 2.3.0 x64 está incluido y fijado por SHA256;
no requiere instalación. Consulta el diagnóstico original en
`docs/WINDOWS_MEASUREMENT_DIAGNOSIS.md`.

## Ejecución para el propietario

1. Conecta el portátil a corriente, usa el mismo plan de energía, monitor,
   resolución de escritorio, escala DPI y refresco en todas las repeticiones.
   Anota cambios, temperatura ambiente y otras cargas. Evita escritorio remoto,
   overlays y ventanas que tapen el Atlas durante la captura.
2. Cierra otras instancias del Atlas. Abre **Medir rendimiento.cmd**. Si ETW
   requiere permisos, abre una consola **como administrador** y ejecuta el
   mismo CMD. No hay elevación automática. Un error de PresentMon conserva logs
   y detiene la suite; no se fabrica un resultado de FPS. Un preflight ETW de
   1 s comprueba permisos antes de preparar la historia.
3. Deja trabajar la suite sin interacción: **36 ejecuciones** = 1080p/720p ×
   pausado/activo × tres modos × **tres repeticiones**. Cada ejecución inicia
   Go de nuevo, prepara 10.000 años causales, espera 3 s pausado y mide **30 s**.
   La preparación repetida puede tardar mucho; no cierres la ventana de consola.
4. Conserva y comparte **toda** la carpeta `mediciones-*`, incluso si falla.
   Incluye manifiesto, equipo, parámetros, orden, crudos Godot, telemetría,
   CSV y logs PresentMon, stdout/stderr y logs Go cuando están disponibles.
   `resumen.json` se genera si hay Python 3 instalado; la captura no lo necesita.

**Medir completo.cmd** añade zooms 1,4,24: 108 ejecuciones. Para un ensayo técnico
corto antes de gastar toda la preparación, desde PowerShell:

```powershell
.\benchmark.ps1 -Seconds 5 -PreparationYears 3 -Repeats 1 -Modes minimal -Small
```

Eso es un smoke, no el benchmark de 400×200. Para medir el mismo conjunto sin
repetir controles del profiler, después de validar su overhead:

```powershell
.\benchmark.ps1 -Modes minimal -Repeats 3
```

Para investigar consultas/cámara, en otra carpeta de resultados:

```powershell
.\benchmark.ps1 -StaticCamera -NoSelection -Repeats 3
```

No mezcles esa variante con la suite original. El arnés registra los parámetros
exactos. Para resumir posteriormente en cualquier equipo con Python 3:

```powershell
python .\summarize.py .\mediciones-...\1920x1080-zoom24-activeFalse-minimal-r1.jsonl --out .\resumen-caso.json
# O todos los casos:
$files = Get-ChildItem .\mediciones-...\*.jsonl | Where-Object { $_.Name -notmatch '\.telemetry\.|suite\.' }
python .\summarize.py $files.FullName --out .\resumen.json
```

## Qué se mide

- **Presentación**: PresentMon ETW filtra el PID Godot confirmado, usa QPC y
  mantiene seguimiento de display activado. `DisplayLatency` + `CPUStartQPC`
  reconstruyen el evento de display; `DisplayedTime=NA` distingue no presentados.
  Se exige una sola swap chain relevante, eventos antes y después de la ventana,
  columnas válidas y PID exacto. No se suman swap chains ni se convierten los
  callbacks en FPS si falta evidencia. Se entrega tasa de eventos mostrados,
  P50/P95/P99/máximo de intervalos y porcentaje >33,333 ms. ETW observa el sistema
  de presentación, no mide fotones ni tiempo físico de escaneo del panel.
- **Ventana común**: sample_begin/end con reloj monotónico Godot y UTC; telemetría
  con QPC/UTC y acotación del tiempo de lectura. Se rechaza presentación válida
  si hay deriva o incertidumbre de alineación >5 ms. Los intervalos percentiles
  usan pares dentro de la ventana; huecos de ambos bordes se entregan separados.
  Se conservan los descartes y logs ETW. Advertencias de eventos perdidos invalidan
  la presentación; ausencia de advertencia no prueba ausencia absoluta de pérdida.
- **Callbacks**: `post_draw_interval_ms` es intervalo entre frame_post_draw,
  independiente de FPS. También se entrega conteo agregado y máximo en modo
  ligero. Selección/mapa→post_draw tampoco se llaman latencias de display.
- **CPU/RAM**: PID + hora de creación + ruta real; Go además padre y comando con
  endpoint y parent-pid propios. No se buscan procesos por nombre. Desde el
  arranque, cada 500 ms nominales: working set, memoria privada, CPU acumulada y
  delta, Godot/Go/recolector/PresentMon, RAM disponible, foco/minimización.
  100% de CPU one-core equivale a un núcleo; CPU machine se divide por lógicos.
  Primer delta o proceso ausente: null y estado explícito. Suma RAM sólo si
  ambos son válidos; su suma puede contar memoria compartida más de una vez.
  Son métricas de proceso/OS, no asignaciones de heap Go.
- **Hardware**: `targetHardwareVerified` se deriva de CPU i5-1340P, Iris Xe activa
  declarada por Godot y GPU Iris Xe en CIM. Inventario solo no basta. Modelo,
  driver, batería, plan de energía, resolución/refresco y versión de PowerShell
  quedan archivados. Este campo verifica identidad, no 30 FPS sostenidos.
- **Historia**: años/s son años publicados por el observador durante la muestra.
  Recepción anual incluye Go, transporte, decoder y espera de polling. La
  proyección/upload se miden aparte; no se altera ni salta el cálculo histórico.

## Control del profiler y comparabilidad

`baseline`: sin PresentMon y sin filas por callback, pero con contadores ligeros,
telemetría de procesos y eventos de etapa. `minimal`: lo mismo más PresentMon.
`detailed`: añade una fila por callback y monitores Godot. Los tres conservan el
mismo escenario, semillas, estado preparado, VSync desactivado, cámara y selección
automáticas. La consola del profiler se inicia oculta para no robar foco al Atlas.
Reproducción arranca después del calentamiento, desde año 1000 en
la preparación estándar. Cada ejecución comienza con mundo/Go nuevos.

Orden de escenarios invertido en la segunda repetición y modos rotados por
repetición, determinísticamente. `suite.jsonl` conserva el orden exacto. El
resumen agrupa sólo escenarios comparables y presenta medianas/rangos entre
repeticiones, variación de callbacks baseline→minimal (coste conjunto de ETW) y
minimal→detailed (coste de detalle). Revisar también CPU/RAM del profiler y años/s;
los deltas no prueban causalidad si hay calentamiento, energía u otras cargas.
Las dimensiones `map_pixels` quedan registradas: cambiar resolución también puede
cambiar el área visible, por lo que no aísla exclusivamente fill rate.
No restar un porcentaje supuesto de los resultados ni elegir la mejor repetición.

El lector JSONL mantiene offset y conserva líneas/UTF-8 parciales: no relee el
pasado. Escritores de telemetría persistentes. Dentro de la muestra Godot retiene
las filas en RAM (hasta 200.000 filas o 64 MiB estimados conservadoramente);
serialización medida, sin flush por frame. Vuelca después de fijar el final.
Desbordamiento invalida la captura. CPU, RAM, costo del sondeo y contador de bytes
leídos permiten evaluar el propio arnés. Un cierre abrupto puede perder ese
buffer: se preserva y marca como incompleto, nunca como rendimiento válido.

Para interpretar una interrupción, correlaciona callback, display, tiempos de
etapa, CPU, foco y lag del muestreo. Para demostrar una causa específica de
scheduler, driver o disco puede hacer falta una traza adicional; este paquete
no atribuye las pausas originales a una causa todavía no observada.

## Construir el mismo paquete

Con Go 1.27.2, Godot oficial 4.7.2 y plantilla Windows release x64, verificados
contra `client/tools/godot-pins.txt`, descargar también:

- `https://github.com/GameTechDev/PresentMon/releases/download/v2.3.0/PresentMon-2.3.0-x64.exe`
- Guardar como `build/atlas2d/tools/PresentMon.exe`.
- SHA256: `690533cf5c2591ef571a3037aa4c205c8e75860ef3f56927bf3a98acf7198485`.

Ejecutar `tools/build.py` como indica README, con destino vacío (se rechazan
archivos previos para evitar mezclas). La licencia PresentMon se distribuye con
el paquete. El manifiesto incluye commit, hashes de fuentes/adaptadores y de
todos los archivos entregados. CI aplica la misma receta y prueba el ejecutable
exportado frente al SHA Go directo; no regenera golden ni referencia.
