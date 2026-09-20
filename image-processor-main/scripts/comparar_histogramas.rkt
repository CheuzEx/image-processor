#lang racket/base
;; -----------------------------------------------------------------------
;; comparar_histogramas.rkt
;;
;; Reutiliza la MISMA combinacion de algoritmos que pto-equilibrio en
;; clase.scm:
;;
;;   (define pto-equilibrio
;;     (lambda (M)
;;       (mergecount (pack (quicksort (map (lambda (f) (apply + f)) M) <))
;;                   (pack (quicksort (map (lambda (c) (apply + c)) (apply map list M)) <)))))
;;
;; es decir: (1) ordenar una lista de valores, (2) empaquetarla con
;; pack (que sobre una lista ORDENADA da exactamente un histograma
;; valor->repeticiones), y (3) usar mergecount para "cruzar" dos
;; histogramas ya ordenados sumando el producto de repeticiones donde
;; los valores coinciden -- el mismo patron "estilo merge" que se usa
;; para contar inversiones o interseccion de listas ordenadas.
;;
;; Aqui, en vez de comparar sumas de filas contra sumas de columnas de
;; una matriz (como en pto-equilibrio), comparamos el histograma de
;; intensidades de DOS IMAGENES para medir que tan parecidas son sus
;; distribuciones de color.
;;
;; Uso: racket scripts/comparar_histogramas.rkt imagenA.ppm imagenB.ppm
;; -----------------------------------------------------------------------

(require racket/string racket/port racket/list racket/format racket/math)

;; ---- quicksort: referenciado mas no definido en clase.scm (se usa en
;; pto-equilibrio como "(quicksort L <)"); se implementa aca con la
;; misma firma (lista, predicado de orden) en el mismo estilo
;; recursivo de la clase. ----
(define (quicksort L menor?)
  (cond
    [(null? L) '()]
    [else
     (define pivote (car L))
     (define resto (cdr L))
     (define menores (filter (λ (x) (menor? x pivote)) resto))
     (define resto-mayores-o-iguales (filter (λ (x) (not (menor? x pivote))) resto))
     (append (quicksort menores menor?) (list pivote) (quicksort resto-mayores-o-iguales menor?))]))

;; ---- pack / pack-aux: exactamente como en clase.scm ----
(define (pack L)
  (cond
    [(null? L) '()]
    [else (pack-aux (cdr L) (car L) 1)]))

(define (pack-aux L PA tam)
  (cond
    [(null? L) (list (list PA tam))]
    [(equal? (car L) PA) (pack-aux (cdr L) PA (+ 1 tam))]
    [else (cons (list PA tam) (pack-aux (cdr L) (car L) 1))]))

;; ---- mergecount: exactamente como en clase.scm ----
(define (mergecount L1 L2)
  (cond
    [(or (null? L1) (null? L2)) 0]
    [(< (caar L1) (caar L2)) (mergecount (cdr L1) L2)]
    [(> (caar L1) (caar L2)) (mergecount L1 (cdr L2))]
    [else (+ (* (cadar L1) (cadar L2)) (mergecount (cdr L1) (cdr L2)))]))

;; ---- lectura minima de PPM (P3), y conversion a intensidad (grises) ----

(define (leer-ppm path)
  (define contenido (call-with-input-file path (λ (i) (port->string i))))
  (define lineas (string-split contenido "\n"))
  (define dims (string-split (cadr lineas) " " #:trim? #t))
  (define ancho (string->number (car dims)))
  (define alto (string->number (cadr dims)))
  (define tokens (map string->number (append-map (λ (l) (string-split l " " #:trim? #t)) (cdddr lineas))))
  (values ancho alto tokens))

;; Convierte la lista plana R G B R G B ... en una lista de
;; intensidades de gris (una por pixel), para poder comparar imagenes
;; de forma perceptualmente razonable en vez de comparar canales R,G,B
;; sueltos.
(define (a-grises plano)
  (cond
    [(null? plano) '()]
    [else
     (define r (car plano)) (define g (cadr plano)) (define b (caddr plano))
     (cons (inexact->exact (round (+ (* 0.299 r) (* 0.587 g) (* 0.114 b))))
           (a-grises (cdddr plano)))]))

;; histograma: ordenar + pack = lista (valor repeticiones) ordenada
(define (histograma valores) (pack (quicksort valores <)))

(define (auto-mergecount H) (mergecount H H))

(define (comparar pathA pathB)
  (define-values (anchoA altoA pixA) (leer-ppm pathA))
  (define-values (anchoB altoB pixB) (leer-ppm pathB))
  (define hA (histograma (a-grises pixA)))
  (define hB (histograma (a-grises pixB)))
  (define cruce (mergecount hA hB))
  (define normA (auto-mergecount hA))
  (define normB (auto-mergecount hB))
  ;; similitud coseno entre los dos histogramas vistos como vectores
  ;; (uno por valor de gris 0..255): 1.0 = distribuciones identicas,
  ;; 0.0 = sin superposicion.
  (define similitud (if (and (> normA 0) (> normB 0))
                         (/ cruce (sqrt (* 1.0 normA normB)))
                         0))
  (printf "A: ~a (~ax~a)\n" pathA anchoA altoA)
  (printf "B: ~a (~ax~a)\n" pathB anchoB altoB)
  (printf "  mergecount(A,B) = ~a\n" cruce)
  (printf "  similitud coseno de histogramas = ~a\n" (real->decimal-string similitud 4)))

(module+ main
  (define args (vector->list (current-command-line-arguments)))
  (cond
    [(not (= (length args) 2))
     (printf "Uso: racket comparar_histogramas.rkt imagenA.ppm imagenB.ppm\n")]
    [else (comparar (car args) (cadr args))]))
