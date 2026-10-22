# Arquitectura de Asabiya Atlas 2D — especificación de transición

**Tipo:** propuesta de arquitectura para nueva vertical slice. **Estado:** decisión sobre independencia Go aprobada; selección de cliente y contratos concretos, por validar.

## 1. Restricción principal

Go conserva la **única autoridad de causalidad histórica** (año, calendario, estados, pueblos, ciudades, guerras, tecnología, economía, recursos, comandos, RNG y persistencia). La presentación 2D no determina propietarios ni crea eventos; tampoco introduce reglas históricas para mejorar una captura.

La arquitectura no debe obligar a eliminar el cliente Godot 3D, reescribir Go ni modificar el HTML v0.6.

```text
Datos geográficos versionados y condiciones iniciales
                    |
                    v
      ASABIYA CORE — Go (simulación)
    eventos/IDs/estado/semillas/huellas
                    |
                    v
      Contratos de vistas y comandos
  snapshots, cambios, consultas, historial
                    |
           +--------+--------+
           |                 |
           v                 v
    Atlas 2D principal   Cliente 3D futuro
  cartografía + UX      visualización física
```

El diagrama describe responsabilidades deseadas. **No afirma que un nuevo protocolo, datos persistentes de ruinas o un cliente 2D ya existan**.

## 2. Datos que sobreviven a cualquier cliente

Modelar y versionar en la capa adecuada:

- **Geografía:** versión/digest de dataset, proyección, coordenadas, topología, costas, elevación, hidrografía y celdas geográficas.
- **Identidad:** ID estable de provincia/celda, pueblo, Estado, cultura, religión, ciudad, sitio, construcción, evento, personaje si existe y recurso.
- **Tiempo:** año causal y secuencia, no dependiente del framerate; cambios anuales atómicos conforme a los contratos de la rama activa.
- **Estado:** propietario, población, capacidad, composición y datos relevantes para las capas; campos ausentes diferenciados de cero cuando el contrato lo exija.
- **Historia:** sucesos y relaciones con entidades/fechas, referencias verificables y límites de retención.
- **Patrimonio futuro:** origen, localización, fecha, tipo, materiales, conservación, ocupación, reparación, reutilización y destrucción de sitios/construcciones.
- **Replay/guardado:** semillas, reglas versionadas, recursos, órdenes, huellas y reproducibilidad en el entorno fijado.

Si uno de estos campos **no existe todavía**, describirlo como ampliación contractual propuesta y no falsificarlo desde la UI.

## 3. Interfaz de lectura y comando

El cliente requiere capacidades conceptuales (las firmas/operaciones reales se extraerán de las implementaciones Go y su protocolo):

1. `get_map_region(extent, layer, epoch/active_state)`: consulta o bloque de mapa para región/escala (propuesta).
2. `get_entity(id, context)`: detalle histórico bajo demanda sin explorar los 80,000 registros en cada hover (propuesta).
3. `get_history(id, time_window)`: eventos trazables, límites y paginación (propuesta).
4. `subscribe_or_poll_changes(since)`: cambios diferenciales versionados, con fallback completo (propuesta).
5. `advance / pause / intervention`: usar operaciones Go reales con semántica de año atómico, comandos validados y resultado causal confirmado.

**No imponer estos nombres como API existente.** El primer entregable es mapearlos con las operaciones y entidades que ya ofrece Go, sin romper compatibilidad de cliente 3D.

Los campos de rendimiento (timestamps, contadores, caché) pueden ser metadatos de diagnóstico; nunca deben modificar RNG o las huellas de la simulación.

## 4. Cartografía desacoplada de la simulación

Separar conceptualmente:

- **Base física versionada:** mapas raster/vectoriales derivados de fuentes autorizadas, mosaicos por región y resoluciones.
- **Capa dinámica:** Estados, pueblos, religiones, rutas, ciudades, fronteras y cambios anuales desde Go.
- **Anotaciones:** etiquetas, leyendas, iconos, ruinas, eventos y selección adaptados al zoom.
- **Herramientas de investigación:** inspector, cronologías, búsqueda, comparación de épocas y explicación de causalidad.

