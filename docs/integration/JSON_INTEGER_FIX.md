# Corrección r3: enteros JSON entre Godot y Go

## Causa y alcance

El usuario observó una pantalla negra con `json: cannot unmarshal number 4.0 into Go struct field .world.detail of type int`. La configuración leída por Godot desde JSON contiene números flotantes; `JSON.stringify()` los vuelve a escribir como `400.0`, `200.0` y `4.0`. El decoder estándar de Go exige escritura entera para sus campos `int`.

La solución se aplica exclusivamente a peticiones de `asabiya/local-v1`, tanto al sobre `Request` como a `decodePayload`. No cambia `sim.WorldConfig`, comandos del motor, archivos de replay/guardado, mecánicas, interfaz ni validadores del núcleo. No hay cambios al HTML ni a los golden anteriores.

## Contrato numérico

- Se acepta un número decimal o exponencial si su valor decimal exacto es entero y cabe en el tipo Go de destino: por ejemplo `4.0`, `40e-1`, `400.0`, `200.0` y `-9000.0`.
- Se analiza la escritura decimal sin convertir primero a `float64`. `4.5`, `4.0000000000000001` y `9007199254740992.5` siguen siendo fracciones y se rechazan para campos enteros. No se truncan ni redondean.
- La normalización produce como máximo 20 dígitos, suficientes para los tipos Go enteros. Exponentes enormes no ocasionan reservas proporcionales a su valor. Las cantidades mayores permanecen intactas y el decoder rechaza su uso como enteros.
- `encoding/json` sigue imponiendo rangos y signos: `int` de Windows x64 e `int64`, `uint64` para sesión/secuencia e `int32` para `CellID`. Un valor representable, pero inválido para el mundo, se rechaza después por el mismo validador del motor: dimensiones, detalle y fracción de tierra conservan sus límites.
- Se conservan las cadenas, escapes, orden y miembros repetidos del JSON; no se reconstruyen objetos mediante mapas ni se convierten cadenas numéricas a números. Se conserva el signo del cero flotante. Los campos reales de clima, reglas y fracción de tierra conservan su valor; no se exige que sean enteros.
- Los payloads siguen rechazando campos desconocidos; se exige un único valor JSON válido. `advance` sigue representando un año completo: no acepta un campo `years` ni un lote implícito.
- La exactitud se refiere al número recibido. Si un cliente ya redondeó un valor antes de serializarlo, el servidor no puede reconstruirlo. Godot emplea números flotantes al leer JSON; no se afirma un round trip arbitrario de IDs de 64 bits por ese cliente. Los IDs actuales son pequeños. Un futuro contrato que necesite contadores mayores que el rango exacto del cliente deberá representarlos como texto o acordar otro formato.

Campos revisados: `world.width/height/detail`; sobre `session`; comando `sequence/targetYear/cell`; consultas provinciales `id` (`CellID`), entidades `id` (`int`) y capas históricas `year`; metadatos `source.assets[].bytes`. Los demás campos numéricos de entrada son reales. Las respuestas de Go siguen serializando sus enteros como números JSON enteros.

## Pruebas específicas y reproducción

Entorno ejecutado: Windows x64, Go 1.27.2 y Godot 4.7.2 stable official ed1daf0bf. No se afirma validación en otras plataformas ni GPUs.

1. `client/godot/tests/protocol_integer_fixture.gd` utiliza `JSON.parse_string()` y `JSON.stringify()` reales de Godot para escribir seis peticiones en `internal/interop/testdata/godot-integer-requests.json`, y comprueba su round trip. No carga escenas ni el juego.
2. `TestProtocolGodotSerializationFixture` deserializa esas peticiones en sus tipos reales, conserva valores decimales de clima/reglas y comprueba la serialización del sobre. La configuración completa 400×200, detalle 4 se deserializa en esta prueba.
3. Las pruebas numéricas cubren notación exponencial, límites signed/unsigned, enteros mayores que 2^53, fracciones que redondearían a enteros en float64, desbordamientos, cadenas, campos desconocidos, signo de cero, floats sin cambios y exponentes extremos.
4. `TestProtocolGodotIntegersOnConnection` pasa por `serveConnection` con una conexión `net.Pipe` y líneas JSON reales. Genera un mundo pequeño 24×16, detalle 4, inicia historia, consulta provincias, rechaza argumentos inválidos sin modificar estado/sesión, aplica un comando con enteros decimales y avanza exactamente un año. Entidades/capas inexistentes devuelven `not_found`, no errores de deserialización. No es una validación gráfica ni una partida extensa.
5. Se conservan y ejecutan las regresiones de sesión/pausa/sin lotes y rechazo de escucha fuera de loopback.

Comandos reproducibles desde la raíz del repositorio (con las versiones fijadas en PATH):

```powershell
godot --headless --path client/godot --script res://tests/protocol_integer_fixture.gd -- --output "$((Get-Location).Path)/internal/interop/testdata/godot-integer-requests.json"
go test ./internal/interop -run '^TestProtocol(ExactIntegers|NumberAdaptationPreservesOtherJSON|IntegerFieldRejections|GodotSerializationFixture|GodotIntegersOnConnection|RefusesNonLoopbackWithoutAccepting|SessionBoundariesAndNoHiddenBatch)$' -count=1 -v
```

Resultado: seis fixtures generados y round trip Godot correcto; las siete pruebas Go seleccionadas pasan. El paquete incluye los logs específicos y los de compilación/exportación. El manifiesto identifica la revisión de fuentes y los hashes de los binarios.

## Pendiente del usuario

Descomprimir r3 completo en una carpeta nueva y abrir `AsabiyaNative.exe`. Confirmar aparición del mundo 3D, navegación, selección y avances en el equipo/GPU del usuario. No se abrió el ejecutable gráfico ni se ejecutaron suites históricas, oráculos o CI. Se corrige la causa de deserialización reportada; no se declara validado el renderizado por compilar.

Se actualiza PR #9 en su rama existente, sin merge a main.
