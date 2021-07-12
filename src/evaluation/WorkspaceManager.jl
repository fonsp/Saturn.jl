module WorkspaceManager
import UUIDs: UUID
import ..Pluto: Configuration, Notebook, Cell, ProcessStatus, ServerSession, ExpressionExplorer, pluto_filename, Token, withtoken, Promise, tamepath, project_relative_path, putnotebookupdates!, UpdateMessage
import ..Pluto.PkgCompat
import ..Configuration: CompilerOptions, _merge_notebook_compiler_options, _convert_to_flags
import ..Pluto.ExpressionExplorer: FunctionName
import ..PlutoRunner
import Distributed

"Contains the Julia process (in the sense of `Distributed.addprocs`) to evaluate code in. Each notebook gets at most one `Workspace` at any time, but it can also have no `Workspace` (it cannot `eval` code in this case)."
Base.@kwdef mutable struct Workspace
    pid::Integer
    discarded::Bool=false
    log_channel::Distributed.RemoteChannel
    module_name::Symbol
    dowork_token::Token=Token()
    nbpkg_was_active::Bool=false
    original_LOAD_PATH::Vector{String}=String[]
    original_ACTIVE_PROJECT::Union{Nothing,String}=nothing
end

"These expressions get evaluated whenever a new `Workspace` process is created."
const process_preamble = [
    :(ccall(:jl_exit_on_sigint, Cvoid, (Cint,), 0)),
    :(include($(project_relative_path("src", "runner", "Loader.jl")))),
    :(ENV["GKSwstype"] = "nul"), 
    :(ENV["JULIA_REVISE_WORKER_ONLY"] = "1"), 
]

const workspaces = Dict{UUID,Promise{Workspace}}()

const SN = Tuple{ServerSession,Notebook}

"""Create a workspace for the notebook, optionally in the main process."""
function make_workspace((session, notebook)::SN; force_offline::Bool=false)::Workspace
    force_offline || (notebook.process_status = ProcessStatus.starting)

    use_distributed = if force_offline
        false
    else
        session.options.evaluation.workspace_use_distributed
    end

    pid = if use_distributed
        create_workspaceprocess(;compiler_options=_merge_notebook_compiler_options(notebook, session.options.compiler))
    else
        pid = Distributed.myid()
        if !(isdefined(Main, :PlutoRunner) && Main.PlutoRunner isa Module)
            # we make PlutoRunner available in Main, right now it's only defined inside this Pluto module.
            @eval Main begin
                PlutoRunner = $(PlutoRunner)
            end
        end
        pid
    end

    Distributed.remotecall_eval(Main, [pid], :(PlutoRunner.notebook_id[] = $(notebook.notebook_id)))
    log_channel = Core.eval(Main, quote
        $(Distributed).RemoteChannel(() -> eval(:(Main.PlutoRunner.log_channel)), $pid)
    end)
    module_name = create_emptyworkspacemodule(pid)
    
    original_LOAD_PATH, original_ACTIVE_PROJECT = Distributed.remotecall_eval(Main, pid, :(Base.LOAD_PATH, Base.ACTIVE_PROJECT[]))
    
    workspace = Workspace(;
        pid=pid,
        log_channel=log_channel, 
        module_name=module_name,
        original_LOAD_PATH=original_LOAD_PATH,
        original_ACTIVE_PROJECT=original_ACTIVE_PROJECT,
    )

    @async start_relaying_logs((session, notebook), log_channel)
    cd_workspace(workspace, notebook.path)
    use_nbpkg_environment((session, notebook), workspace)

    force_offline || (notebook.process_status = ProcessStatus.ready)
    return workspace
end

function use_nbpkg_environment((session, notebook)::SN, workspace=nothing)
    enabled = notebook.nbpkg_ctx !== nothing
    if workspace.nbpkg_was_active == enabled
        return
    end
    
    workspace = workspace !== nothing ? workspace : get_workspace((session, notebook))
    if workspace.discarded
        return
    end
    
    workspace.nbpkg_was_active = enabled
    if workspace.pid != Distributed.myid()
        new_LP = enabled ? ["@", "@stdlib"] : workspace.original_LOAD_PATH
        new_AP = enabled ? PkgCompat.env_dir(notebook.nbpkg_ctx) : workspace.original_ACTIVE_PROJECT
        
        Distributed.remotecall_eval(Main, [workspace.pid], quote
            copy!(LOAD_PATH, $(new_LP))
            Base.ACTIVE_PROJECT[] = $(new_AP)
        end)
    else
        # uhmmmmmm TODO
    end
