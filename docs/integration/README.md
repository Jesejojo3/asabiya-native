# Integración Go + Godot para Windows x64

Actualización r5: ritmo inicial 10 años/s; se añaden 25, 50 y Máxima y se reduce trabajo repetido de publicación y capas estáticas. Ver [CLIENT_R5.md](CLIENT_R5.md). Los ritmos son objetivos; no hay una aceleración medida ni aprobación visual de esta entrega.

Esta rama incorpora el historial completo de PR #6/#7 y del cliente PR #8. El merge de incorporación es `7edec8d5bd300045cbd9f97444107d348db69001`, con padres `3130256ca5a3e8103ae131b395dec1cff81c41f3` y `f5b8d5635f0e2389bcc492fff11d3d6eb68ed9cd`. Las tres PR permanecían abiertas al preparar la integración. No hay merge a main ni reescritura de commits.

El usuario reasignó a Codex el cliente de Claude y pidió corregir interfaz, zoom irregular y tiempo a saltos. [Cambios r4 y límites de comprobación](CLIENT_R4.md). Su instrucción mantiene el testeo visual y de juego a su cargo. La entrega distingue compilación/exportación de verificación funcional. Las pruebas numéricas específicas autorizadas en r3 se registran por separado; en r4 no se ejecuta el juego exportado, suites, oráculos, simulaciones de comprobación ni CI nuevos.

## Abrir y construir

Abre `AsabiyaNative.exe` en la carpeta Windows entregada. Go se inicia automáticamente. No necesita Godot instalado, Go instalado ni conexión externa para jugar. La generación y el cálculo histórico son locales.

Para reconstruir se necesitan Go 1.27.2 Windows amd64 y Godot 4.7.2 estable, fijados en el repositorio:

```powershell
./tools/package-windows.ps1
# Con editor ya descargado:
./tools/package-windows.ps1 -GodotPath C:/ruta/Godot_v4.7.2-stable_win64_console.exe
```

El script compila, importa recursos y exporta; no ejecuta tests, genera partidas ni abre el juego. Descarga herramientas oficiales con los hashes fijados cuando hacen falta; las plantillas completas pesan aproximadamente 1.28 GB y sólo se extraen las de Windows x64. `BUILD-MANIFEST.json` registra revisión de fuentes, herramientas y hashes de los archivos de la entrega.

La configuración inicial es `asabiya.json`. `asabiya-earth.json` permite seleccionar Tierra, cargando el HTML preservado desde `resources/legacy-v0.6.html`. Las rutas relativas de recursos se resuelven respecto al ejecutable. Un archivo pasado mediante `-- --world-source RUTA.json` usa como base su propia carpeta. Ver [Tierra e importaciones](../mission/WORLD_INPUTS.md).

## Conexión y publicaciones

Se mantiene un solo protocolo activo: TCP en 127.0.0.1, `asabiya/local-v1`. No se implementa `asabiya-bridge/v1` ni un segundo motor. El nombre de clase Godot `BridgeSource` se conserva por compatibilidad interna del cliente; ahora implementa TCP.

El cliente lanza `asabiya-server.exe --port 0 --endpoint-file ... --log-file ...`, vigila el proceso padre en Windows, lee el endpoint publicado de forma atómica y se conecta en un hilo de trabajo. Este hilo también recibe NDJSON, decodifica JSON y produce vistas históricas. El hilo gráfico sólo recibe publicaciones completas. Cada petición tiene ID de texto; se comprueban ID, esquema y generación de sesión. Una desconexión o expiración no repite comandos de resultado incierto. Se conserva la última vista y se permite reiniciar explícitamente la sesión.

Secuencia inicial: `create_world`, `get_catalog`, `export_geography`, `start_history`. La geografía se lee mediante el manifiesto y binario de Go. `WorldData` valida tamaño, cabecera, hash del binario, capas y dimensiones, y conserva el digest lógico del mundo. Una geografía externa que no coincide con el mundo recreado es rechazada.

