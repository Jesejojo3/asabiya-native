# Calendario causal y organización del port

`v06-compat` conserva el orden de `stepG` y de cada llamada interna. Dividir archivos Go por sistema en un solo paquete `internal/sim` inicialmente facilita inspeccionar el orden sin añadir dependencias circulares. Los nombres propuestos de archivo no indican implementación existente.

| Orden | Cadencia exacta JS | Sistema / orden interno | Archivo futuro |
|---|---|---|---|
| 0 | Frontera de año Y | Lote ordenado de comandos; posible guardar; vista completa | app/commands |
| 1 | Cada año | Incrementar a Y+1; climateStep, weather, hearthCheck | calendar, climate, technology |
| 2 | Cada año | Decrementar enfriamiento activo o sortear volcán | climate, catastrophe |
| 3 | Cada año | computeK, growth, migrate, seaHop | capacity, population, migration |
| 4 | `year % 3 === 0` | techStep(0,.34), (.34,.67), (.67,1), en ese orden | technology |
| 5 | Cada año | disease | disease |
| 6 | `year % 10 === 5` | poolPass | ecology_contact |
| 7 | `year % 20 === 7` | caravanPass | trade |
| 8 | Cada año | omenPass: favor, seguimiento y posible cataclismo | omen, catastrophe |
| 9 | Cada año | politicsG completo: agregación, gobernantes/estado, tecnología emergente, diplomacia, guerras, cohesión/formación y migraciones | politics, rulers, war, migration |
| 9a | Dentro de política | Muestreo de celdas si `%10===0`; conservar el RNG de reservoir sampling | politics |
| 9b | Dentro de política, `%5===0` | distBFS, integración por familia; después exitPass si `%10===0`; revisión de retención territorial | distance, identity, ecology_exit |
| 10 | `year % 20 === 0` | ethPass(true), relPass | peoples, religion |
| 11 | `year % 10 === 0` | recordStats, cityPass, regionPass, mixPass, snapshot | statistics, city, region, peoples, history |
| 12 | Frontera completa | Publicar vista; siguiente lote; nunca emitir estado parcial por los yield originales | app |

Esta tabla resume las fases, no sustituye las ramas internas de `politicsG` ni autoriza reordenarlas. Al portar un sistema se añade una traza de las subfases y sorteos y se coteja con su ubicación exacta en el HTML. Los yield son planificación de UI heredada, no nuevas fases causales ni puntos de entrada de comandos nativos.

## O1 — comercio y contacto antes de CE

En JS el resto de un año negativo no es +5 ni +7. Por ello `poolPass` y `caravanPass` no se llaman antes de CE en el calendario original: afecta propagación de contacto/enfermedad ganadera y actualización/creación de caravanas, no significa que toda forma de intercambio o tecnología naval esté desactivada. Además de la cadencia, caravanPass exige fuentes pobladas con estado junto a zonas áridas, camellos o wind wagons, una ruta desértica y destino poblado de otro propietario; ver 2022–2049.

`v06-compat` conserva exactamente ese comportamiento, sin normalizar el resto. Propuesta separada para `native/calendar-v2`: fases ancladas al año inicial (o un módulo positivo con época definida), con sus propios fixtures y revisión de balance/comercio. **No se implementa ni se elige silenciosamente una de esas alternativas.** Cambiar la cadencia también cambia llamadas RNG, enfermedades, rutas, impuestos e historia posterior.

## Expansión futura

Todo sistema nuevo de `native` declara fase y orden, entradas/eventos que consume, cadencia anclada a una época explícita, namespace RNG y versión de reglas. Mantener calendario y fixtures de `v06-compat` permanentemente. Nuevas mecánicas como refugiados o maravillas no se incorporan en esta Fase 0. Extender presiones seculares, comercio o sucesión parte de las variables ya existentes; no construir duplicados paralelos sin justificar un cambio de modelo.
