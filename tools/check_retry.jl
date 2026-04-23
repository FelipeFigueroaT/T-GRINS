using DelimitedFiles
using Printf

# ==============================================================================
# check_retry.jl — Check status of retry jobs
#
# Reads retry-input.dat and reports which models now have mod_sp.jld2
# (succeeded) and which still don't (still failing).
#
# USAGE:
#   julia check_retry.jl
# ==============================================================================

input_file = "retry-input.dat"

if !isfile(input_file)
    println("Error: '$input_file' not found. Run make_retry_list.jl first.")
    exit(1)
end

data = readdlm(input_file)
models = [(Float64(data[i,1]), Float64(data[i,2])) for i in 1:size(data,1)]

dir_name(t, g) = "model_$(@sprintf("%.0f_%.0f", t, g * 100))"

succeeded = []
failed    = []

for (t, g) in models
    d = dir_name(t, g)
    if isfile(joinpath(d, "mod_sp.jld2"))
        push!(succeeded, (t, g))
    else
        push!(failed, (t, g))
    end
end

println("Retry results ($(length(models)) models total):")
println("  ✓ Succeeded : $(length(succeeded))")
println("  ✗ Still failing: $(length(failed))")

if !isempty(failed)
    println()
    println("Still failing:")
    for (t, g) in failed
        println("  $(dir_name(t, g))")
    end
end