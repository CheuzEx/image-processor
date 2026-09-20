# Procesamiento distribuido de imágenes — Erlang + Scheme (Racket)

Sistema que aplica filtros de convolución (mínimo: difuminado gaussiano)
sobre imágenes PPM, dividiendo el trabajo en regiones que se procesan de
forma concurrente. **Erlang** coordina: lee la imagen, la divide en
regiones, crea los procesos, reconstruye el resultado. **Scheme
(Racket)** procesa cada región de forma aislada: cada proceso Erlang
lanza su propia instancia independiente de Racket.

## 1. Requisitos

- Erlang/OTP (probado con OTP 25/26).
- Racket (probado con 8.10).
- En Ubuntu/Debian: `sudo apt-get install erlang racket`

Verificar:
```bash
erl -version
racket --version
```

## 2. Estructura del proyecto

```
proyecto/
├── image_processor            # ejecutable: ./image_processor entrada.ppm salida.ppm N
├── erlang/
│   ├── image_processor.erl   # coordinador: lectura, división, concurrencia, reconstrucción
│   └── ppm.erl                # lectura/escritura de imágenes PPM (P3)
├── scheme/
│   └── filtro.rkt             # procesamiento de UNA región (gaussiano + extensiones)
├── scripts/
│   ├── generar_imagenes.rkt      # genera imágenes de prueba PPM
│   ├── benchmark.sh              # mide Tp, Speedup y Eficiencia para p=1,2,4,8
│   ├── analizar_compresion.rkt   # reutiliza pack/pack-aux de clase.scm (RLE)
│   └── comparar_histogramas.rkt  # reutiliza quicksort+pack+mergecount de clase.scm
├── test_images/               # imágenes de prueba ya generadas
├── informe/
│   └── informe.md             # plantilla del informe técnico
└── README.md
```

## 3. Compilar

El ejecutable `./image_processor` compila solo la primera vez (o si
detecta que los `.erl` cambiaron). Para compilar a mano de todos modos:

```bash
erlc -o erlang erlang/ppm.erl erlang/image_processor.erl
```

Scheme no requiere compilación: `filtro.rkt` se ejecuta directamente con
`racket`.

## 4. Ejecutar

**Interfaz literal exigida por el enunciado** (sección 15) — ejecutable
`./image_processor`, desde la raíz del proyecto:

```bash
./image_processor entrada.ppm salida.ppm 1
./image_processor entrada.ppm salida.ppm 2
./image_processor entrada.ppm salida.ppm 4
./image_processor entrada.ppm salida.ppm 8
```

Forma completa:

```bash
./image_processor entrada.ppm salida.ppm N [filtro] [ksize] [borde]
```

| Argumento | Por defecto | Descripción |
|---|---|---|
| `filtro` | `gaussian` | ver tabla de filtros abajo |
| `ksize` | `3` | tamaño del kernel (solo aplica a `gaussian`); entero **impar ≥ 3** |
| `borde` | `extender` | estrategia de borde: `extender` o `ceros` |

Ejemplos:

```bash
./image_processor test_images/benchmark_400x300.ppm salida.ppm 4
./image_processor test_images/benchmark_400x300.ppm salida.ppm 4 gaussian 5
./image_processor test_images/benchmark_400x300.ppm salida.ppm 4 gaussian 3 ceros
./image_processor test_images/colorbars_120x60.ppm salida.ppm 1 transponer
```

**Forma alternativa** (llamar directamente a `erl`, útil para depurar):

```bash
erlc -o erlang erlang/ppm.erl erlang/image_processor.erl
erl -noshell -pa erlang -eval \
  'image_processor:main(["ENTRADA.ppm","SALIDA.ppm","N","FILTRO","KSIZE","BORDE"]), init:stop().'
```

Filtros disponibles:

