# Asabiya — Registro de decisiones de producto

**Propósito:** separar decisiones **acordadas**, alternativas **a probar** y asuntos **abiertos** de los hechos técnicos verificados. Las decisiones de producto no reescriben retroactivamente la historia de ramas y PR.

## ADR-PROD-001 — Identidad y modo observador
**Estado:** acordado, previo a 21-10-2026.

Asabiya es una simulación histórica emergente observacional, con intervenciones ocasionales y opcionales. No es principalmente control dinástico ni conquista. Un mismo planeta puede producir historias diferentes. Go conserva la causalidad; la UI debe explicar los cambios.

## ADR-PROD-002 — Tierra real como geografía objetivo
**Estado:** acordado como dirección; integración pendiente.

La geografía principal será terrestre, reconocible y versionada; fronteras, pueblos, Estados, ciudades y cronología serán emergentes. Se conserva la geografía procedural existente como referencia/prueba. Quedan abiertos la fuente, licencia, resolución, proyección, topología, paleogeografía y fecha inicial.

## ADR-PROD-003 — Cambio de prioridad de atlas 3D a Atlas 2D
**Fecha:** 21-10-2026. **Estado:** aprobado como decisión de producto; prototipo 2D no implementado todavía.

**Antes:** la visión en PR #23 priorizaba un atlas terrestre 3D plano con zoom de gran estrategia y construcción física visible.  
**Ahora:** Asabiya Atlas **2D de alta fidelidad** es la prioridad. Debe conservar máximo detalle histórico/cartográfico útil, zoom mundial/regional/provincial, ciudades, construcciones, ruinas, crónicas e investigación causal.

**Motivo:** una carga y complejidad gráfica 3D desproporcionada distrae de la profundidad histórica en el hardware y equipo actuales; las mediciones del zoom cercano en Iris Xe reflejaron coste GPU significativo, sin demostrar que Godot sea intrínsecamente inadecuado.

**Consecuencia:** experimentar primero con clientes 2D sin tirar Go ni su cliente 3D, no fusionar/descartar unilateralmente las PR #21–#25. Mantener referencia y comparativas. Ésta es una **reorientación de prioridad**, no una orden de borrado.

## ADR-PROD-004 — Máximo detalle en 2D no significa dibujarlo todo
**Fecha:** 21-10-2026. **Estado:** aprobado como criterio de UX y rendimiento.

Objetivo: un atlas rico en relieve, hidrografía, biomas, capas políticas/culturales/económicas, topónimos, rutas, asentamientos, edificios y ruinas, con inspección histórica profunda. La densidad depende de zoom y consulta; no se deben renderizar indiscriminadamente todas las entidades ni confundir datos históricos con iconografía. Ver `ATLAS_2D_SPEC.md`.

## ADR-PROD-005 — Motor Go independiente de clientes
**Estado:** reafirmado 21-10-2026; alcance técnico concreto debe comprobarse por SHA.

Go es la única autoridad del estado causal, independiente de render, UI y ritmo de frames. La geografía, identidades, eventos, snapshots, comandos y persistencia deberán tener contratos versionados para facilitar coexistencia de atlas 2D y 3D. **No asumir que todos esos contratos están completos hoy.**

## ADR-PROD-006 — 3D pospuesto y condicionado
**Fecha:** 21-10-2026. **Estado:** aprobado como estrategia, sin fecha.

El 3D sigue siendo objetivo futuro si el proyecto consigue fuentes de financiación adecuadas, mejor cómputo, capacidad de usar herramientas de IA útiles y un equipo multidisciplinario que pueda desarrollar/mantener el cliente. El 2D no se desecha cuando ello ocurra. La elección de motor 3D se hará con evidencia futura.

## ADR-PROD-007 — No sustituir Go por CK3
**Estado:** propuesta explorada y no seleccionada para el camino crítico.

Se evaluó aprovechar el renderizador de CK3 como mod/visor, congelando o neutralizando su simulación. Los mods estándar no permiten retirar su backend propietario como un módulo y enlazar libremente Go. Aun en uso exclusivamente personal, existen límites técnicos/de licencia y fuerte dependencia de terceros. **No continuar como ruta principal**; una prueba de exportación separada podría investigarse sin bloquear el atlas independiente.

## ADR-PROD-008 — Cliente 2D definitivo sin decidir
**Estado:** abierto; requiere prototipo comparativo.

Candidatos: Godot 2D, Go/Ebitengine, web cartográfica de escritorio (p. ej. Wails/MapLibre). No se declara que ninguno logre 60 FPS ni sea ganador. Evaluar con una misma región/estado Go, 1080p Windows, zoom, UI, capa histórica, cifras de rendimiento, costes de adaptación, licencias y mantenimiento. Documentar un nuevo ADR después de la evaluación.

## ADR-PROD-009 — Persistencia material y futurismo
**Estado:** visión acordada; implementación sistémica todavía por validar.

Las sociedades pueden alcanzar tecnologías modernas, fusión, cyberpunk y operación orbital y después perder capacidades sin borrar automáticamente infraestructura y memoria. Ruinas e instituciones sobrevivientes son consecuencia causal del estado de edificios, mantenimiento, cultura y aprendizaje; no decoraciones vinculadas solamente a una etiqueta de era.

## ADR-PROD-010 — Uso personal y sostenibilidad
**Estado:** uso actual confirmado como personal/no comercial; financiación/equipo, futuro hipotético.

El desarrollo prioriza mantener el proyecto entendible, compilable, reproducible y portable entre asistentes/equipos. Se podrán explorar fuentes de financiación y reclutamiento tras demostrar una experiencia convincente; no se acuerda comercialización ni presupuesto.

## Regla de interpretación y cambios

- **Decisión** no equivale a **implementado** ni a **aceptado en Windows**.
- Repositorio `main` y PR abiertas pueden contener situaciones técnicas distintas. Citar la rama/HEAD y pruebas correspondientes.
- `docs/phase-0`/`phase-1`, HTML v0.6 y PR originales documentan su propia época; mantener su integridad.
- Cualquier nueva decisión estratégica requiere fecha, propuesta, alternativas, motivación, consecuencias, pruebas necesarias y PR revisable.

## Próximo hito

Inventario técnico del estado Go realmente disponible; prototipo Atlas 2D acotado; medición sobre el hardware objetivo; después selección formal de cliente. No autoriza modificar PR ajenas, fusionar ramas o comenzar migración masiva.
