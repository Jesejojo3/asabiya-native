# Guía del responsable del proyecto

No necesitas saber programar para abrir el prototipo. En la PR #27 entra en
Checks → Atlas 2D experiment → ejecución terminada en verde. En Artifacts,
descarga `asabiya-atlas2d-windows-x64`; extrae todo el ZIP y abre
`AsabiyaAtlas2D.exe`. Usa ese artefacto: el botón Code de main todavía no contiene
toda la integración. El paquete es independiente del cliente 3D.

Si quieres explorar sociedades posteriores sin esperar toda la reproducción
anual, abre `Abrir historia avanzada.cmd`. Go prepara 10.000 años, hasta +1000;
puede tardar varios minutos. Se avisa de que la presentación durante esa fase
es cada 100 años, aunque Go calcula todos. Puedes pausar. El arranque normal
empieza en −9000 y puede no tener estados todavía.

Espera a que aparezca el mapa. El encabezado dice mundo procedural porque todavía
no es la Tierra. Usa Mundo, Región y Provincia, arrastra y gira la rueda. Un clic
identifica la provincia de Go; el panel debe mostrar el mismo año que el mapa.
Cambia Política por Población para comprobar otra lectura de la misma historia.
Una provincia sin estado no debe tener un propietario inventado.

Pulsa +1 año: el número aumenta en una unidad al terminar Go. Reproducir calcula
años sucesivos; Máximo pide el siguiente al publicar el anterior. Pausar termina
el año en curso y verifica el estado; la advertencia SHA diferido debe desaparecer
cuando llega la huella exacta. El selector de años revisa publicaciones recientes;
no hace que Go vuelva al pasado. Nueva sesión descarta la sesión en memoria:
el prototipo aún no tiene una operación de guardar/cargar partida.

Para medir el portátil, conéctalo a corriente y cierra otras cargas. Abre
`Medir rendimiento.cmd`: son cuatro capturas, con preparación histórica en cada
una. No interactúes con la ventana durante la prueba. `Medir completo.cmd` añade
los otros zooms y repeticiones; tarda más. Conserva la carpeta mediciones-* y el
build-manifest.json del paquete. La captura no necesita Python; si no hay resumen,
comparte los datos crudos. El perfil energético usado se anota por separado.

Qué revisar antes de decidir la siguiente etapa:

- Navegar y seleccionar sin tirones molestos en tu Iris Xe.
- Confirmar 30 FPS sostenidos con P95/P99 y porcentaje de frames lentos, además de la mediana. 60 FPS sigue siendo deseable.
- Que reproducir no congele la cámara y que pausar deje un año y SHA verificables.
- Consumo de memoria y años/segundo; una mejora gráfica no demuestra que Go calcule más rápido.
- Que población, propietario y cultura tengan fuente y año, y que lo ausente figure como ausente.

El prototipo no demuestra todavía el rendimiento del portátil. Los resultados
Linux/software y CI prueban integración, export y metodología. Antes de Tierra,
edificios o ruinas, hay que revisar una captura real. Integrar esta PR o cualquier
otra en main sigue siendo una decisión posterior del responsable.

Si algo falla, conserva el mensaje visible, la carpeta de mediciones, los logs de
sesión en `%APPDATA%/AsabiyaAtlas2D/sessions` y la versión del paquete. Una carpeta
de prueba incompleta no acredita un resultado de rendimiento.
