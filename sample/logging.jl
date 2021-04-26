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

# ╔═╡ 65e8cd4e-dcc0-4b06-bb4b-566c1f19f794
using PlutoUI

# ╔═╡ 091d33fe-fffe-11ea-131f-01f4248b30ea
@info "23aaa"

# ╔═╡ e35e35f4-71c8-4f3b-8c72-4b3ffe4766a3
@info collect(1:100)

# ╔═╡ 2d01cdaa-fffe-11ea-09f5-63527a1b0f87
x = 233564653

# ╔═╡ c50f7178-8c7d-4319-82d9-b9154e8892d9
for x in 1:20
	@info "This is too long."
end

# ╔═╡ e5a8e7bd-5734-4254-914d-6f87670bf7d4
@bind wow html"<input type=checkbox>"

# ╔═╡ 2883b3d8-fffe-11ea-0a0f-bbd85ec665ea
begin
	
	wow && @info "a"
	wow && @info "b"
	wow && @info "c"
	wow && @info "d"
	
	try
		sqrt(-1)
	catch e
		@error "99" exception=(e, catch_backtrace())
	end
	nothing
end

# ╔═╡ 786b7146-8eab-4390-a746-3ccf25d1c4c8
for i in 1:10
	@info i
	@debug i
	sleep(.05)
end

# ╔═╡ 3599eb82-0003-11eb-3814-dfd0f5737846
for i in 1:10
	
	@debug i
	@info i*100
	if isodd(i)
		@warn "Oh no!" i
		@error i
	end
	sleep(.1)
end

# ╔═╡ f6147e0c-796f-4f5d-b000-93d790683a54
@info md"# hello"

# ╔═╡ f017b4d5-38ac-4498-8e58-770337a0d17d
md"""

# Hello


I am a footnote $(@info("Inside text!")), how cool is that!

But im not working :(
"""

# ╔═╡ Cell order:
# ╠═091d33fe-fffe-11ea-131f-01f4248b30ea
# ╠═e35e35f4-71c8-4f3b-8c72-4b3ffe4766a3
# ╠═2d01cdaa-fffe-11ea-09f5-63527a1b0f87
# ╠═c50f7178-8c7d-4319-82d9-b9154e8892d9
# ╠═e5a8e7bd-5734-4254-914d-6f87670bf7d4
# ╠═2883b3d8-fffe-11ea-0a0f-bbd85ec665ea
# ╠═786b7146-8eab-4390-a746-3ccf25d1c4c8
# ╠═3599eb82-0003-11eb-3814-dfd0f5737846
# ╠═65e8cd4e-dcc0-4b06-bb4b-566c1f19f794
# ╠═f6147e0c-796f-4f5d-b000-93d790683a54
# ╠═f017b4d5-38ac-4498-8e58-770337a0d17d
