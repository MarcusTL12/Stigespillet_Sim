using Base.Threads
using Plots
using OffsetArrays
using Statistics

ladders = [
    1 20
    7 9
    25 29
    32 13
    39 51
    46 41
    65 79
    68 73
    71 35
    77 58
]

cutoff = 200

function make_board(ladders; n=80)
    board = [i for i in 1:n]

    for (a, b) in eachrow(ladders)
        board[a] = b
    end

    board
end

function simulate_game(board; bounce=false)
    pos = 0

    moves = 0

    while pos < length(board)
        pos += rand(1:6)

        if bounce && pos > 80
            pos -= (pos - 80) * 2
        else
            pos = min(pos, length(board))
        end

        pos = board[pos]

        moves += 1
    end

    moves
end

function simulate_average(n)
    board = make_board(ladders)

    tot_moves = 0

    for i in 1:n
        tot_moves += simulate_game(board)
    end

    tot_moves / n
end

function simulate_average_paralell(n; threads=nthreads())
    n = (n ÷ threads) * threads

    counts = [0 for _ in 1:threads]

    @threads for i in 1:threads
        board = make_board(ladders)
        tot_moves = 0

        for _ in 1:(n ÷ threads)
            tot_moves += simulate_game(board)
        end

        counts[i] = tot_moves
    end

    sum(counts) / n
end

function make_hist(data)
    xvals = sort!(collect(keys(data)))
    yvals = [data[x] for x in xvals]

    plot(xvals, yvals; legend=false)
end

function simulate_games(n)
    board = make_board(ladders)

    data = [0]

    for _ in 1:n
        x = simulate_game(board)

        if x > length(data)
            append!(data, 0 for _ in 1:x - length(data))
        end

        data[x] += 1
    end

    data
end

function simulate_histogram(n)
    board = make_board(ladders)

    data = Dict{Int,Int}()

    for _ in 1:n
        x = simulate_game(board)

        if haskey(data, x)
            data[x] += 1
        else
            data[x] = 1
        end
    end

    ndata = Dict(x => data[x] / n for x in keys(data))

    make_hist(ndata)
end

function simulate_game_with_history!(board, history; bounce=false)
    pos = 0

    while pos < length(board)
        pos += rand(1:6)

        if bounce && pos > 80
            pos -= (pos - 80) * 2
        else
            pos = min(pos, length(board))
        end

        pos = board[pos]

        push!(history, pos)
    end
end

function get_all_tile_counts(n; bounce=false)
    board = make_board(ladders)

    counts = OffsetArray([Int[] for _ in 0:80], 0:80)

    history = [0]

    for _ in 1:n
        resize!(history, 1)
        simulate_game_with_history!(board, history; bounce=bounce)

        for i in eachindex(history)
            moves = length(history) - i

            push!(counts[history[i]], moves)
        end
    end

    counts
end

function get_tile_averages_and_stdevs(n)
    counts = get_all_tile_counts(n)

    avgs = [mean(c) for c in counts]
    stds = [std(c) for c in counts]

    collect(avgs), collect(stds)
end

function get_counts(n; bounce=false)
    board = make_board(ladders)

    counts = OffsetArray([0 for _ in 0:80, _ in 0:cutoff], 0:80, 0:cutoff)

    history = [0]

    for _ in 1:n
        resize!(history, 1)
        simulate_game_with_history!(board, history; bounce=bounce)

        for i in eachindex(history)
            moves = length(history) - i

            if moves <= cutoff
                counts[history[i], moves] += 1
            end
        end
    end

    counts
end

function write_matrix_to_file(filename, m)
    open(filename, "w") do io
        print(io, m)
    end
end

function load_matrix(filename)
    OffsetArray(
        Base.Meta.eval(Base.Meta.parse(open(String ∘ read, filename))),
        0:80, 0:cutoff
    )
end

function load_matrices(name, ids)
    sum(load_matrix("$name$id.txt") for id in ids)
end

function simulate_until_safeword(; bounce=false, id=1)
    filename = bounce ? "count_bounce$id.txt" : "count$id.txt"
    if isfile(filename)
        counts = load_matrix(filename)
    else
        counts = get_counts(100_000; bounce=bounce)
    end

    while !isfile("safeword")
        counts .+= get_counts(100_000; bounce=bounce)
        write_matrix_to_file(filename, counts)
    end
end

function get_dist_from_counts(counts)
    dist = [0.0 for _ in counts]

    for i in 0:80
        dist[i, :] = counts[i, :] / sum(counts[i, :])
    end

    dist
end

function plot_2d_dist(dist)
    xs = 0:80
    ys = 0:cutoff
    f(x, y) = dist[x, y]

    plot(xs, ys, f; st=:surface)
end

function prob_fewer(dist, pos, max_moves)
    if max_moves <= 0
        0.0
    else
        sum(dist[pos, moves] for moves in 0:max_moves)
    end
end

function prob_win(dist, you, other_pos, you_first)
    sum(
        prob_fewer(dist, you, moves - !you_first) * dist[other_pos, moves]
        for moves in 0:cutoff
    )
end

function prob_fewer_than_all(dist, you, others)
    prob = 0.0

    for a_moves in 0:cutoff
        a_prob = dist[you, a_moves]
        for (pos, equal) in others
            b_prob = 0.0
            for b_moves in a_moves + (equal ? 0 : 1):cutoff
                b_prob += dist[pos, b_moves]
            end
            a_prob *= b_prob
        end
        prob += a_prob
    end

    prob
end

function prob_win_all(dist, queue)
    n = length(queue)
    
    current = popfirst!(queue)
    rest = [(x, true) for x in queue]

    probs = Float64[]

    for _ in 1:n - 1
        push!(probs, prob_fewer_than_all(dist, current, rest))

        push!(rest, (current, false))
        current, _ = popfirst!(rest)
    end

    push!(probs, 1 - sum(probs))

    probs
end