end

function start_relaying_logs((session, notebook)::SN, log_channel::Distributed.RemoteChannel)
    while true
        try
            next_log = take!(log_channel)
            putnotebookupdates!(session, notebook, UpdateMessage(:log, next_log, notebook))
        catch e
            if !isopen(log_channel)
                break
            end
            @error "Failed to relay log" exception=(e, catch_backtrace())
        end
    end
end

"Call `cd(\$path)` inside the workspace. This is done when creating a workspace, and whenever the notebook changes path."
function cd_workspace(workspace, path::AbstractString)
    eval_in_workspace(workspace, quote
        cd($(path |> dirname))
    end)
end

"Create a new empty workspace. Return the `(old, new)` workspace names as a tuple of `Symbol`s."
function bump_workspace_module(session_notebook::SN)
    workspace = get_workspace(session_notebook)
    old_name = workspace.module_name
    new_name = workspace.module_name = create_emptyworkspacemodule(workspace.pid)

    old_name, new_name
end

function create_emptyworkspacemodule(pid::Integer)::Symbol
    Distributed.remotecall_eval(Main, pid, :(PlutoRunner.increment_current_module()))
end

const Distributed_expr = :(
    Base.loaded_modules[Base.PkgId(Base.UUID("8ba89e20-285c-5b6f-9357-94700520ee1b"), "Distributed")]
)

# NOTE: this function only start a worker process using given
# compiler options, it does not resolve paths for notebooks
# compiler configurations passed to it should be resolved before this
function create_workspaceprocess(;compiler_options=CompilerOptions())::Integer
    # run on proc 1 in case Pluto is being used inside a notebook process
    # Workaround for "only process 1 can add/remove workers"
    pid = Distributed.remotecall_eval(Main, 1, quote
        $(Distributed_expr).addprocs(1; exeflags=$(_convert_to_flags(compiler_options))) |> first
    end)

    for expr in process_preamble
        Distributed.remotecall_eval(Main, [pid], expr)
    end

    # so that we NEVER break the workspace with an interrupt 🤕
    @async Distributed.remotecall_eval(Main, [pid],
        :(while true
            try
                wait()
            catch end
        end))

    pid
end

"Return the `Workspace` of `notebook`; will be created if none exists yet."
function get_workspace(session_notebook::SN)::Workspace
    session, notebook = session_notebook
    promise = get!(workspaces, notebook.notebook_id) do
        Promise{Workspace}(() -> make_workspace(session_notebook))
    end
    fetch(promise)
end
get_workspace(workspace::Workspace)::Workspace = workspace

"Try our best to delete the workspace. `ProcessWorkspace` will have its worker process terminated."
function unmake_workspace(session_notebook::Union{SN,Workspace}; async=false)
    workspace = get_workspace(session_notebook)
    workspace.discarded = true

    if workspace.pid != Distributed.myid()
        filter!(p -> fetch(p.second).pid != workspace.pid, workspaces)
        t = @async begin
            interrupt_workspace(workspace; verbose=false)
            # run on proc 1 in case Pluto is being used inside a notebook process
            # Workaround for "only process 1 can add/remove workers"
            Distributed.remotecall_eval(Main, 1, quote
                $(Distributed_expr).rmprocs($(workspace.pid))
            end)
        end
        async || wait(t)
    end
end

function distributed_exception_result(exs::CompositeException, workspace::Workspace)
    ex = exs.exceptions |> first

    if ex isa Distributed.RemoteException &&
        ex.pid == workspace.pid &&
        ex.captured.ex isa InterruptException

        (
            output_formatted=PlutoRunner.format_output(CapturedException(InterruptException(), [])),
            errored=true,
            interrupted=true,
            process_exited=false,
            runtime=nothing,
            published_objects=Dict{String,Any}(),
        )
    elseif ex isa Distributed.ProcessExitedException
        (
            output_formatted=PlutoRunner.format_output(CapturedException(exs, [])),
            errored=true,
            interrupted=true,
            process_exited=true && !workspace.discarded, # don't report a process exit if the workspace was discarded on purpose
            runtime=nothing,
            published_objects=Dict{String,Any}(),
        )
    else
        @error "Unkown error during eval_format_fetch_in_workspace" ex
        (
            output_formatted=PlutoRunner.format_output(CapturedException(exs, [])),
            errored=true,
            interrupted=true,
            process_exited=false,
            runtime=nothing,
            published_objects=Dict{String,Any}(),
        )
    end
