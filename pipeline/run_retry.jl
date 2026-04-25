using DelimitedFiles
using Printf
using JLD2

# ==============================================================================
# run_retry.jl — Run a single failed model using a neighbor as starting point
#
# Reads Teff/logg from retry-input.dat and the neighbor from retry-neighbors.dat.
# Skips the gray LTE step — uses neighbor's mod_nl.7 directly as start.
# Accelerations disabled (ITEK=IACC=50) for all steps — these are borderline
# models that diverge with the standard acceleration scheme.
#
# PIPELINE (4 steps, no gray LTE):
#   mod_nc    NLTE continuum CNO  ← starts from neighbor mod_nl.7
#   mod_nc_fe NLTE continuum + Si+S+Fe
#   mod_nl    NLTE full lines
#   mod_sp    SYNSPEC → JLD2
#
# USAGE:
#   julia run_retry.jl <row_number>
#   where row_number is 1-based index into retry-input.dat / retry-neighbors.dat
# ==============================================================================

# ==============================================================================
# GRID METALLICITY — keep in sync with run_model_fe.jl
# ==============================================================================
# Keep in sync with run_model.jl
const COMPOSITION = "SiFe"   # "H", "HHe", "HHeCNO", or "SiFe"
const Z_SOLAR = 1.0

const SOLAR_ABUND = Dict(
    :he => -1.07,  :c  => -3.57,  :n  => -4.17,
    :o  => -3.31,  :ne => -4.07,  :na => -5.76,
    :mg => -4.40,  :al => -5.55,  :si => -4.49,
    :p  => -6.59,  :s  => -4.88,  :cl => -6.50,
    :ar => -5.60,  :k  => -6.97,  :ca => -5.66,
    :fe => -4.50,
)

function make_abn(elem::Symbol, Z::Float64)
    (Z == 1.0 || elem == :he) && return "0."
    return @sprintf("%.5f", SOLAR_ABUND[elem] + log10(Z))
end

input_file    = "retry-input.dat"
neighbor_file = "retry-neighbors.dat"

if length(ARGS) < 1
    println("Usage: julia run_retry.jl <row_number>")
    exit(1)
end

row_idx = parse(Int, ARGS[1])

for f in [input_file, neighbor_file]
    if !isfile(f)
        println("Error: '$f' not found.")
        exit(1)
    end
end

inp = readdlm(input_file)
nbr = readdlm(neighbor_file)

if row_idx < 1 || row_idx > size(inp, 1)
    println("Error: Row $row_idx out of range (1-$(size(inp,1)))")
    exit(1)
end

teff      = Float64(inp[row_idx, 1])
logg      = Float64(inp[row_idx, 2])
teff_nb   = Float64(nbr[row_idx, 1])
logg_nb   = Float64(nbr[row_idx, 2])

dir_name  = "model_$(@sprintf("%.0f_%.0f", teff,    logg    * 100))"
nb_dir    = "model_$(@sprintf("%.0f_%.0f", teff_nb, logg_nb * 100))"
nb_model  = abspath(joinpath(nb_dir, "mod_nl.7"))  # absolute path before any cd

println("="^60)
println(" RETRY: Teff=$teff K, logg=$logg")
println(" Directory : $dir_name")
println(" Neighbor  : $nb_dir")
println("="^60)

if !isfile(nb_model)
    println("ERROR: Neighbor model not found: $nb_model")
    exit(1)
end

if !isdir(dir_name); mkdir(dir_name); end
cd(dir_name)

# ==============================================================================
# STELLAR TYPE AND PARAMETERS
# ==============================================================================
is_ostar = teff >= 30000.0
vtb_val  = is_ostar ? 10.0 : 2.0
is_sg    = logg < 3.0
star_type = is_ostar ? "O-Star" : "B-Star"

println("   -> Type: $star_type | VTB=$vtb_val km/s$(is_sg ? " | Supergiant" : "")")

# ITEK=IACC=50: disable accelerations — borderline models diverge with default scheme
# TAULAS=1.e2: shallower lower boundary for supergiants
sg_extra = is_sg ? ",TAULAS=1.e2" : ""
nst_base = " ND=50,VTB=$(vtb_val),IELCOR=-1,ITEK=50,IACC=50$(sg_extra)"

