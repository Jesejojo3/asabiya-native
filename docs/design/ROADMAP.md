# ASABIYA — Roadmap conceptual por capacidades

**Edición:** 21 de octubre de 2026  
**Uso:** secuencia de decisiones y criterios verificables, **sin fechas de lanzamiento comprometidas**.

## Estado del proyecto al redactar este documento

- **Referencia conservada:** HTML v0.6 en reference/v0.6, junto con su historial de validación.
- **Arquitectura nativa de trabajo:** motor histórico Go, puente TCP local, cliente 3D Godot para Windows x64.
- **Integración pendiente:** PR #21 de consolidación todavía separada de main.
- **Rendimiento pendiente de aceptación:** PR #22, Fase 2.2, en borrador; las mediciones Windows aportadas indican progreso en aplicación histórica y picking, pero todavía se observan alrededor de 13 FPS al acercar mucho la cámara en ciertas condiciones.
- **Todavía no implementado como producto principal:** atlas terrestre real 3D plano, patrimonio material/ruinas causales y extensión integral a eras de fusión u orbitales.

El README y las instrucciones antiguas en main pueden reflejar fases previas. No interpretar su contenido como estado actualizado del código de PR #21/#22. Consultar los contratos y resultados de las ramas técnicas correspondientes.

## Etapa 0 — Crear una base estable, medible y mantenible

**Objetivo:** poder reproducir, ejecutar, diagnosticar y validar una versión Windows sin depender de conocimiento tribal ni de PR superpuestas.

**Trabajo:** cerrar aceptación de consolidación y cliente, inventariar ramas y documentación, automatizar pruebas apropiadas, reducir cuellos de botella de render cercano y medir CPU/worker/GPU sin confundirlos.

**Puerta de salida:** compilación reproducible, pruebas causales y de UI relevantes aprobadas, referencia v0.6 preservada, instrucciones simples y mediciones comparables documentadas. No exigir una cifra arbitraria de FPS sin presupuesto de hardware y calidad.

## Etapa 1 — Atlas terrestre versionado

**Objetivo:** sustituir gradualmente la generación de geografía ficticia en la experiencia principal por la Tierra real, manteniendo el motor Go como autoridad de simulación.

**Trabajo:** seleccionar y licenciar fuentes cartográficas; definir proyección y coordenadas; construir celdas/topología/vecindad verificables; importación reproducible de elevación, tierras, mares y ríos; representación 3D con LOD y carga regional. Mantener el mapa procedural anterior para comparación técnica hasta cerrar la migración.

**Puerta de salida:** la misma semilla/atlas genera entradas idénticas; costas, relieve y selección concuerdan entre Go y Godot; navega sin discontinuidades graves ni regresión inaceptable; ninguna frontera moderna se impone como Estado simulado.

**Decisiones abiertas:** fecha geográfica de referencia, extensión y fidelidad de costas históricas, resolución terrestre, tratamiento del antimeridiano y polos, licencias de datos.

## Etapa 2 — Observatorio histórico utilizable

**Objetivo:** hacer accesibles y explicables los acontecimientos de las simulaciones.

**Trabajo:** zoom mundial-regional-local coherente, filtros y capas, búsqueda de entidad, cronologías de pueblos/Estados/ciudades, navegación de periodos y registros causales de acontecimientos. Modo observador puro e intervenciones opcionales claramente separadas.

**Puerta de salida:** seguir una sociedad durante siglos, identificar al menos un cambio político o demográfico y reconstruir sus causas modeladas desde la interfaz sin inventar hechos.

## Etapa 3 — Ciclo completo de asentamiento, crisis y legado

**Objetivo:** validar el núcleo diferenciador antes de ampliar siglos y eras.

**Vertical slice:** en una región terrestre, observar de forma emergente establecimiento → crecimiento → infraestructura → crisis → posible abandono o transformación → nueva ocupación.

**Trabajo:** persistencia de construcciones y sitios, degradación/recuperación, historial material, representación inicial con assets placeholder y reglas de reutilización.

**Puerta de salida:** el sitio persiste tras desaparecer su constructor; otra sociedad puede interactuar con el legado; mismo evento y estado aparecen en motor, panel y atlas; repetible mediante semilla y datos iniciales.

## Etapa 4 — Profundización sistémica y presentación

**Objetivo:** enriquecer la emergencia sin introducir funcionalidades aisladas.

**Trabajo posible:** instituciones, cultura/religión, economía y rutas, relaciones sociales, ecología, mantenimiento de infraestructura, selección y navegación refinadas, estilos arquitectónicos por contexto y LOD, assets artísticos definitivos.

**Puerta de salida:** cada incorporación presenta evidencia causal, efecto visible, coste de rendimiento y regresiones automatizadas; el ciclo completo anterior continúa funcionando.

## Etapa 5 — Capacidades modernas, futuristas y regresiones

**Objetivo:** permitir desarrollos tecnológicos no lineales y colapsos de sociedades complejas manteniendo continuidad.

**Trabajo futuro, sujeto a validación:** capacidades industriales y científicas especializadas, redes de energía, fusión, infraestructura espacial, posibles sociedades cyberpunk, guerras de gran escala, pérdida de conocimientos prácticos y complejos en ruinas.

**Puerta de salida:** coexistencia regional de capacidades distintas; pérdida gradual de mantenimiento y producción; infraestructura heredada no se transforma mágicamente en edificios de otra era; consecuencias persistentes e investigables.

Esta etapa **no obliga** a que toda sociedad alcance una era futura ni a que una guerra nuclear provoque un Neolítico global.

## Orden de gestión

1. No agregar nuevos sistemas a una rama de optimización que aún necesita aceptación.
2. Auditar estado real del código y dependencias **antes** de reorganizar archivos.
3. Especificar cada etapa con tareas pequeñas, dueño de archivos y pruebas.
4. Mantener un registro separado de decisiones de producto y de resultados técnicos.
5. Preferir una vertical slice causal comprobable a muchas mecánicas incompletas.
6. Aprobar el merge de cada PR solo después de revisar sus evidencias.

## Alcance deliberadamente excluido del compromiso inmediato

- Recreación exhaustiva o exacta de toda la historia terrestre.
- Simulación individual de todos los habitantes del planeta en todo momento.
- Modelos 3D finales para todas las culturas y eras.
- Simulación física detallada y autónoma de cada satélite o construcción orbital.
- Cronogramas fijos de entrega de fusión, cyberpunk o regresiones nucleares.

**Próxima decisión de producto:** fijar criterios del atlas terrestre e inicio histórico **después** de contar con una base técnica estable y un inventario aprobado del repositorio.
