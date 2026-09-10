#lang racket/base
;; filtro.rkt -- procesa UNA region de imagen. Estilo: como clase.scm
;; (define nombre (lambda (args) ...)), todo con listas y cond, sin
;; vectores ni hash-tables. pp y transpuesta son las mismas de clase.scm.

(require racket/string)

;; ---------- framing de 4 bytes (protocolo con Erlang) ----------

(define leer-entero32
  (lambda (in)
    (define bs (read-bytes 4 in))
    (cond ((or (eof-object? bs) (< (bytes-length bs) 4)) #f)
          (else (integer-bytes->integer bs #f #t)))))

(define leer-paquete
  (lambda ([in (current-input-port)])
    (define n (leer-entero32 in))
    (cond ((not n) #f)
          (else (let ([cuerpo (read-bytes n in)])
                  (cond ((eof-object? cuerpo) #f)
                        (else (bytes->string/utf-8 cuerpo))))))))

(define escribir-paquete
  (lambda (texto [out (current-output-port)])
    (define bs (string->bytes/utf-8 texto))
    (write-bytes (integer->integer-bytes (bytes-length bs) 4 #f #t) out)
    (write-bytes bs out)
    (flush-output out)))

;; ---------- parsing del cuerpo (lineas CLAVE valor valor ...) ----------

(define analizar-peticion
  (lambda (texto)
    (analizar-lineas-aux (string-split texto "\n"))))

(define analizar-lineas-aux
  (lambda (lineas)
    (cond ((null? lineas) '())
          (else (let ([partes (string-split (car lineas) " " #:trim? #t)])
                  (cond ((null? partes) (analizar-lineas-aux (cdr lineas)))
                        (else (cons (cons (string-upcase (car partes)) (cdr partes))
                                    (analizar-lineas-aux (cdr lineas))))))))))

(define campo
  (lambda (tabla clave)
    (define entrada (assoc clave tabla))
    (cond (entrada (cdr entrada))
          (else (error 'filtro "campo faltante: ~a" clave)))))

(define campo-opcional
  (lambda (tabla clave defecto)
    (define entrada (assoc clave tabla))
    (cond (entrada (cdr entrada))
          (else defecto))))

(define a-enteros (lambda (lst) (map string->number lst)))

;; ---------- region como lista de filas, cada fila lista de pixeles (r g b) ----------
;; (misma idea que 'mat' en clase.scm: lista de listas)

(define pixeles-a-matriz
  (lambda (plano ancho alto)
    (cond ((zero? alto) '())
          (else (cons (fila-aux plano ancho)
                      (pixeles-a-matriz (resto-filas-aux plano ancho) ancho (- alto 1)))))))

(define fila-aux
  (lambda (plano ancho)
    (cond ((zero? ancho) '())
          (else (cons (list (car plano) (cadr plano) (caddr plano))
                      (fila-aux (cdddr plano) (- ancho 1)))))))

(define resto-filas-aux
  (lambda (plano ancho)
    (cond ((zero? ancho) plano)
          (else (resto-filas-aux (cdddr plano) (- ancho 1))))))

(define matriz-a-pixeles
  (lambda (m)
    (cond ((null? m) '())
          (else (append (fila-a-pixeles-aux (car m)) (matriz-a-pixeles (cdr m)))))))

(define fila-a-pixeles-aux
  (lambda (fila)
    (cond ((null? fila) '())
          (else (append (car fila) (fila-a-pixeles-aux (cdr fila)))))))

(define recortar-valor (lambda (v lo hi) (max lo (min hi v))))

;; Acceso con clamp: fuera de rango -> se recorta a la fila/columna valida
;; mas cercana (misma estrategia de borde para bordes reales y halo).
(define obtener-pixel
  (lambda (m alto ancho fila col)
    (define f2 (recortar-valor fila 0 (sub1 alto)))
    (define c2 (recortar-valor col 0 (sub1 ancho)))
    (list-ref (list-ref m f2) c2)))

;; pp: producto punto, igual que en clase.scm.
(define pp (lambda (v w) (apply + (map * v w))))

;; offsets del kernel cuadrado de radio r, fila por fila (mismo orden del kernel)
(define offsets-aux
  (lambda (r) (offsets-filas-aux (- r) r)))

(define offsets-filas-aux
  (lambda (kf r)
    (cond ((> kf r) '())
          (else (append (offsets-cols-aux kf (- r) r) (offsets-filas-aux (+ kf 1) r))))))

(define offsets-cols-aux
  (lambda (kf kc r)
    (cond ((> kc r) '())
          (else (cons (cons kf kc) (offsets-cols-aux kf (+ kc 1) r))))))

(define vecinos-aux
  (lambda (m alto ancho fila col offsets)
    (cond ((null? offsets) '())
          (else (cons (obtener-pixel m alto ancho (+ fila (caar offsets)) (+ col (cdar offsets)))
                      (vecinos-aux m alto ancho fila col (cdr offsets)))))))

;; convolucion generica: cada canal de salida es pp(kernel, vecinos-del-canal),
;; exactamente el mismo patron de pp/mul-mat de clase.scm.
(define convolucion
  (lambda (m ancho alto kernel r divisor)
    (define offsets (offsets-aux r))
    (convolucion-filas-aux m ancho alto kernel divisor offsets 0)))

(define convolucion-filas-aux
  (lambda (m ancho alto kernel divisor offsets fila)
    (cond ((>= fila alto) '())
          (else (cons (convolucion-fila-aux m ancho alto kernel divisor offsets fila 0)
                      (convolucion-filas-aux m ancho alto kernel divisor offsets (+ fila 1)))))))

(define convolucion-fila-aux
  (lambda (m ancho alto kernel divisor offsets fila col)
    (cond ((>= col ancho) '())
          (else
           (let ([vec (vecinos-aux m alto ancho fila col offsets)])
             (cons (list (recortar-valor (round (/ (pp kernel (map car vec)) divisor)) 0 255)
                         (recortar-valor (round (/ (pp kernel (map cadr vec)) divisor)) 0 255)
                         (recortar-valor (round (/ (pp kernel (map caddr vec)) divisor)) 0 255))
                   (convolucion-fila-aux m ancho alto kernel divisor offsets fila (+ col 1))))))))

;; ---------- filtros ----------

(define filtro-gaussiano
  (lambda (m ancho alto params)
    (define valores (a-enteros params))
    (define ksize (car valores))
    (define divisor (cadr valores))
    (define kernel (cddr valores))
    (convolucion m ancho alto kernel (quotient (sub1 ksize) 2) divisor)))

(define filtro-sharpen
  (lambda (m ancho alto params)
    (convolucion m ancho alto '(0 -1 0 -1 5 -1 0 -1 0) 1 1)))

;; filtros puntuales: no usan vecinos, solo mapean cada pixel con f
(define mapa-puntual
  (lambda (m f)
    (cond ((null? m) '())
          (else (cons (mapa-puntual-fila-aux (car m) f) (mapa-puntual (cdr m) f))))))

(define mapa-puntual-fila-aux
  (lambda (fila f)
    (cond ((null? fila) '())
          (else (cons (f (car fila)) (mapa-puntual-fila-aux (cdr fila) f))))))

(define filtro-grayscale
  (lambda (m ancho alto params)
    (mapa-puntual m (lambda (p)
                       (define gris (recortar-valor
                                     (inexact->exact
                                      (round (+ (* 0.299 (car p)) (* 0.587 (cadr p)) (* 0.114 (caddr p)))))
                                     0 255))
                       (list gris gris gris)))))

(define filtro-invert
  (lambda (m ancho alto params)
    (mapa-puntual m (lambda (p) (list (- 255 (car p)) (- 255 (cadr p)) (- 255 (caddr p)))))))

(define filtro-threshold
  (lambda (m ancho alto params)
    (define t (car (a-enteros params)))
    (mapa-puntual m (lambda (p)
                       (define gris (/ (+ (car p) (cadr p) (caddr p)) 3))
                       (cond ((>= gris t) '(255 255 255)) (else '(0 0 0)))))))

(define filtro-brightness
  (lambda (m ancho alto params)
    (define delta (car (a-enteros params)))
    (mapa-puntual m (lambda (p)
                       (list (recortar-valor (+ (car p) delta) 0 255)
                             (recortar-valor (+ (cadr p) delta) 0 255)
                             (recortar-valor (+ (caddr p) delta) 0 255))))))

;; transpuesta: literal de clase.scm (M es lista de filas, cada fila lista de pixeles)
(define transpuesta
  (lambda (M)
    (cond ((null? M) '())
          ((null? (car M)) '())
          (else (cons (map car M) (transpuesta (map cdr M)))))))

(define filtro-transponer (lambda (m ancho alto params) (transpuesta m)))

;; despacho de filtros por nombre: cond en vez de tabla hash, como en clase.scm
(define obtener-filtro
  (lambda (nombre)
    (cond ((string=? nombre "GAUSSIAN") filtro-gaussiano)
          ((string=? nombre "SHARPEN") filtro-sharpen)
          ((string=? nombre "GRAYSCALE") filtro-grayscale)
          ((string=? nombre "INVERT") filtro-invert)
          ((string=? nombre "THRESHOLD") filtro-threshold)
          ((string=? nombre "BRIGHTNESS") filtro-brightness)
          ((string=? nombre "TRANSPONER") filtro-transponer)
          (else (error 'filtro "filtro desconocido: ~a" nombre)))))

(define necesita-halo?
  (lambda (nombre)
    (cond ((string=? nombre "GAUSSIAN") #t)
          ((string=? nombre "SHARPEN") #t)
          (else #f))))

;; recorta el halo: se queda solo con las filas/columnas de la region propia
(define recortar-halo
  (lambda (m izq arr der ab alto)
    (recortar-halo-aux (quita-primeras m arr) izq der (- alto arr ab))))

(define recortar-halo-aux
  (lambda (m izq der restantes)
    (cond ((zero? restantes) '())
          (else (cons (recortar-fila-aux (car m) izq der)
                      (recortar-halo-aux (cdr m) izq der (- restantes 1)))))))

(define recortar-fila-aux
  (lambda (fila izq der)
    (recortar-fila-quita-izq (recortar-fila-quita-der fila der) izq)))

(define recortar-fila-quita-der
  (lambda (fila der)
    (cond ((zero? der) fila)
          (else (recortar-fila-quita-der (reverse (cdr (reverse fila))) (- der 1))))))

(define recortar-fila-quita-izq
  (lambda (fila izq)
    (cond ((zero? izq) fila)
          (else (recortar-fila-quita-izq (cdr fila) (- izq 1))))))

(define quita-primeras
  (lambda (m n)
    (cond ((zero? n) m)
          (else (quita-primeras (cdr m) (- n 1))))))

;; ---------- manejo de la peticion ----------

(define procesar-peticion
  (lambda (texto)
    (define tabla (analizar-peticion texto))
    (define nombre (string-upcase (car (campo tabla "FILTER"))))
    (define params (campo-opcional tabla "PARAMS" '()))
    (define dims (a-enteros (campo tabla "DIMS")))
    (define ancho (car dims))
    (define alto (cadr dims))
    (define halo (a-enteros (campo tabla "HALO")))
    (define izq (car halo)) (define arr (cadr halo)) (define der (caddr halo)) (define ab (cadddr halo))
    (define pixeles (a-enteros (campo tabla "PIXELS")))
    (define f (obtener-filtro nombre))
    (define m (pixeles-a-matriz pixeles ancho alto))
    (define resultado (f m ancho alto params))
    (define final
      (cond ((necesita-halo? nombre) (recortar-halo resultado izq arr der ab alto))
            (else resultado)))
    (define alto-final (length final))
    (define ancho-final (cond ((zero? alto-final) 0) (else (length (car final)))))
    (string-append "OK\n"
                   "DIMS " (number->string ancho-final) " " (number->string alto-final) "\n"
                   "PIXELS " (string-join (map number->string (matriz-a-pixeles final)) " ")
                   "\n")))

;; ---------- punto de entrada ----------

(define main
  (lambda ()
    (define peticion (leer-paquete))
    (cond
      ((not peticion) (exit 1))
      (else
       (with-handlers
           ([exn:fail? (lambda (e)
                         (escribir-paquete (string-append "ERROR " (exn-message e) "\n"))
                         (exit 1))])
         (escribir-paquete (procesar-peticion peticion))
         (exit 0))))))

(main)
