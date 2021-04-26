import REPL:ends_with_semicolon
import .Configuration
import .ExpressionExplorer: FunctionNameSignaturePair, is_joined_funcname, UsingsImports, external_package_names

Base.push!(x::Set{Cell}) = x

"Run given cells and all the cells that depend on them, based on the topology information before and after the changes."
function run_reactive!(session::ServerSession, notebook::Notebook, old_topology::NotebookTopology, new_topology::NotebookTopology, cells::Vector{Cell}; deletion_hook::Function=WorkspaceManager.delete_vars, persist_js_state::Bool=false)::TopologicalOrder
	# make sure that we're the only `run_reactive!` being executed - like a semaphor
	take!(notebook.executetoken)

	removed_cells = setdiff(keys(old_topology.nodes), keys(new_topology.nodes))
	cells = Cell[cells..., removed_cells...]

	# by setting the reactive node and expression caches of deleted cells to "empty", we are essentially pretending that those cells still exist, but now have empty code. this makes our algorithm simpler.
	new_topology = NotebookTopology(
		nodes=merge(
			new_topology.nodes,
			Dict(cell => ReactiveNode() for cell in removed_cells),
		),
		codes=merge(
			new_topology.codes,
			Dict(cell => ExprAnalysisCache() for cell in removed_cells)
		)
	)

	# save the old topological order - we'll delete variables assigned from it and re-evalutate its cells
	old_order = topological_order(notebook, old_topology, cells)

	old_runnable = old_order.runnable
	to_delete_vars = union!(Set{Symbol}(), defined_variables(old_topology, old_runnable)...)
	to_delete_funcs = union!(Set{Tuple{UUID,FunctionName}}(), defined_functions(old_topology, old_runnable)...)

	# get the new topological order
	new_order = topological_order(notebook, new_topology, union(cells, keys(old_order.errable)))
	to_run = setdiff(union(new_order.runnable, old_order.runnable), keys(new_order.errable))::Vector{Cell} # TODO: think if old error cell order matters


	# change the bar on the sides of cells to "queued"
	for cell in to_run
		cell.queued = true
	end
	for (cell, error) in new_order.errable
		cell.running = false
		cell.queued = false
		relay_reactivity_error!(cell, error)
	end

	# Send intermediate updates to the clients at most 20 times / second during a reactive run. (The effective speed of a slider is still unbounded, because the last update is not throttled.)
	# flush_send_notebook_changes_throttled, 
	send_notebook_changes_throttled, flush_notebook_changes = throttled(1.0 / 20) do
		send_notebook_changes!(ClientRequest(session=session, notebook=notebook))
	end
	send_notebook_changes_throttled()

	# delete new variables that will be defined by a cell
	new_runnable = new_order.runnable
	to_delete_vars = union!(to_delete_vars, defined_variables(new_topology, new_runnable)...)
	to_delete_funcs = union!(to_delete_funcs, defined_functions(new_topology, new_runnable)...)

	# delete new variables in case a cell errors (then the later cells show an UndefVarError)
	new_errable = keys(new_order.errable)
	to_delete_vars = union!(to_delete_vars, defined_variables(new_topology, new_errable)...)
	to_delete_funcs = union!(to_delete_funcs, defined_functions(new_topology, new_errable)...)

	to_reimport = union(Set{Expr}(), map(c -> new_topology.codes[c].module_usings_imports.usings, setdiff(notebook.cells, to_run))...)

	deletion_hook((session, notebook), to_delete_vars, to_delete_funcs, to_reimport; to_run=to_run) # `deletion_hook` defaults to `WorkspaceManager.delete_vars`

	delete!.([notebook.bonds], to_delete_vars)

	local any_interrupted = false
	for (i, cell) in enumerate(to_run)
		
		cell.queued = false
		cell.running = true
		empty!(cell.logs)
		send_notebook_changes_throttled()
		
		if any_interrupted || notebook.wants_to_interrupt
			relay_reactivity_error!(cell, InterruptException())
		else
			run = run_single!(
				(session, notebook), cell, 
				new_topology.nodes[cell], new_topology.codes[cell]; 
				persist_js_state=(persist_js_state || cell ∉ cells)
			)
			any_interrupted |= run.interrupted
		end
		
		cell.running = false
	end
	
	notebook.wants_to_interrupt = false
	flush_notebook_changes()
	# allow other `run_reactive!` calls to be executed
	put!(notebook.executetoken)
	return new_order
end

run_reactive_async!(session::ServerSession, notebook::Notebook, to_run::Vector{Cell}; kwargs...) = run_reactive_async!(session, notebook, notebook.topology, notebook.topology, to_run; kwargs...)

function run_reactive_async!(session::ServerSession, notebook::Notebook, old::NotebookTopology, new::NotebookTopology, to_run::Vector{Cell}; run_async::Bool=true, kwargs...)
	run_task = @async begin
		run_reactive!(session, notebook, old, new, to_run; kwargs...)
	end
	if run_async
		run_task
	else
		fetch(run_task)
	end
