# Atlas Tierra 2D — Fase A: auditoría técnica

Fecha: 24 de octubre de 2026. Rama: `claude/nice-planck-lf2sly`, desde `main` 4979e71 (PR #32 integrada). Solo lectura del repositorio más una consulta de red a Natural Earth. No se ejecutaron suites, simulaciones, Godot ni CI. Esta fase no modifica código.

## 1. Estado real (comprobado en el código)

| Hecho | Evidencia |
|---|---|
| Ya existe un cliente Atlas 2D en Godot 4.7 (Compatibility), integrado en `main`: `experiments/atlas2d/godot/` (~3000 líneas de GDScript, shader `terrain.gdshader`, UI de inspección). | `git log`, PR #30 y #32 |
| Ese atlas muestra un mundo **procedural** (o el raster "Earth" heredado), no geografía verificable. | `experiments/atlas2d/README.md` |
| Go es la autoridad: el cliente consume `HistoryFrame`/`WorldData` por TCP NDJSON local con geografía binaria `ASABGEO` (`asabiya/geography-v1`). | `internal/interop/geography.go` |
| El motor acepta fuentes de mundo importadas (PNG de altura, temperatura, precipitación y Köppen u8) mediante `--world-source`. No exige tocar la simulación. | `docs/mission/WORLD_INPUTS.md`, `internal/mapsource/load.go` |
| La malla del motor está limitada a **400×200 lógica, detalle ≤4** (1600×800 fina). | `internal/sim/world.go:31-44` |
| La Tierra integrada procede de rasters incrustados en el HTML v0.6 y **no tiene proveedor ni licencia identificados**. El propio documento lo declara. | `WORLD_INPUTS.md` |
| `AGENTS.md` raíz acumula instrucciones de misiones antiguas con restricciones de pruebas contradictorias. Prevalece `experiments/atlas2d/AGENTS.md` para esa carpeta. | `AGENTS.md` |

## 2. Consecuencia clave: la resolución de la malla del motor

Resolución angular efectiva: 0,9° (≈100 km en el ecuador) en la malla lógica y 0,225° (≈25 km) en la fina. La región piloto europea (−12°…45° lon, 29°…72° lat) ocupa unas **63×48 celdas lógicas** o **253×191 finas**.

Eso permite reconocer Europa a escala continental, pero **no cumple** "altísima fidelidad", provincias detalladas ni ríos o relieve de calidad editorial. Convertir la Tierra en una malla mayor exigiría tocar el motor (límite de validación, digests, golden), lo cual está prohibido sin autorización explícita en este repositorio.

## 3. Decisión arquitectónica propuesta (ADR-E1)

Separar dos capas, sin que el cliente simule nada:

1. **Atlas geográfico estático** (nuevo, offline, versionado): costas, relieve, hidrografía y derivados a resolución propia, por tiles y niveles de detalle. Es la capa visual y de consulta geoespacial.
2. **Mundo del motor** (existente): Go sigue simulando sobre su malla. El atlas la referencia mediante un mapeo explícito, geográfico→celda del motor. Cada celda del motor corresponde a un conjunto de unidades del atlas.

El mapeo atlas→celda se versiona y el cliente no crea datos históricos. Los estados de Go pintan sobre la geometría del atlas por identificador de celda. Esto da relieve y costas reales a la resolución de los datos y mantiene intactos RNG, calendario, golden y digests.

Para que el motor simule la Tierra real, el atlas generará los PNG de entrada del motor (altura, temperatura, precipitación, Köppen) a partir de los mismos datasets verificables. Se usa el mecanismo `--world-source` existente. Estos PNG sustituirían el raster heredado de origen desconocido. El cambio de fuente altera `World.Version` (`native/world-v3`) y los digests de esos mundos. No afecta a los procedurales ni a los golden actuales.

## 4. Fuentes y licencias (por verificar al descargar)

No se ha descargado ningún dataset todavía. Solo se comprobó que el proxy alcanza el host de Natural Earth. Antes de incorporar cada fuente se registrará versión, fecha, hash, CRS y términos exactos leídos de la propia página. Las siguientes anotaciones salen de mi conocimiento general y **deben confirmarse**:

| Fuente | Uso previsto | Nota provisional |
|---|---|---|
| Natural Earth (1:110m/50m/10m) | Costas, islas, lagos, ríos de referencia | Dominio público según su política; confirmar al descargar |
| Copernicus DEM GLO-90/GLO-30 | Relieve, pendiente | Licencia propia con atribución; **verificar** redistribución de derivados |
| HydroSHEDS/HydroRIVERS | Red fluvial, cuencas | Términos propios; **verificar** redistribución |
| OpenStreetMap | Solo referencias selectivas | ODbL: obligaciones de atribución y share-alike que pueden afectar al atlas derivado |
| geoBoundaries | Límites modernos como capa opcional | Verificar licencia por país |
| ESA WorldCover, WorldPop | Referencia contemporánea | Verificar; no sirven como verdad histórica |

## 5. Riesgos

1. **Identificadores.** El ID de provincia del motor es `fila*ancho+columna`. Cambiar la malla o la fuente cambia los IDs. El atlas debe llevar un `atlasVersion` y una tabla de migración explícita.
2. **Costa.** El cliente actual define costa como el signo de la elevación fina y usa un `land_remap`. Una costa real de mayor resolución puede contradecirlo. Se necesita una regla única de asignación atlas→celda.
3. **Licencia del raster heredado.** La Tierra actual no es redistribuible con garantías. Es una razón de peso para generar la propia.
4. **Tamaño.** Los DEM y capas fuente no deben ir a Git. Se necesitan manifiestos, hashes y scripts de preparación por región.
5. **Documentación contradictoria** entre misiones. Falta consolidarla en una PR documental aparte.
6. **Medición en hardware real.** No hay capturas en el i5-1340P/Iris Xe para el atlas nuevo. Los objetivos de FPS no se pueden afirmar.

## 6. Tecnología 2D

Se mantiene Godot 4 2D, ya decidida en `experiments/atlas2d/docs/TECHNOLOGY.md` (ADR-A1). Motivo: reutiliza el puente TCP, el decodificador y las sesiones con pausa y SHA ya verificados. Esa decisión se apoya en integración, no en FPS. Las cifras de microprobe se midieron en software (llvmpipe) y no predicen la Iris Xe. Reabrir la decisión solo con capturas emparejadas del cliente real.

## 7. Plan por fases (sin cambios en el motor)

| Fase | Entrega | Verificación mínima |
|---|---|---|
| B1 | `tools/atlas/`: manifiesto de fuentes, descarga con hash y validación; Natural Earth → máscara tierra/mar de Europa piloto | Hash reproducible; bbox y topología válidas; costas contra Natural Earth |
| B2 | Proyección y API de conversión geo↔mapa↔pantalla (lon/lat canónicos); tiles de costa por LOD | Ida y vuelta de coordenadas, meridiano 180°, selección por cursor |
| B3 | DEM → hillshade, pendiente, tintas hipsométricas por LOD | Montañas reconocibles (Alpes, Pirineos…); memoria acotada |
| C | Hidrografía y unidades territoriales estables, mapeo atlas→celda del motor | Adyacencias, polígonos válidos, IDs estables entre ejecuciones |
| D+ | Estados, asentamientos y eventos de Go sobre el atlas | Mismos digests Go; cliente solo proyecta |

## 8. No verificado en esta fase

Compilación Go/Godot, exportación Windows, rendimiento y exactitud geográfica de cualquier dataset. Nada de eso se ha ejecutado.

## 9. Pendiente de decisión del usuario

La Fase B1 requiere descargar datos públicos pequeños (Natural Earth 1:50m, pocos MB) y añadir `tools/atlas/` y `docs/atlas-earth/`. No toca el motor, el cliente 3D, la referencia ni los golden. Confirmar también si se autoriza generar PNG de mundo para `--world-source` y aceptar que cambie la versión del mundo Tierra.
