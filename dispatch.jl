include("main.jl")

simulate_until_safeword(; bounce=true, id=parse(Int, ARGS[1]))
