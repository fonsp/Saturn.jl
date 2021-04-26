using Base: PkgId, loaded_modules, package_callbacks
using Base.Meta: isexpr
if isdefined(Base, :mapany)
  const mapany = Base.mapany
else
  mapany(f, A::AbstractVector) = map!(f, Vector{Any}(undef, length(A)), A)
end

export @require

isprecompiling() = ccall(:jl_generating_output, Cint, ()) == 1

loaded(pkg::PkgId) = haskey(Base.loaded_modules, pkg)

const notified_pkgs = [Base.PkgId(UUID(0x295af30fe4ad537b898300126c2a3abe), "Revise")]

const _callbacks = Dict{PkgId, Vector{Function}}()
callbacks(pkg::PkgId) = get!(Vector{Function}, _callbacks, pkg)

listenpkg(@nospecialize(f), pkg::PkgId) =
  loaded(pkg) ? f() : push!(callbacks(pkg), f)

function loadpkg(pkg::PkgId)
  if haskey(_callbacks, pkg)
    fs = _callbacks[pkg]
    delete!(_callbacks, pkg)
    foreach(Base.invokelatest, fs)
  end
end

function withpath(@nospecialize(f), path::String)
  tls = task_local_storage()
  hassource = haskey(tls, :SOURCE_PATH)
  hassource && (path′ = tls[:SOURCE_PATH])
  tls[:SOURCE_PATH] = path
  try
    return f()
  finally
    hassource ?
      (tls[:SOURCE_PATH] = path′) :
      delete!(tls, :SOURCE_PATH)
  end
end

function err(@nospecialize(f), listener::Module, modname::String)
  try
    f()
  catch exc
    @warn "Error requiring `$modname` from `$listener`" exception=(exc,catch_backtrace())
  end
end

function parsepkg(ex::Expr)
  isexpr(ex, :(=)) || @goto fail
  mod, id = ex.args
  (mod isa Symbol && id isa String) || @goto fail
  return id::String, String(mod::Symbol)
  @label fail
  error("Requires syntax is: `@require Pkg=\"uuid\"`")
end

function withnotifications(@nospecialize(args...))
  for id in notified_pkgs
    if loaded(id)
      mod = Base.root_module(id)
      if isdefined(mod, :add_require)
        add_require = getfield(mod, :add_require)::Function
        add_require(args...)
      end
    end
  end
  return nothing
end

function replace_include(ex::Expr, source::LineNumberNode)
  if ex.head == :call && ex.args[1] === :include && ex.args[2] isa String
    return Expr(:macrocall, :($Requires.$(Symbol("@include"))), source, ex.args[2]::String)
  end
  return Expr(ex.head, (mapany(ex.args) do arg
    isa(arg, Expr) ? replace_include(arg, source) : arg
  end)...)
end

macro require(pkg::Union{Symbol,Expr}, expr)
  pkg isa Symbol &&
    return Expr(:macrocall, Symbol("@warn"), __source__,
                "Requires now needs a UUID; please see the readme for changes in 0.7.")
  idstr, modname = parsepkg(pkg)
  pkg = :(Base.PkgId(Base.UUID($idstr), $modname))
  expr = isa(expr, Expr) ? replace_include(expr, __source__) : expr
  expr = macroexpand(__module__, expr)
  srcfile = string(__source__.file)
  quote
    if !isprecompiling()
      listenpkg($pkg) do
        $withnotifications($srcfile, $__module__, $idstr, $modname, $(esc(Expr(:quote, expr))))
        withpath($srcfile) do
          err($__module__, $modname) do
            $(esc(:(eval($(Expr(:quote, Expr(:block,
                                            :(const $(Symbol(modname)) = Base.require($pkg)),
                                            expr)))))))
          end
        end
      end
    end
  end
end
