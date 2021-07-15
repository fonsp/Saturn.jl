module PkgCompat

export package_versions, package_completions

import Pkg
import Pkg.Types: VersionRange

import ..Pluto

# Should be in Base
flatmap(args...) = vcat(map(args...)...)

# Should be in Base
function select(f::Function, xs)
	for x ∈ xs
		if f(x)
			return x
		end
	end
	nothing
end


#=

NOTE ABOUT PUBLIC/INTERNAL PKG API

Pkg.jl exposes lots of API, but only some of it is "public": guaranteed to remain available. API is public if it is listed here:
https://pkgdocs.julialang.org/v1/api/

In this file, I labeled functions by their status using 🐸, ⚠️, etc.

A status in brackets (like this) means that it is only called within this file, and the fallback might be in a caller function.

---

I tried to only use public API, except:
- I use the `Pkg.Types.Context` value as first argument for many functions, since the server process manages multiple notebook processes, each with their own package environment. We could get rid of this, by settings `Base.ACTIVE_PROJECT[]` before and after each Pkg call. (This is temporarily activating the notebook environment.) This does have a performance impact, since the project and manifest caches are regenerated every time.
- https://github.com/JuliaLang/Pkg.jl/issues/2607 seems to be impossible with the current public API.
- Some functions try to use internal API for optimization/better features.

=#





###
# CONTEXT
###


const PkgContext = if isdefined(Pkg, :Context)
	Pkg.Context
elseif isdefined(Pkg, :Types) && isdefined(Pkg.Types, :Context)
	Pkg.Types.Context
elseif isdefined(Pkg, :API) && isdefined(Pkg.API, :Context)
	Pkg.API.Context
else
	Pkg.Types.Context
end

# 🐸 "Public API", but using PkgContext
load_ctx(env_dir)::PkgContext = PkgContext(env=Pkg.Types.EnvCache(joinpath(env_dir, "Project.toml")))

# 🐸 "Public API", but using PkgContext
create_empty_ctx()::PkgContext = load_ctx(mktempdir())

# ⚠️ Internal API with fallback
function load_ctx(original::PkgContext)
	new = load_ctx(env_dir(original))
	
	try
		new.env.original_project = original.env.original_project
		new.env.original_manifest = original.env.original_manifest
	catch e
		@warn "Pkg compat: failed to set original_project" exception=(e,catch_backtrace())
	end
	
	new
end

# ⚠️ Internal API with fallback
function mark_original!(ctx::PkgContext)
	try
		ctx.env.original_project = deepcopy(ctx.env.project)
		ctx.env.original_manifest = deepcopy(ctx.env.manifest)
	catch e
		@warn "Pkg compat: failed to set original_project" exception=(e,catch_backtrace())
	end
end

# ⚠️ Internal API with fallback
function is_original(ctx::PkgContext)::Bool
	try
		ctx.env.original_project == ctx.env.project &&
		ctx.env.original_manifest == ctx.env.manifest
	catch e
		@warn "Pkg compat: failed to get original_project" exception=(e,catch_backtrace())
		false
	end
end



# 🐸 "Public API", but using PkgContext
env_dir(ctx::PkgContext) = dirname(ctx.env.project_file)

project_file(x::AbstractString) = joinpath(x, "Project.toml")
manifest_file(x::AbstractString) = joinpath(x, "Manifest.toml")
project_file(ctx::PkgContext) = joinpath(env_dir(ctx), "Project.toml")
manifest_file(ctx::PkgContext) = joinpath(env_dir(ctx), "Manifest.toml")


# ⚠️ Internal API with fallback
function withio(f::Function, ctx::PkgContext, io::IO)
    @static if :io ∈ fieldnames(PkgContext)
        old_io = ctx.io
        ctx.io = io
        result = try
			f()
		finally
        	ctx.io = old_io
			nothing
		end
        result
    else
        f()
    end
end


###
# REGISTRIES
###

