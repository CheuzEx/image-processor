#lang racket/base
;; -----------------------------------------------------------------------
;; analizar_compresion.rkt
;;
;; Reutiliza LITERALMENTE pack/pack-aux de clase.scm (codificacion por
;; longitud de racha, "run-length encoding") para medir que tan
;; compresible es una imagen: cuantos "grupos" de valores repetidos
;; consecutivos hay, comparado con la cantidad total de valores.
;;
;;   (define pack
;;     (lambda (L)
;;       (cond ((null? L) '())
;;             (else (pack-aux (cdr L) (car L) 1)))))
;;   (define pack-aux
;;     (lambda (L PA tam)
;;       (cond ((null? L) (list (list PA tam)))
;;             ((equal? (car L) PA) (pack-aux (cdr L) PA (+ 1 tam)))
;;             (else (cons (list PA tam) (pack-aux (cdr L) (car L) 1))))))
;;
;; Uso: racket scripts/analizar_compresion.rkt archivo1.ppm [archivo2.ppm ...]
;; -----------------------------------------------------------------------

(require racket/string racket/port racket/list racket/format)

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

;; ---- lectura minima de PPM (P3) ----

(define (leer-ppm path)
  (define contenido (call-with-input-file path (λ (i) (port->string i))))
  (define lineas (string-split contenido "\n"))
  (define dims (string-split (cadr lineas) " " #:trim? #t))
  (define ancho (string->number (car dims)))
  (define alto (string->number (cadr dims)))
  (define tokens (append-map (λ (l) (string-split l " " #:trim? #t)) (cdddr lineas)))
  (values ancho alto (map string->number tokens)))

;; ---- analisis ----

(define (analizar path)
  (define-values (ancho alto pixeles) (leer-ppm path))
  (define n (length pixeles))
  (define grupos (pack pixeles))
  (define cant-grupos (length grupos))
  ;; tamano "codificado" aproximado: 2 numeros por grupo (valor y
  ;; repeticiones), contra 1 numero por valor original.
  (define tasa (if (> n 0) (/ (* 2.0 cant-grupos) n) 0))
  (printf "~a  (~ax~a, ~a valores)\n" path ancho alto n)
  (printf "  grupos tras RLE (pack): ~a\n" cant-grupos)
  (printf "  tasa aprox. (2*grupos/valores, menor es mas compresible): ~a\n"
          (real->decimal-string tasa 4))
  (printf "  racha promedio: ~a valores/grupo\n\n"
          (real->decimal-string (if (> cant-grupos 0) (/ n cant-grupos) 0) 2)))

(module+ main
  (define args (vector->list (current-command-line-arguments)))
  (cond
    [(null? args)
     (printf "Uso: racket analizar_compresion.rkt archivo1.ppm [archivo2.ppm ...]\n")]
    [else (for-each analizar args)]))
