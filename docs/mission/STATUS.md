# Misión: núcleo histórico v0.6 completo

Rama de integración: `integration/v06-historical-core`, desde **d19e27ef56e45290cf2b12ed4a275086e3e78aab**, HEAD corregido de PR #6. Dependencia explícita: PR #6 permanece abierta, no integrada. No hacer merge en main. Al integrarse, incorporar main conservando todos los commits.

El usuario autorizó completar autónomamente todas las etapas, sin auditorías externas intermedias. La revisión integral queda al final. No declarar terminado el núcleo por acabar una lista parcial.

- Prerrequisito cerrado: EraShare copiado profundamente y opciones de reglas incluidas en Digest; regresiones antes/después, tests/vet, builds, reproducción y CI Windows nativa/legado pasan. HTML y golden intactos.
- Etapa A: weather, hearthCheck, growth, migrate, seaHop, techStep y disease portados. Contratos controlados contra JavaScript verifican posición RNG, identidades y orden de infecciones, epidemias, sumas y muestras de arrays. No equivalen a una historia anual completa. No hay avance anual público parcial.
- B portado para mundos procedurales: mezcla cultural, fundación/censo/cismas religiosos, ciudades, pools epidemiológicos, salida territorial, caravanas, cultura cortesana y regiones/formas imperiales. Contrato original controlado cubre 22 religiones y creación/caducidad de rutas desérticas; el calendario integrado cubre estadísticas e historial. Regiones específicas de Tierra pendientes de G.
- C portado: newPolity, gobernantes/figuras, sucesión, civilWar, collapse, fiscalidad/statecraft, cultura cortesana y politicsG completo, con censo, fronteras y mantenimiento territorial. Contrato político controlado de seis años verifica censo, fase de gobernantes, RNG exacto, provincias y entidades, incluyendo los rebeldes visitados el mismo año. Falta la integración anual integral y la historia emergente larga.
- D en curso: combate, conquista decisiva, saqueo, declaración/paz, diplomacia, distancia territorial, presión migratoria, movimiento/dispersión/asentamiento de migraciones y éxodo de hordas portados. Contrato controlado cubre combate, guerra civil, paz, una migración y diplomacia; falta integrarlos en el calendario y demostrar historia emergente larga.
- E portado: ocho presagios, seguimiento, favor/sandbox, siete cataclismos, selección aleatoria ordenada y erupciones volcánicas. Contrato original cubre todas las intervenciones, Spark sin técnicas nuevas, ambos tipos de erupción y rechazos sin consumir RNG.
- F en curso: calendario público atómico, comandos/replay, digest completo versionado, consultas inmutables, deltas e historial comprimido implementados. Exportación geográfica binaria/JSON y TCP exclusivamente loopback probados con consumidor Node y replay reconstruido por otro proceso headless. Contrato original cubre 60 años de forrajeo y 80 controlados con sociedades avanzadas. Una primera corrida Windows x64 de 10 000 años pasó validaciones periódicas en 116.39 s y terminó en 1000 con 130 estados, 8 hordas y entradas de conflictos; es evidencia preliminar, pendiente repetir con el motor final. Fixtures finales, inventario y empaquetado pendientes.
- G pendiente: inventario completo, Tierra/importación/clima ajustado y procedencia de recursos.

Guardar/reanudar partida completa es una ampliación nativa aún no implementada. El historial visual original no la sustituye.

`InitialSummary()` conserva la proyección congelada `native/history-init-v1`. `StateDigest()` cubre el estado causal completo, reglas, RNG y secuencia de comandos; `Digest()` cambia a `native/history-state-v1` tras un comando aceptado o avance. Se excluyen archivos históricos y marcadores de visita; `bfsParent` se incluye por su reutilización causal en poolPass. Los golden iniciales anteriores siguen pasando en dos procesos independientes.

## Semántica comprobada durante la integración política

- Las lecturas de arrays float32 se promueven a float64 también al comparar umbrales. Por ejemplo, float32(0.7) es menor que el literal JS 0.7; comparar directamente en Go redondearía ambos al mismo float32, permitiría inventar moneda y consumiría otro sorteo. El contrato político detectó esa diferencia; se corrigió el código, no el valor de referencia.
- `newPolity` no define `o.integ` ni `o.coastN`. Los rebeldes visitados antes de su primer censo pueden propagar NaN a presión y cultura; el efecto se confirmó ejecutando el original. Se conserva explícitamente mediante disponibilidad del censo y NaN, sin confundirlo con las matrices provinciales de integración. Las vistas JSON deben emitir null para números no disponibles/no finitos. No normalizar cultura a cero silenciosamente; una corrección futura requerirá reglas versionadas.
- Región/forma imperial, vigilancias de pérdida de escritura y estadísticas políticas están portadas para mundos procedurales; las encuestas y regiones terrestres siguen pendientes de la rama Tierra. Su validación integrada sigue pendiente.

## Dirección vigente: Go + Godot 4

Go es la autoridad histórica; Godot 4 será el cliente final 3D, desarrollado independientemente por Claude. Ebitengine se conserva como visor provisional y no condicionará el núcleo. No modificar proyectos, escenas, recursos ni shaders de Claude. No hay comunicación automática con él.

Contrato y productor Go: `docs/mission/GODOT_CONTRACT.md`, `internal/interop`, `cmd/asabiya-server`. El consumidor Godot pertenece a Claude. Exportador y protocolo están implementados y probados en Windows x64; los fixtures finales y la interfaz de Claude no se declaran terminados. La documentación preserva costura longitudinal, límites polares, IDs y relación lógica/fina, con escalas visuales a elección del cliente. No hay edificios nuevos ni entidades dinásticas inventadas.
