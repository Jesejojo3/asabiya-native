# Fase B2 — geodesia y proyección neutrales

## Qué se hizo
`internal/atlas/geo` (Go, sin dependencias, sin importar `sim`): 
- `LonLat` es la identidad geográfica persistente (grados). `MapPoint` (equirectangular, X∈[0,1) con envoltura E-O, Y 0 en el polo norte) y `Camera` son derivados y no se guardan como identidad.
- `Camera.ToScreen/ToMap/ZoomAt`: pantalla↔mapa↔geografía; `ToScreen` elige la copia E-O más próxima al centro (sin saltos en ±180°); `ZoomAt` conserva el punto bajo el cursor.
- `DistanceKm` (haversine), `RingAreaKm2` (área esférica, desenvuelve cruces de 180°), `BBox` con soporte de antimeridiano, `NormLon`.

## Decisiones
- Esfera de R=6371,0088 km: error de distancia/área frente al elipsoide hasta ~0,5 %. Aceptable para consultas y estimaciones; no es geodesia de topografía.
- Equirectangular para el mundo (la malla del motor ya lo es). La distorsión en latitudes altas queda fuera de las distancias, que usan siempre geometría esférica. Una proyección regional (p. ej. cónica) podría añadirse tras esta interfaz sin tocar identidades.
- Las zonas polares se manejan por recorte de Y; no hay tratamiento especial de polo en polígonos todavía.

## Verificado (go test ./internal/atlas/...)
Ida y vuelta de proyección, envoltura de ±180°, París–Roma ≈1105 km, 1° de longitud en el ecuador a 180°, cuarto de meridiano exacto, área de celda 1°×1° (con y sin cruce de 180°), ida y vuelta de cámara, ancla del zoom, ausencia de salto en pantalla en el antimeridiano, `BBox` normal y antimeridiano. Pasan. No se ejecutó nada más del repositorio.

## Pendiente
Espejo en GDScript para el cliente (misma fórmula, pruebas cruzadas), selección por cursor con índice espacial (requiere provincias, Fase C), inspector de coordenadas/distancias en el atlas.
