# ASABIYA — Roadmap por hitos (Atlas 2D primero)

**Edición:** 21 de octubre de 2026 · **Estado:** plan de producto, no compromisos de fecha ni constatación de funciones ya terminadas.

## 0. Hechos, intención y límites

**Hechos técnicos:** existe una referencia HTML v0.6 preservada, trabajo del motor Go y cliente Godot 3D desarrollado en PR separadas; la rama `main` no contiene necesariamente esos cambios. La PR #21 es consolidación y #22–#25 son investigación/optimización gráfica no integrada. No presentar un pipeline CI correcto como validación de FPS en Iris Xe.

**Decisión nueva:** 2D cartográfico de alto detalle pasa a ser la **dirección principal de producto**. Go mantiene toda la simulación. La experiencia 3D deja de estar en el camino crítico y se retomará **solo cuando financiación, hardware, herramientas de IA, especialización y capacidad de reclutar equipo lo justifiquen**.

**Sin decisiones aún:** cliente 2D definitivo, fuente terrestre, licencias de datos, presupuesto, fecha inicial, alcance de sim histórica, financiación y motor 3D posterior.

## Etapa A — Congelar evidencia y preparar transición reversible

**Objetivo:** asegurar continuidad del trabajo antes de cambiar la representación.

**Entregables:**
- Inventario del código y PR que contienen la última simulación Go, TCP, exportaciones y cliente 3D.
- Estado de tests Go, determinismo, replay, golden, UI y rendimiento realmente ejecutados.
- Conservación de builds, artefactos y capturas 3D sin eliminar archivos ni rehacer historia.
- Contrato de vista independiente de presentación: IDs, coordenadas, snapshots, diffs, eventos y consultas bajo demanda.
- Documentación de decisiones y de lo que **no** se ha migrado.

**Salida:** se puede ejecutar y comparar el mismo estado Go con el visor existente y con un prototipo sin alterar la simulación.

## Etapa B — Competencia técnica de clientes 2D

**Objetivo:** escoger mediante evidencia entre **Godot 2D**, **Go + Ebitengine** y **web de escritorio/cartografía** (p. ej., Wails/MapLibre, sujetos a evaluación).

**Prototipo idéntico en las tres opciones o en finalistas:**
- Vista mundial y una región cargada desde datos reales de Go.
- Zoom, desplazamiento, selección de provincia, un mapa político y una capa física.
- Inspector y cronología conectados a estado real; una transición anual visible.
- Prueba de cientos/miles de símbolos o eventos a diferentes escalas, sin inventar complejidad causal.
- Mismas condiciones Windows, resolución y escenarios para comparar.

**Evaluación:** FPS y frame P50/P95/P99, carga inicial, RAM, velocidad de consulta, años/s durante reproducción, accesibilidad/legibilidad de la interfaz, mantenibilidad, dificultad de migración y calidad visual. **60 FPS a 1080p en hardware actual es meta aspiracional**, no resultado garantizado; publicar el mínimo aceptado al medir.

**Salida:** ADR de cliente seleccionado con evidencias; los prototipos descartados quedan como experimentos, no se fusionan por defecto.

## Etapa C — Atlas terrestre 2D de alta fidelidad

**Objetivo:** pasar a Tierra reconocible con cartografía estéticamente cuidada.

**Trabajo:**
- Seleccionar fuentes de elevación, costas, hidrografía, biomas/uso del suelo según alcance y licencias.
- Versionar dataset, proyección, topología, traducción coordenadas→celdas y semilla de historia.
- Preprocesar mapas base, relieve sombreado, niveles de escala y regiones/cachés.
- Mantener las fronteras políticas como capa dinámica de la historia, no copiar países modernos.
- Manejar antimeridiano, polos, selección y cambios físicos donde las reglas lo permitan.

**Salida:** mismo dataset y semilla reproducen geografía/IDs; selección y fronteras encajan; no se asignan falsamente culturas o Estados modernos.

## Etapa D — Atlas exploratorio y observador

**Objetivo:** que el usuario investigue la historia, no solo vea colores cambiantes.

**Trabajo:** capas política/cultural/religiosa/económica/ambiental, nombres adaptativos, ciudades y rutas; paneles profundos, navegación entre entidades, búsqueda, mapas históricos y cronología por provincia/civilización/ciudad; velocidad, pausa y modo observador puro.