# Simplified retry: skip nc_fix/nc_inre intermediates that produce invalid structures.
# Run nc → nc_fe → nl starting from neighbor mod_nl.7 directly.
open("param_nc.nst",    "w") do f; print(f, "$nst_base,NLAMBD=3,ISPODF=0,CHMAX=1.e-3\n ");  end
open("param_nc_fe.nst", "w") do f; print(f, "$nst_base,NLAMBD=8,ISPODF=1,CHMAX=1.e-3\n ");  end
open("param_nl.nst",    "w") do f; print(f, "$nst_base,NLAMBD=8,ISPODF=1,CHMAX=1.e-5\n ");  end
open("param_sp.nst",    "w") do f; print(f, " VTB=$(vtb_val)\n ");                            end

# ==============================================================================
# ATOM/ION BLOCKS (same as run_model_fe.jl)
# ==============================================================================
atoms_cno_2k = """
*-----------------------------------------------------------------
* frequencies
 2000
*-----------------------------------------------------------------
* data for atoms
*
 8
* mode abn modpf
    2   0.      0     ! H
    2   0.      0     ! He
    0   0.      0     ! Li
    0   0.      0     ! Be
    0   0.      0     ! B
    2   0.      0     ! C
    2   0.      0     ! N
    2   0.      0     ! O
*
*iat   iz   nlevs  ilast ilvlin  nonstd typion  filei
*"""

atoms_fe_50k = """
*-----------------------------------------------------------------
* frequencies
 50000
*-----------------------------------------------------------------
* data for atoms
*
 26
* mode abn modpf
    2   0.      0     ! H
    2   0.      0     ! He
    0   0.      0     ! Li
    0   0.      0     ! Be
    0   0.      0     ! B
    2   0.      0     ! C
    2   0.      0     ! N
    2   0.      0     ! O
    0   0.      0     ! F
    1   0.      0     ! Ne
    1   0.      0     ! Na
    1   0.      0     ! Mg
    1   0.      0     ! Al
    2   0.      0     ! Si
    1   0.      0     ! P
    2   0.      0     ! S
    1   0.      0     ! Cl
    1   0.      0     ! Ar
    1   0.      0     ! K
    1   0.      0     ! Ca
    0   0.      0     ! Sc
    0   0.      0     ! Ti
    0   0.      0     ! V
    0   0.      0     ! Cr
    0   0.      0     ! Mn
    2   0.      0     ! Fe
*
*iat   iz   nlevs  ilast ilvlin  nonstd typion  filei
*"""

function fe_ion_block(iz, nlevs, ilvlin, typion, va_file, gam_n, rap_file)
    return """  26  $(lpad(iz,2))  $(lpad(nlevs,4))     0  $(lpad(ilvlin,4))    -1   '$typion' 'data/$va_file'
   0   0                                           'data/gf$(gam_n).gam'
                                                   'data/gf$(gam_n).lin'
                                                   'data/$rap_file'"""
end

ions_cno_100 = """
   1    0     9      0    100      0    ' H 1' 'data/h1.dat'
   1    1     1      1      0      0    ' H 2' ' '
   2    0    24      0    100      0    'He 1' 'data/he1.dat'
   2    1    20      0    100      0    'He 2' 'data/he2.dat'
   2    2     1      1      0      0    'He 3' ' '
   6    0    40      0    100      0    ' C 1' 'data/c1.dat'
   6    1    22      0    100      0    ' C 2' 'data/c2.dat'
   6    2    46      0    100      0    ' C 3' 'data/c3_34+12lev.dat'
   6    3    25      0    100      0    ' C 4' 'data/c4.dat'
   6    4     1      1      0      0    ' C 5' ' '
   7    0    34      0    100      0    ' N 1' 'data/n1.dat'
   7    1    42      0    100      0    ' N 2' 'data/n2_32+10lev.dat'
   7    2    32      0    100      0    ' N 3' 'data/n3.dat'
   7    3    48      0    100      0    ' N 4' 'data/n4_34+14lev.dat'
   7    4    16      0    100      0    ' N 5' 'data/n5.dat'
   7    5     1      1      0      0    ' N 6' ' '
   8    0    33      0    100      0    ' O 1' 'data/o1_23+10lev.dat'
   8    1    48      0    100      0    ' O 2' 'data/o2_36+12lev.dat'
   8    2    41      0    100      0    ' O 3' 'data/o3_28+13lev.dat'
   8    3    39      0    100      0    ' O 4' 'data/o4.dat'
   8    4     6      0    100      0    ' O 5' 'data/o5.dat'
   8    5     1      1      0      0    ' O 6' ' '
   0    0     0     -1      0      0    '    ' ' '
*
* end
"""

