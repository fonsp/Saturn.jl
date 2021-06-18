### A Pluto.jl notebook ###
# v0.14.3

using Markdown
using InteractiveUtils

# ╔═╡ 4353ed5b-390c-40dd-979a-f8e839c5234f
using URIs

# ╔═╡ bcfad98a-1ba1-4557-8fdb-4cbe3000ad81
using PlutoUI

# ╔═╡ 7afb8d34-60db-4432-925b-8663437fed66
md"""
# Pre-downloading Pluto's web assets



"""

# ╔═╡ b174ad68-a3c9-11eb-04fd-531bfa823e16
import Pluto

# ╔═╡ f44587da-9eca-40f5-b600-d5be53469eb7


# ╔═╡ 0070955a-3b8d-4c36-b91b-e68a5e934588
src = "https://esm.sh/preact@10.5.13/hooks?target=es2020"

# ╔═╡ bd3917e2-deac-4308-af81-c21274c20fab
isurl(s) = startswith(s, r"https?://")

# ╔═╡ ea52a3a7-bddf-4b18-b40f-defd7403030f
path = if isurl(src)
	download(src)
else
	Pluto.project_relative_path("frontend", splitpath(src)...)
end

# ╔═╡ 2cbfd96f-3843-4be1-b105-f89657741398
begin
	contents = read(path, String)
	Text(contents)
end

# ╔═╡ 39a72690-2ed2-42fe-9153-2542f4d5670a
matchers = Dict(
	 "js" => r"(export|import)([{ \r\n][\w{} ,\n\r\*]*?)?['\"](.+?)['\"]"s,
	"mjs" => r"(export|import)([{ \r\n][\w{} ,\n\r\*]*?)?['\"](.+?)['\"]"s,
	"html" => r"(script|link) .*?(src|href)\=\"(.+?)\""s,
	"css" => r"url\(['\"]?(.+?)['\"]?\)"s,
)

# ╔═╡ 9152ec7e-2170-46f1-b8f4-eab3b91d7b5c


# ╔═╡ 8d891117-9f30-45e4-93c4-c19dfc642b50
u = URI("https://a.asdf/x/y/")

# ╔═╡ 02542c94-25cd-48d3-8db0-b16c2a770377
relpath dirname(u.path)

# ╔═╡ 202ae502-2eaf-42cc-8b85-9cf486fa104a
joinpath(URIs.absuri( dirname(u.path), u), "a.js")

# ╔═╡ f9a8e182-2f76-4421-91a0-8b950711dab8
joinuri(relative, root) = let
	u = URI(root)
	string(joinpath(URIs.absuri( dirname(u.path), u), String(relative)))
end

# ╔═╡ 35a58936-bfb1-4b9f-8545-db8d054c7414
function next_src(current_src, found_src)
	if isurl(found_src)
		String(found_src)
	else
		if isurl(current_src)
			joinuri(found_src, current_src)
		else
			normpath(joinpath(dirname(current_src), found_src))
		end
	end
end

# ╔═╡ 5a307667-47df-4b9c-a8d6-9d3238eed13f
joinuri("/a/b.js", "https://a.asdf/x/y/z.js"), 
"https://a.asdf/a/b.js"

# ╔═╡ 9ef82c84-7179-4fe6-aa3d-416447d33693
joinuri("b.js", "https://a.asdf/x/y/z.js"), "https://a.asdf/x/y/b.js"

# ╔═╡ 7993ab3d-51d5-4898-b237-14cf7801f987
joinpath(u, "a")

# ╔═╡ da4f62fb-f084-4663-891e-cd273711b019
lastcapture(c) = c.captures[end]

# ╔═╡ c15834bb-593b-47e7-a71a-2fde40413896
r = "http://asdfasdf/asdc/sdc/dsc/sss"

# ╔═╡ 5520ae12-88c3-431e-81ae-5cae7d95a0a5
findlast('/', r)

# ╔═╡ 46641b85-538c-4bfe-a6f9-be80e35779c0
r[1:29]

# ╔═╡ b7ddcb43-4eb7-4291-ac6c-f842d17a647a
joinpath("/a/b/c", "./x") |> normpath

# ╔═╡ 76c86df6-ab2b-479a-b5b7-a2f54822a76e
relpath

# ╔═╡ b01e0c26-9a6a-4166-8bfb-3dccdb743efe
function getfiletype(src)
	e = let
		p = isurl(src) ? URI(src).path : src
		splitext(p)[2][2:end]
	end
	isempty(e) ? "js" : e
end

# ╔═╡ 0059ebf7-d476-4f17-bd8a-8edb2b6083b1
filetype = getfiletype(src)

# ╔═╡ e89281c3-1038-45bc-b287-925efcbdffc8
matcher = get(matchers, filetype, nothing)

