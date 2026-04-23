using DelimitedFiles
using Printf
using JLD2

# ==============================================================================
# run_model_fe.jl  —  TLUSTY + SYNSPEC: NLTE model atmospheres up to Fe (Z≤26)
#
# USAGE:
#   Grid mode  : julia run_model_fe.jl -g tlusty-input.dat -l 3
#   Config mode: julia run_model_fe.jl -c config.toml
#   Quick mode : julia run_model_fe.jl -t 35000 -G 4.0
#   Legacy     : julia run_model_fe.jl 3   (reads tlusty-input.dat, line 3)
#
# PIPELINE (5 steps):
#   mod_lt    LTE gray atmosphere
#   mod_nc    NLTE continuum, CNO only
#   mod_nc_fe NLTE continuum + Si+S+Fe (Fe blanketing in LTE superlevel mode)
#   mod_nl    NLTE full lines, final converged atmosphere
#   mod_sp    SYNSPEC → detailed SED saved as .jld2
#
# ENVIRONMENT VARIABLES REQUIRED:
#   TLUSTY   — path to tlusty/synspec root
#   LINELIST — path to line list directory (gfATO.dat / gfATO.bin)
#   IRON     — path to iron superline data
#
# DEPENDENCIES:
#   julia -e 'using Pkg; Pkg.add(["JLD2", "CodecZlib", "TOML"])'
# ==============================================================================

# ==============================================================================
# GRID METALLICITY
# Change Z_SOLAR once to run the full grid at a different metallicity:
#   Z_SOLAR = 1.0  → Galactic (solar)
#   Z_SOLAR = 0.5  → LMC
#   Z_SOLAR = 0.2  → SMC
# Applied to all metals (Z > 2). H and He are not scaled by Z.
# In config mode, use the [abundances] section for finer control.
# ==============================================================================
const Z_SOLAR = 1.0

# Asplund et al. (2009) solar photospheric abundances: log(N/N_H)
const SOLAR_ABUND = Dict(
    :he => -1.07,  :c  => -3.57,  :n  => -4.17,
    :o  => -3.31,  :ne => -4.07,  :na => -5.76,
    :mg => -4.40,  :al => -5.55,  :si => -4.49,
    :p  => -6.59,  :s  => -4.88,  :cl => -6.50,
    :ar => -5.60,  :k  => -6.97,  :ca => -5.66,
    :fe => -4.50,
)

# ==============================================================================
# ARGUMENT PARSING
# ==============================================================================
function parse_args(args)
    grid_file   = "tlusty-input.dat"
    line_idx    = nothing
    config_file = nothing
    teff_arg    = nothing
    logg_arg    = nothing

    i = 1
    while i <= length(args)
        a = args[i]
        if a == "-g" && i < length(args)
            grid_file = args[i+1]; i += 2
        elseif a == "-l" && i < length(args)
            line_idx = parse(Int, args[i+1]); i += 2
        elseif a == "-c" && i < length(args)
            config_file = args[i+1]; i += 2
        elseif a == "-t" && i < length(args)
            teff_arg = parse(Float64, args[i+1]); i += 2
        elseif a == "-G" && i < length(args)
            logg_arg = parse(Float64, args[i+1]); i += 2
        else
            # Legacy positional arg: line number
            line_idx = parse(Int, a); i += 1
        end
    end

    if config_file !== nothing
        return :config, config_file, nothing, nothing, nothing
    elseif teff_arg !== nothing && logg_arg !== nothing
        return :quick, nothing, nothing, teff_arg, logg_arg
    elseif line_idx !== nothing
        return :grid, grid_file, line_idx, nothing, nothing
    else
        println("""
Usage:
  Grid mode  : julia run_model_fe.jl -g tlusty-input.dat -l 3
  Config mode: julia run_model_fe.jl -c config.toml
  Quick mode : julia run_model_fe.jl -t 35000 -G 4.0
  Legacy     : julia run_model_fe.jl 3
""")
        exit(1)
    end
end

mode, config_file, line_idx, teff_arg, logg_arg = parse_args(ARGS)

