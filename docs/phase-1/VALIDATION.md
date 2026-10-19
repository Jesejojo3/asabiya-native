# Validación de Fase 1

Objetivo comprobado: primer bloque del generador y sus ejecutables en Windows amd64. Ningún resultado demuestra equivalencia del motor Go completo con v0.6.

## Entorno local y resultados

Windows amd64, Intel Core i5-1340P, Go **1.27.2**, Ebitengine **2.10.5**, `GOAMD64=v1`, `CGO_ENABLED=0`, `GOTOOLCHAIN=local`.

La distribución oficial `go1.27.2.windows-amd64.zip` se verificó antes de ejecutar: SHA-256 `1314008898bd40df77af4b014f777f08873dbdfbcd3d92308728ee03304fe04f`. La descarga inicial incompleta fue descartada por no coincidir; se usó la descarga íntegra verificada.

| Comprobación | Resultado local |
|---|---|
| Verificador de referencia existente | OK, 1 553 001 bytes, SHA-256 y Git blob originales |
| go test ./... | Pasa RNG, núcleo y ejecutable headless; los paquetes de ventana compilan pero no tienen prueba interactiva |
| go vet ./... | Pasa |
| Build headless y Ebitengine | Dos .exe Windows amd64, sin compilador C, trimpath y buildvcs=false |
| Procesos headless independientes | Reportes idénticos para Asabiya / historia 1, mapa default y consulta 200,100 |
| Golden nativo nuevo | Coincide con `tests/native/world-v1.windows-go1.27.2.json`; ningún golden legado fue sustituido |
| PNG | Exportado y examinado visualmente: imagen 400×200 con océano/terreno; no es prueba de la ventana Ebitengine |
| Benchmark pequeño | 3 iteraciones, 14 148 567 ns/op, 1 047 194 B/op, 34 allocs/op, mapa 48×24, detalle 4 |
| Generación completa + resumen + PNG | Una medición de pared: ~1,75 s; no es benchmark anual ni comparación de velocidad contra JS |

La referencia nativa para Asabiya contiene 80 000 celdas, 26 124 terrestres, 3 073 costeras y 61 masas terrestres. RNG de mundo: semilla 4 037 141 429, **215 644 llamadas**. SHA-256 del mundo: `6f763794f922ed72f6ccfca992338ef5a731e20d0dff096c8c40ffbb385dcc22`. Historia 1: semilla 58 464 154, cero llamadas; sesión **sin población**.

## Qué prueban los tests

- Hashes de cadena vacía, ASCII, acento y emoji; 32 sorteos enteros y sus conversiones Float64. Vectores evaluados directamente desde las funciones del HTML intacto (líneas 383–384), no desde Go. Prueban ese contrato entero, no las funciones trascendentes del generador.
- Restauración de RNG tras 100 003 llamadas y posición superior a 2^32; continuación idéntica y contador uint64 conservado.
- Misma configuración/semilla produce misma huella y consumo; otra semilla cambia el mundo. El escenario pequeño exige 5 116 sorteos de generación.
- Celdas finitas, rangos de rugosidad/lluvia/amplitud/área, signo de elevación, vecinos recíprocos, costura longitudinal, límites polares, costa junto al agua, asignación/tamaño de componentes y área superficial aproximada.
- Consultas inválidas fallan y las vistas por valor no permiten mutar los arrays privados. Configuración inválida y malla climática demasiado pequeña se rechazan.
- Separación de semilla histórica; sesión inicial sin población. CLI exporta JSON y PNG válidos, verifica consulta y errores de entrada.

## CI y referencias

`native.yml` usa Windows 2022, Go exacto de .go-version y acciones fijadas por SHA. Verifica módulos, vet, tests, builds, ejecución de **dos procesos** y comparación con el golden nativo registrado. Publica ambos ejecutables y reportes/PNG para revisión, con permisos de lectura. El helper temporal con escritura para el tag se elimina del árbol final.

Un fallo de golden en otra CPU no autoriza actualizarlo: investigar primero diferencias de math/toolchain/implementación y documentar el alcance real. Que dos procesos coincidan sólo muestra determinismo local; el golden añade detección de regresiones de referencia. El workflow de legado y sus oráculos/hashes originales no se modifican.

## Pendiente

- Abrir y probar interactivamente la ventana en el equipo del usuario: GPU/controladores, resize, DPI, Esc y distribución del ejecutable.
- Port del resto de genWorld, prepEco y newHistory; invariantes poblacionales/ecológicas, hitos de estados y guerras y pruebas del calendario anual, una vez implementados.
- Guardado/restauración completo, replays de comandos, eventos/narrativa, pruebas de largas partidas y benchmarks de años. RNG Restore no equivale a Save/Restore de una partida.
- Verificación entre varias CPUs Windows x64; no se afirma soporte validado en arm64, Linux o macOS.
- Revisión independiente de esta PR por Claude, con entrega manual del paquete por el usuario. No se ha solicitado ni recibido automáticamente una auditoría.
