# Instrucciones de trabajo — Asabiya Native

> Versión de decisiones de producto: 21-10-2026. Estas reglas afectan al desarrollo futuro; **no redefinen retrospectivamente** el contenido o la aceptación de las ramas históricas.

## Norte de producto

- **Asabiya Atlas 2D de máximo detalle** es la prioridad actual: Tierra reconocible, historia alternativa emergente, zoom mundial/regional/provincial, capas cartográficas, ciudades, construcciones, ruinas, inspector profundo y cronologías causales.
- **Go es la única autoridad causal** de la historia. La vista 2D, Godot 3D o cualquier visor futuro solo proyectan/consultan sus estados y envían intervenciones explícitas.
- **3D está aplazado, no cancelado.** Considerarlo nuevamente al existir financiación suficiente, mejores capacidades de cómputo y herramientas, un equipo multidisciplinario, y un prototipo validado.
- El producto es **principalmente observacional**, con intervenciones opcionales trazables; no imponer control de un Estado, victorias o cronología histórica fija.
- Los cambios de tecnología, instituciones, economía, ecología y territorio son regionales y causalmente vinculados. Las ruinas son **persistencia material**, no assets aleatorios decorativos.
- No confundir objetivos con implementaciones. Ver `docs/design/README.md` y `docs/design/DECISIONS.md`.

## Alcance de código y ramas

- Consultar el estado real de `main`, ramas y HEAD de PR antes de editar. `main` puede permanecer atrasado frente a PR #21–#25.
- Trabajar en **rama propia y PR independiente**, no escribir directamente a `main`, no fusionar ni cerrar PR sin autorización expresa.
- No modificar trabajo de otro agente o rama; documentar dependencias. **El cambio de visión no autoriza cancelar PR técnicas existentes.**
- No modificar, reformatear ni normalizar `reference/v0.6/Asabiya History Engine (Copy).html`, fixtures ni golden para esconder divergencias. Usar el verificador existente cuando corresponda.
- Preservar contratos Go (simulación, RNG, calendario, replay/SHA, comandos, protocolo y cargas) hasta que exista propuesta y migración expresamente autorizadas.
- Conservar el cliente 3D y sus artefactos para comparación y futura reutilización. **No borrar ni sustituir el cliente actual por el prototipo 2D** antes de una decisión posterior.

## Ruta de evaluación 2D

1. Inventariar APIs y datos reales del Go más reciente, sin asumir que todas las capacidades deseadas existen.
2. Prototipar 2D **fuera del cliente de producción**, consumiendo estados reales de Go.
3. Comparar Godot 2D, Ebitengine y web/cartografía según rendimiento en Windows x64, mantenimiento, UX, calidad visual y coste de migración.
4. Mostrar Tierra real versionada cuando las fuentes, licencias, proyección, topología y costes estén definidos; si se usan datos/procedural de prueba, identificarlos explícitamente como tales.
5. Priorizar detalle dependiente del zoom, consulta por selección, índices y actualizaciones diferenciales sobre miles de nodos o sprites activos.
6. Validar en hardware objetivo con FPS/frametimes P50/P95/P99, RAM, latencia de navegación y throughput anual; no extrapolar pruebas headless o GPU ajena.
7. Evitar agregar mecánicas históricas que no aporten consecuencias explicables y visibles.

## Diseño para el eventual 3D

- Mantener IDs durables, coordenadas geográficas, estados, eventos, infraestructura y ruinas fuera de la capa de presentación.
- Versionar contratos de representación y exportaciones. No guardar datos causales únicamente como sprites, escenas, widgets o shaders.
- Permitir dos clientes futuros (atlas 2D y mundo 3D) sobre una sola verdad histórica; no garantizar reutilización directa de UI o assets.
- No comprometer recursos comerciales, una plantilla de equipo, fecha de migración ni cambio de motor hasta que existan condiciones verificables.

## Evidencia y comunicación

- Cada tarea entregará: SHA base/head, archivos editados, justificación, dependencias, tests realmente corridos, mediciones reproducibles, regresiones, limitaciones y acciones pendientes.
- Distinguir: **idea / especificación / código / CI / validación en PC / aceptación del usuario**.
- No inventar medidas o aprobaciones externas ni declarar paridad histórica completa sin evidencia.
- Proponer primero la solución de menor coste que preserve profundidad y mantenimiento.
- Consultar [visión](docs/design/VISION.md), [principios](docs/design/DESIGN_PRINCIPLES.md), [roadmap](docs/design/ROADMAP.md), [arquitectura](docs/design/ARCHITECTURE_2D.md) y [decisiones](docs/design/DECISIONS.md) antes de empezar una nueva feature.

## Historia documental

`docs/phase-0/` y `docs/phase-1/` contienen decisiones, límites y artefactos propios de fases anteriores. Las referencias a Ebitengine o Go inicial en ellas son **históricas**, no una orden de revertir cambios técnicos que viven en otras PR.
