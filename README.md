# Asabiya Native

Migración propuesta de Asabiya History Engine v0.6 a Go + Ebitengine.

Estado: **Fase 0, pendiente de revisión y aprobación**. Todavía no hay simulación ni interfaz nativa en Go. La referencia HTML original está preservada sin cambios.

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

No integrar ni etiquetar legacy-v0.6 hasta aprobación e integración de la referencia. No iniciar Fase 1 automáticamente.

Correcciones de primera auditoría: [matriz de hallazgos](docs/phase-0/AUDIT_FINDINGS.md) y [validación correctiva](docs/phase-0/CORRECTION_VALIDATION.md). Pendientes segunda revisión de Claude y autorización del usuario; sin merge, tag ni Fase 1.
