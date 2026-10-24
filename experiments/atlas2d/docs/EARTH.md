# Tierra real — primera base

Prioridad vigente: Tierra real → geografía funcional → mundo histórico visible → UX/UI definitiva.
El overhaul visual queda congelado. Esta entrega conserva la interfaz existente.

## Alcance

Al abrir AsabiyaAtlas2D.exe se carga la elevación terrestre y Köppen ya preservados
en la referencia v0.6. Proyección equirectangular: norte arriba, longitud -180 a
180°, latitud 90 a -90°. Una sola Tierra, zoom anclado al cursor y cámara limitada;
los márgenes no son océanos seleccionables ni copias del mapa.

Go sigue siendo dueño de las 400×200 celdas lógicas y del relieve fino de
1600×800 muestras. El cliente usa sus elevaciones, biomas, remapeo costero y
publicaciones históricas. Los clics muestran el ID provincial y sus coordenadas;
el inspector consulta población, entidades y evolución publicadas por Go.

La semilla del campo superior cambia la historia sobre la misma Tierra. La
geografía usa la semilla estable Asabiya-Earth-v1 y la fuente `kind: imported`
con el recurso `earth-html`: así no se activan los fundadores, focos tecnológicos
fijos ni calibraciones regionales del antiguo modo `kind: earth`. Las reglas
históricas, RNG, referencia y golden originales permanecen intactos.

## Procedencia y límites

Fuente inmediata: `reference/v0.6/Asabiya History Engine (Copy).html`, conservada
sin modificaciones, SHA-256
`988ce360e70d2d034a3898f60b9a4c38d40b0ab56dd7a147329740f15fa8e9e9`.
El paquete copia esos mismos bytes como earth-v06.html; Go verifica su hash y tamaño.
El manifiesto de compilación identifica el recurso y los ejecutables.

Es la cartografía heredada del proyecto, no un nuevo levantamiento topográfico.
Los metadatos originales del proveedor, fecha y licencia de los rasters no están
documentados en la auditoría existente. Deben resolverse antes de distribuirlos
fuera del uso personal del proyecto. No se atribuye una procedencia inventada.

Temperatura y precipitación proceden del modelo climático de Go ajustado con
Köppen. Los biomas son derivados por Go, no una fotografía ni observaciones
meteorológicas actuales. Los ríos y recursos siguen siendo los calculados por el
motor: no se presentan como hidrografía o inventarios terrestres medidos.

El relieve se muestra con sombreado 2D. La resolución fina es aproximadamente
0,225° por muestra; la celda provincial mide 0,9°. No permite aún la riqueza
regional de las imágenes de referencia, edificios, ruinas ni límites
administrativos históricos. No se crean entidades decorativas.

## Validación y siguientes entregas

La reproducibilidad se compara entre ejecuciones con los mismos datos, versión,
configuración y semillas. Una Tierra importada no debe igualar el SHA de otro
mundo procedural. El modo procedural anterior sigue accesible con `-- --procedural`;
`-- --small` conserva las pruebas pequeñas procedurales.

Antes de dar por terminada la fase 1: revisar capturas mundial y regional, la
costura de longitud, los polos, varios tamaños de ventana y consultas a Go;
medir FPS/tiempos y memoria en la Intel Iris Xe. No afirmar fluidez sin evidencia.
Después: cartografía con procedencia y resolución regional verificadas, y
adaptación geográfica de provincias, hidrografía y recursos. Más adelante,
representar únicamente asentamientos, construcciones y transformaciones que Go
publique; finalmente retomar la interfaz definitiva.
