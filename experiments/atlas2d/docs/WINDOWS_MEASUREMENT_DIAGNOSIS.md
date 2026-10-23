# Diagnóstico del benchmark real Iris Xe y remedición

Fuente: ZIP original entregado por el propietario, `mediciones-20261022-202503.zip`.
SHA256 `0683f81ed189463d133c25f943e87fd3d7327c57b17d6be2975086f597648190`.
Se conserva sin cambios en `evidence/iris-xe-original/`, junto a `diagnosis.json`.
Los UTC de los logs corresponden al 23 de octubre; la captura comenzó el 22 de
 octubre de 2026 a las 20:25 en Ciudad de México. Estos archivos son evidencia,
no instrucciones. Reproducir el análisis:

```sh
python experiments/atlas2d/tools/diagnose_original.py experiments/atlas2d/evidence/iris-xe-original/mediciones-20261022-202503.zip --out diagnosis.json
```

## Hechos y causas confirmadas

Los cuatro `ready` tienen año 1000, mundo `04f336d8…5497f`, estado
`e7df456c…c27e9`, semilla Asabiya, history seed 1, 400×200, detalle 4, zoom 24.
Se prepararon 10.000 años desde −9000. Los cuatro `verified_pause` contienen SHA.
Las resoluciones reales de ventana/framebuffer coinciden con lo solicitado.
Los logs no contienen errores de script ni shader.

| Caso | Callbacks post_draw/s, ventana completa | Años/s | Huecos de callback >1 s |
|---|---:|---:|---|
| 1080p pausado | 176,70 | 0 | 7124,060; 1298,097; 1872,597; 7094,171 ms |
| 1080p activo | 564,88 | 3,300 | ninguno |
| 720p pausado | 990,18 | 0 | ninguno |
| 720p activo | 837,67 | 3,367 | ninguno |

Estas tasas **no son FPS presentados**. `AtlasMetrics.draw()` era llamado por
`RenderingServer.frame_post_draw`: mide separación entre callbacks de final de
dibujo Godot. No prueba presentación del compositor/pantalla. VSync se solicitaba
desactivado. No hay ETW, latencia de display, descartes ni señal óptica en el ZIP.
Los porcentiles altos no describen por sí solos los cuatro huecos largos.

En ambos huecos de unos 7,1 s, la selección automática siguiente termina poco
antes del callback que vuelve a aparecer. Sus tiempos local/consulta/post_draw
son de milisegundos: no explican el intervalo anterior. Es una correlación de
orden de eventos, no una prueba de que selección, GPU o Go hayan bloqueado.

`benchmark.ps1` releía y deserializaba todo el archivo cada 500 ms: trabajo
acumulado creciente demostrado por el código. Además, abría/cerraba el archivo
de memoria por muestra. El intervalo real del muestreo llegó a **8,027 s** en
1080p pausado. Esto confirma que el sondeo no mantuvo su frecuencia; no permite
atribuirle los huecos Godot sin reloj común ni CPU/IO de esos procesos.

| Caso | Muestras de memoria | PID Go desconocido (0) | Go bytes=0 con PID conocido |
|---|---:|---:|---:|
| 1080p pausado | 345 | 322 | 5 |
| 1080p activo | 318 | 296 | 0 |
| 720p pausado | 237 | 216 | 1 |
| 720p activo | 234 | 214 | 1 |

La causa de los ceros con PID desconocido está confirmada: el script sólo leía
`go_pid` de `ready`, emitido después de la preparación. Esos ceros no eran
mediciones de memoria Go. Los siete ceros restantes están al final de sus
archivos; el formato antiguo también usaba cero cuando Get-Process no encontraba
el PID. **No hay prueba de la causa de cada uno**: salida de Go mientras el
lector procesa el final, fallo de consulta u otra condición requieren el nuevo
registro de estado/identidad. No se interpreta cero como servidor sin RAM.

Los dos campos de hardware (equipo y resumen) estaban fijados a falso. Godot y
stdout declaran **Intel Iris Xe**, OpenGL 3.3, driver **31.0.101.4575**; CIM registra
la misma GPU y un adaptador virtual Epson. CPU: **i5-1340P**, 16 lógicos, Windows
11 build 26200, RAM física 16.876.888.064 bytes. La coincidencia del adaptador
activo y el inventario verifica la identidad del hardware objetivo; no certifica
rendimiento sostenido. El adaptador Epson instalado no prueba que estuviera
activo o causara un problema.

La reproducción comienza en el arnés anterior durante sus 3 s de calentamiento:
la ventana medida empieza en años **1009 y 1011**, no en 1000. Esto está
confirmado por los eventos. No se comparan estados iniciales exactamente iguales.
Los 3,30/3,37 años/s incluyen el circuito Go → transporte → decoder → proyección
→ publicación y la contrapresión del observador. No son una medición aislada del
cálculo Go ni una conclusión sobre su cuello de botella.

## Hipótesis pendientes y discriminantes

- Contención provocada por deserialización/IO del arnés: comparar baseline,
  minimal y detailed, CPU del recolector, tiempo de sondeo y memoria privada.
- Espera en presentación, driver o compositor: ETW PresentMon debe mostrar si
  también desaparecen los eventos de display. El callback Godot solo no basta.
- Desprogramación, presión de memoria, procesos externos, energía o pérdida de
  foco: correlacionar UTC/QPC, muestras CPU/RAM, memoria disponible, foco y
  minimización; conservar plan de energía y estado de batería. Sin traza de
  scheduler no se podrá identificar con certeza un tercero específico.
- Trabajo de consulta, decoder/proyección/upload/publicación: observar tiempos
  de petición→recepción (incluyen varias etapas), `slow_poll`, proyección,
  upload y callback posterior. Si sigue ambiguo, repetir con `-StaticCamera
  -NoSelection` como experimento separado. No atribuir todo a Go ni a GPU.

La remedición aún debe ejecutarse en la Iris Xe. El paquete y las pruebas de CI
validan el arnés y el arranque; un runner Windows headless o llvmpipe no reemplaza
la captura en ese portátil. No se han cambiado simulación Go, RNG, contratos,
golden, referencia ni el cliente 3D; no se ha fusionado ninguna rama.
