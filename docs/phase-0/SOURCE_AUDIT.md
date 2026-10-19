# Inspección estática de v0.6

Todos los números de línea corresponden al HTML intacto en `reference/v0.6/Asabiya History Engine (Copy).html`. Son observaciones del código, salvo las propuestas identificadas como tales. El fichero tiene 3 199 saltos LF, sin CRLF; no se ha convertido su codificación.

## División existente

| Área | Evidencia | Observación |
|---|---|---|
| Recursos | scripts `assets`, líneas 313–314 | Elevación terrestre y Köppen en base64 comprimido. Mantenerlos como parte de la referencia; documentar su procedencia/licencia antes de redistribuir recursos extraídos. |
| Núcleo | script `core`, 315–2299 | No se encontraron accesos a DOM, reloj, `Math.random` ni `Date` en este bloque. Usa los globales mutables `WD`, `S`, `P` y `CL`. |
| Interfaz | 2300–3198 | Canvas, navegación, paneles, semillas de entrada, importación de imágenes y planificación por frames. |
| Tamaños | 318 | Simulación 400×200 = 80 000 celdas; elevación/clima fino 1600×800; anomalías climáticas 40×20. No confundir resolución lógica con píxeles de pantalla. |
| Configuración | 319–381 | 40 parámetros `PDEF`, 16 climáticos `CDEF`; además `hearthMode`, `fitClimate`, `shuffleNames`, `sandbox`. |
| Datos | `TECH`, `OMENS`, `CATA` | 32 tecnologías, ocho presagios y siete cataclismos; inventario derivado en `evidence/source-inventory.json`. |

## Sistemas prioritarios y sus dependencias

| Prioridad | Entrada y estado relevantes | Funciones originales | Dependencias que conservar |
|---|---|---|---|
| Mapa | `WD`, elevación, vecinos, áreas, costas, ríos, islas y capas climáticas/ecológicas | `decodeEarth` 414; `genClimate` 425; `fitClimate` 468; `genWorld` 522; `prepEco` 1927 | Envoltura longitudinal; límites latitudinales; áreas variables; mapa fino y agregación; Tierra ajustada/no ajustada y mapa generado/importado. |
| Pueblos | `eth`, `eth2`, `mix`, `mixT`, `eths`, lenguas, población y familias | `newEth` 813; `newHistory` 864; `migrate` 1007; `seaHop` 1034; `ethPass` 1815; `mixPass` 1841 | Capacidad de carga, tecnología naval, enfermedades, geografía, presión migratoria, cultura y religión; nombres también consumen RNG. |
| Estados | `pol`, `pols`, `alive`, cohesión `s`, capitales, dinastías, fiscalidad | `newPolity` 1227; `succession` 1250; `civilWar` 1273; `collapse` 1302; `politicsG` 1621; `statecraft` 1951 | Alimentación, grano, arado, administración, ecología local, salida/circunscripción, desigualdad, rutas, religión y gobernantes. |
| Guerras | `wars`, `activeWars`, enemigos, alianzas, fronteras y distancias | `milAt` 1307; `attack` 1318; `raid` 1348; `decisive` 1356; `distBFS` 1367; `declareWar` 1383; `endWar` 1397; `diplomacy` 1423 | Impuestos/cohesión, armas, caballos/camellos, tsetsé, desierto, transporte, terreno y alcance administrativo; bajas y desplazamientos vuelven a población/ecología. |
| Presagios | `favor`, `omens`, `cataclysms`, `kMod`, `kModUntil` | `OMENS` 2063; `omenCheck` 2103; `castOmen` 2114; `omenFollow` 2177; `cataclysm` 2232; `omenPass` 2270 | Validación territorial/poblacional, tecnología, religión, epidemias, eras y capacidad de carga. `finishYear` 3053 completa el año antes de ejecutar un presagio desde UI. |

