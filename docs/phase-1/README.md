# Fase 1 — primer bloque nativo

**Documento histórico del Bloque 1**, integrado en `7fb42f9eab9304b7bcd6811a379780ea6ca4723b`. Estado posterior: [Bloque 2](BLOCK2.md). Las limitaciones y propuestas siguientes corresponden al momento de aquella entrega.

Entrega para revisión, **sin autorización de merge**. Rama `phase-1/native-world`, creada desde el merge de Fase 0 `2bbefb70959bc0648dbf29b08b17e814ff287625`. Este documento actualiza el estado de implementación; los documentos de Fase 0 siguen como historial de diseño/auditoría.

## Paso previo completado

`legacy-v0.6` es un tag ligero, verificado mediante la API Git de GitHub: objeto tipo `commit`, SHA **`fe58bdb2ccf4db83857b02d16fa1852b54836824`**. No apunta al merge. Creado por la [tarea temporal expresamente autorizada](https://github.com/Jesejojo3/asabiya-native/actions/runs/39198335396), que terminó correctamente. La tarea se retira en esta misma rama después de ejecutarse; su commit queda en el historial. La nueva CI sólo solicita lectura del repositorio. Main no se modifica.

## Funcionalidad disponible

| Área | Implementado | Límite de este bloque |
|---|---|---|
| Semillas/RNG | hashStr sobre UTF-16, Mulberry32 uint32, Float64, semilla/contador uint64 y restauración directa | Entrada pública: cadenas UTF-8 válidas; no representa sustitutos UTF-16 aislados |
| Terreno | makeNoise, fbm, deformación esférica, muestreo ponderado por latitud, nivel del mar y elevación | Sólo rama procedural; no Earth ni imágenes importadas |
| Clima inicial | genClimate y boxBlur con los 16 valores originales de CDEF | Sin fitClimate, ajustes UI, clima anual ni tiempo atmosférico |
| Mundo | agregación 4×4, elevación/clima/rugosidad, latitud, área, vecinos, costas, componentes terrestres | Sin drenaje/ríos, aptitud ecológica, enlaces de mar ni interpolación meteorológica |
| Simulación | World inmutable, CellID, sesión con año −9000 y RNG histórico propio | Sin población, pueblos, estados, guerras, eventos o AdvanceYear |
| Headless | JSON, consulta x,y, PNG, versión del mundo y entorno numérico | Informe diagnóstico, no Save/Restore |
| Presentación | PNG estándar y viewport Ebitengine con textura, escalado y Esc | Sin widgets, cámara, crónica ni UI completa; ventana aún pendiente de prueba interactiva |

Los colores de la vista son una leyenda provisional de elevación, temperatura y precipitación, **no** una implementación de los biomas o de la aptitud agrícola original. No inferir población o capacidad de carga a partir de ellos.

## Trazabilidad del port

Referencia: HTML inmutable en `reference/v0.6/`, SHA-256 `988ce360e70d2d034a3898f60b9a4c38d40b0ab56dd7a147329740f15fa8e9e9`.

| Fuente v0.6 | Implementación |
|---|---|
| 383–384: mulberry32/hashStr | `internal/rng/rng.go` |
| 391–406: makeNoise/fbm | `internal/sim/noise.go` |
| 407–410 y 425–467: boxBlur/genClimate | `internal/sim/climate.go` |
| 522–543: genWorld procedural/elevación | `internal/sim/world.go`, generateElevation |
| 552–582: agregación, vecinos, costas, landmasses | `internal/sim/world.go`, GenerateWorld/indexLand |
| 865: prefijo de semilla histórica | `rng.HistorySeed`; sólo separación del flujo, no port de newHistory |

Comprobar fórmulas en el HTML, no usar esta tabla como sustituto de su lectura. Las capas finas se liberan tras agregarlas; World sólo guarda los datos gruesos implementados. No hay todavía recursos extraídos del HTML ni nuevos catálogos dirigidos por datos.

## Decisiones de implementación

1. **ADR-010: producto nativo Windows x64.** Go 1.27.2 y Ebitengine 2.10.5, sumas de módulos en go.sum. `GOAMD64=v1`, CGO desactivado. Se usa Go math; no jsmath ni promesa de paridad V8 o entre CPUs distintas. El build script rechaza otra versión/plataforma. Go requiere versión mínima en go.mod; la versión exacta está además en .go-version y CI/script.
2. **ADR-011: un paquete sim, archivos por sistema.** Arrays privados float32 como almacenamiento; fórmulas en float64 al leerlos. World es inmutable y devuelve Cell por valor. CellID firmado con −1 como vecino ausente, índice row-major estable dentro de mundo/versiones. No crear aún repositorios genéricos de entidades: pueblos/religiones conservarán sus centinelas firmados y estados su cero al portarlos. Referencias persistentes futuras por ID, no direcciones de memoria.
3. **ADR-012: sesión inicial explícita.** Simulation no finge una historia creada ni expone un AdvanceYear vacío. RNG de generación e historia separados con los prefijos originales. Aún no hay comandos/replay/guardado. La futura transición anual seguirá siendo atómica, respetando calendario y semántica de colecciones de Fase 0; no se elige ahora una goroutine ni un sistema de eventos genérico.
4. **ADR-013: límites y versiones.** Default original 400×200 con detalle 4 y tierra 0,33. Resoluciones de desarrollo configurables hasta ese tamaño; fina mínima 96×64 para que las marchas de humedad no usen pasos inestables. Es una extensión nativa documentada, no parte del oráculo. Parámetros climáticos originales fijos bajo `native/world-v1`; cambiar algoritmo/defaults requiere revisar versión, manifiesto y fixtures. La fracción objetivo se pondera por latitud y no equivale al porcentaje exacto de celdas.
5. **ADR-014: huella nativa separada.** Digest SHA-256 con cadenas prefijadas por longitud, versión/config, semilla/contador y todos los arrays persistidos en orden row-major, bits float32/float64 y enteros LE, incluyendo −0. No tiene timestamp ni orden de mapas. Es fingerprint de regresión, no formato de partida ni hash del oráculo. Reporte JSON incluye toolchain y backend numérico; los fixtures heredados se conservan sin modificaciones.
6. **ADR-015: ventana mínima.** La generación sucede antes de RunGame; Draw lee sólo textura. Sin avance anual ni estado compartido mutable no hay necesidad de concurrencia. La prueba futura de widgets/crónica/DPI sigue pendiente; no incorporar otra biblioteca UI ni comprometer arquitectura de concurrencia en este bloque.

Fuentes de versiones/contratos: [Go 1.27.2](https://go.dev/dl/), [Ebitengine 2.10.5](https://github.com/hajimehoshi/ebiten/releases/tag/v2.10.5), [Ebitengine 2.10 y requisitos](https://ebitengine.org/en/documents/2.10.html). Los módulos conservan sus licencias originales en la caché Go; no se incorpora código de V8/fdlibm ni se redistribuyen los recursos Tierra.

## Riesgos y siguiente bloque propuesto

Los algoritmos portados pueden diferir numéricamente del HTML. Validar invariantes y replays nativos; investigar cambios antes de ajustar un golden. La reproducibilidad medida no demuestra igualdad para todas las CPUs Windows x64. No se ha validado GPU, DPI o interacción de la ventana en esta entrega.

Propuesta para la siguiente PR: terminar drenaje/ríos, aptitud agrícola/pastoral, biomas, tsetsé, costes de viaje, interpolación meteorológica y enlaces marítimos de genWorld; probar sus dependencias de clima/geografía. Después portar prepEco, capacidad de carga y newHistory con población/pueblos y sus nombres/RNG. Tecnología, estados, guerras y presagios requieren esa base. No sustituir ecología o tecnología por constantes para mostrar una partida aparente. Tierra/importación necesita además revisar la procedencia de los recursos antes de extraerlos.

Guardar/restaurar, eventos estructurados y límites anuales conservan el diseño de Fase 0, sin presentarse como código existente. Nada de este bloque implementa ciclos de Turchin nuevos, comercio ampliado, diplomacia nueva o dinastías nuevas.
