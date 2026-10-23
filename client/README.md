# Cliente 3D

Cliente original de Claude conservado y adaptado al motor Go de PR #7. La integración definitiva usa un único servidor TCP local, asabiya/local-v1; no usa el protocolo stdio propuesto en PR #8.

```powershell
./client/tools/build-client.ps1
# Abre después build/client/AsabiyaNative.exe para tus comprobaciones.
```

El script sólo compila/exporta; no lanza el cliente ni ejecuta tests. La aplicación inicia Go y genera el mundo automáticamente. El terreno fino, cámara, LOD, vegetación y shaders se conservan. Cambiar propietarios o población actualiza capas históricas, sin reconstruir la malla.

El exportador/lector .asw permanece como herramienta heredada; el arranque normal carga geography-v1 desde el mismo servidor que simula la historia.

[Contrato y decisiones](../docs/integration/README.md), [testeo del usuario](../docs/integration/HANDOFF.md), [configuración de Tierra/importación](../docs/mission/WORLD_INPUTS.md).
