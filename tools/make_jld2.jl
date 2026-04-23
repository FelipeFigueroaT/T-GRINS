using DelimitedFiles
using Printf
using JLD2

# ==============================================================================
# make_jld2.jl — Create JLD2 files from existing SYNSPEC output
#
# Goes through all model_* directories and creates mod_sp.jld2 from
# mod_sp.spec and mod_sp.cont if they exist and are complete (>10000 pts).
#
# Does NOT run TLUSTY or SYNSPEC — only processes existing output files.
#
# USAGE:
#   julia make_jld2.jl
# ==============================================================================

all_dirs = sort(filter(d -> isdir(d) && startswith(d, "model_"), readdir()))
println("Found $(length(all_dirs)) model directories.\n")

count_ok   = 0
count_skip = 0
count_fail = 0

function read_synspec(filename)
    lam  = Float64[]
    flux = Float64[]
    open(filename, "r") do f
        for line in eachline(f)
            cols = split(line)
            length(cols) >= 2 || continue
            l = replace(cols[1], r"([0-9])[Dd]([+-][0-9])" => s"\1e\2")
            h = replace(cols[2], r"([0-9])[Dd]([+-][0-9])" => s"\1e\2")
            lv = tryparse(Float64, l)
            hv = tryparse(Float64, h)
            (lv === nothing || hv === nothing) && continue
            push!(lam,  lv)
            push!(flux, hv)
        end
    end
    return lam, flux
end

for dir in all_dirs
    parts = split(dir, "_")
    length(parts) == 3 || continue

    teff = tryparse(Float64, parts[2])
    logg = tryparse(Float64, parts[3])
    (teff === nothing || logg === nothing) && continue
    logg = logg / 100.0

    spec_file = joinpath(dir, "mod_sp.spec")
    cont_file = joinpath(dir, "mod_sp.cont")
    jld2_file = joinpath(dir, "mod_sp.jld2")

    # Skip if already has valid JLD2
    if isfile(jld2_file)
        try
            d = load(jld2_file)
            n = haskey(d, "lam") ? length(d["lam"]) : 0
            if n > 10000
                println("SKIP: $dir (already has valid JLD2, $n pts)")
                global count_skip += 1
                continue
            end
        catch; end
    end

    # Skip if no spec/cont
    if !isfile(spec_file) || !isfile(cont_file)
        println("SKIP: $dir (no mod_sp.spec or mod_sp.cont)")
        global count_skip += 1
        continue
    end

    # Read
    lam_s, hlam_s = read_synspec(spec_file)
    lam_c, hlam_c = read_synspec(cont_file)

    if length(lam_s) < 10000
        println("FAIL: $dir — only $(length(lam_s)) points in spec (SYNSPEC incomplete)")
        global count_fail += 1
        continue
    end

    # Interpolate onto uniform grid
    is_ostar  = teff >= 30000.0
    vtb_val   = is_ostar ? 10.0 : 2.0
    star_type = is_ostar ? "O-Star" : "B-Star"

    step_out = 0.5
    lam_grid = collect(lam_s[1]:step_out:lam_s[end])

    interp(lam, hlam, λ) = let idx = searchsortedfirst(lam, λ)
        idx == 1 ? hlam[1] : idx > length(lam) ? hlam[end] :
        hlam[idx-1] + (hlam[idx]-hlam[idx-1])*(λ-lam[idx-1])/(lam[idx]-lam[idx-1])
    end

    hs_out = Float32.([interp(lam_s, hlam_s, λ) for λ in lam_grid])
    hc_out = Float32.([interp(lam_c, hlam_c, λ) for λ in lam_grid])

    jldsave(jld2_file; compress=true,
        lam       = Float32.(lam_grid),
        hlam_spec = hs_out,
        hlam_cont = hc_out,
        teff      = Float32(teff),
        logg      = Float32(logg),
        vtb       = Float32(vtb_val),
        star_type = star_type,
        step_ang  = Float32(step_out)
    )

    println("OK:   $dir — $(length(lam_grid)) pts → mod_sp.jld2")
    global count_ok += 1
end

println()
println("="^50)
println("  Created : $count_ok")
println("  Skipped : $count_skip")
println("  Failed  : $count_fail")
println("="^50)
