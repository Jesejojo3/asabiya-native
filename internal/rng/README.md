# internal/rng

Hash UTF-16 y Mulberry32 de 32 bits implementados con vectores tomados del HTML intacto. Cada instancia guarda semilla original y contador uint64; Restore reconstruye la posición sin consumir sorteos previos. WorldSeed y HistorySeed mantienen los prefijos originales.

Diseño: [arquitectura](../../docs/phase-0/ARCHITECTURE.md).
