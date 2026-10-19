# Contrato numérico — decisión de producto Windows x64

**Decisión aprobada por el usuario tras la segunda auditoría de Claude:** Asabiya Native es un simulador personal para **Windows x64**. El perfil nativo utiliza inicialmente `math` de Go; la equivalencia bit a bit con JavaScript/V8 **no es un requisito** ni una puerta de entrada a Fase 1. No existe todavía código Go ni se ha demostrado reproducibilidad del motor nativo.

## Alcance de los perfiles

| Perfil | Contrato |
|---|---|
| `native` — producto principal | Go + Ebitengine sobre Windows x64. Preservar la intención y mecanismos históricos del original, RNG controlado, calendario causal, IDs y estabilidad numérica. Aceptar historias distintas del HTML cuando no impliquen errores ni pérdida de invariantes. Reproducibilidad dentro del entorno/versiones fijados, a comprobar durante la implementación; no se promete identidad entre CPUs distintas sin probar. |
| `v06-compat` — referencia diagnóstica | Conservar **sin modificar** el HTML v0.6, sus corpus y hashes; sirven para inspeccionar algoritmos y detectar cambios de comportamiento. No obliga a que los hashes o funciones matemáticas de Go sean iguales a V8, ni requiere desarrollar un segundo motor compatible. |

Se fijarán la versión de Go, dependencias y configuración Windows amd64 al comenzar la implementación. `GOAMD64=v1` es una configuración inicial razonable, pero **no garantiza** por sí sola resultados idénticos en todos los procesadores: algunas funciones de `math`, como `Exp`, pueden escoger una ruta según capacidades de CPU (FMA). Para esta instalación personal bastan verificaciones básicas de determinismo; si el usuario necesita compartir partidas entre equipos Windows diferentes, revisar las rutas numéricas relevantes y probarlas. No copiar aún una implementación alternativa de `Exp` sin necesidad demostrada.

## Qué se preserva del legado

- `hashStr` (UTF-16), Mulberry32, operaciones de 32 bits y semilla/contador RNG.
- Orden del calendario anual, iteración de colecciones, orden de catálogos y redondeos que influyen en decisiones discretas.
- Representación por celda, índices/IDs y centinelas; las diferencias numéricas se analizan si provocan fallos, NaN, poblaciones inválidas, cambios históricos graves o replays inconsistentes.
- Registro de decisiones de port intencionales; los fixtures históricos **nunca** se reescriben para ocultar una diferencia.
- CI rápida obligatoria en Windows x64; diagnóstico Linux opcional y no bloqueante, con resultados estrictos sin cambiar oráculos.

El comportamiento numérico puede alterar eventos y consumo de RNG incluso cuando las diferencias son de un ULP. Por ello no se declara el port «matemáticamente equivalente»: se verificará mediante invariantes, reproducción con semilla y estadísticas/hitos históricos, y se tratarán las divergencias relevantes de forma explícita.

## Evidencia histórica y limitaciones

En la primera auditoría de Claude se observaron discrepancias entre funciones de V8 y Go, además de rutas dependientes de CPU. En Fase 0 también se observó, con Node **24.19.0** y V8 **13.6.233.17-node.51**, una diferencia Windows/Linux de **3 entre 2 273** entradas de `Math.pow` por **1 ULP**. El oráculo histórico de Windows pasó; el diagnóstico estricto Linux falló. El origen preciso no se demostró y no se atribuye sin evidencia a FMA. La evidencia binaria original permanece en `evidence/math-pow.platform-mismatch.node24.json`.

Esta discrepancia **no bloquea la Fase 0 ni la versión nativa Windows x64**. La prueba Linux sigue siendo útil para diagnóstico pero no para la aceptación del producto. Mantener Node y la versión V8 fijados sólo para comprobar el legado y sus golden originales.

## `internal/jsmath`: opción descartada por defecto

La propuesta anterior requería portar las rutas matemáticas de V8 desde `ieee754.cc` y otros builtins, con millones de vectores, análisis FMA, avisos de licencias y equivalencia bit a bit. Esa propuesta era pertinente si el objetivo era replicar estrictamente V8, **pero el usuario retiró dicho requisito**. El directorio `internal/jsmath` queda reservado **sin implementación**; no es dependencia de `internal/sim` ni requisito de inicio de Fase 1.

Si en el futuro se decide implementar una compatibilidad exacta, será una tarea optativa con alcance explícito, pruebas de entrada/salida por bits, licencias de los componentes reutilizados y revisión de rutas reales de V8, incluyendo `hypot` con distintas aridades. No introducir ese trabajo preventivamente.

## Validación mínima futura

Durante Fase 1: verificar que una misma semilla/reglas/versiones en el equipo objetivo reproduzcan la partida; comprobar invariantes de población, estado, guerras, fechas, guardado/restauración y continuidad del RNG; comparar estadísticas e hitos razonables con v0.6, **sin exigir hashes idénticos**. Tests breves y específicos según cada módulo, no campañas matemáticas multiplataforma.