function build_ions_fe(ilvlin::Int)
    si_s = """
   14    0    45      0    $ilvlin      0    'Si 1' 'data/si1.t'
   14    1    40      0    $ilvlin      0    'Si 2' 'data/si2_36+4lev.dat'
   14    2    32      0    $ilvlin      0    'Si 3' 'data/si3.dat'
   14    3    16      0    $ilvlin      0    'Si 4' 'data/si4.dat'
   14    4     1      1      0          0    'Si 5' ' '
   16    0    41      0    $ilvlin      0    ' S 1' 'data/s1.t'
   16    1    33      0    $ilvlin      0    ' S 2' 'data/s2_23+10lev.dat'
   16    2    41      0    $ilvlin      0    ' S 3' 'data/s3_29+12lev.dat'
   16    3    38      0    $ilvlin      0    ' S 4' 'data/s4_33+5lev.dat'
   16    4    25      0    $ilvlin      0    ' S 5' 'data/s5_20+5lev.dat'
   16    5    10      0    $ilvlin      0    ' S 6' 'data/s6.dat'
   16    6     1      1      0          0    ' S 7' ' '"""

    fe1 = "\n   26    0    30      0    $ilvlin      0    'Fe 1' 'data/fe1.dat'"
    fe2 = "\n" * fe_ion_block(1, 36, ilvlin, "Fe 2", "fe2va.dat", "2601", "fe2p_14+11lev.rap")
    fe3 = "\n" * fe_ion_block(2, 50, ilvlin, "Fe 3", "fe3va.dat", "2602", "fe3p_22+7lev.rap")

    if is_ostar
        fe4  = "\n" * fe_ion_block(3, 28, ilvlin, "Fe 4", "fe4va.dat", "2603", "fe4p_21+11lev.rap")
        fe5  = "\n" * fe_ion_block(4, 22, ilvlin, "Fe 5", "fe5va.dat", "2604", "fe5p_19+11lev.rap")
        fe6  = "\n" * fe_ion_block(5, 16, ilvlin, "Fe 6", "fe6v.dat",  "2605", "fe6b.rap")
        fe_b = "\n   26    6     1      1      0          0    'Fe 7' ' '"
        fe_block = fe1 * fe2 * fe3 * fe4 * fe5 * fe6 * fe_b
    else
        fe_b = "\n   26    3     1      1      0          0    'Fe 4' ' '"
        fe_block = fe1 * fe2 * fe3 * fe_b
    end

    return """
   1    0     9      0    $ilvlin      0    ' H 1' 'data/h1.dat'
   1    1     1      1      0          0    ' H 2' ' '
   2    0    24      0    $ilvlin      0    'He 1' 'data/he1.dat'
   2    1    20      0    $ilvlin      0    'He 2' 'data/he2.dat'
   2    2     1      1      0          0    'He 3' ' '
   6    0    40      0    $ilvlin      0    ' C 1' 'data/c1.dat'
   6    1    22      0    $ilvlin      0    ' C 2' 'data/c2.dat'
   6    2    46      0    $ilvlin      0    ' C 3' 'data/c3_34+12lev.dat'
   6    3    25      0    $ilvlin      0    ' C 4' 'data/c4.dat'
   6    4     1      1      0          0    ' C 5' ' '
   7    0    34      0    $ilvlin      0    ' N 1' 'data/n1.dat'
   7    1    42      0    $ilvlin      0    ' N 2' 'data/n2_32+10lev.dat'
   7    2    32      0    $ilvlin      0    ' N 3' 'data/n3.dat'
   7    3    48      0    $ilvlin      0    ' N 4' 'data/n4_34+14lev.dat'
   7    4    16      0    $ilvlin      0    ' N 5' 'data/n5.dat'
   7    5     1      1      0          0    ' N 6' ' '
   8    0    33      0    $ilvlin      0    ' O 1' 'data/o1_23+10lev.dat'
   8    1    48      0    $ilvlin      0    ' O 2' 'data/o2_36+12lev.dat'
   8    2    41      0    $ilvlin      0    ' O 3' 'data/o3_28+13lev.dat'
   8    3    39      0    $ilvlin      0    ' O 4' 'data/o4.dat'
   8    4     6      0    $ilvlin      0    ' O 5' 'data/o5.dat'
   8    5     1      1      0          0    ' O 6' ' '
$si_s
$fe_block
   0    0     0     -1      0          0    '    ' ' '
*
* end
"""
end

