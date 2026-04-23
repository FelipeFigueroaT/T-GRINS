#!/usr/bin/env python3
"""
read_jld2.py — Read and inspect a T-GRINS JLD2 output file

T-GRINS saves SYNSPEC SEDs in JLD2 format (HDF5-based).
This script shows how to read them using h5py.

Usage:
    python read_jld2.py model_35000_400/mod_sp.jld2

Dependencies:
    pip install h5py numpy matplotlib
"""

import sys
import numpy as np
import h5py

# ==============================================================================
# READING A JLD2 FILE
# JLD2 files are standard HDF5 — use h5py directly.
# ==============================================================================

def read_jld2(filepath):
    """
    Read a T-GRINS JLD2 SED file.

    Returns
    -------
    dict with keys:
        lam       : wavelength grid [Å]
        hlam_spec : Eddington flux with lines H_λ [erg/cm²/s/Å]
        hlam_cont : Eddington flux continuum only H_λ [erg/cm²/s/Å]
        teff      : effective temperature [K]
        logg      : log surface gravity [cgs]
        Z         : metallicity relative to solar
        vtb       : microturbulent velocity [km/s]
        star_type : 'O-Star' or 'B-Star'
        step_ang  : wavelength step of the output grid [Å]

    Notes
    -----
    All flux arrays are stored as Float32.
    To get physical flux: F_λ = 4π H_λ
    """
    with h5py.File(filepath, "r") as f:
        data = {
            "lam"       : f["lam"][:].astype(np.float64),
            "hlam_spec" : f["hlam_spec"][:].astype(np.float64),
            "hlam_cont" : f["hlam_cont"][:].astype(np.float64),
            "teff"      : float(f["teff"][()]),
            "logg"      : float(f["logg"][()]),
            "Z"         : float(f["Z"][()]) if "Z" in f else 1.0,
            "vtb"       : float(f["vtb"][()]) if "vtb" in f else 0.0,
            "star_type" : f["star_type"][()].decode() if "star_type" in f else "",
            "step_ang"  : float(f["step_ang"][()]) if "step_ang" in f else 0.5,
        }
    return data


# ==============================================================================
# EXAMPLE USAGE
# ==============================================================================
if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python read_jld2.py <path/to/mod_sp.jld2>")
        sys.exit(1)

    filepath = sys.argv[1]
    sed = read_jld2(filepath)

    # Print summary
    print(f"Model    : Teff={int(sed['teff'])} K  logg={sed['logg']:.2f}  Z={sed['Z']:.2f}×solar")
    print(f"Type     : {sed['star_type']}  VTB={sed['vtb']:.1f} km/s")
    print(f"Wavelength: {sed['lam'][0]:.1f} – {sed['lam'][-1]:.1f} Å  ({len(sed['lam'])} pts, step={sed['step_ang']:.1f} Å)")
    print(f"Peak H_λ  : {sed['hlam_spec'].max():.3e} erg/cm²/s/Å  at {sed['lam'][sed['hlam_spec'].argmax()]:.1f} Å")

    # Quick plot (optional)
    try:
        import matplotlib.pyplot as plt
        lam  = sed["lam"]
        ms   = sed["hlam_spec"] > 0
        mc   = sed["hlam_cont"] > 0

        fig, ax = plt.subplots(figsize=(11, 4))
        ax.plot(np.log10(lam[ms]), np.log10(sed["hlam_spec"][ms]),
                color="steelblue", lw=0.4, label="Spectrum")
        ax.plot(np.log10(lam[mc]), np.log10(sed["hlam_cont"][mc]),
                color="tomato", lw=1.0, ls="--", label="Continuum")
        ax.set_xlabel("log λ [Å]")
        ax.set_ylabel("log H_λ [erg/cm²/s/Å]")
        ax.set_title(f"Teff={int(sed['teff'])} K  logg={sed['logg']:.2f}  Z={sed['Z']:.2f}×solar")
        ax.legend()
        ax.grid(True, alpha=0.2)
        plt.tight_layout()
        plt.show()
    except ImportError:
        print("(matplotlib not available — skipping plot)")