# Iteración y alias de colecciones — I2 y O2–O5

El inventario AST `evidence/collection-iteration-inventory.json` enumera los **130 ForOfStatement del core** con función, línea y colección. Se obtuvo con Acorn 8.17.0 incluido en Node 24.19.0, fuera del HTML; es un inventario sintáctico, no una prueba automática de alias ni de frecuencia en partidas. El código original es la autoridad; el port revisará cada entrada antes de traducirla.

## Caso crítico comprobado

`politicsG` asigna `s.alive=next` (1658); recorre `next` (1663); `civilWar` (1685–1686) llama `newPolity` (1288), que añade a `s.alive` (1240). El iterador JS visita los IDs añadidos durante ese mismo recorrido. La prueba mínima `tools/test-oracle-contracts.mjs` lo confirma sin modificar el legado; no mide su frecuencia real.

Regla de port: un **único campo propietario** para esa lista. Recorrer por índice con longitud reevaluada sobre ese campo en cada iteración. No usar `range` con longitud capturada, ni dos cabeceras slice `next`/`alive` que se separen al hacer append. Si se realoca el almacenamiento, todos los accesos relevantes siguen leyendo el campo propietario. No sustituir un recorrido vivo por una copia para evitar un error de índices: cambiaría visitas y RNG.

## Inventario de riesgos y decisiones

| Colección / sitio | Revisión de mutación y regla |
|---|---|
| `next` / `s.alive`, politicsG 1658–1686 | Crecimiento transitivo confirmado por civilWar/newPolity. Mantener visitas a nuevos rebeldes y sus sorteos. |
| `s.alive`, politicsG 1624/1631/1752/1801 y otras funciones | El objeto lista puede reemplazarse y sus registros mutan; no asumir que un alias local sigue viendo el campo tras reemplazo. Revisar por fase y llamada; conservar orden. |
| `s.inf`, disease 1169 | La propagación crea la lista `nl` para la siguiente generación; no confundir `nl.push` con crecimiento del iterador de entrada ni anticipar infecciones. |
| `s.outbreaks`, disease 1168/1183 | Mutación de registros y propagación; conservar orden de creación, filtrar sólo donde lo hace el legado. |
| `s.activeWars`, politicsG 1743 | Cambian bandos/fin de guerras, y la lista se filtra tras procesarlas. No compactarla durante el recorrido ni visitar elementos fuera del orden del legado. |
| `s.activeMigs.slice()`, politicsG 1802 | Snapshot explícito: `migStep` puede terminar y alterar migraciones. Preservar la copia; no convertir todos los recorridos a vivos por una regla global. |
| `o.enemies`, politicsG 1633; `o.nb`, diplomacia/política | Maps con efectos en mapas relacionados; conservar orden de inserción, borrados y revisitas. No usar range de map Go. |
| `allies`, `war.a`, `war.d`, `ids`, `cells` | Diferenciar listas nuevas, compartidas y resultados de filter/slice. Funciones pueden cambiar entidades referidas sin cambiar la lista. No deduplicar ni ordenar por conveniencia. |
| `E`, eths, ciudades, omens, snapshots | Registros mutables, posible creación fuera de esa pasada y mapas de años. Inventario completo adjunto; verificar alta/baja por sitio al portar, no concluir inmutabilidad por el nombre. |

En Map/Set ECMAScript se conserva orden de inserción y las adiciones/borrados afectan iteradores vivos; borrar y reinsertar puede mover una clave al final. Traducir a una estructura ordenada con semántica de visita definida, no ordenar por ID tras cada operación. La futura prueba de cada sistema incluirá inserción, eliminación y reinserción durante su recorrido. El inventario no pretende demostrar que las 130 colecciones crecen; identifica todos los sitios que requieren conservar su semántica.

O2: `[a,b].sort()` sin comparador ordena por representación de cadena, incluyendo las claves de caravanas (2041) y `cropX` (2054). Con IDs 9/10, la clave canónica compatible es `10:9`. Usar orden numérico sólo sería una versión nueva de `native`, nunca una «limpieza» de la referencia.

O3: `Object.entries(CATA)` (2226) determina el orden de acumulación y selección. Los catálogos causales futuros serán **listas ordenadas** con IDs estables; no objetos JSON que terminen en map Go. Validar duplicados y orden al cargar.

O4: `decodeEarth` usa Int16Array (414–417). Para el ámbito fijado LE, la decodificación Go futura usa little-endian explícito y acumulación float64 con conversión float32 sólo al escribir. No atribuir esa validación a una máquina big-endian.

O5: el smoke histórico ordena propiedades y pierde −0 en números JSON. Se conserva intacto; se añade `encodeExactState` v2 para el comparador futuro, con orden ECMAScript, alias/referencias, bits float, arrays tipados LE y distinción −0/+0. Sus pruebas comprueban esos casos; no es un formato de guardado ya implementado ni un comparador Go.
