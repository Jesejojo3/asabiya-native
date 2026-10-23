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

## Regresión del cierre de escenarios en Windows PowerShell 5.1

El fallo posterior a `1920x1080-zoom24-activeFalse-baseline-r1` procedía de
`@($prefix+'.stdout.log',$prefix+'.stderr.log')`: la coma se agrupa antes que
la suma y termina formando una sola ruta. El arnés ahora construye `stdoutLog`
y `stderrLog` por separado con `Join-Path`; reutiliza esas rutas tanto al
redirigir el proceso como al inspeccionar sus logs después de esperar su salida.

Auditoría del resto de `benchmark.ps1` y `telemetry.ps1`: no hay otra lista con
esa combinación de suma y coma sin paréntesis, ni operadores o parámetros
exclusivos de PowerShell 7. Las otras expresiones de suma en listas ya estaban
entre paréntesis. Los accesos al paquete, manifiesto, JSONL y logs usan ahora
`-LiteralPath` para evitar interpretación de patrones en esos cmdlets. Se
conservan los handles originales de lanzamiento y las comprobaciones de salida,
identidad, pausa, integridad y errores de ejecución.

La auditoría por ejecución detectó además una limitación de `Start-Process`:
interpreta sus redirecciones como patrones y no ofrece `-LiteralPath`. Con
corchetes en la ruta del paquete falla antes del preflight; la resolución se
repite internamente y escapar la ruta tampoco basta. La regresión usa una
carpeta con espacios, sin corchetes. Extraer el paquete en una ruta sin `[` ni
`]`. Esta limitación del cmdlet no se confunde con el fallo corregido de la lista
concatenada, que la prueba reproduce expresamente al final.

El workflow ejecuta `tests/test_benchmark.ps1` mediante **powershell.exe 5.1**
después de construir el paquete. La prueba copia el paquete a una carpeta con
espacios, sustituye únicamente los dos ejecutables productores en
esa copia por procesos nativos C# y regenera su manifiesto de prueba. Usa el
script empaquetado completo, PresentMon 2.3.0 real con su hash fijado, preflight
ETW, identidad por PID/ruta/padre, telemetría, cierre, inspección de ambos logs,
limpieza y resumen Python real. No se simula `Select-String` ni se omite el
flujo de producción.

El lanzador de pruebas añade sólo a la captura PresentMon de los productores
sintéticos `--timed 4 --terminate_after_timed`: esos procesos de consola viven
3,3 s y no generan swap chains, por lo que PresentMon no los registra para
terminar por salida de un proceso que presenta. El preflight no se modifica.
La captura ETW sigue siendo real; no se falsean hashes, identidades, resultados
de cmdlets ni logs. El arnés y el paquete distribuido conservan
`--terminate_on_proc_exit` y sus comprobaciones de salida.

- Cuatro escenarios × tres modos, una repetición: 12 capturas completas.
- Cuatro escenarios baseline × dos repeticiones: ocho capturas completas;
  comprueba un único modo y el orden invertido de la segunda repetición.
- Inyección de `SCRIPT ERROR`, `SHADER ERROR` y `Parse Error` en cada stream:
  seis rechazos que identifican el log correcto y conservan el diagnóstico.
- Restauración temporal de la expresión defectuosa sólo en la copia de prueba:
  debe fallar en el primer escenario y mencionar ambas rutas concatenadas.

La evidencia de cada invocación incluye `suite.jsonl`, crudos, telemetría, logs
y resúmenes, dentro de `atlas2d-windows-contract-evidence`. Las capturas de los
productores C# son sintéticas y no prueban FPS, historia Go ni rendimiento de
Iris Xe. El paquete distribuido conserva los ejecutables reales y su manifiesto
se verifica de nuevo después de estas pruebas.
