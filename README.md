# Asabiya Native

Port incremental de Asabiya History Engine v0.6 a Go + Ebitengine, para uso personal en **Windows x64**.

Estado: Fase 0 integrada en `2bbefb70959bc0648dbf29b08b17e814ff287625`. Tag `legacy-v0.6` verificado en el commit de importación `fe58bdb2ccf4db83857b02d16fa1852b54836824`. **Fase 1: primer bloque nativo para revisión, sin merge autorizado.**

Ya genera terreno procedural, clima inicial, costas y masas de tierra; exporta un informe JSON y un PNG, consulta celdas y ofrece una ventana mínima con Ebitengine. La sesión está explícitamente **sin población**: aún no avanza años ni crea pueblos, estados o guerras. Ver [alcance y decisiones actuales](docs/phase-1/README.md).

## Compilar y ejecutar

Requisitos: Go **1.27.2** para Windows amd64; Ebitengine **2.10.5** fijado en `go.mod`/`go.sum`. No requiere compilador C. El script de compilación exige la versión exacta y fija `GOAMD64=v1`, `CGO_ENABLED=0`.

```powershell
./tools/build-native.ps1
./bin/asabiya-headless.exe --seed Asabiya --history-seed 1 --cell 200,100 --out world.json --png world.png
./bin/asabiya.exe --seed Asabiya
```

La ventana muestra el terreno con colores de clima/elevación; Esc la cierra. No hay todavía paneles, cámara ni controles temporales. El JSON es un informe de inspección, **no un guardado reanudable**.

```powershell
go test ./...
go vet ./...
./tools/check-native-repro.ps1
```

El generador usa `math` de Go: no se exige paridad bit a bit con V8. El golden nativo es independiente de los fixtures originales. Cambios de CPU o toolchain requieren investigar cualquier discrepancia, no regenerar referencias automáticamente. [Validación y limitaciones](docs/phase-1/VALIDATION.md).

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
