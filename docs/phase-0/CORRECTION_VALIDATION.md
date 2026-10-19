# Pruebas correctivas: resultados y límites

Entorno ejecutado por Codex: **Windows x64 LE, Node 24.19.0, V8 13.6.233.17-node.51, ICU 78.3, Unicode 17.0**. Las mediciones de Claude en Go/Linux se conservan como evidencia recibida, sin atribuirlas a este entorno. Los jobs nuevos de GitHub se verifican en la PR; su resultado posterior queda también en el paquete de entrega. Una matriz YAML no prueba una plataforma.

## Ejecutado y aprobado localmente

| Comprobación | Resultado |
|---|---|
| `verify-reference.mjs` contra el archivo real de Descargas | Igualdad byte a byte, 1 553 001 bytes y SHA-256 original. Cierra la comparación local que el auditor no pudo hacer desde su entorno. |
| Archivos protegidos contra blobs del HEAD auditado | `.gitattributes`, smoke, verificador, evidencia original, inventario original, SHA256SUMS y manifest intactos; HTML conserva su blob original. |
| `check-reference-golden.mjs` | Pasa contra los cinco hashes y ocho sorteos originales de cada escenario; no se actualizó ningún valor de referencia histórico. |
| `test-oracle-contracts.mjs` | Wrapper RNG transparente: mundo/estado y continuación coinciden con ejecución sin contador. Fórmula probada con semillas límite y posiciones 0/1/2/65537; caso mínimo de iteración viva `[1,2,3,99]` aprobado. |
| Posición histórica tras tres años en Tierra, sin presagio | Seed uint32 3245295878, 46 912 llamadas, estado 544991558. La reconstrucción reproduce ocho sorteos. |
| `test-exact-state.mjs` | Distingue orden de propiedades/Map, −0/+0, arrays tipados, alias, ciclos y arrays dispersos; rechaza funciones sin posición RNG explícita. |
| Inventario de colecciones | 130 ForOfStatement cotejados con AST Acorn 8.17.0 del Node fijado; checker independiente exige la evidencia. No es análisis estático completo de alias. |
| Corpus matemático rápido | 27 869 vectores V8, incluyendo casos límite; regeneración de resultados compara SHA contra su baseline nueva. |
| Corpus matemático extenso | 2 601 245 vectores V8 generados; resúmenes por función. Sin comparación con Go ni promesa sobre todo binary64. |
| Fixture tardío, una generación completa | Tierra/historia 1, ajuste climático, defaults, sin comandos, −9000→−3500. Primer estado −3837, primera guerra −3619; final: 8 estados, 5 guerras y 1 098 registros de pueblos. Coincide con hitos/estados/guerras informados por Claude. |
| Posición RNG del fixture tardío | Seed 3245295878, 99 869 912 llamadas, estado 592143294; continuación de ocho sorteos reconstruida exactamente. |

Fixture nuevo: `evidence/reference-late.earth-history1.node24.json`. Hash full-S final: `eb6326feccc32ae93d7d7f5c8c2e312dae9a7e998006b8b491405850d55f5ade`. No reemplaza la evidencia de 54 años ni altera el HTML. La cifra de 103 117 788 llamadas mencionada por el auditor junto a 5 681 años no se usa como baseline de −3500: desde −9000 hasta −3500 hay 5 500 años, y el punto exacto de aquella cuenta no está especificado inequívocamente. Se registra la cuenta observada en el punto explícito, sin ajustarla para hacerla coincidir.

Una generación tardía no se presenta como dos procesos independientes aprobados. Su siguiente reproducción exacta se puede ejecutar con `reference-late.mjs --verify`, en segunda revisión o workflow extenso manual. El hash y los datos esperados ya están fijados; las verificaciones no escriben fixtures. Los tiempos no se usan como benchmarks.

## CI corregido

`reference.yml`: Node exacto, acciones por SHA, PR y push a main sin duplicado de push de rama, matriz Windows 2022 y Ubuntu 24.04. Verifica referencia, golden original, RNG, codificador e inventario, además del corpus rápido. `reference-extended.yml`: ejecución manual separada, corpus de 2,6 millones y fixture tardío. No hay cron ni automatización externa creada. GitHub puede exigir presencia del workflow en la rama por defecto para exponer el botón manual; no se integra main para habilitarlo.