| Filtro       | Necesita halo | Descripción                          |
|--------------|:---:|----------------------------------------------|
| `gaussian`   | sí  | Difuminado gaussiano, tamaño configurable (obligatorio) |
| `sharpen`    | sí  | Realce de bordes (extensión, kernel 3×3 fijo) |
| `grayscale`  | no  | Escala de grises (extensión, punto a punto)   |
| `invert`     | no  | Inversión de colores                          |
| `threshold`  | no  | Binarización (umbral 128)                     |
| `brightness` | no  | Ajuste de brillo (+30)                        |
| `transponer` | no  | Intercambia filas/columnas (solo `N=1`, ver abajo) |

### Kernel gaussiano de tamaño configurable — listo para la defensa

El profesor puede pedir "cambiar el tamaño del kernel" en vivo (ejemplo
explícito del enunciado, sección 19). **Scheme genera el kernel el
mismo**, a partir del **triángulo de Pascal**, para cualquier tamaño
impar (`fila-pascal`/`kernel-gaussiano` en `filtro.rkt`). Erlang solo
manda el tamaño (`PARAMS <ksize>`), no los coeficientes. Para `ksize=3`
esto da exactamente el kernel clásico `[[1,2,1],[2,4,2],[1,2,1]]/16`
(verificado: mismos valores que con el kernel hardcodeado).

### Estrategia de borde configurable — también lista para la defensa

El otro ejemplo del enunciado (sección 19). Dos estrategias, elegibles
sin tocar código: `extender` (por defecto, replica el píxel más
cercano) y `ceros` (los píxeles fuera de la imagen valen `(0,0,0)`).
Se verificó que ambas dan resultados **distintos** entre sí, y que para
cada una el resultado con `N=1` es **idéntico** al de `N=4`.

## 5. Generar imágenes de prueba

Ya vienen algunas en `test_images/`. Para regenerarlas o crear más:

```bash
racket scripts/generar_imagenes.rkt test_images
```

Incluye: un degradado, un tablero de ajedrez (bordes duros, ideal para
ver el efecto del blur), barras de color y ruido pseudoaleatorio, más
una imagen de 400×300 pensada para las mediciones de rendimiento.

## 6. Benchmarking (Tp, Speedup, Eficiencia)

```bash
./scripts/benchmark.sh test_images/benchmark_400x300.ppm gaussian "1 2 4 8"
```

Genera `resultados/tiempos.csv` y una tabla en consola con Tp, Sp = T1/Tp
y Ep = Sp/p para cada cantidad de procesos. Use estos datos para la
sección de resultados experimentales del informe (gráficos de
Speedup/Eficiencia vs. p).

## 7. Diseño (resumen para la defensa)

- **Arquitectura servidor + clientes** (mismo patrón que `pi.erl` de la
  clase): `imgServer/3` es un proceso servidor con `receive` en loop que
  acumula resultados en su estado (una tupla `{Resultados, Pendientes,
  Reintentos, Cola}`, al estilo de `{D,T}` en `piServer`). `lanzarTodos/3`
  crea un proceso "cliente" (`trabajar/3`) para cada banda inicial —
  igual que `nClientes/3` crea clientes que hacen `Server ! nPuntos(Pts)`
  —, solo que aquí cada cliente primero habla con una instancia de
  Racket antes de mandarle el resultado al servidor. Para no agotar
  recursos con `N` grande, no se lanzan todas las bandas de una vez:
  solo un cupo inicial, y el resto queda en una cola que `imgServer` va
  vaciando a medida que se libera un cupo (ver sección 8).
- **Sin funciones anónimas en Erlang**: ni `spawn` ni el chequeo de
  errores usan `fun...end`. Los dos `spawn` del proyecto usan la forma
  `spawn(?MODULE, Funcion, Args)` (`spawn/3`), que llama a una función
  **exportada** por su nombre — por eso `imgServer/3` y `trabajar/3`
  están en el `-export()` aunque no formen parte de la interfaz
  pública, es solo para que `spawn/3` las pueda invocar. El chequeo de
  "¿hay algún error?" (`hayError/1`) también es recursión nombrada en
  vez de `lists:any` con una función anónima.
- **División de la imagen**: en `N` bandas horizontales de tamaño
  similar (el ancho completo, alto ≈ H/N). Simplifica el manejo del halo:
  solo se necesita halo arriba/abajo, nunca a los costados.
