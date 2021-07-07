# NOTE: This file is included in runner/PlutoRunner.jl
module REST


# TODO: Find a way to do this dynamically so we don't need to load this for every Pluto notebook
import HTTP
import Serialization


function static_function(output::Symbol, inputs::Vector{Symbol}, filename::AbstractString, host::AbstractString="localhost:1234")
    @warn "Ensure you trust this host, as the function returned could be malicious"

    query = ["outputs" => String(output), "inputs" => join(inputs, ",")]
    request_uri = merge(HTTP.URI("http://$(host)/v1/notebook/$filename/static"); query=query)
    response = HTTP.get(request_uri)

    Meta.parse(String(response.body))
end

"""
    evaluate(output::Symbol, filename::AbstractString, host::AbstractString="localhost:1234"; kwargs...)

Function equivalent of syntax described in documentation for `PlutoNotebook`.

# Examples
**NOTE**: This function should not be used outside of Pluto unless absolutely necessary.
```
julia> Pluto.REST.evaluate(:c, "EuclideanDistance.jl"; a=5., b=12.)
13.0
```
"""
function evaluate(output::Symbol, filename::AbstractString, host::AbstractString="localhost:1234"; kwargs...)
    request_uri = HTTP.URI("http://$(host)/v1/notebook/$(HTTP.escapeuri(filename))/eval")

    body = IOBuffer()
    Serialization.serialize(body, Dict{String, Any}(
        "outputs" => [output],
        "inputs" => Dict(kwargs)
    ))
    serialized_body = take!(body)

    response = HTTP.request("POST", request_uri, [
        "Accept" => "application/x-julia",
        "Content-Type" => "application/x-julia"
    ], serialized_body; status_exception=false)

    if response.status >= 300
        throw(ErrorException(String(response.body)))
    end

    return Serialization.deserialize(IOBuffer(response.body))[output]
end

"""
    call(fn_name::Symbol, args::Tuple, kwargs::Iterators.Pairs, filename::AbstractString, host::AbstractString="localhost:1234")

Function equivalent of syntax described in documentation for `PlutoCallable`.
"""
function call(fn_name::Symbol, args::Tuple, kwargs::Iterators.Pairs, filename::AbstractString, host::AbstractString="localhost:1234")
    request_uri = HTTP.URI("http://$(host)/v1/notebook/$(HTTP.escapeuri(filename))/call")

    body = IOBuffer()
    Serialization.serialize(body, Dict{String, Any}(
        "function" => fn_name,
        "args" => [args...],
        "kwargs" => Dict(kwargs...)
    ))
    serialized_body = take!(body)

    response = HTTP.request("POST", request_uri, [
        "Accept" => "application/x-julia",
        "Content-Type" => "application/x-julia"
    ], serialized_body; status_exception=false)

    if response.status >= 300
        throw(ErrorException(String(response.body)))
    end
    
    return Serialization.deserialize(IOBuffer(response.body))
end
end

"""
    PlutoNotebook(filename::AbstractString, host::AbstractString="localhost:1234")

Reference a Pluto notebook running on a Pluto server somewhere.

# Examples
```julia-repl
julia> nb = PlutoNotebook("EuclideanDistance.jl");

julia> nb.c
5.0

julia> nb(; a=5., b=12.).c
13.0
```
"""
struct PlutoNotebook
    host::AbstractString
    filename::AbstractString

    PlutoNotebook(filename::AbstractString, host::AbstractString="localhost:1234") = new(host, filename)
end
function Base.getproperty(notebook::PlutoNotebook, symbol::Symbol)
    Base.getproperty(notebook(), symbol)
end

"""
    PlutoCallable(notebook::PlutoNotebook, name::Symbol)

Reference to a symbol which can be called as a function within a Pluto notebook.

# Examples
Within a Pluto notebook `EuclideanDistance.jl` the following function is defined:

```julia
distance(args...) = sqrt(sum(args .^ 2))
```

From elsewhere the `PlutoCallable` structure can be called as a function in itself. It will return the same value which is returned by the referenced function.

```julia-repl
julia> nb = PlutoNotebook("EuclideanDistance.jl");

julia> nb.distance
Pluto.PlutoCallable(PlutoNotebook("localhost:1234", "EuclideanDistance.jl"), :distance)

julia> nb.distance(5., 12.)
13.0
```
"""
struct PlutoCallable
    notebook::PlutoNotebook
    name::Symbol
end
function (callable::PlutoCallable)(args...; kwargs...)
    REST.call(callable.name, args, kwargs, Base.getfield(callable.notebook, :filename), Base.getfield(callable.notebook, :host))
end

"""
    PlutoNotebookWithArgs(notebook::PlutoNotebook, kwargs::Dict{Symbol, Any})

An intermediate structure which is returned when one calls a `PlutoNotebook` as a function. Holds `kwargs` to be passed to a Pluto server after requesting an output with `getproperty(::PlutoNotebookWithArgs, symbol::Symbol)`.

# Examples
```julia-repl
julia> nb = PlutoNotebook("EuclideanDistance.jl");

julia> nb_withargs = nb(; a=5., b=12.)
Pluto.PlutoNotebookWithArgs(PlutoNotebook("localhost:1234", "EuclideanDistance.jl"), Dict{Symbol, Any}(:a => 5.0, :b => 12.0))

julia> nb_withargs.c
13.0
```
Note that this is **not** recommended syntax because it separates the "parameters" from the desired output of your notebook. Rather, perform both steps at once like the following example:
```julia
nb(; a=5., b=12.).c  # Notice that parameters are provided and an output is requested in one step rather than two
```
"""
struct PlutoNotebookWithArgs
    notebook::PlutoNotebook
    kwargs::Dict{Symbol, Any}
end

# Looks like notebook_instance(a=3, b=4)
function (nb::PlutoNotebook)(; kwargs...)
    PlutoNotebookWithArgs(nb, Dict{Symbol, Any}(kwargs))
end
# Looks like notebook_instance(a=3, b=4).c ⟹ 5
function Base.getproperty(with_args::PlutoNotebookWithArgs, symbol::Symbol)
    try
        return REST.evaluate(symbol, Base.getfield(Base.getfield(with_args, :notebook), :filename), Base.getfield(Base.getfield(with_args, :notebook), :host); Base.getfield(with_args, :kwargs)...)
    catch e
        if hasfield(typeof(e), :msg) && contains(e.msg, "function") # See if the function error was thrown, and return a PlutoCallable struct
            return PlutoCallable(Base.getfield(with_args, :notebook), symbol)
        end
        throw(e)
    end
end
# Looks like notebook_instance(a=3, b=4)[:c, :m] ⟹ 5
function Base.getindex(with_args::PlutoNotebookWithArgs, symbols::Symbol...)
    outputs = []

    # TODO: Refactor to make 1 request with multiple output symbols
    for symbol ∈ symbols
        push!(outputs, REST.evaluate(symbol, Base.getfield(Base.getfield(with_args, :notebook), :filename), Base.getfield(Base.getfield(with_args, :notebook), :host); Base.getfield(with_args, :kwargs)...))
    end

    # https://docs.julialang.org/en/v1/base/base/#Core.NamedTuple
    return (; zip(symbols, outputs)...)
end
