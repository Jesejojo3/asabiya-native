# Revisión independiente propuesta — Bloque 2

Rama `phase-1/drainage-geography-ecology`, base `7fb42f9eab9304b7bcd6811a379780ea6ca4723b`, [Issue #3](https://github.com/Jesejojo3/asabiya-native/issues/3). No hacer merge. Ver BLOCK2.md y BLOCK2_VALIDATION.md para alcance, decisiones y pruebas. Intercambio con Claude manual por el usuario.

1. H1: cotejar drainHeap contra hpush/hpop. No introducir ID/FIFO en empates; verificar orden n8, costas, escritura float32 antes de push y acumulación inversa. Revisar el fixture y su extracción desde el HTML inmutable, además de ejecutar los tests.
2. H2: trigonometría, latitud redondeada de cosLat y derivación cxA/cyA; API por valores y copias. Revisar umbrales float32→float64, biomas y redondeo Math.round del coste.
3. Enlaces: cuatro vecinos iniciales, n8 posterior, visited por origen, límite seis, dc>=2, otro landmass primero y sort estable con máximo diez. No exigir reciprocidad inexistente en el legado.
4. prepEco y su posición antes de publicar World: puramente dependiente del mapa y sin RNG. No asumir AG gauss inicializado ni que weather/newHistory existen.
5. H3: retención opcional de cuatro capas finas en Surface, 19,53 MiB de datos, sin copias extra de generación. La ventana retiene datos y textura; headless puede descartarlos. No afirmar render completo de ríos o biomas.
6. Verificar que HTML, tag y fixtures históricos/v1 siguen intactos. BaseDigest y BaseSummary son proyección v1, no un golden sustituido. El fingerprint nuevo cubre todas las capas nuevas y los órdenes relevantes.
7. Windows Go 1.27.2: vet/tests, build y check-native-repro; Node fijado: verify-reference y check-geography-oracle. Consultar CI del legado Windows para sus hashes originales. No exigir paridad V8 o pruebas de otras plataformas.

Entregar hallazgos reproducibles, archivos/líneas, impacto y pruebas realizadas; distinguir errores del bloque de pendientes fuera de alcance. Población/estados y la próxima PR siguen sin autorización de implementación en esta entrega.
