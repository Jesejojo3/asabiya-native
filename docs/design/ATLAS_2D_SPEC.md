# Asabiya Atlas 2D — especificación de detalle y experiencia

**Estado:** objetivo de diseño, sujeto a prototipos; no es evidencia de implementación.

## 1. Promesa visual

**2D de altísimo detalle**, no pixel art obligatorio, no mapa austero y no un sustituto temporal de bajo esfuerzo. Aspiramos a un **atlas histórico vivo**, con cartografía coherente de la Tierra, atractivo visual premium, información contextual profunda y navegación ágil.

Prioridad: **fidelidad histórica y cartográfica legible** sobre complejidad gráfica superficial. La apariencia debe mantener identidad propia; las referencias a CKIII son de escala, navegabilidad y claridad, no copia de assets ni interfaces.

## 2. Capas del mapa

| Familia | Capas objetivo | Fuente de verdad |
|---|---|---|
| Física | relieve sombreado, costa, ríos, lagos, elevación, pendientes | atlas geográfico versionado |
| Ambiente | climas, biomas, vegetación, suelos, aptitud, riesgos | datos geográficos + Go donde corresponda |
| Política | Estados, propietarios, fronteras, disputas, cambios | Go |
| Sociedad | pueblos, culturas, lenguas, religiones, población | Go |
| Economía | recursos, producción, ciudades, minas, puertos, comercio y caminos | Go; iconografía de cliente |
| Historia | guerras, migraciones, crisis, cataclismos, colonización, acontecimientos | eventos/estado Go |
| Material | construcciones, fortalezas, monumentos, abandono y ruinas | Go cuando se implemente patrimonio causal |

Las capas pueden superponerse con controles de opacidad, leyenda y fechas. **Los datos ausentes no se sustituyen por números inventados.** No todos los mapas existen hoy.

## 3. Qué aparece al acercarse

### Vista mundial
Geografía continua, clima general, áreas de pueblos/culturas, grandes Estados, religiones, migraciones, guerras y cataclismos. Nombres geográficos con jerarquía cartográfica. Evitar miles de etiquetas pequeñas.

### Vista regional
Provincias, fronteras detalladas, principales ciudades, caminos y rutas comerciales, zonas de producción, fortalezas, campos de conflicto, nombres regionales y principales sitios históricos.

### Vista provincial
Asentamientos menores, infraestructuras, explotación de recursos, ríos secundarios, sitios arqueológicos, estados de conservación de edificios y ocupaciones anteriores. Señales gráficas de cuándo un lugar cambió de manos, creció, fue saqueado o se abandonó.

### Vista de sitio / inspector profundo
Ficha o plano ilustrado de ciudad, edificio o ruina: cultura de origen, fundador si hay datos, edad, material, función, propietario, abandono, restauraciones, usos sucesivos, cronología y conexiones con eventos. **No requiere un mapa 3D navegable.**

El zoom afecta **representación y densidad**, nunca la causalidad del estado. No renderizar cada hogar en todas las escalas.

## 4. Historia material visible y arqueología

La capa «Palimpsesto Histórico» es una **función propuesta**. Sus futuras reglas deben soportar:

- construcción → ocupación → reparación/deterioro → abandono/daño → ruina → nueva ocupación/reutilización;
- restos simultáneos de eras muy distintas en la misma provincia;
- materiales, edad y condición coherentes con capacidades de la sociedad actual;
- iconografía/ilustración contextual para ruinas de piedra, industria, tecnología de fusión o instalaciones orbitales;
- consulta de la cronología del lugar y de las sociedades constructoras.

**Ejemplo hipotético:** asentamiento agrícola pequeño junto a las ruinas de un reactor de fusión. El atlas muestra el sitio y su estado; Go determina si los habitantes pueden aprovechar materiales o conocimientos. La UI no inventa un reactor por estar el mundo en «era cyberpunk».

## 5. Controles e interacción

- Zoom continuo dirigido por cursor, panorámica suave, volver a selección y escalas rápidas.
- Selección de celda/provincia/ciudad/sitio con identidad estable; hover ligero y clic para inspector completo.
- Búsqueda geográfica e histórica, relaciones enlazadas (pueblo ↔ Estado ↔ provincia ↔ ciudad ↔ evento).
- Línea temporal de campaña y cronologías locales; comparación de épocas si los datos históricos lo permiten.
- Pausa, paso exacto, velocidad y modo observador; distinguir tiempos de simulación de tiempos de render.
- Filtros, leyendas, señalización de datos faltantes, tooltips, acceso por teclado y soporte razonable para pantallas/DPI.
- Mostrar por qué ocurre un evento cuando existen datos causales; distinguir explícitamente hecho de interpretación.

## 6. Dirección artística

- Cartografía topográfica refinada, no ruido decorativo ilegible.
- Tipografía escalonada por importancia y nivel de zoom.
- Paleta de tierras/agua/relieve legible en conjunto con overlays políticos; evitar colores territoriales que oculten hidrografía.
- Iconografía consistente de ciudades, puertos, fortalezas, recursos, ruinas y cataclismos; variaciones por condición y contexto histórico.
- Ilustraciones de edificios, culturas o artefactos en fichas para dar riqueza sin polígonos.
- Un lenguaje visual común desde Neolítico hasta Fusión/Orbital, con formas que evolucionan pero navegación estable.
- Assets provisionales claramente indicados; no basar requisitos funcionales en assets generados aún inexistentes.

## 7. Rendimiento como requisito visual

«Máximo detalle» significa el máximo detalle **útil** sostenido por la máquina, no el máximo de píxeles o sprites simultáneos.

Técnicas a evaluar: tiles/tesselas y LOD cartográfico, cachés por región, preprocesado de sombreado, cambios diferenciales, culling, agregación a zoom lejano, instanciación, límites de etiquetas y consulta bajo demanda.

**Máquina inicial:** Windows x64, Intel Core i5-1340P/Iris Xe/16 GB según pruebas previas. **Aspiración:** 1080p, desplazamiento fluido y ~60 FPS si el hardware lo permite con la calidad elegida. Definir mínimo medido en el prototipo; registrar FPS y P50/P95/P99, RAM y años/s (en pausa y activo). No extrapolar resultados de 3D ni prometer un número.

No confundir cientos de miles de celdas de simulación con igual número de objetos dibujados a la vez.

## 8. Criterios de aceptación de la vertical slice 2D

1. Misma identidad/propiedad/población entre Go, mapa e inspector, dentro del contrato disponible.
2. Zoom mundial–regional–provincial con información añadida y etiquetas legibles.
3. Al menos capas física, política y otra sustentada en datos reales.
4. Selección de provincia, ficha, historia y transición anual sin invenciones.
5. Escenario medido reproducible en Windows (FPS, memoria, carga e input).
6. No alterar Go, golden, replay, IDs ni cliente 3D existente.
7. Assets placeholder se distinguen de contenido definitivo y las capas futuras figuran como pendientes.

**Más detalle no equivale a más complejidad sin propósito: una buena vista provincial debe permitir reconstruir qué pasó, a quién y qué queda hoy.**
