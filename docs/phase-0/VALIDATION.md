# Evidencia y límites de validación — primera entrega

Este documento conserva el registro de la entrega auditada. Correcciones y pruebas posteriores: [CORRECTION_VALIDATION.md](CORRECTION_VALIDATION.md). Los valores de referencia aquí citados no se reemplazan.

Comprobaciones realizadas localmente el 18 de octubre de 2026, Windows x64, Node v24.19.0, endianidad LE. El resultado íntegro de caracterización se conserva en `evidence/reference-smoke.windows-node24.json`. Los scripts no tienen dependencias npm.

| Comprobación | Resultado |
|---|---|
| Acceso al repositorio y README en `main` | Confirmado por conector GitHub; base inicial `16e7e8adcb86e30b3b6e7487967bf636077b3403`. |
| Lectura del archivo local y copia binaria | Archivo de Descargas localizado antes de modificar; 1 553 001 bytes; comparación byte a byte aprobada con `verify-reference.mjs`. |
| SHA-256 + blob SHA-1 Git | Coinciden con manifiesto. GitHub devolvió el mismo blob `940af36bce0cdb05c3552f1d086ffe4290e392ac` al importar los bytes mediante base64. |
| Sintaxis JS | Compilación de los tres scripts aprobada; sólo se ejecutaron assets/core. |
| Separación estática del core | No se encontraron las referencias DOM/reloj/aleatoriedad no sembrada comprobadas por el script. No es una prueba formal de pureza. |
| Reproducibilidad del original generado | `atlas-7`, historia `1`, defaults, 54 años, sequía: dos ejecuciones idénticas en hashes de mundo/estado y ocho sorteos de continuación. |
| Reproducibilidad del original Tierra | Recursos embebidos, ajuste climático activo, historia `1`, 54 años, sequía: dos ejecuciones idénticas con los mismos criterios. |
| Seguimiento del presagio y población | Seguimiento de sequía a 50 años confirmado; población final finita y no negativa en ambos escenarios. |
| Atributos Git de la referencia | `text`, `filter`, `ident`, `diff` y `merge` comprobados como desactivados en un repositorio temporal local. |
| Revisión documental y alcance | 31 archivos; enlaces Markdown locales válidos; cero archivos Go o `go.mod`; referencia todavía idéntica al archivo aportado. |

Ambos escenarios terminan en −8946: 115/125 registros de pueblos respectivamente, cero estados activos, cero guerras, un presagio seguido. Los hashes no sustituyen fixtures de conflictos tardíos. Los resultados de tiempos (aprox. 33,5 s por repetición generada y 10,7 s por repetición Tierra en esta máquina) incluyen generación y hashing; no son rendimiento del núcleo aislado.

El workflow incluido verifica integridad y repetibilidad con Node 22 en Linux. Sus resultados remotos deberán comprobarse en la PR; agregar el archivo del workflow no acredita que GitHub Actions se haya ejecutado o esté habilitado. Los hashes de evidencia local no se imponen como golden entre versiones de Node.

## Comprobaciones no realizadas

- Compilación o ejecución Go/Ebitengine: no existe implementación en esta fase.
- Equivalencia JS/Go, determinismo multiplataforma y checkpoints reanudables.
- Estados/guerras tardíos, siete presagios restantes, todos los cataclismos y ventanas climáticas largas.
- Pruebas visuales del HTML en navegador o de la futura app nativa.
- Benchmarks aislados, memoria a milenios y presupuesto de rendimiento.
- Auditoría independiente Claude, integración, tag y aprobación para Fase 1.

Las decisiones propuestas no se presentan como resultados de pruebas pendientes.
