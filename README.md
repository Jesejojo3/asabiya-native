# Asabiya Native

Motor histórico en Go para Windows x64 y cliente 3D en Godot 4, incorporando el trabajo independiente de Claude. Go conserva toda la autoridad de la simulación. Ebitengine permanece como visor provisional.

Esta es la rama de integración `integration/go-godot-windows`: conserva los commits de PR #6/#7 y PR #8, sin merge a main. El HTML original, el tag legacy-v0.6 y los golden anteriores se preservan.

El código integra calendario anual, demografía, culturas/lenguas, tecnologías, ecología, epidemias, religiones, ciudades, comercio, Estados, gobernantes, sucesión, diplomacia, guerras, migraciones, colapsos, presagios y cataclismos. Incluye las ramas Tierra/importación/clima ajustado y las consultas históricas disponibles. Usa math de Go; no promete paridad bit a bit con V8.

El cliente conserva el terreno 3D fino, cámara, LOD, vegetación y materiales de Claude, y consume el servidor TCP local de Go. Arranca el servidor y obtiene el puerto automáticamente. Las publicaciones históricas no reconstruyen la geografía.

## Abrir la entrega

Abre `AsabiyaNative.exe` en la carpeta Windows entregada. No necesitas instalar Go/Godot ni configurar puertos. La historia comienza con pueblos fundadores; usa el selector de años para observar la aparición de Estados y ciudades.

**Reproducción:** inicia en Máxima, muestra todos los años y comprueba automáticamente el estado cada 25 años y al pausar. No requiere seleccionar un modo. La base tiene regresiones previas documentadas; los cambios de Fase 2 sólo tienen revisión estática y requieren nueva validación en Windows. [Cambio y mediciones](docs/integration/FLUID_PLAYBACK.md).

El núcleo reduce cálculos repetidos de vecindad y recorre sólo tecnologías conocidas, conservando los resultados anteriores. [Optimización de algoritmos y comparación de campañas](docs/integration/CORE_ALGORITHMS.md).

## Reconstruir

Requiere Go **1.27.2 Windows amd64** y Godot **4.7.2 estable**. Las herramientas y hashes están fijados. El script puede obtener el editor y las plantillas oficiales:

```powershell
./tools/package-windows.ps1
```

Produce `build/client/`, incluidos cliente, servidor, herramientas opcionales, configuración y manifiesto de hashes. El script no ejecuta el juego ni tests.

- [Integración y contrato activo](docs/integration/README.md)
- [Entrega y comprobaciones del usuario](docs/integration/HANDOFF.md)
- [Decisiones](docs/integration/DECISIONS.md)
- [Tierra, importaciones y clima](docs/mission/WORLD_INPUTS.md)
- [Inventario del port original](docs/mission/PORT_INVENTORY.md)
- [Contrato geográfico y API histórica](docs/mission/GODOT_CONTRACT.md)
- [Referencia inmutable y Fase 0](docs/phase-0/README.md)

Guardar/restaurar una partida completa mediante snapshot sigue siendo una función nativa futura. El replay reconstruye la simulación ejecutando sus comandos; el historial visual comprimido no es un guardado rápido.

**Fase 2 del cliente 3D:** [auditoría estática](docs/performance/GODOT_FRAME_AUDIT.md) e [implementación, compilación y validación pendiente](docs/performance/GODOT_FRAME_IMPLEMENTATION.md).
