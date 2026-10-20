# Pendientes verificables de paridad v0.6

Este archivo enumera brechas **no implementadas en esta rama**. No confundir disponibilidad de datos Go con exposición completa en Godot. Consultar `PARITY_V06_MATRIX.md` para clase y evidencia. El HTML original no se modifica.

| ID de matriz | Pendiente preciso | Referencia original → receptor pendiente | Siguiente paso comprobable |
|---|---|---|---|
| PAR-003 | Relaciones políticas ampliadas y árbol de sucesión | HTML:2702–2729 → `internal/sim/queries.go:entityLocked(polity,ruler)`; `client/godot/scripts/app/main.gd:_entity_sections` | Mostrar aliados, tributarios, dinastía/episodios como relaciones navegables, sin recalcular historia |
| PAR-004 | Linaje y léxico de pueblos | HTML:2730–2739 → `queries.go:entityLocked(people)`; `main.gd:_entity_sections` | Panel de ancestros/hijos y palabras reales de `lexicon`; prueba headless con datos Go |
| PAR-005 | Cismas y difusión religiosa | HTML:2740–2748 → `queries.go:entityLocked(religion)` | Conectar `parentId`, `children`, `stateIds`, sin entidades religiosas inventadas |
| PAR-007 | Resumen de coaliciones y contexto bélico | HTML:2709–2714,2760–2788 → `queries.go:entityLocked(war)` | Mostrar participantes, razones y resultados conservando IDs nativos |
| PAR-008 | Ruta de migraciones en el mapa | HTML:2819–2824 → `queries.go:entityLocked(migration)`; `map_view.gd` | Renderizar de manera temporal `path` del motor, sin activar tick/polling |
| PAR-011 | Hazañas y relaciones de figuras | HTML:2749–2755 → `queries.go:entityLocked(figure)`; `main.gd:_entity_sections` | Transformar `deeds` en cronología legible y enlaces existentes |
| PAR-013 | Índice epidemiológico ordenado | HTML:2873–2889 → `queries.go:entityLocked(outbreak)`; `hud.gd` | Lista 100 primeras por muertes/fecha y ficha sin copiar epidemias a estado local causal |
| PAR-014 | Índice/cartografía de cataclismos | HTML:2793–2802,2876–2889 → `queries.go:entityLocked(cataclysm)` | Historial filtrado por año y zoom al `cellId` validado |
| PAR-015 | Búsqueda textual de crónicas | HTML:2834–2856 → `hud.gd:_fill_chronicle` | Campo de búsqueda por texto/contexto y filtro tipo, con límite de resultados |
| PAR-016 | Curvas históricas interactivas | HTML:2594–2645 → `queries.go:Stats`; `hud.gd:_fill_stats` | Gráfico del histórico disponible sin consultas proporcionales a 80k por frame |
| PAR-018 | Editor PDEF con valores y restricciones exactas | HTML:2963–2977 → `internal/sim/catalog.go:ParameterDef`, `internal/sim/commands.go:change_rules`; `hud.gd` | Añadir UI de sliders con precondición de mundo nuevo; emitir `asabiya/command-v1`, leer rechazo y replay |
| PAR-019 | Activación/desactivación de sandbox | HTML:3034–3040 → `internal/sim/commands.go:set_sandbox` | UI solo a través de comando Go secuenciado; mostrar favor efectivo devuelto |
| PAR-020 | Intervenciones dirigidas a provincia | HTML:3030–3058 → `internal/sim/commands.go:cast_omen`; `internal/interop/protocol.go:apply_command` | Selector de los 8 tipos, precondiciones, apuntado y respuesta del motor |
| PAR-021 | Catálogo de costes/permisos de presagios | HTML:3031–3039 → `internal/sim/intervention_catalog.go`; `internal/interop/protocol.go:get_catalog` | Exponer el catálogo del motor a la UI sin duplicar reglas causales |
| PAR-022 | Parámetros de generación y re-inicio | HTML:3103–3130 → `internal/interop/protocol.go:create_world,start_history`; `hud.gd:_build_world_dialog` | Selector de mundo, opciones de generación y semilla histórica independientes |
| PAR-023 | Tierra y mundos importados desde interfaz | HTML:3103–3128 → `internal/mapsource/load.go`, `world_source.go`; `bridge_source.gd` | UI de fuentes y validación de importaciones; no modificar recursos referencia |
| PAR-024 | Evaluación climática y ajuste CDEF | HTML:2893–2962 → `internal/sim/climate_configured.go`, `world_source.go` | Validar equivalencia del optimizador antes de crear controles de usuario |
| PAR-025 | Histórico decenal más allá de frames locales | HTML:3000–3021 → `internal/sim/historical_queries.go:HistoricalLayer`; `internal/interop/protocol.go:get_historical_layer` | Consulta por demanda de año, capas parciales sin ampliar retención |
| PAR-027 | Capas especiales del HTML no reflejadas | HTML:2315–2321,2391–2461 → `internal/sim/queries.go:ProvinceView`; `client/godot/scripts/map/map_layers.gd:DEFS` | Auditar cada campo de mapa contra publicaciones compactas y añadir modos faltantes |
 
## Estado del bloque ya realizado

- **PAR-010 / PAR-012:** índice de figuras y búsqueda histórica implementados en `client/godot/scripts/ui/hud.gd`, con regresiones en `client/godot/tests/atlas_ux_regressions.gd`. El estado de CI debe verificarse antes de declarar este bloque aprobado.
- **Sin afirmar:** pruebas visuales de Windows, paridad global, nuevas mecánicas de edificios o export Windows en esta rama.
- Si algún workflow falla, conservar SHA de fallo y reparar la causa sin regenerar goldens ni deshabilitar aserciones.
