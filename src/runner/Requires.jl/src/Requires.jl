module Requires

if isdefined(Base, :Experimental) && isdefined(Base.Experimental, Symbol("@compiler_options"))
    @eval Base.Experimental.@compiler_options compile=min optimize=0 infer=false
end

using UUIDs

function _include_path(relpath::String)
    # Reproduces include()'s runtime relative path logic
    # See Base._include_dependency()
    prev = Base.source_path(nothing)
    if prev === nothing
        path = abspath(relpath)
    else
        path = normpath(joinpath(dirname(prev), relpath))
    end
end

"""
    @include("somefile.jl")

Behaves like `include`, but caches the target file content at macro expansion
time, and uses this as a fallback when the file doesn't exist at runtime. This
is useful when compiling a sysimg. The argument `"somefile.jl"` must be a
string literal, not an expression.

`@require` blocks insert this automatically when you use `include`.
"""
macro include(relpath::String)
    compiletime_path = joinpath(dirname(String(__source__.file)), relpath)
    s = String(read(compiletime_path))
    quote
        # NB: Runtime include path may differ from the compile-time macro
        # expansion path if the source has been relocated.
        runtime_path = _include_path($relpath)
        if isfile(runtime_path)
            # NB: For Revise compatibility, include($relpath) needs to be
            # emitted where $relpath is a string *literal*.
            $(esc(:(include($relpath))))
        else
            include_string($__module__, $s, $relpath)
        end
    end
end

include("init.jl")
include("require.jl")

function __init__()
    push!(package_callbacks, loadpkg)
end

if isprecompiling()
    precompile(loadpkg, (Base.PkgId,)) || @warn "Requires failed to precompile `loadpkg`"
    precompile(withpath, (Any, String)) || @warn "Requires failed to precompile `withpath`"
    precompile(err, (Any, Module, String)) || @warn "Requires failed to precompile `err`"
    precompile(parsepkg, (Expr,)) || @warn "Requires failed to precompile `parsepkg`"
    precompile(listenpkg, (Any, Base.PkgId)) || @warn "Requires failed to precompile `listenpkg`"
    precompile(callbacks, (Base.PkgId,)) || @warn "Requires failed to precompile `callbacks`"
    precompile(withnotifications, (String, Module, String, String, Expr)) || @warn "Requires failed to precompile `withnotifications`"
    precompile(replace_include, (Expr, LineNumberNode)) || @warn "Requires failed to precompile `replace_include`"
    precompile(getfield(Requires, Symbol("@require")), (LineNumberNode, Module, Expr, Any)) || @warn "Requires failed to precompile `@require`"

    precompile(_include_path, (String,)) || @warn "Requires failed to precompile `_include_path`"
    precompile(getfield(Requires, Symbol("@include")), (LineNumberNode, Module, String)) || @warn "Requires failed to precompile `@include`"

    precompile(__init__, ()) || @warn "Requires failed to precompile `__init__`"
end

end # module
