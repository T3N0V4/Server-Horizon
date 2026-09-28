# Auditoría y optimización de HORIZONS

Fecha: 25 de septiembre de 2026. Equipo compartido por cliente y servidor: Ryzen 7 5700G, 8 núcleos/16 hilos, 32 GB RAM, SSD/NVMe. Minecraft 1.20.1, Fabric Loader 0.16.10, Java instalado 17.0.12 de 64 bits.

**Estado:** ajustes conservadores aplicados. No se inició Minecraft durante la auditoría ni se modificaron los mundos. No existe una medición antes/después que demuestre mejores TPS, MSPT o FPS. Los cambios reducen trabajo potencial y competencia por CPU; su efecto real debe medirse.

## A. Qué encontré

Se inspeccionaron el arranque, propiedades, 136 JAR inicialmente activos, sus metadatos y dependencias anidadas, 218 archivos de configuración, los siete logs comprimidos recientes, latest.log, logs de REI, paquetes globales, configuración persistida de Chunky y estructura/encabezados de regiones del mundo. `defaultconfigs` y `datapacks` de la raíz están vacíos; también las carpetas `world/serverconfig` y `world/datapacks`. Forge Config API Port utiliza configuración global. Los seis resource packs globales y el datapack HORIZONS se conservaron.

### Hallazgos y clasificación

| Hallazgo | Clasificación | Decisión |
|---|---|---|
| Arranque duplicado para Windows Terminal; `&&` puede omitir mensajes finales cuando Java falla | Seguro/recomendado | Una sola ejecución en primer plano, captura del código y pausa |
| DH usa 8 hilos; C2ME predeterminado calculado alrededor de 6, además del cliente | Seguro/recomendado como punto de partida | DH 2 y C2ME 3; medir también velocidad de carga |
| DH comprime nuevos LOD con LZMA2, costoso para CPU | Seguro/recomendado en este equipo | LZ4; mismo contenido, más almacenamiento y posible transferencia |
| DH permite solicitudes hasta 4096 chunks, muy por encima del objetivo de 256 | Seguro/recomendado | Límites de generación y sincronización 256; no recorta mundo ni distancia vanilla |
| PuzzlesLib 8.0.15 y 8.1.20 juntos | Seguro/recomendado | Deshabilitar solo 8.0.15, que Fabric ya descartaba |
| Cuatro JAR exclusivamente cliente sin dependientes obligatorios | Seguro/recomendado | Trasladarlos a disabled-mods; mantenerlos en el cliente |
| Crab incluye mixin incompatible con 1.20.1 | Opcional: reparación que requiere prueba | No eliminar contenido ni instalar una versión sin verificar |
| Errores de datapack/recetas y migración repetida de Ice and Fire | Opcional: reparación separada | Preservar contenido e intención del pack |
| Chunk loaders ilimitados y activos hasta siete días offline | Opcional, modifica gameplay | Medir uso real antes de imponer límites |
| Cambiar DH globalmente a PRE_EXISTING_ONLY | Opcional, cambia cobertura visual | No aplicado: faltaría LOD en terreno no generado |
| Forzar serializer incompatible, iluminación/pregen asumida o reparaciones experimentales DH | Arriesgado/no recomendado | Mantener protecciones y valores actuales |
| Quitar contenido, estructuras, dimensiones, reducir spawns o regenerar mundo | Arriesgado/no recomendado para este objetivo | No aplicado |

### Versiones reales relevantes

| Mod | Versión interna |
|---|---|
| Distant Horizons activo | 2.3.4-b |
| Distant Horizons deshabilitado | 2.2.1-a |
| C2ME | 0.2.0+alpha.11.5 |
| Lithium | 0.11.2 |
| Noisium | 2.2.2+mc1.20-1.20.1 |
| FerriteCore | 6.0.1 |
| Chunky | 1.3.146 |
| Spark | 1.10.53 |
| MemoryLeakFix | 1.1.5 |
| LazyDFU | 0.1.3 |

El inventario completo está en `optimization-audit-2026-09-25/mods-inventory.csv`. Hay discrepancias entre nombres de JAR y versiones internas de varios mods; por sí solas no demuestran incompatibilidad. Noisium, Lithium y C2ME tienen optimizaciones complementarias y compatibilidad declarada; no se retiraron por supuesto solapamiento.

