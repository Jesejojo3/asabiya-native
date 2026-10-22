# Documentación de diseño — Asabiya Atlas

**Dirección vigente desde 21-10-2026:** simulación emergente Go + **atlas 2D de máximo detalle útil** como cliente prioritario. Un **3D futuro condicionado a recursos**; la implementación 3D actual se conserva.

> Estos documentos describen **decisiones y objetivos de producto**, no la totalidad de las características implementadas.

## Orden de lectura (documentos vigentes)

| Documento | Propósito |
|---|---|
| [VISION.md](VISION.md) | Identidad, observador, Tierra, profundidad y eras |
| [DESIGN_PRINCIPLES.md](DESIGN_PRINCIPLES.md) | Constitución, límites, reglas de aceptación |
| [ROADMAP.md](ROADMAP.md) | Secuencia por hitos y condiciones de salida |
| [ARCHITECTURE_2D.md](ARCHITECTURE_2D.md) | Contrato Go–presentación, adaptación 2D y reversibilidad |
| [ATLAS_2D_SPEC.md](ATLAS_2D_SPEC.md) | Máximo detalle cartográfico/UX, zoom, capas y ruinas |
| [FUTURE_3D.md](FUTURE_3D.md) | Recursos, equipo, financiación y diseño para 3D |
| [DECISIONS.md](DECISIONS.md) | Registro de cambios de estrategia, opciones y pendientes |

## Estado y autoridad documental

- **Vigente como decisión:** simulador observacional, Go causal, Tierra real como objetivo, Atlas 2D principal, continuidad y materialidad, futuro 3D sin fecha comprometida.
- **Existe en ramas técnicas y debe validarse por SHA:** motor Go, cliente Godot 3D, puente TCP, herramientas de perfilado y paridad interactiva.
- **No entregado ni certificado:** Tierra real definitiva, atlas 2D de producción, todas las eras futuristas, ruinas persistentes como sistema causal completo, transición 3D.
- **Histórico:** `docs/phase-0/`, `docs/phase-1/`, PR antiguas, HTML v0.6 y documentación de la etapa en que el producto priorizaba Ebitengine o 3D. Se preservan, no se ocultan.
- **Investigación en paralelo:** PR #22–#25 con rendimiento 3D y la PR #23 conceptual. Su contenido no pasa a `main` automáticamente.

## Regla ante contradicciones

1. Para **dirección del producto**, usar estos documentos vigentes y el registro de decisiones.
2. Para **qué código funciona**, comprobar la rama/commit, pruebas y documentación técnica de ese código.
3. Para **restricciones causales**, respetar contratos Go y tests verificados.
4. Para **historia de decisiones**, conservar documentos originales sin hacerles decir lo que no decían.
5. Para **cambios futuros**, registrar un nuevo ADR/decisión y una PR explícita.

El README de `main` puede describir Bloques 1–2 y el cliente Ebitengine; eso es estado de aquella rama, **no una contradicción que autorice eliminar el trabajo posterior**.

## Preguntas que siguen abiertas

- Motor/stack 2D definitivo (Godot 2D, Ebitengine o web).
- Dataset terrestre, licencia, formato, resolución, proyección y costa histórica.
- Fecha inicial, poblamiento, agrupación de celdas/provincias y niveles de persistencia.
- Contrato de consultas e historial, límites de memoria, presupuestos de render y hardware mínimo final.
- Horizonte de financiación, equipo y cliente 3D futuro; sin obligación ni calendario.

## Disciplina

No hacer merges de PR sin autorización; no reescribir HTML/golden; no confundir placeholders con assets finales; no prometer FPS sin benchmark; no mover sistemas históricos a la UI. Cada feature debe mostrar **causa → consecuencia → persistencia → observación**.
