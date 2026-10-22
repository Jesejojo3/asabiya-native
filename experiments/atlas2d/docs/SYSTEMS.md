# Sistemas y límites

Go conserva geografía/clima/ecología, población, pueblos/cultura/lenguas,
estados/gobernantes, tecnología, religión, ciudades, guerras, migración,
enfermedad, rutas, eventos, presagios y cataclismos. Presencia en el motor no
significa que este primer panel exponga todos los sistemas.

El atlas presenta terreno fino sombreado, costas, provincias/IDs, ocho capas,
población/propietario/pueblo/cultura/religión/capacidad/bioma/altitud; en pausa
consulta cohesión/integración/fortificación/ciudad e historial de propiedad.
Ciudades: puntos y nombres de registros reales al acercarse; no se interpreta
la población provincial como población urbana. Historial provincial: observación
cada 10 años; no fecha exacta de conquista. Crónica: cinco de hasta 1000 eventos
publicados por el adaptador; no pretende ser el archivo completo.

Pendientes: Tierra real y licencias/dataset/versionado; leyendas y búsqueda
cartográfica más completas; editor de reglas/órdenes; consulta enciclopédica de
todas las entidades; guardar/recuperar sesiones; navegación por todo el archivo
histórico, no sólo últimas 24 publicaciones; accesibilidad y diseño final;
cronología enriquecida; idiomas de eventos (Go actualmente mezcla inglés).

Construcciones y ruinas persistentes no tienen contrato causal completo. El
punto de extensión está en `atlas_symbols.gd`: consumir futuras entidades
versionadas por ID, posición, tipo y período de existencia. No derivar ruinas de
una textura ni estructuras causales de un índice de fortificación. Reutilizar
los mismos datos en el futuro observador 3D, sin moverlos al cliente.