### Logs: problemas reales frente a ruido de arranque

- **Crab:** siete arranques registran `InvalidMixinException` en `crab.mixins.json:ServerPlayNetworkHandlerMixin`: superclase `class_8609` ausente del target `class_3244`. El archivo está marcado para 1.20.2 aunque su dependencia Minecraft es demasiado permisiva. También intenta aplicar un mixin cliente en servidor. Hay arranques que llegan a `Done`, pero ese mixin falla. Requiere una versión compatible comprobada en una copia; no se retiró el mob.
- El log `2026-09-25-7.log.gz` contiene **134 líneas ERROR de arranque**: 93 mensajes de data fixers ausentes, 28 de tags de integración, ocho recetas y cinco restantes. No son 134 crashes ni evidencia de errores repetidos cada tick.
- Tres recetas de Deeper and Darker requieren objetos de Create; cinco de Ice and Fire usan `farmersdelight:cooking`, sin esos mods instalados. No corresponde agregarlos solo para silenciar errores.
- `watching:check` no carga por comando inválido y Beans' Backpacks tiene un advancement con criterio `has_upgraded` inexistente.
- `global_packs/required_data/horizonsDataPack.zip!/data/simplyswords/loot_tables/grant_book_on_first_join.json` tiene **cero bytes** y causa EOFException. El original entrega un libro. Una tabla JSON vacía válida podría expresar una intención de impedirlo, pero esa intención y el fallback no están demostrados: no se cambió automáticamente.
- Ice and Fire conserva `version: 1`, anuncia migración a 2 dos veces por arranque y acumuló 27 backups de 3054 bytes. No se cambió solamente el número de versión sin comprobar el esquema.
- Refmaps ausentes y SemVer inválido son principalmente advertencias de empaquetado; no se confundieron con la incompatibilidad concreta de Crab.
- Durante pregeneración hubo 2333 avisos de atributos desconocidos, 108 de block entities y 19 de pools de estructuras. No se modificaron generación ni NBT para silenciarlos. Los logs también contienen 19 timeouts acumulados de cierre de pools DH; bajar concurrencia puede reducir presión, pero no constituye una reparación probada de esos timeouts.

Cinco arranques completos tardaron **34, 44, 50, 45 y 46 segundos** desde `Loading` hasta `Done`. El valor entre paréntesis de `Done` no incluye todo ese tiempo. Hubo tres avisos históricos de retraso: 2182, 4154 y 2107 ms. Los guardados finales vanilla terminaron en 0–1 s según timestamps con resolución de segundos; DH siguió cerrándose después. Esto no demuestra un cuello de botella persistente de guardado.

`latest.log` solo contiene dos segundos de inicio; otros dos logs están truncados. No bastan para concluir que hubo crashes. No había series TPS/MSPT, logs GC ni perfiles Spark guardados para una comparación controlada.

## B. Qué cambié

Se crearon y verificaron copias exactas antes de editar:

- `start.bat.bak`
- `config/c2me.toml.bak`
- `config/DistantHorizons.toml.bak`
- `server.properties.bak` como referencia; **server.properties no cambió**.

| Archivo / clave | Antes | Ahora |
|---|---|---|
| C2ME `globalExecutorParallelism` | `"default"`, aproximadamente 6 | `3` |
| DH `common.multiThreading.numberOfThreads` | 8 | 2 |
| DH `common.lodBuilding.dataCompression` | LZMA2 | LZ4 |
| DH `server.maxGenerationRequestDistance` | 4096 | 256 |
| DH `server.maxSyncOnLoadRequestDistance` | 4096 | 256 |

Se trasladaron intactos a `disabled-mods`:

- `PuzzlesLib-v8.0.15-1.20.1-Fabric.jar`
- `antique-atlas-2.11.0+1.20.jar`
- `entityculling-fabric-1.7.2-mc1.20.1.jar`
- `keybind_fix-1.0.0.jar`
- `waveycapes-fabric-1.4.8-mc1.20.1.jar`