# ==============================================================================
# DEFAULT PARAMETERS (overridden by config or CLI)
# ==============================================================================
cfg = Dict{String,Any}(
    "teff"       => 0.0,
    "logg"       => 0.0,
    "Z"          => Z_SOLAR,
    "abund"      => Dict{String,Float64}(),  # element overrides relative to solar
    # TLUSTY
    "nd"         => 50,
    "nlambd"     => 8,
    "chmax"      => 1.0e-5,
    "itek"       => 15,
    "iacc"       => 10,
    "ielcor"     => -1,
    "vtb"        => -1.0,    # -1 = auto (2 km/s B-star, 10 km/s O-star)
    "taulas"     => -1.0,    # -1 = auto (1e2 for supergiants)
    # SYNSPEC
    "segments"   => Tuple{Float64,Float64,Float64}[],  # empty = auto
    "sp_step"    => 0.1,
    "sp_cutof"   => 0.01,
    # Output
    "step_ang"   => 0.5,
    "keep_ascii" => false,
)

# ==============================================================================
# LOAD PARAMETERS FROM MODE
# ==============================================================================
if mode == :config
    using TOML
    if !isfile(config_file)
        println("Error: Config file '$config_file' not found.")
        exit(1)
    end
    toml = TOML.parsefile(config_file)

    m = get(toml, "model", Dict())
    cfg["teff"] = Float64(get(m, "teff", 0.0))
    cfg["logg"] = Float64(get(m, "logg", 0.0))
    cfg["Z"]    = Float64(get(m, "Z", Z_SOLAR))

    if cfg["teff"] == 0.0 || cfg["logg"] == 0.0
        println("Error: [model] teff and logg must be specified in $config_file")
        exit(1)
    end

    for (k, v) in get(toml, "abundances", Dict())
        k2 = lowercase(k)
        k2 == "z" && (cfg["Z"] = Float64(v); continue)
        cfg["abund"][k2] = Float64(v)
    end

    for (k, v) in get(toml, "tlusty", Dict())
        cfg[lowercase(k)] = v
    end

    sp = get(toml, "synspec", Dict())
    for (k, v) in sp
        if lowercase(k) == "segments"
            cfg["segments"] = [(Float64(s[1]), Float64(s[2]), Float64(s[3])) for s in v]
        else
            cfg[lowercase(k)] = v
        end
    end

    for (k, v) in get(toml, "output", Dict())
        cfg[lowercase(k)] = v
    end

elseif mode == :quick
    cfg["teff"] = teff_arg
    cfg["logg"] = logg_arg

else  # :grid
    if !isfile(grid_file)
        println("Error: Grid file '$grid_file' not found.")
        exit(1)
    end
    data = readdlm(grid_file)
    if line_idx < 1 || line_idx > size(data, 1)
        println("Error: Line $line_idx out of range (1–$(size(data,1)))")
        exit(1)
    end
    cfg["teff"] = Float64(data[line_idx, 1])
    cfg["logg"] = Float64(data[line_idx, 2])
    cfg["Z"]    = size(data, 2) >= 3 ? Float64(data[line_idx, 3]) : Z_SOLAR
end

teff = cfg["teff"]
logg = cfg["logg"]
Z    = cfg["Z"]

# ==============================================================================
# STELLAR TYPE
# ==============================================================================
is_ostar      = teff >= 30000.0
is_supergiant = logg < 3.0
star_type     = is_ostar ? "O-Star" : "B-Star"
vtb_val       = cfg["vtb"] > 0 ? cfg["vtb"] : (is_ostar ? 10.0 : 2.0)

dir_name = "model_$(@sprintf("%.0f_%.0f", teff, logg * 100))"
Z != 1.0 && (dir_name *= "_Z$(@sprintf("%.2f", Z))")

println("="^60)
println(" Teff=$(teff) K  logg=$(logg)  Z=$(Z)×solar  $(star_type)  VTB=$(vtb_val) km/s")
println(" Directory: $dir_name")
println("="^60)

# Skip if already has valid JLD2
jld2_path = joinpath(dir_name, "mod_sp.jld2")
if isfile(jld2_path)
    try
        d = load(jld2_path)
        n_pts = haskey(d, "lam") ? length(d["lam"]) : 0
        if n_pts > 10000
            println("SKIP: $dir_name already has valid JLD2 ($n_pts pts).")
            exit(0)
        else
            println("WARNING: JLD2 has only $n_pts pts — rerunning.")
        end
    catch
        println("WARNING: Unreadable JLD2 — rerunning.")
    end
end

if !isdir(dir_name); mkdir(dir_name); end
cd(dir_name)