# (⛔️ Internal API)
"Return paths to all installed registries."
_get_registry_paths() = @static if isdefined(Pkg, :Types) && isdefined(Pkg.Types, :registries)
	Pkg.Types.registries()
elseif isdefined(Pkg, :Registry) && isdefined(Pkg.Registry, :reachable_registries)
	registry_specs = Pkg.Registry.reachable_registries()
	[s.path for s in registry_specs]
elseif isdefined(Pkg, :Types) && isdefined(Pkg.Types, :collect_registries)
	registry_specs = Pkg.Types.collect_registries()
	[s.path for s in registry_specs]
else
	String[]
end

# (⛔️ Internal API)
_get_registries() = map(_get_registry_paths()) do r
	@static if isdefined(Pkg, :Registry) && isdefined(Pkg.Registry, :RegistryInstance)
		Pkg.Registry.RegistryInstance(r)
	else
		r => Pkg.Types.read_registry(joinpath(r, "Registry.toml"))
	end
end

# (⛔️ Internal API)
"Contains all registries as `Pkg.Types.Registry` structs."
const _parsed_registries = Ref(_get_registries())

# (⛔️ Internal API)
"Re-parse the installed registries from disk."
function refresh_registry_cache()
	_parsed_registries[] = _get_registries()
end

const _updated_registries_compat = Ref(false)

# ⚠️✅ Internal API with good fallback
function update_registries(ctx)
	@static if isdefined(Pkg, :Types) && isdefined(Pkg.Types, :update_registries)
		Pkg.Types.update_registries(ctx)
	else
		if !_updated_registries_compat[]
			_updated_registries_compat[] = true
			Pkg.Registry.update()
		end
	end
end

# ⚠️✅ Internal API with fallback
function instantiate(ctx; update_registry::Bool)
	@static if hasmethod(Pkg.instantiate, Tuple{}, (:update_registry,))
		Pkg.instantiate(ctx; update_registry=update_registry)
	else
		Pkg.instantiate(ctx)
	end
end



# (⚠️ Internal API with fallback)
_stdlibs() = try
	values(Pkg.Types.stdlibs())
catch e
	@warn "Pkg compat: failed to load standard libraries." exception=(e,catch_backtrace())

	String["CRC32c", "Future", "Sockets", "MbedTLS_jll", "Random", "ArgTools", "libLLVM_jll", "GMP_jll", "Pkg", "Serialization", "LibSSH2_jll", "SHA", "OpenBLAS_jll", "REPL", "LibUV_jll", "nghttp2_jll", "Unicode", "Profile", "SparseArrays", "LazyArtifacts", "CompilerSupportLibraries_jll", "Base64", "Artifacts", "PCRE2_jll", "Printf", "p7zip_jll", "UUIDs", "Markdown", "TOML", "OpenLibm_jll", "Test", "MPFR_jll", "Mmap", "SuiteSparse", "LibGit2", "LinearAlgebra", "Logging", "NetworkOptions", "LibGit2_jll", "LibOSXUnwind_jll", "Dates", "LibUnwind_jll", "Libdl", "LibCURL_jll", "dSFMT_jll", "Distributed", "InteractiveUtils", "Downloads", "SharedArrays", "SuiteSparse_jll", "LibCURL", "Statistics", "Zlib_jll", "FileWatching", "DelimitedFiles", "Tar", "MozillaCACerts_jll"]
end

# ⚠️ Internal API with fallback
is_stdlib(package_name::AbstractString) = package_name ∈ _stdlibs()

global_ctx = PkgContext()

###
# Package names
###

# ⚠️ Internal API with fallback
function package_completions(partial_name::AbstractString)::Vector{String}
	String[
		filter(s -> startswith(s, partial_name), collect(_stdlibs()));
		_registered_package_completions(partial_name)
	]
end

