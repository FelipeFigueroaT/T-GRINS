using DelimitedFiles
using Printf
using JLD2

# ==============================================================================
# check_grid.jl — Check status of the main grid run
#
# Reads tlusty-input.dat and reports:
#   - Which models have a valid mod_sp.jld2
#   - Which models are missing (failed or not yet run)
#   - File size of each JLD2 (flags suspiciously small files)
#   - Number of wavelength points (flags files with 1 point = Fortran D bug)
#
# USAGE:
#   julia check_grid.jl
#   julia check_grid.jl --input tlusty-input.dat
# ==============================================================================

input_file = "--input" in ARGS ?
    ARGS[findfirst(==("--input"), ARGS) + 1] : "tlusty-input.dat"

if !isfile(input_file)
    println("Error: '$input_file' not found.")
    exit(1)
end

data   = readdlm(input_file)
models = [(Float64(data[i,1]), Float64(data[i,2])) for i in 1:size(data,1)]

dir_name(t, g) = "model_$(@sprintf("%.0f_%.0f", t, g * 100))"
jld2_path(t, g) = joinpath(dir_name(t, g), "mod_sp.jld2")

# Thresholds
MIN_SIZE_KB  = 100    # JLD2 smaller than this is suspicious
MIN_LAM_PTS  = 1000   # fewer wavelength points = likely Fortran D bug

ok       = Tuple{Float64,Float64}[]
bad_size = Tuple{Float64,Float64,Float64,Int}[]   # teff, logg, size_kb, n_pts
missing  = Tuple{Float64,Float64}[]

println("Checking $(length(models)) models from $input_file...\n")

for (t, g) in models
    path = jld2_path(t, g)
    if !isfile(path)
        push!(missing, (t, g))
        continue
    end

    size_kb = filesize(path) / 1024
    n_pts   = 0

    try
        d     = load(path)
        n_pts = haskey(d, "lam") ? length(d["lam"]) : 0
    catch e
        push!(bad_size, (t, g, size_kb, -1))   # -1 = unreadable
        continue
    end

    if size_kb < MIN_SIZE_KB || n_pts < MIN_LAM_PTS
        push!(bad_size, (t, g, size_kb, n_pts))
    else
        push!(ok, (t, g))
    end
end

# ==============================================================================
# REPORT
# ==============================================================================
println("="^60)
println(" GRID STATUS")
println("="^60)
println("  ✓ OK            : $(length(ok))")
println("  ✗ Missing       : $(length(missing))")
println("  ⚠ Suspicious   : $(length(bad_size))")
println("  Total           : $(length(models))")

if !isempty(bad_size)
    println()
    println("="^60)
    println(" SUSPICIOUS FILES (small size or few wavelength points)")
    println("="^60)
    println("  $(rpad("Model", 25)) $(rpad("Size [KB]", 12)) $(rpad("λ points", 10)) Issue")
    println("  " * "-"^58)
    for (t, g, sz, np) in sort(bad_size, by=x->x[1])
        d = dir_name(t, g)
        issue = np == -1 ? "UNREADABLE" :
                np < MIN_LAM_PTS ? "Fortran D bug ($(np) pts)" :
                "Small file"
        println("  $(rpad(d, 25)) $(rpad(@sprintf("%.1f", sz), 12)) $(rpad(string(np), 10)) $issue")
    end
end

if !isempty(missing)
    println()
    println("="^60)
    println(" MISSING MODELS ($(length(missing)))")
    println("="^60)
    for (t, g) in sort(missing, by=x->x[1])
        println("  $(dir_name(t, g))")
    end
end

# ==============================================================================
# WRITE LIST OF MODELS THAT NEED TO BE RERUN (missing + bad)
# ==============================================================================
needs_rerun = vcat([(t,g) for (t,g) in missing],
                   [(t,g) for (t,g,_,_) in bad_size])

if !isempty(needs_rerun)
    open("rerun-input.dat", "w") do f
        for (t, g) in sort(needs_rerun, by=x->x[1])
            @printf(f, "%.1f  %.2f\n", t, g)
        end
    end
    println()
    println("Written: rerun-input.dat ($(length(needs_rerun)) models to rerun)")
    println("  → Copy to tlusty-input.dat and resubmit, or use as retry input.")
end