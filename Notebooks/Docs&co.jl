### A Pluto.jl notebook ###
# v0.14.0

using Markdown
using InteractiveUtils

# ╔═╡ 8c24c5ae-84f0-11eb-1ab5-2f763486c5e6
import Base.Docs

# ╔═╡ 14ac032c-376a-491d-a5af-2a5ce2066921
import PlutoUI

# ╔═╡ 37d7def9-4f8e-4058-a0b0-ff9936fb0e35
begin
	function is_pure_expression(expr::Expr)
		if expr.head == :. || expr.head === :curly || expr.head === :ref
			all((is_pure_expression(x) for x in expr.args))
		else
			false
		end
	end
	is_pure_expression(s::Symbol) = true
	is_pure_expression(q::QuoteNode) = true
	is_pure_expression(q::Number) = true
	is_pure_expression(q::String) = true
	is_pure_expression(x) = false # Better safe than sorry I guess
end

# ╔═╡ 3c1b1268-bc57-41dc-98db-dd8361c1bcbe
module ParentMod
	module DocsMod
		"Function with doc"
		function function_with_doc end

		function function_without_doc end

		"Function with multiple docs #1"
		function function_with_multiple_docs() end

		"Function with multiple docs #2"
		function function_with_multiple_docs(::Number) end


		reassigned_function = function_with_multiple_docs


		"Variable with doc"
		variable_with_doc = 10

		"Variable with doc"
		variable_with_doc = 20


		variable_without_doc = 10
	end

	module BorrowMod
		import ..DocsMod: function_with_doc, function_without_doc
	end
end

# ╔═╡ 70571a9d-4f76-4ddb-be3f-851c0f4de65d
import Base.Meta

# ╔═╡ 7b9d5eea-d9e0-4551-9787-f6405e6466d0
Docs.meta(ParentMod.DocsMod)

# ╔═╡ 1cad1626-a018-4878-894e-34660e6f627e
Docs.doc(ParentMod.DocsMod.reassigned_function)

# ╔═╡ 18b9b905-b329-4ec1-96ad-05a5876aa97e
"Overwrite"
function overwrite_doc() end

# ╔═╡ b8194572-6537-470c-9fdf-8e04c853d2d4
function Docs.getdoc(X::typeof(overwrite_doc))
	return 10
end

# ╔═╡ 41fd9407-6c9f-489e-983f-3231fd2c70dc
_x = ParentMod.DocsMod.function_with_doc

# ╔═╡ 693420dc-88de-4836-bda9-56486c671858
Docs.doc(overwrite_doc)

# ╔═╡ 2fac54ef-3a80-4950-90cb-a6b9a420dfa3
var"if" = 10

# ╔═╡ 6d877aa2-5d1f-437c-b8d8-cf0df80d98ac
Docs.aliasof(ParentMod.BorrowMod.function_with_doc, Tuple{})

# ╔═╡ 29f36768-bd2f-443c-8783-ea5acde06c0c
Base.Docs.bindingexpr(:(X.Yz.a.x))

# ╔═╡ 6990a827-da52-4e89-a186-ec3d046c21a8
@macroexpand Docs.@ref X.Y.z(a, b)

# ╔═╡ 97ca5b1a-a536-4efa-ad7c-57989b4c09a8
Docs.splitexpr(:(X().i.o))

# ╔═╡ 67056d06-aa91-442d-b750-e4325a9452f4
Docs.splitexpr(:(@X.i.o))

# ╔═╡ 5db0de06-6087-4b01-8e9e-23613d687e71
function binding_from(expr::Expr, workspace::Module=PlutoRunner.current_module)
	# $(...).x where $(...) is a pure expression that resolves to a Module
	# should yield a Binding($(...), :x) instead of the object itself
    try
		module_expr, binding_var = Docs.splitexpr(expr)
		if is_pure_expression(expr)
			binding_mod = Core.eval(workspace, module_expr)
			return Docs.Binding(binding_mod, binding_var.value)
		end
	catch; end
		
	if is_pure_expression(expr)
		Core.eval(workspace, expr)
	else
		error("Couldn't infer `$expr` for Live Docs.")
	end
end


# ╔═╡ b97fca48-4030-4e91-9732-5465ecd0a400
Docs.doc(binding_from(:(ParentMod.DocsMod.function_with_doc)))

# ╔═╡ 81c84585-73c7-4f0f-ab89-fd99a3aa7c04
Docs.doc(binding_from(:(ParentMod.BorrowMod.function_with_doc)))

