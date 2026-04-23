# T-GRINS — TLUSTY Grid Interface for NLTE Synthesis

[![Julia](https://img.shields.io/badge/Julia-≥1.9-9558B2?logo=julia)](https://julialang.org/)
[![Python](https://img.shields.io/badge/Python-≥3.8-3776AB?logo=python&logoColor=white)](https://www.python.org/)
[![TLUSTY](https://img.shields.io/badge/TLUSTY-208-blue)](http://tlusty.oca.eu/)
[![SYNSPEC](https://img.shields.io/badge/SYNSPEC-54-blue)](http://tlusty.oca.eu/)

T-GRINS is a pipeline for computing NLTE model atmosphere grids of OB stars using [TLUSTY 208](http://tlusty.oca.eu/) and SYNSPEC 54, with HTCondor for parallel execution.

The pipeline produces one JLD2 file per model containing the full SED (spectrum + continuum) from the UV to the near-IR.

---

## Repository structure

```
T-GRINS/
├── README.md
├── Project.toml          — Julia dependencies
├── config.toml           — Template for single-model mode
│
├── pipeline/
│   ├── run_model_fe.jl   — Main pipeline (grid or single mode)
│   ├── run_wrapper.sh    — HTCondor wrapper
│   ├── tlusty_grid.sub   — HTCondor submit file
│   ├── run_retry.jl      — Retry pipeline for difficult models
│   ├── retry_wrapper.sh  — HTCondor wrapper for retry
│   └── retry_grid.sub    — HTCondor submit file for retry
│
├── tools/
│   ├── setup_grid.sh     — Create a ready-to-run grid directory
│   ├── make_retry_list.jl — Generate retry input from failed models
│   ├── check_grid.jl     — Report grid status (converged/missing)
│   ├── check_retry.jl    — Report retry status
│   ├── collect_jld2.jl   — Collect JLD2 files into a single directory
│   └── make_jld2.jl      — Regenerate JLD2 from existing ASCII output
│
├── plot/
│   ├── plot_sed.jl       — Plot SED from JLD2 (Julia)
│   └── plot_sed.py       — Plot SED from JLD2 (Python)
│
└── examples/
    ├── tlusty-input_example.dat — Sample input file
    └── read_jld2.py      — How to read JLD2 files in Python
```

---

## Requirements

### TLUSTY and SYNSPEC
Download TLUSTY 208 + SYNSPEC 54 from http://tlusty.oca.eu/ and set the following environment variables:

```bash
export TLUSTY=/path/to/tl208-s54
export LINELIST=/path/to/linelist      # directory with gfATO.dat or gfATO.bin
export IRON=/path/to/irondata          # Kurucz iron superline data
export OPTABLES=/path/to/optables
```

### Julia packages
```bash
julia -e 'using Pkg; Pkg.add(["JLD2", "CodecZlib", "TOML"])'
# Optional for plotting:
julia -e 'using Pkg; Pkg.add("Plots")'
```
Or install everything from `Project.toml`:
```bash
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

### Python (optional, for reading JLD2 and plotting)
```bash
pip install h5py numpy matplotlib
```

---

## Quick start

### Setting up a new grid

```bash
# Create a working directory with all scripts copied and configured
bash tools/setup_grid.sh Grid_SiFe_GAL

cd Grid_SiFe_GAL

# Copy your input file (one model per line: Teff logg [Z])
cp /path/to/tlusty-input.dat .

# Set queue count to number of models
wc -l tlusty-input.dat
# Edit tlusty_grid.sub: queue N

condor_submit tlusty_grid.sub
```

### Running a single model

```bash
# Grid mode — row 3 of tlusty-input.dat
julia pipeline/run_model_fe.jl -g tlusty-input.dat -l 3

# Config mode — all parameters in a TOML file
julia pipeline/run_model_fe.jl -c config.toml

# Quick mode — specify Teff and logg directly
julia pipeline/run_model_fe.jl -t 35000 -G 4.0
```

### Monitoring and collecting results

```bash
# Check grid status
julia tools/check_grid.jl

# Collect all JLD2 files into JLD2/ directory
julia tools/collect_jld2.jl

# Plot a model
julia plot/plot_sed.jl model_35000_400/mod_sp.jld2
python plot/plot_sed.py model_35000_400/mod_sp.jld2
```

---

## Input file format

Plain text, one model per line. The third column (metallicity Z) is optional — if absent, the value of `Z_SOLAR` defined at the top of `run_model_fe.jl` is used.

```
# Teff [K]   logg [cgs]   Z [optional, relative to solar]
35000.0      4.0
35000.0      4.0          0.5
50000.0      4.3          1.0
```

---

## Physics

### NLTE pipeline (4 steps)

| Step | Model | Description |
|------|-------|-------------|
| 1 | `mod_lt` | LTE gray atmosphere — starting point |
| 2 | `mod_nc` | NLTE continuum, H He C N O only |
| 3 | `mod_nc_fe` | NLTE continuum + Si S Fe in LTE superlevel mode — absorbs Fe blanketing into T(τ) before full NLTE solve |
| 4 | `mod_nl` | NLTE full lines — final converged atmosphere |

### Elements included

| Treatment | Elements |
|-----------|----------|
| Explicit NLTE | H, He, C, N, O, Si, S, Fe |
| EOS implicit (LTE) | Ne, Na, Mg, Al, P, Cl, Ar, K, Ca |
| Ignored | Li, Be, B, F, Sc, Ti, V, Cr, Mn |

Fe ion stages included:
- **B-stars** (Teff < 30000 K): Fe I–III + bare Fe IV
- **O-stars** (Teff ≥ 30000 K): Fe I–VI + bare Fe VII

Fe superlines use Kurucz iron data (`gf260x.lin/gam`) via `ISPODF=1`.

### Wavelength coverage

SYNSPEC runs in two segments for O-stars to avoid internal array overflow from the dense far-UV line list:

| Stellar type | Segment | Range | relop |
|---|---|---|---|
| O-star | 1 | 50–900 Å | 1×10⁻² |
| O-star | 2 | 900–50000 Å | 1×10⁻⁴ |
| B-star | 1 | 500–50000 Å | 1×10⁻⁴ |

Custom segments can be defined in `config.toml` for single-model mode.

### Metallicity scaling

`Z_SOLAR` at the top of `run_model_fe.jl` scales all metals (Z > 2) relative to [Asplund et al. (2009)](https://doi.org/10.1146/annurev.astro.46.060407.145222) solar abundances. H and He are not scaled.

| Z | Environment |
|---|---|
| 1.0 | Solar / Milky Way |
| 0.5 | LMC |
| 0.2 | SMC |

---

## Output format

Each converged model produces a JLD2 file (`mod_sp.jld2`) containing:

| Key | Type | Units | Description |
|-----|------|-------|-------------|
| `lam` | Float32 | Å | Wavelength grid (uniform step) |
| `hlam_spec` | Float32 | erg/cm²/s/Å | Eddington flux H_λ with spectral lines |
| `hlam_cont` | Float32 | erg/cm²/s/Å | Eddington flux H_λ continuum only |
| `teff` | Float32 | K | Effective temperature |
| `logg` | Float32 | cgs | Log surface gravity |
| `Z` | Float32 | — | Metallicity relative to solar |
| `vtb` | Float32 | km/s | Microturbulent velocity |
| `star_type` | String | — | `"O-Star"` or `"B-Star"` |
| `step_ang` | Float32 | Å | Wavelength step of the output grid |

To convert to physical flux: **F_λ = 4π H_λ**

Reading in Python:
```python
import h5py
import numpy as np

with h5py.File("mod_sp.jld2", "r") as f:
    lam       = f["lam"][:]
    hlam_spec = f["hlam_spec"][:]
    teff      = float(f["teff"][()])
    logg      = float(f["logg"][()])
    Z         = float(f["Z"][()])
```

Reading in Julia:
```julia
using JLD2
d = load("mod_sp.jld2")
lam, hlam_spec = d["lam"], d["hlam_spec"]
```

---

## Retry strategy for difficult models

Models near the Eddington limit (Γ ≳ 0.5) often fail to converge from a gray LTE starting point. T-GRINS includes a retry pipeline that uses a converged neighbor model as the starting point:

```bash
julia tools/make_retry_list.jl      # generates retry-input.dat and retry-neighbors.dat
condor_submit pipeline/retry_grid.sub
julia tools/check_retry.jl          # check results
```

The neighbor is selected as the closest converged model in Teff-logg space, with a penalty for neighbors with lower logg (less stable).

---

## References

- Hubeny, I. & Lanz, T. (2017a, b, c): TLUSTY Papers I, II, III — [arXiv:1706.01859](https://arxiv.org/abs/1706.01859)
- Hubeny, I., Allende Prieto, C., Osorio, Y. & Lanz, T. (2021): TLUSTY Paper IV (v208/54) — [arXiv:2104.02829](https://arxiv.org/abs/2104.02829)
- Lanz, T. & Hubeny, I. (2003): OSTAR2002 grid — [ApJS 146, 417](https://doi.org/10.1086/374373)
- Lanz, T. & Hubeny, I. (2007): BSTAR2006 grid — [ApJS 169, 83](https://doi.org/10.1086/511270)
- Asplund, M., Grevesse, N., Sauval, A.J. & Scott, P. (2009): Solar abundances — [ARA&A 47, 481](https://doi.org/10.1146/annurev.astro.46.060407.145222)
