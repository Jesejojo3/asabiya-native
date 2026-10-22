# Asabiya Native

**Un mundo. Infinitas historias.**

Asabiya es un **simulador histórico emergente de observación**: sociedades que nacen, se organizan, se transforman y desaparecen sobre una Tierra reconocible, dejando consecuencias persistentes para las generaciones posteriores. El observador puede investigar la historia e intervenir ocasionalmente, sin necesidad de gobernar una dinastía ni ganar una partida.

> **Dirección de producto aprobada (21-10-2026):** desarrollar primero **Asabiya Atlas 2D**, con el mayor detalle cartográfico, histórico y sistémico que podamos sostener. Mantener la simulación en **Go como única autoridad causal**. El **3D queda aplazado** hasta disponer de financiación, mejores recursos de cómputo/IA y capacidad de formar un equipo especializado. No es una cancelación de la visión 3D ni un compromiso de fecha.

## Qué significa «2D de máximo detalle»

No se persigue un mapa plano sin profundidad: la representación tendrá varias escalas de zoom, relieve sombreado, costas y ríos, capas dinámicas, nombres, provincias, ciudades, rutas, construcciones, ruinas y una interfaz de investigación con cronologías y causalidad explicable. **La complejidad de la historia no depende del número de polígonos.**

El detalle será **progresivo según escala, región y consulta**, no miles de objetos permanentes que colapsen la GPU. Los eventos, identidades, edificios e historias se modelan en Go y conservan su continuidad aunque estén fuera de pantalla. No se debe inventar información histórica desde el cliente.

## Situación del código frente a la visión

**No confundir una decisión de diseño con una función entregada.** El `main` de este repositorio conserva documentación e implementación de fases tempranas de Go/Ebitengine. El motor Go y el cliente Godot 3D más avanzados, las optimizaciones y la documentación conceptual se han desarrollado en **ramas y pull requests separados**; su contenido no debe describirse como fusionado ni validado en `main`.

- [PR #21 — consolidación Go + Godot 3D](https://github.com/Jesejojo3/asabiya-native/pull/21): rama técnica para validación Windows, sin merge.
- [PR #22 — Fase 2.2 de rendimiento](https://github.com/Jesejojo3/asabiya-native/pull/22): optimizaciones pendientes de validación integral.
- [PR #23 — visión anterior, en revisión](https://github.com/Jesejojo3/asabiya-native/pull/23): documentación conceptual de la etapa de atlas 3D, base de esta revisión.
- [PR #24 — perfilado Windows](https://github.com/Jesejojo3/asabiya-native/pull/24) y [PR #25 — diagnóstico/optimización 3D](https://github.com/Jesejojo3/asabiya-native/pull/25): investigación técnica preservada; no es la prioridad futura de producto.
- **Nueva etapa:** prototipo Atlas 2D comparativo antes de escoger definitivamente Godot 2D, Ebitengine o una interfaz cartográfica web.

Los README técnicos de cada rama, sus artefactos y suites prevalecen al documentar qué compila, cómo se ejecuta y qué está probado **en esa rama**. No usar comandos del `main` como instrucciones de las PR modernas.

## Documentos rectores

1. [Visión del producto](docs/design/VISION.md): Tierra real, historia alternativa, observador y memoria material.
2. [Principios de diseño](docs/design/DESIGN_PRINCIPLES.md): causalidad, independencia gráfica y aceptación de mecánicas.
3. [Roadmap por hitos](docs/design/ROADMAP.md): del prototipo 2D al desarrollo sistémico y futuro 3D.
4. [Arquitectura de transición 2D](docs/design/ARCHITECTURE_2D.md): contratos Go–representación y opciones de cliente.
5. [Detalle cartográfico y UX](docs/design/ATLAS_2D_SPEC.md): zoom, capas, ciudades, ruinas, inspección y presupuesto de rendimiento.
6. [Estrategia futura 3D/equipo](docs/design/FUTURE_3D.md): condiciones de financiación, contratación y migración.
7. [Registro de decisiones](docs/design/DECISIONS.md): decisiones tomadas, experimentos descartados y asuntos abiertos.
8. [Estado documental](docs/design/README.md): qué es vigente, histórico o todavía una hipótesis.

## Límites de la transición

- **El motor histórico Go se conserva.** No reescribirlo por motivos gráficos.
- El **HTML v0.6 es referencia inmutable**: `reference/v0.6/` y sus golden no se alteran.
- **No borrar** los trabajos Godot 3D ni sus evidencias: quedan como activo técnico y posible cliente futuro.
- **No reemplazar código de producción aún.** Probar una vertical slice 2D con datos de Go, capturas, métricas y contratos antes de seleccionar cliente.
- No tocar `main`, fusionar PR, cambiar contratos de simulación ni afirmar mejoras no medidas sin autorización y validación.

**Plataforma actual:** uso personal en Windows x64. Una comercialización futura, si se considerara, exigiría una decisión distinta sobre alcance y licencias.

## Legado técnico

La documentación de [Fase 0](docs/phase-0/README.md), [arquitectura inicial Go + Ebitengine](docs/phase-0/ARCHITECTURE.md) y [Fase 1](docs/phase-1/README.md) conserva el contexto de sus respectivas fechas. **No se reescriben retroactivamente** para fingir que describen la arquitectura activa actual. Las referencias históricas se mantienen intactas y están claramente distinguidas de la nueva dirección de producto.