# (⚠️ Internal API with fallback)
function _registered_package_completions(partial_name::AbstractString)::Vector{String}
	# compat
	try
		@static if hasmethod(Pkg.REPLMode.complete_remote_package, (String,))
			Pkg.REPLMode.complete_remote_package(partial_name)
		else
			Pkg.REPLMode.complete_remote_package(partial_name, 1, length(partial_name))[1]
		end
	catch e
		@warn "Pkg compat: failed to autocomplete packages" exception=(e,catch_backtrace())
		String[]
	end
end

###
# Package versions
###

# (⛔️ Internal API)
"""
Return paths to all found registry entries of a given package name.

# Example
```julia
julia> Pluto.PkgCompat._registry_entries("Pluto")
1-element Vector{String}:
 "/Users/fons/.julia/registries/General/P/Pluto"
```
"""
function _registry_entries(package_name::AbstractString, registries::Vector=_parsed_registries[])::Vector{String}
	flatmap(registries) do (rpath, r)
		packages = values(r["packages"])
		String[
			joinpath(rpath, d["path"])
			for d in packages
			if d["name"] == package_name
		]
	end
end

# (⛔️ Internal API)
function _package_versions_from_path(registry_entry_fullpath::AbstractString)::Vector{VersionNumber}
	# compat
    vd = @static if isdefined(Pkg, :Operations) && isdefined(Pkg.Operations, :load_versions) && hasmethod(Pkg.Operations.load_versions, (String,))
        Pkg.Operations.load_versions(registry_entry_fullpath)
    else
        Pkg.Operations.load_versions(PkgContext(), registry_entry_fullpath)
    end
	vd |> keys |> collect
end

# ⚠️ Internal API with fallback
# See https://github.com/JuliaLang/Pkg.jl/issues/2607
"""
Return all registered versions of the given package. Returns `["stdlib"]` for standard libraries, and a `Vector{VersionNumber}` for registered packages.
"""
function package_versions(package_name::AbstractString)::Vector
    if is_stdlib(package_name)
        ["stdlib"]
    else
		try
			@static(if isdefined(Pkg, :Registry) && isdefined(Pkg.Registry, :uuids_from_name)
				flatmap(_parsed_registries[]) do reg
					uuids_with_name = Pkg.Registry.uuids_from_name(reg, package_name)
					flatmap(uuids_with_name) do u
						pkg = get(reg, u, nothing)
						if pkg !== nothing
							info = Pkg.Registry.registry_info(pkg)
							collect(keys(info.version_info))
						else
							[]
						end
					end
				end
			else
				ps = _registry_entries(package_name)
				flatmap(_package_versions_from_path, ps)
			end) |> sort
		catch e
			@warn "Pkg compat: failed to get installable versions." exception=(e,catch_backtrace())
			["latest"]
		end
    end
end

# ⚠️ Internal API with fallback
"Does a package with this name exist in one of the installed registries?"
package_exists(package_name::AbstractString)::Bool =
    package_versions(package_name) |> !isempty

# 🐸 "Public API", but using PkgContext
function dependencies(ctx)
	# Pkg.dependencies(ctx) should also work on 1.5, but there is some weird bug (run the tests without this patch). This is probably some Pkg bug that got fixed.
	@static if VERSION < v"1.6.0-a"
		ctx.env.manifest
	else
		try
			# ctx.env.manifest
			@static if hasmethod(Pkg.dependencies, (PkgContext,))
				Pkg.dependencies(ctx)
			else
				Pkg.dependencies(ctx.env)
			end
		catch e
			if !occursin(r"expected.*exist.*manifest", sprint(showerror, e))
				@error """
				Pkg error: you might need to use

				Pluto.reset_notebook_environment(notebook_path)

				to reset this notebook's environment.

				Before doing so, consider sending your notebook file to https://github.com/fonsp/Pluto.jl/issues together with the following info:
				""" Pluto.PLUTO_VERSION VERSION exception=(e,catch_backtrace())
			end

			Dict()
		end
	end
