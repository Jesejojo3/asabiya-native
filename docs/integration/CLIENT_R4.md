# r4 — interfaz, cámara y reproducción continua

El usuario reasignó a Codex el trabajo del cliente de Claude y señaló tres problemas: interfaz recargada, zoom irregular (aceleración, falta de respuesta y reinicios aparentes en el límite) y tiempo mostrado a saltos. Esta revisión modifica el cliente en la misma rama de PR #9. Conserva el terreno 3D, materiales, Go, geografía, reglas y protocolo existente. No hay merge a main.

## Interfaz

- Barra superior compacta: identidad del mundo, contadores esenciales y acceso a mapas, búsqueda y menú. La columna permanente de 23 modos se sustituye por un selector desplegable; las capas sin datos no se anuncian como funciones utilizables.
- Controles de tiempo juntos en la parte inferior: Continuar/Pausar, ritmo explícito en años por segundo, paso de un año, fecha e historial reciente. Crónica y búsqueda se abren a petición. La selección conserva una ficha lateral que aprovecha la altura disponible.
- Paneles neutros, separadores discretos, esquinas casi rectas y sin sombras de tarjetas ni insignias permanentes de conexión. Tipografía del sistema (Segoe UI en Windows, con fallback). Espaciado, recorte de texto largo, adaptación a ventanas estrechas y límite de escala para que los controles quepan.
- Fichas con hechos históricos y enlaces a entidades/provincias; se retiran volcados genéricos de JSON, nombres de campos de transporte y filas repetidas de datos ausentes. Se mantienen las limitaciones reales de ciudades, fortificación y decoración.
- Arranque centrado, con reintento mostrado sólo tras un error. No se considera aprobado visualmente por esta descripción del código.

## Zoom

La rueda anterior calculaba `zoom_step * event.factor`. Un evento de precisión con factor 0.2 producía una razón menor que 1 y podía invertir el sentido de la rueda. Ahora se usa `pow(zoom_step, steps)`, con pasos acotados y razón siempre coherente. Los gestos también comprueban valores finitos y límites.

El zoom conserva el punto de terreno bajo el cursor durante el suavizado mediante intersecciones con su plano de altura. Se conserva la copia longitudinal realmente señalada; al normalizar coordenadas se desplazan juntos objetivo y ancla. Invertir la rueda cancela la inercia pendiente. En un límite se mantiene el límite, sin reiniciar la cámara. Los fotogramas lentos no consumen de golpe toda la transición.

La vista mundial se calcula según tamaño del mapa, campo visual y relación de aspecto. La altura del punto de enfoque deja de variar artificialmente con el porcentaje de zoom. Se conserva la protección contra atravesar el terreno y se mantiene el movimiento separado de la simulación.

Estas son correcciones contrastadas con el código. No se afirma haber reproducido o eliminado visualmente todos los síntomas del equipo del usuario.

## Tiempo continuo

El botón anterior reproducía publicaciones guardadas y, al llegar al presente, pedía diez años; los lotes publicaban estados cada cincuenta. Ahora Continuar activa un programador en BridgeSource basado en reloj monotónico, con ritmos objetivo 1/2/5/10 años por segundo. Sólo hay un año en vuelo y se publica cada año completo mediante `advance` con `view: map`. No recorre primero la caché ni simula estados intermedios en Godot.

Si calcular/transportar/representar un año excede el intervalo, la velocidad efectiva baja. No se acumulan solicitudes ni se envía una ráfaga de recuperación. Pausar deja terminar el año aceptado y detiene la programación. El botón permanece utilizable durante ese cálculo, incluso con una única publicación inicial. Consultar el historial pausa el avance; cambiar el ritmo no acumula deuda.

El motor v0.6 sigue teniendo resolución anual: tiempo continuo significa ejecución automática sostenida, no mecánicas diarias/mensuales ni estados fraccionarios inventados. Las funciones previas de lotes quedan disponibles para herramientas y pruebas existentes, pero no son el camino del botón Continuar.

## Trabajo repetido evitado

Se conserva la geometría de asentamientos cuando no cambian identidad, provincia, categoría, aspecto, era o nombre; la era pasa a formar parte de su clave de caché. No se invalida la vegetación por listas de claros idénticas. Etiquetas, marcadores y rutas sólo se reconstruyen cuando cambia la información visual que utilizan. Las leyendas y listas de crónica idénticas se reutilizan, y una crónica cerrada no se rellena continuamente. Las consultas detalladas de una selección se hacen en pausa; no se añaden a cada año en reproducción. La ficha sigue leyendo los datos anuales publicados.

Se elimina además la creación de etiquetas huérfanas para cada enlace de una ficha. No se presentan estas decisiones como un benchmark o una garantía de FPS: falta medirlas en el equipo del usuario.

## Correcciones de datos del cliente

La cultura de un pueblo es un vector de seis componentes. La capa anterior intentaba convertir el Array completo a float. El color utiliza ahora explícitamente los tres primeros componentes como RGB (rango visual 0.25..0.90); la leyenda lo declara y la ficha conserva los seis valores. Los valores inválidos quedan sin colorear, sin inventar un índice cultural.

La capa de guerras recorre ambas coaliciones completas que entrega Go, en lugar de marcar sólo su primer atacante y defensor. Se conserva el significado de Estado 0 como territorio sin Estado y no se inventan frentes de batalla.

## Producción y comprobaciones

Se compila/importa/exporta con las herramientas fijadas: Go 1.27.2 y Godot 4.7.2, Windows x64. El manifiesto del ZIP identifica la revisión y cada archivo. El servidor conserva la corrección numérica r3. Se mantienen intactos el HTML, el tag, los commits anteriores y los golden previos.

Se añadieron casos a `client/godot/tests/run_tests.gd` para rueda de precisión, programación de un único año, ausencia de ráfagas, vector cultural y coaliciones. **No se ejecutan en r4**: el usuario mantiene a su cargo el testeo. La evidencia de siete pruebas del protocolo de r3 corresponde a r3 y no demuestra el cliente r4. No se ejecutan suites, oráculos, CI ni el juego exportado.

Pendiente del usuario: inspección visual de la nueva composición; rueda lenta/rápida y gestos; inversión de dirección y ambos límites; costa, montañas y costura longitudinal; reproducción sostenida, pausa durante un cálculo, cambio de ritmo y consulta del historial; medida de FPS, memoria y ritmo efectivo. Ni sensaciones de cámara ni rendimiento gráfico se deducen de compilar.
