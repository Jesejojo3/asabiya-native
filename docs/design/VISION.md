# ASABIYA — Visión fundacional y dirección vigente

**Versión conceptual:** 0.2 · **Decisión:** 21 de octubre de 2026  
**Estado:** dirección de producto acordada; no equivale a capacidades ya implementadas.

> **Un mundo. Infinitas historias.**

## 1. Qué es Asabiya

Asabiya es un **simulador histórico emergente principalmente observacional**. El usuario contempla, investiga y, si lo desea, interviene ocasionalmente en la evolución autónoma de sociedades humanas sobre la Tierra. No existe un imperio, una dinastía o una cronología obligatorios; tampoco es necesario «ganar».

El principio rector es la **continuidad histórica**. Las sociedades se organizan, prosperan, entran en crisis, se recuperan, se transforman o desaparecen; sus poblaciones, instituciones, culturas, conocimientos, paisajes y construcciones pueden afectar a nuevas sociedades siglos o milenios después.

No buscamos simular todas las variables del mundo con el mismo detalle. Priorizamos las **relaciones causales que producen transformación histórica** y la capacidad del observador de comprenderlas.

## 2. Decisión estratégica: 2D primero, 3D después

La **experiencia principal que desarrollaremos ahora es Asabiya Atlas 2D**, un atlas terrestre interactivo de alta calidad cartográfica e histórica. El paso a 2D **no reduce la ambición sistémica**: permite invertir esfuerzo en simulación, historia material, análisis y legibilidad en lugar de geometría, luces, sombras y pipeline 3D.

El **3D no se cancela**. Será una etapa futura condicionada a financiación disponible, hardware apropiado, herramientas de IA adecuadas, equipo técnico/artístico y pruebas de que la base histórica es sólida. No se promete un motor, presupuesto ni fecha de transición.

**La versión 2D debe ser un producto útil y completo en términos de simulación e investigación**, no un prototipo desechable. Eventualmente 2D y 3D podrán coexistir como dos formas de observar el mismo mundo.

El cliente Godot 3D existente se **conserva como trabajo técnico y referencia experimental**. No se elimina ni se declara inválido por el cambio de estrategia.

## 3. La Tierra es reconocible; su historia no está predeterminada

La meta geográfica es una **Tierra real**, representada inicialmente por un **atlas 2D plano** con costas, relieve, ríos, biomas y coordenadas sustentados en datos versionados y licencias comprobadas. No se reutilizan las fronteras políticas actuales como Estados iniciales obligatorios.

Pueblos, Estados, ciudades, religión, comercio, migraciones, culturas y tecnologías emergen de reglas y condiciones. Una misma geografía puede producir historias diferentes; semillas y versiones de datos permiten reproducirlas.

La geografía y su ecología también pueden cambiar causalmente (clima, nivel del mar, cataclismos), pero los mecanismos, fuentes y escalas deben especificarse. **La Tierra real aún es un objetivo de integración**, no una geografía entregada en producción. El generador procedural existente sigue siendo útil para test y como legado.

## 4. El atlas 2D debe tener máximo detalle útil

**2D no significa baja fidelidad.** Aspiramos a un atlas histórico vivo, bello y legible, con dirección artística propia: relieve sombreado, hidrografía, paisajes, capas temáticas, toponimia, rutas, fronteras y símbolos contextuales.

El contenido emerge progresivamente por **escala de zoom**:

- **Mundial:** civilizaciones, culturas, grandes Estados, religiones, migraciones, clima, cataclismos y tendencias.
- **Regional:** provincias, cambios de fronteras, ciudades, caminos, rutas comerciales, guerras, recursos y actividades económicas.
- **Provincial/local:** asentamientos, construcciones, minas, puertos, monumentos, ruinas, ocupaciones sucesivas y huellas del paisaje.

El detalle no significa dibujar todo simultáneamente. Culling, cachés por región, capas activables, etiquetas adaptativas, agrupación de iconos y consultas bajo demanda permiten un mapa limpio de lejos y muy rico al acercarse.

Cada ficha y cronología puede ofrecer una **profundidad de información superior a la de la escena dibujada**: demografía, instituciones, cultura, lengua, economía, tecnología, genealogías, edificios, cambios de dueño, causas y consecuencias.

La calidad visual se juzgará por **claridad, belleza y fidelidad al estado histórico**, no por cantidad de sprites o efectos. Los assets provisionales son válidos durante desarrollo y deben identificarse como tales.

## 5. Una misma historia en todas las escalas

