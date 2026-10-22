# Asabiya 3D futuro — condiciones, equipo y continuidad técnica

**Estado:** visión de evolución futura. **No autoriza** comenzar una migración, contratar personal o comprometer gastos. Asabiya es actualmente un proyecto de uso personal.

## 1. Decisión

**Primero:** conseguir un Atlas 2D profundamente histórico, atractivo, fluido, mantenible y alimentado por Go.  
**Después, si se reúnen las condiciones:** producir una experiencia 3D a partir de la simulación y los registros históricos existentes.

El 3D se **aplaza, no se abandona**. No es un premio automático ni una obligación de lanzar un producto comercial. La dirección 2D tiene valor permanente.

## 2. Por qué aplazamos el 3D

La implementación Godot 3D previa requiere inversión en terreno, shaders, sombras, cámaras, LOD, modelos, arte, UI, pruebas y optimización en hardware integrado. Ese trabajo compite con la profundidad sistémica y la investigación histórica.

Una versión 2D permite validar lo distintivo: causalidad, evoluciones no lineales, ruinas, legado, cartografía e inspección. **No se afirma que 2D sea automáticamente más rápido**; el prototipo deberá medirlo.

El cliente 3D actual, sus benchmarks, diseños y contratos **no se borran**. Se preservan como activo técnico y fuente de aprendizaje.

## 3. Condiciones para reconsiderar seriamente un cliente 3D

Evaluar conjuntamente estas puertas, sin fijar fecha:

1. **Producto:** una experiencia 2D estable y atractiva, con al menos una vertical slice causal completa de civilización y legado.
2. **Finanzas:** recursos de desarrollo sostenibles, presupuesto para herramientas, hardware, contratación/colaboración y mantenimiento, sin depender de una predicción incierta.
3. **Equipo:** capacidad de coordinar programación gráfica/engine, optimización, arte técnico 3D, UI/UX, QA y mantenimiento de Go.
4. **Cómputo:** estaciones y GPUs suficientes para desarrollo y pruebas, además de objetivos explícitos de hardware de jugadores.
5. **Herramientas de IA:** disponibilidad razonable como aceleradores de trabajo, no dependencia obligatoria para entender, compilar o mantener el proyecto.
6. **Arquitectura:** contratos de datos versionados, IDs estables, guardado/replay reproducible y separación real entre core y presentaciones.
7. **Derechos y activos:** licencias claras de cartografía, música, imágenes, modelos y cualquier reutilización de tecnología externa.

La falta de una sola condición puede justificar posponer 3D sin bloquear la evolución histórica del 2D.

## 4. Cómo reclutar y organizar un equipo cuando sea oportuno

No comenzar con un número arbitrario de contrataciones. Definir roles por cuellos de botella medidos y entregables concretos:

| Perfil | Responsabilidad eventual | Criterio de necesidad |
|---|---|---|
| Líder técnico/arquitectura | Go–cliente, datos, mantenimiento y calidad | integración entre subsistemas supera capacidad individual |
| Programador gráfico 3D | terreno, cámara, renderer, LOD, GPU | prototipo 3D muestra requerimientos claros |
| Technical artist / modelador | pipeline de assets, materiales, edificios por cultura/era | alcance artístico y benchmarks definidos |
| UX/UI diseñador | atlas, inspección, visualización causal y continuidad 2D/3D | pruebas con usuarios evidencian fricciones |
| QA/performance | regresiones, determinismo, FPS y despliegues | complejidad de builds y hardware crece |
| Diseñador de simulación/investigación | validación de plausibilidad y economía/tecnología | ampliar sistemas requiere especialización |

El trabajo comienza con una **vertical slice 3D pequeña**, no con el planeta entero o edificios de todas las eras. Cada rol debe tener propiedad de archivos, interfaces y criterios de aceptación. Documentar onboarding, convenciones, dependencias y decisiones, para preservar continuidad si cambian asistentes o colaboradores.

## 5. Qué se reutiliza y qué no

**Objetivo de reutilización:**
- núcleo histórico Go, reglas y calendario;
- IDs de entidades y coordenadas/topología geográfica;
- semilla/dataset/replay y trazas causales;
- estados de ciudades, construcciones y ruinas;
- API de consulta/commandos y protocolos versionados;
- atlas 2D para mapas políticos, filtros, cronologías o modo de consulta.

**Rehacer o adaptar probablemente:**
- shaders, geometría y materiales;
- modelos, animaciones e iluminación;
- renderizado de agua/relieve, LOD/vegetación;
- picking/raycast, cámara cercana y UI espacial;
- empaquetado, pruebas GPU y ajustes visuales.

Una arquitectura limpia **reduce la reescritura de lógica**, pero no promete que el arte o la UI se trasladen automáticamente.

## 6. Forma de la experiencia 3D futura

La visión sigue inspirada en la navegación fluida por mapas de estrategia: zoom global → provincial → local, construcciones y ruinas visibles en terreno, fronteras y dueños emergentes, con una estética propia.

La Tierra real sirve de escenario, no de historia prefijada. Regresiones de eras de fusión/orbital a sociedades agrícolas deben poder expresarse físicamente sin borrar las ruinas de sus predecesores.

Una vista 3D representará **la misma verdad de Go** que el Atlas 2D, no una segunda simulación.

## 7. Elección de motor gráfico futura

No fijar hoy Godot, Unity, Unreal, Ebitengine 3D o CK3 como compromiso. La selección futura dependerá de rendimiento real, derechos/licencias, capacidad del equipo, tooling, fidelidad visual, interoperabilidad y sostenibilidad.

**CK3** se consideró como visor o mod personal, pero un mod estándar no expone un motor gráfico desacoplado ni reemplaza toda su lógica interna. Puede quedar como experimento de exportación o visualización, no como supuesto del roadmap. No desmantelar ejecutables propietarios ni asumir una integración inexistente.

El 3D propio mantiene independencia del juego de terceros y del calendario de sus actualizaciones.

## 8. Hitos para un prototipo 3D futuro

1. Abrir la misma geografía y selección que el atlas 2D desde un estado Go.
2. Mostrar 1 región, algunas ciudades y un sitio histórico con historial real.
3. Renderizar propietario, cultura, capas y cambios de año coherentes con Go.
4. Representar un edificio activo, abandonado y reutilizado sin cambiar su ID causal.
5. Medir FPS/frametimes, RAM/VRAM, latencia de selección y continuidad de la simulación en hardware definido.
6. Expandir solo si el equipo valida coste artístico, rendimiento y mantenibilidad.

**Producto final posible:** Atlas 2D y cliente 3D coexistentes. Si el coste no se justifica, 2D continúa como producto principal sin ser un «fracaso».

## 9. Financiación y eventual distribución

El proyecto actual es **personal y no comercial**. Se contempla la posibilidad de buscar financiación, colaboradores o un modelo sostenible **en el futuro**, sin decidir ahora comercialización ni derechos de distribución.

Antes de una publicación comercial: revisar propiedad intelectual, licencias de software/datasets/assets, acuerdos de colaboradores, viabilidad de soporte y obligaciones correspondientes. No depender de assets de CK3 ni de licencias de mods para un producto independiente.

**Medida del éxito:** que exista un simulador interesante y sostenible que un equipo pueda entender, ampliar y representar, no simplemente una colección grande de tecnologías.
