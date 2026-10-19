# Perfiles y comandos en fronteras anuales

Decisión propuesta: `AdvanceYear()` es atómico respecto a comandos, snapshots publicados y guardados. No habrá cambios de reglas, sandbox ni presagios observables a mitad de año en la API nativa. Esto introduce una diferencia deliberada respecto a la UI del HTML y acota el dominio de equivalencia; no modifica el HTML.

## Evidencia e intención

`buildRules` escribe `P[k]` inmediatamente (2974) y restaura defaults inmediatamente (2975). Sandbox escribe `P.sandbox` y ajusta `S.favor` inmediatamente (3135). El generador puede estar suspendido y leer después valores nuevos. Presagios sí llaman `finishYear` antes de `castOmen` (3053–3055). CL configura generación del mundo; distinguir esos parámetros de reglas de la historia. La crónica añadida por UI a 1800 (3165) tampoco se traslada como escritura arbitraria al estado.

## Protocolo propuesto

Cada comando lleva `schemaVersion`, `profile`, `targetYear`, `sequence`, `kind`, payload y hash de reglas esperado. El propietario del estado acepta el lote sólo en el estado completo del año Y, antes de iniciar Y+1. Orden total por `(targetYear, sequence)`; rechazar secuencias repetidas, comandos atrasados, hash inesperado y campos inválidos. Registrar en el replay comandos aceptados y resultados/rechazos; un rechazo no consume RNG. Comandos simultáneos se ordenan al recibirlos y ese orden queda grabado, no se reconstruye del reloj.

| Comando | Efecto en la frontera completa de Y |
|---|---|
| `CastOmen` | Validar tipo/provincia/favor y aplicar efectos con fecha Y; consumo RNG y resultado del legado. |
| `ChangeRules` | Parche validado o restauración de defaults como lote; versión/hash efectivos nuevos. Un solo estado consistente del lote antes de Y+1. `Rules` es estado efectivo mutable por comandos, no sólo valor de construcción. |
| `SetSandbox` | Booleano; activar fija favor a 9; desactivar recorta a 5 si era mayor, como la acción original. No ejecutar esa acción si no llegó un comando explícito. |
| `RebuildWorld` / `NewHistory` | Operación de sesión explícita que crea una nueva ejecución y nuevo manifiesto. Parámetros marcados de nuevo mundo no alteran retroactivamente el mundo existente. |
| `Save` | Capturar sólo tras aplicar el lote y antes de empezar Y+1; incluir la cola futura y su siguiente secuencia. |

`ChangeRules` divide los campos por semántica de uso observada: los consumidos por pasos anuales cambian en frontera; `landFrac`, focos/pueblos iniciales y año inicial se almacenan como configuración de la próxima ejecución, sin regeneración oculta. La validación de campos y sus categorías debe derivarse del catálogo y probarse; el marcador de UI no sustituye el análisis de lectura de cada parámetro.

En `v06-compat`, los fixtures estrictos usan reglas constantes o comandos en fronteras conocidas. La UI heredada con un cambio dentro de un `yield` queda **fuera** de ese contrato de entrada. No se llama a esta diferencia un error corregido del HTML. En `native`, la misma frontera es el contrato inicial; cualquier semántica nueva versiona el perfil.

El aviso de límite del modelo a 1800 es una notificación de presentación/sesión. El core conserva su capacidad de avanzar más años si se pide. El aviso inglés original sigue en el oráculo de UI, pero no se inyecta en el estado causal nativo ni se confunde con un evento histórico.

## RNG y calendario para nuevas funciones

`v06-compat` conserva el flujo histórico único y los RNG derivados que ya existen, con semilla y contador. No añadir un sorteo por traducción, hover, textura, telemetría o guardado.

`native` futuro separa nuevos sistemas mediante flujos derivados de una codificación binaria versionada de `(seed, namespaceSistema, añoConSigno, tipoEntidad, ID, propósito, versiónAlgoritmo)`, y contador local si se necesitan varios sorteos. No concatenar cadenas ambiguas ni depender del orden de mapas/hilos. Fijar hash/generador y vectores antes de implementar; no se elige ahora un algoritmo arbitrario sin revisión. Sistemas heredados mantienen su flujo existente hasta una decisión de migración explícita. Un evento de guerra puede producir un futuro evento de refugiados en una fase conocida; no modificar la fase origen ni desplazar sus sorteos.

Todo sistema nuevo requiere namespace, fase y cadencia, dependencias, contrato numérico, reglas y fixtures propios. Cambiar la cadencia de `poolPass` o `caravanPass` exige `native/calendar-v2` u otra versión nombrada, no un arreglo silencioso de `v06-compat`.
