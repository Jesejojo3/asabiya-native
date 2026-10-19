# Paquete manual para revisión independiente — Fase 1

Implementación por Codex; revisión prevista por Claude, transportada manualmente por el usuario. No hay comunicación automática ni aprobación de Claude afirmada para esta entrega.

Base: main `2bbefb70959bc0648dbf29b08b17e814ff287625`. Rama `phase-1/native-world`. Ver alcance, ADR-010–015 y límites en README.md de esta carpeta; resultados y pendientes en VALIDATION.md. No integrar sin autorización explícita del usuario.

## Revisión propuesta

1. Verificar `legacy-v0.6^{commit}` = `fe58bdb2ccf4db83857b02d16fa1852b54836824`, la ejecución del bootstrap y su retirada del árbol final. La tarea temporal fue expresamente autorizada; no debe quedar CI permanente con escritura.
2. Verificar el SHA-256 del HTML, y que `git diff 2bbefb7 HEAD -- reference/ docs/phase-0/evidence/ tools/reference-smoke.mjs tools/verify-reference.mjs tools/check-reference-golden.mjs` está vacío. Ningún fixture se cambia para disimular divergencias.
3. Contrastar RNG con líneas 383–384, ruido con 391–406, clima con 407–410/425–467 y genWorld parcial con 522–582. Revisar promociones float32→float64, muestreo original, consumo de sorteos, cadencia de interpolación, hemisferios, costura y BFS vivo. Go math está autorizado y no se exige paridad V8.
4. Comprobar arrays privados/vistas por valor, centinela CellID −1, ausencia de dependencias de render/reloj en sim/rng y RNG histórico independiente. No atribuir mecánicas anuales a una sesión sin población.
5. Ejecutar en Windows amd64 Go 1.27.2: `go mod verify`, `go vet ./...`, `go test -count=1 ./...`, `./tools/build-native.ps1`, `./tools/check-native-repro.ps1`. Investigar cualquier fallo de golden sin regenerarlo.
6. Revisar ambos ejecutables/artifacts. La compilación Ebitengine y el PNG no prueban una ventana real: registrar GPU/DPI/resize/Esc al probarla. No hay aún decisión de widgets ni concurrencia anual.
7. Identificar errores dentro del alcance y dependencias que deben portarse antes de población/estados/guerras. No convertir la revisión de este bloque en exigencia de toda la migración o jsmath.

Solicitar veredicto, hallazgos reproducibles con archivo/línea, impacto y pruebas ejecutadas/pendientes. No aprobar merge mediante mensajes automáticos entre agentes; entregar el informe al usuario.
