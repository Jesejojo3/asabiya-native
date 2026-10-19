# Asabiya Native

Migración propuesta de Asabiya History Engine v0.6 a Go + Ebitengine.

Estado: **Fase 0 aprobada con condiciones documentales por Claude; merge/tag pendientes de autorización del usuario**. Todavía no hay simulación ni interfaz nativa en Go. La referencia HTML original está preservada sin cambios.

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

Correcciones de primera auditoría: [matriz de hallazgos](docs/phase-0/AUDIT_FINDINGS.md) y [validación correctiva](docs/phase-0/CORRECTION_VALIDATION.md). Segunda revisión estática completada; merge/tag y Fase 1 pendientes de autorización del usuario.

Alcance aprobado: uso personal **Windows x64**, Go + Ebitengine. `native` usará inicialmente `math` de Go, sin paridad bit a bit obligatoria con V8; `v06-compat` y los fixtures originales permanecen como referencia diagnóstica. Linux es diagnóstico opcional, no CI bloqueante.