# ╔═╡ 8afa7481-53ff-42b7-a677-54cf6ede2e67
normuri(u) = string(URIs.absuri( URI(u).path |> normpath, URI(u)))

# ╔═╡ 9af2d08b-14c8-4d96-9019-cd72d2f5d87e
md"""
## Download assets
"""

# ╔═╡ 82f7d981-8316-41c1-b3ff-d449bb23cb79
URIs.escapeuri("https://cdn.jsdelivr.net/npm/htm@3.0.4/preact/standalone.mjs")

# ╔═╡ c4b87c88-a6b9-49e1-ae57-a276f2c86703
md"""
## Removing comments
"""

# ╔═╡ 02d9b29c-db20-477e-b64f-15b29f17f560


# ╔═╡ bf2d85d1-4e49-4e3a-9186-53745ca6939d
comment_matchers = Dict(
	"css" => r"/\*.*?\*/"s,
	"html" => r"\<\!\-\-.*?\-\-\>"s,
	"mjs" => r"// .*", # add a space to prevent mathcing https://www
	 "js" => r"// .*",
)

# ╔═╡ bb0c6639-52b2-4c29-8a23-913a55714387
wc = replace(contents, comment_matchers["js"] => "")

# ╔═╡ efdd88c5-a7a3-443b-8006-0748ca6609bf
matches = eachmatch(matcher, wc) |> collect

# ╔═╡ e92c18f0-883f-4d96-9e19-a29ae03bda0d
sources = map(lastcapture, matches)

# ╔═╡ 36e145f7-d583-476f-9f5e-06062d44444a
[next_src(src, s) for s in sources]

# ╔═╡ b7e5cedf-cda4-4a5f-9654-f8f9b4ad70c6
without_comments(contents, filetype) = replace(
	contents, 
	get(comment_matchers, filetype, "klasdfjlkjasdflkjalksdf") => "",
)

# ╔═╡ c28b17c2-ad05-46e2-abc5-26574de57080
function getsources(src::AbstractString)
	filetype = getfiletype(src)
	matcher = get(matchers, filetype, nothing)
	
	if matcher !== nothing
	
		path = if isurl(src)
			download(src)
		else
			@assert isabspath(src)
			src
		end

		contents = read(path, String)
		matches = eachmatch(matcher, without_comments(contents, filetype))
		sources = map(lastcapture, matches)
	else
		[]
	end
end

# ╔═╡ 30fd447e-c51a-4e50-afb9-a55df76ecb4d
@assert getsources("https://cdn.jsdelivr.net/npm/mathjax@3.1.2/es5/tex-svg-full.js") == []

# ╔═╡ 39567a53-a0a3-42a4-b0a1-67e67461a798
@assert getsources("https://raw.githubusercontent.com/fonsp/Pluto.jl/v0.14.3/frontend/imports/Preact.js") == ["https://cdn.jsdelivr.net/npm/htm@3.0.4/preact/standalone.mjs"]

# ╔═╡ 8e602fa2-b3c0-4826-9b71-491bceeefed7
@assert getsources("https://esm.sh/preact@10.5.13/hooks?target=es2020") |> length == 1

# ╔═╡ 53a42c0c-b5bf-401a-85bc-6f7b8822a96f
@assert getsources("https://cdn.esm.sh/v41/preact@10.5.13/es2020/hooks.js") == ["/v41/preact@10.5.13/es2020/preact.js"]

# ╔═╡ 97665280-c17b-4396-b4d3-d286b06612a8
getsources(path)

# ╔═╡ d9eea4e5-1c1a-41ed-9bc6-23000026c47b
function find_sources_recursive!(found::Set{String}, src::String, visited::Set{String})
	if src ∈ visited
		return found
	end
	
	push!(visited, src)
	
	sources = getsources(src)

	for s in sources
		next = next_src(src, s)

		push!(found, next)
		try
			find_sources_recursive!(found, next, visited)
		catch e
			@error "asdf" src next s exception=(e,catch_backtrace())
		end
	end
	
	found
end

# ╔═╡ 6c2add9c-95fa-4e09-aed5-5f2fc2b6188f
find_sources_recursive(src) = find_sources_recursive!(Set{String}([src]), src, Set{String}())

# ╔═╡ a7b84f78-7800-4743-a178-fd5943833f40
found = find_sources_recursive(Pluto.project_relative_path("frontend", "editor.html"))

# ╔═╡ 1976c87b-bdd0-4850-a23e-abcfc25ff8c4
sort(collect(found))

# ╔═╡ 9d002b0f-64a7-4c54-ab41-4a347936e950
remote = sort(collect(filter(isurl, found)))