# ╔═╡ 9e4de697-a50b-420e-886b-6671c5532e95
Docs.doc(binding_from(:(ParentMod.BorrowMod.function_without_doc)))

# ╔═╡ cfc24343-a49a-47e9-b3db-b54609965403
Docs.doc(binding_from(:(ParentMod.DocsMod.reassigned_function)))

# ╔═╡ 560ac947-3b9f-4956-b3be-6f73eb2991cc
Docs.doc(binding_from(:(ParentMod.DocsMod.function_with_multiple_docs)))

# ╔═╡ c760cfd4-67ea-46b2-aa26-b1f9f1dc9003
Docs.doc(binding_from(:(ParentMod.DocsMod.function_with_multiple_docs)), Tuple{})

# ╔═╡ b1c1baff-3a49-472d-ae69-b6cd7b75ca95
Docs.doc(binding_from(:(ParentMod.DocsMod.function_with_multiple_docs)), Tuple{Number})

# ╔═╡ 74a5506c-23dd-430b-8b87-7f3b41b8905c
Docs.doc(binding_from(:(ParentMod.DocsMod.variable_with_doc)))

# ╔═╡ f833afe9-eec6-46d1-9209-d6080faea6cb
Docs.doc(binding_from(:(ParentMod.DocsMod.variable_without_doc))).meta

# ╔═╡ 5ccb0ea0-cecc-4891-91bd-b577875353e9
multidocs = Docs.doc(binding_from(:(ParentMod.DocsMod.function_with_multiple_docs)), Tuple{String})

# ╔═╡ ffc8c3df-9cd5-443b-a06a-f18f3215f1a3
multidocs.meta

# ╔═╡ e5720830-e74c-46f4-97c5-726bf7d2d9de


# ╔═╡ 082613ef-effa-4411-8f7c-b9dd04105f65
md"## Autocompletion"

# ╔═╡ 6ff13e19-7c4d-4225-b0de-d9145f136d7e
Base.incomplete_tag("1 +=")

# ╔═╡ 128a363f-f686-40af-a677-ca306b82944a
struct Atom
	value
end

# ╔═╡ 6db5a077-d3a5-4234-ace3-d13e61fdde00
fff = Dict(:x => Dict(:y => 10))

# ╔═╡ 3654ab64-5f91-49e3-bdc2-80bd0a611501


# ╔═╡ ed23ed7e-e1a3-4a5e-a0bf-79b2ec60312c
root = Atom(10)

# ╔═╡ d35bae23-cfe9-4191-b0fb-274f76bae66c
root.value

# ╔═╡ 8a4a58c2-f301-47ca-9e48-6b95e17afe62
root_2 = Atom([Atom(10), Atom(20)])

# ╔═╡ e0563a78-1931-4ddb-b279-c849d75ced3d
root_2.value[1].

# ╔═╡ 7463f458-f02a-4eed-870e-af4e13d9ebbe
md"## Remove bindings from Docs"

# ╔═╡ 3b91118f-e30e-46aa-a5ef-da5700c56751
Docs.modules

# ╔═╡ fab777b8-9b65-488e-a034-f5c14f380aac
binding_to_check = begin
	"1"
	function x() end
	"2"
	function x(x) end
	
	mapthis = Docs.meta(@__MODULE__)
	
	for (key, value) in mapthis
		@info "thing" key value
	end
	
	binding = Docs.Binding(@__MODULE__, :x)
	
	Docs.meta(binding.mod)[Docs.Binding(@__MODULE__, :y)] = Docs.meta(binding.mod)[Docs.Binding(@__MODULE__, :x)]
	
	# pop!(Base.Docs.meta(binding.mod)[binding].order)
	
	binding
end

# ╔═╡ 2856570c-9c5c-4f24-ae47-4d8ceee3958f
function remove_module_from_docs(old_workspace)
	# Remove old module from docs
    filter!(Docs.modules) do mod
        mod != old_workspace
    end
end

# ╔═╡ e0daacb5-5c1d-42d3-a30c-99787468f424
Docs.doc(binding_to_check)

# ╔═╡ 82c8a532-18ed-4641-9a9a-44a5696fd8d5
Docs.doc(Docs.Binding(binding_to_check.mod, :y))

# ╔═╡ 41dc720f-6806-4b3e-864c-ebcf538a1aec
Docs.meta(binding_to_check.mod)

# ╔═╡ 7834a1b4-8a55-4988-8f4d-62b828e92541
Docs.meta(binding_to_check.mod)[binding_to_check].order

