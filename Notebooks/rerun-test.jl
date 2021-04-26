### A Pluto.jl notebook ###
# v0.14.0

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

# ╔═╡ 1508da20-2f94-4a98-affd-5d49c7fd6223


# ╔═╡ 1867d6f6-3609-4f6b-909d-7466c6cd0c40
@bind x html"<input type=range>"

# ╔═╡ d4c18e2b-457d-4b2f-b8d8-822f4f7e5c6d
@bind y html"<input type=range>"

# ╔═╡ dee4bf1c-cd02-40de-a72e-15f076a0da92
@bind z html"<input type=range>"

# ╔═╡ 5e8358d9-8d76-4e8a-ba52-18f9a375edad
numberoftimes = Ref(0)

# ╔═╡ 6aee5316-6bf1-41fd-9f69-120c63b1627a
let x; y; z; numberoftimes[] += 1 end

# ╔═╡ Cell order:
# ╠═1508da20-2f94-4a98-affd-5d49c7fd6223
# ╠═1867d6f6-3609-4f6b-909d-7466c6cd0c40
# ╠═d4c18e2b-457d-4b2f-b8d8-822f4f7e5c6d
# ╠═dee4bf1c-cd02-40de-a72e-15f076a0da92
# ╠═5e8358d9-8d76-4e8a-ba52-18f9a375edad
# ╠═6aee5316-6bf1-41fd-9f69-120c63b1627a
