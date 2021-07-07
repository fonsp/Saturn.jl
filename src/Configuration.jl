"""
The full list of keyword arguments that can be passed to [`Pluto.run`](@ref) (or [`Pluto.Configuration.from_flat_kwargs`](@ref)) is divided into four categories. Take a look at the documentation for:

- [`Pluto.Configuration.CompilerOptions`](@ref) defines the command line arguments for notebook `julia` processes.
- [`Pluto.Configuration.ServerOptions`](@ref) configures the HTTP server.
- [`Pluto.Configuration.SecurityOptions`](@ref) configures the authentication options for Pluto's HTTP server. Change with caution.
- [`Pluto.Configuration.EvaluationOptions`](@ref) is used internally during Pluto's testing.

Note that Pluto is designed to be _zero-configuration_, and most users should not (have to) change these settings. Most 'customization' can be achieved using Julia's wide range of packages! That being said, the available settings are useful if you are using Pluto in a special environment, such as docker, mybinder, etc.
"""
module Configuration

using Configurations # https://github.com/Roger-luo/Configurations.jl

import ..Pluto: tamepath

function notebook_path_suggestion()
    preferred_dir = startswith(Sys.BINDIR, pwd()) ? homedir() : pwd()
    return joinpath(preferred_dir, "") # so that it ends with / or \
end

function default_browser()::Function
    function construct_cmd(url::AbstractString)::Union{Nothing, Cmd}
        try
            if Sys.isapple()
                return `open $url`
            elseif Sys.iswindows() || detectwsl()
                return `powershell.exe Start "'$url'"`
            elseif Sys.islinux()
                return `xdg-open $url`
            else
                return nothing
            end
        catch ex
            return nothing
        end
    end
    return construct_cmd
end

"""
    ServerOptions([; kwargs...])

The HTTP server options. See [`SecurityOptions`](@ref) for additional settings.

# Arguments

- `root_url::Union{Nothing,String} = nothing`
- `host::String = "127.0.0.1"`
- `port::Union{Nothing,Integer} = nothing`
- `launch_browser::Bool = true`
- `on_url::Function = default_browser()`
- `dismiss_update_notification::Bool = false`
- `show_file_system::Bool = true`
- `notebook_path_suggestion::String = notebook_path_suggestion()`
- `disable_writing_notebook_files::Bool = false`
- `notebook::Union{Nothing,String} = nothing`
- `simulated_lag::Real=0.0`
"""
@option mutable struct ServerOptions
    root_url::Union{Nothing,String} = nothing
    host::String = "127.0.0.1"
    port::Union{Nothing,Integer} = nothing
    launch_browser::Bool = true
    on_url::Function = default_browser()
    dismiss_update_notification::Bool = false
    show_file_system::Bool = true
    notebook_path_suggestion::String = notebook_path_suggestion()
    disable_writing_notebook_files::Bool = false
    notebook::Union{Nothing,String} = nothing
    init_with_file_viewer::Bool=false
    simulated_lag::Real=0.0
end

"""
    SecurityOptions([; kwargs...])

Security settings for the HTTP server. 

# Arguments

- `require_secret_for_open_links::Bool = true`

    Whether the links `http://localhost:1234/open?path=/a/b/c.jl`  and `http://localhost:1234/open?url=http://www.a.b/c.jl` should be protected. 

    Use `true` for almost every setup. Only use `false` if Pluto is running in a safe container (like mybinder.org), where arbitrary code execution is not a problem.

- `require_secret_for_access::Bool = true`

    If false, you do not need to use a `secret` in the URL to access Pluto: you will be authenticated by visiting `http://localhost:1234/` in your browser. An authentication cookie is still used for access (to prevent XSS and deceptive links or an img src to `http://localhost:1234/open?url=badpeople.org/script.jl`), and is set automatically, but this request to `/` is protected by cross-origin policy.

    Use `true` on a computer used by multiple people simultaneously. Only use `false` if necessary.

**Leave these options on `true` for the most secure setup.**

Note that Pluto is quickly evolving software, maintained by designers, educators and enthusiasts — not security experts. If security is a serious concern for your application, then we recommend running Pluto inside a container and verifying the relevant security aspects of Pluto yourself.
"""
@option mutable struct SecurityOptions
    require_secret_for_open_links::Bool = true
    require_secret_for_access::Bool = true
