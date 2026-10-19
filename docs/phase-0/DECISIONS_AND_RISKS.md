# Decisiones, riesgos y pendientes

## Registro de decisiones

| ID | Decisión / estado | Motivo y consecuencia |
|---|---|---|
| D01 | Adoptada: referencia completa e inmutable | Se copia el HTML byte a byte; importación aislada en `fe58bdb2ccf4db83857b02d16fa1852b54836824`, con hashes y atributos Git. No editarlo para probar. |
| D02 | Adoptada: sólo rama y PR | `main` permanece en su estado previo; integración y tag necesitan aprobación. Preservar commits de importación al integrar. |
| D03 | Propuesta: Go + Ebitengine con core sin render | Dos ejecutables futuros comparten simulación; UI no altera RNG ni orden. Sin ventana ni código Go todavía. |
| D04 | Propuesta: compatibilidad antes de balance | Reproducir el comportamiento de v0.6 y sus dependencias; mecánicas nuevas en otra fase y PR. |
| D05 | Propuesta: datos versionados e IDs estables | Extraer tablas sólo con pruebas; no renumerar tecnologías, entidades ni eventos. |
| D06 | Propuesta: orden secuencial y numericidad JS explícitos | Evitar reordenamiento, concurrencia o RNG por sistema antes de equivalencia. |
| D07 | Adoptada: auditoría independiente por entrega manual | Implementador GPT-6 Astra/Codex; auditor previsto Claude Opus 5.5/Claude Code. Son roles solicitados, no afirmación del modelo actualmente ejecutándose ni de disponibilidad externa. |
| D08 | Pendiente: toolchain, versiones y objetivos de rendimiento | Se fijarán tras aprobar Fase 1 y comprobar compilación Windows; no hay números de velocidad prometidos. |

## Riesgos y tratamiento

| ID / gravedad | Riesgo respaldado por inspección | Tratamiento / prueba pendiente |
|---|---|---|
| R01 Alta | Float32 en arrays + float64 en fórmulas, RNG compartido, sort y Map/Set | Vectores numéricos y RNG, traza de primer desacuerdo; no aceptar sólo agregados. |
| R02 Alta | Clima/tecnología/ecología afectan las cinco prioridades | Conservar llamadas y capas; fixtures cruzados con capacidad de carga, fiscalidad y alcance militar. |
| R03 Alta | Smoke inicial no forma estados ni guerras | Cero estados/guerras al final de ambos escenarios; conseguir fixtures tardíos deterministas antes de portar esos sistemas. No presentar este smoke como cobertura militar. |
| R04 Alta | Snapshots de mapa no restauran estado completo; Mulberry32 sí es reconstruible con semilla/contador | Fórmula y transparencia probadas por adaptador externo; diseño Save/Restore v1 con IDs y orden en EVENTS_AND_SAVE.md. Persistencia completa pendiente de implementación. |
| R05 Media | Tiempo de UI y años parciales pueden mezclar comandos | Mantener frontera `finishYear` y orden de intervenciones; probar velocidades y render distintos. |
| R06 Media | Recursos terrestres embebidos y fuentes externas | Preservar bytes y procedencia local. Verificar licencias/atribuciones de elevación, Köppen, fuentes y código antes de distribuir binarios o extraer assets. No se adjudica una licencia no comprobada. |
| R07 Media | Importación de heightmaps vía Canvas depende del navegador | Fixture de píxeles decodificados y hash; definir interpolación exacta antes de prometer equivalencia de importación. |
| R08 Media | Versión/runtime/plataforma pueden cambiar trascendentales | Registrar entorno del oráculo y comparar por etapa; declarar alcance de determinismo multiplataforma tras medir. |
| R09 Media | poolPass y caravanPass no disparan antes de CE por %10===5 y %20===7 | Conservar en v06-compat; alternativa native/calendar-v2 requiere decisión/fixtures separados. Ver SYSTEM_CALENDAR.md. |
| R10 Media | Renombrar `metal`/`admin` por claves TECH podría romper alias | Mantener índices y referencias de almacenamiento; inventariar los 32 canales. |
| R11 Media | Compartir sólo semilla omite reglas y recursos | Replay completo con configuración, hashes y comandos. |
| R12 Media | Crecimiento de arrays de eventos/entidades y snapshots a largo plazo | Pruebas de milenios, memoria y centinelas; mantener políticas originales de poda. |

## Preguntas para resolver en revisión

- Aceptar o corregir el contrato de equivalencia exacta; si hay tolerancias float, especificarlas sin permitir divergencias discretas.
- Aprobar estructura, límites core/UI, estrategia de datos y secuencia de port, sin confundir prioridad de interfaz con permiso para omitir dependencias.
- Confirmar procedencia/licencia para futura distribución; la copia privada de referencia no resuelve esa revisión.
- Resolver cómo obtener checkpoints tardíos del oráculo sin alterar el original.
- Conservar el commit dedicado mediante merge; tras integración aprobada, autorizar por separado el tag sobre ese commit.

Primera auditoría íntegra recibida por el usuario e incorporada en AUDIT_FINDINGS.md. Correcciones pendientes de segunda aprobación de Claude y autorización expresa del usuario. No hay aprobación de Fase 1. ADR y límites numéricos corregidos en ARCHITECTURAL_DECISIONS.md y NUMERIC_COMPATIBILITY.md.