# ==============================================================================
# ABUNDANCE SCALING
# When Z=1 and no overrides: abn=0. → TLUSTY uses internal solar defaults.
# When Z≠1 or overrides exist: explicit log(N/N_H) values are computed.
# He is never scaled by Z — only by explicit override.
# H is always fixed at N(H)/N(H)=1.
# ==============================================================================
function make_abn(elem::Symbol, Z::Float64, overrides::Dict{String,Float64})
    override = get(overrides, string(elem), 1.0)
    scale    = (elem == :he) ? override : (Z * override)
    if scale == 1.0 && override == 1.0
        return "0."   # let TLUSTY use internal solar default
    end
    log_abund = SOLAR_ABUND[elem] + log10(scale)
    return @sprintf("%.5f", log_abund)
end

ovr = cfg["abund"]
abn = Dict(e => make_abn(e, Z, ovr) for e in
    [:he,:c,:n,:o,:ne,:na,:mg,:al,:si,:p,:s,:cl,:ar,:k,:ca,:fe])

# ==============================================================================
# NST PARAMETER FILES
# ==============================================================================
nd     = cfg["nd"]
ielcor = cfg["ielcor"]
itek   = cfg["itek"]
iacc   = cfg["iacc"]
chmax  = cfg["chmax"]

if is_supergiant
    sg_lt = ",TAULAS=1.e2,ITEK=50,IACC=50"
    sg_nc = ",TAULAS=1.e2,ITEK=50,IACC=50,CHMAX=1.e-4"
    sg_fe = ",TAULAS=1.e2,ITEK=50,IACC=50,CHMAX=1.e-3"
    sg_nl = ",TAULAS=1.e2,ITEK=50,IACC=50,CHMAX=1.e-5"
    println("   -> Supergiant (logg<3.0): TAULAS=1e2, accelerations disabled.")
else
    sg_lt = ""
    sg_nc = ",CHMAX=1.e-4"
    sg_fe = ",CHMAX=1.e-3,ITEK=$(itek),IACC=$(iacc)"
    sg_nl = ",CHMAX=$(chmax),ITEK=$(itek),IACC=$(iacc)"
end

taulas_str = cfg["taulas"] > 0 ? ",TAULAS=$(cfg["taulas"])" : ""

open("param_lt.nst",    "w") do f; print(f, " ND=$(nd),NLAMBD=3,VTB=$(vtb_val),ISPODF=0,IELCOR=$(ielcor)$(sg_lt)\n "); end
open("param_nc.nst",    "w") do f; print(f, " ND=$(nd),NLAMBD=6,VTB=$(vtb_val),ISPODF=0,IELCOR=$(ielcor)$(sg_nc)\n "); end
open("param_nc_fe.nst", "w") do f; print(f, " ND=$(nd),NLAMBD=8,VTB=$(vtb_val),ISPODF=1,IELCOR=$(ielcor)$(sg_fe)\n "); end
open("param_nl.nst",    "w") do f; print(f, " ND=$(nd),NLAMBD=8,VTB=$(vtb_val),ISPODF=1,IELCOR=$(ielcor)$(sg_nl)\n "); end
open("param_sp.nst",    "w") do f; print(f, " VTB=$(vtb_val)\n ");                                                        end

# ==============================================================================
# ATOM HEADERS
# ==============================================================================
function atom_header(nfreq, natoms)
    lines = """
*-----------------------------------------------------------------
* frequencies
 $(nfreq)
*-----------------------------------------------------------------
* data for atoms
*
 $(natoms)
* mode abn modpf
    2   0.            0     ! H
    2   $(rpad(abn[:he],10))0     ! He
    0   0.            0     ! Li
    0   0.            0     ! Be
    0   0.            0     ! B
    2   $(rpad(abn[:c], 10))0     ! C
    2   $(rpad(abn[:n], 10))0     ! N
    2   $(rpad(abn[:o], 10))0     ! O"""
    if natoms == 8
        return lines * "\n*\n*iat   iz   nlevs  ilast ilvlin  nonstd typion  filei\n*"
    else
        return lines * """
    0   0.            0     ! F
    1   $(rpad(abn[:ne],10))0     ! Ne
    1   $(rpad(abn[:na],10))0     ! Na
    1   $(rpad(abn[:mg],10))0     ! Mg
    1   $(rpad(abn[:al],10))0     ! Al
    2   $(rpad(abn[:si],10))0     ! Si
    1   $(rpad(abn[:p], 10))0     ! P
    2   $(rpad(abn[:s], 10))0     ! S
    1   $(rpad(abn[:cl],10))0     ! Cl
    1   $(rpad(abn[:ar],10))0     ! Ar
    1   $(rpad(abn[:k], 10))0     ! K
    1   $(rpad(abn[:ca],10))0     ! Ca
    0   0.            0     ! Sc
    0   0.            0     ! Ti
    0   0.            0     ! V
    0   0.            0     ! Cr
    0   0.            0     ! Mn
    2   $(rpad(abn[:fe],10))0     ! Fe
*
*iat   iz   nlevs  ilast ilvlin  nonstd typion  filei
*"""
    end
