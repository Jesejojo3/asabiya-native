# Auditoría estática del cliente 3D — Fase 2

Estado: implementación y revisión estática; eficacia y corrección en ejecución pendientes del usuario. No se ejecutan pruebas, editor, juego, benchmarks, CI ni exportación durante esta fase.

## Base y límites

Remotos consultados el 21-10-2026: consolidación `79035761f1e61041a3ccbf74b648577e53ba7150`; main `714d06c3a9d3ce9d69dbb184161a99b2c78e82f1`. Rama nueva `perf/godot-frame-optimization`, sin integrar otras ramas. Checkout separado. Las mediciones Windows proporcionadas (16–17 FPS sostenidos, P95 100–115 ms) no atribuyen coste a un subsistema.

## Recorrido inspeccionado antes de editar

`main._process → BridgeSource.poll → callbacks → _load_frame → settlements/history/layers/HUD`. TCP, parseo JSON y NativeFrameDecoder ya trabajan fuera del hilo gráfico. Se conserva ese contrato y el orden de publicaciones. `_store` emite frames_changed y status_changed, de modo que algunas actualizaciones del HUD se solicitan dos veces por publicación.

`StrategyCamera._process → _apply → MapMath.height_at` recalcula pose y dos muestras completas de altura incluso en reposo. La interpolación converge sin un cierre explícito, por lo que pequeñas variaciones pueden seguir invalidando vistas. El raycast de hover sólo ocurre al mover cámara/ratón; no se elimina esa interacción.

`MapView._process → terrain.update_view → view_listeners` se ejecuta cada frame. El terreno **ya** evita el recorrido de chunks si posición/proyección no cambian y **ya** evita texturas idénticas. Se conserva esa lógica. Fog, sombras, minor_rivers y todos los listeners se vuelven a solicitar aun con cámara inmóvil. Los listeners recorren bandas, etiquetas y marcadores. Vegetación necesita continuar recibiendo finalizaciones de su worker aunque la cámara esté quieta: una invalidación global sin bombeo independiente rompería su generación.

`VegetationLayer.update_view` poda y busca tiles repetidamente, aunque ya no falte ninguno. Un worker calcula transformaciones; `InstanceBands.set_band` todavía convierte y envía cada instancia por separado en el hilo principal. Hay un máximo de un worker y un tile publicado por frame, pero no un límite temporal estricto para una subida GPU.

`SettlementLayer.set_settlements` reutiliza layouts individuales, pero cualquier cambio de presentación reconstruye todas las bandas y todas las etiquetas; un renombre basta para dispararlo. `HistoryOverlay` recalcula centroides al cambiar nombres y repite seno/coseno para celdas de una misma longitud. Ya tiene firmas separadas; su actualización de vista sigue recorriendo todos los nodos cada frame y recrea materiales iguales al reconstruir marcadores/rutas.

`Hud.refresh_layers` depende de la identidad del frame aunque disponibilidad sólo dependa de sistemas y existencia de datos. `set_frame_stats` vuelve a rellenar desastres al repetir un refresh; `set_view_scale` reasigna controles/textos sin cambios. Chronicle ya compara eventos y las capas geográficas ya se conservan entre años; no se reescriben esos mecanismos.

`PerformanceTrace` sólo mide ventanas globales y vive en TerrainRenderer. Hace flush por registro. No distingue cámara/LOD/vegetación/HUD ni identifica una espera GPU. Se ampliará con agregación acotada y un único dueño en el hilo principal.

## Hipótesis que requieren medición

El trabajo redundante anterior existe en código; su porcentaje de frametime aún no está medido. Forward+, MSAA, SSAO, sombras y el shader de relieve pueden seguir siendo costosos en la iGPU. Se preservan calidad, shaders, geometría, densidad y sistemas. No se concluye CPU-bound ni GPU-bound a partir de TIME_PROCESS. La decodificación en worker puede competir por CPU; no se modifica el protocolo sin datos que lo justifiquen.
