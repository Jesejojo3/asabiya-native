# Asabiya Atlas 2D — Misión A

Prototipo experimental Windows x64, motor Go real. Mundo **procedural**; no es la Tierra.
Base: PR #21 `79035761f1e61041a3ccbf74b648577e53ba7150`. Dirección: PR #26
`10258dd16763a92e5ad0c5194f0e600e827ecad5`. Ninguna PR se integra.

## Ejecutar sin programar

1. Descarga el artefacto `asabiya-atlas2d-windows-x64` de Actions de esta PR.
2. Extrae **toda** la carpeta ZIP. Abre `AsabiyaAtlas2D.exe`.
3. Opcional: abre `Abrir historia avanzada.cmd` para que Go calcule 10.000 años
   antes de explorar (+1000 en el calendario del motor). Puede tardar varios
   minutos; muestra progreso y se puede pausar. No inventa sociedades ni salta
   cálculos causales. En esa preparación se muestran publicaciones cada 100
   años; la reproducción normal conserva cada año.
4. Espera a que Go cree el mundo y aparezca el año. No necesita Godot, Go ni Python instalados.
5. Arrastra el mapa; usa rueda o Mundo / Región / Provincia para acercarte.
6. Selecciona una provincia. Cambia Política por Población, Pueblos, Cultura o Biomas.
7. Usa +1 año o Reproducir. Máximo solicita años sin espera artificial; presenta cada año recibido.
8. Pausar detiene solicitudes y verifica el SHA del último año completo. Una solicitud en curso acaba atómicamente.
9. El selector de años revisa hasta 24 publicaciones retenidas; **no rebobina Go**.

Nueva sesión vuelve a generar el mundo con la semilla escrita. La sesión actual no
se guarda automáticamente. Cerrar finaliza el proceso Go propiedad de esta ventana.
Los logs están en `%APPDATA%/AsabiyaAtlas2D/sessions`.

Las fechas iniciales y los nombres proceden de Go. Una celda sin estado o pueblo
se muestra como tal. Cultura son seis componentes numéricos reales; el color usa
los tres primeros, sin inventar nombres. La población es provincial, nunca censo
urbano. Los puntos de ciudad, cuando existen, identifican ciudades reales de Go.
No se dibujan edificios ni ruinas inventados.

## Medir

El nuevo arnés y el diagnóstico de la captura real Iris Xe están en
`docs/BENCHMARK.md` y `docs/WINDOWS_MEASUREMENT_DIAGNOSIS.md`. Descarga el paquete
**asabiya-atlas2d-measurement-windows-x64** de esta PR, extrae todo y ejecuta
`Medir rendimiento.cmd`: cuatro escenarios, tres modos de instrumentación y
**tres repeticiones**, 36 ejecuciones con preparación nueva de 10.000 años y
30 s de medida cada una. `Medir completo.cmd` añade tres zooms, 108 ejecuciones.
La captura incluye PresentMon, CPU/RAM e identidad de procesos; el resumen requiere
Python, la captura no. La Iris Xe original está identificada; su rendimiento
presentado y las causas de las pausas siguen pendientes de remedición.

## Desarrollar

Herramientas fijadas por el repositorio: Go 1.27.2, Godot 4.7.2 oficial, Python 3.12+.
Los hashes oficiales permanecen en `client/tools/godot-pins.txt`.

```sh
python experiments/atlas2d/tools/stage.py
go build -o build/bin/asabiya-server ./cmd/asabiya-server
godot --headless --path build/atlas2d/project --import
godot --path build/atlas2d/project -- --server=/ruta/absoluta/build/bin/asabiya-server
```

En Windows, usa `asabiya-server.exe`. Para generar el paquete con la plantilla
oficial `windows_release_x86_64.exe` ya extraída del TPZ verificado:

```sh
python experiments/atlas2d/tools/build.py --godot /ruta/godot --go /ruta/go --template /ruta/windows_release_x86_64.exe
```

No edites `build/`: se genera. El proyecto toma ocho adaptadores existentes
byte por byte y anota sus hashes. Los fuentes del cliente 3D quedan intactos.

Documentación: `docs/AUDIT.md`, `docs/ARCHITECTURE.md`, `docs/TECHNOLOGY.md`,
`docs/SYSTEMS.md`, `docs/BENCHMARK.md`, `docs/PERFORMANCE.md`,
`docs/VALIDATION.md`, `docs/OWNER_GUIDE.md`.
