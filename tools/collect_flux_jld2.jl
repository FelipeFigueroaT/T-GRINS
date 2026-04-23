using JLD2
using Printf

# ==============================================================================
# collect_jld2.jl — Collect JLD2 SEDs from model directories
#
# Scans all model_TEFF_LOGG directories in the current folder and copies
# the mod_sp.jld2 file from each into a single output directory.
# Models that failed (no JLD2) are reported but not fatal.
#
# Output directory structure:
#   JLD2/
#     T25000LG4p30.jld2
#     T30000LG4p00.jld2
#     ...
#
# Each JLD2 contains:
#   lam       — uniform wavelength grid [Å]              Float32
#   hlam_spec — Eddington flux H_λ with lines            Float32
#   hlam_cont — Eddington flux H_λ continuum only        Float32
#   teff      — effective temperature [K]                Float32
#   logg      — log surface gravity [cgs]                Float32
#   vtb       — microturbulent velocity [km/s]           Float32
#   star_type — "O-Star" or "B-Star"                     String
#   step_ang  — wavelength step of the output grid [Å]   Float32
#
# To read a file:
#   using JLD2
#   d = load("JLD2/T25000LG4p30.jld2")
#   lam, hlam_spec, hlam_cont = d["lam"], d["hlam_spec"], d["hlam_cont"]
#
# Usage:
#   julia collect_jld2.jl
#   julia collect_jld2.jl /path/to/grid/directory
# ==============================================================================

# --- CONFIGURATION ---
output_dir      = "JLD2"
source_filename = "mod_sp.jld2"

# Optional: run from a different directory passed as argument
if length(ARGS) >= 1
    grid_dir = ARGS[1]
    if !isdir(grid_dir)
        println("Error: Directory '$grid_dir' not found.")
        exit(1)
    end
    cd(grid_dir)
end

# Create output directory
if !isdir(output_dir)
    mkdir(output_dir)
    println("Created output directory: $output_dir")
else
    println("Using existing directory: $output_dir")
end

# --- COLLECTION ---
all_dirs = sort(filter(d -> isdir(d) && startswith(d, "model_"), readdir()))
println("Found $(length(all_dirs)) model directories.\n")

count_ok   = 0
count_fail = 0

for dir in all_dirs
    # Parse directory name: model_TEFF_LOGGx100
    parts = split(dir, "_")
    if length(parts) != 3
        println("  SKIP: '$dir' — unexpected name format")
        continue
    end

    teff_str  = parts[2]
    logg_code = parts[3]

    logg_val       = parse(Float64, logg_code) / 100.0
    logg_formatted = replace(@sprintf("%.2f", logg_val), "." => "p")
    new_filename   = "T$(teff_str)LG$(logg_formatted).jld2"

    source_path = joinpath(dir, source_filename)
    dest_path   = joinpath(output_dir, new_filename)

    if isfile(source_path)
        cp(source_path, dest_path, force=true)
        println("  OK: $dir/$source_filename → $output_dir/$new_filename")
        global count_ok += 1
    else
        println("  MISSING: $dir (model failed or not yet computed)")
        global count_fail += 1
    end
end

println("\n--- DONE ---")
println("  Collected : $count_ok")
println("  Missing   : $count_fail")
println("  Total     : $(count_ok + count_fail)")
println("  Output    : $(abspath(output_dir))/")