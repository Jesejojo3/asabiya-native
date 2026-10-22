# Resultados medidos y límites de la conclusión

**No hay una captura del i5-1340P/Iris Xe. No se acredita todavía el objetivo de
30 FPS sostenidos en ese equipo.** El paquete Windows incluye el kit para medirlo.

## Banco ejecutado

Linux, CPU Xeon Platinum 8573C, Xvfb 1920×1080, llvmpipe LLVM 19.1.7 / Mesa
25.0.7, Compatibility OpenGL. Renderizado **por software**, sin GPU física objetivo.
Godot 4.7.2 oficial ejecutando el proyecto desde fuentes; no es el export Windows.
Código de captura/runtime `197f46a242e2dea316ef500b359e07dc4898843a`.
Las correcciones posteriores de sesión, contador, cámara y lanzador no son una
optimización A/B del renderer; estas cifras no certifican ese build posterior.
Shader, capas compartidas y Go permanecen iguales.

Cuatro procesos/sesiones independientes y secuenciales: Asabiya/historia 1,
400×200, detalle 4, 10.000 años preparados hasta +1000. Zoom regional 4,
cámara sinusoidal y selección del centro cada segundo. 3 s warmup +10 s,
una repetición por caso. VSync se solicita desactivado, pero llvmpipe advierte
que no puede cambiarlo. Framebuffer, ventana y dimensiones del PNG comprobados.
Mapa útil: 1574×962 a 1080p; 934×567 a 720p. Ver valores exactos en ready.

Las cuatro sesiones llegan al mismo mundo
`04f336d80022d6e07f1ff9eb96559033742b98db9086164db781d2499675497f`
y al mismo SHA histórico inicial de medición:
`e7df456c262d6bf4f01918de79a8ff1b3eb8f736f347c7d5c3cf12e44d1c27e9`.
En reproducción se presentan años consecutivos; el avance en curso termina
antes de verificar el SHA de pausa. No se compara un SHA diferido como exacto.

| Caso | Frames | FPS P50 | Frame P50 / P95 / P99 (ms) | Frames >33,33 ms | Años/s |
|---|---:|---:|---:|---:|---:|
| 1080p pausa | 232 | 28,49 | 35,10 / 62,71 / 66,95 | 56,47% | 0 |
| 1080p activa máxima | 140 | 14,71 | 67,97 / 132,77 / 166,46 | 100% | 0,91 |
| 720p pausa | 528 | 71,32 | 14,02 / 38,35 / 42,63 | 14,39% | 0 |
| 720p activa máxima | 288 | 42,88 | 23,32 / 85,68 / 200,04 | 29,17% | 1,10 |

No son intervalos de presentación física del monitor: son `frame_post_draw`.
Los P99 de muestras tan cortas tienen poca estabilidad. La mediana de 71 FPS
a 720p no demuestra 30 sostenidos: hay frames lentos. No extrapolar a Iris Xe.

## Latencias y memoria

| Caso | Selección local P50/P95 ms | Selección hasta post_draw P50/P95 ms | Consulta Go P50/P95 ms | RAM observada Go+Godot, GB decimales |
|---|---:|---:|---:|---:|
| 1080p pausa | 0,60 / 0,97 | 34,76 / 60,52 | 34,93 / 60,53 | 3,86 |
| 1080p activa | 0,69 / 1,55 | 70,18 / 96,58 | No se consulta detalle en marcha | 3,72 |
| 720p pausa | 0,59 / 1,52 | 16,96 / 38,26 | 16,58 / 37,70 | 3,85 |
| 720p activa | 0,63 / 2,37 | 25,74 / 33,87 | No se consulta detalle en marcha | 3,78 |

Diez selecciones por caso. Memoria: máximos observados de RSS muestreado cada
500 ms, Godot y Go por separado y suma por instante; no sumar máximos ocurridos
en instantes distintos. Se incluye preparación para Godot, pero el PID Go sólo
se registra desde ready: su pico previo puede faltar. Páginas compartidas pueden
contarse dos veces; no es VRAM ni memoria privada exclusiva. No es RAM Windows.

| Actualización durante avance | Muestras | Proyección CPU P50/P95 ms | Subida P50/P95 ms | Recepción → post_draw P50/P95 ms |
|---|---:|---:|---:|---:|
| 1080p | 9 | 14,42 / 23,23 | 0,30 / 0,59 | 75,79 / 133,45 |
| 720p | 11 | 13,31 / 19,19 | 0,30 / 0,68 | 45,07 / 54,36 |

En pausa no hay cambios de mapa durante la muestra: no se inventa una latencia
cero para un evento que no ocurrió. Se muestra «sin muestras» en JSON.

## Qué queda demostrado

Reducir el área del mapa aproximadamente 2,86 veces reduce el frame mediano en
pausa de 35,10 a 14,02 ms (2,50 veces); con avance, de 67,97 a 23,32 ms
(2,91 veces). Es una sensibilidad fuerte a resolución/detalle **en rasterización CPU**.
Hay un factor que impide atribuirla sólo a píxeles: los puntos de ciudades reales
se activan a 10 píxeles por celda. En este zoom, 1080p tiene ~15,74 px/celda y
720p ~9,34; los puntos están habilitados sólo en 1080p. Las etiquetas (>20) no
lo están en ninguno. No se registró el número visible de puntos ni se ejecutó
un A/B que los aislara. Por tanto no es una prueba pura de fill rate ni demuestra
que la Iris Xe esté limitada por GPU. Al activar Go también
crece la cola de frames; aquí Go y el rasterizador compiten por CPU/memoria.
Se necesita perfilado del equipo real para separar esos costes.

La subida de textura medida (~0,30 ms P50) es muy inferior al frame mediano.
La proyección cuesta ~13–14 ms y se ejecuta en trabajador. El tiempo hasta
presentar el mapa incluye espera al siguiente frame. La consulta de selección
en pausa también sigue el orden de magnitud de la cadencia gráfica; no atribuir
sus 35 ms directamente al cálculo Go o a un bloqueo TCP sin instrumentación.

El nuevo renderer no usa terreno de malla, sombras 3D ni LOD geométrico. La
cartografía es una proyección 2D de campos Go con símbolos reales. No hay
medición emparejada del cliente 3D anterior y no se afirma haber «resuelto los
13 FPS» de ese cliente. No se han añadido cachés, regiones ni diferencias nuevas
basándose en una GPU virtual. El transporte ya negocia las diferencias existentes.

La retención de 24 publicaciones con entidades históricas es una hipótesis
plausible para parte de los ~3 GB de Godot. **No está aislada como causa.** Antes
de cambiarla: comparar retención y perfiles de asignación con el mismo estado,
conservar toda la historia Go, IDs, SHA y la revisión declarada del cliente.

## Próxima decisión con Iris Xe

Ejecutar `Medir rendimiento.cmd` (cuatro casos de zoom provincial) y después
`Medir completo.cmd` si procede (tres zooms, tres repeticiones, 30 s). Registrar
corriente/perfil térmico/energético/controlador. Revisar P95/P99, frames lentos,
latencia, RAM y años/s, además de FPS P50. Si hay límite, perfilar CPU principal,
decoder, Go y GPU/driver; aislar política/terreno/símbolos con igual cámara y
estado antes de optimizar. No incorporar Tierra ni detalle causal de edificios
para ocultar un problema de navegación.

Datos crudos, entorno, tamaños, hashes y resumen: `evidence/full-world/`.
Capturas inválidas iniciales conservadas aparte: `evidence/invalid-resolution/`.
Benchmark y fórmulas: BENCHMARK.md. Fuente y contrato no cambian por medir.
