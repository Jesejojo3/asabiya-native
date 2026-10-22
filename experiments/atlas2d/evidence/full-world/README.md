# Captura completa aceptada para diagnóstico de integración

Runtime: `197f46a242e2dea316ef500b359e07dc4898843a`, Linux/Godot oficial en modo
proyecto, llvmpipe software. No Windows export ni Iris Xe. Escenario Go completo,
+1000, 400×200 detalle 4, zoom 4, 3 s warmup +10 s, una repetición. Los cuatro
ready tienen el mismo SHA inicial. Tamaños de ventana/framebuffer/PNG verificados.

Cada JSONL contiene entorno, PID real, ready, frames, latencias y pausa exacta.
`.memory.jsonl` contiene RSS de los procesos. No confundir la memoria estática de
Godot con RSS. Go sólo está identificado desde ready: el pico anterior puede
no estar cubierto. Los hashes de PNG conservados en manifest corresponden a las
capturas originales en build/atlas2d/verified-diagnostic del workspace; los PNG
no se necesitan para recalcular el resumen numérico.

Para resumir, pasa los cuatro JSONL de aplicación a tools/summarize.py,
**excluyendo** los cuatro `.memory.jsonl`. `summary.json` agrega el ready a cada
fila para facilitar la revisión. No es un golden de rendimiento ni un umbral CI.

Interpretación, factor de símbolos por escala y límites: docs/PERFORMANCE.md.
Los últimos cambios de controles/cámara no se presentan como una mejora medida
respecto a este commit. Medir el paquete final en el hardware objetivo antes de
atribuirle cualquier cifra de esta carpeta.
