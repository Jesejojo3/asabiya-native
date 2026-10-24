# Fase C1 — red fluvial (HydroRIVERS) con topología verificada

## Qué se hizo
- `sources.json` registra HydroRIVERS v10 Europa/Oriente Medio. `fetch.py` descarga con User-Agent propio (el servidor devuelve 403 al agente por defecto de urllib) y verifica SHA-256; probado desde cero (descarga nueva, hash correcto; el SHA-1 que publica el servidor coincide).
- `tools/atlas/rivers.py`: lee el shapefile y el dbf, filtra por recuadro y jerarquía (`ORD_FLOW`; 1 = mayores), simplifica con Douglas–Peucker y escribe `asabiya/atlas-rivers-v1` con, por tramo: id, `nextDown`, cuenca (`MAIN_RIV`), longitud, orden de Strahler, endorreica y **caudal medio modelado** en `modelled`. No se deriva navegabilidad ni se mezcla con datos observados. Comprueba conexión aguas abajo y ciclos.

## Verificado (recuadro piloto −12…45°E, 29…72°N, ORD_FLOW ≤ 6)
- 156 638 tramos, 3 550 desembocaduras, **0 ciclos**; 92 tramos desembocan fuera del recuadro.
- Las 8 mayores desembocaduras por caudal modelado coinciden con ríos reales: Danubio (29,70°E 45,25°N, 6745 m³/s), Dvina Septentrional, Neva, Rin (4,15°E 51,96°N), Po (12,51°E 44,96°N), Ródano (4,81°E 43,38°N), Dniéper y Vístula.
- ORD_FLOW ≤ 4 (continental): 14 321 tramos, 3,0 MB; ≤ 6: 33 MB (demasiado para el cliente: requiere teselas, no está hecho). Tiempo ~13 s.
- Observación del dato: hay 8 pares con descenso de clase por <5 % de caudal y 65 con caídas >10 % de caudal aguas abajo, concentradas en el Oriente Medio árido (p. ej. Tigris/Éufrates ≈ 821→701 m³/s): pérdidas modeladas. Se registran en los metadatos, no se corrigen.

## Licencia
Los términos publicados: libre para uso científico, educativo y comercial; la redistribución se rige por la HydroSHEDS License Agreement. El propietario del proyecto leyó el acuerdo el 24-oct-2026 y confirmó que **sí se pueden redistribuir** los derivados. Claude no ha leído el texto completo: se conserva la cita de Lehner & Grill (2013) y el enlace a hydrosheds.org en los metadatos y debe mostrarse en la interfaz (**pendiente**). Se versiona solo el nivel continental (`ORD_FLOW ≤ 4`) en `data/atlas/europe-pilot/rivers_l4.json`; los niveles regionales siguen generándose en `build/` hasta que haya teselado.

## Reproducir
```sh
python3 tools/atlas/fetch.py build/atlas/cache
python3 -I tools/atlas/rivers.py build/atlas/cache/HydroRIVERS_v10_eu_shp.zip data/atlas/europe-pilot/rivers_l4.json --max-ord-flow 4
```

## Límites y siguiente
- Sin vínculo con unidades territoriales, provincias ni celdas del motor; sin render en el cliente.
- Lagos/humedales no incluidos (HydroLAKES sin evaluar). Deltas y distribuidarios: HydroRIVERS es un árbol, así que no representa bifurcaciones.
- Siguiente: unidades territoriales estables (cuencas HydroBASINS + relieve) y mapeo a celdas del motor; teselado de ríos por LOD.

## Coherencia entre capas (comprobación visual)
Superpuestos los 733 tramos de `rivers_l4.json` sobre el relieve del recorte alpino (DEM Copernicus + costa Natural Earth) en la misma rejilla lon/lat, los cauces siguen los valles del relieve (Po, Tesino, Adda, Rin en Basilea) sin desplazamientos apreciables. Es una inspección a simple vista, no una medición de error; con ORD_FLOW ≤ 4 no se dibujan los valles alpinos altos. Los datos regenerados son idénticos byte a byte (SHA-256 `89b2122d…d4a5`).