Las diferentes escalas, mapas temáticos, inspectores, búsquedas, cronologías y explicaciones deben derivar del **mismo estado y registro de eventos de Go**. El cliente no asigna acontecimientos ficticios para llenar huecos.

La experiencia principal es observar una civilización, localizar sus provincias, seguir su auge, descubrir su crisis y consultar el legado presente después de su desaparición.

Si un acontecimiento no está soportado por datos causales, la interfaz debe mostrar incertidumbre, dato no disponible o un resumen explícitamente interpretativo, nunca presentar una inferencia como hecho.

## 6. El mundo se mueve aunque no intervengamos

El simulador debe sostener un **modo Observador puro**. El usuario controla pausa, velocidad, filtros y consultas; las intervenciones opcionales entran en Go como comandos trazables, no como resultados fabricados por la UI.

Asabiya no será principalmente un juego de conquista, ni una recreación fija de la historia real, ni un constructor manual de imperios.

## 7. Un modelo causal común

La historia emerge de interacciones entre:

- **Sociedad:** población, migraciones, cohesión, culturas, lenguas, religión, estratificación y transmisión.
- **Economía y ecología:** recursos, producción, excedentes, rutas, comercio, clima, alimentos y capacidad de carga.
- **Poder:** Estados, élites, legitimidad, sucesiones, administración, diplomacia y conflictos.
- **Conocimiento y tecnología:** instituciones, aprendizaje, especialistas, energía, manufactura y capacidad operativa.
- **Territorio:** ciudades, infraestructuras, suelo, caminos, monumentos y transformaciones persistentes.

La cohesión social da significado al nombre *Asabiya*, pero no es una ley rígida que condene a todas las civilizaciones a un ciclo invariable.

## 8. Eras regionales, no una escalera tecnológica universal

Sociedades contemporáneas pueden tener capacidades radicalmente distintas. El avance y la regresión tecnológica se modelan mediante dimensiones separadas: conocimiento disponible, especialistas, industria, infraestructura, energía y organización social.

Una guerra o cataclismo puede destruir instalaciones, redes y especialistas sin borrar instantáneamente bibliotecas o conocimientos. Recuperaciones y regresiones pueden tardar generaciones, diferir entre regiones y no coincidir con etiquetas únicas de «era».

Sociedades industriales, **fusión, cyberpunk y orbitales**, así como colapsos y regresiones posteriores, son horizontes del diseño a largo plazo. **No son capacidades actualmente verificadas ni resultados garantizados** de una sola catástrofe.

## 9. Palimpsesto histórico: legados y ruinas

La memoria material es un sistema causal futuro, no un decorado aleatorio. Cada sitio o construcción podrá conservar ID, localización, origen, cultura constructora, material, función, fecha, condición, daño, mantenimiento, abandono, reparación, reutilización y destrucción.

Una civilización tardía puede encontrarse con restos muy avanzados que no sabe operar. Puede transformarlos en cantera, santuario, asentamiento o sitio de estudio. La historia cultural (nombres, relatos, tabúes, conocimientos y memoria institucional) también puede sobrevivir.

En 2D estos resultados se mostrarán mediante **símbolos situados, ilustraciones, capas arqueológicas, fichas y líneas temporales**. En un 3D futuro podrán visualizarse como estructuras físicas sin modificar su historia subyacente.

## 10. Primera experiencia completa

Antes de expandir a todas las eras, construir una **vertical slice emergente y comprobable** en una región:

1. Una comunidad establece población y asentamiento.
2. Desarrolla actividades, vínculos e instituciones.
3. La combinación de presiones económicas, políticas o ambientales puede provocar crisis.
4. Se transforma, pierde capacidad o abandona infraestructuras.
5. Su legado permanece e influye en ocupaciones posteriores.
6. El observador puede reconstruir causas y consecuencias desde el atlas y el historial.

Una demostración guionizada sirve para probar UI, pero **no prueba emergencia**. Deben existir casos reproducibles de simulación real.

## 11. Límites de promesa y decisiones abiertas

Se mantienen abiertos: fecha inicial, poblamiento, resolución y proyección terrestre, granularidad provincial, archivos y datos licenciados, alcance de intervenciones, detalle de cronologías, persistencia/guardados, modelos concretos de colapsos y extensión de eras.

Tampoco se ha escogido definitivamente el cliente 2D: comparar **Godot 2D, Go/Ebitengine y una interfaz cartográfica web** con el mismo estado real de Go antes de decidir.

**Restricción transversal:** Go conserva la autoridad histórica. La cartografía 2D, la variante 3D y los visores externos son representaciones reemplazables. El éxito es **una historia emergente profunda, visible, trazable y reproducible**, no un determinado motor gráfico.