**Salida:** seguir durante siglos una sociedad real de Go, hallar cambios y consultar estados/causas registradas; ninguna afirmación de la interfaz no tiene respaldo.

## Etapa E — Vertical slice de transformación y legado

**Objetivo:** demostrar la identidad específica de Asabiya antes de aumentar el catálogo de mecánicas.

**Ciclo:** comunidad → desarrollo → asentamiento/instituciones → crisis posible → transformación/abandono → persistencia → ocupación/reutilización posterior.

**Trabajo pendiente:** IDs estables de sitios/construcciones; condición material, reparación/daño, demolición, ruina, reutilización; registros de causas y eventos; símbolos e ilustraciones 2D por condición/época y capas arqueológicas.

**Salida:** varias configuraciones reproducibles producen consecuencias persistentes; una sociedad posterior encuentra datos reales de un sitio anterior; historia visible a escala mundial/provincial/local. Una presentación guionizada no certifica emergencia.

## Etapa F — Profundidad sistémica y siglos de historia

**Objetivo:** ampliar capacidad causal sin multiplicar deuda técnica.

**Candidatos:** economía y rutas comerciales emergentes; ciudades capitales/abandono/saqueo; instituciones, legitimidad, cohesión y estratos sociales; sucesión; recursos minerales/energía; religiones y culturas; plagas, ecología y cataclismos. La prioridad se define por dependencias causales y observabilidad, **no por cantidad de features**.

**Salida:** evidencia de interacción entre sistemas, estado, consecuencias y trazabilidad; benchmarks históricos largos reproducibles, sin perder UX del atlas.

## Etapa G — Futuro tecnológico, regresiones y patrimonio complejo

**Objetivo:** permitir crecimiento desigual y regresiones creíbles desde edades tempranas hasta industrias complejas, fusión, cyberpunk u operaciones orbitales.

**Trabajo:** separar conocimiento, manufactura, infraestructura, fuentes de energía, especialistas y mantenimiento; introducir destrucción y obsolescencia; trazabilidad de ruinas avanzadas y herencia cultural.

**Salida:** una región puede perder capacidades sin borrar automáticamente su patrimonio; no se fuerza transición global simultánea ni una ruta tecnológica única.

## Etapa H — Sostenibilidad, financiación y equipo

**No bloquea el producto 2D personal.** Cuando exista una demostración estable, investigable y atractiva, evaluar opciones sostenibles de financiación y colaboradores según necesidades reales. El uso actual es personal/no comercial; otro modelo de distribución requiere decisión específica.

Documentar arquitectura, procesos de build, licencias, arte, diseño, perfilado y onboarding para que cualquier especialista pueda trabajar sin depender permanentemente de un asistente de IA.

**Salida:** capacidad presupuestaria y operativa demostrable, equipo o socios adecuados, IP/assets auditados y plan verificable de desarrollo 3D.

## Etapa I — Cliente 3D futuro, condicionado

**No se inicia automáticamente por terminar la etapa G.** Evaluar un renderizador según requisitos de ciudades, terreno, cámara, atlas y hardware, sin asumir que Godot, Unity o Unreal será la elección final.

Portar **representación** (terreno, modelos, vegetación, LOD, materiales, UI de inspección), no los cálculos históricos. Validar equivalencia de IDs/estados/eventos entre 2D y 3D. Conservar atlas 2D como modo de consulta cuando aporte valor.

**Salida:** comparación verificable, rendimiento medido, arte aprobable y presupuesto sostenible; ningún compromiso de calendario antes de esa evidencia.

## Reglas para ordenar el trabajo

1. Una prioridad técnica o de UI a la vez cuando compitan por los mismos archivos; PR independientes y sin merge automático.
2. Mantener los documentos técnicos anteriores como **historia de sus ramas**, no reescribir resultados retroactivamente.
3. Las metas de rendimiento son **criterios a validar en hardware real**, nunca resultados anticipados.
4. No agregar Tierra, ruinas o eras futuristas como si fueran funcionalidades existentes.
5. Preferir la vertical slice causal y consultable a una lista extensa de mecánicas incompletas.
6. Revisar dependencias y decisiones abiertas al terminar cada etapa.

**Próxima acción recomendada:** inventario de contratos Go y una prueba Atlas 2D usando un estado existente, separada de PR #22–#25. No cancelar ni fusionar esas PR por este cambio de dirección.
