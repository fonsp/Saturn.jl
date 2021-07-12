import Pluto
import Pluto.ExpressionExplorer
import Pluto.ExpressionExplorer: SymbolsState, compute_symbolreferences, FunctionNameSignaturePair, UsingsImports, compute_usings_imports
using Test

function Base.show(io::IO, s::SymbolsState)
    print(io, "SymbolsState([")
    join(io, s.references, ", ")
    print(io, "], [")
    join(io, s.assignments, ", ")
    print(io, "], [")
    join(io, s.funccalls, ", ")
    print(io, "], [")
    if isempty(s.funcdefs)
        print(io, "]")
    else
        println(io)
        for (k, v) in s.funcdefs
            print(io, "    ", k, ": ", v)
            println(io)
        end
        print(io, "]")
    end
    print(io, "], [")
    print(io, s.macrocalls)
    print(io, "])")
end

"Calls `ExpressionExplorer.compute_symbolreferences` on the given `expr` and test the found SymbolsState against a given one, with convient syntax.

# Example

```jldoctest
julia> @test testee(:(
    begin
        a = b + 1
        f(x) = x / z
    end),
    [:b, :+], # 1st: expected references
    [:a, :f], # 2nd: expected definitions
    [:+],     # 3rd: expected function calls
    [
        :f => ([:z, :/], [], [:/], [])
    ])        # 4th: expected function definitions, with inner symstate using the same syntax
true
```
"
function testee(expr, expected_references, expected_definitions, expected_funccalls, expected_funcdefs, expected_macrocalls = []; verbose::Bool=true)
    expected = easy_symstate(expected_references, expected_definitions, expected_funccalls, expected_funcdefs, expected_macrocalls)

    original_hash = Pluto.PlutoRunner.expr_hash(expr)
    result = compute_symbolreferences(expr)
    new_hash = Pluto.PlutoRunner.expr_hash(expr)
    if original_hash != new_hash
        error("\n== The expression explorer modified the expression. Don't do that! ==\n")
    end

    # Anonymous function are given a random name, which looks like anon67387237861123
    # To make testing easier, we rename all such functions to anon
    new_name(sym) = startswith(string(sym), "anon") ? :anon : sym

    result.assignments = Set(new_name.(result.assignments))
    result.funcdefs = let
        newfuncdefs = Dict{FunctionNameSignaturePair,SymbolsState}()
        for (k, v) in result.funcdefs
            union!(newfuncdefs, Dict(FunctionNameSignaturePair(new_name.(k.name), "hello") => v))
        end
        newfuncdefs
    end

    if verbose && expected != result
        println()
        println("FAILED TEST")
        println(expr)
        println()
        dump(expr, maxdepth=20)
        println()
        @show expected
        resulted = result
        @show resulted
        println()
    end
    return expected == result
end

function easy_symstate(expected_references, expected_definitions, expected_funccalls, expected_funcdefs, expected_macrocalls = [])
    array_to_set(array) = map(array) do k
        new_k = k isa Symbol ? [k] : k
        return new_k
    end |> Set
    new_expected_funccalls = array_to_set(expected_funccalls)
    
    new_expected_funcdefs = map(expected_funcdefs) do (k, v)
        new_k = k isa Symbol ? [k] : k
        new_v = v isa SymbolsState ? v : easy_symstate(v...)
        return FunctionNameSignaturePair(new_k, "hello") => new_v
    end |> Dict

    new_expected_macrocalls = array_to_set(expected_macrocalls)

    SymbolsState(Set(expected_references), Set(expected_definitions), new_expected_funccalls, new_expected_funcdefs, new_expected_macrocalls)
end

function setcode(cell, newcode)
    cell.code = newcode
end

function noerror(cell)
    if cell.errored
        @show cell.output.body
    end
    !cell.errored
end

function occursinerror(needle, haystack::Pluto.Cell)
    haystack.errored && occursin(needle, haystack.output.body[:msg])
end

"Test notebook equality, ignoring cell UUIDs and such."
function notebook_inputs_equal(nbA, nbB; check_paths_equality=true)
    x = !check_paths_equality || (normpath(nbA.path) == normpath(nbB.path))

    to_compare(cell) = (cell.cell_id, cell.code_folded, cell.code)
    y = to_compare.(nbA.cells) == to_compare.(nbB.cells)
    
    x && y
end

"Whether the given .jl file can be run without any errors. While notebooks cells can be in arbitrary order, their order in the save file must be topological.

If `only_undefvar` is `true`, all errors other than an `UndefVarError` will be ignored."
function jl_is_runnable(path; only_undefvar=false)
    🔖 = Symbol("lab", time_ns())
    🏡 = Core.eval(Main, :(module $(🔖) end))
    try
        Core.eval(🏡, :(include($path)))
        true
    catch ex
        if (!only_undefvar) || ex isa UndefVarError || (ex isa LoadError && ex.error isa UndefVarError)
            println(stderr, "\n$(path) failed to run. File contents:")

            println(stderr, "\n\n\n")
            println.(enumerate(readlines(path; keep=true)))
            println(stderr, "\n\n\n")

            showerror(stderr, ex, stacktrace(catch_backtrace()))
            println(stderr)
            false
        else
            true
        end
    end
end

"Whether the `notebook` runs without errors."
function nb_is_runnable(session::Pluto.ServerSession, notebook::Pluto.Notebook)
    Pluto.update_run!(session, notebook, notebook.cells)
    errored = filter(c -> c.errored, notebook.cells)
    if !isempty(errored)
        @show errored
    end
    isempty(errored)
end

"The converse of Julia's `Base.sprint`."
function sread(f::Function, input::String, args...)
    io = IOBuffer(input)
    output = f(io, args...)
    close(io)
    return output
end

function num_backups_in(dir::AbstractString)
    count(readdir(dir)) do fn
        occursin("backup", fn)
    end
end

has_embedded_pkgfiles(contents::AbstractString) = 
    occursin("PROJECT", contents) && occursin("MANIFEST", contents)

has_embedded_pkgfiles(nb::Pluto.Notebook) = 
    read(nb.path, String) |> has_embedded_pkgfiles