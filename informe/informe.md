# Informe técnico — Procesamiento distribuido de imágenes (Erlang + Scheme)

*(Plantilla: complete cada sección. Los resultados de la sección 7 son
un ejemplo real obtenido con `scripts/benchmark.sh` sobre una imagen
pequeña de prueba; reemplácelos por sus propias mediciones con la
imagen de benchmark de tamaño real e indique el hardware usado.)*

## 1. Arquitectura del sistema

Describa el flujo completo: Erlang lee la imagen → la divide en
regiones → crea un proceso por región → cada proceso lanza una
instancia de Racket vía puerto → Racket procesa y devuelve su región →
Erlang reconstruye y escribe la imagen de salida. Incluya un diagrama.

## 2. División de la imagen

Explique el método elegido (bandas horizontales), por qué se eligió, y
qué alternativas se consideraron (p. ej. cuadrícula 2D) y sus
trade-offs (una cuadrícula reduce el halo pero complica el protocolo,
necesitando halo también a los costados).

## 3. Modelo de concurrencia

Explique el uso de `spawn_monitor/1`, el paso de mensajes para
recolectar resultados, y por qué esto satisface el requisito de no
paralelizar mediante una simple secuencia de llamadas.

## 4. Comunicación entre Erlang y Scheme

Documente el protocolo diseñado:
- Framing de transporte: `{packet,4}` (4 bytes de longitud + cuerpo).
- Formato del mensaje de petición y de respuesta (líneas
  `FILTER`/`PARAMS`/`DIMS`/`HALO`/`PIXELS` y `OK`/`ERROR`).
- Justifique las decisiones: ¿por qué texto y no binario?, ¿por qué una
  instancia de Scheme por región y no un servidor persistente?

## 5. Implementación del filtro

Explique la convolución genérica implementada en `filtro.rkt`, el
kernel gaussiano 3×3 usado, y la(s) transformación(es) adicional(es)
implementadas (`grayscale`, `invert`, `threshold`, `brightness`,
`sharpen`, `transponer`).

## 5.1. Algoritmos reutilizados de `clase.scm` (y su encaje real)

Tabla para citar en la defensa — qué algoritmo de la clase se reutilizó,
dónde, y si aplicó tal cual o hubo que adaptar la representación de
datos:

| Algoritmo en `clase.scm` | Dónde se reutiliza | ¿Verbatim o adaptado? |
|---|---|---|
| `pp` (producto punto) | `convolucion` en `filtro.rkt`: cada canal de salida es `pp(kernel, vecinos)` | Verbatim |
| `transpuesta` | Filtro `transponer` (intercambia filas/columnas) | Verbatim (solo se convierte vector↔lista antes/después) |
| `pack`/`pack-aux` (RLE) | `scripts/analizar_compresion.rkt` (mide compresibilidad) | Verbatim |
| `mergecount` | `scripts/comparar_histogramas.rkt` (similitud entre histogramas) | Verbatim |
| `quicksort` (referenciado, no definido en el archivo) | `scripts/comparar_histogramas.rkt` | Implementado con la misma firma `(quicksort L menor?)` |
| Recursión con `append` estilo `preorden` | `matriz-a-pixeles-aux`/`fila-a-pixeles-aux` en `filtro.rkt` | Mismo patrón, adaptado a matrices en vez de árboles |

**Lo que NO se forzó a encajar y por qué:** los recorridos de árbol
(`altura`, `nivel`, `anchura`) no se aplicaron literalmente porque una
imagen es una grilla, no un árbol — forzar una estructura de árbol
(p. ej. un *quadtree*) sobre la imagen habría sido una sobre-ingeniería
sin un motivo real para este proyecto. La excepción honesta se
documenta en vez de simular un encaje que no existe.

Los resultados concretos obtenidos con `pack`/`mergecount` sobre las
imágenes de prueba están en el `README.md`, sección 7.1.

## 6. Manejo de bordes y halo

Explique la estrategia de *extensión de borde* (clamp) y cómo el halo
resuelve la dependencia entre píxeles de regiones vecinas. Mencione la
verificación de corrección: el resultado con `p=1` y con `p=N>1` es
idéntico (adjunte el `diff`).

## 7. Resultados experimentales

Ejemplo real (imagen `checkerboard_100x100.ppm`, filtro `gaussian`,
máquina de un solo hardware de referencia — **reemplazar por sus
propias mediciones con `benchmark_400x300.ppm` o una imagen mayor**):

| p | Tp (ms) | Sp = T1/Tp | Ep = Sp/p |
|---|---------|------------|-----------|
| 1 | 455     | 1.00       | 1.00      |
| 2 | 938     | 0.49       | 0.24      |
| 4 | 1415    | 0.32       | 0.08      |

*(Inserte también sus gráficos de Tp vs. p, Speedup vs. p y Eficiencia
vs. p.)*

## 8. Análisis de speedup y eficiencia

En el ejemplo anterior el *speedup* es **menor que 1** (más procesos =
más tiempo). Discuta por qué, considerando:
- Costo de crear un proceso de sistema operativo Racket por cada
  región y por cada llamada (arranque del runtime de Racket).
