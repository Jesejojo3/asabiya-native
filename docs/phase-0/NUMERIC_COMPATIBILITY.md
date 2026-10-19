# C1 — contrato numérico y viabilidad de internal/jsmath

Estado: decisión de diseño propuesta para segunda revisión; **no hay port matemático Go ni equivalencia Go/V8 demostrada**. C1 se acepta como defecto del diseño anterior. La corrección de Fase 0 es un contrato verificable y un oráculo reforzado; implementar `jsmath` será una prueba técnica matemática previa a portar mecánicas, sólo cuando se autorice esa fase.

## Oráculo y perfiles

Oráculo fijado: Node **24.19.0**, V8 **13.6.233.17-node.51**, x64, little-endian. `.node-version` y `tools/oracle-runtime.json` deben coincidir. El HTML y sus pruebas originales no cambian. Las mediciones Linux/Node 22.22.0/Go 1.24.7 del auditor son evidencia recibida, no ejecuciones Go repetidas por Codex en esta corrección.

| Perfil | Contrato y límites |
|---|---|
| `v06-compat` permanente | Reglas, IDs, algoritmos, calendario, colecciones y flujo RNG originales. Objetivo estricto verificable para estado causal, nombres generados y eventos estructurados; narrativa localizada fuera de ese contrato, decisión explícita en EVENTS_AND_SAVE.md. Ningún desacuerdo numérico que cambie RNG, IDs o eventos se acepta por tolerancia. Sólo se comparan fixtures sin cambios a mitad de año. |
| `native` futuro | Evolución con reglas, catálogo, calendario, formato de guardado y contrato numérico versionados. Reproducible dentro de la combinación publicada de perfil/reglas/backend/plataforma validada. No se afirma que reproduzca v0.6 ni que todos los equipos compartan resultados hasta validarlo. |

Cambiar backend matemático, orden, frontera de comandos o algoritmo exige versión de contrato y nuevos fixtures separados. `native` nunca sobrescribe valores de referencia de `v06-compat`.

## Por qué math de Go no basta

