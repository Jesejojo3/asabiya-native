# Integración vigente

El cliente 3D original se conserva. Su transporte y carga activa fueron adaptados al servidor TCP real por autorización final del usuario. [Arquitectura y contrato actual](../integration/README.md). La propuesta stdio que aparezca más abajo es histórica y no está activa.

# Cliente 3D — arquitectura breve

Godot **4.7.2-stable** (Forward+, GDScript, sin .NET). Windows x64. La simulación vive sólo en Go; el cliente representa datos.

```
Go engine ──asabiya-snapshot──▶ .asw (geografía) ─┐
          ──asabiya-bridge (stdio, pendiente)──▶ HistoryFrame ─┤
                                                     ▼
WorldData / HistorySource ──▶ MapView (terreno, cámara, capas) ──▶ Hud
```

| Carpeta | Contenido |
|---|---|
| `client/exporter` | Exportador Go de snapshots; sólo API pública de `sim` |
| `client/godot/scripts/data` | `WorldData` (snapshot), `HistorySource` → `GeographySource`, `BridgeSource`; `HistoryFrame` |
| `client/godot/scripts/map` | `MapMath` (geometría compartida CPU/GPU), `TerrainRenderer`, `RiverBaker`, `MapLayers`, `SettlementLayer`, `VegetationLayer`, `HistoryOverlay` |
| `client/godot/scripts/camera` | `StrategyCamera` |
| `client/godot/scripts/ui` | `Hud`, `UiTheme` |
| `client/godot/shaders` | `map_common.gdshaderinc` (espejo de `MapMath`), terreno, agua |

## Decisiones

- **Geometría real.** 200 chunks de 80×80 unidades (1 unidad = 1 muestra fina ≈ 25 km) con 5 LOD (160…10 subdivisiones) elegidos por error proyectado en píxeles y faldones contra grietas. El vértice se desplaza en GPU con la elevación fina del motor (Catmull-Rom lejos de la costa, bilineal cerca, de modo que la línea de costa es exactamente la del motor) más microrrelieve procedural (crestas donde el gradiente real es fuerte). Exageración vertical configurable; no afecta a la simulación.
- **CPU = GPU.** Hash, ruido, deformación de fronteras y curva de alturas existen dos veces (`map_math.gd` y `map_common.gdshaderinc`). Selección (raycast contra el campo de alturas), colocación de objetos y dibujo usan la misma función; las pruebas lo comprueban.
- **Provincias = celdas del motor.** `CellID = y·400 + x`. Las fronteras se dibujan en el shader sobre la rejilla lógica con una deformación periódica para que no parezcan cuadros; no se inventan subdivisiones. La tierra fina dentro de una celda de mar se atribuye a su vecina de tierra (`land_remap`, hallazgo O1 de la auditoría).
- **Costura longitudinal.** Ruido periódico en X; chunks, mosaicos de instancias, agua y etiquetas se colocan en la copia más cercana a la cámara.
- **Estático vs dinámico.** Geografía: texturas finas subidas una vez. Historia: dos texturas de 400×200 (color y clave de grupo) por fotograma; ninguna geometría se regenera por cambios políticos. Asentamientos: instancias agrupadas en mosaicos de 80×80 con caché de disposición por id.
- **Entidades.** Asentamientos, Estados, pueblos, guerras, rutas y crónica sólo existen si el motor los envía (`HistoryFrame`). La disposición de edificios dentro de un asentamiento es presentación determinista por id; su existencia, tamaño y construcciones vienen del motor.
- **Decoración.** Árboles y rocas derivados del bioma y `forest0`; no seleccionables, sin efectos causales y desactivables. Se apartan de los asentamientos.
- **Rendimiento.** Calidad Alta/Media/Baja ajusta LOD, sombras, SSAO y alcance de la vegetación (construida en hilo, un mosaico por fotograma). Sin streaming.

## Pruebas

`tests/run_tests.gd` (headless): integridad del snapshot y rechazo de corrupción, periodicidad del ruido, costa preservada, cada centro de celda resuelve a su CellID, raycast, capas (las históricas vacías y deshabilitadas sin motor), ríos = celdas de río del motor, decodificación de fotogramas y el canal stdio completo contra el doble de pruebas. `tools/capture.sh` renderiza capturas bajo Xvfb.