end

header_cno_2k  = atom_header(2000,  8)
header_fe_50k  = atom_header(50000, 26)

# ==============================================================================
# ION BLOCKS
# ==============================================================================
function fe_superline(iz, nlevs, ilvlin, typion, va_file, gam_n, rap_file)
    "  26  $(lpad(iz,2))  $(lpad(nlevs,4))     0  $(lpad(ilvlin,4))    -1   '$typion' 'data/$va_file'\n" *
    "   0   0                                           'data/gf$(gam_n).gam'\n" *
    "                                                   'data/gf$(gam_n).lin'\n" *
    "                                                   'data/$rap_file'"
end

function ions_cno(ilvlin)
    """
   1    0     9      0   $(lpad(ilvlin,4))      0    ' H 1' 'data/h1.dat'
   1    1     1      1      0          0    ' H 2' ' '
   2    0    24      0   $(lpad(ilvlin,4))      0    'He 1' 'data/he1.dat'
   2    1    20      0   $(lpad(ilvlin,4))      0    'He 2' 'data/he2.dat'
   2    2     1      1      0          0    'He 3' ' '
   6    0    40      0   $(lpad(ilvlin,4))      0    ' C 1' 'data/c1.dat'
   6    1    22      0   $(lpad(ilvlin,4))      0    ' C 2' 'data/c2.dat'
   6    2    46      0   $(lpad(ilvlin,4))      0    ' C 3' 'data/c3_34+12lev.dat'
   6    3    25      0   $(lpad(ilvlin,4))      0    ' C 4' 'data/c4.dat'
   6    4     1      1      0          0    ' C 5' ' '
   7    0    34      0   $(lpad(ilvlin,4))      0    ' N 1' 'data/n1.dat'
   7    1    42      0   $(lpad(ilvlin,4))      0    ' N 2' 'data/n2_32+10lev.dat'
   7    2    32      0   $(lpad(ilvlin,4))      0    ' N 3' 'data/n3.dat'
   7    3    48      0   $(lpad(ilvlin,4))      0    ' N 4' 'data/n4_34+14lev.dat'
   7    4    16      0   $(lpad(ilvlin,4))      0    ' N 5' 'data/n5.dat'
   7    5     1      1      0          0    ' N 6' ' '
   8    0    33      0   $(lpad(ilvlin,4))      0    ' O 1' 'data/o1_23+10lev.dat'
   8    1    48      0   $(lpad(ilvlin,4))      0    ' O 2' 'data/o2_36+12lev.dat'
   8    2    41      0   $(lpad(ilvlin,4))      0    ' O 3' 'data/o3_28+13lev.dat'
   8    3    39      0   $(lpad(ilvlin,4))      0    ' O 4' 'data/o4.dat'
   8    4     6      0   $(lpad(ilvlin,4))      0    ' O 5' 'data/o5.dat'
   8    5     1      1      0          0    ' O 6' ' '
   0    0     0     -1      0          0    '    ' ' '
*
* end
"""
end