end


"Evaluate expression inside the workspace - output is fetched and formatted, errors are caught and formatted. Returns formatted output and error flags.

`expr` has to satisfy `ExpressionExplorer.is_toplevel_expr`."
function eval_format_fetch_in_workspace(session_notebook::Union{SN,Workspace}, expr::Expr, cell_id::UUID, ends_with_semicolon::Bool=false, function_wrapped_info::Union{Nothing,Tuple}=nothing, contains_user_defined_macrocalls::Bool=false)::NamedTuple{(:output_formatted, :errored, :interrupted, :process_exited, :runtime, :published_objects),Tuple{PlutoRunner.MimedOutput,Bool,Bool,Bool,Union{UInt64,Nothing},Dict{String,Any}}}
    workspace = get_workspace(session_notebook)

    # if multiple notebooks run on the same process, then we need to `cd` between the different notebook paths
    if session_notebook isa Tuple
        if workspace.pid == Distributed.myid()
            cd_workspace(workspace, session_notebook[2].path)
        end
        use_nbpkg_environment(session_notebook, workspace)
    end
    
    # run the code 🏃‍♀️
    
    # a try block (on this process) to catch an InterruptException
    take!(workspace.dowork_token)
    early_result = try
        # we use [pid] instead of pid to prevent fetching output
        Distributed.remotecall_eval(Main, [workspace.pid], :(PlutoRunner.run_expression(
            getfield(Main, $(QuoteNode(workspace.module_name))), 
            $(QuoteNode(expr)), 
            $cell_id, 
            $function_wrapped_info,
            $contains_user_defined_macrocalls,
        )))
        put!(workspace.dowork_token)
        nothing
    catch exs
        # We don't use a `finally` because the token needs to be back asap for the interrupting code to pick it up.
        put!(workspace.dowork_token)
        distributed_exception_result(exs, workspace)
    end

    early_result === nothing ?
        format_fetch_in_workspace(workspace, cell_id, ends_with_semicolon) :
        early_result
end

"Evaluate expression inside the workspace - output is not fetched, errors are rethrown. For internal use."
function eval_in_workspace(session_notebook::Union{SN,Workspace}, expr)
    workspace = get_workspace(session_notebook)
    
    Distributed.remotecall_eval(Main, [workspace.pid], :(Core.eval($(workspace.module_name), $(expr |> QuoteNode))))
    nothing
end

function format_fetch_in_workspace(session_notebook::Union{SN,Workspace}, cell_id, ends_with_semicolon, showmore_id::Union{PlutoRunner.ObjectDimPair,Nothing}=nothing)::NamedTuple{(:output_formatted, :errored, :interrupted, :process_exited, :runtime, :published_objects),Tuple{PlutoRunner.MimedOutput,Bool,Bool,Bool,Union{UInt64,Nothing},Dict{String,Any}}}
    workspace = get_workspace(session_notebook)
    
    # instead of fetching the output value (which might not make sense in our context, since the user can define structs, types, functions, etc), we format the cell output on the worker, and fetch the formatted output.
    withtoken(workspace.dowork_token) do
        try
            Distributed.remotecall_eval(Main, workspace.pid, :(PlutoRunner.formatted_result_of(
                $cell_id, $ends_with_semicolon, $showmore_id,
                getfield(Main, $(QuoteNode(workspace.module_name))),
                )))
        catch ex
            distributed_exception_result(CompositeException([ex]), workspace)
        end
    end
end

function macroexpand_in_workspace(session_notebook::Union{SN,Workspace}, macrocall, cell_uuid, module_name = nothing)
    workspace = get_workspace(session_notebook)
    module_name = module_name === nothing ? workspace.module_name : module_name

    expr = quote
        PlutoRunner.try_macroexpand($(module_name), $(cell_uuid), $(macrocall |> QuoteNode))
    end
    try
        result = Distributed.remotecall_eval(Main, workspace.pid, expr)
        return result
    catch e
        return e
    end
end

