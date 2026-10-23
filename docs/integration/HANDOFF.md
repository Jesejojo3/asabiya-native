# Entrega para el testeo del usuario

Actualización r5: el usuario precisa que lo lento es el avance anual. Ritmo inicial 10 años/s; opciones 25, 50 y Máxima, sin omitir años ni acumular ráfagas. Se evitan filas de mapa idénticas y repintado de capas estáticas. Ver [CLIENT_R5.md](CLIENT_R5.md). Compilación/exportación sin pruebas nuevas ni juego; validación y medida del ritmo efectivo a cargo del usuario.

Actualización r4: Codex asume el cliente completo y revisa interfaz, cámara y reproducción a petición del usuario. Ver [cambios y casos pendientes](CLIENT_R4.md). Se produce un ZIP r4 independiente; se mantienen r2/r3. Se compila/importa/exporta, sin abrir el juego ni ejecutar pruebas nuevas. La comprobación visual y de comportamiento con el ratón del usuario sigue pendiente. Continuar solicita años consecutivos con ritmo 1/2/5/10 años/s; el botón 1 año conserva el paso manual. Ya no presenta saltos de lotes como reproducción continua.

Actualización r3: el usuario solicitó corregir los enteros JSON del protocolo y autorizó sus pruebas específicas. Se ejecutó esa cobertura y las dos regresiones esenciales previas del protocolo; ver [evidencia y contrato](JSON_INTEGER_FIX.md). El testeo visual y de juego sigue a su cargo. No se ejecutaron suites históricas extensas, oráculos, CI ni el juego exportado. Compilar Go, importar recursos y exportar Godot son pasos de producción del artefacto y no se presentan como aprobación visual.

## Evidencia anterior a la detención

En Windows x64, antes de esta integración: tests Go y vet, contratos JS por sistema, calendario controlado, golden nativos en dos procesos, reconstrucción binaria por Node y protocolo TCP con replay independiente pasaron. El consumidor TCP anterior realizó 19 peticiones y tres avances y reconstruyó el replay en otro proceso.

Una ejecución preliminar de 10 000 años en 400×200 terminó en el año 1000 en 116.39 s, con 130 Estados y 8 hordas en el último censo; registró conflictos. Esa medición pertenece al núcleo procedural anterior al cierre de Tierra y a la adaptación de Godot. No mide FPS ni rendimiento de esta integración, ni valida Tierra.

No se reutilizan estas pruebas para declarar aprobada la versión final. Las dos tareas CI de HEAD 3130256 estaban en cola al detener el testeo; el conector carece de cancelación y el navegador disponible no tiene acceso al repositorio privado. Los commits nuevos usan [skip ci]. No se solicitan nuevas ejecuciones.

## Producción del paquete

La entrega incluye el cliente Godot exportado para Windows x64, servidor Go, herramienta headless, exportador .asw heredado, configuración procedural/Tierra, copia íntegra del recurso original, licencias y manifiesto de hashes. Los logs de importación/exportación se guardan en build/. El manifiesto del paquete es la evidencia de los binarios concretos y de su revisión de fuentes.

El juego exportado no fue abierto. La misión se entrega para comprobación manual; su funcionamiento integrado y visual no se declara demostrado.

## Comprobaciones pendientes, a cargo del usuario

1. Abrir AsabiyaNative.exe, observar arranque de Go sin configurar puertos y generación del relieve.
2. Mover cámara y hacer zoom continental/provincial; seleccionar tierra, costa, océano y costura longitudinal.
3. Pausar en un año publicado; comparar provincia seleccionada con su consulta directa al servidor, incluidos IDs y año.
4. Usar Continuar a 10/25/50 años/s y Máxima, pausar y probar el paso de 1 año; comprobar población, propietarios, pueblos, religiones, ciudades, crónica y censos. Una historia nueva requiere evolucionar para que aparezcan Estados.
5. Comprobar que cámara/render siguen respondiendo durante cálculo, decodificación y recepción. Medir FPS y memoria, que no se han validado.
6. Consultar gobernantes, conflictos, rutas, acontecimientos y observaciones históricas; probar regreso a publicaciones antiguas disponibles.
7. Pausar durante un lote, generar un mundo nuevo, cerrar la ventana y comprobar salida de Go. Interrumpir Go y confirmar el error y reinicio explícito, sin reintento de un avance incierto.
8. Repetir con Tierra, focos históricos, clima ajustado y al menos un mapa importado; comparar dos procesos y preservar todos los golden anteriores.
9. Ejecutar a voluntad las suites existentes y la integración real Godot/TCP. Las pruebas de cliente ya no usan el mock stdio; admiten --server con el servidor real.
10. Comprobar el paquete en la GPU y configuración Windows reales. No se afirma soporte gráfico de un dispositivo que no se haya utilizado.

No hay merge a main ni aprobación de una auditoría externa nueva. La integración definitiva requiere autorización del usuario.

## Corrección del adaptador tras la primera entrega

El adaptador acepta listas nulas de Go como listas vacías, limita a 1 000 los eventos de cada publicación visible y comparte registros históricos idénticos entre vistas. El panel de Estados usa sus censos reales para mostrar las observaciones disponibles. Comprobar manualmente un avance anual sin acontecimientos, publicaciones sucesivas y el cambio de año en esos paneles. Esta corrección se compila/exporta sin ejecutar las pruebas ni el juego. La entrega se produce desde una copia aislada de la revisión publicada para conservar una edición local ajena a la PR.
