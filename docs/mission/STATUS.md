# Estado de la integración

Rama vigente: integration/go-godot-windows, desde HEAD 3130256 de PR #7. Se incorpora PR #8 mediante merge 7edec8d5bd300045cbd9f97444107d348db69001, con ambos padres conservados. PR #7 sigue dependiendo de PR #6 corregida en d19e27ef. Ninguna de esas ramas ni main se sobrescribe.

La instrucción más reciente asigna a Codex tanto el núcleo como la adaptación del cliente Godot. La instrucción posterior del usuario reserva todo el testeo para él: sólo se produce código, documentación y compilación/exportación del paquete Windows. No se abren partidas ni se ejecutan nuevas pruebas, oráculos o CI. No confundir compilación con integración verificada.

## Código incorporado

- Correcciones PR #6: copia profunda de EraShare y opciones ShuffleNames/Sandbox en la huella histórica.
- Núcleo procedural: calendario completo y sistemas A–F del original, con API anual atómica, reglas/comandos, replay, consultas, eventos, deltas e historial comprimido.
- Rama G: Tierra, focos históricos, órbita, regiones/encuestas originales, decodificación de recursos, 16 controles CDEF, ajuste/evaluación Köppen e importaciones de imágenes versionadas.
- Productor: geografía binaria y manifiesto, API TCP exclusiva de loopback, vistas completas y de mapa, publicaciones por año, consultas por ID y exportación.
- Cliente: transporte asabiya/local-v1, arranque/cierre del proceso, endpoint local, sesiones, hilo de red/decodificación y consumo de estados/deltas. Se conservan terreno 3D, LOD, cámara, vegetación y materiales de Claude.
- Interfaz: provincias y consultas directas, Estados/pueblos/religiones, ciudades, gobernantes, guerras/rutas, crónica y estadísticas. La UI no simula mecánicas ni fabrica edificios o entidades.
- Producción: script Windows sin ejecución de tests o juego, configuración predeterminada y de Tierra, licencias y manifiesto de hashes.

[Inventario del original](PORT_INVENTORY.md), [decisiones y límites](../integration/DECISIONS.md), [entrega para el usuario](../integration/HANDOFF.md).

## Evidencia y límites

Antes de detener las pruebas pasaron los contratos por sistema, calendario controlado, pruebas Go, golden previos, consumidor binario y protocolo/replay entre procesos. Una corrida preliminar procedural de 10 000 años terminó con 130 Estados y 8 hordas en el último censo en 116.39 s. No corresponde al motor final con Tierra ni al cliente integrado.

Las comprobaciones finales de reproducibilidad, equivalencia de ramas nuevas, protocolo adaptado, extremo a extremo, GPU y rendimiento quedan al usuario. No se declaran aprobadas ni se ocultan detrás de fixtures regenerados.

Se conserva la semántica de arrays float32/promoción a float64, iteración viva de alive, colecciones ordenadas, RNG único heredado y consumo original. Los NaN de cultura de rebeldes antes del primer censo son comportamiento heredado documentado; las vistas representan métricas no disponibles con null. PoolPass/caravanPass mantienen sus condiciones originales con años negativos.

No hay guardado rápido/restauración de partida completa ni mecánicas nuevas. El merge a main requiere autorización.
