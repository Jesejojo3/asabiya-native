# Paquete de auditoría independiente para Claude

## Mensaje listo para entregar manualmente

Actúa como auditor independiente de la Fase 0 de Asabiya Native en `Jesejojo3/asabiya-native`. Tu rol previsto es Claude Opus 5.5 / Claude Code; verifica por tu cuenta tu acceso y entorno. Revisa la PR de la rama `phase-0/legacy-baseline-architecture` contra `main`. Registra el SHA completo del HEAD antes de comenzar y no audites una rama cambiante sin indicar los commits añadidos. La PR contiene un commit exclusivo de importación `fe58bdb2ccf4db83857b02d16fa1852b54836824` y un commit posterior de estructura/documentación/comprobaciones.

El alcance se limita a preservar e inspeccionar el HTML v0.6 y proponer la migración a Go + Ebitengine. No implementes Fase 1 ni nuevas mecánicas. No integres la PR, no escribas directamente en `main` y no crees `legacy-v0.6`. Si propones cambios, usa otra rama/PR e identifica los hallazgos que los motivan.

Comprueba que `reference/v0.6/Asabiya History Engine (Copy).html` tiene 1 553 001 bytes y SHA-256 `988ce360e70d2d034a3898f60b9a4c38d40b0ab56dd7a147329740f15fa8e9e9`. Su blob Git debe ser `940af36bce0cdb05c3552f1d086ffe4290e392ac`. Si el usuario conserva el original de Descargas, compara también bytes contra él; no afirmes una comparación externa si no tienes ese archivo.

Lee `docs/phase-0/README.md`, `SOURCE_AUDIT.md`, `ARCHITECTURE.md`, `DETERMINISM_AND_TESTS.md`, `BENCHMARK_PLAN.md`, `DECISIONS_AND_RISKS.md`, `COLLABORATION.md` y `VALIDATION.md`. Contrasta el inventario con el código original, no sólo con la explicación del implementador.

Prioriza mapa, pueblos, estados, guerras y presagios, pero busca omisiones causales de clima, tecnología y ecología. Inspecciona especialmente orden de `stepG`/`politicsG`, UTF-16 y Mulberry32, redondeo float32, inserción de Map/Set, años negativos, alias tecnológicos, comandos al acabar el año, dependencia de nombres en RNG e historial de mapa frente a partida completa. Revisa si las propuestas permiten ejecutar el core sin GPU, reglas versionadas, equivalencia verificable y benchmarks comparables.

Reproduce los comandos indicados abajo. El smoke sólo cubre dos escenarios iniciales con sequía; termina sin estados ni guerras. No lo interpretes como validación de la migración Go o de los sistemas militares. Las pruebas Go, largo plazo y benchmarks están pendientes.

Entrega un dictamen con SHA auditado, severidades, rutas/líneas, casos mínimos, evidencia y comprobaciones no realizadas. Distingue defectos observados de hipótesis. No modifiques fixtures para hacer pasar una discrepancia. Devuelve el informe al usuario para entrega manual a Codex; no hay canal automático entre ambas herramientas. La integración y el inicio de Fase 1 dependen de aprobación humana.

## Comandos desde la raíz del repositorio

```sh
git status --short
git rev-parse HEAD
git show --stat fe58bdb2ccf4db83857b02d16fa1852b54836824
git rev-parse 'HEAD:reference/v0.6/Asabiya History Engine (Copy).html'
git check-attr text filter ident diff merge -- 'reference/v0.6/Asabiya History Engine (Copy).html'
node tools/verify-reference.mjs
node tools/reference-smoke.mjs
```

Con acceso al archivo aportado: `node tools/verify-reference.mjs "RUTA_DEL_ORIGINAL"`. Node y Git son suficientes para las comprobaciones de Fase 0; no requiere instalar Go, Ebitengine ni paquetes npm.

## Lista de revisión

- El diff contiene sólo importación inmutable, estructura reservada, documentación y herramientas de caracterización.
- El commit de importación no mezcla cambios al JS ni arquitectura.
- Hash/longitud/blob, atributos Git y comprobación contra archivo local cuando esté disponible.
- Correspondencia entre líneas citadas, tablas, orden anual y dependencias originales.
- Contrato core/render, datos y determinismo suficiente para comenzar un port auditable.
- Plan de equivalencia y benchmarks con criterios claros; pruebas pendientes visibles.
- Protocolo independiente sin atribuciones falsas de comunicación o aprobación.
- Bloqueo explícito de merge, tag y Fase 1 hasta aprobación.

Resultado de auditoría: **pendiente**. Esta entrega no atribuye ningún hallazgo ni aprobación a Claude.
