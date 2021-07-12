"""
Gets a dictionary of all symbols and the respective cells which are dependent on the given cell.

Changes in the given cell cause re-evaluation of these cells.
Note that only direct dependents are given here, not indirect dependents.
"""
function downstream_cells_map(cell::Cell, notebook::Notebook)::Dict{Symbol,Vector{Cell}}
    defined_symbols = let node = notebook.topology.nodes[cell]
        node.definitions ∪ node.funcdefs_without_signatures
    end
    return Dict{Symbol,Vector{Cell}}(
        sym => where_referenced(notebook, notebook.topology, Set([sym]))
        for sym in defined_symbols
    )
end

"""
Gets a dictionary of all symbols and the respective cells on which the given cell depends.

Changes in these cells cause re-evaluation of the given cell.
Note that only direct dependencies are given here, not indirect dependencies.
"""
function upstream_cells_map(cell::Cell, notebook::Notebook)::Dict{Symbol,Vector{Cell}}
    referenced_symbols = notebook.topology.nodes[cell].references
    return Dict{Symbol,Vector{Cell}}(
        sym => where_assigned(notebook, notebook.topology, Set([sym]) )
        for sym in referenced_symbols
    )
end

"Checks whether or not the cell references user-defined macrocalls"
function contains_user_defined_macrocalls(cell::Cell, notebook::Notebook)::Bool
    calls = notebook.topology.nodes[cell].macrocalls
    !isempty(calls) && any(notebook.cells) do other
        !disjoint(notebook.topology.nodes[other].funcdefs_without_signatures, calls)
    end
end

"Fills cell dependency information for display in the GUI"
function update_dependency_cache!(cell::Cell, notebook::Notebook)
    cell.cell_dependencies = CellDependencies(
        downstream_cells_map(cell, notebook), 
        upstream_cells_map(cell, notebook), 
        cell_precedence_heuristic(notebook.topology, cell),
        contains_user_defined_macrocalls(cell, notebook)
    )
end

"Fills dependency information on notebook and cell level."
function update_dependency_cache!(notebook::Notebook)
    notebook._cached_topological_order = topological_order(notebook)
    for cell in values(notebook.cells_dict)
        update_dependency_cache!(cell, notebook)
    end
end