- **Halo / región de contexto**: Erlang siempre construye, para cada
  banda, `radio` filas adicionales arriba y abajo (`radio` depende del
  tamaño de kernel pedido: `(ksize-1)/2`), leyendo la imagen original
  con la estrategia de borde elegida. Scheme filtra la región completa
  (con halo) y luego recorta exactamente esas filas antes de devolver
  el resultado — así solo regresa los píxeles que le corresponden a su
  banda.
- **Manejo de bordes, configurable**: `extender` (por defecto, replica
  el píxel más cercano) o `ceros` (píxeles fuera de la imagen valen
  `(0,0,0)`). Se aplica de forma uniforme tanto en los bordes reales de
  la imagen como en los límites entre regiones — aunque en el halo
  entre regiones vecinas la estrategia nunca se activa de verdad,
  porque esa coordenada siempre cae dentro de la imagen real (es una
  fila de otra banda, no un borde genuino).
- **Filtro en Scheme, sin bucles imperativos y sin atajos de Racket**:
  `filtro.rkt` está escrito 100% con `(define nombre (lambda (args)
  ...))`, recursión explícita con `cond` y funciones auxiliares `-aux`,
  igual que `clase.scm`. No usa `for`/`for*`, no usa `let`/`let*`/
  `letrec` (los locales se declaran con `define` interno), no usa
  `set!`, y no usa `list-ref` (el acceso a un elemento de una lista se
  hace a mano con `nth-aux`, bajando recursivamente el contador). El
  cálculo de la convolución reutiliza el mismo patrón de producto punto
  `pp` que aparece en `clase.scm` (`(apply + (map * v w))`), aplicado
  canal por canal contra la lista de vecinos de cada píxel.
- **Kernel gaussiano de tamaño arbitrario, generado por Scheme**: en
  vez de que Erlang mande los `K*K` coeficientes ya calculados,
  `filtro.rkt` los genera el mismo a partir de la fila `(ksize-1)` del
  **triángulo de Pascal** (`fila-pascal`, recursión clásica
  `C(n,k)=C(n-1,k-1)+C(n-1,k)`) y su producto externo consigo misma.
  Para `ksize=3` da exactamente `[[1,2,1],[2,4,2],[1,2,1]]/16`.
- **Filtro `transponer`, reutilizando literalmente `transpuesta` de
  `clase.scm`**: intercambia filas por columnas de la imagen usando
  exactamente la misma función recursiva de la clase (`(cons (map car M)
  (transpuesta (map cdr M)))`), sin modificarla. Es una operación
  **global** sobre toda la imagen (no tiene sentido aplicarla banda por
  banda), así que `image_processor.erl` fuerza `N=1` automáticamente
  cuando se pide este filtro con `N>1`, avisando por qué. Se verificó
  que `transponer(transponer(X)) = X` exactamente (round-trip sin
  pérdida).
- **Protocolo Erlang↔Scheme**: mensajes de texto UTF-8 con formato de
  líneas `FILTER`/`PARAMS`/`DIMS`/`HALO`/`BORDE`/`PIXELS`, transportados
  con el *framing* estándar de puertos Erlang `{packet,4}` (4 bytes de
  longitud big-endian + cuerpo). Cada cliente abre un puerto hacia
  `racket scheme/filtro.rkt`; ese proceso Racket procesa una única
  petición y termina (instancia independiente por región, como exige el
  enunciado).
- **Tolerancia a fallos**: si Scheme responde `ERROR` o termina con
  código de salida distinto de 0, `imgServer` lo registra en su estado
  (avisando por consola) y crea un nuevo cliente para esa banda
  (reintento automático, hasta `MAX_REINTENTOS`). Si sigue fallando, el
  programa aborta **sin** escribir una imagen incorrecta.
- **Verificación de corrección**: procesar la misma imagen con `p=1` y
  `p=4` produce **exactamente el mismo resultado** (verificado con
  `diff`) para el kernel clásico, para `ksize=5`, y para ambas
  estrategias de borde — lo que confirma que el halo está bien
  calculado en todos los casos.

