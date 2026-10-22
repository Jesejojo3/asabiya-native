# ASABIYA — Constitución de diseño (2D primero)

**Estado:** criterios rectores vigentes desde 21-10-2026; no son prueba de implementación ni autorizan por sí solos cambios de código.

## Principios innegociables

### P1. Emergencia autónoma y observación
La historia avanza sin órdenes del jugador. Existe una modalidad de observación pura; intervenir es opcional y trazable.
**Prueba:** campaña sin comandos produce cambios consultables y reproducibles.

### P2. Causalidad antes que cronologías prefijadas
Los acontecimientos proceden de condiciones y relaciones entre sistemas. La historia real inspira parámetros, no una lista obligatoria de sucesos.
**Prueba:** misma configuración reproduce resultados; condiciones distintas producen alternativas explicables.

### P3. Una única autoridad histórica
**Go decide; las interfaces representan.** El atlas 2D, el Godot 3D archivado y futuros visores no inventan cambios, fechas, guerras ni ruinas. Los comandos entran por contratos versionados.
**Prueba:** para la misma instantánea, todos los clientes describen identidades, años y hechos equivalentes.

### P4. Persistencia y memoria intergeneracional
Ciudades, construcciones, infraestructuras, conocimientos, instituciones y marcas ambientales no desaparecen arbitrariamente por cambio de era o gobernante.
**Prueba:** sitio/legado verificable después de perder a su constructor.

### P5. Tierra fija como referencia, historia variable
La dirección geográfica es una Tierra real versionada, sin imponer países modernos ni la cronología histórica. Sus cambios físicos futuros requieren reglas causales y fuentes comprobables.
**Prueba:** IDs/vecindades/posiciones coherentes con el atlas, mapa real verificable y partidas reproducibles.

### P6. Tecnología regional y multidimensional
Energía, conocimiento, especialistas, manufactura, redes, infraestructura e instituciones evolucionan de forma parcialmente independiente. No hay una era única obligatoria para todo el planeta.
**Prueba:** pérdida o preservación de capacidades según variables y no por cambio instantáneo de etiqueta.

### P7. Máximo detalle histórico, visualización progresiva
El objetivo no es el número máximo de objetos simultáneos, sino la mayor cantidad **útil, correcta y legible** de información al explorar. Mundo, región, provincia y localidad revelan progresivamente relieve, biomas, ciudades, rutas, construcciones y ruinas.
**Prueba:** zoom y capas aportan detalle sin saturación ni disparar complejidad por cada celda fuera de pantalla.

### P8. La misma verdad en mapa, inspector e historial
Los paneles, cronologías y la cartografía se apoyan en estado y eventos reales. Separar datos confirmados, inferencias explicativas y elementos no disponibles.
**Prueba:** una ocupación o construcción muestra fecha, ID y relación causal consistentes donde se consulte.

### P9. Diseño independiente del medio
La simulación no contiene imports ni dependencias de sprites, shaders, escenas 3D, UI ni reloj gráfico. Coordenadas, IDs, eventos y persistencia deben sobrevivir a un cambio de cliente.
**Prueba:** la misma simulación puede ejecutarse headless y alimentar al menos un visor sin mutar el estado.

### P10. Rendimiento medido, no prometido
Presupuesto explícito de CPU, GPU, RAM, coste de avance y latencia de inspección. Preferir diffs, cachés, índices y streaming por región.
**Prueba:** escenarios comparables en Windows x64 muestran FPS y P50/P95/P99, memoria y años/s; resultados ajenos/headless no se presentan como Iris Xe.

### P11. Un ciclo completo supera cien mecánicas aisladas
Una feature debe reforzar una cadena causa → transformación → legado → explicación accesible.
**Prueba:** vertical slice reproducible de comunidad, crisis, cambio y huella histórica.

### P12. 3D futuro sin deuda arquitectónica irreversible
El 2D es producto útil, no trabajo descartable; el 3D se retoma con financiación, hardware, herramientas y equipo suficientes. Conservar el prototipo 3D y evitar atar datos al 2D.
**Prueba:** entidades históricas persistentes no dependen de coordenadas de pantalla, nombres de nodos ni assets.

## Puerta de aceptación de cualquier nueva función

Cada propuesta debe responder:

1. **Experiencia:** ¿qué podrá observar o investigar el usuario?
2. **Causa:** ¿qué variables y reglas producen el resultado?
3. **Persistencia:** ¿qué huellas deja y quién puede heredarlas?
4. **Escalas:** ¿cómo aparece en mapa mundial, región, provincia, sitio e historial?
5. **Autoridad:** ¿qué calcula Go y qué se limita a dibujar o consultar el cliente?
6. **Coste:** ¿qué presupuestos de CPU/GPU/memoria/tiempo anual consume?
7. **Compatibilidad:** ¿qué contratos, RNG, hashes, replay, saves y referencias protege?
8. **Prueba:** ¿cómo medimos aceptación y qué resultado descartaría la idea?

Si no hay respuestas, recortar alcance o postergar.

## Disciplina de ingeniería

- Una PR y una responsabilidad verificable; separar cambios causales, interfaz, render, rendimiento y documentación.
- Verificar HEAD reales antes de editar, no asumir que main contiene ramas abiertas.
- No fusionar, borrar trabajo ajeno ni alterar oráculos y golden sin autorización.
- Mantener trazabilidad de IDs, semillas, archivos de datos, builds y evidencias.
- Informar de manera explícita: visión / especificación / implementación / CI / validación en PC / aceptación.
- No introducir 3D, Unity o CK3 en el camino crítico del prototipo 2D.
- No usar la presión de financiación o la disponibilidad de IA como justificación para generar código inmantenible.

## Ejemplo de criterio de producto

**Situación hipotética:** una sociedad con fusión sufre una guerra, pierde su red energética y especialistas, conserva parcialmente archivos e instalaciones; siglos después un pueblo agrícola reutiliza las ruinas.

**Evidencia exigible:** estados y eventos Go trazables; reglas de deterioro y conservación; sitio con ID estable; icono arqueológico e historial coherentes en atlas 2D; una futura vista 3D sería otra representación del mismo objeto. Este caso es **diseño futuro**, no código ya comprobado.