Los cuatro últimos tienen exclusivamente inicializadores/mixins cliente, no incluyen `data/*` ni son dependencias obligatorias de otro mod activo. Se conserva Surveyor en el servidor para el mapa del cliente. PuzzlesLib 8.1.20 satisface las dependencias, incluida EasyShulkerBoxes >=8.1.13. Quedan **131 JAR activos y seis deshabilitados**. No se descargó ni actualizó ningún mod.

El nuevo `start.bat` usa su propia carpeta, una ruta explícita al Java 17 instalado, una única ejecución en primer plano, mensajes legibles, `nogui`, captura inmediata de `%ERRORLEVEL%`, pausa y devolución del código al proceso que lo invoca. `stop` llega directamente a Minecraft. Si se mueve o actualiza Java a otra carpeta, ajustar `JAVA_EXE`.

## C. Por qué lo cambié

### JVM y memoria

La configuración conserva **4 GB iniciales y 8 GB máximos de heap**. No es memoria total del proceso: quedan además memoria nativa, buffers, código y bibliotecas. Para el cliente, empezar con 8 GB de heap, evaluar 10 GB solo si lo necesita y reservar margen para Windows, memoria nativa, DH y caché de disco. No asignar 16–24 GB al servidor por defecto.

| Parámetro | Decisión y motivo |
|---|---|
| `-Xms4G` | Mantener: evita iniciar con heap diminuto sin comprometer desde el comienzo 8 GB en una PC compartida |
| `-Xmx8G` | Mantener: límite razonable inicial para este pack; revisar ocupación después de GC antes de aumentarlo |
| `-XX:+UseG1GC` | Mantener explícito: G1 es el recolector actual y adecuado para el objetivo; no se cambió a un GC experimental |
| `-XX:+ParallelRefProcEnabled` | Quitar de la línea: se verificó que ya es `true` por defecto en este Java/G1; el comportamiento continúa |
| `-XX:MaxGCPauseMillis=200` | Quitar de la línea: 200 ya es el valor por defecto verificado; es un objetivo flexible, no garantía de ticks menores a 50 ms |
| `-XX:+DisableExplicitGC` | Mantener la política previa: ignora peticiones `System.gc()` de mods; la JVM sigue recolectando normalmente. No se afirma que tales peticiones fueran un problema medido |
| `-Xlog:gc*,safepoint:file=logs/gc.log:time,uptime,level,tags:filecount=5,filesize=10M` | Agregar diagnóstico rotativo: permite correlacionar pausas con tirones. Son aproximadamente cinco archivos archivados más el actual; guardar copias externas para comparaciones entre sesiones |
| `nogui` | Mantener: consola directa sin GUI del servidor |

No se añadieron listas de Aikar, tamaños de generación/regiones forzados, `AlwaysPreTouch`, afinidad, prioridad alta ni `ActiveProcessorCount`. G1 conserva sus heurísticas; en este Java detectó 13 trabajadores paralelos y tres concurrentes como límites ergonómicos, que no significan 16 hilos consumiendo CPU continuamente. Cambiarlos sin datos podría alargar pausas.

Los presupuestos C2ME=3 y DH=2 reducen competencia con el hilo de tick y el cliente. No fijan el número total de hilos del proceso ni reservan núcleos físicos. Pueden hacer que LOD o chunks terminen más despacio; medir esa contrapartida junto a MSPT.

### Distant Horizons y los chunks existentes

El log confirma que Chunky terminó **393129 chunks, 100 %, a las 09:14:36**, en 1:07:08. El contador persistido ligeramente anterior y `cancelled=true` no justifican repetir la tarea. Hay 398 regiones Overworld, con 340655 entradas; los 306740 centros de chunk dentro del círculo de radio 5000 están presentes. Es una comprobación de presencia por encabezados, no una verificación profunda de cada NBT.

DH **ya lee los chunks existentes antes de generar**. El bytecode de esta versión muestra lectura NBT y omisión de la fase FEATURES cuando el chunk ya alcanzó ese estado. Los logs confirman integración de esa lectura con C2ME. No corresponde afirmar que DH regenere desde cero todo lo que hizo Chunky.

