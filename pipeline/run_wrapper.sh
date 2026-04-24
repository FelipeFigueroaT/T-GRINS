#!/bin/bash
# ==============================================================================
# run_wrapper.sh — HTCondor wrapper for T-GRINS (TLUSTY + SYNSPEC grid)
#
# Environment variables TLUSTY, IRON, LINELIST, and OPTABLES must be defined
# in the user's .bashrc and propagated to Condor via 'getenv = True' in the
# submit file.
# ==============================================================================
set -euo pipefail

# ==============================================================================
# 1. CHECK ENVIRONMENT VARIABLES
# ==============================================================================
for var in TLUSTY IRON LINELIST; do
    if [ -z "${!var:-}" ]; then
        echo "ERROR: Environment variable '$var' is not defined."
        echo "       Make sure your .bashrc exports it and the submit file has 'getenv = True'."
        exit 1
    fi
done

# ==============================================================================
# 2. PERFORMANCE SETTINGS
# ==============================================================================
# TLUSTY is single-threaded. Without these settings, Julia/BLAS may spawn
# threads that compete with other jobs running on the same node.
export OMP_NUM_THREADS=1
export JULIA_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1
export MKL_NUM_THREADS=1

# TLUSTY 208 requires an unlimited stack: its COMMON blocks can exceed
# the default 8 MB limit, causing a silent segfault on the worker node.
ulimit -s unlimited

# ==============================================================================
# 3. ROW INDEX
# ==============================================================================
# Condor passes $(Process) starting at 0, but tlusty-input.dat starts at row 1.
PROCESS_ID=$1
ROW=$(( PROCESS_ID + 1 ))

# ==============================================================================
# 4. START LOG
# ==============================================================================
echo "============================================================"
echo " TLUSTY Job — $(date)"
echo " Node        : $(hostname)"
echo " Process     : $PROCESS_ID  ->  Input row: $ROW"
echo " Directory   : $(pwd)"
echo " TLUSTY      : $TLUSTY"
echo " IRON        : $IRON"
echo " LINELIST    : $LINELIST"
echo " Julia       : $(julia --version)"
echo "============================================================"

# ==============================================================================
# 5. RUN JULIA
# ==============================================================================
julia run_model_fe.jl -g tlusty-input.dat -l "$ROW"
EXIT_CODE=$?

# ==============================================================================
# 6. END LOG AND EXIT CODE
# ==============================================================================
echo "============================================================"
echo " Process $PROCESS_ID finished — $(date)"
echo " Julia exit code: $EXIT_CODE"
echo "============================================================"

# Without this, Condor always sees success even if Julia failed.
exit $EXIT_CODE
