# Fase C4 — África, geometría sin solapes e índice espacial

## Cambios
1. **Cobertura.** `units.py` acepta varios archivos regionales (`units.py OUT ZIP [ZIP…]`). Se añade HydroBASINS África nivel 6 (misma licencia, confirmada por el propietario). Resultado: **1 348 unidades** (1 120 europeas + 228 africanas), 17 islas, área total 11 605 367 km² frente a 11 605 324 km² del atributo `SUB_AREA` (4·10⁻⁶). El archivo de Asia (`as`) no aporta ninguna unidad en el recuadro: Anatolia y el Levante ya están en el de Europa. Solo 2 pares de unidades europeo–africanas son adyacentes.
2. **Celdas del motor sin unidad** (Tierra heredada, recuadro piloto): de **307 a 61**; las restantes son celdas sueltas de costa/fiordo y del borde de la ventana. 0 asimetrías de vecindad.
3. **Geometría.** Verificación con el índice nuevo: **27 de 60 000 puntos pseudoaleatorios caían en más de una unidad.** Causa: simplificar cada anillo por separado hacía que una frontera compartida quedara distinta a cada lado. Corregido ajustando los vértices a una rejilla de 0,01° (idéntica en ambos lados) y eliminando solo vértices exactamente colineales: **0 solapes en 60 000 puntos**. Coste: las fronteras se desplazan hasta ~0,007° (<1 km); 1 975 anillos menores de ~1 km se descartan (se cuentan en `droppedCollapsedRings`; el área de las unidades sale de los polígonos originales, no de estos). Además se descubrió que los anillos que se colapsan al simplificar producían geometría degenerada (2–3 puntos): el cargador ahora los rechaza y el script no los emite.
4. **Índice espacial** (`internal/atlas/index`, Go): `Load(dir)`, `At(lonlat)`, `AtAll`, `Unit(id)`. Rejilla de cubos de 1° + caja + trazado de rayos par-impar; el empate en una frontera se resuelve por el menor id. Coordenadas enteras escaladas (`scale`) en `units_geom.json` (7,8 MB).

## Verificado (`go test ./internal/atlas/...`, `go vet`)
- Siete ciudades de control → las mismas unidades que la comprobación independiente en Python; mar abierto (Mar del Norte) → ninguna; longitud +360° se normaliza.
- 60 000 puntos pseudoaleatorios (xorshift con semilla fija): 35 075 caen en una unidad, 0 en dos, todos dentro de la caja de su unidad.
- Vecindad simétrica para las 1 348 unidades.
- Rendimiento orientativo: ~12 µs por consulta `At` (1 CPU Xeon de la sesión de nube, 20 000 iteraciones, un punto). **No es una medición en el equipo de referencia.**
- Mapeo a celdas con la geometría nueva: error de área por unidad interior > 20 000 km² (119 unidades): mediana 0,22 %, p95 0,83 %, máx 1,16 %.

## Límites
- Los huecos entre unidades (mar, lagos grandes sin cuenca) son «sin unidad» por diseño; no hay unidades para el mar.
- El sesgo a la rejilla de 0,01° es independiente de HydroBASINS; para zoom provincial/local harán falta niveles de detalle más finos.
- No hay consulta por cursor en el cliente: falta el espejo en GDScript de `geo` e `index`, y la lectura de este formato en Godot.
- Los ids siguen siendo estables solo dentro de la versión del atlas.

## Reproducir
```sh
python3 tools/atlas/fetch.py build/atlas/cache
python3 -I tools/atlas/units.py data/atlas/europe-pilot/units-l6 \
  build/atlas/cache/hybas_eu_lev06_v1c.zip build/atlas/cache/hybas_af_lev06_v1c.zip
python3 -I tools/atlas/cell_map.py data/atlas/europe-pilot/units-l6 data/atlas/europe-pilot/cell_map.json
go test ./internal/atlas/...
```
Dos ejecuciones dan archivos idénticos byte a byte.
