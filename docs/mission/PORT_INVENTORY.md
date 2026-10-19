# Inventario del port del motor v0.6

Correspondencia de las funciones declaradas del bloque core (líneas 315–2299) del HTML inmutable. Esta tabla es un inventario de implementación por lectura de fuentes, no evidencia de tests finales. Las ramas Tierra, focos/regiones, importación y clima se incorporan en esta integración; su comprobación queda al usuario.

| Línea HTML | Función original | Archivo Go | Implementación / adaptación |
|---:|---|---|---|
| 383 | mulberry32 | internal/rng/rng.go | Mulberry32 / New |
| 384 | hashStr | internal/rng/rng.go | HashStr |
| 386 | gauss | internal/sim/peoples.go | gauss |
| 387 | pick | internal/sim/language.go | pick |
| 389 | fy | internal/sim/narrative.go | formatYear (texto nativo) |
| 390 | hsl | internal/sim/peoples.go | hsl |
| 391 | makeNoise | internal/sim/noise.go | makeNoise |
| 406 | fbm | internal/sim/noise.go | fbm |
| 407 | boxBlur | internal/sim/climate.go | boxBlur |
| 414 | decodeEarth | internal/mapsource/load.go | decodeEarth |
| 421 | kgGroup | internal/sim/world_source.go | kgGroup |
| 422 | simGroup | internal/sim/world_source.go | simClimateGroup |
| 425 | genClimate | internal/sim/climate.go; internal/sim/climate_configured.go | generateClimate / generateConfiguredClimate |
| 468 | fitClimate | internal/sim/world_source.go | fitClimate |
| 486 | gradeClimate | internal/sim/world_source.go | gradeClimate |
| 504 | biomeOf | internal/sim/ecology.go | biomeOf |
| 508 | cellAt | internal/sim/earth.go | cellAt |
| 522 | genWorld | internal/sim/world.go | GenerateWorldWithInputs y preparación geográfica |
| 693 | applyRule | internal/sim/language.go | applySoundRule |
| 705 | applyRules | internal/sim/language.go | applySoundRules |
| 706 | tidy | internal/sim/language.go | tidy |
| 707 | syl | internal/sim/language.go | syllable |
| 718 | rawWord | internal/sim/language.go | rawWord |
| 722 | join | internal/sim/language.go | joinWord |
| 723 | word | internal/sim/language.go | word |
| 724 | makeLang | internal/sim/language.go | makeLanguage |
| 731 | langNames | internal/sim/language.go | Language.names |
| 737 | childLang | internal/sim/language.go | childLanguage |
| 748 | hybridLang | internal/sim/language.go | hybridLanguage |
| 755 | personName | internal/sim/language.go | personName |
| 758 | placeWord | internal/sim/language.go | placeWord |
| 759 | cityWord | internal/sim/language.go | cityWord |
| 760 | roman | internal/sim/language.go | roman |
| 801 | eraOf | internal/sim/tech.go | eraOf |
| 813 | newEth | internal/sim/peoples.go | newPeople |
| 824 | ethDist | internal/sim/peoples.go | ethDistance |
| 830 | chron | internal/sim/history.go | chron |
| 831 | spot | internal/sim/entities.go | spot |
| 832 | angDist | internal/sim/history.go | angDist |
| 833 | seedTech | internal/sim/hearths.go | seedTech |
| 835 | nearestPeopled | internal/sim/hearths.go | nearestPeopled |
| 841 | ring | internal/sim/history.go | ring |
| 842 | dirWord | internal/sim/migration_pressure.go | dirWord |
| 843 | dxWrap | internal/sim/migration_pressure.go | dxWrap |
| 864 | newHistory | internal/sim/history.go | newHistory |
| 924 | climateStep | internal/sim/carrying.go | climateStep |
| 943 | epochTemp | internal/sim/carrying.go | epochTemp |
| 944 | regionName | internal/sim/carrying.go | regionName |
| 948 | weather | internal/sim/weather.go | weather |
| 958 | computeK | internal/sim/carrying.go | computeK |
| 982 | growth | internal/sim/population.go | growth |
| 1006 | mixIn | internal/sim/population.go | mixIn |
| 1007 | migrate | internal/sim/population.go | migrate |
| 1025 | virginSoil | internal/sim/disease.go | virginSoil |
| 1034 | seaHop | internal/sim/seafaring.go | seaHop |
| 1062 | firstTech | internal/sim/technology_yearly.go | firstTech |
| 1070 | techStep | internal/sim/technology_yearly.go | techStep |
| 1114 | hearthCheck | internal/sim/hearths.go | hearthCheck |
| 1147 | cropFor | internal/sim/hearths.go | cropFor |
| 1156 | disease | internal/sim/disease.go | disease |
| 1191 | figFor | internal/sim/rulers.go | figFor |
| 1196 | deed | internal/sim/rulers.go | deed |
| 1197 | figScore | internal/sim/rulers.go | figScore |
| 1201 | tierOf | internal/sim/polities.go | tierOf |
| 1208 | fullName | internal/sim/polities.go | fullName |
| 1209 | styleOf | internal/sim/rulers.go | selección inline al iniciar titleOf |
| 1210 | titleOf | internal/sim/rulers.go | titleOf |
| 1214 | rulerName | internal/sim/rulers.go | rulerName |
| 1215 | newRuler | internal/sim/rulers.go | newRuler |
| 1226 | langAt | internal/sim/history.go | langAt |
| 1227 | newPolity | internal/sim/polities.go | newPolity |
| 1250 | succession | internal/sim/crises.go | succession |
| 1269 | etOf | internal/sim/polities.go | etOf |
| 1271 | topCauses | internal/sim/crises.go | topCauses |
| 1272 | polCells | internal/sim/settlements_cultures.go | polCells |
| 1273 | civilWar | internal/sim/crises.go | civilWar |
| 1302 | collapse | internal/sim/polities.go | collapse |
| 1307 | milAt | internal/sim/migration_pressure.go | milAt |
| 1308 | cerealEff | internal/sim/polities.go | cerealEff |
| 1309 | strength | internal/sim/polities.go | strength |
| 1310 | power | internal/sim/polities.go | power |
| 1312 | defense | internal/sim/polities.go | defense |
| 1317 | displace | internal/sim/polities.go | displace |
| 1318 | attack | internal/sim/wars.go | attack |
| 1348 | raid | internal/sim/wars.go | raid |
| 1356 | decisive | internal/sim/wars.go | decisive |
| 1367 | distBFS | internal/sim/wars.go | distBFS |
| 1383 | declareWar | internal/sim/wars.go | declareWar |
| 1397 | endWar | internal/sim/wars.go | endWar |
| 1413 | affinity | internal/sim/diplomacy.go | affinity |
| 1423 | diplomacy | internal/sim/diplomacy.go | diplomacy |
| 1446 | foundReligion | internal/sim/religions.go | foundReligion |
| 1462 | holyName | internal/sim/religions.go | holyName |
| 1463 | relPass | internal/sim/religions.go | relPass |
| 1503 | pushPressure | internal/sim/migration_pressure.go | pushPressure |
| 1517 | startMigration | internal/sim/migration_pressure.go | startMigration |
| 1533 | fmtK | internal/sim/migration_pressure.go | fmtK |
| 1534 | migStep | internal/sim/migration_movement.go | migStep |
| 1563 | disperse | internal/sim/migration_movement.go | disperse |
| 1567 | settle | internal/sim/migration_movement.go | settle |
| 1589 | hordeMigration | internal/sim/migration_movement.go | hordeMigration |
| 1599 | culture | internal/sim/crises.go | culture |
| 1620 | politics | internal/sim/politics.go | politics |
| 1621 | politicsG | internal/sim/politics.go; internal/sim/political_census.go; internal/sim/political_borders.go | politics y fases secuenciales |
| 1815 | ethPass | internal/sim/peoples.go | ethPass |
| 1841 | mixPass | internal/sim/settlements_cultures.go | mixPass |
| 1863 | cityPass | internal/sim/settlements_cultures.go | cityPass |
| 1874 | polShape | internal/sim/regions.go | polShape |
| 1878 | shapePass | internal/sim/regions.go | shapePass |
| 1881 | regionPass | internal/sim/regions.go | regionPass |
| 1902 | recordStats | internal/sim/history.go | recordStats |
| 1910 | step | internal/sim/simulation.go | AdvanceYear |
| 1912 | stepG | internal/sim/calendar.go | advanceYear |
| 1927 | prepEco | internal/sim/ecology.go | prepareEcology |
| 1945 | techFit | internal/sim/crises.go | techFit |
| 1946 | ecoD | internal/sim/polities.go | ecoD |
| 1948 | isWaste | internal/sim/polities.go | isWaste |
| 1951 | statecraft | internal/sim/crises.go | statecraft |
| 1981 | localPop | internal/sim/contact_ecology.go | localPop |
| 1983 | exitPass | internal/sim/contact_ecology.go | exitPass |
| 1993 | poolPass | internal/sim/contact_ecology.go | poolPass |
| 2009 | volcano | internal/sim/cataclysms.go | volcano |
| 2022 | caravanPass | internal/sim/contact_ecology.go | caravanPass |
| 2052 | cropExchange | internal/sim/seafaring.go | cropExchange |
| 2094 | placeName | internal/sim/history.go | placeName |
| 2099 | cellsWithin | internal/sim/cataclysms.go | cellsWithin |
| 2103 | omenCheck | internal/sim/omens.go | omenCheck |
| 2114 | castOmen | internal/sim/omens.go | castOmen |
| 2177 | omenFollow | internal/sim/omens.go | omenFollow |
| 2199 | foundReligionAt | internal/sim/omens.go | foundReligionAt |
| 2214 | cataSite | internal/sim/cataclysms.go | cataSite |
| 2222 | leadEra | internal/sim/cataclysms.go | leadEra |
| 2224 | randomCataclysm | internal/sim/cataclysms.go | randomCataclysm |
| 2231 | setKMod | internal/sim/cataclysms.go | setKMod |
| 2232 | cataclysm | internal/sim/cataclysms.go | cataclysm |
| 2270 | omenPass | internal/sim/omens.go | omenPass |
| 2277 | snapshot | internal/sim/map_history.go | snapshot |
| 2291 | polAt | internal/sim/map_history.go | polAt |
| 2298 | layerAt | internal/sim/map_history.go | layerAt |

Además de las declaraciones, clamp y otros helpers flecha tienen sus equivalentes en noise.go, geography.go y los sistemas correspondientes. Los heaps y recorridos anidados de genWorld viven en drainage.go/sea_links.go; las colecciones ordenadas están en ordered.go. Los datos ordenados de lenguas, reglas, técnicas, épocas e intervenciones se conservan en los catálogos JSON extraídos.

Los yield del navegador se sustituyen por un año Go atómico. politicsG conserva la visita por índice a alive que crece durante una guerra civil. Las etiquetas/narración se adaptan al texto de Go; no se promete igualdad exacta de formateo V8/ICU. No se normalizan silenciosamente los NaN heredados.

El tercer script, DOM, botones, autoTune/quickGrade, pintura canvas, animación y la pausa/mensaje de interfaz de 1800 no son nuevos sistemas causales del calendario. Su interfaz se sustituye por Godot; los controles CDEF y el ajuste/evaluación climática sí están portados. readImage se adapta a un remuestreador nativo versionado, explicado en WORLD_INPUTS.md. No se porta código de render dentro del núcleo.

No se incluye persistencia rápida ni expansión de edificios, tratados o dinastías como entidades nuevas. Las relaciones y consultas exponen lo que v0.6 realmente modela.
