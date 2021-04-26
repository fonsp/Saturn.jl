### A Pluto.jl notebook ###
# v0.14.0

using Markdown
using InteractiveUtils

# ╔═╡ 46b1e7b2-8460-11eb-3454-f7fa9542f903
begin
	import Pkg
	Pkg.add([
		"Dash",
		"DashCoreComponents",
		"DashHtmlComponents",
		"DashTable",
		"HTTP",
	])
end

# ╔═╡ b6963f48-81ce-4332-94b7-acc5740376be
using Dash

# ╔═╡ 7209c5f8-47f8-4d64-89e2-b08e121eb227
using DashHtmlComponents

# ╔═╡ 007a8782-2487-41bc-82cc-c26ef7e6a6f9
using DashCoreComponents

# ╔═╡ c8f8d722-96a9-49b3-a566-58f73dc1f4c4
md"""
# Example of Dash app in Pluto

This is the successor to [My Previous Dash Integration](https://gist.github.com/dralletje/131eff9e90703346ca7db09ebcec223f), succeeding in being more seamless. It's still a bit jittery with every reload, but above the `Dash setup` line nothing should be different from normal dash app code... but it works!!
"""

# ╔═╡ 17f86bb0-4960-4980-9ba6-2f3ada6ceee3
md"## Appendix"

# ╔═╡ b53711ab-7d12-40f1-8457-146b665ea9ca
md"### Packages"

# ╔═╡ db3b4012-52b8-4711-b81d-7dc54f914add
import HTTP

# ╔═╡ e4978853-818a-4911-9fbd-17d170422521
import UUIDs: UUID, uuid4

# ╔═╡ fd894b9d-0844-4627-a833-e79c9355972c
md"### Dash setup"

# ╔═╡ f7d7aad2-fcb2-451e-a5dc-8238a9502ac1
# """
# This is because I'm experimenting with showing docs above cells 😁
# """
# function Base.show(io::IO, mime::MIME"text/html", binding::Base.Docs.Binding)
# 	write(io, sprint(show, mime, Base.Docs.doc(binding)))
# 	write(io, sprint(show, mime, HTML("""
# 	<assignee
# 		style="
# 			color: #5668a4;
# 			font-weight: 700;
# 			font-family: JuliaMono, monospace;
# 			font-size: 0.75rem;
# 			font-variant-ligatures: none;
# 		"
# 	>
# 		$(binding.var)
# 		<span style="opacity: 0.6">=</span>
# 	</assignee>
# 	""")))
# end

# ╔═╡ efafd63a-2bc6-4bc5-9d8e-a636448b9ced
"""
I need to have a reference to all "running" dash apps per uuid.
Might want to use something like [WeakValueDicts.jl](https://github.com/travigd/WeakValueDicts.jl) to prevent memory leaking, but this is something I want to try with more in Pluto anyway.
"""
DASH_APPS = Dict{UUID, Any}()

# ╔═╡ 084ebaf4-ba36-413c-b409-35e25b7b9ca5
"""
For Dash I am just running the Dash server as normal, and proxying all the requests 🙃
This works remarkably well.
"""
function PlutoRunner.IntegrationsWithOtherPackages.on_request(::Val{:Dash}, request)
	local _1, _2, _3, _4, uuid_string = split(request[:target], "/")
		
	local app_uuid = UUID(uuid_string)
	
	if !haskey(DASH_APPS, app_uuid)
		return Dict(:status => 500)
	end
	handler = DASH_APPS[app_uuid]
	
	response = HTTP.handle(handler, Dash.HTTP.Request(request[:method], request[:target], [], request[:body]))
		
	return Dict(
		:status => Int64(response.status),
		:headers => response.headers,
		:body => response.body,
	)
end

# ╔═╡ 35494f14-de9c-4968-8df4-4fa098a22793
"""
    structmerge(object, changes::Dict{Symbol,<:Any})

Simple version of stuff found in SetField.jl and Accessors.jl.
Tries to create new version of what you pass in, but with fieldnames
found in the changes Dict replaced.
"""
function structmerge(original::T, changes::Dict{Symbol,<:Any}) where T
	local Constructor = getfield(parentmodule(T), nameof(T))
	Constructor(
		map(propertynames(original)) do p
			if haskey(changes, p)
				changes[p]
			else
				getproperty(original, p)
			end
		end...
	)
end

# ╔═╡ 03c3688f-4d4a-47a0-b0b8-f4b7a6e98d9b
"""
    copy_dash(app::DashApp; url_base_pathname::String)

Because DashApps don't just wanna get copied,
I need this strange method to do this very specifically.
Looking forward to maintaining this when they change anything!!!
"""
function copy_dash(app::Dash.DashApp; url_base_pathname::String)
	local config = structmerge(app.config, Dict(
		:url_base_pathname => url_base_pathname,
		:requests_pathname_prefix => url_base_pathname,
		:routes_pathname_prefix => url_base_pathname,
	))
	new_app = Dash.DashApp(
		app.root_path,
		app.is_interactive,
		config,
		app.index_string,
		app.title
	)
	
	new_app.layout = app.layout
	merge!(new_app.callbacks, app.callbacks)	
	new_app
end

# ╔═╡ 634ac74d-f9b3-422a-8ebc-d46f585cb4a6
base_url = PlutoRunner.IntegrationsWithOtherPackages.get_base_url(:Dash)

