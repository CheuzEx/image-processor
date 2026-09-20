#lang racket/base
;; Genera un pequeño set de imágenes de prueba en formato PPM (P3)
;; sin depender de bibliotecas externas de imágenes.
;; Uso: racket generar_imagenes.rkt <carpeta-destino>

(require racket/string racket/format racket/file racket/path)

(define (escribir-ppm path ancho alto pixel-fn)
  (call-with-output-file path #:exists 'replace
    (λ (out)
      (fprintf out "P3\n~a ~a\n255\n" ancho alto)
      (for ([f (in-range alto)])
        (for ([c (in-range ancho)])
          (define-values (r g b) (pixel-fn f c))
          (fprintf out "~a ~a ~a " r g b))
        (fprintf out "\n")))))

(define (clamp v) (max 0 (min 255 (inexact->exact (round v)))))

;; 1) Degradado de color (diagonal)
(define (gradiente f c ancho alto)
  (values (clamp (* 255 (/ c ancho)))
          (clamp (* 255 (/ f alto)))
          128))

;; 2) Tablero de ajedrez (bordes duros, útil para ver el efecto del blur)
(define (checkerboard f c)
  (define tam 20)
  (cond [(even? (+ (quotient f tam) (quotient c tam)))
         (values 240 240 240)]
        [else (values 20 20 20)]))

;; 3) Barras de color (para probar grayscale/invert)
(define (colorbars f c ancho)
  (define franja (quotient (* c 6) ancho))
  (case franja
    [(0) (values 255 0 0)]
    [(1) (values 0 255 0)]
    [(2) (values 0 0 255)]
    [(3) (values 255 255 0)]
    [(4) (values 0 255 255)]
    [else (values 255 0 255)]))

;; 4) Ruido pseudoaleatorio (estresa el filtro gaussiano)
(define (ruido f c)
  (define seed (+ (* f 928371) (* c 12007) 17))
  (define v (modulo (* seed seed) 256))
  (values v (modulo (+ v 85) 256) (modulo (+ v 170) 256)))

(define (main)
  (define destino
    (cond [(> (vector-length (current-command-line-arguments)) 0)
           (vector-ref (current-command-line-arguments) 0)]
          [else "test_images"]))
  (make-directory* destino)

  (escribir-ppm (build-path destino "gradiente_64x64.ppm") 64 64
                (λ (f c) (gradiente f c 64 64)))

  (escribir-ppm (build-path destino "checkerboard_100x100.ppm") 100 100
                (λ (f c) (checkerboard f c)))

  (escribir-ppm (build-path destino "colorbars_120x60.ppm") 120 60
                (λ (f c) (colorbars f c 120)))

  (escribir-ppm (build-path destino "ruido_80x80.ppm") 80 80
                (λ (f c) (ruido f c)))

  ;; Imagen más grande, pensada para las mediciones de speedup/eficiencia
  (escribir-ppm (build-path destino "benchmark_400x300.ppm") 400 300
                (λ (f c) (gradiente f c 400 300)))

  (printf "Imágenes de prueba generadas en ~a~n" destino))

(module+ main (main))
