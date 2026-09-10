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

Desde la raíz del proyecto (`proyecto/`):

```bash
erlc -o erlang erlang/ppm.erl erlang/image_processor.erl
```

Scheme no requiere compilación: `filtro.rkt` se ejecuta directamente con
`racket`.

## 4. Ejecutar

Siempre desde la raíz del proyecto, porque `image_processor` invoca
`racket scheme/filtro.rkt` con una ruta relativa.

```bash
erl -noshell -pa erlang -eval \
  'image_processor:main(["ENTRADA.ppm","SALIDA.ppm","N","FILTRO"]), init:stop().'
```

Ejemplos equivalentes a la interfaz pedida en el enunciado
(`./image_processor entrada.ppm salida.ppm N`):

```bash
erl -noshell -pa erlang -eval 'image_processor:main(["test_images/benchmark_400x300.ppm","salida1.ppm","1"]), init:stop().'
erl -noshell -pa erlang -eval 'image_processor:main(["test_images/benchmark_400x300.ppm","salida2.ppm","2"]), init:stop().'
erl -noshell -pa erlang -eval 'image_processor:main(["test_images/benchmark_400x300.ppm","salida4.ppm","4"]), init:stop().'
erl -noshell -pa erlang -eval 'image_processor:main(["test_images/benchmark_400x300.ppm","salida8.ppm","8"]), init:stop().'
```

El cuarto argumento (filtro) es opcional; por defecto es `gaussian`.
Filtros disponibles:

| Filtro       | Necesita halo | Descripción                          |
|--------------|:---:|----------------------------------------------|
| `gaussian`   | sí  | Difuminado gaussiano 3×3 (obligatorio)        |
| `sharpen`    | sí  | Realce de bordes (extensión, kernel 3×3)      |
| `grayscale`  | no  | Escala de grises (extensión, punto a punto)   |
| `invert`     | no  | Inversión de colores                          |
| `threshold`  | no  | Binarización (umbral 128)                     |
| `brightness` | no  | Ajuste de brillo (+30)                        |
| `transponer` | no  | Intercambia filas/columnas (solo `N=1`, ver abajo) |

> Nota práctica: si su terminal/IDE ejecuta escripts Erlang directamente,
> también puede envolver la llamada anterior en un escript propio; se
> dejó como llamada explícita `erl -eval` para que sea trivial de
> ejecutar y de depurar durante la defensa.

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
  clase): `imgServer/1` es un proceso servidor con `receive` en loop que
  acumula resultados en su estado — exactamente igual que `piServer/1`
  acumula `{D,T}` a partir de los mensajes que le mandan sus clientes.
  `lanzarBanda/3` crea un proceso "cliente" para cada banda de la imagen
  — igual que `nClientes/3` crea clientes que hacen
  `Server ! nPuntos(Pts)` —, solo que aquí cada cliente
  (`trabajarRegion/3`) primero habla con una instancia de Racket antes
  de mandarle el resultado al servidor. Para no agotar recursos con `N`
  grande, no se lanzan todas las bandas de una vez: solo un cupo inicial,
  y el resto queda en una cola que `imgServer` va vaciando a medida que
  se libera un cupo (ver sección 8). `imgServer` entiende tres
  mensajes: `{resultado, Idx, R}` (como el `{A,B}` de `piServer`),
  `{progreso, Pid}` (consulta de avance, como el `valepi` de la clase) y
  `fin` (se apaga sin volver a recursar, igual que la cláusula `fin` de
  `piServer`).
- **División de la imagen**: en `N` bandas horizontales de tamaño
  similar (el ancho completo, alto ≈ H/N). Simplifica el manejo del halo:
  solo se necesita halo arriba/abajo, nunca a los costados.
- **Halo / región de contexto**: Erlang siempre construye, para cada
  banda, `radio` filas adicionales arriba y abajo (radio = 1 para un
  kernel 3×3), leyendo la imagen original con coordenadas recortadas
  (*clamp*). Scheme filtra la región completa (con halo) y luego recorta
  exactamente esas filas antes de devolver el resultado — así solo
  regresa los píxeles que le corresponden a su banda.
- **Manejo de bordes**: estrategia de *extensión de borde* (replicar el
  píxel más cercano). Se aplica de forma uniforme tanto en los bordes
  reales de la imagen como en los límites entre regiones, usando la
  misma función de recorte de coordenadas (`clamp`) en ambos lenguajes.
- **Filtro en Scheme, sin bucles imperativos**: `filtro.rkt` está escrito
  con recursión explícita y funciones auxiliares `-aux`, igual que
  `clase.scm` (nada de `for`/`for*` ni tablas mutables). El cálculo de
  la convolución reutiliza el mismo patrón de producto punto `pp` que
  aparece en `clase.scm` (`(apply + (map * v w))`), aplicado canal por
  canal contra la lista de vecinos de cada píxel.
- **Filtro `transponer`, reutilizando literalmente `transpuesta` de
  `clase.scm`**: intercambia filas por columnas de la imagen usando
  exactamente la misma función recursiva de la clase (`(cons (map car M)
  (transpuesta (map cdr M)))`), sin modificarla — solo se convierte la
  matriz de vectores a lista de listas antes y después, ya que
  `transpuesta` está pensada para listas. Es una operación **global**
  sobre toda la imagen (no tiene sentido aplicarla banda por banda), así
  que `image_processor.erl` fuerza `N=1` automáticamente cuando se pide
  este filtro con `N>1`, avisando por qué. Se verificó que
  `transponer(transponer(X)) = X` exactamente (round-trip sin pérdida).
- **Protocolo Erlang↔Scheme**: mensajes de texto UTF-8 con formato de
  líneas `FILTER`/`PARAMS`/`DIMS`/`HALO`/`PIXELS`, transportados con el
  *framing* estándar de puertos Erlang `{packet,4}` (4 bytes de longitud
  big-endian + cuerpo). Cada cliente abre un puerto hacia
  `racket scheme/filtro.rkt`; ese proceso Racket procesa una única
  petición y termina (instancia independiente por región, como exige el
  enunciado).
- **Tolerancia a fallos**: si Scheme responde `ERROR` o termina con
  código de salida distinto de 0, `imgServer` lo registra en su estado
  y crea un nuevo cliente para esa banda (reintento automático, hasta
  `MAX_REINTENTOS`). Si sigue fallando, el programa aborta **sin**
  escribir una imagen incorrecta.
- **Verificación de corrección**: procesar la misma imagen con `p=1`,
  `p=4` y `p=8` produce **exactamente el mismo resultado** (verificado
  con `diff`), lo que confirma que el halo está bien calculado
  independientemente de en cuántas bandas se divida la imagen.

### Tabla de correspondencia con `pi.erl`

| `pi.erl`                          | `image_processor.erl`                     |
|------------------------------------|--------------------------------------------|
| `piServer/1` (servidor, receive)   | `imgServer/1`                               |
| `nClientes/3` (crea clientes)      | `lanzarBanda/3` (con cupo + cola)           |
| cliente: `Server ! nPuntos(Pts)`   | cliente: `trabajarRegion/3` → `Server ! {resultado, Idx, R}` |
| mensaje `{A,B}` (acumula)          | mensaje `{resultado, Idx, R}`               |
| mensaje `valepi` (consulta)        | mensaje `{progreso, Pid}`                   |
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
