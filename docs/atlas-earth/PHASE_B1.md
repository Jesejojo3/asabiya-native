# Fase B1 — máscara de tierra de Europa piloto

## Qué se hizo
- `tools/atlas/sources.json`: manifiesto de fuentes (Natural Earth 1:50m Land v4.1.0, SHA-256 fijado, dominio público según sus términos, leídos el 24-oct-2026).
- `tools/atlas/fetch.py`: descarga y verifica el hash. Sin credenciales.
- `tools/atlas/land_mask.py`: rasteriza los polígonos (lector SHP propio, numpy + Pillow, sin dependencias GIS) a una máscara equirectangular, 255 tierra / 0 mar, muestreo en centro de píxel.
- `data/atlas/europe-pilot/land_mask.{png,json}`: salida para −12°…45° lon, 29°…72° lat a 20 px/°  (1140×860 píxeles), con hash de fuente y de salida.

## Reproducir
```sh
python3 tools/atlas/fetch.py build/atlas/cache
python3 -I tools/atlas/land_mask.py build/atlas/cache/ne_50m_land.zip data/atlas/europe-pilot
```
Debe dar `sha256` `f4f3232e…b08c` en `land_mask.json`.

## Verificado
- Dos ejecuciones consecutivas dan el mismo hash.
- Muestreo de 9 puntos (París, Roma, Madrid, Alpes: tierra; Mediterráneo, Mar del Norte, Golfo de Vizcaya, Mar Negro, Báltico: mar): todos correctos.
- Inspección visual: Iberia, Italia, Balcanes, Escandinavia, Islas Británicas, Báltico y Negro reconocibles.

## No verificado / límites
- Sin comparación cuantitativa contra otra fuente, ni exactitud en islas pequeñas (1:50m las generaliza).
- Costa contemporánea: aproximación, no paleogeografía.
- Sin relieve, hidrografía, proyección de cliente ni integración con Go o Godot. No se ejecutaron suites del repositorio.
- No se han generado PNG para `--world-source`; requieren DEM (siguiente paso).

## Siguiente
B2: API de conversión geo↔mapa↔pantalla; B3: DEM (Copernicus, licencia por verificar) → relieve.