- Comunicación Erlang↔Scheme (serialización de texto, escritura y
  lectura del puerto).
- Lectura/escritura de archivos.
- División y reconstrucción de la imagen (copiado de listas/tuplas).
- Tamaño de la imagen: para imágenes pequeñas el *overhead* domina
  sobre el trabajo útil; se espera que el speedup mejore con imágenes
  más grandes, donde el tiempo de cómputo por región supera el costo
  fijo de lanzar cada instancia de Scheme. Repita el experimento con
  una imagen bastante más grande y compare.

## 8.1. ¿Se tuvieron en cuenta las fortalezas y debilidades de cada lenguaje?

Tabla de referencia usada para el diseño:

| | Fortalezas | Debilidades |
|---|---|---|
| **Scheme** | procesamiento simbólico, recursión sobre estructuras, IA/sistemas de reglas, diseño de lenguajes | **no orientado a concurrencia/distribución**, **no ideal para cómputo numérico de alto rendimiento**, uso industrial limitado |
| **Erlang** | concurrencia masiva, sistemas distribuidos, **tolerancia a fallos**, alta disponibilidad | **no optimizado para cómputo numérico intensivo**, no ideal para una sola tarea CPU-bound, menos apto para programas secuenciales tradicionales |

**Reparto de responsabilidades:** siguiendo esta tabla, Erlang **nunca**
hace aritmética de píxeles — solo coordina, divide, crea procesos,
pasa mensajes y reintenta ante fallos (su fortaleza). Scheme **nunca**
maneja concurrencia ni E/S de red — cada instancia procesa una sola
región y termina (evita depender de su debilidad en concurrencia). El
manejo de errores (`exit_status`, timeout, reintento automático) explota
directamente la fortaleza de tolerancia a fallos de Erlang.

**Un punto que NO se había evaluado con datos** (surgió al revisar el
código): el filtro de convolución *es*, por naturaleza, cómputo
numérico — la debilidad que la tabla marca justamente para Scheme.
Para saber si esto realmente pesaba, se instrumentó `filtro.rkt` y se
midió, sobre la imagen completa de benchmark (400×300 = 120 000
píxeles, gaussiano 3×3), cuánto tiempo se va en cada etapa:

| Etapa | Tiempo | % del total |
|---|---|---|
| Parseo de texto → enteros (`a-enteros` sobre ~360 000 tokens) | **3119 ms** | **86 %** |
| Construir la matriz de píxeles | 43 ms | 1 % |
| **Aplicar el filtro (convolución)** | **205 ms** | **6 %** |
| Armar la respuesta (matriz → texto) | 235 ms | 7 % |

También se comparó la convolución **recursiva** (con `map`/`apply`,
reusando el patrón `pp` de `clase.scm`) contra una versión **imperativa**
equivalente con `for*` y vectores mutables: 205 ms vs 202 ms — una
diferencia despreciable (~1%).

**Conclusión honesta:** la debilidad numérica de Scheme casi no se
siente en la convolución en sí (ambos estilos, recursivo e imperativo,
la resuelven en ~200 ms para 120 000 píxeles). El verdadero costo está
en el **protocolo de texto plano**: convertir cientos de miles de
números de texto a valores numéricos de Racket (y de vuelta a texto)
dominado el tiempo total. Esto fue una decisión de diseño consciente
—se eligió texto plano en vez de un formato binario para que el
protocolo fuera fácil de inspeccionar y depurar durante el desarrollo y
la defensa— pero tiene un costo real y medible que conviene declarar
explícitamente en vez de asumir que "Scheme es lento para esto" sin
comprobarlo. Una extensión natural (mencionada como trabajo futuro) es
pasar a un protocolo binario (enteros de 1 byte por canal, sin texto
intermedio), lo que eliminaría la mayor parte de ese 86%.

Sobre las fortalezas de **distribución** de Erlang: este proyecto corre
en un solo nodo (no se usa Erlang distribuido con múltiples nodos
físicos/`net_kernel`), porque el enunciado no lo requiere. Es una
limitación de alcance, no de la arquitectura: el mismo diseño de
servidor+clientes con paso de mensajes se podría extender a múltiples
nodos sin cambios profundos, ya que Erlang fue pensado exactamente
para eso.


## 9. Manejo de errores

Describa cómo se simuló un fallo (por ejemplo, forzando un filtro
inválido o interrumpiendo un proceso), cómo el sistema lo detectó
(`exit_status` distinto de 0 o mensaje `ERROR` del protocolo), la
política de reintento automático implementada, y qué ocurre si el
reintento también falla (el programa aborta sin escribir una imagen
incorrecta).

## 10. Limitaciones del sistema

- División solo en bandas horizontales.
- Sin *pipeline* de filtros encadenados en una sola invocación.
- Sin *pool* de procesos Scheme persistente (instancia nueva por
  región y por llamada).
- (Agregue las que identifique durante la defensa/pruebas.)

## 11. Conclusiones

Resuma lo aprendido sobre integración de lenguajes, concurrencia con
paso de mensajes, y análisis de rendimiento paralelo.
