### A Pluto.jl notebook ###
# v0.14.0

using Markdown
using InteractiveUtils

# ╔═╡ 720411f4-8575-11eb-3bcb-b74d5b47bc74
begin
	import Pkg
	Pkg.activate(mktempdir())
	Pkg.develop(path="../JSServe.jl/")
	Pkg.add([
		# "JSServe",
		"Observables"
		# "WGLMakie",
	])

	using JSServe
	using JSServe: @js_str
	using JSServe.DOM
	using Observables
	import .PlutoRunner.IntegrationsWithOtherPackages
	
	jsserve_name = :JSServe9
	
	base_url = PlutoRunner.IntegrationsWithOtherPackages.get_base_url(jsserve_name)
	JSServe.JSSERVE_CONFIGURATION.external_url[] = base_url
	
	Page(listen_url="0.0.0.0",
         listen_port=8283,
         external_url=base_url,
	)
end

# ╔═╡ b0081c47-3208-489d-9553-7fa71db82947


# ╔═╡ a5e4aabd-9ae6-4e22-a50f-4165ef9fefb1
base_url

# ╔═╡ e2a2a5a2-fced-4b14-9c88-16ece68f64f7
function IntegrationsWithOtherPackages.on_request(::Val{jsserve_name}, request)
	try
		local relative_url = request[:target][length(base_url)+1:end]
		@info "relative_url" relative_url
		local file_path = JSServe.assetserver_to_localfile(relative_url)
		@info "path" file_path
		if isfile(file_path)
			Dict(
				:status => 200,
				:headers => ["Content-Type" => IntegrationsWithOtherPackages.mime_fromfilename(file_path)],
				:body => read(file_path),
			)
		else
			Dict(:status => 404)
		end
	catch e
		@error "e" e
		Dict(:status => 404)
	end
end

# ╔═╡ c8462916-131a-4375-8c17-f0240ff5dd99
JSServe.assetserver_to_localfile("/assetserver/04f18a408e0007a465e1eff71a9e4d269046c613-JSServe.js")

# ╔═╡ 37e718d2-e270-4173-b447-97e97396932d
JSServe.Page

# ╔═╡ 45298042-bed2-4954-bf6a-78d917d040fb
JSServe.Button("haha")

# ╔═╡ 1a042b44-d16a-47f9-a12a-174f9df008fa
JSServe.App() do
color = JSServe.Observable("red")

    button = DOM.div("click me", onclick=js"JSServe.update_obs($(color), 'blue')")
    return DOM.div(
        button, DOM.h1("Hello World", style=map(x-> "color: $(x)", color))
    )
end

# ╔═╡ Cell order:
# ╠═720411f4-8575-11eb-3bcb-b74d5b47bc74
# ╠═b0081c47-3208-489d-9553-7fa71db82947
# ╠═a5e4aabd-9ae6-4e22-a50f-4165ef9fefb1
# ╠═e2a2a5a2-fced-4b14-9c88-16ece68f64f7
# ╠═c8462916-131a-4375-8c17-f0240ff5dd99
# ╠═37e718d2-e270-4173-b447-97e97396932d
# ╠═45298042-bed2-4954-bf6a-78d917d040fb
# ╠═1a042b44-d16a-47f9-a12a-174f9df008fa
