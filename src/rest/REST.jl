module REST
import ..Pluto: ServerSession, Notebook, NotebookTopology, Cell, FunctionName, WorkspaceManager, where_assigned, where_referenced, update_save_run!, topological_order
import Pluto.PlutoRunner
import UUIDs: UUID

WYSIWYR_VERSION = "v1"

"Return the given cells, and all cells that depend on them (recursively)."
function downstream_recursive(notebook::Notebook, topology::NotebookTopology, from::Union{Vector{Cell},Set{Cell}})
    found = Set{Cell}(copy(from))
    downstream_recursive!(found, notebook, topology, from)
    found
end

function downstream_recursive!(found::Set{Cell}, notebook::Notebook, topology::NotebookTopology, from::Vector{Cell})
    for cell in from
        one_down = where_referenced(notebook, topology, cell)
        for next in one_down
            if next ∉ found
                push!(found, next)
                downstream_recursive!(found, notebook, topology, Cell[next])
            end
        end
    end
end


"Return all cells that are depended upon by any of the given cells."
function upstream_recursive(notebook::Notebook, topology::NotebookTopology, from::Union{Vector{Cell},Set{Cell}})
    found = Set{Cell}(copy(from))
    upstream_recursive!(found, notebook, topology, from)
    found
end

function upstream_recursive!(found::Set{Cell}, notebook::Notebook, topology::NotebookTopology, from::Vector{Cell})
    for cell in from
        references = topology.nodes[cell].references
        for upstream in where_assigned(notebook, topology, references)
            if upstream ∉ found
                push!(found, upstream)
                upstream_recursive!(found, notebook, topology, Cell[upstream])
            end
        end
    end
end

function direct_parents(notebook::Notebook, topology::NotebookTopology, node::Cell)
    filter(notebook.cells) do cell
        any(x ∈ topology.nodes[node].references for x ∈ topology.nodes[cell].definitions)
    end
end

function recursive_parents(notebook::Notebook, topology::NotebookTopology, node::Cell)
    parents = Set{Cell}([node])
    
    for parent_cell ∈ direct_parents(notebook, topology, node)
        parents = parents ∪ recursive_parents(notebook, topology, parent_cell)
    end

    parents
end
function recursive_parents(notebook::Notebook, topology::NotebookTopology, nodes::Vector{Cell})
    if length(nodes) == 0
        return []
    end

    reduce(∪, (x -> recursive_parents(notebook, topology, x)).(nodes))
end

function upstream_roots(notebook::Notebook, topology::NotebookTopology, from::Cell)
    found = Set{Cell}()
    parents = direct_parents(notebook, topology, from)

    for p ∈ parents
        if length(direct_parents(notebook, topology, p)) == 0
            found = found ∪ Set([p])
        else
            found = found ∪ upstream_roots(notebook, topology, p)
        end
    end

    found
end
function upstream_roots(notebook::Notebook, topology::NotebookTopology, from::Union{Vector{Cell}, Set{Cell}})
    reduce(∪, (x->upstream_roots(notebook, topology, x)).(from))
end

function get_notebook_output(session::ServerSession, notebook::Notebook, topology::NotebookTopology, inputs::Dict{Symbol, Any}, outputs::Set{Symbol})
    to_set, new_values = keys(inputs), values(inputs)
    output_cell = where_assigned(notebook, topology, outputs)

    if length(output_cell) < length(outputs)
        throw(ErrorException("A requested output does not exist"))
    end
    # For now only one output cell is supported
    output_cell = output_cell[1]

    intersection_path = upstream_recursive(notebook, topology, Cell[output_cell])

    to_reeval = Cell[
        # Re-evaluate all cells that reference the modified input parameters
        where_referenced(notebook, notebook.topology, Set{Symbol}(to_set))...,
    ]

    function custom_deletion_hook((session, notebook)::Tuple{ServerSession,Notebook}, to_delete_vars::Set{Symbol}, funcs_to_delete::Set{Tuple{UUID,FunctionName}}, to_reimport::Set{Expr}; to_run::AbstractVector{Cell})
        to_delete_vars = Set{Symbol}([to_delete_vars..., to_set...]) # also delete the bound symbols
        WorkspaceManager.delete_vars((session, notebook), to_delete_vars, funcs_to_delete, to_reimport)
        for (sym, new_value) in zip(to_set, new_values)
            WorkspaceManager.eval_in_workspace((session, notebook), :($(sym) = $(new_value)))
        end
    end

    update_save_run!(session, notebook, to_reeval; deletion_hook=custom_deletion_hook, dependency_mod=Cell[intersection_path...], run_async=false, save=false)
    out = Dict(out_symbol => WorkspaceManager.eval_fetch_in_workspace((session, notebook), out_symbol) for out_symbol in outputs)
    update_save_run!(session, notebook, where_assigned(notebook, notebook.topology, Set{Symbol}(to_set)); dependency_mod=Cell[intersection_path...])

    out
end
get_notebook_output(session::ServerSession, notebook::Notebook, topology::NotebookTopology, inputs::Dict{Symbol, Any}, outputs::Vector{Symbol}) = get_notebook_output(session, notebook, topology, inputs, Set(outputs))

#fn_result = REST.get_notebook_call(session, notebook, fn_name, args, kwargs)
function get_notebook_call(session::ServerSession, notebook::Notebook, name::Symbol, args, kwargs)
    fn_symbol = :($(name)($(args...); $([:($k=$v) for (k, v) ∈ kwargs]...)))
    return WorkspaceManager.eval_fetch_in_workspace((session, notebook), fn_symbol)
end

function get_notebook_static_function(session::ServerSession, notebook::Notebook, topology::NotebookTopology, inputs::Vector{Symbol}, outputs::Vector{Symbol})
    output_cells = where_assigned(notebook, topology, Set(outputs))
    output_cell = output_cells[1]
    
    input_cells = (input -> where_assigned(notebook, topology, Set([input]))[1]).(inputs)

    function_name = Symbol("eval_" * string(outputs[1]))
    function_params = (x -> Expr(:kw, :($x), WorkspaceManager.eval_fetch_in_workspace((session, notebook), x))).(inputs)

    necessary_cells = recursive_parents(notebook, topology, output_cell)

    cell_ordering = topological_order(notebook, topology, [necessary_cells..., output_cell])

    cell_expressions = (cell -> Meta.parse(cell.code)).(filter(cell_ordering.runnable) do cell
        (cell ∈ necessary_cells && cell ∉ input_cells) || cell ∈ output_cells
    end)

    :(
        function $function_name($(function_params...))
            $(cell_expressions...)
        end
    )
end

end


PlutoNotebook = PlutoRunner.PlutoNotebook
PlutoNotebookWithArgs = PlutoRunner.PlutoNotebookWithArgs

macro resolve(notebook, inputs, output)
    :(
        eval(REST.static_function($(esc(output)), [$(esc(inputs))...], Base.getfield($(esc(notebook)), :filename), Base.getfield($(esc(notebook)), :host)))
    )
end