# ==============================================================================
# GENERATE .5 INPUT FILES
# ==============================================================================
open("mod_nc_fix.5", "w") do f
    println(f, "$teff $logg")
    println(f, " F  F")
    println(f, " 'param_nc_fix.nst'")
    println(f, atoms_cno_2k)
    println(f, ions_cno_100)
end

open("mod_nc_inre.5", "w") do f
    println(f, "$teff $logg")
    println(f, " F  F")
    println(f, " 'param_nc_inre.nst'")
    println(f, atoms_cno_2k)
    println(f, ions_cno_100)
end

open("mod_nc.5", "w") do f
    println(f, "$teff $logg")
    println(f, " F  F")
    println(f, " 'param_nc.nst'")
    println(f, atoms_cno_2k)
    println(f, ions_cno_100)
end

open("mod_nc_fe.5", "w") do f
    println(f, "$teff $logg")
    println(f, " F  F")
    println(f, " 'param_nc_fe.nst'")
    println(f, atoms_fe_50k)
    println(f, build_ions_fe(100))
end

open("mod_nl.5", "w") do f
    println(f, "$teff $logg")
    println(f, " F  F")
    println(f, " 'param_nl.nst'")
    println(f, atoms_fe_50k)
    println(f, build_ions_fe(0))
end

open("mod_sp.5", "w") do f
    println(f, "$teff $logg")
    println(f, " F  F")
    println(f, " 'param_sp.nst'")
    println(f, atoms_fe_50k)
    println(f, """
   1    0     9      0      0      0    ' H 1' 'data/h1.dat'
   1    1     1      1      0      0    ' H 2' ' '
   2    0    24      0      0      0    'He 1' 'data/he1.dat'
   2    1    20      0      0      0    'He 2' 'data/he2.dat'
   2    2     1      1      0      0    'He 3' ' '
   6    0    40      0      0      0    ' C 1' 'data/c1.dat'
   6    1    22      0      0      0    ' C 2' 'data/c2.dat'
   6    2    46      0      0      0    ' C 3' 'data/c3_34+12lev.dat'
   6    3    25      0      0      0    ' C 4' 'data/c4.dat'
   6    4     1      1      0      0    ' C 5' ' '
   7    0    34      0      0      0    ' N 1' 'data/n1.dat'
   7    1    42      0      0      0    ' N 2' 'data/n2_32+10lev.dat'
   7    2    32      0      0      0    ' N 3' 'data/n3.dat'
   7    3    48      0      0      0    ' N 4' 'data/n4_34+14lev.dat'
   7    4    16      0      0      0    ' N 5' 'data/n5.dat'
   7    5     1      1      0      0    ' N 6' ' '
   8    0    33      0      0      0    ' O 1' 'data/o1_23+10lev.dat'
   8    1    48      0      0      0    ' O 2' 'data/o2_36+12lev.dat'
   8    2    41      0      0      0    ' O 3' 'data/o3_28+13lev.dat'
   8    3    39      0      0      0    ' O 4' 'data/o4.dat'
   8    4     6      0      0      0    ' O 5' 'data/o5.dat'
   8    5     1      1      0      0    ' O 6' ' '
   14   0    45      0      0      0    'Si 1' 'data/si1.t'
   14   1    40      0      0      0    'Si 2' 'data/si2_36+4lev.dat'
   14   2     1      1      0      0    'Si 3' ' '
   16   0    41      0      0      0    ' S 1' 'data/s1.t'
   16   1    33      0      0      0    ' S 2' 'data/s2_23+10lev.dat'
   16   2     1      1      0      0    ' S 3' ' '
   26   0    30      0      0      0    'Fe 1' 'data/fe1.dat'
   26   1     1      1      0      0    'Fe 2' ' '
   0    0     0     -1      0      0    '    ' ' '
*
* end
""")
end

