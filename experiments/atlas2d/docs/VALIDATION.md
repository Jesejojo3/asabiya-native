# Evidencia y límites

Base #21 verificada. Ningún cambio en motor, protocolo, HTML, golden, 3D ni
art direction. La prueba headless del observador frente a Go directo pasó:
48×24, detalle 4, semilla Asabiya/historia 1, tres años hasta −8997, SHA exacto
`84690d61334d4419eb103f893e88d4c64940a481ea403ff032d3bc7a219b8637`.
Prueba publicaciones consecutivas, pausa exacta, inmutabilidad de frames,
consulta ID/propietario/población/año, carga de capa, revisión sin rebobinar Go
y wrapping/picking. Tres pruebas Python de staging/hashes y resumen pasaron.

Compilación local: export release Windows x64 con plantilla oficial verificada;
Go server x64/v1 CGO0. Este build cruzado no equivale a ejecución Windows.
Godot Linux 4.7.2 oficial, llvmpipe/Mesa 25.0.7, CPU Xeon Platinum 8573C:
smoke gráfico y captura inspeccionada manualmente, terreno/panel visibles.
Es integración en software, **no** medición de Iris Xe.

En el SHA `197f46a`, CI Atlas (Linux + Windows), Native Windows x64 y Legacy
reference están en verde. La ejecución Windows incluye prueba del observador y
arranque/avance/pausa del ejecutable release exportado. Es prueba funcional
headless: no valida GPU ni apariencia de una ventana Windows.

También se comprobó preparación explícita de 3 años +3 pasos normales en el
mundo pequeño: SHA `9503b72061975381d65cb1676a857ad15fde36544f19585497a8027ef16b714c`,
igual a seis años en Go directo. La aplicación bloquea pasos/reinicio durante
preparación; permite pausar. El adaptador compartido queda intacto.

Las primeras capturas se descartaron para comparar resoluciones: el framebuffer
seguía en 1280×720 al usar DisplayServer.window_set_size. Datos y explicación en
`evidence/invalid-resolution`. Se corrigió con Window.size, validación del
framebuffer y comprobación IHDR del PNG en CI/runner. No se sustituyen esas
cifras por una afirmación de mejora: era un fallo del método de captura.

Comparativa corregida completa: 400×200 detalle 4, 10000 años preparados,
1080p/720p reales, zoom regional 4, pausa/activo, warmup 3 s +muestra 10 s.
Datos crudos y hashes en evidence/full-world; cifras y análisis en PERFORMANCE.md.
Runtime de esa captura: 197f46a; cambios posteriores de controles/cámara no se
presentan como una mejora medida. La matriz objetivo completa de tres zooms,
tres repeticiones y 30 s se entrega reproducible; sigue sin ejecutarse en Iris Xe.
Tampoco se comparó de forma emparejada con el antiguo renderer 3D.
