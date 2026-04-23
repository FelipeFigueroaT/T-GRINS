#!/usr/bin/env python3
"""
plot_sed.py — Plot SED from a T-GRINS JLD2 file

Usage:
    python plot_sed.py model_35000_400/mod_sp.jld2
    python plot_sed.py model_35000_400/mod_sp.jld2 --save

Options:
    --save   Save plot as PNG instead of displaying interactively

Dependencies:
    pip install h5py numpy matplotlib
"""

import sys
import os
import numpy as np
import matplotlib.pyplot as plt
import matplotlib.ticker as ticker
import h5py

if len(sys.argv) < 2:
    print("Usage: python plot_sed.py <path/to/mod_sp.jld2> [--save]")
    sys.exit(1)

jld2_file = sys.argv[1]
save_plot = "--save" in sys.argv

if not os.path.isfile(jld2_file):
    print(f"Error: File not found: {jld2_file}")
    sys.exit(1)

# --- Load JLD2 ---
with h5py.File(jld2_file, "r") as f:
    lam       = f["lam"][:]
    hlam_spec = f["hlam_spec"][:]
    hlam_cont = f["hlam_cont"][:]
    teff      = float(f["teff"][()])
    logg      = float(f["logg"][()])
    Z         = float(f["Z"][()]) if "Z" in f else 1.0
    star_type = f["star_type"][()].decode() if "star_type" in f else ""

# --- Filter positive values ---
ms = hlam_spec > 0
mc = hlam_cont > 0

# --- Title ---
title = f"Teff = {int(teff)} K   log g = {logg:.2f}"
if Z != 1.0:
    title += f"   Z = {Z:.2f}×solar"

# --- Plot ---
fig, ax = plt.subplots(figsize=(12, 5))

ax.plot(np.log10(lam[ms]), np.log10(hlam_spec[ms]),
        color="steelblue", lw=0.4, alpha=0.9, label="Spectrum")
ax.plot(np.log10(lam[mc]), np.log10(hlam_cont[mc]),
        color="tomato", lw=1.2, ls="--", alpha=0.85, label="Continuum")

# Reference lines
refs = [(912, "Ly limit"), (1216, r"Ly$\alpha$"), (4861, r"H$\beta$"), (6563, r"H$\alpha$")]
ymin, ymax = ax.get_ylim()
for lam_ref, name in refs:
    if lam[ms].min() < lam_ref < lam[ms].max():
        ax.axvline(np.log10(lam_ref), color="gray", lw=0.6, ls=":")
        ax.text(np.log10(lam_ref), ymax - 0.05*(ymax-ymin),
                name, ha="center", va="top", fontsize=8, color="gray")

ax.set_xlabel(r"$\log\,\lambda\;[\AA]$", fontsize=13)
ax.set_ylabel(r"$\log\,H_\lambda\;[\mathrm{erg\,cm^{-2}\,s^{-1}\,\AA^{-1}}]$", fontsize=13)
ax.set_title(title, fontsize=13)
ax.legend(fontsize=11)
ax.grid(True, alpha=0.2)
plt.tight_layout()

if save_plot:
    out = jld2_file.replace(".jld2", "_sed.png")
    plt.savefig(out, dpi=150, bbox_inches="tight")
    print(f"Saved: {out}")
else:
    plt.show()