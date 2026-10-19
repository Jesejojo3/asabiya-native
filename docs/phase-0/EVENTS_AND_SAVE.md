# IDs, eventos, historial y guardado: diseño mínimo

Propuesta para segunda aprobación; **sin implementación de persistencia o mecánicas**. El HTML no guarda partidas completas: no hay oráculo para Save/Restore. Las pruebas futuras de round-trip serán invariantes del formato nuevo, además de replays compatibles.

## Identidad y referencias

IDs estables, tipados por clase y nunca reutilizados dentro de una ejecución. Las entidades legadas conservan sus índices y centinelas al portar: estado 0 = sin estado; pueblos/religión −1 = ninguno donde el original lo usa. No cambiar a uint indiscriminadamente. Celda = índice original `y*400+x`, separado del ID de entidad. Cada clase tiene un contador de asignación monotónico y registros de entidades muertas (tombstones) cuando se necesitan referencias históricas.

Entidades: pueblos/familias/lenguas, estados, gobernantes/dinastías, figuras, religiones, guerras, ciudades, rutas, migraciones, epidemias, presagios y cataclismos. Tratados y otras entidades futuras se agregan sólo a versiones nuevas de `native`; no se inventa un sistema operativo en Fase 0. Relaciones por `(tipo, ID)`, nunca direcciones de memoria serializadas. El núcleo puede usar índices internos como optimización; los punteros Go, si los hubiera, no son identidad persistente ni relaciones autoritativas. Mantener identidad de listas compartidas y alias de arrays tecnológicos mediante un único campo/almacén y referencias declaradas.

## Eventos y texto: decisión explícita de equivalencia

`chron()` (830) guarda texto inglés y `why`; `fy` (389) usa `toLocaleString('en-US')`. No se supone que Go reproduzca su redondeo/formato ICU. Los nombres generados de entidades, idiomas y lugares **sí** son datos comparables; conservar sus algoritmos, cadenas y sorteos. El texto narrativo localizado es presentación.

Contrato propuesto `equivalence/v1`: comparar exactamente estado causal, nombres generados, calendario, RNG y eventos estructurados ordenados. Separar frases narrativas de la comparación Go/JS. Esta es una delimitación deliberada del objetivo estricto, pendiente de segunda aprobación; no afirmar equivalencia textual de toda la interfaz.

Los hashes históricos del smoke siguen incluyendo S completo y texto: se conservan como regresión del oráculo JS, sin retirar campos para hacerlos pasar. Un comparador Go futuro usará una proyección nueva, versionada y revisada; nunca reutilizar un hash diferente bajo el mismo identificador del fixture histórico.

Evento propuesto: `{schemaVersion, eventID, sequence, year, phase, kind, cellID, subjectRefs, causeRefs, payload}`. Payload tipado por clase, números con unidad y precisión declaradas; referencias a IDs, no etiquetas traducidas. Un `templateKey` y `templateVersion` opcionales residen en `internal/narrative`, que no modifica estado ni consume RNG histórico.

El adaptador original puede capturar tipo/año/celda/refs al envolver `chron`; **no contiene todos los campos cuantitativos ni causas estructuradas** que hoy se incrustan en frases. No extraerlos con regex y presentarlos como causalidad demostrada. Antes del port de cada sistema, especificar su esquema de eventos, asociarlo al sitio de emisión original y capturar entradas/salidas observables por un adaptador revisado. Hasta completar esa cobertura, la equivalencia estructurada del sistema sigue pendiente. `legacyText` y `legacyWhy` pueden conservarse como evidencia diagnóstica sin intervenir en reglas.

Los eventos que nuevas funciones de `native` consuman se entregan en la fase publicada del calendario, con secuencia estable; no callbacks que muten un sistema anterior o recorrido dependiente de mapas. En `v06-compat` no reemplazar llamadas directas del legado por una cola nueva si cambia el orden causal.

## Save/Restore v1 propuesto

Módulo `internal/save` separado de `internal/history` (vistas de mapa comprimidas) y de `internal/replay` (comandos/identidad de ejecución). Guardado sólo en frontera completa; nunca a mitad de `AdvanceYear()`.

Formato binario de contenedor por secciones: magic `ASABIYA`, versión de contenedor, versión de esquema, longitud y SHA-256 de cada sección. Manifest JSON UTF-8 con tamaño acotado; tablas como listas ordenadas, arrays tipados por bloques little-endian. Formato documental, no código implementado.

| Sección | Contenido obligatorio |
|---|---|
| Identidad | Perfil, versión del contrato, reglas/calendario/backend numérico y sus hashes; versión del motor y toolchain/plataforma validados. |
| Mundo | Parámetros, dimensiones, semillas como cadenas, recursos por hash y capas necesarias; permitir recursos externos sólo si el cargador exige el hash y falla si faltan. |
| Estado | Año completo, arrays por celda, entidades, contadores de IDs, alias tecnológicos, orden de Map/Set y propiedades relevantes; centinelas y bits float explícitos. |
| RNG | Por flujo: algoritmo/versión, semilla uint32 original y contador uint64 de llamadas; generadores derivados y sus claves. Estado = `(seed + calls*0x6D2B79F5) mod 2^32` para Mulberry32. |
| Entradas/eventos | Comandos aceptados/rechazados, cola futura ordenada, siguiente secuencia, eventos autoritativos y cursores. |
| Historial | Snapshots/deltas de mapa y políticas de retención del legado, distintos de la partida completa. |

Un contador JS de llamadas se limita a enteros seguros; los fixtures actuales están muy por debajo. El formato guarda uint64 sin convertirlo a Number; para el estado Mulberry sólo se requieren los 32 bits bajos del producto. Validar tipos, longitudes máximas, IDs, referencias y hashes antes de publicar una partida restaurada. Rechazar versiones/perfiles/backend incompatibles con mensaje explícito; las migraciones serán puras, versionadas y probadas sobre copias. Nunca reescribir silenciosamente la partida fuente.

Pruebas futuras exigidas: guardar/cargar conserva bits, identidad y orden; continuar N años produce mismos eventos y RNG que ejecución sin guardar; reconstrucción en otro proceso; referencia ausente/corrupta, versión desconocida y archivo truncado fallan; ninguna captura concurrente de estado a medio año. Windows amd64 es objetivo inicial propuesto, no persistencia ya validada.