# fort.55 for SYNSPEC — written per segment in the loop below
sp_step  = 0.1
sp_cutof = 0.01

if is_ostar
    segments = [
        (50.0,  -900.0,   1.0e-2),
        (900.0, -50000.0, 1.0e-4),
    ]
else
    segments = [
        (500.0, -50000.0, 1.0e-4),
    ]
end

linelist_path = get(ENV, "LINELIST", "")
inlist_val = (!isempty(linelist_path) && isfile(joinpath(linelist_path, "gfATO.bin"))) ? 1 : 0

function write_fort55(afirst, alast, relop)
    open("synspec.55", "w") do f
        print(f, """   0     0     0
   1     0     0     0
   0     0     0     0     0
   1     0     0     $(inlist_val)     0
   0     0     0
 $(afirst) $(alast) $(sp_step)  0  $(relop)  $(sp_cutof)
   1    19
""")
    end
end

println("Input files generated.")

# ==============================================================================
# EXECUTION
# ==============================================================================
tlusty_path  = get(ENV, "TLUSTY", "")
rtlusty_cmd  = isempty(tlusty_path) ? "RTlusty"  : joinpath(tlusty_path, "RTlusty")
rsynspec_cmd = isempty(tlusty_path) ? "RSynspec" : joinpath(tlusty_path, "RSynspec")

if !isempty(linelist_path) && isfile(joinpath(linelist_path, "gfATO.bin"))
    linelist_file = joinpath(linelist_path, "gfATO.bin")
elseif !isempty(linelist_path) && isfile(joinpath(linelist_path, "gfATO.dat"))
    linelist_file = joinpath(linelist_path, "gfATO.dat")
else
    linelist_file = ""
end

function clean_data_link()
    (islink("data") || isfile("data") || isdir("data")) && rm("data", force=true)
end

function check_output(step_name)
    if !isfile("$step_name.7")
        println("ERROR: $step_name.7 not found. Check $step_name.6.")
        cd("..")
        exit(1)
    end
    println("   ✓ $step_name.7 generated.")
end

function check_nan(step_name)
    flux_file = "$step_name.13"
    if !isfile(flux_file)
        println("ERROR: $step_name.13 not found — TLUSTY crashed.")
        println("  Directory preserved: $(abspath(pwd()))")
        cd("..")
        exit(1)
    end
    open(flux_file, "r") do f
        for (i, line) in enumerate(eachline(f))
            cols = split(line)
            length(cols) >= 2 || continue
            flux_str = cols[2]
            if occursin(r"[Nn][Aa][Nn]", flux_str)
                println("ERROR: NaN in $step_name.13 (line $i). Directory preserved.")
                cd("..")
                exit(1)
            end
            val = tryparse(Float64, replace(flux_str, r"[dD](?=[+-]?\d)" => "e"))
            if val !== nothing && (isnan(val) || isinf(val))
                println("ERROR: NaN/Inf in $step_name.13 (line $i). Directory preserved.")
                cd("..")
                exit(1)
            end
        end
    end
    println("   ✓ $step_name.13 — no NaN.")
end

println("\nStarting retry calculations...")

# Use neighbor's mod_nl.7 directly as starting point
cp(nb_model, "mod_lt.7", force=true)
println("   ✓ Starting from neighbor: $nb_dir/mod_nl.7")

# Step 1: NLTE continuum CNO — start directly from neighbor structure
println("\n>> [1] NLTE continuum...")
clean_data_link()
run(`bash -c "$rtlusty_cmd mod_nc mod_lt"`)
check_output("mod_nc")
check_nan("mod_nc")

if COMPOSITION == "SiFe"
    println("\n>> [2] NLTE continuum Si+S+Fe...")
    clean_data_link()
    run(`bash -c "$rtlusty_cmd mod_nc_fe mod_nc"`)
    check_output("mod_nc_fe")
    check_nan("mod_nc_fe")
    prev_nl = "mod_nc_fe"
else
    prev_nl = "mod_nc"
end

println("\n>> NLTE full lines...")
clean_data_link()
run(`bash -c "$rtlusty_cmd mod_nl $prev_nl"`)
clean_data_link()
check_output("mod_nl")
check_nan("mod_nl")

# Step 4: SYNSPEC — multi-segment to avoid array overflow in far UV
println("\n>> [5/5] SYNSPEC...")
clean_data_link()
cp("mod_nl.7", "mod_sp.7", force=true)

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