# ╔═╡ 306d2094-9377-47ec-a73f-1a347e6b87b3
begin
	dash_show_extensions = true
	
	"""
	Do exactly the same setup as the method below, but instead of showing an iframe,
	I just print the (relative) url.
	"""
	function Base.show(io::IO, app::Dash.DashApp)
		local app_uuid = uuid4()
		local app_url = base_url * "/$(app_uuid)/"
		local app_copy = copy_dash(app, url_base_pathname=app_url)
		DASH_APPS[app_uuid] = Dash.make_handler(app_copy)

		write(io, something(app_copy.config.url_base_pathname, ""))
	end
	
	"""
	To show a dash app, we have to copy the app with a new unique base_url,
	and save that base_url/app pair. It feels a bit off to put a side-effect
	like this in Base.show, let me know if you have a better way 😁
	"""
	function Base.show(io::IO, mime::MIME"text/html", app::Dash.DashApp)
		local app_uuid = uuid4()
		local app_url = base_url * "/$(app_uuid)/"
		local app_copy = copy_dash(app, url_base_pathname=app_url)
		DASH_APPS[app_uuid] = Dash.make_handler(app_copy)

		write(io, """
		<div style="position: relative">
			<div
				id="loading"
				style="
					position: absolute;
					top: 0;
					left: 0;
					right: 0;
					bottom: 0;
					background-color: rgba(255,255,255);

					display: flex;
					align-items: center;
					justify-content: center;
					font-size: 32px;
				"
			><span>Loading</span></div>
			<iframe src="$(app_copy.config.url_base_pathname)" style="border: none; width: 100%;"></iframe>
		</div>

		<script>
		let \$iframe = currentScript.closest('pluto-output').querySelector('iframe')
		let \$loading = currentScript.closest('pluto-output').querySelector('#loading')

		// Code below here is borrowed from CellOutput.js in Pluto
		let iframeref = {
			current: \$iframe,
		}
		await new Promise((resolve) => iframeref.current.addEventListener("load", () => resolve()))
		let iframeDocument = iframeref.current.contentWindow.document

		// Insert iframe resizer inside the iframe
		let x = iframeDocument.createElement("script")
		x.src = "https://cdn.jsdelivr.net/npm/iframe-resizer@4.2.11/js/iframeResizer.contentWindow.min.js"
		x.integrity = "sha256-EH+7IdRixWtW5tdBwMkTXL+HvW5tAqV4of/HbAZ7nEc="
		x.crossOrigin = "anonymous"
		iframeDocument.head.appendChild(x)

		// Apply iframe resizer from the host side
		new Promise((resolve) => x.addEventListener("load", () => resolve()))
		// @ts-ignore
		window.iFrameResize({ checkOrigin: false }, iframeref.current)
		// End of borrowed code

		\$loading.style.display = "none"
		</script>
		""")
	end
end

# ╔═╡ 0a8ed9fd-eb72-420f-93ff-8368cf0fc0e8
my_app = begin
	# I have this one change!!! Because my Base.show extension should be loaded
	dash_show_extensions;
	
	local app = dash(
		external_stylesheets = ["https://codepen.io/chriddyp/pen/bWLwgP.css"]
	)
	app.layout = html_div() do
		dcc_input(id="graphTitle", value="Let's Dance!!", type = "text"),
		html_div(id="outputID"),
		dcc_graph(id="graph",
			figure = (
				data = [(x = [1,2,3], y = [3,2,8], type="bar")],
				layout = Dict(:title => "Graph")
			)
		)
	end
	callback!(
		app,
		Output("outputID", "children"),
		Input("graphTitle","value"),
		State("graphTitle","type")
	) do value, type
		@info "SAY WHAAT" value
		"You've entered: '$(value)' into a '$(type)' input control"
	end
		
	callback!(
		app,
		Output("graph", "figure"),
		Input("graphTitle", "value")
	) do value
		(
			data = [
				(x = [1,2,3], y = abs.(randn(3)), type="bar"),
				(x = [1,2,3], y = abs.(randn(3)), type="scatter", mode = "lines+markers", line = (width = 4,))
			],
			layout = (title = value,)
		)
	end

	app
end

# ╔═╡ 74a80b9f-663d-4fa4-b1d6-56db206cb167
HTML("""
<a href="$(string(my_app))" target="_blank">Open app in seperate tab</a>
""")

# ╔═╡ Cell order:
# ╟─c8f8d722-96a9-49b3-a566-58f73dc1f4c4
# ╟─74a80b9f-663d-4fa4-b1d6-56db206cb167
# ╠═0a8ed9fd-eb72-420f-93ff-8368cf0fc0e8
# ╟─17f86bb0-4960-4980-9ba6-2f3ada6ceee3
# ╟─b53711ab-7d12-40f1-8457-146b665ea9ca
# ╠═46b1e7b2-8460-11eb-3454-f7fa9542f903
# ╠═db3b4012-52b8-4711-b81d-7dc54f914add
# ╠═b6963f48-81ce-4332-94b7-acc5740376be
# ╠═7209c5f8-47f8-4d64-89e2-b08e121eb227
# ╠═007a8782-2487-41bc-82cc-c26ef7e6a6f9
# ╠═e4978853-818a-4911-9fbd-17d170422521
# ╟─fd894b9d-0844-4627-a833-e79c9355972c
# ╟─f7d7aad2-fcb2-451e-a5dc-8238a9502ac1
# ╠═efafd63a-2bc6-4bc5-9d8e-a636448b9ced
# ╠═084ebaf4-ba36-413c-b409-35e25b7b9ca5
# ╠═35494f14-de9c-4968-8df4-4fa098a22793
# ╟─03c3688f-4d4a-47a0-b0b8-f4b7a6e98d9b
# ╠═634ac74d-f9b3-422a-8ebc-d46f585cb4a6
# ╠═306d2094-9377-47ec-a73f-1a347e6b87b3
