# Validación del arnés v2

Ejecutado localmente sobre Linux, Go 1.27.2 y Godot oficial
4.7.2.stable.official.ed1daf0bf:

- Ocho pruebas Python: archivo original y diagnóstico idénticos; ventana de
  muestra, pausas largas, errores/incompletos, verificación de GPU activa,
  presentación vs descartes, PID/swap chain, rechazo de deriva y agrupación por
  escenarios/repeticiones; staging de adaptadores byte por byte.
- PowerShell 7.4.6: lectura incremental de 10.000 líneas, bytes leídos exactamente
  una vez, UTF-8 cortado y línea parcial, ausencia como null, primer delta CPU y
  rechazo de identidad con otra hora de inicio; parser del script de benchmark.
- Contratos del observador: `ATLAS TESTS: 0 failures`, SHA Go directo tras tres
  años `84690d61334d4419eb103f893e88d4c64940a481ea403ff032d3bc7a219b8637`.
- Ventana Xvfb + llvmpipe: captura 1080p detailed y 720p minimal con tres años de
  preparación, 3 s de calentamiento y 3 s de medida activa. Ambos comienzan la
  muestra en −8997, mismo año preparado, y terminan con pausa exacta. Captura
  PNG 1920×1080 confirmada; sin errores de script/shader. Sin writes dentro de
  la muestra (`profiler_write_us_before_end=0`), buffer sin desbordamiento.

CI de esta PR ejecuta además PowerShell **5.1 en Windows**, identidad nativa por
ruta/padre/hora de creación, salida real del hijo, RAM disponible y foco de
ventana; build Windows con PresentMon fijado, manifiesto completo y prueba de
arranque del EXE exportado con SHA exacto. Los logs y artefactos de cada commit
están en Actions de la PR. Native Windows y Legacy golden son checks adicionales.

Las pruebas sintéticas de CSV validan análisis y descarte de datos inválidos;
no son una captura ETW real. El smoke Windows es headless. La validación de
display ETW, overhead y rendimiento en el portátil Iris Xe requiere ejecutar el
paquete según BENCHMARK.md y compartir la carpeta completa. No se presenta el
smoke por software como resultado nuevo de ese hardware ni como causa de las
pausas originales.

Alcance: diff de producción limitado al arnés dentro de experiments/atlas2d y su
workflow. Sin cambios de Go, RNG, contratos, golden, referencia o cliente 3D.
Base independiente sobre #27, sin merge ni cambios de main.
