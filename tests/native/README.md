# Referencia nativa

`world-v1.windows-go1.27.2.json` es el resumen de la primera generación nativa
de Asabiya (400×200, detalle 4, fracción objetivo 0,33) en Windows amd64,
Go 1.27.2 y GOAMD64=v1. No procede del oráculo V8 y no reemplaza sus fixtures.

`tools/check-native-repro.ps1` exige sus valores y dos procesos independientes.
Investigar toda diferencia; no regenerar para esconder errores. Este golden
no demuestra portabilidad entre todas las CPUs ni es una partida guardada.
