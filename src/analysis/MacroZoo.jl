module MacroZoo

"Given a macro's name and its arguments, this may return a new list of arguments
for use by Pluto's expression explorer. Or `nothing`, if not recogniased / confusing."
function expand(func, expr...)
    length(func) > 0 || return nothing
    if func[end] in query_list
        [query_expand(expr...)]
    elseif func[end] in einsum_list
        [einsum_expand(expr...)]
    elseif func[end] in reduce_list
        reduce_expand(expr...)
    else
        nothing
    end
end

###
# THE ZOO
###

query_list = map(Symbol, [
    # https://www.queryverse.org/Query.jl/stable/standalonequerycommands/
    "@map",
    "@filter",
    "@groupby",
    "@orderby",
    "@orderby_descending",
    "@thenby",
    "@thenby_descending",
    "@groupjoin",
    "@join",
    "@mapmany",
    "@take",
    "@drop",
    "@unique",
    "@select",
    "@rename",
    "@mutate",
    "@dropna",
    "@dissallowna",
    "@replacena",
    # https://www.queryverse.org/Query.jl/stable/linqquerycommands/
    "@let",
    "@from",
    "@group",
    "@where",
    "@select",
    "@collect",
    ])

query_expand(exs...) = 0

einsum_list = map(Symbol, [
    "@einsum", "@einsimd", "@vielsum", "@vielsimd", # Einsum.jl
    "@tensor", "@tensoropt", # TensorOperations.jl
    "@cast", # TensorCast.jl
    "@ein", # OMEinsum.jl
    "@tullio", # Tullio.jl
    ])

function einsum_expand(exs...)
    for ex in exs
        # this assumes that only one expression is of interest
        ex isa Expr || continue
        if ex.head == :(:=)  # then this is assignment
            left = einsum_name(ex.args[1])
            left === nothing && return nothing
            return Expr(:(=), left, einsum_undummy(ex.args[2]))
        elseif ex.head in vcat(:(=), modifiers) && einsum_hasref(ex)
            # then either scalar assignment, or in-place
            return einsum_undummy(ex)
        end
        # ignore other expressions, including e.g. keyword options
    end
    nothing
end

einsum_name(s::Symbol) = s
einsum_name(ex::Expr) = ex.head == :(.) ? ex :  # case A.x[i] := ...
    ex.head == :ref ? einsum_name(ex.args[1]) : # allow for A[i][j] := ...
    nothing

# @cast six[n][c, h,w] := npy[n, h,w, c]

einsum_undummy(s, inref=false) = inref ? 0 : s
einsum_undummy(ex::Expr, inref=false) =
    if ex.head == :ref
        # inside indexing, all loose symbols are dummy indices
        args = map(i -> einsum_undummy(i, true), ex.args[2:end])
        Expr(:ref, ex.args[1], args...)
    elseif ex.head == :call
        # function calls keep the function name
        args = map(i -> einsum_undummy(i, inref), ex.args[2:end])
        Expr(:call, ex.args[1], args...)
    elseif ex.head == :$
        # interpted $ as interpolation
        ex.args[1]
    else
        args = map(i -> einsum_undummy(i, inref), ex.args)
        Expr(ex.head, args...)
    end

function einsum_hasref(ex) # this serves to exclude keyword options
    out = false
    postwalk(ex) do x
        if x isa Expr && x.head == :ref
            out = true
        end
        x
    end
    out
end

reduce_list = map(Symbol, ["@reduce", "@matmul"])

reduce_expand(::LineNumberNode, exs...) = reduce_expand(exs...)
function reduce_expand(exs...)
    length(exs) < 2 && return nothing
    ex1, ex2 = exs[1:2]
    ex1 isa Expr && ex2 isa Expr || return nothing
    # first expression is like A[i] := sum(j), treat like @einsum but delete indices
    out1 = if ex1.head == :(:=)
        left = einsum_name(ex1.args[1])
        left === nothing && return nothing
        Expr(:(=), left, einsum_undummy(ex1.args[2], true))
    elseif ex1.head in vcat(:(=), modifiers) || ex1.head == :call # allow @reduce sum(i)
        einsum_undummy(ex, true)
    else
        return nothing
    end
    # second expression is the right hand side, treat as before
    out2 = einsum_undummy(ex2)
    return [out1, out2]
end


###
# HELPER FUNCTIONS
###

# from the source code: https://github.com/JuliaLang/julia/blob/master/src/julia-parser.scm#L9
const modifiers = [:(+=), :(-=), :(*=), :(/=), :(//=), :(^=), :(÷=), :(%=), :(<<=), :(>>=), :(>>>=), :(&=), :(⊻=), :(≔), :(⩴), :(≕)]
const modifiers_dotprefixed = [Symbol('.' * String(m)) for m in modifiers]

# Copied verbatim from here:
# https://github.com/MikeInnes/MacroTools.jl/blob/master/src/utils.jl

walk(x, inner, outer) = outer(x)
walk(x::Expr, inner, outer) = outer(Expr(x.head, map(inner, x.args)...))

"""
    postwalk(f, expr)
Applies `f` to each node in the given expression tree, returning the result.
`f` sees expressions *after* they have been transformed by the walk. See also
`prewalk`.
"""
postwalk(f, x) = walk(x, x -> postwalk(f, x), f)

"""
    prewalk(f, expr)
Applies `f` to each node in the given expression tree, returning the result.
`f` sees expressions *before* they have been transformed by the walk, and the
walk will be applied to whatever `f` returns.
This makes `prewalk` somewhat prone to infinite loops; you probably want to try
`postwalk` first.
"""
prewalk(f, x)  = walk(f(x), x -> prewalk(f, x), identity)

replace(ex, s, s′) = prewalk(x -> x == s ? s′ : x, ex)

end # module
