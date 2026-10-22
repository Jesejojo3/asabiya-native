# Asabiya Atlas 2D · Sprint 01: consolidación, integridad y estabilidad

## Fase 0: base verificada (22-10-2026)

| Referencia | SHA | Estado |
|---|---|---|
| `main` | `714d06c3a9d3ce9d69dbb184161a99b2c78e82f1` | Sin el motor histórico ni el cliente; no se modifica |
| PR #21, consolidación (base de #27) | `79035761f1e61041a3ccbf74b648577e53ba7150` | Abierta, sin fusionar |
| PR #27, Atlas 2D Misión A (`experiments/atlas2d/mission-a`) | `6f234dbe8313eef68aaa195254335643b8b1a295` | Abierta, borrador; **base de este sprint** |
| PR #26, especificación 2D (`docs/atlas-2d-first-20261021`) | `10258dd16763a92e5ad0c5194f0e600e827ecad5` | Documentación de producto |
| PR #22, #24, #25 (cliente 3D) | — | Cerradas sin fusionar; el cliente 3D queda intacto en el árbol |

- **Cliente Atlas 2D vigente:** Godot 4.7.2 oficial, renderer *Compatibility* (OpenGL), proyecto
  propio en `experiments/atlas2d/godot`.
  - `tools/stage.py` lo compone con ocho adaptadores del cliente 3D copiados byte a byte (con
    manifiesto SHA): `BridgeSource`, `NativeFrameDecoder`, `HistoryFrame`, `WorldData`,
    `MapLayers`, etc.
  - Se comunica con Go por el protocolo TCP local `asabiya/local-v1`.
- **Trabajo paralelo:** la rama de #27 la creó otra sesión. Para no tocar su rama, este sprint se
  desarrolla en `claude/bold-carson-smo9r9` (rama asignada a esta sesión), a partir del SHA
  exacto de #27, y se propone como PR independiente con base `experiments/atlas2d/mission-a`.
  - El contenido anterior de esa rama era la PR #25, cerrada. Se conserva en GitHub en
    `refs/pull/25/head` (`d20d13e`).
- **Archivos que no se modifican:** `internal`, `cmd`, el protocolo, `client/godot` (cliente 3D
  y los adaptadores compartidos), `reference/` y los golden. CI lo comprueba con
  `git diff --exit-code` contra la base.

## E1 · Versión consolidada

### Funcionalidades nuevas o completadas, todas con datos de Go

- **Pestañas de la barra lateral:** Provincia, Entidad, Crónica, Buscar y Mundo.
- **Provincia:**
  - Enlaces al Estado, pueblo, religión y ciudad.
  - Altitud, bioma, tecnología y capacidad.
  - En pausa, consulta de Go (cohesión, integración, fortificación) e historial de propiedad.
    Las respuestas se guardan por provincia, año y SHA, y ya no se pierden al redibujar el
    panel (defecto corregido).
- **Entidad** (`atlas_entities.gd`): ficha de los 12 tipos de entidad que publica Go.
  - Tipos: Estado, pueblo, religión, ciudad, gobernante, figura, guerra, ruta, migración,
    epidemia, presagio y cataclismo.
  - Muestra campos y relaciones navegables, con «◀ Anterior».
  - Si la entidad no figura en la publicación, lo dice y no rellena nada.
- **Crónica:** todos los acontecimientos que retiene Go (hasta 1000).
  - Filtro por clase y texto, del más reciente al más antiguo.
  - Enlaces a la provincia y a las entidades referenciadas.
  - Se corrige el año mostrado como decimal (`-9000.0`).
- **Buscar:** por nombre o ID en los 12 tipos, sobre los registros publicados (sin consultas
  extra al motor).
- **Mundo:**
  - Población; Estados (tipo *state*) y entidades políticas; pueblos, religiones, ciudades y
    guerras activas.
  - SHA del estado y los últimos 12 registros de `stats`.
  - **Consulta de capas históricas** de Go (`get_historical_layer`): pueblos, religiones,
    densidad, era o cohesión de cualquier año retenido, con el año real de la capa indicado.
- **Capas:**
  - Las 23 capas del catálogo compartido. Las que Go no publica (economía) quedan desactivadas y
    explicadas.
  - Rutas comerciales activas dibujadas como polilíneas sobre su trayecto Go.
