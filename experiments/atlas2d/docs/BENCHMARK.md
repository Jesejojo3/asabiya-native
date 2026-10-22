# Captura reproducible

Objetivo pendiente de medir: Windows 11 x64, i5-1340P, Iris Xe, RAM 16 GB.
30 FPS sostenidos: comprobar también P95/P99 y porcentaje de frames >33,333 ms;
FPS P50 por sí solo no acredita estabilidad. 60 FPS es el objetivo deseable.

`benchmark.ps1` ejecuta el paquete exportado. Cada sesión usa semilla Asabiya,
historia 1, 400×200, detalle 4; prepara explícitamente 10000 años con el encadenador
TCP existente. Se avisa de que esta preparación no muestra cada año intermedio.
La medición normal sí solicita/publica años consecutivos, con backpressure del
renderizador. No hay años ocultos en reproducción. Pausa obtiene SHA exacto.

Matriz completa (`-Full`): 1920×1080 y 1280×720, zoom 1/4/24, pausa/activo máximo, 3 repeticiones,
3 s de calentamiento +30 s de muestra. El doble clic básico mide sólo zoom 24,
una repetición, ambas resoluciones y pausa/activo: cuatro capturas. Ventana, no pantalla completa; tamaño
físico registrado. Misma trayectoria sinusoidal en coordenadas del mundo,
selección del centro cada segundo, política. El panel reduce el área útil del
mapa; se registra ventana y viewport. VSync se solicita desactivado: comprobar
el log porque un controlador puede ignorarlo. No cambiar driver entre capturas.
Registrar corriente/perfil energético/temperatura y aplicaciones abiertas.

JSONL: intervalos entre `frame_post_draw` de Godot; no son latencia de fotones ni
mediciones GPU de PresentMon. `fps_p50=1000/P50(frame_ms)`; percentiles por
interpolación lineal `(n−1)*q`; FPS medio = frames / suma de sus intervalos.
Selección local: picking y panel; selección presentada: hasta siguiente post-draw;
consulta: ida y vuelta TCP en pausa. Actualización: recepción en hilo principal
hasta post-draw; separar CPU de proyección y subida de textura. La consulta
provincial se descarta si cambia selección/año. Años/s: diferencia del año
presentado entre sample_begin y end / tiempo monótono, excluye preparación y warmup.
El modo headless rechaza captura de FPS; `--smoke-out` ejecuta tres años y
compara SHA, sin producir métricas gráficas. Memoria estática Godot **no es RSS**. El runner registra WorkingSet64 de Godot,
Go y suma cada 500 ms (incluye arranque; puede perder picos entre muestras).
Identifica PID real con `OS.get_process_id`, hijo Go con ready; no mide launcher.

```powershell
.\benchmark.ps1 -Full -Seconds 30 -PreparationYears 10000 -Repeats 3
# El runner invoca summarize.py con los archivos correctos si hay Python.
```

Al resumir, incluye sólo capturas de aplicación, no `.memory.jsonl` ni equipo.json.
El script PowerShell pasa automáticamente la lista correcta si hay Python.
Conservar datos crudos, equipo.json, logs, manifiesto del paquete y modo energético.
Las capturas marcan verificación del equipo como false: revisar equipo.json y el
adaptador real antes de atribuirlas a Iris Xe. No se cambia esa bandera por CLI.

## Microprototipos

```sh
go run ./experiments/atlas2d/probes/fixture --years 10000
go build -o build/atlas2d/ebiten-probe ./experiments/atlas2d/probes/ebiten
# Ejecutar SECUENCIALMENTE, mismo equipo y sin otras cargas:
build/atlas2d/ebiten-probe --fixture build/atlas2d/fixture --out ebiten.jsonl --seconds 30 --zoom 4
godot --path build/atlas2d/project --script res://probe.gd -- --fixture=/ruta/absoluta/build/atlas2d/fixture --out=/ruta/godot.jsonl --seconds=30 --zoom=4
```

Ambos dibujan exactamente terreno.png + political.png exportados de Go, sin
símbolos (0), filtro lineal, 1920×1080, cinco copias periódicas, zoom 4 y misma
trayectoria. Son un caso estático mínimo; no contienen la integración/UI del
atlas ni prueban equivalencia de calidad de renderizado final. Repetir con zoom
1/24 y registrar sistema/controlador. No comparar con el cliente 3D de 13 FPS
sin captura emparejada del mismo equipo/estado/cámara/calidad.
