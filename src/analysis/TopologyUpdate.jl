import .ExpressionExplorer
import .ExpressionExplorer: join_funcname_parts, FunctionNameSignaturePair

function maybe_macroexpand(macroexpand_cb, cell::Cell, expr::Expr, symbol_state)
	if !symbol_state.has_macrocalls
		symbol_state
	else
		# Expand macro calls and re-compute symbol references
		macroexpand_cb(cell, expr) |> ExpressionExplorer.try_compute_symbolreferences
	end
end

identity_y(x, y) = begin x; y end

"Return a copy of `old_topology`, but with recomputed results from `cells` taken into account."
function updated_topology(old_topology::NotebookTopology, notebook::Notebook, cells; macroexpand_cb=identity_y)
	
	updated_codes = Dict{Cell,ExprAnalysisCache}()
	for cell in cells
		if !(
			haskey(old_topology.codes, cell) && 
			old_topology.codes[cell].code === cell.code
		)
			updated_codes[cell] = ExprAnalysisCache(notebook, cell)
		end
	end
	new_codes = merge(old_topology.codes, updated_codes)

	updated_nodes = Dict{Cell,ReactiveNode}(cell => (
			new_codes[cell].parsedcode |> 
			ExpressionExplorer.try_compute_symbolreferences |> 
			symstate -> maybe_macroexpand(macroexpand_cb, cell, new_codes[cell].parsedcode, symstate) |>
			ReactiveNode
		) for cell in cells)

	new_nodes = merge(old_topology.nodes, updated_nodes)

	# DONE (performance): deleted cells should not stay in the topology
	for removed_cell in setdiff(keys(old_topology.nodes), notebook.cells)
		delete!(new_nodes, removed_cell)
		delete!(new_codes, removed_cell)
	end

	NotebookTopology(nodes=new_nodes, codes=new_codes)
end