- **Años:** con la convención de v0.6 (`6001 a. C. [-6000]`).
- **Rendimiento** (ver E4):
  - Render bajo demanda fuera de las mediciones.
  - El mapa se redibuja solo cuando cambian la cámara, la capa o la selección.
  - La liberación de publicaciones antiguas se hace fuera del hilo principal.
  - Métricas por fotograma del hilo principal y del render.

### Compilar y ejecutar (Linux; en Windows, rutas `.exe`)

```sh
go build -o build/bin/asabiya-server ./cmd/asabiya-server
python3 experiments/atlas2d/tools/stage.py
godot --headless --path build/atlas2d/project --import
godot --path build/atlas2d/project -- --server="$PWD/build/bin/asabiya-server"
# Historia madura: añade --prepare-years=10000 (Go calcula todos los años; muestra cada 100)
```

Paquete Windows sin herramientas instaladas: artefacto `asabiya-atlas2d-windows-x64` del workflow
*Atlas 2D experiment* (`tools/build.py`). Uso en `README.md` y `docs/OWNER_GUIDE.md`.

### Pruebas

```sh
go run ./experiments/atlas2d/probes/fixture --small --years 3 --out build/atlas2d/test-fixture
godot --headless --path build/atlas2d/project --script res://test_atlas.gd -- --server=ABS --small --expected=ABS/build/atlas2d/test-fixture/state.json
godot --headless --path build/atlas2d/project --script res://test_integrity.gd -- --server=ABS --small
```

## E3 · Informe de integridad

Todas las pruebas son headless (sin GPU) contra el servidor Go real compilado desde el mismo
árbol, en un mundo de 48×24 con detalle 4, semilla «Asabiya» e historia 1. Las ejecuté en Linux;
CI las repite en Linux y Windows.