Las operaciones `start_history`, `get_state` y `advance` aceptan `view: "map"`: son proyecciones versionadas `asabiya/map-state-v1` y `asabiya/map-delta-v1`. Conservan el contrato de entidades, eventos, RNG, estadísticas y digest. Sus registros provinciales contienen ID, propietario, pueblo, religión, población, capacidad, fortificación y era, sin repetir los 32 niveles tecnológicos y otros detalles en todas las celdas. `get_province` sigue ofreciendo esos datos completos. La respuesta incluye el año de consulta para evitar mezclar datos de años diferentes.

Continuar aplica un delta cada año mediante un programador de presentación basado en reloj monotónico, con ritmos objetivo 1/2/5/10/25/50 años/s o Máxima y como máximo un año en vuelo. No reproduce primero la caché ni acumula ráfagas si el cálculo tarda. Pausa detiene la secuencia después del año ya aceptado. El reloj de presentación sólo decide cuándo solicitar el siguiente año completo a Go; no calcula historia en Godot. Las herramientas que usan lotes pueden seguir utilizando `publication: "status"` y estados cada 50 años; esa optimización no se usa para la reproducción continua del cliente.

## Geografía y representación

Los formatos .asw y geography-v1 son diferentes. Se conserva el exportador .asw y su lector para herramientas antiguas; el arranque normal usa exclusivamente geography-v1, sin convertir sus bytes como si fueran .asw. El adaptador comparte las rutinas de carga de capas y traduce nombres y offsets de forma explícita.

Se conservan terreno 3D, shaders, cámara, costura longitudinal, relieve fino, LOD, vegetación y selección de Claude. Los cambios históricos modifican texturas y anotaciones; no reconstruyen la malla geográfica. CellID sigue siendo `y * width + x`. Estado 0 significa sin Estado; pueblo/religión -1 significan ausencia. El cliente no crea una entidad de Estado 0.

La era provincial procede directamente de Go; su división por 7 sólo normaliza el color de la capa. La cultura es un vector de seis componentes del pueblo. La capa cultural asigna sus tres primeros componentes a RGB, con rango visual 0.25..0.90; la leyenda declara esa selección y los seis valores se conservan en el panel del pueblo. No se inventa un índice o una cultura nominal. Las fronteras de esa capa corresponden a IDs de pueblos. La capa de guerras incluye todos los atacantes y defensores que entrega Go, no sólo los líderes de coalición. Las ciudades son sitios reales del motor; el tamaño visual usa población provincial. Las murallas visibles son un proxy del índice de fortificación; la disposición de casas es decorativa. No se inventan puertos, templos ni entidades de edificios. No se dibujan frentes de batalla inexistentes en el contrato. Las rutas usan el camino real y un grosor visual sin fingir un volumen comercial medido.

## Memoria e historia

El cliente retiene como máximo 24 publicaciones completas y 1 000 eventos visibles por publicación; la crónica dibuja como máximo 500. Los registros históricos que no cambian se comparten entre publicaciones; los arrays provinciales publicados son copias independientes. Los límites del cliente no alteran la historia de Go.

Go conserva censos, entidades y el historial comprimido original: propiedad observada cada 10 años y capas cuantizadas cada 50. Las consultas provinciales muestran las observaciones disponibles, no fechas exactas de cada conquista. No existe restauración rápida de partida completa; el replay vuelve a simular los comandos.

## Revisión del usuario

[Entrega y comprobaciones pendientes](HANDOFF.md) separa evidencia anterior de las pruebas que el usuario realizará. [Inventario del original](../mission/PORT_INVENTORY.md) muestra la correspondencia de funciones. Las pruebas existentes del cliente se adaptan al contrato actual, pero no se ejecutaron. El mock stdio heredado de PR #8 queda como material histórico sin uso en el cliente ni en la prueba TCP actual.
