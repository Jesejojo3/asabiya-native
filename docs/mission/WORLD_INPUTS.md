# Tierra, importación y clima de generación

El núcleo recibe WorldInputs numéricos; internal/mapsource se ocupa de archivos locales. WorldConfig conserva su estructura congelada. La fuente y los controles CDEF viven en WorldSource; las reglas anuales siguen separadas.

## Tierra

```powershell
./bin/asabiya-headless.exe --seed Earth --earth-html "reference/v0.6/Asabiya History Engine (Copy).html" --years 0 --export earth
```

El adaptador exige el SHA-256 original 988ce360e70d2d034a3898f60b9a4c38d40b0ab56dd7a147329740f15fa8e9e9. Extrae las dos constantes base64 sin ejecutar JavaScript; descomprime zlib con límites exactos. La elevación es delta int16 little-endian por fila, con acumulador float64 y escrituras float32. La clasificación Köppen es u8. Tierra requiere 400×200 con detalle 4; no se inventa otro remuestreo del recurso.

La rama histórica omite el sorteo de fase orbital, usa la curva orbital fija, conserva el barajado del catálogo de macrolenguas incluso sin ShuffleNames, los diez puntos fundadores y los dieciséis focos originales, incluido grain=0. Se incorporan regiones originales, cuotas china/mediterránea y encuestas agrícolas/políticas. Las vistas opcionales earth y las capas Köppen/grade no fabrican entidades nuevas.

Procedencia comprobable del recurso: el HTML preservado y su manifest de importación. El HTML no identifica una licencia/proveedor original suficientemente claro para estos raster; no se atribuye a un dataset externo inventado ni se distribuye otra extracción separada. La copia del paquete sigue siendo el HTML íntegro del repositorio privado para uso personal.

## Importaciones y controles

Atajos: --height-image (negro -11000 m, blanco 9000 m, punto medio mar), --temperature-image (-40..35 °C) y --precipitation-image (0..4000 mm/año), con PNG/JPEG/GIF. Se exigen muestras positivas de elevación y al menos una celda lógica terrestre. No se interpreta una imagen como partida histórica.

Para controlar escalas y los 16 parámetros CDEF usa --world-source RUTA.json:

```json
{
  "kind": "imported",
  "climate": {"tEq": 29, "rainBelt": 3150},
  "fitClimate": false,
  "assets": [
    {"role":"height","path":"height.png","min":-11000,"max":9000,"midpoint":true},
    {"role":"temperature","path":"temperature.png","min":-40,"max":35},
    {"role":"precipitation","path":"rain.png","min":0,"max":4000}
  ]
}
```

Los controles omitidos heredan CDEF. Las rutas de ese archivo se resuelven respecto a su carpeta. Un asset koppen opcional es un archivo u8 de longitud exacta igual a la malla fina, con códigos 0..32. Permite fitClimate fuera de Tierra.

El adaptador nativo fija bilineal por centros de pixel, RGB8 y redondeo; después conserva los puntos de escritura float32 de luminancia y escalado. El filtrado canvas “high” del navegador no define un algoritmo portátil: las importaciones no prometen producir sus mismos pixels. Tampoco se promete igualdad de perfiles ICC/transparencia de navegadores; alpha cero se trata como RGB cero. Este cambio de adaptación está versionado como native/bilinear-rgb8-v1.

El generador usa los mismos controles CDEF y orden, ajusta clima cuando hay Köppen y lo solicita la fuente, y calcula el grade a partir del clima bruto anterior a overrides/ajuste. El camino procedural con controles por defecto mantiene su aritmética congelada para no reescribir los golden anteriores.

World.Version sigue en native/world-v2 para el caso procedural por defecto y pasa a native/world-v3 para fuentes/controles extendidos. El digest extendido incluye fuente, escalas, hashes de assets, controles y capas diagnósticas; excluye rutas absolutas. El binario de geografía tiene además su propio hash, que cubre el relieve fino de presentación.

El replay registra la fuente y los hashes de los archivos. Al reconstruir, el adaptador exige esos mismos bytes. Una llamada Go directa con rasters sin assets puede reproducirse pasando el mismo World a ReplayOnWorld; el ejecutable no puede inventar archivos de entrada que no fueron registrados. No es un guardado rápido.

Estas ramas se han implementado y compilado; sus pruebas funcionales y de equivalencia quedan al usuario.