# ╔═╡ a87a7a3e-43ca-4df8-ba62-dc4315f05c83
begin
	sig = Union{}
	results, groups = Docs.DocStr[], Docs.MultiDoc[]
    # Lookup `binding` and `sig` for matches in all modules of the docsystem.
    for mod in Docs.modules
        dict = Docs.meta(mod)
        if haskey(dict, binding)
            multidoc = dict[binding]
            push!(groups, multidoc)
            for msig in multidoc.order
                sig <: msig && push!(results, multidoc.docs[msig])
            end
        end
    end
	groups
end

# ╔═╡ Cell order:
# ╠═8c24c5ae-84f0-11eb-1ab5-2f763486c5e6
# ╠═14ac032c-376a-491d-a5af-2a5ce2066921
# ╠═37d7def9-4f8e-4058-a0b0-ff9936fb0e35
# ╠═3c1b1268-bc57-41dc-98db-dd8361c1bcbe
# ╠═70571a9d-4f76-4ddb-be3f-851c0f4de65d
# ╠═b97fca48-4030-4e91-9732-5465ecd0a400
# ╠═81c84585-73c7-4f0f-ab89-fd99a3aa7c04
# ╠═9e4de697-a50b-420e-886b-6671c5532e95
# ╠═cfc24343-a49a-47e9-b3db-b54609965403
# ╠═7b9d5eea-d9e0-4551-9787-f6405e6466d0
# ╠═1cad1626-a018-4878-894e-34660e6f627e
# ╠═560ac947-3b9f-4956-b3be-6f73eb2991cc
# ╠═c760cfd4-67ea-46b2-aa26-b1f9f1dc9003
# ╠═b1c1baff-3a49-472d-ae69-b6cd7b75ca95
# ╠═74a5506c-23dd-430b-8b87-7f3b41b8905c
# ╠═f833afe9-eec6-46d1-9209-d6080faea6cb
# ╠═18b9b905-b329-4ec1-96ad-05a5876aa97e
# ╠═b8194572-6537-470c-9fdf-8e04c853d2d4
# ╠═41fd9407-6c9f-489e-983f-3231fd2c70dc
# ╠═693420dc-88de-4836-bda9-56486c671858
# ╠═5ccb0ea0-cecc-4891-91bd-b577875353e9
# ╠═ffc8c3df-9cd5-443b-a06a-f18f3215f1a3
# ╠═2fac54ef-3a80-4950-90cb-a6b9a420dfa3
# ╠═6d877aa2-5d1f-437c-b8d8-cf0df80d98ac
# ╠═29f36768-bd2f-443c-8783-ea5acde06c0c
# ╠═6990a827-da52-4e89-a186-ec3d046c21a8
# ╠═97ca5b1a-a536-4efa-ad7c-57989b4c09a8
# ╠═67056d06-aa91-442d-b750-e4325a9452f4
# ╠═5db0de06-6087-4b01-8e9e-23613d687e71
# ╠═e5720830-e74c-46f4-97c5-726bf7d2d9de
# ╟─082613ef-effa-4411-8f7c-b9dd04105f65
# ╠═6ff13e19-7c4d-4225-b0de-d9145f136d7e
# ╠═128a363f-f686-40af-a677-ca306b82944a
# ╠═6db5a077-d3a5-4234-ace3-d13e61fdde00
# ╠═3654ab64-5f91-49e3-bdc2-80bd0a611501
# ╠═ed23ed7e-e1a3-4a5e-a0bf-79b2ec60312c
# ╠═d35bae23-cfe9-4191-b0fb-274f76bae66c
# ╠═8a4a58c2-f301-47ca-9e48-6b95e17afe62
# ╠═e0563a78-1931-4ddb-b279-c849d75ced3d
# ╟─7463f458-f02a-4eed-870e-af4e13d9ebbe
# ╠═3b91118f-e30e-46aa-a5ef-da5700c56751
# ╠═fab777b8-9b65-488e-a034-f5c14f380aac
# ╠═2856570c-9c5c-4f24-ae47-4d8ceee3958f
# ╠═e0daacb5-5c1d-42d3-a30c-99787468f424
# ╠═82c8a532-18ed-4641-9a9a-44a5696fd8d5
# ╠═41dc720f-6806-4b3e-864c-ebcf538a1aec
# ╠═7834a1b4-8a55-4988-8f4d-62b828e92541
# ╠═a87a7a3e-43ca-4df8-ba62-dc4315f05c83