all_lam_s  = Float64[]
all_hlam_s = Float64[]
all_lam_c  = Float64[]
all_hlam_c = Float64[]

for (iseg, (afirst, alast, relop)) in enumerate(segments)
    println("  Segment $iseg/$(length(segments)): $(afirst)–$(abs(alast)) Å...")
    write_fort55(afirst, alast, relop)

    synspec_call = isempty(linelist_file) ?
        "$rsynspec_cmd mod_sp synspec.55" :
        "$rsynspec_cmd mod_sp synspec.55 $linelist_file"

    clean_data_link()
    run(`bash -c "$synspec_call"`)
    clean_data_link()

    !isfile("mod_sp.spec") || !isfile("mod_sp.cont") && continue

    lam_s, hlam_s = read_synspec("mod_sp.spec")
    lam_c, hlam_c = read_synspec("mod_sp.cont")
    length(lam_s) < 10 && continue

    println("    → $(length(lam_s)) points")

    if !isempty(all_lam_s)
        last_lam = all_lam_s[end]
        keep_s = lam_s .> last_lam
        keep_c = lam_c .> last_lam
        lam_s  = lam_s[keep_s];  hlam_s = hlam_s[keep_s]
        lam_c  = lam_c[keep_c];  hlam_c = hlam_c[keep_c]
    end

    append!(all_lam_s, lam_s);  append!(all_hlam_s, hlam_s)
    append!(all_lam_c, lam_c);  append!(all_hlam_c, hlam_c)
    rm("mod_sp.spec", force=true); rm("mod_sp.cont", force=true)
end

if length(all_lam_s) < 10000
    println("FAILURE: SYNSPEC produced only $(length(all_lam_s)) total points.")
    println("  mod_nl.7 is intact — directory preserved.")
    cd("..")
    exit(1)
end

# Filter NaN and negative values before interpolation
function clean_spectrum(lam, hlam, label)
    valid = isfinite.(hlam) .& (hlam .> 0)
    n_bad = count(.!valid)
    if n_bad > 0
        pct = round(100 * n_bad / length(hlam), digits=2)
        println("   WARNING: $n_bad invalid points ($pct%) removed from $label.")
    end
    return lam[valid], hlam[valid]
end

all_lam_s, all_hlam_s = clean_spectrum(all_lam_s, all_hlam_s, "hlam_spec")
all_lam_c, all_hlam_c = clean_spectrum(all_lam_c, all_hlam_c, "hlam_cont")

println("\nSaving JLD2...")
lam_s  = all_lam_s;  hlam_s = all_hlam_s
lam_c  = all_lam_c;  hlam_c = all_hlam_c

step_out = 0.5
lam_grid = collect(lam_s[1]:step_out:lam_s[end])
interp(lam, hlam, λ) = let idx = searchsortedfirst(lam, λ)
    idx == 1 ? hlam[1] : idx > length(lam) ? hlam[end] :
    hlam[idx-1] + (hlam[idx]-hlam[idx-1])*(λ-lam[idx-1])/(lam[idx]-lam[idx-1])
end

hlam_s_out = Float32.([interp(lam_s, hlam_s, λ) for λ in lam_grid])
hlam_c_out = Float32.([interp(lam_c, hlam_c, λ) for λ in lam_grid])

# Check for NaN after interpolation
n_nan_s = count(isnan, hlam_s_out)
n_nan_c = count(isnan, hlam_c_out)
(n_nan_s > 0 || n_nan_c > 0) &&
    println("   WARNING: $n_nan_s NaN in hlam_spec, $n_nan_c in hlam_cont after interpolation.")

jldsave("mod_sp.jld2"; compress=true,
    lam         = Float32.(lam_grid),
    hlam_spec   = hlam_s_out,
    hlam_cont   = hlam_c_out,
    teff        = Float32(teff),
    logg        = Float32(logg),
    Z           = Float32(Z_SOLAR),
    composition = COMPOSITION,
    vtb         = Float32(vtb_val),
    star_type   = star_type,
    step_ang    = Float32(step_out)
)
println("   ✓ JLD2 saved.")

cd("..")
println("\n==> SUCCESS: $dir_name (restarted from $nb_dir)")
println("    SED → $dir_name/mod_sp.jld2")