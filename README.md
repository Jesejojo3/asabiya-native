# Asabiya Native

Port incremental de Asabiya History Engine v0.6 a Go + Ebitengine, para uso personal en **Windows x64**.

Estado: Bloques 1–2 integrados (último merge `714d06c3a9d3ce9d69dbb184161a99b2c78e82f1`). Tag `legacy-v0.6` conservado en `fe58bdb2ccf4db83857b02d16fa1852b54836824`. **Fase 1, Bloque 3 para revisión; no integrar automáticamente.** [Issue #5](https://github.com/Jesejojo3/asabiya-native/issues/5).

Ya genera terreno y clima procedural, drenaje/ríos, geometría esférica, biomas, aptitud agrícola/pastoral, costes de viaje, enlaces marítimos y ecología inicial. Exporta JSON/PNG, consulta celdas y ofrece un viewport fino en Ebitengine. Bloque 3: lenguas y nombres, `newHistory`, pueblos fundadores, población inicial y capacidad de carga (`asabiya-headless --peoples`). Todavía no avanza años ni crea estados o guerras. [Bloque 3](docs/phase-1/BLOCK3.md); [Bloque 2](docs/phase-1/BLOCK2.md); [Bloque 1](docs/phase-1/README.md).

## Compilar y ejecutar

Requisitos: Go **1.27.2** para Windows amd64; Ebitengine **2.10.5** fijado en `go.mod`/`go.sum`. No requiere compilador C. El script de compilación exige la versión exacta y fija `GOAMD64=v1`, `CGO_ENABLED=0`.

```powershell
./tools/build-native.ps1
./bin/asabiya-headless.exe --seed Asabiya --history-seed 1 --cell 200,100 --out world.json --png world.png
./bin/asabiya-headless.exe --seed Asabiya --png world-fine.png --high-res
./bin/asabiya.exe --seed Asabiya
```

La ventana conserva las capas finas 1600×800 y muestra una textura de clima/elevación; Esc la cierra. No hay todavía overlays fluviales, paneles, cámara ni controles temporales. El JSON v2 incluye drenaje/ecología y enlaces marítimos de la celda consultada; **no es un guardado reanudable**.

```powershell
go test ./...
go vet ./...
./tools/check-native-repro.ps1
```

El generador usa `math` de Go: no se exige paridad bit a bit con V8. El golden v1 se conserva como proyección congelada; el nuevo golden v2 cubre todas las capas de geografía/ecología. Cambios de CPU o toolchain requieren investigar cualquier discrepancia, no regenerar referencias automáticamente. [Validación del Bloque 2](docs/phase-1/BLOCK2_VALIDATION.md).

## Referencia conservada

- [Entrega y alcance de Fase 0](docs/phase-0/README.md)
- [Arquitectura propuesta](docs/phase-0/ARCHITECTURE.md)
- [Inspección del motor JavaScript](docs/phase-0/SOURCE_AUDIT.md)
- [Paquete de auditoría para Claude](docs/phase-0/CLAUDE_REVIEW.md)
- [Pruebas realizadas y pendientes](docs/phase-0/VALIDATION.md)

Comprobaciones locales con Node, sin instalar paquetes:

```sh
node tools/verify-reference.mjs
node tools/reference-smoke.mjs
```

El HTML y todos los fixtures de Fase 0 permanecen intactos. Sus documentos describen la auditoría histórica; las decisiones actuales de implementación están en `docs/phase-1/`.

Correcciones de primera auditoría: [matriz de hallazgos](docs/phase-0/AUDIT_FINDINGS.md) y [validación correctiva](docs/phase-0/CORRECTION_VALIDATION.md).

Alcance aprobado: uso personal **Windows x64**, Go + Ebitengine. `native` usará inicialmente `math` de Go, sin paridad bit a bit obligatoria con V8; `v06-compat` y los fixtures originales permanecen como referencia diagnóstica. Linux es diagnóstico opcional, no CI bloqueante.
