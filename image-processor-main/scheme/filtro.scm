#lang swindle
(define split-cadena-aux
  (lambda (str sep)
    (define len (string-length str))
    (define buscar
      (lambda (i inicio)
        (cond ((>= i len)
               (if (> i inicio)
                   (list (substring str inicio i))
                   '()))
              ((char=? (string-ref str i) sep)
               (if (> i inicio)
                   (cons (substring str inicio i) (buscar (+ i 1) (+ i 1)))
                   (buscar (+ i 1) (+ i 1))))
              (else (buscar (+ i 1) inicio)))))
    (buscar 0 0)))

(define unir-cadenas-aux
  (lambda (lst sep)
    (cond
      ((null? lst) "")
      (else
       (define out (open-output-string))
       (escribir-cadenas-aux lst sep out)
       (get-output-string out)))))

(define escribir-cadenas-aux
  (lambda (lst sep out)
    (cond
      ((null? lst) #t)
      ((null? (cdr lst))
       (write-string (car lst) out))
      (else
       (write-string (car lst) out)
       (write-string sep out)
       (escribir-cadenas-aux (cdr lst) sep out)))))

;; ---------- framing de 4 bytes (protocolo con Erlang) ----------

(define leer-entero32
  (lambda (in)
    (define bs (read-bytes 4 in))
    (cond ((or (eof-object? bs) (< (bytes-length bs) 4)) #f)
          (else (integer-bytes->integer bs #f #t)))))

;; Argumento opcional adaptado usando '. rest' para evitar el error de sintaxis en Swindle
(define leer-paquete
  (lambda rest
    (define in (if (null? rest) (current-input-port) (car rest)))
    (define n (leer-entero32 in))
    (cond ((not n) #f)
          (else (define cuerpo (read-bytes n in))
                (cond ((eof-object? cuerpo) #f)
                      (else (bytes->string/utf-8 cuerpo)))))))

(define escribir-paquete
  (lambda (texto . rest)
    (define out (if (null? rest) (current-output-port) (car rest)))
    (define bs (string->bytes/utf-8 texto))
    (write-bytes (integer->integer-bytes (bytes-length bs) 4 #f #t) out)
    (write-bytes bs out)
    (flush-output out)))

;; ---------- parsing del cuerpo (lineas CLAVE valor valor ...) ----------

(define analizar-peticion
  (lambda (texto)
    (analizar-lineas-aux (split-cadena-aux texto #\newline))))

(define analizar-lineas-aux
  (lambda (lineas)
    (cond ((null? lineas) '())
          (else (define partes (split-cadena-aux (car lineas) #\space))
                (cond ((null? partes) (analizar-lineas-aux (cdr lineas)))
                      (else (cons (cons (string-upcase (car partes)) (cdr partes))
                                  (analizar-lineas-aux (cdr lineas)))))))))

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

;; ---------- acceso manual a un elemento de una lista, sin list-ref ----------

(define nth-aux
  (lambda (lst n)
    (cond ((zero? n) (car lst))
          (else (nth-aux (cdr lst) (- n 1))))))

;; ---------- region como lista de filas, cada fila lista de pixeles (r g b) ----------

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

(define obtener-pixel
  (lambda (m alto ancho fila col borde)
    (define f2 (recortar-valor fila 0 (- alto 1)))
    (cond ((and (eq? borde 'ceros) (or (< col 0) (>= col ancho)))
           (list 0 0 0))
          (else (nth-aux (nth-aux m f2) (recortar-valor col 0 (- ancho 1)))))))

(define pp (lambda (v w) (apply + (map * v w))))

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
  (lambda (m alto ancho fila col offsets borde)
    (cond ((null? offsets) '())
          (else (cons (obtener-pixel m alto ancho (+ fila (caar offsets)) (+ col (cdar offsets)) borde)
                      (vecinos-aux m alto ancho fila col (cdr offsets) borde))))))

(define convolucion
  (lambda (m ancho alto kernel r divisor borde)
    (define offsets (offsets-aux r))
    (convolucion-filas-aux m ancho alto kernel divisor offsets 0 borde)))

(define convolucion-filas-aux
  (lambda (m ancho alto kernel divisor offsets fila borde)
    (cond ((>= fila alto) '())
          (else (cons (convolucion-fila-aux m ancho alto kernel divisor offsets fila 0 borde)
                      (convolucion-filas-aux m ancho alto kernel divisor offsets (+ fila 1) borde))))))

(define convolucion-fila-aux
  (lambda (m ancho alto kernel divisor offsets fila col borde)
    (cond ((>= col ancho) '())
          (else (define vec (vecinos-aux m alto ancho fila col offsets borde))
                (cons (list (recortar-valor (round (/ (pp kernel (map car vec)) divisor)) 0 255)
                            (recortar-valor (round (/ (pp kernel (map cadr vec)) divisor)) 0 255)
                            (recortar-valor (round (/ (pp kernel (map caddr vec)) divisor)) 0 255))
                      (convolucion-fila-aux m ancho alto kernel divisor offsets fila (+ col 1) borde))))))

;; ---------- kernel gaussiano via triangulo de Pascal ----------

(define fila-pascal
  (lambda (n)
    (cond ((zero? n) '(1))
          (else (sumar-adyacentes-aux (cons 0 (append (fila-pascal (- n 1)) '(0))))))))

(define sumar-adyacentes-aux
  (lambda (lst)
    (cond ((or (null? lst) (null? (cdr lst))) '())
          (else (cons (+ (car lst) (cadr lst)) (sumar-adyacentes-aux (cdr lst)))))))

(define producto-externo-aux
  (lambda (fila1 fila2)
    (cond ((null? fila1) '())
          (else (append (map (lambda (x) (* (car fila1) x)) fila2)
                        (producto-externo-aux (cdr fila1) fila2))))))

(define kernel-gaussiano
  (lambda (ksize)
    (define fila (fila-pascal (- ksize 1)))
    (define suma (apply + fila))
    (cons (producto-externo-aux fila fila) (* suma suma))))

;; ---------- filtros ----------

(define filtro-gaussiano
  (lambda (m ancho alto params borde)
    (define ksize (car (a-enteros params)))
    (define kd (kernel-gaussiano ksize))
    (define kernel (car kd))
    (define divisor (cdr kd))
    (convolucion m ancho alto kernel (quotient (- ksize 1) 2) divisor borde)))

(define filtro-sharpen
  (lambda (m ancho alto params borde)
    (convolucion m ancho alto '(0 -1 0 -1 5 -1 0 -1 0) 1 1 borde)))

(define filtro-grayscale
  (lambda (m ancho alto params borde)
    (map
     (lambda (fila)
       (map
        (lambda (p)
          (define gris
            (recortar-valor
             (inexact->exact
              (round
               (+ (* 0.299 (car p))
                  (* 0.587 (cadr p))
                  (* 0.114 (caddr p)))))
             0 255))
          (list gris gris gris))
        fila))
     m)))

(define filtro-invert
  (lambda (m ancho alto params borde)
    (map
     (lambda (fila)
       (map
        (lambda (p)
          (list (- 255 (car p))
                (- 255 (cadr p))
                (- 255 (caddr p))))
        fila))
     m)))

(define filtro-threshold
  (lambda (m ancho alto params borde)
    (define t (car (a-enteros params)))
    (map
     (lambda (fila)
       (map
        (lambda (p)
          (define gris (/ (+ (car p) (cadr p) (caddr p)) 3))
          (cond ((>= gris t) '(255 255 255))
                (else '(0 0 0))))
        fila))
     m)))

(define filtro-brightness
  (lambda (m ancho alto params borde)
    (define delta (car (a-enteros params)))
    (map
     (lambda (fila)
       (map
        (lambda (p)
          (list (recortar-valor (+ (car p) delta) 0 255)
                (recortar-valor (+ (cadr p) delta) 0 255)
                (recortar-valor (+ (caddr p) delta) 0 255)))
        fila))
     m)))

(define transpuesta
  (lambda (M)
    (cond ((null? M) '())
          ((null? (car M)) '())
          (else (cons (map car M) (transpuesta (map cdr M)))))))

(define filtro-transponer (lambda (m ancho alto params borde) (transpuesta m)))

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
    (define borde-texto (string-downcase (car (campo-opcional tabla "BORDE" '("extender")))))
    (define borde (cond ((string=? borde-texto "ceros") 'ceros) (else 'extender)))
    (define f (obtener-filtro nombre))
    (define m (pixeles-a-matriz pixeles ancho alto))
    (define resultado (f m ancho alto params borde))
    (define final
      (cond ((necesita-halo? nombre) (recortar-halo resultado izq arr der ab alto))
            (else resultado)))
    (define alto-final (length final))
    (define ancho-final (cond ((zero? alto-final) 0) (else (length (car final)))))
    (string-append "OK\n"
                   "DIMS " (number->string ancho-final) " " (number->string alto-final) "\n"
                   "PIXELS " (unir-cadenas-aux (map number->string (matriz-a-pixeles final)) " ")
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