Hay trabajo diferente e inevitable: leer chunks reales, construir/comprimir datos LOD y enviarlos. Además, `world/data/DistantHorizons.sqlite.old` ocupa 201814016 bytes, pero no existe la base activa `DistantHorizons.sqlite` del Overworld. No se renombró ni eliminó esa base: se desconoce por qué quedó así y si es adecuada para restaurarla. La próxima sesión puede reconstruir una caché activa y tardar más inicialmente.

**LZ4** conserva la calidad del LOD. Cada registro DH guarda su modo de compresión, por lo que las filas LZMA2 anteriores siguen siendo legibles; el ajuste afecta datos nuevos o regrabados. Reduce coste de compresión a cambio de espacio y potencial tráfico adicional, sin convertir archivos del mundo durante esta auditoría.

**256 chunks equivalen a 4096 bloques**. Se comprobó en el JAR que ambos límites de servidor están expresados en chunks y aceptan secciones que intersectan ese radio. El antiguo 4096 era un techo permitido, no prueba de que cada cliente lo solicitara completo: con clientes a 256, reducir el techo puede no cambiar la carga habitual.

La pregeneración es un círculo de radio 5000 centrado en 0,0. Como aproximación circular, un radio LOD de 4096 solo cabe completamente mientras el jugador esté a unos **904 bloques del centro**. La geometría real de chunks/secciones puede diferir. Al alejarse o cambiar de dimensión habrá solicitudes fuera de la zona pregenerada.

Se conserva `FEATURES`: permite generar LOD del terreno remoto aún inexistente, pero puede omitir estructuras y no guarda ese terreno como chunks reales; parte del trabajo se repetirá al explorarlo. **PRE_EXISTING_ONLY** evita ese trabajo futuro de worldgen DH, pero dejará zonas sin LOD fuera de chunks existentes. No se puede garantizar a la vez un horizonte completo en cualquier lugar, cero nueva generación y una pregeneración finita.

Para una fase de mantenimiento dedicada a importar lo existente, se puede evaluar `PRE_EXISTING_ONLY` manteniendo `enableDistantGeneration=true`; no se aplicó globalmente por su consecuencia visual. Tampoco se activó `INTERNAL_SERVER`: escribe/genera chunks reales y exige otra evaluación. No repetir Chunky para intentar arreglar la caché LOD.

El servidor lee/construye y comparte LOD; el cliente descarga, almacena, prepara mallas y renderiza. El cliente multijugador no genera por sí solo el terreno remoto del servidor. La sección `[client]` de la configuración de esta carpeta **no configura la instalación separada del cliente**.

## D. Qué decidí no tocar

- Contenido, estructuras, biomas, dimensiones, dificultad, spawns, redstone, chunks pregenerados, bases SQLite y `level.dat`.
- `view-distance=10`, `simulation-distance=5`, alcance de entidades 100 %, compresión de red vanilla 256 y `sync-chunk-writes=true`. Reducir tráfico/coste de guardado a ciegas puede perjudicar carga, entidades o durabilidad.
- Lithium no tiene overrides manuales. Sus tres excepciones provienen de C2ME, FerriteCore y SmartBrainLib y preservan compatibilidad.
- C2ME mantiene E/S asíncrona, guardado ENHANCED, protección de acceso aleatorio, compresión vanilla y `ensureChunkCorrectness=false`, evitando el envío doble que esa opción activaría. El serializer reducido está desactivado automáticamente por incompatibilidad con Architectury 9.2.14; no se forzó.
- FerriteCore conserva deduplicaciones y `useSmallThreadingDetector=false`. Noisium no tiene configuración propia generada que haya que inventar.
- DH mantiene comprobación de chunks sin cambios, `assumePreExistingChunksAreFinished=false`, `pullLightingForPregeneratedChunks=false` y `recalculateChunkHeightmaps=false`. Tampoco se activaron arreglos experimentales de agujeros. Reutilizar iluminación puede ahorrar trabajo, pero no se comprobó seguro con esta combinación.
- DH mantiene sincronización y actualizaciones en tiempo real, radio de actualización 256, 20 solicitudes de generación/s, 50 de sincronización/s y límite de subida 500 KB/s. Ese límite puede retrasar el llenado inicial; probar un aumento sería opcional si la red lo permite y se demuestra que es el cuello de botella.
- Chunky no reanuda tareas al arrancar ni fuerza cargar chunks ya existentes. Spark mantiene su perfil de fondo.
- No se retiraron bibliotecas visuales con dependientes, ni REI, FancyMenu o mods con código común solo por su nombre. LazyDFU puede ser redundante en esta versión, pero retirarlo queda como limpieza opcional, sin mejora TPS prometida.
- No se limitaron chunk loaders, random ticks ni frecuencia de Surveyor. Su configuración puede mantener trabajo innecesario dependiendo del uso real; primero identificar hotspots. `positionTicks=1` de Surveyor podría evaluarse a 5–10 si red/perfil lo justifican, con menor frecuencia de actualización de posiciones.
- No se actualizó Java ni Fabric durante esta optimización. Una actualización de mantenimiento de Java 17 se puede evaluar separadamente, con arranque y modpack verificados.

