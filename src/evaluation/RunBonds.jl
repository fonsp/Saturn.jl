function set_bond_values_reactive(; session::ServerSession, notebook::Notebook, bound_sym_names::AbstractVector{Symbol}, is_first_value=nothing, kwargs...)
    if is_first_value !== nothing
        @warn "is_first_value is deprecated, you don't need to set it anymore: https://github.com/fonsp/Pluto.jl/pull/975"
    end
    # filter out the bonds that don't need to be set
    to_set = filter(bound_sym_names) do bound_sym
        new_value = notebook.bonds[bound_sym].value
        is_first_value = notebook.bonds[bound_sym].is_first_value

        variable_exists = is_assigned_anywhere(notebook, notebook.topology, bound_sym)
        if !variable_exists
            # a bond was set while the cell is in limbo state
            # we don't need to do anything
            return false
        end

        # TODO: Not checking for any dependents now
        # any_dependents = is_referenced_anywhere(notebook, notebook.topology, bound_sym)

        # fix for https://github.com/fonsp/Pluto.jl/issues/275
        # if `Base.get` was defined to give an initial value (read more about this in the Interactivity sample notebook), then we want to skip the first value sent back from the bond. (if `Base.get` was not defined, then the variable has value `missing`)
        # Check if the variable does not already have that value.
        # because if the initial value is already set, then we don't want to run dependent cells again.
        eq_tester = :(try !ismissing($bound_sym) && ($bound_sym == $new_value) catch; false end) # not just a === comparison because JS might send back the same value but with a different type (Float64 becomes Int64 in JS when it's an integer.)
        if is_first_value && WorkspaceManager.eval_fetch_in_workspace((session, notebook), eq_tester)
            return false
        end
        return true
    end

    if isempty(to_set)
        return
    end

    new_values = [notebook.bonds[bound_sym].value for bound_sym in to_set]
    
    function custom_deletion_hook((session, notebook)::Tuple{ServerSession,Notebook}, old_workspace_name, new_workspace_name, to_delete_vars::Set{Symbol}, methods_to_delete::Set{Tuple{UUID,FunctionName}}, to_reimport::Set{Expr}; to_run::AbstractVector{Cell})
        to_delete_vars = Set([to_delete_vars..., to_set...]) # also delete the bound symbols
        WorkspaceManager.move_vars((session, notebook), old_workspace_name, new_workspace_name, to_delete_vars, methods_to_delete, to_reimport)
        for (bound_sym, new_value) in zip(to_set, new_values)
            WorkspaceManager.eval_in_workspace((session, notebook), :($(bound_sym) = $(new_value)))
        end
    end
    to_reeval = where_referenced(notebook, notebook.topology, Set{Symbol}(to_set))

    run_reactive_async!(session, notebook, to_reeval; deletion_hook=custom_deletion_hook, persist_js_state=true, run_async=false, kwargs...)
end
