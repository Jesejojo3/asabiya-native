# Solicitudes de API al motor Go (para Astra)

El cliente 3D (`client/godot`) no simula nada. Todo dato histórico debe venir del motor. Este documento propone el contrato; Astra decide la forma final. El cliente ya implementa el lado de lectura descrito aquí y lo prueba contra un doble de pruebas (`client/godot/tests/mock_bridge.py`), que no es una simulación ni se distribuye.

## 1. Ya disponible (sin cambios en `internal/sim`)

`client/exporter` (`asabiya-snapshot`) lee sólo la API pública (`World.Cell`, `Surface.At`) y escribe `asabiya/snapshot-v1`: cabecera JSON + capas binarias little-endian. Capas por celda: tierra, costa, bioma, elevación, clima, drenaje (`down`, acumulación, río), aptitudes y `prepEco`. Capas finas 1600×800: elevación, temperatura, precipitación. Digest = `World.Digest()`; CI lo compara con el golden v2.

## 2. Puente local `asabiya-bridge/v1`

Proceso hijo `asabiya-bridge.exe --stdio` junto al cliente. Una petición JSON por línea en stdin, una respuesta por línea en stdout (stderr libre para registros). Cada respuesta lleva el `id` de la petición.

| Petición | Respuesta |
|---|---|
| `{"cmd":"hello","protocol":"asabiya-bridge/v1"}` | `{"ok":true,"engine":"…","canAdvance":bool}` |
| `{"cmd":"open","seed":S,"historySeed":H,"worldDigest":D}` | `{"ok":true,"year":Y}` o error si el digest no coincide |
| `{"cmd":"frame"}` | `{"ok":true,"frame":FRAME}` |
| `{"cmd":"advance","years":N}` | `{"ok":true,"frame":FRAME}` (año resultante) |
| `{"cmd":"close"}` | sin respuesta; el proceso termina |

Errores: `{"id":…,"ok":false,"error":"texto"}`. Eventos espontáneos opcionales: `{"event":"texto"}`.

`canAdvance` debe ser `false` hasta que `AdvanceYear` exista y esté completo; el cliente deshabilita entonces los controles de avance.

## 3. FRAME

```json
{
  "year": -3000,
  "systems": ["states","peoples","religions","population","carrying","technology","economy",
              "settlements","wars","events","routes"],
  "worldPopulation": 1234567,
  "cells": {
    "owner": "<base64 int32[W*H], -1 = sin Estado>",
    "people": "<base64 int32[W*H], -1 = deshabitada>",
    "religion": "<base64 int32[W*H]>",
    "population": "<base64 float32[W*H]>",
    "carrying": "<base64 float32[W*H]>  (K)",
    "technology": "<base64 float32[W*H], 0..1>",
    "wealth": "<base64 float32[W*H], 0..1>"
  },
  "states":   [{"id":0,"name":"…","rgb":[r,g,b],"kind":"state|horde","capital":CellID,"capitalName":"…",
                "ruler":"…","dynasty":"…","cohesion":0.7,"founded":-3200,"history":["…"]}],
  "peoples":  [{"id":0,"name":"…","rgb":[r,g,b],"family":3,"familyName":"…","language":"…",
                "cultureName":"…","homeland":"…"}],
  "religions":[{"id":0,"name":"…","rgb":[r,g,b],"founded":-2500}],
  "settlements":[{"id":1,"cell":CellID,"name":"…","tier":0-4,"population":40000,"founded":-3500,
                  "state":0,"era":0-7,"features":{"walls":true,"castle":false,"temple":true,"port":true,"market":true}}],
  "events":   [{"year":-3010,"kind":"war|founding|collapse|plague|innovation|migration|…","text":"…","cell":CellID}],
  "wars":     [{"id":1,"a":0,"b":1,"started":-3010,"front":[CellID,…]}],
  "routes":   [{"id":1,"cells":[CellID,…],"volume":0.0-1.0}]
}
```

Reglas: cualquier campo puede faltar; el cliente muestra «No disponible todavía» en vez de inventarlo. Una capa por celda con tamaño distinto de W×H se descarta. `systems` controla qué mapas se habilitan.

## 4. Pendiente en el motor, por prioridad

1. `AdvanceYear`/`stepG` completo y el puente anterior (aunque sea sólo `frame` del año inicial tras `newHistory`).
2. Vistas por valor de propietario, pueblo, religión, población y K por celda (ya existen en el estado interno de la rama de integración).
3. Entidades `states`/`peoples`/`religions` con nombre y color estables (el legado tiene `rgb`).
4. Nombres de lugar por celda (`placeName`), para títulos de provincia y etiquetas.
5. Ciudades/asentamientos con tamaño y, después del port v0.6, construcciones como mecánica nueva (murallas, fortalezas, templos, puertos, mercados, caminos, puentes). El renderizador ya tiene modelos y ranuras para ellas.
6. Historia territorial por celda (cambios de propietario con año) y crónica (`chronicle`).
7. Guardado/reanudación: un `frame` reproducible por año permitiría al cliente cachear la línea del tiempo.