El informe de Claude presenta diferencias de bits en nueve funciones, un ejemplo concreto de `sin`, rutas dependientes de CPU y diferencias de compilación FMA. Se acepta el riesgo demostrado de bibliotecas distintas, pero no se extrapolan sus porcentajes a otras versiones o CPUs. La especificación Go permite fusión y especifica que una conversión explícita impone el redondeo correspondiente: [operadores flotantes](https://go.dev/ref/spec#Floating_point_operators). Elegir `GOAMD64=v1` por sí solo no demuestra ausencia de rutas matemáticas seleccionadas por CPU.

Tampoco se adopta automáticamente la lista de funciones «exactas» propuesta por el auditor: `Max`/`Min` necesitan comprobar NaN y signo de cero con semántica JS; `sqrt`, floor, abs y conversiones tienen casos límite. Igualdad observada en muestras de amd64 no certifica arm64 ni todo binary64.

## Ruta propuesta para jsmath

Port en Go puro, sin cgo, ensamblador ni despacho por capacidades de CPU, basado en **la fuente incluida en el Node fijado**, no en el HEAD actual de V8 ni en un fdlibm genérico. Cubrir `sin`, `cos`, `exp`, `log`, `log10`, `pow` y `**`, `atan2`, `asin`, `acos`; auditar también redondeo, min/max, signos de cero y constantes.

`hypot` requiere una corrección a la propuesta de Claude: no basta portar `ieee754.cc`. La [implementación MathHypot de V8 en math.tq](https://raw.githubusercontent.com/nodejs/node/v24.19.0/deps/v8/src/builtins/math.tq) tiene rutas para dos y tres argumentos y una suma compensada para más argumentos. El core usa normas de varias componentes. Se debe reproducir la ruta y aridad efectivas, los casos especiales y el orden de sumas.

La [fuente ieee754.cc fijada](https://raw.githubusercontent.com/nodejs/node/v24.19.0/deps/v8/src/base/ieee754.cc) contiene la licencia de Sun/fdlibm y modificaciones de Google; [LICENSE de V8](https://raw.githubusercontent.com/nodejs/node/v24.19.0/deps/v8/LICENSE) exige conservar avisos, condiciones y descargos, también al distribuir binarios. La viabilidad técnica es favorable, con coste alto: reducción de argumentos, constantes por bits, ramas de casos especiales y rutas del JIT deben trazarse. Antes de copiar código, guardar fuentes exactas con hash, avisos completos de cada archivo y un registro de modificaciones en `THIRD_PARTY_NOTICES`; comprobar dependencias adicionales. No se incorpora código de terceros en esta entrega ni se adjudica licencia al resto del juego.

## Validación obligatoria antes de afirmar compatibilidad

1. Rastrear llamadas del core hasta las rutas efectivas de V8 de la versión fijada, incluidos builtins, `**`, aridades de hypot y optimizaciones. Portar con constantes de bits y operaciones en el mismo orden.
2. Corpus dirigido de ceros con signo, subnormales, extremos, infinito, NaN por clasificación, fronteras de ramas, potencias enteras/no enteras y rangos reales del motor; además millones de vectores deterministas y trazas de argumentos reales. Los vectores finitos e infinitos se comparan por bits; NaN por clase, salvo que un formato necesite preservar payload.
3. El programa Go futuro recibirá los **mismos bits de entrada** emitidos por `tools/math-vectors.mjs --vectors-out corpus.jsonl`; no regenerará entradas usando sus propias funciones matemáticas. Comparar cada resultado y detener en la primera diferencia. Los resúmenes SHA no sustituyen ese comparador por vector.
4. Cero diferencias en corpus rápido y extenso, y en fixtures de mundo/historia por etapas. Una muestra finita aprobada no prueba todo binary64; la promesa se limita al conjunto de plataformas y versiones ensayadas y al contrato publicado.
5. Analizador Go futuro sobre AST/tipos: prohibir `math` numérico no aprobado en `internal/sim` y `internal/jsmath`, alias de importación y llamadas indirectas incluidos; permitir explícitamente sólo operaciones revisadas. Prohibir `math.FMA`. No se añade ahora un linter que pueda pasar por ausencia de código Go.
6. Impedir fusión en todas las fórmulas relevantes mediante barreras de redondeo explícitas, preservando fronteras float32/float64. Inspeccionar ensamblador del código de producción y dependencias numéricas para instrucciones FMA, con una lista revisada para cada arquitectura; búsqueda textual sola no certifica todo el binario ni rutas no ejecutadas.

## Plataformas, coste y puerta de salida

Objetivo inicial propuesto: **Windows amd64**, `GOAMD64=v1`, backend puro y toolchain Go fijado al aprobar la prueba técnica. Linux amd64 sirve como segundo entorno de oráculo. ARM64 y otras CPU/OS son objetivos posteriores, sin validación atribuida en esta fase. Probar al menos rutas con FMA disponible y deshabilitada/máquina sin FMA antes de prometer replays intercambiables; una compilación cruzada no equivale a ejecutar.

El backend puro podría perder rendimiento frente al ensamblador de Go; no se asigna un porcentaje inventado. Medir por función, generación de mundo y año completo, separando hashing y render. No se sustituye por aproximaciones para alcanzar FPS. Una alternativa con V8 embebido conservaría un runtime extranjero y distribución compleja; cgo/fdlibm tampoco garantiza por sí solo la semántica V8. Se descartan como ruta por defecto, conservándolas como alternativas a revisar si el port puro falla.

**Puerta numérica pendiente:** revisión humana del contrato, prueba técnica jsmath y sus licencias, vectores Go/V8 sin diferencias dentro del ámbito publicado, controles FMA y fixtures causales aprobados. Sin ello no se declara resuelto el objetivo de equivalencia estricta ni se inicia automáticamente el port de mecánicas.