Un mismo evento puede cambiar un overlay y un inspector sin requerir regenerar toda la base topográfica.

No cambiar la granularidad causal de Go por cada escala visual. El cliente agrupa símbolos de forma reversible y explicita cuándo muestra una agregación estadística.

## 5. Elegir cliente 2D por prueba, no por preferencia

| Opción | Potencial | Riesgo a medir |
|---|---|---|
| Godot 2D | Reutilizar parte de GDScript, paneles y flujo de Godot; cámara e input | Costes por nodos/Canvas, migración de shaders, bridge y UX |
| Go + Ebitengine | Un solo lenguaje/proceso posible, control de sprites y datos | Reconstrucción de interfaz, tipografía, paneles e interacción rica |
| Web (Wails/MapLibre u otra) | UI documental/atlas, cronologías, capas geográficas | Coste WebView/DOM, IPC, memoria y límites de actualización |

**No está decidido ningún ganador.** Probar el mismo escenario, con igual número de provincias/símbolos/capas, resolución, densidad de datos y carga histórica.

Criterios: P50/P95/P99 de frame, RAM, carga, interacción/zoom, latencia de ficha, rendimiento de años, calidad visual, accesibilidad, tiempo de mantenimiento, compatibilidad Windows x64 y esfuerzo de preservar datos para 3D.

## 6. Escalabilidad: máximo detalle sin carga global

Diseñar con:
- cachés de atlas por región y nivel de zoom;
- teselas preprocesadas de relieve/costa/biomas;
- culling y agrupación de iconos;
- etiquetas con prioridad y colisiones;
- diffs de Estado y de capas cambiadas;
- consultas del inspector solo para el seleccionado o región visible;
- límites de memoria/retención, paginación de historial;
- workers para preprocesar datos no causales, **sin adelantar hechos de Go**.

Evitar un nodo UI por celda × layer × año; evitar volver a generar todo el mapa ante un único cambio político; no usar el FPS de render como tick de simulación.

## 7. Transición a Tierra real

Una conversión desde un generador procedural no es cambiar una textura. Se requiere un atlas geográfico reproducible (IDs, coordenadas, vecindad y proyección) y pruebas de que Go y el cliente comparten la misma topología. Deben revisarse licencias, fecha del dataset, costa histórica, antimeridiano, polos y celdas de agua/tierra.

Conservar mundos procedurales para benchmarks y tests hasta aprobar el nuevo conjunto. **No afirmar que Tierra real está terminada.**

## 8. Prueba de integración previa a cualquier port masivo

Vertical slice de cliente usando **estados reales de Go**:
- abrir mundo y ver mapa físico/político;
- seleccionar provincia y mostrar propietarios, población, cultura y datos realmente disponibles;
- avanzar varios años, reflejar cambios sin omisiones;
- abrir una cronología respaldada por eventos;
- seleccionar otra región a distinto zoom;
- registrar FPS, memoria y latencias en Windows.

Evidencia mínima: semilla/versiones, estado SHA o equivalente, resultado de pruebas de protocolo, capturas y medición nativa. Dejar escrito qué se simuló y qué es placeholder.

## 9. Condiciones de preservación y compatibilidad

- No cambiar los cálculos de Go como «optimización» gráfica.
- No reescribir contratos TCP sin negociación/migración y tests.
- No reordenar operaciones causales ni generar datos ficticios desde el cliente.
- No fusionar PR ni borrar el 3D actual durante el experimento.
- Preparar assets/IDs/eventos para que un futuro cliente 3D use los mismos datos, aunque necesite shaders, modelos y UI nuevos.

**Criterio de salida:** el proyecto puede escoger un visor 2D robusto **sin perder capacidad de simular historia ni cerrar la puerta a 3D**.