# ╔═╡ 947aa562-b603-4e8f-bf49-6b2a02e02f34
begin
	outdir = "proxied_lib"
	
	try
		rm(outdir; recursive=true)
	catch end
	mkpath(outdir)
	
	for s in remote
		try
			download(s, joinpath(outdir, URIs.escapeuri(s)))
		catch end
	end
end

# ╔═╡ 2579055b-c87e-4be7-9d6b-bd02e9b02982
without_comments("""
	// 23fsdfadsf sdf
	x = "https://asdf"
	/*
	asdf
	https://asdf
	*/
	asdf
	""", "js") |> Text

# ╔═╡ Cell order:
# ╟─7afb8d34-60db-4432-925b-8663437fed66
# ╠═b174ad68-a3c9-11eb-04fd-531bfa823e16
# ╠═4353ed5b-390c-40dd-979a-f8e839c5234f
# ╟─f44587da-9eca-40f5-b600-d5be53469eb7
# ╠═0070955a-3b8d-4c36-b91b-e68a5e934588
# ╠═2cbfd96f-3843-4be1-b105-f89657741398
# ╟─ea52a3a7-bddf-4b18-b40f-defd7403030f
# ╠═bd3917e2-deac-4308-af81-c21274c20fab
# ╠═39a72690-2ed2-42fe-9153-2542f4d5670a
# ╠═30fd447e-c51a-4e50-afb9-a55df76ecb4d
# ╠═39567a53-a0a3-42a4-b0a1-67e67461a798
# ╠═8e602fa2-b3c0-4826-9b71-491bceeefed7
# ╠═53a42c0c-b5bf-401a-85bc-6f7b8822a96f
# ╠═0059ebf7-d476-4f17-bd8a-8edb2b6083b1
# ╠═e89281c3-1038-45bc-b287-925efcbdffc8
# ╠═efdd88c5-a7a3-443b-8006-0748ca6609bf
# ╠═e92c18f0-883f-4d96-9e19-a29ae03bda0d
# ╠═36e145f7-d583-476f-9f5e-06062d44444a
# ╠═bb0c6639-52b2-4c29-8a23-913a55714387
# ╠═c28b17c2-ad05-46e2-abc5-26574de57080
# ╠═35a58936-bfb1-4b9f-8545-db8d054c7414
# ╠═9152ec7e-2170-46f1-b8f4-eab3b91d7b5c
# ╠═5a307667-47df-4b9c-a8d6-9d3238eed13f
# ╠═9ef82c84-7179-4fe6-aa3d-416447d33693
# ╠═8d891117-9f30-45e4-93c4-c19dfc642b50
# ╠═02542c94-25cd-48d3-8db0-b16c2a770377
# ╠═202ae502-2eaf-42cc-8b85-9cf486fa104a
# ╠═f9a8e182-2f76-4421-91a0-8b950711dab8
# ╠═7993ab3d-51d5-4898-b237-14cf7801f987
# ╠═97665280-c17b-4396-b4d3-d286b06612a8
# ╠═da4f62fb-f084-4663-891e-cd273711b019
# ╠═bcfad98a-1ba1-4557-8fdb-4cbe3000ad81
# ╠═c15834bb-593b-47e7-a71a-2fde40413896
# ╠═5520ae12-88c3-431e-81ae-5cae7d95a0a5
# ╠═46641b85-538c-4bfe-a6f9-be80e35779c0
# ╠═b7ddcb43-4eb7-4291-ac6c-f842d17a647a
# ╠═76c86df6-ab2b-479a-b5b7-a2f54822a76e
# ╠═b01e0c26-9a6a-4166-8bfb-3dccdb743efe
# ╠═d9eea4e5-1c1a-41ed-9bc6-23000026c47b
# ╠═6c2add9c-95fa-4e09-aed5-5f2fc2b6188f
# ╠═a7b84f78-7800-4743-a178-fd5943833f40
# ╠═1976c87b-bdd0-4850-a23e-abcfc25ff8c4
# ╠═9d002b0f-64a7-4c54-ab41-4a347936e950
# ╠═8afa7481-53ff-42b7-a677-54cf6ede2e67
# ╟─9af2d08b-14c8-4d96-9019-cd72d2f5d87e
# ╠═947aa562-b603-4e8f-bf49-6b2a02e02f34
# ╠═82f7d981-8316-41c1-b3ff-d449bb23cb79
# ╟─c4b87c88-a6b9-49e1-ae57-a276f2c86703
# ╠═02d9b29c-db20-477e-b64f-15b29f17f560
# ╠═bf2d85d1-4e49-4e3a-9186-53745ca6939d
# ╠═b7e5cedf-cda4-4a5f-9654-f8f9b4ad70c6
# ╠═2579055b-c87e-4be7-9d6b-bd02e9b02982
