#!/bin/bash
# -----------------------------------------------------------------------
# benchmark.sh
# Corre image_processor con p = 1, 2, 4, 8 procesos sobre la misma
# imagen y filtro, mide el tiempo de ejecución Tp y calcula el
# Speedup (Sp = T1/Tp) y la Eficiencia (Ep = Sp/p).
#
# Uso:
#   ./scripts/benchmark.sh [imagen.ppm] [filtro] [lista_de_p]
#   ej: ./scripts/benchmark.sh test_images/benchmark_400x300.ppm gaussian "1 2 4 8"
#
# Debe ejecutarse desde la raíz del proyecto.
# -----------------------------------------------------------------------

set -e

IMG="${1:-test_images/benchmark_400x300.ppm}"
FILTRO="${2:-gaussian}"
LISTA_P="${3:-1 2 4 8}"

mkdir -p resultados

# Compilar Erlang
erlc -o erlang erlang/ppm.erl erlang/image_processor.erl >/dev/null

CSV="resultados/tiempos.csv"
echo "p,tiempo_ms" > "$CSV"

echo "== Benchmark: imagen=$IMG filtro=$FILTRO =="
echo ""

for P in $LISTA_P; do

    echo "======================================"
    echo " Ejecutando con p=$P"
    echo "======================================"

    OUT="resultados/salida_p${P}.ppm"

    SALIDA=$(erl -noshell -pa erlang -eval \
        "image_processor:main([\"$IMG\",\"$OUT\",\"$P\",\"$FILTRO\"]), halt()." \
        2>&1)

    echo "$SALIDA"

    # Extraer Tp de:
    # Listo resultados/salida_p1.ppm (400x300) Tp=1535 ms
    T=$(echo "$SALIDA" | \
        grep -oE 'Tp=[0-9]+ ms' | \
        grep -oE '[0-9]+' | \
        tail -1)

    if [ -z "$T" ]; then
        echo "(!) No se pudo medir el tiempo para p=$P"
        continue
    fi

    echo "$P,$T" >> "$CSV"

    echo ""
    echo "Finalizado p=$P: ${T} ms"
    echo ""

done

echo "======================================"
echo " RESULTADOS"
echo "======================================"

printf "%-6s %-12s %-10s %-10s\n" \
    "p" "Tp(ms)" "Sp" "Ep"

awk -F, '
NR==1 {next}
NR==2 {T1=$2}
{
    Sp = T1/$2
    Ep = Sp/$1

    printf "%-6s %-12s %-10.2f %-10.2f\n", \
           $1, $2, Sp, Ep
}
' "$CSV"

echo ""
echo "CSV guardado en: $CSV"
