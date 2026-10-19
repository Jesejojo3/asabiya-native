# Simulation Core

World es inmutable; Simulation posee el estado histórico y serializa cada año completo, comando y consulta. El núcleo no depende de DOM, Godot, Ebitengine, reloj real, sockets ni archivos.

Se ha incorporado el calendario causal v0.6 y sus sistemas de población, culturas/lenguas, tecnología, ecología, enfermedades, religiones, ciudades, comercio, Estados/gobernantes, crisis, migraciones, diplomacia, guerras, presagios y cataclismos. Cada sistema mantiene su archivo y el orden del original en calendar.go. Earth añade focos, órbita y regiones originales; mapsource es el adaptador de I/O externo al núcleo.

AdvanceYear es público y atómico. Las vistas, deltas, eventos y consultas por ID no exponen estado mutable. Las entidades, reglas, RNG y estado causal completo tienen digest versionado. bfsParent permanece en ese digest por la reutilización causal original de su contenido. Las publicaciones de mapa son adaptaciones de lectura en interop, no otra simulación.

Las proyecciones congeladas world-v1, world-v2 e history-init-v1 y sus fixtures siguen preservadas. Las fuentes extendidas usan world-v3. La equivalencia bit a bit con V8 no es un requisito del producto Windows x64 personal. Las últimas pruebas de la integración quedan a cargo del usuario por su instrucción expresa.

[Inventario](../../docs/mission/PORT_INVENTORY.md), [entradas del mundo](../../docs/mission/WORLD_INPUTS.md), [integración](../../docs/integration/README.md).