| Requisito | Prueba (`test_integrity.gd` salvo indicación) | Resultado |
|---|---|---|
| El cliente no altera el estado causal | `get_replay` antes y después de: recorrer todas las capas, seleccionar, consultar, abrir fichas, buscar, filtrar la crónica, abrir el panel Mundo, pedir y cerrar una capa histórica, revisar un año antiguo | Mismo año y mismo SHA; ningún año solicitado |
| Identidades coherentes | Estado de la provincia = registro `polity` publicado = `get_entity` de Go (nombre e ID); búsqueda por nombre devuelve el mismo ID | Pasa |
| Consultas del año seleccionado | `get_entity`, `get_province` e historial responden con el año mostrado; propietario y población del panel = `get_province` | Pasa |
| La pausa detiene el avance | Tras pausar, 2 s de fotogramas: sin nuevas publicaciones; `get_replay` igual | Pasa |
| Reanudar no duplica | Años retenidos estrictamente consecutivos tras dos ciclos reproducción/pausa; SHA igual a `get_replay` | Pasa |
| Operaciones de interfaz sin efectos | Ídem fila 1 | Pasa |
| Determinismo por semilla | Nueva sesión con la misma semilla: mismo SHA de mundo y mismo SHA inicial; otra semilla: otro mundo | Pasa |
| Eventos y estadísticas originales | La crónica cuenta los eventos Go publicados y muestra el texto de los 10 últimos; el panel Mundo muestra la población Go | Pasa |
| Capas históricas fieles | La capa de pueblos de Go para el año inicial coincide con la publicación retenida de ese año | Pasa |
| Observador = Go directo (`test_atlas.gd`, de #27) | 3 años: SHA `84690d61…` igual que Go sin cliente | Pasa |

**Resultado:** `ATLAS INTEGRITY: 69 checks, 0 failures` y `ATLAS TESTS: 0 failures`.

**Determinismo a escala completa** (400×200, detalle 4, 10 000 años con el avance rápido del
Atlas): año 1000 con SHA `e7df456c262d6bf4f01918de79a8ff1b3eb8f736f347c7d5c3cf12e44d1c27e9`. Es el
mismo SHA que dan Go *headless* en Linux, Go en Windows (CI de #25) y la captura del usuario en
Windows con el cliente 3D.

### Incompatibilidades y diferencias registradas

1. Go conserva las capas históricas cada 50 años (cada 250 con más de 1500 años) y sin propietarios.
   El propietario histórico solo existe por provincia (observación decenal).
2. Hay dos recuentos de Estados. `stats.polities` (Go) y el número de Estados de tipo *state* que
   cuenta el cliente difieren del total de entidades políticas vivas, porque este incluye hordas y
   otros tipos. El panel muestra ambos con su definición.
3. Go no publica el campo `wealth`: la capa de economía del catálogo compartido no puede mostrarse.
4. Go redacta los textos de eventos en inglés.
5. La revisión de años cubre las 24 publicaciones que retiene el adaptador compartido, no todo el
   archivo; las capas históricas Go cubren el resto con su resolución.
6. Las consultas de detalle provincial solo se hacen en pausa y sobre el último año (diseño de #27
   que se mantiene).

### Defectos corregidos

- Año de la crónica mostrado como decimal.
- El detalle Go del panel provincial se perdía al redibujar.
- Solo 8 de las 23 capas eran accesibles.
- Las rutas no se veían en 2D.
- Las entidades no eran navegables.
- El mapa y los símbolos se redibujaban en cada fotograma aun en reposo.
- La liberación de años antiguos ocurría en el hilo principal.

### Pendientes

Intervenciones causales (reglas, sandbox, presagios), filtros avanzados de figuras, trayectorias
de migración y epidemias, curvas estadísticas, guardar sesión y validación visual en Windows.

## E4 · Informe de rendimiento

Ver `PERFORMANCE_SPRINT01.md`. Todo se midió con llvmpipe, sin Iris Xe; en resumen:

- Los tirones del modo activo venían de liberar las publicaciones expulsadas en el hilo
  principal. Al pasar ese trabajo a un worker:
  - P95 de frame: de 128–147 ms a 45–48 ms.
  - P99: de 252–260 ms a 62–64 ms.
  - Hilo principal P95: de 116–126 ms a 1,5 ms.
- La mediana de FPS en activo baja unos 4 FPS, y en pausa hay una regresión de un 8 % frente a
  #27 que no se ha aislado. Ambas quedan documentadas como pendientes.
- En reposo se dibuja 1 fotograma/s en lugar de 58.
- El objetivo de 30 FPS a 1080p en Iris Xe sigue **sin verificar**. El procedimiento de Windows
  está en el informe.

## E5 · Preparación del siguiente sprint (solo documentación)

### Dependencias para la Tierra real

- **Motor:** `WorldSource` y `mapsource` ya admiten fuentes Tierra (`earth-html`, imágenes de
  elevación, temperatura y precipitación).
- **Pendiente:**
  - Dataset con licencia, versionado y hash.
  - Decidir la proyección y la resolución lógica (hoy 400×200 con detalle 4).
  - Política de IDs de provincia estables.
  - Golden y replays nuevos que no invaliden los mundos procedurales.
- **Atlas:**
  - Selector de fuente al crear la sesión. `BridgeSource.source_config` ya existe.
  - Mostrar «Tierra» frente a «procedural».
  - Etiquetas geográficas reales y proyección de símbolos (hoy por celda).

### Componentes reutilizables

- `BridgeSource`, `NativeFrameDecoder`, `HistoryFrame`, `WorldData` y `MapLayers`, compartidos
  byte a byte con el cliente 3D.
- `AtlasEntities`: fichas, crónica y búsqueda, sin lógica histórica.
- `AtlasProjection`: picking, capas vivas e históricas.
- El shader de terreno 2D por campos finos.
- Las pruebas de integridad (`test_integrity.gd`) y el banco de medición (`atlas_metrics.gd`).

### Riesgos arquitectónicos

1. Cada año Go envía JSON que se decodifica en GDScript: es el coste de CPU dominante con
   reproducción rápida. Un formato binario sería un cambio de contrato y requiere una PR propia
   con pruebas de digest.
2. Retener 24 publicaciones completas cuesta unos 3 GB de RAM en un mundo maduro, entre Godot y Go.
   Hay que medirlo con la Tierra antes de aumentar la resolución.
3. `MapLayers` mezcla catálogo y color; separarlo exigiría tocar el adaptador compartido.
4. La Tierra puede cambiar los IDs de celda. El picking, las capas y los enlaces dependen del ID
   row-major.
5. Los adaptadores compartidos atan el Atlas al cliente 3D. Extraerlos a un paquete neutral es
   una PR propia, con export de ambos clientes.

### Recomendaciones para el overhaul UX/UI

- Diseño visual de la barra lateral (tipografía, iconos, jerarquía) sobre las cinco pestañas ya
  funcionales.
- Leyendas gráficas en lugar de texto.
- Mini-mapa y línea de tiempo con las capas históricas de Go.
- Tooltips al pasar sobre provincias. El picking ya da el ID; hace falta un hover barato.
- Traducción de eventos en el cliente o en Go (decisión de producto).
- Accesibilidad: escala de UI, contraste y teclado.
- No reintroducir el render continuo: mantener el modo bajo demanda.
