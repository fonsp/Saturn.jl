import Base: showerror
import .ExpressionExplorer: FunctionName, join_funcname_parts

abstract type ReactivityError <: Exception end

struct CyclicReferenceError <: ReactivityError
	syms::Set{Symbol}
end

function CyclicReferenceError(topology::NotebookTopology, cycle::Cell...)
	referenced_during_cycle = union((topology[c].references for c in cycle)...)
	assigned_during_cycle = union((topology[c].definitions_without_signatures for c in cycle)...)
	
	CyclicReferenceError(referenced_during_cycle ∩ assigned_during_cycle)
end


struct MultipleDefinitionsError <: ReactivityError
	syms::Set{Symbol}
end

function MultipleDefinitionsError(topology::NotebookTopology, cell::Cell, all_definers)
	competitors = setdiff(all_definers, [cell])
	MultipleDefinitionsError(
		union((topology[cell].definitions_without_signatures ∩ topology[c].definitions_without_signatures for c in competitors)...)
	)
end

struct FunctionAssignsGlobalError <: ReactivityError
	funcname::FunctionName
	syms::Set{Symbol}
end

function FunctionAssignsGlobalError(topology::NotebookTopology, cell::Cell)
	# TODO

	# namesig, syms = first(filter(p -> !isempty(p.second.assignments), topology[cell].funcdefs))
	# FunctionAssignsGlobalError(
	# 	namesig.name,
	# 	syms.assignments
	# )
end

hint1 = "Combine all definitions into a single reactive cell using a `begin ... end` block."
hint2 = "Wrap all code in a `begin ... end` block."
hint3 = "Functions in a Pluto notebook cannot assign to globals. Instead, initialize the global in another cell as `x = Ref{Any}()`, and then update its value using `x[] = ...`."

# TODO: handle case when cells are in cycle, but variables aren't
function showerror(io::IO, cre::CyclicReferenceError)
	print(io, "Cyclic references among $(join(cre.syms, ", ", " and ")).\n$hint1")
end

function showerror(io::IO, mde::MultipleDefinitionsError)
	print(io, "Multiple definitions for $(join(mde.syms, ", ", " and ")).\n$hint1") # TODO: hint about mutable globals
end

function showerror(io::IO, fage::FunctionAssignsGlobalError)
	print(io, "Function $(join_funcname_parts(fage.funcname)) assigns to global$(length(fage.syms) > 1 ? "s" : "") $(join(fage.syms, ", ", " and ")).\n$hint3")
end

"Send `error` to the frontend without backtrace. Runtime errors are handled by `WorkspaceManager.eval_format_fetch_in_workspace` - this function is for Reactivity errors."
function relay_reactivity_error!(cell::Cell, error::Exception)
	cell.errored = true
	cell.runtime = missing
	cell.output_repr, cell.repr_mime = PlutoRunner.format_output(CapturedException(error, []))
end