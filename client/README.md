# Asabiya Native — cliente 3D

Mapa histórico tridimensional en Godot 4.7.2 para Windows x64. Observa el mundo que genera el motor Go; no simula nada por su cuenta. [Arquitectura](../docs/client/ARCHITECTURE.md) · [API pedida al motor](../docs/client/API_REQUESTS.md).

## Compilar

```powershell
./client/tools/build-client.ps1
./build/client/AsabiyaNative.exe
```

Descarga Godot 4.7.2 y sus plantillas (SHA-256 fijados en `client/tools/godot-pins.txt`), compila `asabiya-snapshot.exe`, genera `worlds/Asabiya.asw` y exporta `build/client/AsabiyaNative.exe`. Requiere Go según `.go-version`. CI: `.github/workflows/client.yml`.

Opciones: `--snapshot RUTA`, `--seed TEXTO`, `--layer ID`, `--ui-scale F`, `--no-bridge`. Desde el menú *Mundo* se generan otras semillas y se ajustan calidad y exageración del relieve.

## Controles

Arrastrar: desplazar · rueda: zoom al cursor · botón derecho/central: girar e inclinar · WASD/flechas · Q/E, R/F · clic: provincia o asentamiento · Inicio: vista mundial · Ctrl+F: buscar · 1–9: mapas · Esc: quitar selección · F1: ayuda.

## Estado

| Funcionalidad | Estado |
|---|---|
| Terreno 3D real con relieve, costas, ríos, biomas, agua, sombras, LOD y costura | Integrado (datos reales) |
| Cámara de gran estrategia, niveles mundo → detalle | Integrado |
| Selección de provincias (CellID), resaltado, fronteras, panel provincial | Integrado; los campos históricos dicen «No disponible todavía» |
| Mapas de geografía, clima y recursos | Integrado (datos reales) |
| Mapas de Estados, guerras, pueblos, culturas, lenguas, religiones, población, K, tecnología, economía, rutas | Implementados; se activan cuando el motor envíe esos sistemas |
| Asentamientos y construcciones 3D, selección y panel | Implementados; dependen de asentamientos del motor |
| Nombres de territorios, crónica, marcadores, línea del tiempo, reproducción | Implementados; dependen de fotogramas del motor |
| Avance temporal del motor | Puente stdio implementado y probado con un doble de pruebas; falta `asabiya-bridge` en Go |
| Vegetación | Decorativa, derivada de bioma y `forest0` |

No hay datos históricos de demostración: la historia sólo llega desde Go.
