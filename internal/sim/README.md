# internal/sim

Primer bloque implementado: mundo procedural, clima inicial, agregación, vecinos, costas y masas de tierra. World es inmutable; sus consultas devuelven valores sin acceso a los arrays privados. Simulation conserva mundo, semilla histórica, año inicial y RNG independiente; la sesión aún está sin población y no tiene AdvanceYear.

Pendiente: drenaje/ríos, aptitud ecológica, enlaces marítimos, recursos Tierra/importados, newHistory, tecnología y calendario anual. No sustituir capacidad de carga por constantes al incorporarlos. Go math y versión native/world-v1, sin exigir igualdad V8.

Diseño: [arquitectura](../../docs/phase-0/ARCHITECTURE.md).
