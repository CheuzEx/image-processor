(require racket/string racket/port racket/list racket/format racket/math)

(define quicksort
  (lambda (L menor?)
    (cond
      ((null? L) '())
      (else
       (define pivote (car L))
       (define resto (cdr L))
       (define menores
         (filter (lambda (x) (menor? x pivote)) resto))
       (define resto-mayores-o-iguales
         (filter (lambda (x) (not (menor? x pivote))) resto))
       (append
        (quicksort menores menor?)
        (list pivote)
        (quicksort resto-mayores-o-iguales menor?))))))

(define pack
  (lambda (L)
    (cond
      ((null? L) '())
      (else (pack-aux (cdr L) (car L) 1)))))

(define pack-aux
  (lambda (L PA tam)
    (cond
      ((null? L) (list (list PA tam)))
      ((equal? (car L) PA)
       (pack-aux (cdr L) PA (+ 1 tam)))
      (else
       (cons (list PA tam)
             (pack-aux (cdr L) (car L) 1))))))

(define mergecount
  (lambda (L1 L2)
    (cond
      ((or (null? L1) (null? L2)) 0)
      ((< (caar L1) (caar L2))
       (mergecount (cdr L1) L2))
      ((> (caar L1) (caar L2))
       (mergecount L1 (cdr L2)))
      (else
       (+ (* (cadar L1) (cadar L2))
          (mergecount (cdr L1) (cdr L2)))))))

(define leer-ppm
  (lambda (path)
    (define contenido
      (call-with-input-file
       path
       (lambda (i) (port->string i))))
    (define lineas (string-split contenido "\n"))
    (define dims
      (string-split (cadr lineas) " " #:trim? #t))
    (define ancho (string->number (car dims)))
    (define alto (string->number (cadr dims)))
    (define tokens
      (map string->number
           (append-map
            (lambda (l)
              (string-split l " " #:trim? #t))
            (cdddr lineas))))
    (values ancho alto tokens)))

(define a-grises
  (lambda (plano)
    (cond
      ((null? plano) '())
      (else
       (define r (car plano))
       (define g (cadr plano))
       (define b (caddr plano))
       (cons
        (inexact->exact
         (round
          (+ (* 0.299 r)
             (* 0.587 g)
             (* 0.114 b))))
        (a-grises (cdddr plano)))))))

(define histograma
  (lambda (valores)
    (pack (quicksort valores <))))

(define auto-mergecount
  (lambda (H)
    (mergecount H H)))

(define comparar
  (lambda (pathA pathB)
    (define-values (anchoA altoA pixA)
      (leer-ppm pathA))
    (define-values (anchoB altoB pixB)
      (leer-ppm pathB))
    (define hA (histograma (a-grises pixA)))
    (define hB (histograma (a-grises pixB)))
    (define cruce (mergecount hA hB))
    (define normA (auto-mergecount hA))
    (define normB (auto-mergecount hB))
    (define similitud
      (cond
        ((and (> normA 0) (> normB 0))
         (/ cruce (sqrt (* 1.0 normA normB))))
        (else 0)))
    (printf "A: ~a (~ax~a)\n" pathA anchoA altoA)
    (printf "B: ~a (~ax~a)\n" pathB anchoB altoB)
    (printf "  mergecount(A,B) = ~a\n" cruce)
    (printf "  similitud coseno de histogramas = ~a\n"
            (real->decimal-string similitud 4))))

(define main
  (lambda ()
    (define args
      (vector->list (current-command-line-arguments)))
    (cond
      ((not (= (length args) 2))
       (printf
        "Uso: racket comparar_histogramas.rkt imagenA.ppm imagenB.ppm\n"))
      (else
       (comparar (car args) (cadr args))))))

(main)
