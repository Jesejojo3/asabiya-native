# Misión: núcleo histórico v0.6 completo

Rama de integración: `integration/v06-historical-core`, desde **d19e27ef56e45290cf2b12ed4a275086e3e78aab**, HEAD corregido de PR #6. Dependencia explícita: PR #6 permanece abierta, no integrada. No hacer merge en main. Al integrarse, incorporar main conservando todos los commits.

El usuario autorizó completar autónomamente todas las etapas, sin auditorías externas intermedias. La revisión integral queda al final. No declarar terminado el núcleo por acabar una lista parcial.

- Prerrequisito cerrado: EraShare copiado profundamente y opciones de reglas incluidas en Digest; regresiones antes/después, tests/vet, builds, reproducción y CI Windows nativa/legado pasan. HTML y golden intactos.
- Etapa A: weather, hearthCheck, growth, migrate, seaHop, techStep y disease portados. Contratos controlados contra JavaScript verifican posición RNG, identidades y orden de infecciones, epidemias, sumas y muestras de arrays. No equivalen a una historia anual completa. No hay avance anual público parcial.
- B en curso: mezcla cultural, fundación/censo/cismas religiosos, ciudades, pools epidemiológicos, salida territorial y caravanas portados; contrato original controlado cubre 22 religiones y creación/caducidad de rutas desérticas. Regiones y cultura cortesana dependen todavía de los estados. newRuler/figuras se incorporaron como dependencias reales de profetas y reformadores.
- C en curso: newPolity, gobernantes/figuras, sucesión, civilWar, collapse, fiscalidad/statecraft y cultura cortesana portados; politicsG anual y agregaciones todavía pendientes. Contrato controlado verifica ocho puntos (incluye creación de rebeldes) y posición RNG exacta.
- D en curso: combate, conquista decisiva, saqueo, declaración/paz, diplomacia, distancia territorial, presión migratoria, movimiento/dispersión/asentamiento de migraciones y éxodo de hordas portados. Contrato controlado cubre combate, guerra civil, paz, una migración y diplomacia; falta integrarlos en el calendario y demostrar historia emergente larga.
- E pendiente: ocho presagios y siete cataclismos.
- F pendiente: calendario completo, año atómico, consultas/headless/ventana y simulaciones largas.
- G pendiente: inventario completo, Tierra/importación/clima ajustado y procedencia de recursos.

Guardar/reanudar partida completa es una ampliación nativa aún no implementada. El historial visual original no la sustituye.

`Digest()` continúa siendo la proyección congelada `native/history-init-v1`; no debe presentarse como hash de todo el nuevo estado anual. Antes de exponer años se añadirá un contrato de estado completo versionado, conservando explícitamente los golden de inicialización.

## Dirección vigente: Go + Godot 4

Go es la autoridad histórica; Godot 4 será el cliente final 3D, desarrollado independientemente por Claude. Ebitengine se conserva como visor provisional y no condicionará el núcleo. No modificar proyectos, escenas, recursos ni shaders de Claude. No hay comunicación automática con él.

El entregable incluye un contrato versionado de consultas inmutables, exportación geográfica binaria con manifiesto JSON, estado histórico estructurado y ejemplos reales; después, un protocolo exclusivamente local con comandos y deltas publicados al terminar años completos. Contrato y productor Go serán responsabilidad de Codex; consumidor Godot, de Claude. Todavía no están implementados. La documentación de coordenadas debe preservar la costura longitudinal, los límites polares, IDs lógicos y la relación entre resolución lógica y fina, dejando las escalas visuales al cliente. No inventar edificios ni entidades inexistentes para completar vistas.
