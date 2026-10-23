# Captura original del propietario

ZIP conservado byte por byte, SHA256:
`0683f81ed189463d133c25f943e87fd3d7327c57b17d6be2975086f597648190`.
Contiene cuatro casos Windows reales de #27, commit `6f234dbe`.
No contiene eventos de presentación ETW, CPU ni una explicación confirmada de
los huecos. Los cero de memoria antiguos no equivalen a RAM real nula.

Reproducir `diagnosis.json` desde la raíz:

```sh
python experiments/atlas2d/tools/diagnose_original.py experiments/atlas2d/evidence/iris-xe-original/mediciones-20261022-202503.zip --out diagnosis.json
```

El script verifica el SHA antes de leer, no extrae ni ejecuta contenidos del ZIP.
El diagnóstico completo y las hipótesis están en
`../../docs/WINDOWS_MEASUREMENT_DIAGNOSIS.md`.
