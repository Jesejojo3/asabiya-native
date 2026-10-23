# Contrato activo del cliente integrado

La propuesta original asabiya-bridge/v1 de PR #8 queda sustituida por asabiya/local-v1. El cliente no requiere otro puente ni otro motor.

El arranque obtiene puerto 0 mediante --endpoint-file. Se usan create_world, get_catalog, export_geography, start_history, get_state, advance, pause, get_province, get_entity, get_province_history y shutdown. La generación de sesión y los IDs de texto se comprueban en cada respuesta. El proceso se controla desde Godot y vigila su proceso padre en Windows.

Las vistas map-state-v1 y map-delta-v1 son proyecciones opcionales del estado histórico real dentro del mismo protocolo TCP. No usan los arrays base64 del antiguo mock. Las capas del archivo geography-v1 se leen mediante un adaptador explícito; sus bytes no se tratan como un archivo .asw.

Detalles: [integración](../integration/README.md), [contrato geográfico](../mission/GODOT_CONTRACT.md). Las pruebas finales corresponden al usuario y no se han ejecutado en esta entrega.
