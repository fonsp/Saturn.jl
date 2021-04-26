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

# ╔═╡ 20bd321a-9cec-4d6a-a618-cc8132fbc8c7
@bind y html"<input type=range>"

# ╔═╡ fbf09000-632d-419a-83b8-c2a739c13cdd
y

# ╔═╡ Cell order:
# ╠═20bd321a-9cec-4d6a-a618-cc8132fbc8c7
# ╠═fbf09000-632d-419a-83b8-c2a739c13cdd
