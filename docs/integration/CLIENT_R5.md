# r5 — ritmo de los años

El usuario precisa que lo lento en r4 es el paso de los años. R4 seleccionaba inicialmente 1 año/s y limitaba el ritmo a 10. R5 selecciona 10 por defecto y ofrece 1, 2, 5, 10, 25, 50 y Máxima. Máxima elimina la espera artificial: cada petición sigue avanzando exactamente un año y no se solicita otro hasta recibir el anterior. No se acumulan ráfagas ni se omiten años publicados. Se mantienen pausa y cámara r4.

Los valores son objetivos, no medidas de rendimiento. El ritmo alcanzado depende del cálculo, publicación, transporte y representación en el equipo del usuario. No se ejecutan benchmarks ni partidas en esta entrega.

## Trabajo eliminado

- Las capas estáticas (Terreno, provincias, geografía y clima original) conservan su textura entre años. Un cambio explícito de capa sigue actualizándola; las capas históricas continúan leyendo cada publicación. No se regenera el mundo.
- El protocolo ya proyectaba las provincias a ocho campos de mapa, pero seleccionaba cambios por el registro provincial completo. Un cambio sólo en clima anual, epidemiología o niveles técnicos podía reenviar una fila de mapa idéntica. Ahora la sesión mantiene una copia privada de la última proyección y omite sólo las filas idénticas a esa base. Se conservan todos los cambios reales del mapa, los demás campos del delta y cada frontera anual.
- Se comparan los bits float32 de población, capacidad y fortificación, incluyendo el signo del cero. La caché no comparte el array de una publicación devuelta. Las órdenes y los avances sin vista de mapa invalidan la base; una base ausente o de otro año devuelve el delta original sin filtrar. Un estado completo de mapa repone la base. No hay cambios en internal/sim, RNG, reglas, digest, replay o calendario.

## Producción y pendientes

Go 1.27.2 y Godot 4.7.2, Windows x64. Compilación/importación/exportación; sin ejecutar el juego, pruebas, oráculos o CI por la instrucción vigente del usuario. Se añaden casos no ejecutados para filtrado exacto, ausencia de aliasing, base inválida, ritmo 50 y Máxima manteniendo una sola petición pendiente. Los golden y el HTML anteriores permanecen intactos. No se afirma que esas pruebas pasaron ni una aceleración medida.

La prueba del usuario debe comparar Continuar a 10, 25, 50 y Máxima, comprobar años consecutivos, pausa durante cálculo, selección y capas históricas. PR #9 continúa en su rama; sin merge a main. Las entregas r3/r4 se conservan aparte.
