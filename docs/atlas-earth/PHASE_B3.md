# Fase B3 — relieve desde Copernicus DEM (recorte Alpes)

## Qué se hizo
`tools/atlas/dem_relief.py` descarga teselas Copernicus DEM GLO-90 (bucket público AWS Open Data) para un recuadro de grados enteros y produce, de forma determinista (numpy/tifffile/Pillow):
- `relief.png`: tinta hipsométrica suave × sombreado (Horn, luz 315°/45°, exageración vertical 2× solo para el sombreado, tamaño de celda según latitud).
- `slope.png` (0,4°/nivel) y `elevation_u16.png` (metros sin exagerar): regenerables, **no versionados** (3,7 MB).
- `relief.json`: fuente, atribución, parámetros, SHA-256 de cada tesela y de cada salida, teselas ausentes (mar) tratadas como 0 m.
Las salidas se promedian por bloques (factor 4 → 300 px/° ≈ 370 m); el sombreado se calcula antes a resolución completa.

## Resultado piloto
`data/atlas/alps-pilot/` (6°–12°E, 44°–48°N, 1800×1200). 24 teselas, ninguna ausente. Altura máxima del DEM 4793 m. Inspección visual: Se reconocen los Alpes con sus valles y lagos, la llanura del Po y los Apeninos ligures (los Pirineos no entran en el recuadro).

## Licencia y atribución (leída el 24-oct-2026 en la página COP-DEM de Copernicus Data Space)
GLO-30/GLO-90 son gratuitos para el público general. Al comunicar o distribuir datos modificados debe mostrarse: «produced using Copernicus WorldDEM-90 © DLR e.V. 2010-2014 and © Airbus Defence and Space GmbH 2014-2018 provided under COPERNICUS by the European Union and ESA; all rights reserved». Cualquier build que incluya estos derivados debe llevar ese aviso (queda en `relief.json` y debe mostrarse en la UI del atlas: **pendiente**). Los términos completos de redistribución conviene revisarlos en la ESA User Licence antes de publicar derivados fuera del uso personal.

## Reproducir
```sh
python3 -I tools/atlas/dem_relief.py build/atlas/dem data/atlas/alps-pilot 6 44 12 48
```
Requiere `pip install numpy tifffile imagecodecs pillow`. Dos ejecuciones dieron los mismos hashes de salida. Los hashes de teselas son confianza-en-primer-uso: el proveedor no publica sumas.

## Límites
- Es un DSM (incluye vegetación y edificios), no un DTM.
- Sin batimetría. `tools/atlas/compose_map.py` pinta el mar (máscara Natural Earth de B1, misma rejilla: `land_mask.py ... --bbox 6 44 12 48 --px-per-deg 300`) sobre `relief.png` con un tinte plano; comprobado visualmente con el Mar de Liguria del recuadro. No se versiona el PNG compuesto.
- Resolución 90 m: suficiente para vista continental/regional; GLO-30 queda para zoom provincial.
- Europa completa son ~2450 teselas (~12 GB de descarga): no se ha hecho; hay que ejecutarlo por regiones.
- Sin niveles de detalle/tiles ni carga en el cliente; sin medidas de memoria ni FPS.
- No se ha ejecutado nada del resto del repositorio.