## E. Configuración final recomendada

| Área | Valor inicial |
|---|---|
| Servidor heap | 4 GB iniciales / 8 GB máximos, G1 |
| Cliente heap | Empezar con 8 GB; 10 solo si hay presión demostrada |
| Distancia vanilla servidor | 10 chunks |
| Simulación servidor | 5 chunks, valor previo preservado |
| Render vanilla cliente | 10 chunks como punto de partida; comprobar en el cliente |
| Radio LOD cliente | 256 chunks; comprobar en el cliente |
| CPU DH cliente | Preset bajo como punto de partida; medir FPS y velocidad de mallas |
| DH servidor | 2 hilos, ratio 1.0, LZ4, generación/sync permitidos hasta 256 |
| C2ME | Paralelismo global 3 |
| Generación DH | FEATURES conservado; PRE_EXISTING_ONLY opcional con límites visuales |

`view-distance` controla chunks reales enviados; `simulation-distance` controla la simulación cercana, incluidos muchos ticks de entidades. Render del cliente controla su presentación de chunks reales disponibles. Los LOD son representación lejana y **no extienden mobs, redstone, granjas ni simulación**. No son distancias intercambiables. Subir simulación de 5 a 6–8 puede ser razonable si el gameplay lo necesita, pero aumenta carga y sería una decisión aparte.

## F. Cómo medir si realmente mejoró

Usar los comandos de **Spark 1.10.53**, verificados dentro del JAR. En consola se escriben sin `/`; en el chat con `/` y permisos adecuados:

```text
spark tps
spark healthreport --memory --network
spark gcmonitor
spark tickmonitor --threshold-tick 50
spark profiler start --timeout 300 --thread * --save-to-file
```

`gcmonitor` y `tickmonitor` se desactivan repitiendo su comando. `--save-to-file` conserva el perfil local; no sube automáticamente el resultado. Si hace falta detener antes: `spark profiler stop --save-to-file`. No usar `spark gc` para forzar una recolección dentro de una medición normal. El profiler manual gestiona el muestreador de fondo; no hace falta deshabilitarlo de forma permanente.

1. Iniciar con el cliente abierto, igual configuración gráfica, mismo número de jugadores y mismas dimensiones. Esperar a `Done`, entrar y calentar al menos cinco minutos. Mantener Chunky inactivo.
2. Medir cinco minutos en una base representativa con entidades/redstone. Ejecutar `tps` y `healthreport` al comienzo y final. Capturar perfil con todos los hilos para ver tick, C2ME y DH por separado.
3. Repetir cinco minutos de exploración sobre una ruta y velocidad reproducibles dentro de lo pregenerado. Medir también segundos hasta completar LOD y aparición de chunks. Tratar exploración fuera de pregen como un escenario distinto.
4. Para comparar ajustes anteriores y actuales, usar sesiones/copies de prueba con el mismo estado de mundo y cachés **tanto de servidor como de cliente**. No comparar el primer llenado de DH contra una caché caliente. No borrar la caché de producción para fabricar una comparación.
5. Las `.bak` permiten reconstruir los valores anteriores con el servidor apagado. Para una comparación del paralelismo y compresión, mantener el nuevo launcher y su logging en ambos casos, cambiar únicamente las claves bajo prueba y documentarlo. Para una comparación global, registrar todas las diferencias. No reactivar DH viejo.
6. Repetir cada escenario al menos dos o tres veces. Guardar perfiles y una copia de `logs/gc.log*` antes del siguiente arranque. Describir si la caché estaba fría o caliente y cuántos jugadores había.

