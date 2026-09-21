#lang swindle
(require racket/string racket/format racket/file racket/path)

(define escribir-ppm
  (lambda (path ancho alto pixel-fn)
    (call-with-output-file path #:exists 'replace
      (lambda (out)
        (fprintf out "P3\n~a ~a\n255\n" ancho alto)
        (escribir-filas out 0 ancho alto pixel-fn)))))

(define escribir-filas
  (lambda (out f ancho alto pixel-fn)
    (cond
      ((>= f alto) #t)
      (else
       (escribir-columnas out f 0 ancho pixel-fn)
       (fprintf out "\n")
       (escribir-filas out (+ f 1) ancho alto pixel-fn)))))

(define escribir-columnas
  (lambda (out f c ancho pixel-fn)
    (cond
      ((>= c ancho) #t)
      (else
       (define-values (r g b) (pixel-fn f c))
       (fprintf out "~a ~a ~a " r g b)
       (escribir-columnas out f (+ c 1) ancho pixel-fn)))))

(define clamp
  (lambda (v)
    (max 0 (min 255 (inexact->exact (round v))))))

(define gradiente
  (lambda (f c ancho alto)
    (values (clamp (* 255 (/ c ancho)))
            (clamp (* 255 (/ f alto)))
            128)))

(define checkerboard
  (lambda (f c)
    (define tam 20)
    (cond
      ((even? (+ (quotient f tam) (quotient c tam)))
       (values 240 240 240))
      (else
       (values 20 20 20)))))

(define colorbars
  (lambda (f c ancho)
    (define franja (quotient (* c 6) ancho))
    (cond
      ((= franja 0) (values 255 0 0))
      ((= franja 1) (values 0 255 0))
      ((= franja 2) (values 0 0 255))
      ((= franja 3) (values 255 255 0))
      ((= franja 4) (values 0 255 255))
      (else (values 255 0 255)))))

(define ruido
  (lambda (f c)
    (define seed (+ (* f 928371) (* c 12007) 17))
    (define v (modulo (* seed seed) 256))
    (values v
            (modulo (+ v 85) 256)
            (modulo (+ v 170) 256))))

(define main
  (lambda ()
    (define args (vector->list (current-command-line-arguments)))
    (define destino
      (cond
        ((not (null? args)) (car args))
        (else "test_images")))

    (make-directory* destino)

    (escribir-ppm
     (build-path destino "gradiente_64x64.ppm")
     64 64
     (lambda (f c) (gradiente f c 64 64)))

    (escribir-ppm
     (build-path destino "checkerboard_100x100.ppm")
     100 100
     (lambda (f c) (checkerboard f c)))

    (escribir-ppm
     (build-path destino "colorbars_120x60.ppm")
     120 60
     (lambda (f c) (colorbars f c 120)))

    (escribir-ppm
     (build-path destino "ruido_80x80.ppm")
     80 80
     (lambda (f c) (ruido f c)))

    (escribir-ppm
     (build-path destino "benchmark_400x300.ppm")
     400 300
     (lambda (f c) (gradiente f c 400 300)))

    (printf "Imágenes de prueba generadas en ~a~n" destino)))

(main)
