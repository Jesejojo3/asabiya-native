# ASABIYA — Principios y constitución de diseño

**Estado:** criterios de producto para evaluar propuestas. No reemplazan los contratos técnicos existentes ni conceden autorización automática para modificar código.

## Reglas fundacionales

### P1. La historia ocurre sin el jugador

El motor debe poder generar cambios y conflictos durante una sesión de observación pura. Toda intervención debe ser opcional y quedar registrada.

**Comprobación:** iniciar una campaña sin comandos de intervención, avanzar y poder investigar transformaciones reales.

### P2. Emerger antes que guionizar

La formación y caída de Estados, difusión cultural, desarrollo técnico y cataclismos se resuelven mediante condiciones e interacciones, no por fechas históricas obligatorias.

**Comprobación:** variar condiciones o semilla y observar resultados diferentes explicables; repetirlas debe reproducir el mismo resultado en el entorno objetivo.

### P3. Persistencia y causalidad histórica

Las construcciones, instituciones, poblaciones, conocimientos y alteraciones ambientales no se eliminan simplemente porque cambie una era o desaparezca su creador.

**Comprobación:** observar al menos una consecuencia persistente tras un cambio de gobernante, Estado o asentamiento.

### P4. Tecnología regional y multidimensional

La capacidad tecnológica no es un único nivel global. Distinguir, cuando corresponda, conocimiento conservado, capacidad productiva, energía, infraestructura y organización social.

**Comprobación:** una sociedad puede conservar un vestigio avanzado sin disponer automáticamente de medios para construirlo o repararlo.

### P5. Un atlas terrestre, muchas historias

El producto principal usa un atlas 3D plano de la Tierra. Topología y fuentes geográficas deben ser identificables; las fronteras políticas y la trayectoria de las sociedades son emergentes.

**Comprobación:** reproducir una configuración sobre una versión de atlas, y distinguir claramente coordenadas físicas de divisiones políticas simuladas. El generador anterior se conserva como referencia técnica mientras se migra.

### P6. La misma verdad en todas las escalas

Mapa mundial, provincia, localidad, cronología e inspector consultan el mismo estado causal o el mismo historial. La presentación no fabrica acontecimientos para decorar.

**Comprobación:** una transición política o destrucción material coincide entre vista global, detalles de provincia y registro histórico.

### P7. Coherencia visual a través del tiempo

La cartografía, selección, navegación y jerarquía visual conservan una lógica común entre eras. Arquitectura, materiales y ruinas reflejan cultura, tecnología y deterioro.

**Comprobación:** el usuario puede leer quién controla un lugar, qué hay allí y qué cambió sin aprender una interfaz nueva por cada era.

### P8. Determinismo, trazabilidad y pruebas

Go es la **única autoridad causal**. Godot visualiza e interroga datos; las intervenciones entran por contratos explícitos. Conservar reglas de RNG, calendario, huellas/replay, referencia HTML v0.6 y suites de regresión.

**Comprobación:** las entradas equivalentes reproducen el estado esperado bajo el contrato de determinismo vigente; discrepancias no se encubren actualizando golden sin justificación.

### P9. Rendimiento y complejidad presupuestados

El motor y el atlas deben poder representar historias largas sin cargar en 3D todo el detalle del planeta a la vez. El detalle local es dependiente del zoom; el contenido causal persiste aun cuando no está renderizado.

**Comprobación:** registrar FPS, tiempos de frame, memoria y coste de avance con escenarios comparables, en especial en Windows x64 y hardware integrado objetivo. No afirmar mejoras sin pruebas.

### P10. Una función debe aportar una experiencia investigable

Una mecánica que no genera consecuencias, no cambia decisiones de las sociedades o no puede observarse requiere una justificación especial.

**Comprobación:** documentar al menos una cadena entrada → efecto → persistencia/resultado → evidencia visible.

## Puerta de aceptación de nuevas funciones

Toda propuesta relevante debe responder antes de implementarse:

1. **Propósito:** ¿qué experiencia central mejora y qué problema observable resuelve?
2. **Causa:** ¿qué datos la producen y qué sistemas afecta?
3. **Legado:** ¿qué ocurre con sus consecuencias al desaparecer la sociedad responsable?
4. **Observación:** ¿en qué mapa, panel o cronología pueden investigarse?
5. **Compatibilidad:** ¿cómo mantiene contratos, determinismo, replay y pruebas?
6. **Coste:** ¿qué impacto tiene sobre CPU, GPU, memoria, longitud de campañas y mantenimiento?
7. **Evidencia:** ¿qué prueba o criterio demostraría que funciona y cuándo rechazaríamos la PR?

Si no hay respuestas verificables, reducir el alcance o aplazarla.

## Disciplina de desarrollo

- **Una PR, un propósito comprobable.** Separar refactor, performance, nuevas reglas causales, UI y documentación salvo dependencias justificadas.
- Antes de borrar o mover archivos, comprobar consumidores, referencias y riesgos de compatibilidad.
- Identificar siempre **visión**, **implementación**, **prueba automática** y **validación empírica** como estados distintos.
- No fusionar ramas ni actualizar referencias históricas sin revisión y autorización.
- El responsable no técnico debe recibir un informe comprensible: cambio, motivo, archivos afectados, pruebas, riesgos y criterio de aceptación.
- Los cambios de diseño aprobados se registran explícitamente en estos documentos; no se deducen del comportamiento accidental de una rama.

## Ejemplo de verificación

**Hipótesis:** tras una guerra devastadora, una ciudad puede perder la capacidad de operar su infraestructura avanzada, mientras sus edificios siguen existiendo.

**Datos:** daños, población, mantenimiento, especialistas, redes de energía y estado de edificios.

**Resultado esperado:** deterioro gradual y recuperaciones potenciales diferentes por territorio; no una regresión global instantánea.

**Evidencia:** datos de Go, evolución determinista en varias configuraciones y representación coherente de la ruina en Godot cuando el contenido sea visible.

Este ejemplo es una **propuesta futura**, no una mecánica actualmente certificada.
