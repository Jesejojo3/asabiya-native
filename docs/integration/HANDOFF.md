# Entrega para el testeo del usuario

Por instrucción expresa del usuario no se ejecutan más suites, oráculos, simulaciones de comprobación, pruebas de integración ni validación visual. Compilar Go, importar recursos y exportar Godot son pasos de producción del artefacto y no se presentan como una prueba funcional.

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
4. Avanzar 1, 10, 100 y 1 000 años; comprobar población, propietarios, pueblos, religiones, ciudades, crónica y censos. Una historia nueva requiere evolucionar para que aparezcan Estados.
5. Comprobar que cámara/render siguen respondiendo durante cálculo, decodificación y recepción. Medir FPS y memoria, que no se han validado.
6. Consultar gobernantes, conflictos, rutas, acontecimientos y observaciones históricas; probar regreso a publicaciones antiguas disponibles.
7. Pausar durante un lote, generar un mundo nuevo, cerrar la ventana y comprobar salida de Go. Interrumpir Go y confirmar el error y reinicio explícito, sin reintento de un avance incierto.
8. Repetir con Tierra, focos históricos, clima ajustado y al menos un mapa importado; comparar dos procesos y preservar todos los golden anteriores.
9. Ejecutar a voluntad las suites existentes y la integración real Godot/TCP. Las pruebas de cliente ya no usan el mock stdio; admiten --server con el servidor real.
10. Comprobar el paquete en la GPU y configuración Windows reales. No se afirma soporte gráfico de un dispositivo que no se haya utilizado.

No hay merge a main ni aprobación de una auditoría externa nueva. La integración definitiva requiere autorización del usuario.

## Corrección del adaptador tras la primera entrega

El adaptador acepta listas nulas de Go como listas vacías, limita a 1 000 los eventos de cada publicación visible y comparte registros históricos idénticos entre vistas. El panel de Estados usa sus censos reales para mostrar las observaciones disponibles. Comprobar manualmente un avance anual sin acontecimientos, publicaciones sucesivas y el cambio de año en esos paneles. Esta corrección se compila/exporta sin ejecutar las pruebas ni el juego. La entrega se produce desde una copia aislada de la revisión publicada para conservar una edición local ajena a la PR.