end

const lazymap = Base.Generator

function defined_variables(topology::NotebookTopology, cells)
	lazymap(cells) do cell
		topology.nodes[cell].definitions
	end
end

function defined_functions(topology::NotebookTopology, cells)
	lazymap(cells) do cell
		((cell.cell_id, namesig.name) for namesig in topology.nodes[cell].funcdefs_with_signatures)
	end
end

"Run a single cell non-reactively, set its output, return run information."
function run_single!(session_notebook::Union{Tuple{ServerSession,Notebook},WorkspaceManager.Workspace}, cell::Cell, reactive_node::ReactiveNode, expr_cache::ExprAnalysisCache; persist_js_state::Bool=false)
	run = WorkspaceManager.eval_format_fetch_in_workspace(
		session_notebook, 
		expr_cache.parsedcode, 
		cell.cell_id, 
		ends_with_semicolon(cell.code), 
		expr_cache.function_wrapped ? (filter(!is_joined_funcname, reactive_node.references), reactive_node.definitions) : nothing
	)
	set_output!(cell, run, expr_cache; persist_js_state=persist_js_state)
	if session_notebook isa Tuple && run.process_exited
		session_notebook[2].process_status = ProcessStatus.no_process
	end
	return run
end

function set_output!(cell::Cell, run, expr_cache::ExprAnalysisCache; persist_js_state::Bool=false)
	cell.output = CellOutput(
		body=run.output_formatted[1],
		mime=run.output_formatted[2],
		rootassignee=ends_with_semicolon(expr_cache.code) ? nothing : ExpressionExplorer.get_rootassignee(expr_cache.parsedcode),
		last_run_timestamp=time(),
		persist_js_state=persist_js_state,
	)
	cell.runtime = run.runtime
	cell.errored = run.errored
end

will_run_code(notebook::Notebook) = notebook.process_status != ProcessStatus.no_process && notebook.process_status != ProcessStatus.waiting_to_restart

###
# CONVENIENCE FUNCTIONS
###

"Do all the things!"
function update_save_run!(session::ServerSession, notebook::Notebook, cells::Array{Cell,1}; save::Bool=true, run_async::Bool=false, prerender_text::Bool=false, kwargs...)
	old = notebook.topology
	new = notebook.topology = updated_topology(old, notebook, cells)

	update_dependency_cache!(notebook)

	session.options.server.disable_writing_notebook_files || save_notebook(notebook)

	# _assume `prerender_text == false` if you want to skip some details_

	to_run_online = if !prerender_text
		cells
	else
		# this code block will run cells that only contain text offline, i.e. on the server process, before doing anything else
		# this makes the notebook load a lot faster - the front-end does not have to wait for each output, and perform costly reflows whenever one updates
		# "A Workspace on the main process, used to prerender markdown before starting a notebook process for speedy UI."
		original_pwd = pwd()
		offline_workspace = WorkspaceManager.make_workspace(
			(
				ServerSession(),
				notebook,
			),
			force_offline=true,
		)

		to_run_offline = filter(c -> !c.running && is_just_text(new, c) && is_just_text(old, c), cells)
		for cell in to_run_offline
			run_single!(offline_workspace, cell, new.nodes[cell], new.codes[cell])
		end
		
		cd(original_pwd)
		setdiff(cells, to_run_offline)
	end

	if !(isempty(to_run_online) && session.options.evaluation.lazy_workspace_creation) && will_run_code(notebook)
		run_reactive_async!(session, notebook, old, new, to_run_online; run_async=run_async, kwargs...)
	end
end

update_save_run!(session::ServerSession, notebook::Notebook, cell::Cell; kwargs...) = update_save_run!(session, notebook, [cell]; kwargs...)
update_run!(args...) = update_save_run!(args...; save=false)



"""
	throttled(f::Function, timeout::Real)

Return a function that when invoked, will only be triggered at most once
during `timeout` seconds.
The throttled function will run as much as it can, without ever
going more than once per `wait` duration.
Inspired by FluxML
See: https://github.com/FluxML/Flux.jl/blob/8afedcd6723112ff611555e350a8c84f4e1ad686/src/utils.jl#L662
"""
function throttled(f::Function, timeout::Real)
	tlock = ReentrantLock()
	iscoolnow = false
	run_later = false

	function flush()
		lock(tlock) do
			run_later = false
			f()
		end
	end

	function schedule()
		@async begin
			sleep(timeout)
			if run_later
				flush()
			end
			iscoolnow = true
		end
	end
	schedule()

	function throttled_f()
		if iscoolnow
			iscoolnow = false
			flush()
			schedule()
		else
			run_later = true
		end
	end

	return throttled_f, flush
end



