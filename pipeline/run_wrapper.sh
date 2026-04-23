#!/bin/bash
# ==============================================================================
# run_wrapper.sh — Wrapper para Condor (TLUSTY + Julia, grilla con Fe)
#
# Las variables TLUSTY, IRON, LINELIST, OPTABLES vienen del .bashrc del usuario
# y se propagan a Condor mediante 'getenv = True' en el submit file.
# Este wrapper las verifica, agrega ajustes de performance, y propaga
# correctamente el exit code de Julia a Condor.
# ==============================================================================

set -euo pipefail

# ==============================================================================
# 1. VERIFICAR VARIABLES DE ENTORNO (vienen de .bashrc via getenv=True)
# ==============================================================================
for var in TLUSTY IRON LINELIST; do
    if [ -z "${!var:-}" ]; then
        echo "ERROR: Variable de entorno '$var' no definida."
        echo "       Verificá que tu .bashrc la exporte y que el submit tenga 'getenv = True'."
        exit 1
    fi
done

# ==============================================================================
# 2. AJUSTES DE PERFORMANCE (siempre necesarios, no vienen del .bashrc)
# ==============================================================================
# TLUSTY es single-threaded. Sin esto, Julia/BLAS puede spawnear threads
# que compiten con otros jobs en el mismo nodo.
export OMP_NUM_THREADS=1
export JULIA_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1
export MKL_NUM_THREADS=1

# TLUSTY 208 necesita stack ilimitado: sus COMMON blocks pueden superar
# el límite de 8 MB por defecto, causando segfault silencioso en el nodo.
ulimit -s unlimited

# ==============================================================================
# 3. ÍNDICE DE FILA
# ==============================================================================
# Condor pasa $(Process) que arranca en 0, pero tlusty-input_01.dat
# arranca en fila 1.
PROCESS_ID=$1
ROW=$(( PROCESS_ID + 1 ))

# ==============================================================================
# 4. LOG DE INICIO
# ==============================================================================
echo "============================================================"
echo " TLUSTY Job — $(date)"
echo " Nodo        : $(hostname)"
echo " Proceso     : $PROCESS_ID  →  Fila de input: $ROW"
echo " Directorio  : $(pwd)"
echo " TLUSTY      : $TLUSTY"
echo " IRON        : $IRON"
echo " LINELIST    : $LINELIST"
echo " Julia       : $(/share/apps/sistema/julia-1.8/bin/julia --version)"
echo "============================================================"

# ==============================================================================
# 5. EJECUCIÓN DE JULIA
# ==============================================================================
/share/apps/sistema/julia-1.8/bin/julia run_model_fe.jl "$ROW"
EXIT_CODE=$?

# ==============================================================================
# 6. LOG DE CIERRE Y EXIT CODE
# ==============================================================================
echo "============================================================"
echo " Proceso $PROCESS_ID finalizado — $(date)"
echo " Exit code Julia: $EXIT_CODE"
echo "============================================================"

# Sin este exit, Condor siempre ve éxito aunque Julia haya fallado.
exit $EXIT_CODE