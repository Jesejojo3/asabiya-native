# Capturas descartadas para comparar resoluciones

Los cuatro intentos iniciales procedían del código de aplicación de `a64df15`.
Su manifiesto se generó antes del commit y registra la base `79035761`; se
compararon los siete archivos de runtime staged contra a64df15 y eran idénticos.
DisplayServer.window_set_size cambió el tamaño solicitado/nativo, pero el
viewport conservó 1280×720. Se detectó inspeccionando el PNG, no por los FPS.

Se conservan JSONL crudos comprimidos y hashes/dimensiones de los PNG originales
(en build/atlas2d/diagnostic del workspace). **No utilizar sus nombres 1920x1080
como evidencia de 1080p**, ni comparar esas filas como dos resoluciones.

Los valores adelantados de 64,51/46,48/68,49/47,46 FPS P50 corresponden a estos
intentos inválidos para esa comparación. No forman parte del resultado aceptado.
El código posterior usa Window.size y valida ventana + textura del viewport;
el runner valida además IHDR del PNG. summarize.py rechaza las capturas Atlas
sin la validación del framebuffer.