Primera ejecución correctiva de Windows (run 39194292609): el verificador detectó que el checkout con autocrlf transformó SHA256SUMS a CRLF; el HTML mantuvo su hash. Se corrige la configuración del runner efímero antes de checkout (`core.autocrlf=false`) en ambos workflows, sin modificar el verificador, el HTML ni los valores esperados. El resultado de la repetición del nuevo HEAD se registra en la PR y en la entrega final; el fallo previo no se oculta como aprobado.

## Pendiente y fuera de las afirmaciones de esta entrega

- Para el perfil native **no es obligatorio implementar `internal/jsmath` ni comparar cada salida con V8**. Verificar reproducibilidad y estabilidad con `math` de Go en el entorno Windows x64 real al existir el motor. Jsmath y análisis exacto V8 sólo si surge una necesidad demostrada.
- Ejecutar el futuro binario Go en el equipo objetivo Windows x64; todavía no hay compilación/validación de Go. Linux, ARM64 y big-endian quedan fuera de alcance. GOAMD64=v1 no garantiza identidad entre CPUs con distintas capacidades FMA.
- Repetición independiente del fixture tardío y todas las guerras/los ocho presagios/causas estructuradas de largo plazo.
- Diseño de proyección de eventos por sistema y su comparador Go; mantener visibles los campos narrativos excluidos.
- Implementar/validar guardar/restaurar, UI, concurrencia elegida y benchmarks Go; no existen mecánicas Go en esta fase.
- Segunda auditoría estática de Claude concluida: APROBADA CON CONDICIONES documentales; el usuario fijó el alcance Windows x64 y retiró jsmath obligatorio. Merge/tag e inicio de Fase 1 requieren autorización del usuario por separado. Tag legacy-v0.6 no creado.

## Discrepancia matemática remota conservada

En run 39194565396, Windows aprobó las comprobaciones (resultado final verificable en la PR); Linux aprobó referencia, golden original, RNG, codificador e inventario, y falló en diagnose-pow con 3/2 273 diferencias de un ULP frente a Windows. La ejecución anterior también falló en el SHA de pow (c7b803… frente a 73330a…). Se guardan vectores concretos, hash y enlaces de job en evidence/math-pow.platform-mismatch.node24.json. El origen preciso no está demostrado.

La diferencia matemática observada **no se resuelve ni oculta**: se conservan el diagnóstico estricto, los datos esperados y los resultados históricos. Por decisión posterior del usuario, Windows x64 es la única plataforma obligatoria; Linux permanece como diagnóstico opcional (`continue-on-error`) y su fallo no bloqueará el workflow. No hay validación matemática multiplataforma, pero tampoco es requisito. Jsmath ya no bloquea la migración nativa. La reproducción independiente del fixture tardío sigue pendiente; no depende de ocultar esta diferencia.

El workflow extenso manual usa Windows 2022, coherente con el origen de sus corpus, para poder verificar esa baseline y después la historia tardía. La matriz rápida mantiene Linux y la comparación estricta fallida; mover la prueba extensa no elimina ni relaja ese control. El oráculo JavaScript original sigue fijado para el legado. El producto native se implementará con math de Go para Windows x64 y se comprobará su propia reproducibilidad, sin equivalencia bit a bit obligatoria con V8.

## Decisión posterior a la segunda auditoría — alcance Windows x64

Esta sección actualiza el criterio de aceptación, **sin reinterpretar ni borrar los resultados históricos anteriores**. La segunda auditoría estática de Claude concluyó APROBADA CON CONDICIONES y recomendó actualizar los documentos; el usuario decidió priorizar el motor nativo personal Windows x64 y postergar equivalencia numérica exacta Go/V8. Por tanto, la CI de Windows es obligatoria y la de Linux es informativa con aserciones intactas, mientras que el uso de `math` Go en native es aceptable. Este cambio documental no se confunde con un resultado de pruebas Go, que aún no existen.