function ions_fe(ilvlin)
    il = lpad(ilvlin, 4)
    cno = """
   1    0     9      0   $(il)      0    ' H 1' 'data/h1.dat'
   1    1     1      1      0          0    ' H 2' ' '
   2    0    24      0   $(il)      0    'He 1' 'data/he1.dat'
   2    1    20      0   $(il)      0    'He 2' 'data/he2.dat'
   2    2     1      1      0          0    'He 3' ' '
   6    0    40      0   $(il)      0    ' C 1' 'data/c1.dat'
   6    1    22      0   $(il)      0    ' C 2' 'data/c2.dat'
   6    2    46      0   $(il)      0    ' C 3' 'data/c3_34+12lev.dat'
   6    3    25      0   $(il)      0    ' C 4' 'data/c4.dat'
   6    4     1      1      0          0    ' C 5' ' '
   7    0    34      0   $(il)      0    ' N 1' 'data/n1.dat'
   7    1    42      0   $(il)      0    ' N 2' 'data/n2_32+10lev.dat'
   7    2    32      0   $(il)      0    ' N 3' 'data/n3.dat'
   7    3    48      0   $(il)      0    ' N 4' 'data/n4_34+14lev.dat'
   7    4    16      0   $(il)      0    ' N 5' 'data/n5.dat'
   7    5     1      1      0          0    ' N 6' ' '
   8    0    33      0   $(il)      0    ' O 1' 'data/o1_23+10lev.dat'
   8    1    48      0   $(il)      0    ' O 2' 'data/o2_36+12lev.dat'
   8    2    41      0   $(il)      0    ' O 3' 'data/o3_28+13lev.dat'
   8    3    39      0   $(il)      0    ' O 4' 'data/o4.dat'
   8    4     6      0   $(il)      0    ' O 5' 'data/o5.dat'
   8    5     1      1      0          0    ' O 6' ' '
   14   0    45      0   $(il)      0    'Si 1' 'data/si1.t'
   14   1    40      0   $(il)      0    'Si 2' 'data/si2_36+4lev.dat'
   14   2    32      0   $(il)      0    'Si 3' 'data/si3.dat'
   14   3    16      0   $(il)      0    'Si 4' 'data/si4.dat'
   14   4     1      1      0          0    'Si 5' ' '
   16   0    41      0   $(il)      0    ' S 1' 'data/s1.t'
   16   1    33      0   $(il)      0    ' S 2' 'data/s2_23+10lev.dat'
   16   2    41      0   $(il)      0    ' S 3' 'data/s3_29+12lev.dat'
   16   3    38      0   $(il)      0    ' S 4' 'data/s4_33+5lev.dat'
   16   4    25      0   $(il)      0    ' S 5' 'data/s5_20+5lev.dat'
   16   5    10      0   $(il)      0    ' S 6' 'data/s6.dat'
   16   6     1      1      0          0    ' S 7' ' '
   26   0    30      0   $(il)      0    'Fe 1' 'data/fe1.dat'
"""
    if is_ostar
        fe_block = fe_superline(1,36,ilvlin,"Fe 2","fe2va.dat","2601","fe2p_14+11lev.rap") * "\n" *
                   fe_superline(2,50,ilvlin,"Fe 3","fe3va.dat","2602","fe3p_22+7lev.rap")  * "\n" *
                   fe_superline(3,28,ilvlin,"Fe 4","fe4va.dat","2603","fe4p_21+11lev.rap") * "\n" *
                   fe_superline(4,22,ilvlin,"Fe 5","fe5va.dat","2604","fe5p_19+11lev.rap") * "\n" *
                   fe_superline(5,16,ilvlin,"Fe 6","fe6v.dat", "2605","fe6b.rap")          * "\n" *
                   "   26    6     1      1      0          0    'Fe 7' ' '"
    else
        fe_block = fe_superline(1,36,ilvlin,"Fe 2","fe2va.dat","2601","fe2p_14+11lev.rap") * "\n" *
                   fe_superline(2,50,ilvlin,"Fe 3","fe3va.dat","2602","fe3p_22+7lev.rap")  * "\n" *
                   "   26    3     1      1      0          0    'Fe 4' ' '"
    end
    return cno * fe_block * "\n   0    0     0     -1      0          0    '    ' ' '\n*\n* end\n"
end

ions_sp_block = """
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
"""

# ==============================================================================
# WRITE .5 INPUT FILES
# ==============================================================================
name_lt = "mod_lt"; name_nc = "mod_nc"
name_nc_fe = "mod_nc_fe"; name_nl = "mod_nl"; name_sp = "mod_sp"

for (name, T_T, nst, hdr, ions) in [
    (name_lt,    "T  T", "param_lt.nst",    header_cno_2k, ions_cno(100)),
    (name_nc,    "F  F", "param_nc.nst",    header_cno_2k, ions_cno(100)),
    (name_nc_fe, "F  F", "param_nc_fe.nst", header_fe_50k, ions_fe(100)),
    (name_nl,    "F  F", "param_nl.nst",    header_fe_50k, ions_fe(0)),
    (name_sp,    "F  F", "param_sp.nst",    header_fe_50k, ions_sp_block),
]
    open("$name.5", "w") do f
        println(f, "$teff $logg")
        println(f, " $T_T")
        println(f, " '$nst'")
        println(f, hdr)
        println(f, ions)
    end
