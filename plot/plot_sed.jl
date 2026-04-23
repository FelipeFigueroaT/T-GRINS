#!/usr/bin/env julia
# ==============================================================================
# plot_sed.jl — Plot SED from a T-GRINS JLD2 file
#
# Usage:
#   julia plot_sed.jl model_35000_400/mod_sp.jld2
#   julia plot_sed.jl model_35000_400/mod_sp.jld2 --save
#
# Options:
#   --save   Save plot as PNG instead of displaying interactively
#
# Dependencies:
#   julia -e 'using Pkg; Pkg.add(["JLD2", "Plots"])'
# ==============================================================================

using JLD2
using Plots
gr()

if length(ARGS) < 1
    println("Usage: julia plot_sed.jl <path/to/mod_sp.jld2> [--save]")
    exit(1)
end

jld2_file = ARGS[1]
save_plot = "--save" in ARGS

if !isfile(jld2_file)
    println("Error: File not found: $jld2_file")
    exit(1)
end

# Load
d         = load(jld2_file)
lam       = Float64.(d["lam"])
hlam_spec = Float64.(d["hlam_spec"])
hlam_cont = Float64.(d["hlam_cont"])
teff      = d["teff"]
logg      = d["logg"]
Z         = haskey(d, "Z") ? d["Z"] : 1.0f0
star_type = haskey(d, "star_type") ? d["star_type"] : ""

# Filter positive values (deep absorption lines can reach 0)
ms = hlam_spec .> 0
mc = hlam_cont .> 0

title_str = "Teff = $(Int(teff)) K   log g = $(logg)"
Z != 1.0f0 && (title_str *= "   Z = $(Z)×solar")

p = plot(
    log10.(lam[ms]), log10.(hlam_spec[ms]),
    label    = "Spectrum",
    lw       = 0.4,
    color    = :steelblue,
    alpha    = 0.9,
    xlabel   = "log λ [Å]",
    ylabel   = "log H_λ [erg cm⁻² s⁻¹ Å⁻¹]",
    title    = title_str,
    legend   = :topright,
    size     = (1000, 450),
    dpi      = 150,
    grid     = true,
    gridalpha = 0.2,
)

plot!(p,
    log10.(lam[mc]), log10.(hlam_cont[mc]),
    label = "Continuum",
    lw    = 1.2,
    color = :tomato,
    ls    = :dash,
    alpha = 0.85,
)

# Reference lines
refs = [(912, "Ly limit"), (1216, "Lyα"), (4861, "Hβ"), (6563, "Hα")]
ymin, ymax = ylims(p)
for (λ_ref, name) in refs
    if lam[ms][1] < λ_ref < lam[ms][end]
        vline!(p, [log10(λ_ref)], color=:gray, lw=0.6, ls=:dot, label="")
        annotate!(p, log10(λ_ref), ymax - 0.05*(ymax-ymin),
                  text(name, :gray, :center, 7))
    end
end

if save_plot
    out = replace(jld2_file, ".jld2" => "_sed.png")
    savefig(p, out)
    println("Saved: $out")
else
    display(p)
    println("Press Enter to close...")
    readline()
end