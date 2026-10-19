# Arquitectura propuesta: Go + Ebitengine

Estado: diseño de Fase 0 pendiente de aprobación; sin código de mecánicas ni dependencias Go instaladas. Se elige una separación por responsabilidades que permita ejecutar y probar la simulación sin ventana, GPU ni Ebitengine.

```text
cmd/asabiya (composición)                 cmd/asabiya-headless (replay / medición)
          |                                           |
internal/presentation/ebiten --> internal/app --> internal/sim
          |                       |                   |
          +--> snapshots de vista |              world / state / systems
                                  +--> internal/rules, internal/replay
internal/sim --> internal/rules + internal/rng
```

Las flechas indican dependencias. `internal/sim`, `internal/rules` e `internal/rng` nunca importan presentación, Ebitengine, reloj real, archivos de configuración ni controles de ventana. El acceso al disco y la validación del documento externo quedan en la composición/carga; el núcleo recibe datos ya validados.

## Contratos propuestos, todavía no implementados

| Operación conceptual | Contrato |
|---|---|
| `NewWorld(WorldSpec, Rules)` | Mundo generado, Tierra o importado con hash de recursos, parámetros y semilla explícitos; devuelve error de validación antes de iniciar. |
| `NewSimulation(World, Rules, HistorySeed)` | Estado y RNG propios de una instancia. No globales compartidos; índices y centinelas compatibles con el legado. |
| `AdvanceYear()` | Una transición anual completa con el orden de `stepG`. No depende de FPS ni reloj; se puede pausar internamente sin publicar estado parcial. |
| `ApplyCommand(Command)` | Orden secuenciada por año y posición dentro de su frontera. Para presagios, completar el año en curso, validar y aplicar como `finishYear`→`castOmen`. Errores no consumen RNG salvo evidencia contraria del legado. |
| `View()` / eventos | Proyección inmutable o copia; cámara, overlays, texto y hover no alteran la simulación. Eventos con año, IDs, tipo, causas y referencias; conservar los registros narrativos del legado. |
| `Save/Restore` futuro | Estado completo, versión de esquema/reglas, mundo, historial de comandos y estado RNG; distinto del historial comprimido del mapa. Pendiente de diseño y aprobación. |

El nombre y la firma Go exactos se definirán en Fase 1 después de revisar las necesidades del oráculo JS. No se publican interfaces ficticias que simulen un port funcional.

## Organización reservada

| Ruta | Responsabilidad futura |
|---|---|
| `cmd/asabiya/` | Arranque de la aplicación nativa y carga de configuración. |
| `cmd/asabiya-headless/` | Ejecución reproducible sin render, exportación y benchmarks. |
| `internal/sim/` | Mundo, estado, sistemas y secuencia anual; estructura por arrays tipados equivalente a la original antes de optimizar. |
| `internal/rng/` | Hash de semillas UTF-16 y Mulberry32 con compatibilidad JS. |
| `internal/rules/` | Definiciones validadas, IDs estables y valores por defecto versionados. |
| `internal/replay/` | Semillas, configuración completa, recursos y comandos ordenados. |
| `internal/app/` | Pausa/velocidad, frontera de comandos, coordinación entre vista y núcleo. |
| `internal/presentation/ebiten/` | `Update`, `Draw`, `Layout`, cámara, mapa y paneles. |
| `data/` | Futuras reglas externas con esquema y hash; no duplicar hoy las tablas originales. |
| `tests/equivalence/` | Futuro comparador Go/JS y fixtures de transición. |
| `benchmarks/` | Escenarios y metodología; mediciones futuras. |
| `tools/` | Verificación de referencia y caracterización del JS original. |

Cada carpeta reservada contiene un README de alcance, sin implementación. `go.mod`, versión de Go y versión exacta de Ebitengine se fijarán al aprobar Fase 1 y comprobar el entorno Windows; no se afirma una compilación nativa en esta fase.

## Reglas dirigidas por datos

Separar datos (`PDEF`, `CDEF`, `TECH`, `ERAS`, `OMENS`, `CATA`, estilos y semillas históricas) de los algoritmos. La futura extracción conservará orden, IDs, valores, prerequisitos, campos opcionales y distinción entre ausente/cero/falso. Mantener alias de los arrays tecnológicos. Los números JSON se validarán explícitamente; rechazar IDs duplicados, dependencias inexistentes, ciclos tecnológicos no permitidos y rangos inválidos antes de crear el mundo.

El catálogo no convierte fórmulas causales en scripts arbitrarios. Primero extraer tablas sin cambiar comportamiento; cualquier ajuste de balance será una PR distinta después de lograr equivalencia. Guardar versión y SHA-256 de reglas efectivas y recursos en cada replay. El inventario de Fase 0 es evidencia, no un segundo catálogo operativo.

## Integración de render

Ebitengine define `Update`, `Draw` y `Layout`; la documentación oficial separa actualización por ticks de dibujo por frames. Propuesta: `Update` procesa entradas y un presupuesto de trabajo determinista; `Draw` sólo consume una vista completa publicada. La velocidad decide cuántos años se solicitan, no el tamaño de una transición anual. Si se reproduce el generador por fragmentos, conservar su orden y aceptar comandos en fronteras definidas. Evitar concurrencia de la simulación inicialmente; si se añade después, un único propietario del estado y entrega de snapshots inmutables.

La resolución 400×200 del mundo no crece con la ventana. Escalar cámara y texturas, envolviendo longitud como el original. Los modos prioritarios son mapa/terreno, pueblos y estados; guerras y presagios se representan con eventos y selección de provincia. El algoritmo causal completo sigue existiendo aunque falte una vista secundaria.

Fuentes de diseño consultadas: [Ebitengine: Game, Update, Draw, Layout](https://ebitengine.org/en/documents/cheatsheet.html), [especificación Go: mapas y aritmética](https://go.dev/ref/spec). La selección de módulos y versiones sigue pendiente.