end

# ==============================================================================
# SYNSPEC SEGMENTS
# ==============================================================================
sp_step  = Float64(cfg["sp_step"])
sp_cutof = Float64(cfg["sp_cutof"])

if !isempty(cfg["segments"])
    segments = cfg["segments"]
elseif is_ostar
    segments = [
        (50.0,  -900.0,   1.0e-2),   # EUV: high relop to reduce line density
        (900.0, -50000.0, 1.0e-4),   # UV-optical-IR: standard relop
    ]
else
    segments = [(500.0, -50000.0, 1.0e-4)]
end

# ==============================================================================
# ENVIRONMENT SETUP
# ==============================================================================
tlusty_path   = get(ENV, "TLUSTY",   "")
linelist_path = get(ENV, "LINELIST", "")
rtlusty_cmd   = isempty(tlusty_path) ? "RTlusty"  : joinpath(tlusty_path, "RTlusty")
rsynspec_cmd  = isempty(tlusty_path) ? "RSynspec" : joinpath(tlusty_path, "RSynspec")

if !isempty(linelist_path) && isfile(joinpath(linelist_path, "gfATO.bin"))
    linelist_file = joinpath(linelist_path, "gfATO.bin"); inlist_val = 1
    println("  Using gfATO.bin (binary, INLIST=1).")
elseif !isempty(linelist_path) && isfile(joinpath(linelist_path, "gfATO.dat"))
    linelist_file = joinpath(linelist_path, "gfATO.dat"); inlist_val = 0
    println("  Using gfATO.dat (text, INLIST=0).")
else
    linelist_file = ""; inlist_val = 0
    println("  WARNING: LINELIST not set or gfATO not found.")
end

println("  SYNSPEC: $(length(segments)) segment(s), step=$(sp_step) Å")
println("Input files generated.")

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================
function clean_data_link()
    (islink("data") || isfile("data") || isdir("data")) && rm("data", force=true)
end

function check_output(name)
    if !isfile("$name.7")
        println("ERROR: $name.7 not found. Check $name.6.")
        cd(".."); exit(1)
    end
    println("   ✓ $name.7 generated.")
end

function check_nan(name)
    ffile = "$name.13"
    if !isfile(ffile)
        println("ERROR: $ffile not found — TLUSTY crashed. Directory preserved.")
        cd(".."); exit(1)
    end
    open(ffile, "r") do f
        for (i, line) in enumerate(eachline(f))
            cols = split(line)
            length(cols) >= 2 || continue
            fs = cols[2]
            if occursin(r"[Nn][Aa][Nn]", fs)
                println("ERROR: NaN in $ffile (line $i). Directory preserved.")
                cd(".."); exit(1)
            end
            v = tryparse(Float64, replace(fs, r"[dD](?=[+-]?\d)" => "e"))
            if v !== nothing && !isfinite(v)
                println("ERROR: Inf in $ffile (line $i). Directory preserved.")
                cd(".."); exit(1)
            end
        end
    end
    println("   ✓ $name.13 — no NaN.")
end

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

function read_synspec(filename)
    lam = Float64[]; flux = Float64[]
    open(filename, "r") do f
        for line in eachline(f)
            cols = split(line)
            length(cols) >= 2 || continue
            l = replace(cols[1], r"([0-9])[Dd]([+-][0-9])" => s"\1e\2")
            h = replace(cols[2], r"([0-9])[Dd]([+-][0-9])" => s"\1e\2")
            lv = tryparse(Float64, l); hv = tryparse(Float64, h)
            (lv === nothing || hv === nothing) && continue
            push!(lam, lv); push!(flux, hv)
        end
    end
    return lam, flux
end

# ==============================================================================
# TLUSTY PIPELINE
# ==============================================================================
println("\nStarting calculations ($star_type)...")

println("\n>> [1/5] LTE (gray atmosphere)...")
clean_data_link()
run(`bash -c "$rtlusty_cmd $name_lt"`)
check_output(name_lt); check_nan(name_lt)