end

"""
    EvaluationOptions([; kwargs...])

Options to change Pluto's evaluation behaviour during internal testing. These options are not intended to be changed during normal use.

- `run_notebook_on_load::Bool = true`
- `workspace_use_distributed::Bool = true`
- `lazy_workspace_creation::Bool = false`
"""
@option mutable struct EvaluationOptions
    run_notebook_on_load::Bool = true
    workspace_use_distributed::Bool = true
    lazy_workspace_creation::Bool = false
end

"""
    CompilerOptions([; kwargs...])

These options will be passed as command line argument to newly launched processes. See [the Julia documentation on command-line options](https://docs.julialang.org/en/v1/manual/command-line-options/).

# Arguments
- `compile::Union{Nothing,String} = nothing`
- `sysimage::Union{Nothing,String} = nothing`
- `banner::Union{Nothing,String} = nothing`
- `optimize::Union{Nothing,Int} = nothing`
- `math_mode::Union{Nothing,String} = nothing`
- `startup_file::Union{Nothing,String} = "no"`
- `history_file::Union{Nothing,String} = "no"`
- `threads::Union{Nothing,String,Int} = default_number_of_threads()`
"""
@option mutable struct CompilerOptions
    compile::Union{Nothing,String} = nothing
    sysimage::Union{Nothing,String} = nothing
    banner::Union{Nothing,String} = nothing
    optimize::Union{Nothing,Int} = nothing
    math_mode::Union{Nothing,String} = nothing

    # notebook specified options
    # the followings are different from
    # the default julia compiler options

    # we don't load startup file in notebook
    startup_file::Union{Nothing,String} = "no"
    # we don't load history file in notebook
    history_file::Union{Nothing,String} = "no"

    threads::Union{Nothing,String,Int} = default_number_of_threads()
end

function default_number_of_threads()
    env_value = get(ENV, "JULIA_NUM_THREADS", "")
    all(isspace, env_value) ? roughly_the_number_of_physical_cpu_cores() : parse(Int,env_value)
end

function roughly_the_number_of_physical_cpu_cores()
    # https://gist.github.com/fonsp/738fe244719cae820245aa479e7b4a8d
    if Sys.CPU_THREADS == 1
        1
    elseif Sys.CPU_THREADS == 2 || Sys.CPU_THREADS == 3
        2
    else
        Sys.CPU_THREADS ÷ 2
    end
end

"""
Collection of all settings that configure a Pluto session. 

`ServerSession` contains a `Configuration`.
"""
@option struct Options
    server::ServerOptions = ServerOptions()
    security::SecurityOptions = SecurityOptions()
    evaluation::EvaluationOptions = EvaluationOptions()
    compiler::CompilerOptions = CompilerOptions()
end

from_flat_kwargs(; kwargs...) = Configurations.from_field_kwargs(Options; kwargs...)

function _merge_notebook_compiler_options(notebook, options::CompilerOptions)::CompilerOptions
    if notebook.compiler_options === nothing
        return options
    end

    kwargs = Dict{Symbol,Any}()
    for each in fieldnames(CompilerOptions)
        # 1. not specified by notebook options
        # 2. general notebook specified options
        if getfield(notebook.compiler_options, each) === nothing
            kwargs[each] = getfield(options, each)
        else
            kwargs[each] = getfield(notebook.compiler_options, each)
        end
    end
    return CompilerOptions(;kwargs...)
end

function _convert_to_flags(options::CompilerOptions)::Vector{String}
    option_list = String[]

    for name in fieldnames(CompilerOptions)
        flagname = string("--", replace(String(name), "_" => "-"))
        value = getfield(options, name)
        if value !== nothing
            if !(VERSION <= v"1.5.0-" && name === :threads)
                push!(option_list, string(flagname, "=", value))
            end
        end
    end

    return option_list
end


end
