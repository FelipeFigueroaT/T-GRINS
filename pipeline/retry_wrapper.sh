#!/bin/bash
# ==============================================================================
# retry_wrapper.sh — Condor wrapper for retry jobs
#
# Same as run_wrapper.sh but calls run_retry.jl instead of run_model_fe.jl
# ==============================================================================

set -euo pipefail

for var in TLUSTY IRON LINELIST; do
    if [ -z "${!var:-}" ]; then
        echo "ERROR: Environment variable '$var' not defined."
        exit 1
    fi
done

export OMP_NUM_THREADS=1
export JULIA_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1
export MKL_NUM_THREADS=1
ulimit -s unlimited

PROCESS_ID=$1
ROW=$(( PROCESS_ID + 1 ))

echo "============================================================"
echo " TLUSTY Retry Job — $(date)"
echo " Node       : $(hostname)"
echo " Process    : $PROCESS_ID  →  Row: $ROW"
echo " Directory  : $(pwd)"
echo " TLUSTY     : $TLUSTY"
echo " Neighbor   : $(sed -n "${ROW}p" retry-neighbors.dat)"
echo "============================================================"

julia run_retry.jl "$ROW"
EXIT_CODE=$?

echo "============================================================"
echo " Process $PROCESS_ID finished — $(date)"
echo " Exit code: $EXIT_CODE"
echo "============================================================"

exit $EXIT_CODE