println("\n>> [2/5] NLTE continuum — CNO...")
clean_data_link()
run(`bash -c "$rtlusty_cmd $name_nc $name_lt"`)
check_output(name_nc); check_nan(name_nc)

println("\n>> [3/5] NLTE continuum — Si+S+Fe (Fe blanketing)...")
clean_data_link()
run(`bash -c "$rtlusty_cmd $name_nc_fe $name_nc"`)
check_output(name_nc_fe); check_nan(name_nc_fe)

println("\n>> [4/5] NLTE full lines — final converged model...")
clean_data_link()
run(`bash -c "$rtlusty_cmd $name_nl $name_nc_fe"`)
clean_data_link()
check_output(name_nl); check_nan(name_nl)

# ==============================================================================
# SYNSPEC — MULTI-SEGMENT
# ==============================================================================
println("\n>> [5/5] SYNSPEC...")
clean_data_link()
cp("$name_nl.7", "$name_sp.7", force=true)

all_lam_s = Float64[]; all_hlam_s = Float64[]
all_lam_c = Float64[]; all_hlam_c = Float64[]

for (iseg, (afirst, alast, relop)) in enumerate(segments)
    println("  Segment $iseg/$(length(segments)): $(afirst)–$(abs(alast)) Å (relop=$(relop))...")
    write_fort55(afirst, alast, relop)

    synspec_call = isempty(linelist_file) ?
        "$rsynspec_cmd $name_sp synspec.55" :
        "$rsynspec_cmd $name_sp synspec.55 $linelist_file"

    clean_data_link()
    run(`bash -c "$synspec_call"`)
    clean_data_link()

    (!isfile("$name_sp.spec") || !isfile("$name_sp.cont")) && continue
    lam_s, hlam_s = read_synspec("$name_sp.spec")
    lam_c, hlam_c = read_synspec("$name_sp.cont")
    length(lam_s) < 10 && continue
    println("    → $(length(lam_s)) points ($(round(lam_s[1],digits=1))–$(round(lam_s[end],digits=1)) Å)")

    if !isempty(all_lam_s)
        last = all_lam_s[end]
        ks = lam_s .> last; kc = lam_c .> last
        lam_s = lam_s[ks]; hlam_s = hlam_s[ks]
        lam_c = lam_c[kc]; hlam_c = hlam_c[kc]
    end
    append!(all_lam_s, lam_s); append!(all_hlam_s, hlam_s)
    append!(all_lam_c, lam_c); append!(all_hlam_c, hlam_c)
    rm("$name_sp.spec", force=true); rm("$name_sp.cont", force=true)
end

if length(all_lam_s) < 10000
    println("WARNING: SYNSPEC produced only $(length(all_lam_s)) points total.")
    println("  mod_nl.7 is intact — only SYNSPEC needs to be rerun.")
    cd(".."); exit(1)
end

# ==============================================================================
# RESAMPLE AND SAVE JLD2
# ==============================================================================
println("\nResampling and compressing SED to JLD2...")
step_out = Float64(cfg["step_ang"])
lam_grid = collect(all_lam_s[1]:step_out:all_lam_s[end])

interp(lam, hlam, λ) = let idx = searchsortedfirst(lam, λ)
    idx == 1 ? hlam[1] : idx > length(lam) ? hlam[end] :
    hlam[idx-1] + (hlam[idx]-hlam[idx-1])*(λ-lam[idx-1])/(lam[idx]-lam[idx-1])
end

jldsave("$name_sp.jld2"; compress=true,
    lam       = Float32.(lam_grid),
    hlam_spec = Float32.([interp(all_lam_s, all_hlam_s, λ) for λ in lam_grid]),
    hlam_cont = Float32.([interp(all_lam_c, all_hlam_c, λ) for λ in lam_grid]),
    teff      = Float32(teff),
    logg      = Float32(logg),
    Z         = Float32(Z),
    vtb       = Float32(vtb_val),
    star_type = star_type,
    step_ang  = Float32(step_out),
)

println("   SYNSPEC points: $(length(all_lam_s)) → resampled: $(length(lam_grid)) (step=$(step_out) Å)")
println("   ✓ JLD2 saved.")

cd("..")
println("\n==> SUCCESS: $dir_name")
println("    TLUSTY model → $dir_name/$name_nl.7")
println("    Detailed SED → $dir_name/$name_sp.jld2")
println("    Keys: lam, hlam_spec, hlam_cont, teff, logg, Z, vtb, star_type, step_ang")
