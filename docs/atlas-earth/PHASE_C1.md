# Fase C1 — red fluvial (HydroRIVERS) con topología verificada

## Qué se hizo
- `sources.json` registra HydroRIVERS v10 Europa/Oriente Medio. `fetch.py` descarga con User-Agent propio (el servidor devuelve 403 al agente por defecto de urllib) y verifica SHA-256; probado desde cero (descarga nueva, hash correcto; el SHA-1 que publica el servidor coincide).
- `tools/atlas/rivers.py`: lee el shapefile y el dbf, filtra por recuadro y jerarquía (`ORD_FLOW`; 1 = mayores), simplifica con Douglas–Peucker y escribe `asabiya/atlas-rivers-v1` con, por tramo: id, `nextDown`, cuenca (`MAIN_RIV`), longitud, orden de Strahler, endorreica y **caudal medio modelado** en `modelled`. No se deriva navegabilidad ni se mezcla con datos observados. Comprueba conexión aguas abajo y ciclos.

## Verificado (recuadro piloto −12…45°E, 29…72°N, ORD_FLOW ≤ 6)
- 156 638 tramos, 3 550 desembocaduras, **0 ciclos**; 92 tramos desembocan fuera del recuadro.
- Las 8 mayores desembocaduras por caudal modelado coinciden con ríos reales: Danubio (29,70°E 45,25°N, 6745 m³/s), Dvina Septentrional, Neva, Rin (4,15°E 51,96°N), Po (12,51°E 44,96°N), Ródano (4,81°E 43,38°N), Dniéper y Vístula.
- ORD_FLOW ≤ 4 (continental): 14 321 tramos, 3,0 MB; ≤ 6: 33 MB (demasiado para el cliente: requiere teselas, no está hecho). Tiempo ~13 s.
- Observación del dato: hay 8 pares con descenso de clase por <5 % de caudal y 65 con caídas >10 % de caudal aguas abajo, concentradas en el Oriente Medio árido (p. ej. Tigris/Éufrates ≈ 821→701 m³/s): pérdidas modeladas. Se registran en los metadatos, no se corrigen.

## Licencia — SIN RESOLVER
Los términos publicados dicen «libre para uso científico, educativo y comercial» y remiten a la HydroSHEDS License Agreement para la redistribución. **No pude leer ese texto** (la página no devolvió contenido). Por tanto **no se versiona ningún dato fluvial, bruto ni derivado**: la salida va a `build/` (ignorado). Pendiente: leer el acuerdo en hydrosheds.org y decidir si los derivados pueden distribuirse con el paquete Windows. Cita exigida/solicitada: Lehner & Grill (2013), incluida en los metadatos.

## Reproducir
```sh
python3 tools/atlas/fetch.py build/atlas/cache
python3 -I tools/atlas/rivers.py build/atlas/cache/HydroRIVERS_v10_eu_shp.zip build/atlas/rivers_eu_l6.json --max-ord-flow 6
```

## Límites y siguiente
- Sin vínculo con unidades territoriales, provincias ni celdas del motor; sin render en el cliente.
- Lagos/humedales no incluidos (HydroLAKES sin evaluar). Deltas y distribuidarios: HydroRIVERS es un árbol, así que no representa bifurcaciones.
- Siguiente: unidades territoriales estables (cuencas HydroBASINS + relieve) y mapeo a celdas del motor; teselado de ríos por LOD.
