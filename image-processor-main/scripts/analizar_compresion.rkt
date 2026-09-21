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

(define leer-ppm
  (lambda (path)
    (define contenido
      (call-with-input-file
       path
       (lambda (i) (port->string i))))
    (define lineas (string-split contenido "\n"))
    (define dims (string-split (cadr lineas) " " #:trim? #t))
    (define ancho (string->number (car dims)))
    (define alto (string->number (cadr dims)))
    (define tokens
      (append-map
       (lambda (l) (string-split l " " #:trim? #t))
       (cdddr lineas)))
    (values ancho alto (map string->number tokens))))

(define analizar
  (lambda (path)
    (define-values (ancho alto pixeles) (leer-ppm path))
    (define n (length pixeles))
    (define grupos (pack pixeles))
    (define cant-grupos (length grupos))
    (define tasa
      (cond
        ((> n 0) (/ (* 2.0 cant-grupos) n))
        (else 0)))
    (printf "~a  (~ax~a, ~a valores)\n" path ancho alto n)
    (printf "  grupos tras RLE (pack): ~a\n" cant-grupos)
    (printf "  tasa aprox. (2*grupos/valores, menor es mas compresible): ~a\n"
            (real->decimal-string tasa 4))
    (printf "  racha promedio: ~a valores/grupo\n\n"
            (real->decimal-string
             (cond
               ((> cant-grupos 0) (/ n cant-grupos))
               (else 0))
             2))))

(define procesar-archivos
  (lambda (args)
    (cond
      ((null? args) #f)
      (else
       (analizar (car args))
       (procesar-archivos (cdr args))))))

(define main
  (lambda ()
    (define args
      (vector->list (current-command-line-arguments)))
    (cond
      ((null? args)
       (printf "Uso: racket analizar_compresion.rkt archivo1.ppm [archivo2.ppm ...]\n"))
      (else
       (procesar-archivos args)))))

(main)
