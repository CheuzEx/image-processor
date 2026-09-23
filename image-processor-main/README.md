# Requisitos
- Erlang/OTP (probado con OTP 25/26).
- Racket (probado con 8.10).
- En Ubuntu/Debian: `sudo apt-get install erlang racket`

# Compilar
chmod +x image_processor
chmod +x benchmark.sh
erlc -o erlang erlang/ppm.erl erlang/image_processor.erl

# Ejecutar
./image_processor test_images/ruido_80x80.ppm salida1.ppm 1

./image_processor entrada.ppm salida.ppm N [filtro] [ksize] [borde]

filtro:
    * gaussian
    * sharpen
    * grayscale
    * invert
    * threshold
    * brightness

ksize
    * Solo aplcia a gaussian entero impar > 3

borde
    * extender
    * ceros


# Ejemplos

./image_processor test_images/benchmark_400x300.ppm salida.ppm 4
./image_processor test_images/benchmark_400x300.ppm salida.ppm 4 gaussian 5
./image_processor test_images/benchmark_400x300.ppm salida.ppm 4 gaussian 3 ceros
./image_processor test_images/colorbars_120x60.ppm salida.ppm 1 invert

# Benchmark

./benchmark.sh entrada.ppm [filtro] "N1 N2 ... Nk"

./benchmark.sh test_images/benchmark_400x300.ppm threshold "1 2 4 8"
