# internal/sim

Bloques 1–2: mundo procedural, clima, agregación, geometría esférica, vecinos/costas/masas, drenaje, aptitud ecológica, viajes, enlaces marítimos, interpolación 40×20 y prepEco. World es inmutable y las consultas devuelven valores/copias. Surface opcional conserva el detalle visual fuera de World, sin dependencias de render. Simulation sigue sin población y no tiene AdvanceYear.

Pendiente: recursos Tierra/importados y ajuste Köppen, nombres/lenguas, newHistory, población, capacidad de carga, tecnología y calendario anual. La malla meteorológica aquí es geometría/índices/pesos, no inicialización aleatoria AG ni weather anual. No sustituir capacidad de carga por constantes. Go math, native/world-v2; proyección congelada v1 para conservar el golden anterior.

Diseño: [arquitectura](../../docs/phase-0/ARCHITECTURE.md).