"Evaluate expression inside the workspace - output is returned. For internal use."
function eval_fetch_in_workspace(session_notebook::Union{SN,Workspace}, expr)
    workspace = get_workspace(session_notebook)
    
    Distributed.remotecall_eval(Main, workspace.pid, :(Core.eval($(workspace.module_name), $(expr |> QuoteNode))))
end

function do_reimports(session_notebook::Union{SN,Workspace}, module_imports_to_move::Set{Expr})
    workspace = get_workspace(session_notebook)
    workspace_name = workspace.module_name
    Distributed.remotecall_eval(Main, [workspace.pid], :(PlutoRunner.do_reimports($(workspace_name), $module_imports_to_move)))
end

"Move variables to a new module. A given set of variables to be 'deleted' will not be moved to the new module, making them unavailable. "
function move_vars(session_notebook::Union{SN,Workspace}, old_workspace_name::Symbol, new_workspace_name::Union{Nothing,Symbol}, to_delete::Set{Symbol}, methods_to_delete::Set{Tuple{UUID,FunctionName}}, module_imports_to_move::Set{Expr}; kwargs...)
    workspace = get_workspace(session_notebook)
    new_workspace_name = something(new_workspace_name, workspace.module_name)
    
    Distributed.remotecall_eval(Main, [workspace.pid], :(PlutoRunner.move_vars($(old_workspace_name |> QuoteNode), $(new_workspace_name |> QuoteNode), $to_delete, $methods_to_delete, $module_imports_to_move)))
end

move_vars(session_notebook::Union{SN,Workspace}, to_delete::Set{Symbol}, methods_to_delete::Set{Tuple{UUID,FunctionName}}, module_imports_to_move::Set{Expr}; kwargs...) =
move_vars(session_notebook, bump_workspace_module(session_notebook)..., to_delete, methods_to_delete, module_imports_to_move; kwargs...)

# TODO: delete me
@deprecate(
    delete_vars(args...; kwargs...),
    move_vars(args...; kwargs...)
)

function poll(query::Function, timeout::Real=Inf64, interval::Real=1/20)
    start = time()
    while time() < start + timeout
        if query()
            return true
        end
        sleep(interval)
    end
    return false
end

"Force interrupt (SIGINT) a workspace, return whether successful"
function interrupt_workspace(session_notebook::Union{SN,Workspace}; verbose=true)::Bool
    workspace = get_workspace(session_notebook)

    if poll(() -> isready(workspace.dowork_token), 2.0, 5/100)
        verbose && println("Cell finished, other cells cancelled!")
        return true
    end

    if Sys.iswindows()
        verbose && @warn "Unfortunately, stopping cells is currently not supported on Windows :(
        Maybe the Windows Subsystem for Linux is right for you:
        https://docs.microsoft.com/en-us/windows/wsl"
        return false
    end
    if workspace.pid == Distributed.myid()
        verbose && @warn """Cells in this workspace can't be stopped, because it is not running in a separate workspace. Use `ENV["PLUTO_WORKSPACE_USE_DISTRIBUTED"]` to control whether future workspaces are generated in a separate process."""
        return false
    end
    if isready(workspace.dowork_token)
        verbose && @info "Tried to stop idle workspace - ignoring."
        return true
    end

    # You can force kill a julia process by pressing Ctrl+C five times 🙃
    # But this is not very consistent, so we will just keep pressing Ctrl+C until the workspace isn't running anymore.
    # TODO: this will also kill "pending" evaluations, and any evaluations started within 100ms of the kill. A global "evaluation count" would fix this.
    # TODO: listen for the final words of the remote process on stdout/stderr: "Force throwing a SIGINT"
    try
        verbose && @info "Sending interrupt to process $(workspace.pid)"
        Distributed.interrupt(workspace.pid)

        if poll(() -> isready(workspace.dowork_token), 5.0, 5/100)
            verbose && println("Cell interrupted!")
            return true
        end

        verbose && println("Still running... starting sequence")
        while !isready(workspace.dowork_token)    
            for _ in 1:5
                verbose && print(" 🔥 ")
                Distributed.interrupt(workspace.pid)
                sleep(0.18)
                if isready(workspace.dowork_token)
                    break
                end
            end
            sleep(1.5)
        end
        verbose && println()
        verbose && println("Cell interrupted!")
        true
    catch ex
        if !(ex isa KeyError)
            @warn "Interrupt failed for unknown reason"
            showerror(ex, stacktrace(catch_backtrace()))
        end
        false
    end
end

end
