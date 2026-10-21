# Reproducción Fluida y paquete Windows

La reproducción arranca en **Máxima**, con **Fluido** activado. La Fase 2.2 restaura su control visible: desactivarlo solicita comprobación anual para los siguientes avances. Continúa publicando cada año consecutivo, con los mismos datos y mecánicas. La diferencia es la política de comprobación: calcula SHA completo cada 25 años y al pausar; el paso individual también conserva su SHA exacto. Pausar y avanzar un año mantienen su comprobación exacta con cualquiera de las dos posiciones del control.

La opción es explícita y visible. Un año intermedio lleva `digestMode=deferred-v1` y una huella vacía, nunca un SHA inventado. La línea temporal avisa cuando el año observado no tiene comprobación individual. Pausar verifica el año actual; no crea retrospectivamente huellas exactas para todos los años anteriores. El historial visual sigue siendo una caché limitada, no un archivo íntegro de huellas.

Los servidores anteriores que no anuncian `digestCheckpointsV1=25` mantienen la ruta verificada anual. No cambia el protocolo ni la simulación Go. La pausa bloquea nuevos avances hasta recibir el snapshot exacto del último año aceptado, incluido cuando se pausa con una petición en vuelo. Los estados diferidos anteriores siguen siendo inmutables y conservan su marcador.

## Medición conectada

Go 1.27.2 y Godot oficial 4.7.2, Linux amd64 cloud, AMD EPYC 7763, mundo 400×200, detalle 4, semillas Asabiya/1. Tres pares alternados, 53 años por sesión, inicio excluido y **pausa final verificada incluida**:

| Modo | Tiempo mediano para 53 años | Ritmo mediano |
|---|---:|---:|
| Verificar cada año | 5,886 s | 9,00 años/s |
| Fluido | 2,836 s | 18,69 años/s |

Resultado: aproximadamente **2,08 veces el avance**. Las seis sesiones publicaron los 53 años consecutivos y terminaron con el mismo replay y SHA `d2a907dbeb1b8f9838ae939e98d44fc7c73a2bfb42075cd973ac4ad4207c79a3`. El final cae entre checkpoints, por lo que también comprueba la verificación de una pausa fuera del múltiplo de 25.

Una muestra adicional con la aplicación completa (mapa, HUD, capas y adaptador), también headless, pasó de 6,078 s a 2,697 s para los mismos 53 años. La consulta de replay posterior conserva el mismo SHA. Es una sola muestra adicional, no una campaña estadística ni una medición de FPS, GPU o rendimiento de la laptop Windows.

## Validación

- Go: `TestCheckpointAnnualEquivalence` pasa sobre mundos 24×16 y 400×200. Comprueba metadatos, todas las provincias, SHA solicitado y replay entre los dos modos.
- Godot headless: 146 comprobaciones de publicación/negociación, 142 de Atlas, 148 de avance/pausa/Fast-Forward y 135 de reproducción fluida real, incluida pausa con un año en vuelo y bloqueo de reanudación durante su comprobación.
- La campaña conectada de tres pares completos pasa 379 comprobaciones, incluyendo todos los años, huellas, replay, pausa exacta y ausencia de avances posteriores a la pausa.
- La optimización Go de la PR #19 y sus verificaciones de bytes, RNG y concurrencia se conservan.

Reproducción:

```sh
go build -o build/bin/asabiya-server ./cmd/asabiya-server
godot --headless --path client/godot --script res://tests/fluid_playback_regressions.gd -- --server "$PWD/build/bin/asabiya-server"
godot --headless --path client/godot --script res://tests/fluid_playback_regressions.gd -- --server "$PWD/build/bin/asabiya-server" --benchmark
```

Los resultados crudos están en `benchmarks/fluid-playback-2026-10-20/`. El benchmark Go inicial de esta continuación se descarta como evidencia cuantitativa porque una compilación/importación coincidió con su primera muestra. Las cifras anteriores proceden de la campaña conectada ejecutada sin otro benchmark o compilación compitiendo.

## Probar en Windows

Descomprimir el ZIP completo en una carpeta nueva y abrir `AsabiyaNative.exe`. Generar el mundo, pulsar **Continuar** y comprobar que la velocidad inicial es **Máxima**. El servidor Go arranca automáticamente. No instalar Go ni Godot, ni reemplazar archivos de una entrega previa por separado.

El paquete se construye con Go 1.27.2 (windows/amd64, GOAMD64=v1, CGO desactivado), Godot oficial 4.7.2 y sus plantillas fijadas por SHA-256. Incluye cliente, servidor, recursos y manifiesto de hashes. La construcción y las pruebas headless no acreditan ejecución Windows ni validación gráfica en el equipo del usuario.