end

function project(ctx::PkgContext)
	@static if hasmethod(Pkg.project, (PkgContext,))
		Pkg.project(ctx)
	else
		Pkg.project(ctx.env)
	end
end

# 🐸 "Public API", but using PkgContext
"Find a package in the manifest. Return `nothing` if not found."
_get_manifest_entry(ctx::PkgContext, package_name::AbstractString) = 
    select(e -> e.name == package_name, values(dependencies(ctx)))

# ⚠️ Internal API with fallback
"""
Find a package in the manifest given its name, and return its installed version. Return `"stdlib"` for a standard library, and `nothing` if not found.
"""
function get_manifest_version(ctx::PkgContext, package_name::AbstractString)
    if is_stdlib(package_name)
        "stdlib"
    else
        entry = _get_manifest_entry(ctx, package_name)
		entry === nothing ? nothing : entry.version
    end
end

###
# WRITING COMPAT ENTRIES
###


_project_key_order = ["name", "uuid", "keywords", "license", "desc", "deps", "compat"]
project_key_order(key::String) =
    something(findfirst(x -> x == key, _project_key_order), length(_project_key_order) + 1)

# ✅ Public API
function _modify_compat(f!::Function, ctx::PkgContext)::PkgContext
	toml = Pkg.TOML.parsefile(project_file(ctx))
	compat = get!(Dict, toml, "compat")

	f!(compat)

	isempty(compat) && delete!(toml, "compat")

	write(project_file(ctx), sprint() do io
		Pkg.TOML.print(io, toml; sorted=true, by=(key -> (project_key_order(key), key)))
	end)
	
	return load_ctx(ctx)
end


# ✅ Public API
"""
Add any missing [`compat`](https://pkgdocs.julialang.org/v1/compatibility/) entries to the `Project.toml` for all direct dependencies. This serves as a 'fallback' in case someone (with a different Julia version) opens your notebook without being able to load the `Manifest.toml`. Return the new `PkgContext`.

The automatic compat entry is: `"~" * string(installed_version)`.
"""
function write_auto_compat_entries(ctx::PkgContext)::PkgContext
	_modify_compat(ctx) do compat
		for p in keys(project(ctx).dependencies)
			if !haskey(compat, p)
				m_version = get_manifest_version(ctx, p)
				if m_version !== nothing && !is_stdlib(p)
					compat[p] = "~" * string(Base.thispatch(m_version))  # drop build number
				end
			end
		end
	end
end


# ✅ Public API
"""
Remove any automatically-generated [`compat`](https://pkgdocs.julialang.org/v1/compatibility/) entries from the `Project.toml`. This will undo the effects of [`write_auto_compat_entries`](@ref) but leave other (e.g. manual) compat entries intact. Return the new `PkgContext`.
"""
function clear_auto_compat_entries(ctx::PkgContext)::PkgContext
	if isfile(project_file(ctx))
		_modify_compat(ctx) do compat
			for p in keys(compat)
				m_version = get_manifest_version(ctx, p)
				if m_version !== nothing && !is_stdlib(p)
					if compat[p] == "~" * string(m_version)
						delete!(compat, p)
					end
				end
			end
		end
	else
		ctx
	end
end

# ✅ Public API
"""
Remove any [`compat`](https://pkgdocs.julialang.org/v1/compatibility/) entries from the `Project.toml` for standard libraries. These entries are created when an old version of Julia uses a package that later became a standard library, like https://github.com/JuliaPackaging/Artifacts.jl. Return the new `PkgContext`.
"""
function clear_stdlib_compat_entries(ctx::PkgContext)::PkgContext
	if isfile(project_file(ctx))
		_modify_compat(ctx) do compat
			for p in keys(compat)
				if is_stdlib(p)
					@info "Removing compat entry for stdlib" p
					delete!(compat, p)
				end
			end
		end
	else
		ctx
	end
end


end
