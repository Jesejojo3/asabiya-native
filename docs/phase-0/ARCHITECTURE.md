# Arquitectura propuesta: Go + Ebitengine

Estado: diseño de Fase 0 aprobado con condición documental en la segunda revisión estática de Claude; sin código de mecánicas ni dependencias Go instaladas. Uso personal exclusivo Windows x64; merge/tag y comienzo de Fase 1 requieren autorización del usuario. El contrato numérico corregido está en [NUMERIC_COMPATIBILITY.md](NUMERIC_COMPATIBILITY.md). Se mantienen perfiles permanentes `v06-compat` y `native`, sin modificar el HTML.

```text
cmd/asabiya (composición)                 cmd/asabiya-headless (replay / medición)
          |                                           |
internal/presentation/ebiten --> internal/app --> internal/sim
          |                       |                   |
          +--> snapshots de vista |              world / state / systems
                                  +--> internal/rules, internal/replay
internal/sim --> internal/rules + internal/rng + math (Go estándar, perfil native)
internal/app --> internal/save + internal/history + internal/replay
internal/presentation/ebiten --> internal/narrative
```

Las flechas indican dependencias. `internal/sim`, `internal/rules` e `internal/rng` nunca importan presentación, Ebitengine, reloj real, archivos de configuración ni controles de ventana. El acceso al disco y la validación del documento externo quedan en la composición/carga; el núcleo recibe datos ya validados.

## Contratos propuestos, todavía no implementados

| Operación conceptual | Contrato |
|---|---|
| `NewWorld(WorldSpec, Rules)` | Mundo generado, Tierra o importado con hash de recursos, parámetros y semilla explícitos; devuelve error de validación antes de iniciar. |
| `NewSimulation(World, Rules, HistorySeed)` | Estado y RNG propios; Rules es la configuración efectiva inicial, modificable sólo por comandos versionados en fronteras. |
| `AdvanceYear()` | Una transición completa y atómica, sin comandos, guardados ni publicación a mitad del año; orden de stepG sin reintroducir sus yield como máquina de estados. |
| `ApplyCommand(Command)` | Presagios, cambios de reglas, defaults y sandbox en frontera completa; orden/rechazos y reglas efectivas en replay. Diferencia intencional frente a UI heredada documentada en COMMANDS_AND_PROFILES.md. |
| `View()` / eventos | Vistas inmutables y eventos estructurados con IDs; narrativa en capa separada. Nombres generados siguen siendo datos comparables. Contrato exacto en EVENTS_AND_SAVE.md. |
| `Save/Restore` propuesto | Esquema mínimo v1 de contenedor, arrays LE, IDs, orden, reglas, RNG semilla/contador, cola y eventos; módulos save/history/replay separados. Sin implementación. |

El nombre y la firma Go exactos se definirán en Fase 1 después de revisar las necesidades del oráculo JS. No se publican interfaces ficticias que simulen un port funcional.

## Organización reservada

| Ruta | Responsabilidad futura |
|---|---|
| `cmd/asabiya/` | Arranque de la aplicación nativa y carga de configuración. |
| `cmd/asabiya-headless/` | Ejecución reproducible sin render, exportación y benchmarks. |
| `internal/sim/` | Mundo, estado, sistemas y secuencia anual; estructura por arrays tipados equivalente a la original antes de optimizar. |
| `internal/rng/` | Hash de semillas UTF-16 y Mulberry32 con compatibilidad JS. |
| `internal/jsmath/` | Reserva opcional, sin implementación ni dependencia; equivalencia V8 exacta descartada como requisito del perfil native. |
| `internal/rules/` | Definiciones validadas, IDs estables y valores por defecto versionados. |
| `internal/replay/` | Semillas, configuración completa, recursos y comandos ordenados. |
| `internal/save/` | Contenedor versionado de partida completa y validación de restauración. |
| `internal/history/` | Historial visual comprimido del mapa, separado de guardados reanudables. |
| `internal/narrative/` | Plantillas/localización, formato numérico de texto y presentación de eventos; sin RNG histórico. |
| `internal/app/` | Pausa/velocidad, frontera de comandos, coordinación entre vista y núcleo. |
| `internal/presentation/ebiten/` | `Update`, `Draw`, `Layout`, cámara, mapa y paneles. |
| `data/` | Futuras reglas externas con esquema y hash; no duplicar hoy las tablas originales. |
| `tests/equivalence/` | Futuro comparador Go/JS y fixtures de transición. |
| `benchmarks/` | Escenarios y metodología; mediciones futuras. |
| `tools/` | Verificación de referencia y caracterización del JS original. |

Cada carpeta reservada contiene un README de alcance, sin implementación. Un paquete sim al principio, archivos por sistema según [SYSTEM_CALENDAR.md](SYSTEM_CALENDAR.md); no convertir cada sistema en paquete independiente prematuramente. `go.mod`, Go y Ebitengine se fijarán al aprobar la prueba técnica y comprobar Windows. No hay compilación nativa validada.

## Reglas dirigidas por datos

Separar datos (`PDEF`, `CDEF`, `TECH`, `ERAS`, `OMENS`, `CATA`, estilos y semillas históricas) de los algoritmos. La futura extracción conservará orden, IDs, valores, prerequisitos, campos opcionales y distinción entre ausente/cero/falso. Mantener alias de los arrays tecnológicos. Los números JSON se validarán explícitamente; rechazar IDs duplicados, dependencias inexistentes, ciclos tecnológicos no permitidos y rangos inválidos antes de crear el mundo.

El catálogo no convierte fórmulas causales en scripts arbitrarios. Primero extraer tablas sin cambiar comportamiento; cualquier ajuste de balance se documentará separadamente para distinguir port y evolución nativa; no se exige equivalencia bit a bit con V8. Guardar versión y SHA-256 de reglas efectivas y recursos en cada replay. El inventario de Fase 0 es evidencia, no un segundo catálogo operativo.

## Integración de render

Ebitengine define `Update`, `Draw` y `Layout`. La unidad causal será un año atómico. Evaluar dos adaptadores: ejecución secuencial acotada por años completos en Update, o goroutine propietaria que recibe comandos y publica vistas inmutables. El primero simplifica pruebas pero puede bloquear UI con años largos; el segundo evita esa espera a costa de cola, ciclo de vida, memoria y pruebas de carrera. No imponer concurrencia por anticipado ni dividir el año en una máquina de estados. La elección se hará con la prueba técnica de latencia y race detector propuesta en ADR-0002. Draw nunca consume ni modifica el estado vivo.

UI: candidato inicial [ebitenui](https://github.com/ebitenui/ebitenui), comparado con una implementación inmediata mínima en una prueba futura de 4–8 horas: textura del mapa, crónica enlazada larga, scroll/selección, 40 sliders de reglas y texto con acentos. Medir legibilidad/latencia/memoria en Windows amd64, ventanas/DPI y coste de traducir enlaces/plantillas. Revisar licencia y fijar versiones al elegir. Esta entrega no instala UI ni promete fechas de producto; ver ADR-0002.

La resolución 400×200 del mundo no crece con la ventana. Escalar cámara y texturas, envolviendo longitud como el original. Los modos prioritarios son mapa/terreno, pueblos y estados; guerras y presagios se representan con eventos y selección de provincia. El algoritmo causal completo sigue existiendo aunque falte una vista secundaria.

Fuentes de diseño consultadas: [Ebitengine: Game, Update, Draw, Layout](https://ebitengine.org/en/documents/cheatsheet.html), [especificación Go: mapas y aritmética](https://go.dev/ref/spec). La selección de módulos y versiones sigue pendiente.