Los ocho presagios existentes son `kindle`, `discord`, `bounty`, `drought`, `spark`, `prophet`, `plague`, `doom`. No se incorporan otros. `favor` comienza en 3 y se recupera en `omenPass` a razón de 1/70 por año, con tope 5; sandbox usa 9. El seguimiento sucede a partir de los 50 años. Cataclismos existentes: `deluge`, `eruption`, `unravel`, `winter`, `quake`, `iceage`, `impact`.

## Secuencia anual que define el comportamiento

`step()` consume completamente el generador `stepG()` (1910–1923):

1. Incrementar año; `climateStep`, `weather`, `hearthCheck`.
2. Decrementar enfriamiento volcánico activo, o sortear erupción si no existe.
3. `computeK`, `growth`, pausa del generador, `migrate`, `seaHop`.
4. Si `year % 3 === 0`: `techStep` en tres bandas consecutivas, con pausas intermedias.
5. `disease`; `poolPass` si `%10===5`; `caravanPass` si `%20===7`; `omenPass`.
6. Consumir `politicsG` en orden.
7. Si `%20===0`: `ethPass(true)`, `relPass`.
8. Si `%10===0`: `recordStats`, `cityPass`, `regionPass`, `mixPass`, `snapshot`.

Las pausas permiten responder a la interfaz; no justifican reordenar sistemas ni paralelizarlos. Importante: los años iniciales son negativos. En JS el resto conserva el signo del dividendo; las condiciones `%10===5` y `%20===7` no se activan en esos años. No convertirlas a un módulo matemático positivo al portar.

## Clima, tecnología y ecología son causalidad del motor

`computeK` (958–980) combina temperatura, precipitación, anomalías, eras climáticas, productividad, agricultura/pastoreo, riego, fertilidad, bosque, salinidad, malaria y tecnología. Los modificadores de presagios/cataclismos afectan esa capacidad de carga. No sustituir por un valor fijo para acelerar el port.

`milAt` aplica tecnología y penalizaciones ecológicas; `politicsG` acumula impuestos y adaptación de nicho; `techFit`/`ecoD` (1945–1946), `exitPass`, `poolPass`, `caravanPass` y `cropExchange` completan retroalimentaciones. Enfermedad, religión, ciudades, lenguas y líderes pueden quedar fuera de los primeros paneles, pero no eliminarse como dependencias del núcleo.

Hay ocho tecnologías sintéticas ya presentes (`TECH[24..31]`, `synth:1`). Preservarlas forma parte de v0.6; no son nuevas propuestas de esta migración. Alias como `S.metal`→`tk[3]` o `S.admin`→`tk[6]` no siempre coinciden con `TECH[k].k` (`copper`, `writing`): el port debe conservar identidad de almacenamiento y significado, sin inferir equivalencia sólo por nombre.

## Aleatoriedad, interfaz e historial

- `mulberry32` y `hashStr`, 383–384: operaciones de 32 bits y hash sobre unidades UTF-16.
- Mundo: `hashStr('world:'+seed)` (523). Historia: `hashStr('hist:'+hseed+':'+worldSeed)` (865).
- `placeName` (2094–2096) crea un RNG derivado por celda; no consume el RNG histórico.
- `Math.random` en UI elige semillas al arrancar/re-sortear (3130, 3192). Registrar el resultado explícito para reproducir; un enlace compartido sólo lleva una semilla de historia y no toda la configuración (3131–3133).
- `frame` (3156) divide trabajo usando tiempo real; la pausa por 1800 es una decisión de UI (3165), no un límite de `step()`.
- `snapshot`/`polAt`/`layerAt`, 2277–2298, guardan vistas históricas reducidas, no el estado completo para reanudar. Claves políticas cada 500 años, diferencias cada diez; capas cada 50 y adelgazamiento del pasado. No usarlas como formato de partida completa.

La inspección no demuestra por sí sola ausencia de defectos históricos. Cualquier discrepancia detectada debe registrarse y decidirse separadamente de la compatibilidad.
