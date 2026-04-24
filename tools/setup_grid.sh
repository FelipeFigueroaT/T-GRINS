#!/bin/bash
# ==============================================================================
# setup_grid.sh — Create a ready-to-run T-GRINS grid directory
#
# Copies all necessary scripts from the T-GRINS repository into a new
# working directory and configures Condor submit files automatically.
#
# Usage:
#   bash tools/setup_grid.sh <grid_name>
#   bash tools/setup_grid.sh Grid_SiFe_LMC
#
# Must be run from the T-GRINS repository root.
# ==============================================================================

set -euo pipefail

if [ $# -lt 1 ]; then
    echo "Usage: bash tools/setup_grid.sh <grid_name>"
    echo "  Example: bash tools/setup_grid.sh Grid_SiFe_LMC"
    exit 1
fi

GRID_NAME="$1"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"   # T-GRINS root
TARGET_DIR="$(pwd)/$GRID_NAME"

echo "============================================================"
echo " T-GRINS Grid Setup"
echo " Repository : $REPO_DIR"
echo " Grid name  : $GRID_NAME"
echo " Target dir : $TARGET_DIR"
echo "============================================================"

# --- Required files (relative to repo root) ---
REQUIRED=(
    "pipeline/run_model.jl"
    "pipeline/run_wrapper.sh"
    "pipeline/run_grid.submit"
    "pipeline/run_retry.jl"
    "pipeline/retry_wrapper.sh"
    "pipeline/retry_grid.submit"
    "tools/make_retry_list.jl"
    "tools/check_grid.jl"
    "tools/check_retry.jl"
    "tools/collect_flux_jld2.jl"
    "config.toml"
)

echo ""
echo "Checking required files..."
for f in "${REQUIRED[@]}"; do
    if [ ! -f "$REPO_DIR/$f" ]; then
        echo "  ERROR: '$f' not found in $REPO_DIR"
        exit 1
    fi
    echo "  ✓ $f"
done

# --- Create or confirm overwrite ---
if [ -d "$TARGET_DIR" ]; then
    echo ""
    echo "WARNING: '$TARGET_DIR' already exists."
    read -r -p "  Overwrite existing files? [y/N] " confirm
    [[ ! "$confirm" =~ ^[Yy]$ ]] && echo "Aborted." && exit 0
else
    mkdir -p "$TARGET_DIR"
    echo ""
    echo "Created: $TARGET_DIR"
fi

# --- Condor log directories ---
mkdir -p "$TARGET_DIR/Out"
mkdir -p "$TARGET_DIR/Error"
echo "Created: Out/ and Error/"

# --- Copy scripts (all flat into target dir) ---
echo ""
echo "Copying scripts..."
for f in "${REQUIRED[@]}"; do
    fname=$(basename "$f")
    cp "$REPO_DIR/$f" "$TARGET_DIR/$fname"
    echo "  ✓ $fname"
done

# --- Permissions ---
chmod +x "$TARGET_DIR/run_wrapper.sh"
chmod +x "$TARGET_DIR/retry_wrapper.sh"

# --- Update Initialdir in Condor submit files ---
sed -i "s|^Initialdir.*|Initialdir = $TARGET_DIR|" "$TARGET_DIR/run_grid.submit"
sed -i "s|^Initialdir.*|Initialdir = $TARGET_DIR|" "$TARGET_DIR/retry_grid.submit"
echo ""
echo "Updated Initialdir in run_grid.submit and retry_grid.submit"

# --- Instructions ---
echo ""
echo "============================================================"
echo " Setup complete. Next steps:"
echo ""
echo "  1. Edit Z_SOLAR in run_model_fe.jl if needed:"
echo "     Z=1.0 (solar), Z=0.5 (LMC), Z=0.2 (SMC)"
echo ""
echo "  2. Copy your input file:"
echo "     cp tlusty-input.dat $TARGET_DIR/"
echo ""
echo "  3. Set queue count in run_grid.submit:"
echo "     wc -l $TARGET_DIR/tlusty-input.dat"
echo ""
echo "  4. Submit:"
echo "     cd $TARGET_DIR && condor_submit run_grid.submit"
echo ""
echo "  5. After completion:"
echo "     julia check_grid.jl"
echo "     julia collect_jld2.jl"
echo "============================================================"
