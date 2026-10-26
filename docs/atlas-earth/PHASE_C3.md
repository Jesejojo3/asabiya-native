# Fase C3 — mapeo atlas → celdas del motor y contraste con la Tierra heredada

## Geometría de la malla del motor (leída de `internal/sim/world.go`, no supuesta)
Equirectangular de centros de celda, fila 0 al norte: `id = y*W + x`, `lon = −180 + 360·(x+½)/W`, `lat = 90 − 180·(y+½)/H`; con la Tierra, 400×200 (0,9° por celda).

## `tools/atlas/cell_map.py`
Muestrea cada celda en una sub-rejilla 18×18 (0,05°), asigna cada muestra a la unidad que la contiene (test exacto de punto en polígono en el centro de la muestra, ponderado por cos(lat)) y emite una relación **muchos a muchos con fracciones de área** (`data/atlas/europe-pilot/cell_map.json`, 0,2 MB): una celda puede solapar varias unidades y una unidad varias celdas. No decide tierra/mar: eso sigue siendo del motor.

### Verificado
- **Un sesgo propio corregido:** el primer relleno de polígonos (Pillow) incluía los píxeles del contorno y daba +2,4 % de área total, con error que bajaba a la mitad al duplicar la resolución. Lo sustituí por un test exacto de centro de muestra.
- Tras la corrección, unidades interiores a la ventana y > 20 000 km² (100 unidades): error de área frente al área esférica de la unidad, **mediana 0,2 %, p95 0,84 %, máximo 1,6 %**. Las unidades que cruzan el borde de la ventana alineada a celdas quedan cortadas por construcción y no entran en esta métrica.
- 1 899 celdas con alguna cobertura (836 completas), 1 unidad sin ninguna muestra (más pequeña que el paso).

## Contraste con el motor (`tools/atlas/compare_engine_land.py`)
Se exportó la Tierra con `asabiya-headless --seed Earth --earth-html … --years 0 --export <dir>` (sin simulación; `worldSHA256` `8f441029…c758`) y se comparó su capa `land` con la máscara Natural Earth 1:50m en las 2 961 celdas enteramente dentro del recuadro:

| | celdas |
|---|---:|
| ambas tierra | 1 740 |
| ambas mar | 1 181 |
| solo motor tierra | 29 |
| solo Natural Earth tierra | 11 |
| **coincidencia** | **98,65 %** |

38 de las 40 discrepancias son celdas costeras con fracción de tierra Natural Earth entre 0,15 y 0,85 (ambigüedad inherente a 0,9°). Conclusión acotada: **a escala de celda, la costa del raster heredado coincide con una fuente verificable en esta región**; no valida su relieve ni su clima, y no resuelve la falta de licencia de ese raster.

## Hallazgo: cobertura de unidades incompleta en el recuadro piloto (resuelto en C4: 307 → 61 celdas de tierra sin unidad)
268 celdas de tierra del motor sin unidades están en el norte de África y el Levante (latitud < 37,5°), que HydroBASINS **no** incluye en el archivo «Europe»; hay que añadir las regiones `af` y `as` (misma licencia). Otras 39 son celdas de costa/fiordo o del borde de ventana. Hasta entonces, el atlas solo cubre con unidades la parte europea del recuadro.

## Pendiente
Selección por cursor con índice espacial; unidades `af`/`as`; relieve/pendiente/ecología por unidad (el DEM solo cubre los Alpes); decidir el sentido de la asignación cuando el motor y el atlas discrepan en la costa (hoy el atlas no decide tierra/mar); no se ha ejecutado ninguna simulación sobre estas unidades ni medido rendimiento.

## Reproducir
```sh
python3 -I tools/atlas/cell_map.py data/atlas/europe-pilot/units-l6 data/atlas/europe-pilot/cell_map.json
go build -o build/bin/asabiya-headless ./cmd/asabiya-headless
build/bin/asabiya-headless --seed Earth --earth-html "reference/v0.6/Asabiya History Engine (Copy).html" --years 0 --export build/atlas/earth-export
python3 -I tools/atlas/compare_engine_land.py build/atlas/earth-export data/atlas/europe-pilot
```
