### A Pluto.jl notebook ###
# v0.14.1

using Markdown
using InteractiveUtils

# This Pluto notebook uses @bind for interactivity. When running this notebook outside of Pluto, the following 'mock version' of @bind gives bound variables a default value (instead of an error).
macro bind(def, element)
    quote
        local el = $(esc(element))
        global $(esc(def)) = Core.applicable(Base.get, el) ? Base.get(el) : missing
        el
    end
end

# ╔═╡ d72e14bf-3f20-4f66-b50d-bcb42176e7bb
import Pkg

# ╔═╡ e71c22df-f26c-475e-94e4-92dabd743af0
begin
	Pkg.activate(mktempdir())
	
	run(`apt-get update`)
	# run(`apt-get install zip -y`)
	Pkg.pkg"add WebIO JSExpr PlotlyJS@v0.14.0"
    
	using WebIO
	using JSExpr
	import PlotlyJS
end

# ╔═╡ db13a7ca-37b8-4c15-81b0-0c7b668dacf4
md"""
# BOOM, a plot
"""

# ╔═╡ ee9f73be-a769-49f1-8385-54837bac122f
plot = PlotlyJS.plot([1,2,3,4])

# ╔═╡ 00e3092a-8888-4f29-bc31-9a6c4870330d
md"""
Currently Pluto doesn't do anything to "sync" with the values received from the frontend. WebIO can do dynamic stuff around Pluto, as you can see when rendering the Observable:
"""

# ╔═╡ 64dafbeb-ff69-4b5e-95b0-c3105968df1c
function Base.get(observable::Observable)
	observable[]
end

# ╔═╡ 123ef9de-05a9-418d-ac54-41bd1c5bdb75
@bind x plot.scope["hover"]

# ╔═╡ 3dc790b7-869d-4503-a80f-39677e3b029b
x

# ╔═╡ 4c25d432-8aa1-4b89-a613-1594d8728470
md"""
If we actually get the value of this Observable, you see it doesn't update.
It would show the updated value, if you re-run this cell while hovering (good luck)
"""

# ╔═╡ 1c1527e2-7d47-4a95-93ca-fd9a94083f71
# plot.scope["hover"][]

# ╔═╡ 0c42ae5a-fed3-4eb6-9b50-3f9f2e923bf6
md"""
Look in the console, and see the value actually end up on the julia side!!
"""

# ╔═╡ 33403896-0477-414f-b00f-20a46856660c
# on(plot.scope["hover"]) do value
# 	@info("Plot hover is $(value)!")
# end

# ╔═╡ 0ccb5dc8-5e6b-4b41-8cda-8628c6d98cc7
md"""
# Direct WebIO Example

Same steps as above, but my own widget so you can actually see how to send data back to Julia.
"""

# ╔═╡ b2539559-74d1-4005-b800-77f948551617
my_scope = Scope()

# ╔═╡ b7056f3d-f655-49a6-84fb-f6d04cc133ea
random_value = Observable(my_scope, "rand-value", 0.0)

# ╔═╡ db8125d2-c622-4f95-9217-4c886ba2683b
my_scope(
    dom"button"(
        "Generate Random Number",
        events=Dict("click" => @js () -> $random_value[] = Math.random()),
    ),
)

# ╔═╡ 9c903dd3-bfe0-435b-9e2c-27f8abf4d895
on(random_value) do value
	@info("Value is now $(value)!")
end

# ╔═╡ c055ab85-6296-4262-8782-6f4e33b5ceda
md"""
You can actually re-run this cell, and see the latest value.
Still looking into a way to @bind with this.
"""

# ╔═╡ f6dd56c0-c818-43c9-adf0-3ca898ef71de
random_value[]

# ╔═╡ cd59d997-3109-4cf4-a743-22d3b7c7e0bb
md"# Just a simple div, but it still needs WebIO normally"

# ╔═╡ 65ec7db0-4966-4f25-88d7-62e9fa80945f
Node(
    :div,
    "Hello, world!",
    style=Dict(
        :backgroundColor => "black",
        :color => "white",
        :padding => "12px",
   ),
)

# ╔═╡ Cell order:
# ╠═d72e14bf-3f20-4f66-b50d-bcb42176e7bb
# ╠═e71c22df-f26c-475e-94e4-92dabd743af0
# ╟─db13a7ca-37b8-4c15-81b0-0c7b668dacf4
# ╠═ee9f73be-a769-49f1-8385-54837bac122f
# ╟─00e3092a-8888-4f29-bc31-9a6c4870330d
# ╠═123ef9de-05a9-418d-ac54-41bd1c5bdb75
# ╠═64dafbeb-ff69-4b5e-95b0-c3105968df1c
# ╠═3dc790b7-869d-4503-a80f-39677e3b029b
# ╟─4c25d432-8aa1-4b89-a613-1594d8728470
# ╠═1c1527e2-7d47-4a95-93ca-fd9a94083f71
# ╟─0c42ae5a-fed3-4eb6-9b50-3f9f2e923bf6
# ╠═33403896-0477-414f-b00f-20a46856660c
# ╟─0ccb5dc8-5e6b-4b41-8cda-8628c6d98cc7
# ╠═b2539559-74d1-4005-b800-77f948551617
# ╠═b7056f3d-f655-49a6-84fb-f6d04cc133ea
# ╠═db8125d2-c622-4f95-9217-4c886ba2683b
# ╠═9c903dd3-bfe0-435b-9e2c-27f8abf4d895
# ╟─c055ab85-6296-4262-8782-6f4e33b5ceda
# ╠═f6dd56c0-c818-43c9-adf0-3ca898ef71de
# ╟─cd59d997-3109-4cf4-a743-22d3b7c7e0bb
# ╠═65ec7db0-4966-4f25-88d7-62e9fa80945f