### Tabla de correspondencia con `pi.erl`

| `pi.erl`                          | `image_processor.erl`                     |
|------------------------------------|--------------------------------------------|
| `piServer/1` (servidor, receive)   | `imgServer/3`                               |
| `nClientes/3` (crea clientes)      | `lanzarTodos/3` (con cupo + cola)           |
| cliente: `Server ! nPuntos(Pts)`   | cliente: `trabajar/3` → `Server ! {resultado, Idx, R}` |
| mensaje `{A,B}` (acumula)          | mensaje `{resultado, Idx, R}`               |
| mensaje `fin` (apaga, sin recursar)| mensaje `fin`                               |

## 7.1. Herramientas de análisis que reutilizan algoritmos de `clase.scm`

Además del filtro `transponer` (que reutiliza `transpuesta`, ver arriba),
se agregaron dos scripts de análisis que reutilizan **literalmente**
(sin modificar la lógica) otros algoritmos de `clase.scm`. No forman
parte del pipeline principal Erlang↔Scheme — son herramientas
independientes para enriquecer el informe con datos reales.

### `scripts/analizar_compresion.rkt` — reutiliza `pack`/`pack-aux`

Copia exacta de `pack`/`pack-aux` de `clase.scm` (codificación por
longitud de racha / *run-length encoding*), aplicada a la lista plana
de valores de una imagen para medir qué tan compresible es.

```bash
racket scripts/analizar_compresion.rkt test_images/checkerboard_100x100.ppm \
       test_images/ruido_80x80.ppm test_images/gradiente_64x64.ppm
```

**Resultados reales obtenidos** (no hipotéticos):

| Imagen | Valores | Grupos (pack) | Racha promedio |
|---|---|---|---|
| `checkerboard_100x100.ppm` (original) | 30 000 | 405 | **74.07** |
| `checkerboard_100x100.ppm` + gaussiano | 30 000 | 1 213 | 24.73 |
| `ruido_80x80.ppm` (original) | 19 200 | 19 200 | 1.00 |
| `ruido_80x80.ppm` + gaussiano | 19 200 | 19 198 | 1.00 |
| `gradiente_64x64.ppm` | 12 288 | 12 096 | 1.02 |

**Hallazgo (contraintuitivo, verificado con datos):** difuminar el
tablero de ajedrez lo hace **menos** compresible por RLE (74→25
valores/grupo), no más. El desenfoque gaussiano convierte los bordes
duros entre bloques uniformes en rampas de grises intermedios,
rompiendo las rachas largas de un mismo valor aunque la imagen se vea
"más suave". El ruido y el degradado, en cambio, casi no tienen
rachas para empezar (cada píxel ya es distinto de su vecino), así que
el filtro casi no cambia su compresibilidad. Esto ilustra por qué
formatos reales de compresión de imagen (PNG, JPEG) no usan RLE puro
sobre los píxeles crudos.

### `scripts/comparar_histogramas.rkt` — reutiliza `quicksort`+`pack`+`mergecount`

Misma combinación de algoritmos que `pto-equilibrio` en `clase.scm`
(`(mergecount (pack (quicksort ...)) (pack (quicksort ...)))`), aplicada
para comparar el histograma de intensidades de dos imágenes en vez de
comparar sumas de filas contra sumas de columnas de una matriz.
`quicksort` no está definido en `clase.scm` (solo se lo referencia
desde `pto-equilibrio`), así que se implementó con la misma firma y
estilo recursivo de la clase.

```bash
racket scripts/comparar_histogramas.rkt imagenA.ppm imagenB.ppm
```

**Resultados reales obtenidos** (similitud coseno derivada de `mergecount`,
1.0 = distribuciones idénticas, 0.0 = sin superposición):

| Comparación | Similitud |
|---|---|
| Imagen contra sí misma | **1.0000** |
| `checkerboard` original vs. su propio gaussiano | 0.9852 |
| `colorbars` original vs. su propio `grayscale` | **1.0000** (exacto) |
| `checkerboard` vs. `ruido` (sin relación) | **0.0000** |

