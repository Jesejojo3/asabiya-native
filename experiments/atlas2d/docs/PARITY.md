# E2 · Matriz de paridad HTML v0.6 → Atlas 2D (Sprint 01)

Referencia funcional: `reference/v0.6/Asabiya History Engine (Copy).html` (inmutable; SHA-256
`988ce360e70d2d034a3898f60b9a4c38d40b0ab56dd7a147329740f15fa8e9e9`). Los identificadores
PAR-xxx y las líneas `HTML:n` son los de `docs/mission/PARITY_V06_MATRIX.md` (auditoría del
cliente 3D), reevaluados aquí para el Atlas 2D. Base: PR #27 `6f234dbe`.

Clases:

- **A**: operativa en Atlas 2D con datos Go y una prueba reproducible.
- **C**: parcial; el límite se indica.
- **P**: pendiente (Go la implementa, el Atlas no la expone).
- **E**: sustituida deliberadamente.
- **X**: fuera de alcance deliberadamente en este sprint.

Pruebas citadas:

- `TA`: `experiments/atlas2d/godot/test_atlas.gd`, de PR #27.
- `TI`: `experiments/atlas2d/godot/test_integrity.gd`, nueva en este sprint.

Todas son headless frente al servidor Go real; ninguna valida píxeles en Windows.

| ID | Capacidad del HTML | Atlas 2D | Evidencia (código · prueba) | Límite o diferencia |
|---|---|:---:|---|---|
| PAR-001 | Provincia, coordenadas y propietario | A | `atlas_app.gd:_update_panel` · TA (consulta ID/propietario/población) · TI (`get_province` = panel) | Detalle (cohesión, fortificación, ciudad) solo en pausa y en el último año. |
| PAR-002 | Historia del dueño provincial | A | `_update_panel` (`query_history`, enlaces a Estados) · TI (texto «Propiedad observada») | Observación decenal de Go; no es la fecha exacta de conquista. |
| PAR-003 | Estados, gobernantes, dinastías y relaciones | C | `atlas_entities.gd:render` (polity: dinastía, métricas, capital, gobernante, aliados, rivales, sucesores, guerras) · TI (ficha = `get_entity`) | Sin árbol de gobernantes ni vistas comparativas. |
| PAR-004 | Pueblos, linaje y vocabulario | C | `render` (people: padres, descendientes, 6 componentes culturales, léxico, cambios fonéticos) · TI (ficha de pueblo) | Sin vista genealógica completa. |
| PAR-005 | Religiones, cismas y adopción estatal | C | `render` (religion: ramas, Estados adoptantes, custodio) | Sin alcance geográfico histórico propio (sí en la capa histórica de religiones). |
| PAR-006 | Ciudades y capitales | C | `atlas_symbols.gd` (puntos y nombres reales), `render` (city), enlace de capital | Población provincial, no censo urbano; sin edificios. |
| PAR-007 | Guerras, coaliciones y resultados | C | `render` (war), capa `wars`, crónica | Go no publica frentes; no se dibujan. |
| PAR-008 | Migraciones | C | `render` (migration), búsqueda | Sin trayectoria cartográfica. |
| PAR-009 | Rutas comerciales | C | capa `routes` con polilíneas de rutas activas (`atlas_symbols.gd`), `render` (route) | Sin relaciones comerciales detalladas. |
| PAR-010 | Índice de figuras, filtros y búsqueda | C | `AtlasEntities.search` (por nombre/ID y por tipo) | Sin los cinco filtros ni la puntuación de renombre del HTML. |
| PAR-011 | Ficha de figuras con hazañas | C | `render` (figure: hazañas Year/Text de Go) | Referencias internas de cada hazaña no enlazadas. |
| PAR-012 | Exploración de registros desde el buscador | A | pestaña Buscar: 12 tipos de entidad Go, 60 resultados · TI (encuentra el Estado por nombre) | Búsqueda en los registros publicados, sin consulta adicional al motor. |
| PAR-013 | Epidemias | C | búsqueda y ficha (outbreak) | Sin ordenación por mortandad ni mapa de propagación. |
| PAR-014 | Cataclismos | C | búsqueda y ficha (cataclysm) | Sin mapa de alcance. |
| PAR-015 | Crónica con categorías y navegación | A | pestaña Crónica: filtro por clase y texto, enlaces a provincia y entidades · TI (recuento y textos = eventos Go) | Hasta 1000 eventos que retiene Go y 300 líneas en pantalla; Go redacta en inglés. |
| PAR-016 | Estadísticas mundiales y de era | C | pestaña Mundo (población, Estados, pueblos, religiones, ciudades, guerras, últimos 12 registros de `stats`) · TI | Sin curva interactiva. |
| PAR-017 | Reproducción, pausa y avance | A | `_step`, `_pause`, velocidades 1/5/20/máx · TA · TI (pausa estable 2 s, reanudación consecutiva) | Una publicación por año; sin años ocultos. |
| PAR-018 | Editor de reglas | P | Go: `internal/sim/commands.go:change_rules` | El Atlas es observador; las intervenciones causales se dejan para otro sprint. |
| PAR-019 | Sandbox | P | Go: `set_sandbox` | Ídem. |
| PAR-020 | Lanzar presagios | P | Go: `cast_omen` | Ídem. |
| PAR-021 | Catálogo y costes de presagios | P | Go: `get_catalog` | Ídem. |
| PAR-022 | Reglas de nuevo mundo y semilla | C | campo de semilla + Nueva sesión · TI (misma semilla = mismo mundo y SHA) | No expone tamaño, fracción de tierra ni semilla histórica. |
| PAR-023 | Mundo Tierra y fuentes importadas | X | — | Siguiente sprint (ver `SPRINT01.md`, E5). |
| PAR-024 | Controles de clima y autoajuste | P | Go: `climate_configured.go` | Sin interfaz. |
| PAR-025 | Capas históricas retenidas | A | pestaña Mundo: «Ver capa histórica Go» (`get_historical_layer`, `AtlasProjection.historical`) · TI (capa = publicación del mismo año) | Go conserva capas cada 50 años (cada 250 pasados 1500), sin propietarios. |
| PAR-026 | Capas política, pueblos, religiones, población, era y terreno | A | selector con las 23 capas de `MapLayers.DEFS` · TI (recorre todas las capas disponibles) · TA (textura = proyección) | `economy` desactivada: Go no publica ese campo. |
| PAR-027 | Alianzas, cohesión, desigualdad, enfermedad y anomalías | C | cohesión en la capa histórica; desigualdad y tesoro en la ficha del Estado | Sin modos de mapa propios. |
| PAR-028 | Navegación, zoom, clic y selección | E | `atlas_map.gd` (zoom continuo, Mundo/Región/Provincia, costura longitudinal, selección por ID) · TA (picking e IDs) | Canvas Godot 2D en lugar del canvas HTML. |
| PAR-029 | Preferencias y enlace compartido | X | — | El Atlas no guarda nada todavía. |
| PAR-030 | Reproducción exacta y trazabilidad | A | barra de estado con SHA · TA (SHA = Go directo) · TI (`get_replay` = año/SHA mostrados, igual antes y después de usar la interfaz) | — |

Recuento: 8 A, 14 C, 5 P, 1 E, 2 X (30 capacidades). Ninguna clase A afirma validación visual en
Windows ni rendimiento en Iris Xe.