Registrar: TPS, MSPT mediano y p95 si el visor los proporciona, máximos/picos, ticks >50 ms, CPU del proceso y total, heap tras GC, memoria total del proceso, pausas GC, velocidad de llenado LOD, carga de chunks y tráfico. Un TPS estable de 20 puede ocultar mayor coste de ticks; buscar margen en MSPT y menos picos sin ralentizar de forma molesta la exploración.

En el perfil separar `Server thread` (entidades/IA, block entities, chunk loaders y guardados) de trabajadores DH/C2ME. No llamar hotspot a un mod solo porque aparece instalado. En Windows el muestreo Java puede incluir espera; una muestra de stack no es por sí sola una medida exacta de CPU consumida.

### Validación y reversión

Se conservaron manifiestos de hashes antes de modificar configs/JAR y hashes de los cinco JAR trasladados. `server.properties` sigue idéntico a su copia. Los **1853 archivos** de `world` y `world_vacio` mantienen rutas, tamaños y timestamps; no se calculó hash completo de todos los datos del mundo. La validación TOML y la prueba aislada del launcher se documentan en `optimization-audit-2026-09-25`.

**Validaciones aprobadas:** el parser NightConfig del propio JAR DH leyó ambos TOML completos y confirmó exactamente un cambio en C2ME y cuatro en DH, con los tipos correctos y sin claves agregadas o eliminadas. Una copia idéntica del BAT se ejecutó desde otra carpeta contra un JAR de prueba aislado: verificó directorio, argumento `nogui`, flags JVM, salida normal 0, crash simulado 42 y JAR ausente con salida 1; mostró el mensaje de pausa. El stdin cerrado permitió terminar esas pruebas automáticamente. Resultados en `validation/config-validation.txt` y `batch-validation/results.json`.

La prueba aislada no sustituye una sesión real de Fabric/HORIZONS: el arranque completo, la compatibilidad dinámica y los resultados de rendimiento quedan por comprobar con el uso del servidor. No se declara solucionado el error de Crab ni los errores de datapacks.

Para revertir con el servidor apagado: restaurar `start.bat`, `config/c2me.toml` y `config/DistantHorizons.toml` desde sus `.bak`, y devolver a `mods` únicamente los cinco archivos listados en `moved-mods.csv`. DH 2.2.1-a debe permanecer deshabilitado. No hace falta restaurar el mundo para revertir estas ediciones de configuración; las futuras escrituras normales del juego son una cuestión distinta.

### Fuentes primarias y evidencia

La fuente principal fue el contenido local: TOML comentados, metadatos de los JAR, bytecode de DH/C2ME/Spark y logs. La versión exacta instalada prevalece sobre instrucciones web de versiones más nuevas.

- [Oracle: opciones de Java 17](https://docs.oracle.com/en/java/javase/17/docs/specs/man/java.html) y [ajuste de G1 en Java 17](https://docs.oracle.com/en/java/javase/17/gctuning/garbage-first-garbage-collector-tuning.html).
- [C2ME: explicación del autor sobre paralelismo](https://github.com/RelativityMC/C2ME-fabric/discussions/292).
- [DH: documentación de servidor, revisión consultada](https://gitlab.com/distant-horizons-team/distant-horizons/-/wikis/1-user-guide/1-frequently-asked-questions/5-server-owners/Server-Owners/diff?version_id=de25dd2bdc18813a5fc6eef8f62ebfef25f8de62).
- [Chunky: configuración oficial](https://github.com/pop4959/Chunky/wiki/Configuration).
- [Noisium: repositorio del autor](https://github.com/Steveplays28/noisium).
- [LazyDFU: descripción del autor](https://www.curseforge.com/minecraft/mc-mods/lazydfu?mobile-app=true&theme=false).
- [Spark: documentación de comandos](https://spark.lucko.me/docs/Command-Usage). Su documentación actual cambió algunos comandos de health; aquí se usa `healthreport` verificado en 1.10.53.
