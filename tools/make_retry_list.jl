using DelimitedFiles
using Printf

# ==============================================================================
# make_retry_list.jl — Generate retry input files for failed models
#
# Scans all model_TEFF_LOGG directories, identifies those without mod_sp.jld2,
# finds the nearest converged neighbor for each, and writes two files:
#
#   retry-input.dat     — Teff logg for each failed model (1 per line)
#   retry-neighbors.dat — Teff logg of the best neighbor  (1 per line, same order)
#
# After running this script:
#   1. Check the plan printed to screen
#   2. Update 'queue N' in retry_grid.sub (N = number of lines in retry-input.dat)
#   3. condor_submit retry_grid.sub
#
# USAGE:
#   julia make_retry_list.jl
#   julia make_retry_list.jl --input tlusty-input.dat
# ==============================================================================

input_file = "--input" in ARGS ?
    ARGS[findfirst(==("--input"), ARGS) + 1] : "tlusty-input.dat"

if !isfile(input_file)
    println("Error: '$input_file' not found.")
    exit(1)
end

data       = readdlm(input_file)
all_models = [(Float64(data[i,1]), Float64(data[i,2])) for i in 1:size(data,1)]

dir_name(t, g) = "model_$(@sprintf("%.0f_%.0f", t, g * 100))"
is_converged(t, g) = isfile(joinpath(dir_name(t,g), "mod_sp.jld2"))

failed    = [(t,g) for (t,g) in all_models if !is_converged(t,g)]
converged = [(t,g) for (t,g) in all_models if  is_converged(t,g)]

println("Total    : $(length(all_models))")
println("Converged: $(length(converged))")
println("Failed   : $(length(failed))")

if isempty(failed)
    println("No failed models. Nothing to do.")
    exit(0)
end

if isempty(converged)
    println("No converged neighbors available.")
    exit(1)
end

# Neighbor distance: prefer same Teff + higher logg (ideal starting point)
# - Penalize lower logg heavily (less stable)
# - Use small Teff penalty as tiebreaker when logg distance is equal
function neighbor_dist(t1, g1, t2, g2)
    dt = abs(t1 - t2) / 500.0
    dg = abs(g1 - g2) / 0.1
    penalty_logg = g2 < g1 ? 10.0 * (g1 - g2) / 0.1 : 0.0
    tiebreak_teff = dt * 0.1   # small tiebreaker: prefer same Teff when logg dist is equal
    return sqrt(dt^2 + dg^2) + penalty_logg + tiebreak_teff
end

function find_neighbor(teff, logg)
    best_dist = Inf
    best = nothing
    is_ostar = teff >= 30000.0
    for (t, g) in converged
        # Must be same stellar type — fort.7 format differs between B and O stars
        # (O-stars have Fe I-VI, B-stars have Fe I-III)
        nb_is_ostar = t >= 30000.0
        nb_is_ostar != is_ostar && continue
        d = neighbor_dist(teff, logg, t, g)
        if d < best_dist && d > 0
            best_dist = d
            best = (t, g)
        end
    end
    return best, best_dist
end

# Build plan
plan = []
no_neighbor = []

for (t, g) in failed
    nb, dist = find_neighbor(t, g)
    if nb === nothing
        push!(no_neighbor, (t, g))
    else
        push!(plan, (t, g, nb[1], nb[2], dist))
    end
end

# Write output files
open("retry-input.dat", "w") do f
    for (t, g, nt, ng, d) in plan
        @printf(f, "%.1f  %.2f\n", t, g)
    end
end

open("retry-neighbors.dat", "w") do f
    for (t, g, nt, ng, d) in plan
        @printf(f, "%.1f  %.2f\n", nt, ng)
    end
end

# Print plan
println()
println("="^65)
println(" RETRY PLAN ($(length(plan)) models)")
println("="^65)
println("  $(rpad("Failed model", 22))  $(rpad("Neighbor", 22))  Dist")
println("  " * "-"^61)
for (t, g, nt, ng, d) in plan
    println("  $(rpad(dir_name(t,g), 22))  $(rpad(dir_name(nt,ng), 22))  $(round(d, digits=2))")
end

if !isempty(no_neighbor)
    println()
    println("  WARNING: No neighbor found for $(length(no_neighbor)) models:")
    for (t, g) in no_neighbor
        println("    $(dir_name(t,g))")
    end
end

println()
println("Written: retry-input.dat ($(length(plan)) rows)")
println("Written: retry-neighbors.dat ($(length(plan)) rows)")
println()
println("Next steps:")
println("  1. Edit retry_grid.sub → set 'queue $(length(plan))'")
println("  2. condor_submit retry_grid.sub")