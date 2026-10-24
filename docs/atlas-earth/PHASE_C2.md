# Fase C2 — unidades territoriales estables (Nivel C)

## Decisión
Se evaluaron cuencas HydroBASINS de nivel 5/6/7 frente a la malla del motor (≈6 000–10 000 km² por celda lógica de 0,9°):

| Nivel | Unidades en el recuadro piloto | Mediana | P5 – P95 (km²) |
|---|---:|---:|---|
| 5 | 378 | 16 820 | 591 – 84 707 |
| **6** | **1 183** | **5 494** | **370 – 24 121** |
| 7 | 4 305 | 1 525 | 75 – 6 753 |

Se elige el **nivel 6**: tamaño comparable al de las celdas del motor pero con forma derivada de cuencas y relieve, no de una cuadrícula. El nivel 7 queda como refinamiento local futuro (Nivel D). No se afirma que 6 sea el óptimo para rendimiento o jugabilidad: no se ha medido ninguna simulación sobre ellas.

## Procedimiento (`tools/atlas/units.py`, determinista)
1. Cuencas cuyo centro de caja cae en el recuadro (no se recortan: recortar inventaría fronteras).
2. Adyacencia por aristas compartidas exactas (HydroBASINS es una partición).
3. Las astillas < 400 km² se funden con el vecino de mayor frontera compartida (orden por área e id). Las islas sin vecinos se conservan: 17 unidades isla.
4. Id de unidad = `u` + HYBAS_ID de la cuenca miembro mayor; se conserva la lista de cuencas miembro. Estable solo **dentro de una versión del atlas**; una versión nueva exigirá tabla de migración.

Cada unidad guarda área esférica, caja, costera/isla, vecinas (con segmentos compartidos), unidades aguas abajo y la lista de cuencas. La geometría (simplificada 0,01°) va aparte, `units_geom.json`, para no retransmitirla ni duplicarla en snapshots históricos.

## Verificado (nivel 6, recuadro piloto: 1 120 unidades, 63 fusionadas)
- Área total calculada por mí (esfera, 9 469 271 km²) frente a la suma del atributo `SUB_AREA` de HydroBASINS (9 469 236 km²): diferencia 4·10⁻⁶. Concuerda con la fuente; no demuestra por sí sola la ausencia de solapamientos.
- Adyacencia simétrica (0 asimetrías), ids únicos, 0 anillos sin cerrar, dos ejecuciones con salidas idénticas byte a byte.
- Las 7 ciudades de control (París, Madrid, Roma, Berlín, Londres, Viena, Zúrich) caen cada una en exactamente una unidad.
- Solo 2 unidades < 400 km² quedan sin fusionar y ambas son islas.

## Límites conocidos
- Heterogeneidad: la unidad de París mide ≈1 088 km², la de Berlín ≈22 893 km² (máximo 69 939). El límite hidrológico no equivale a equilibrio de población o gameplay; un paso posterior podría subdividir las muy grandes.
- Son unidades **geográficas**, sin ningún significado político. Las fronteras entre cuencas no son fronteras de Estado.
- Las costas siguen las cuencas de HydroBASINS (nivel de generalización distinto a Natural Earth 50m): no se han reconciliado ambas.
- El borde del recuadro sigue cuencas enteras. No hay aún relieve/pendiente/ecología por unidad (el DEM solo cubre los Alpes).
- No hay aún mapeo a celdas del motor ni selección por cursor con índice espacial.
- Licencia HydroBASINS: mismos términos que HydroRIVERS; el propietario confirmó la redistribución. Cita en los metadatos.

## Reproducir
```sh
python3 tools/atlas/fetch.py build/atlas/cache
python3 -I tools/atlas/units.py build/atlas/cache/hybas_eu_lev06_v1c.zip data/atlas/europe-pilot/units-l6
```
Salida: `units.json` (0,4 MB) y `units_geom.json` (3 MB). Sale con código ≠ 0 si falla alguna comprobación.