El caso de `colorbars` vs. su `grayscale` dando exactamente 1.0000 no
es casualidad: los coeficientes de luminancia usados en
`filtro-grayscale` suman exactamente 1.0 (`0.299+0.587+0.114`), así que
recalcular la luminancia de una imagen ya convertida a gris devuelve el
mismo valor — la comparación de histogramas termina validando, de
paso, que `filtro-grayscale` es matemáticamente idempotente bajo esa
métrica.

## 8. Robustez (agregado tras revisión de código)

- **Validación de `N`**: `N` debe ser un entero positivo. `N=0` o no
  numérico se rechaza con un mensaje claro en vez de reventar por
  división por cero. Si se pide más `N` que filas tiene la imagen, se
  limita automáticamente a la cantidad de filas (con aviso).
- **Límite de concurrencia**: no se lanzan las `N` instancias de
  Racket todas de una vez. Se detectó experimentalmente que hacerlo
  con `N` grande sobre una imagen chica agota la memoria/CPU
  disponible (varias instancias terminan matadas por el sistema
  operativo — `exit_status 137` — y otras entran en timeout). Ahora
  solo se lanza un cupo inicial (`schedulers_online * 4`, acotado al
  total de bandas) y el resto queda en una cola: cada vez que una
  banda termina (bien o mal, tras sus reintentos), se libera un cupo y
  se lanza la siguiente banda pendiente. El resultado final es
  exactamente el mismo — se verificó procesando la misma imagen con
  `p=1` y `p=64` (cola activa) y comparando con `diff`.
- **Resultados duplicados**: `imgServer` ignora un resultado para una
  banda que ya tiene resultado registrado, por si algún día se agrega
  paralelismo adicional en la capa de reintento.
- **Semántica de `MAX_REINTENTOS`**: con `MAX_REINTENTOS = 1` se hacen
  como máximo **2 ejecuciones totales** por banda (el intento original
  + 1 reintento), no 2 reintentos adicionales.

## 9. ¿Se consideraron las fortalezas/debilidades de cada lenguaje?

Sí, aunque un punto se descubrió recién al medir con datos reales (ver
`informe/informe.md`, sección 8.1, para la tabla completa y la
metodología). En resumen:

- **Reparto de responsabilidades**: Erlang solo coordina, divide,
  crea procesos y reintenta ante fallos (su fortaleza: concurrencia y
  tolerancia a fallos); nunca hace aritmética de píxeles (su
  debilidad). Scheme solo procesa una región y termina, sin manejar
  concurrencia ni red (evita su debilidad ahí).
- **Hallazgo al medir**: se esperaba que la convolución (cómputo
  numérico) fuera el cuello de botella en Scheme, dado que "no es
  ideal para alto rendimiento numérico". Al instrumentar `filtro.rkt`
  sobre la imagen de 400×300, la convolución en sí solo representa
  ~6% del tiempo (205 ms); el **86% del tiempo (3.1 s) se va en
  parsear el protocolo de texto** (convertir ~360 000 tokens de texto
  a números de Racket). Es decir: la debilidad numérica de Scheme casi
  no pesa aquí; el costo real es una decisión de diseño (protocolo de
  texto plano, elegido por ser fácil de depurar) que se puede
  documentar y, si hiciera falta, resolver con un protocolo binario.
- **Erlang distribuido**: el sistema corre en un solo nodo; no se usa
  la capacidad de Erlang de correr en múltiples nodos físicos, porque
  el enunciado no lo pide. Queda como extensión natural a mencionar en
  la defensa si preguntan por ese aspecto de la fortaleza de Erlang.

## 10. Limitaciones conocidas

- La división es solo por bandas horizontales (no en cuadrícula 2D).
- No hay *pipeline* de múltiples filtros encadenados en una sola
  invocación (se puede lograr aplicando el programa dos veces).
- El *pool* de procesos no es persistente: cada región crea y destruye
  una instancia de Racket, lo cual pesa en imágenes pequeñas (ver
  discusión de *overhead* en el informe).
