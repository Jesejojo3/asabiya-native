# Comparación tecnológica y decisión

La elección de Godot 2D se fundamenta en integración comprobable, no en heredar el
renderizador 3D. No se afirma superioridad de FPS en el equipo objetivo.

| Criterio | Godot 2D | Go + Ebitengine | Web cartográfica |
|---|---|---|---|
| Reutilización verificada | BridgeSource/decoder/WorldData/MapLayers funcionan con datos reales; ocho fuentes exactas | Módulo ya fijado 2.10.5 y presentación provisional; API Go interna accesible | HTML v0.6 es oráculo protegido, no cliente neutral reutilizable sin port |
| Integración causal | Mismo proceso Go separado y TCP versionado, consultas/deltas/checkpoints existentes | Mantener servidor separado exige transporte/decoder/sesiones nuevos; importar sim directamente acopla cliente y motor aunque Go lo permita | Navegador no habla TCP loopback NDJSON directamente: hace falta puente HTTP/WebSocket, origen y lifecycle |
| Calidad | Shader 2D, tipografía/UI/cámara nativas; permite relieve y cartografía rica | GPU shaders/texturas viables; UI, texto, paneles, accesibilidad y herramientas por construir | SVG/Canvas/WebGL y UI rica; GIS maduro, pero nuevas bibliotecas/datasets/proyección, empaquetado y licencia por evaluar |
| Migración/mantenimiento | Cliente nuevo pequeño, puente existente compartido por staging; sin tocar 3D | Lenguaje único y binario cómodo; segunda implementación de contrato o refactor de adaptador Go antes de equivalencia | Nuevo stack y wrapper de escritorio/servidor; despliegue local más complejo que una ventana nativa |
| Rendimiento | Microprobe estático y cliente completo medibles; CPU/GPU objetivo pendientes | Microprobe estático equivalente ejecutable; backend integrado y coste UI no medidos | Sin prototipo ni medidas en esta misión; no atribuir rendimiento por reputación de librería |
| Futuro 3D | Datos Go neutrales y puente compartido con 3D actual | Mismos IDs y contrato posibles; Godot 3D necesitaría seguir manteniendo su puente | Backend neutral viable si se diseña; 3D existente no consume automáticamente bridge web |

## Microprototipos y alcance de la evidencia

`probes/fixture`: exporta mundo/historia reales, PNG físico y político, bundle y
SHA. `probes/ebiten`: ventana estática real Ebitengine. `godot/probe.gd`: misma
escena mínima. No se implementa una segunda simulación. Ver comandos, filtros y
trayectoria en BENCHMARK. El caso estático no representa coste de consultas,
publicación ni UI. Una diferencia de FPS en ese caso no decide por sí sola el
coste total de mantener el producto.

La opción web queda como evaluación arquitectónica, no benchmark ejecutado.
No se modifica HTML v0.6 para convertirlo en cliente. El adaptador neutral Go
hace reversible la selección; datos cartográficos/culturales permanecen en Go.

## Decisión ADR-A1

Elegir **Godot 2D Compatibility** para este primer slice. Se ha comprobado que el
adaptador existente mantiene sesiones, publicaciones consecutivas, pausa exacta
y SHA igual al Go directo. El coste necesario para alcanzar esas garantías en
Ebitengine/web incluye trabajo de integración ausente hoy. Shader/cámara/UI son
nuevos e independientes del terreno 3D; no se porta su geometría ni sus efectos.
La hipótesis de que cumplirá 30/60 FPS en Iris Xe debe verificarse con el kit.

Reconsiderar si una captura emparejada revela costes de Godot que impiden el
umbral pese a mejoras locales medidas, o si una alternativa demuestra la misma
integridad/UI/calidad con menor mantenimiento total. No cambiar por una cifra
estática aislada ni declarar ganadora una tecnología sin medir el cliente real.
Los resultados ejecutados se registran en VALIDATION y evidence, con límites.
