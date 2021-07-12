using Test

#= 
`@test_broken` means that the test doesn't pass right now, but we want it to pass. Feel free to try to fix it and open a PR!
Some of these @test_broken lines are commented out to prevent printing to the terminal, but we still want them fixed.

# When working on ExpressionExplorer:

- Go to runtests.jl and move `include("ExpressionExplorer.jl")` to the second line, so that they run instantly (after loading the helper functions). Be careful not to commit this change.
- If you are fixing a `@test_broken`:
  - uncomment that line if needed
  - change `@test_broken` to `@test`
  - remove `verbose=false` at the end of the line
- If you are fixing something else:
  - you can add lots of tests! They run super fast, don't worry about duplicates too much

-fons =#

@testset "Explore Expressions" begin
    @testset "Basics" begin
        @test testee(:(a), [:a], [], [], [])
        @test testee(:(1 + 1), [], [], [:+], [])
        @test testee(:(sqrt(1)), [], [], [:sqrt], [])
        @test testee(:(x = 3), [], [:x], [], [])
        @test testee(:(x = x), [:x], [:x], [], [])
        @test testee(:(x = 1 + y), [:y], [:x], [:+], [])
        @test testee(:(x = +(a...)), [:a], [:x], [:+], [])
        @test testee(:(1:3), [], [], [:(:)], [])
    end
    @testset "Bad code" begin
        # @test_nowarn testee(:(begin end = 2), [:+], [], [:+], [], verbose=false)
        @test testee(:(123 = x), [:x], [], [], [])
        @test_nowarn testee(:((a = b, c, d = 123,)), [:b], [], [], [], verbose=false)
        @test_nowarn testee(:((a = b, c[r] = 2, d = 123,)), [:b], [], [], [], verbose=false)

        @test_nowarn testee(:(function f(function g() end) end), [], [], [:+], [], verbose=false)
        @test_nowarn testee(:(function f() Base.sqrt(x::String) = 2; end), [], [], [:+], [], verbose=false)
        @test_nowarn testee(:(function f() global g(x) = x; end), [], [], [], [], verbose=false)
    end
    @testset "Lists and structs" begin
        @test testee(:(1:3), [], [], [:(:)], [])
        @test testee(:(a[1:3,4]), [:a], [], [:(:)], [])
        @test testee(:(a[b]), [:a, :b], [], [], [])
        @test testee(:([a[1:3,4]; b[5]]), [:b, :a], [], [:(:)], [])
        @test testee(:(a.someproperty), [:a], [], [], []) # `a` can also be a module
        @test testee(:([a..., b]), [:a, :b], [], [], [])
        @test testee(:(struct a; b; c; end), [], [:a], [], [
            :a => ([], [], [], [])
            ])
        @test testee(:(let struct a; b; c; end end), [], [:a], [], [
            :a => ([], [], [], [])
            ])

        @test testee(:(module a; f(x) = x; z = r end), [], [:a], [], [])
    end
    @testset "Types" begin
        @test testee(:(x::Foo = 3), [:Foo], [:x], [], [])
        @test testee(:(x::Foo), [:x, :Foo], [], [], [])
        @test testee(:(a::Foo, b::String = 1, "2"), [:Foo, :String], [:a, :b], [], [])
        @test testee(:(Foo[]), [:Foo], [], [], [])
        @test testee(:(x isa Foo), [:x, :Foo], [], [:isa], [])

        @test testee(:(A{B} = B), [], [:A], [], [])
        @test testee(:(A{T} = Union{T,Int}), [:Int, :Union], [:A], [], [])

        @test testee(:(abstract type a end), [], [:a], [], [:a => ([], [], [], [])])
        @test testee(:(abstract type a <: b end), [], [:a], [], [:a => ([:b], [], [], [])])
        @test testee(:(abstract type a <: b{C} end), [], [:a], [], [:a => ([:b, :C], [], [], [])])
        @test testee(:(abstract type a{T} end), [], [:a], [], [:a => ([], [], [], [])])
        @test testee(:(abstract type a{T,S} end), [], [:a], [], [:a => ([], [], [], [])])
        @test testee(:(abstract type a{T} <: b end), [], [:a], [], [:a => ([:b], [], [], [])])
        @test testee(:(abstract type a{T} <: b{T} end), [], [:a], [], [:a => ([:b], [], [], [])])
        @test_nowarn testee(macroexpand(Main, :(@enum a b c)), [], [], [], []; verbose=false)
        
        e = :(struct a end) # needs to be on its own line to create LineNumberNode
        @test testee(e, [], [:a], [], [:a => ([], [], [], [])])
        @test testee(:(struct a <: b; c; d::Foo; end), [], [:a], [], [:a => ([:b, :Foo], [], [], [])])
        @test testee(:(struct a{T,S}; c::T; d::Foo; end), [], [:a], [], [:a => ([:Foo], [], [], [])])
        @test testee(:(struct a{T} <: b; c; d::Foo; end), [], [:a], [], [:a => ([:b, :Foo], [], [], [])])
        @test testee(:(struct a{T} <: b{T}; c; d::Foo; end), [], [:a], [], [:a => ([:b, :Foo], [], [], [])])
        @test testee(:(struct a; c; a(x=y) = new(x, z); end), [], [:a], [], [:a => ([:y, :z], [], [:new], [])])
        # @test_broken testee(:(struct a; c; a(x=y) = new(x,z); end), [], [:a], [], [:a => ([:y, :z], [], [], [])], verbose=false)
    end
    @testset "Assignment operator & modifiers" begin
        # https://github.com/JuliaLang/julia/blob/f449765943ba414bd57c3d1a44a73e5a0bb27534/base/docs/basedocs.jl#L239-L244
        @test testee(:(a = a), [:a], [:a], [], [])
        @test testee(:(a = a + 1), [:a], [:a], [:+], [])
        @test testee(:(x = a = a + 1), [:a], [:a, :x], [:+], [])
        @test testee(:(const a = b), [:b], [:a], [], [])
        @test testee(:(f(x) = x), [], [], [], [:f => ([], [], [], [])])
        @test testee(:(a[b,c,:] = d), [:a, :b, :c, :d, :(:)], [], [], [])
        @test testee(:(a.b = c), [:a, :c], [], [], [])
        @test testee(:(f(a, b=c, d=e; f=g)), [:a, :c, :e, :g], [], [:f], [])
        
        @test testee(:(a += 1), [:a], [:a], [:+], [])
        @test testee(:(a >>>= 1), [:a], [:a], [:>>>], [])
        @test testee(:(a ⊻= 1), [:a], [:a], [:⊻], [])
        @test testee(:(a[1] += 1), [:a], [], [:+], [])
        @test testee(:(x = let a = 1; a += b end), [:b], [:x], [:+], [])
        @test testee(:(_ = a + 1), [:a], [], [:+], [])
        @test testee(:(a = _ + 1), [], [:a], [:+], [])
    end
    @testset "Tuples" begin
        @test testee(:((a, b,)), [:a,:b], [], [], [])
        @test testee(:((a = b, c = 2, d = 123,)), [:b], [], [], [])
        @test testee(:((a = b,)), [:b], [], [], [])
        @test testee(:(a, b = 1, 2), [], [:a, :b], [], [])
        @test testee(:(a, _, c, __ = 1, 2, 3, _d), [:_d], [:a, :c], [], [])
        @test testee(:(const a, b = 1, 2), [], [:a, :b], [], [])
        @test testee(:((a, b) = 1, 2), [], [:a, :b], [], [])
        @test testee(:(a = b, c), [:b, :c], [:a], [], [])
        @test testee(:(a, b = c), [:c], [:a, :b], [], [])
        @test testee(:(a = (b, c)), [:b, :c], [:a], [], [])
        @test testee(:(a, (b, c) = [e,[f,g]]), [:e, :f, :g], [:a, :b, :c], [], [])
        @test testee(:((x, y), a, (b, c) = z, e, (f, g)), [:z, :e, :f, :g], [:x, :y, :a, :b, :c], [], [])
        @test testee(:((x[i], y.r), a, (b, c) = z, e, (f, g)), [:x, :i, :y, :z, :e, :f, :g], [:a, :b, :c], [], [])
        @test testee(:((a[i], b.r) = (c.d, 2)), [:a, :b, :i, :c], [], [], [])
    end
    @testset "Broadcasting" begin
        @test testee(:(a .= b), [:b, :a], [], [], []) # modifies elements, doesn't set `a`
        @test testee(:(a .+= b), [:b, :a], [], [:+], [])
        @test testee(:(a[i] .+= b), [:b, :a, :i], [], [:+], [])
        @test testee(:(a .+ b ./ sqrt.(c, d)), [:a, :b, :c, :d], [], [:+, :/, :sqrt], [])
    end
    @testset "`for` & `while`" begin
        @test testee(:(for k in 1:n; k + s; end), [:n, :s], [], [:+, :(:)], [])
        @test testee(:(for k in 1:2, r in 3:4; global z = k + r; end), [], [:z], [:+, :(:)], [])
        @test testee(:(while k < 2; r = w; global z = k + r; end), [:k, :w], [:z], [:+, :(<)], [])
    end
    @testset "`try` & `catch`" begin
        @test testee(:(try a = b + 1 catch; end), [:b], [], [:+], [])
        @test testee(:(try a() catch e; e end), [], [], [:a], [])
        @test testee(:(try a() catch; e end), [:e], [], [:a], [])
        @test testee(:(try a + 1 catch a; a end), [:a], [], [:+], [])
        @test testee(:(try 1 catch e; e finally a end), [:a], [], [], [])
        @test testee(:(try 1 finally a end), [:a], [], [], [])
    end
    @testset "Comprehensions" begin
        @test testee(:([sqrt(s) for s in 1:n]), [:n], [], [:sqrt, :(:)], [])
        @test testee(:([sqrt(s + r) for s in 1:n, r in k]), [:n, :k], [], [:sqrt, :(:), :+], [])
        @test testee(:([s + j + r + m for s in 1:3 for j in 4:5 for (r, l) in [(1, 2)]]), [:m], [], [:+, :(:)], [])
        @test testee(:([a for a in b if a != 2]), [:b], [], [:(!=)], [])
        @test testee(:([a for a in f() if g(a)]), [], [], [:f, :g], [])
        @test testee(:([c(a) for a in f() if g(a)]), [], [], [:c, :f, :g], [])

        @test testee(:([a for a in a]), [:a], [], [], [])
        @test testee(:(for a in a; a; end), [:a], [], [], [])
        @test testee(:(let a = a; a; end), [:a], [], [], [])
        @test testee(:(let a = a end), [:a], [], [], [])
        @test testee(:(let a = b end), [:b], [], [], [])
        @test testee(:(a = a), [:a], [:a], [], [])
        @test testee(:(a = [a for a in a]), [:a], [:a], [], [])
    end
    @testset "Multiple expressions" begin
        @test testee(:(x = let r = 1; r + r end), [], [:x], [:+], [])
        @test testee(:(begin let r = 1; r + r end; r = 2 end), [], [:r], [:+], [])
        @test testee(:((k = 2; 123)), [], [:k], [], [])
        @test testee(:((a = 1; b = a + 1)), [], [:a, :b], [:+], [])
        @test testee(Meta.parse("a = 1; b = a + 1"), [], [:a, :b], [:+], [])
        @test testee(:((a = b = 1)), [], [:a, :b], [], [])
        @test testee(:(let k = 2; 123 end), [], [], [], [])
        @test testee(:(let k() = 2 end), [], [], [], [])
    end
    @testset "Functions" begin
        @test testee(:(function g() r = 2; r end), [], [], [], [
            :g => ([], [], [], [])
        ])
        @test testee(:(function g end), [], [], [], [
            :g => ([], [], [], [])
        ])
        @test testee(:(function f() g(x) = x; end), [], [], [], [
            :f => ([], [], [], []) # g is not a global def
        ])
        @test_broken testee(:(function f(z) g(x) = x; g(z) end), [], [], [], [
            :f => ([], [], [], [])
        ]; verbose=false)
        @test testee(:(function f(x, y=1; r, s=3 + 3) r + s + x * y * z end), [], [], [], [
            :f => ([:z], [], [:+, :*], [])
        ])
        @test testee(:(function f(x) x * y * z end), [], [], [], [
            :f => ([:y, :z], [], [:*], [])
        ])
        @test testee(:(function f(x) x = x / 3; x end), [], [], [], [
            :f => ([], [], [:/], [])
        ])
        @test testee(:(function f(x) a end; function f(x, y) b end), [], [], [], [
            :f => ([:a, :b], [], [], [])
        ])
        @test testee(:(function f(x, args...; kwargs...) return [x, y, args..., kwargs...] end), [], [], [], [
            :f => ([:y], [], [], [])
        ])
        @test testee(:(function f(x; y=x) y + x end), [], [], [], [
            :f => ([], [], [:+], [])
        ])
        @test testee(:(function (A::MyType)(x; y=x) y + x end), [], [], [], [
            :MyType => ([], [], [:+], [])
        ])
        @test testee(:(f(x, y=a + 1) = x * y * z), [], [], [], [
            :f => ([:z, :a], [], [:*, :+], [])
        ])
        @test testee(:(begin f() = 1; f end), [], [], [], [
            :f => ([], [], [], [])
        ])
        @test testee(:(begin f() = 1; f() end), [], [], [], [
            :f => ([], [], [], [])
        ])
        @test testee(:(begin
                f(x) = (global a = √b)
                f(x, y) = (global c = -d)
            end), [], [], [], [
            :f => ([:b, :d], [:a, :c], [:√, :-], [])
        ])
        @test testee(:(Base.show() = 0), [:Base], [], [], [
            [:Base, :show] => ([], [], [], [])
        ])
        @test testee(:((x;p) -> f(x+p)), [], [], [], [
            :anon => ([], [], [:f, :+], [])
        ])
        @test testee(:(begin x; p end -> f(x+p)), [], [], [], [
            :anon => ([], [], [:f, :+], [])
        ])
        @test testee(:(minimum(x) do (a, b); a + b end), [:x], [], [:minimum], [
            :anon => ([], [], [:+], [])
        ])
        @test testee(:(f = x -> x * y), [], [:f], [], [
            :anon => ([:y], [], [:*], [])
        ])
        @test testee(:(f = (x, y) -> x * y), [], [:f], [], [
            :anon => ([], [], [:*], [])
        ])
        @test testee(:(f = (x, y = a + 1) -> x * y), [], [:f], [], [
            :anon => ([:a], [], [:*, :+], [])
        ])
        @test testee(:((((a, b), c), (d, e)) -> a * b * c * d * e * f), [], [], [], [
            :anon => ([:f], [], [:*], [])
        ])
        @test testee(:((a...) -> f(a...)), [], [], [], [
            :anon => ([], [], [:f], [])
        ])
        @test testee(:(f = (args...) -> [args..., y]), [], [:f], [], [
            :anon => ([:y], [], [], [])
        ])
        @test testee(:(f = (x, args...; kwargs...) -> [x, y, args..., kwargs...]), [], [:f], [], [
            :anon => ([:y], [], [], [])
        ])
        @test testee(:(f = function (a, b) a + b * n end), [:n], [:f], [:+, :*], [])
        @test testee(:(f = function () a + b end), [:a, :b], [:f], [:+], [])

        @test testee(:(func(a)), [:a], [], [:func], [])
        @test testee(:(func(a; b=c)), [:a, :c], [], [:func], [])
        @test testee(:(func(a, b=c)), [:a, :c], [], [:func], [])
        @test testee(:(√ b), [:b], [], [:√], [])
        @test testee(:(funcs[i](b)), [:funcs, :i, :b], [], [], [])
        @test testee(:(f(a)(b)), [:a, :b], [], [:f], [])
        @test testee(:(f(a).b()), [:a], [], [:f], [])

        @test testee(:(a.b(c)), [:a, :c], [], [[:a,:b]], [])
        @test testee(:(a.b.c(d)), [:a, :d], [], [[:a,:b,:c]], [])
        @test testee(:(a.b(c)(d)), [:a, :c, :d], [], [[:a,:b]], [])
        @test testee(:(a.b(c).d(e)), [:a, :c, :e], [], [[:a,:b]], [])
        @test testee(:(a.b[c].d(e)), [:a, :c, :e], [], [], [])
    end
    @testset "Functions & types" begin
        @test testee(:(function f(y::Int64=a)::String string(y) end), [], [], [], [
            :f => ([:String, :Int64, :a], [], [:string], [])
        ])
        @test testee(:(f(a::A)::C = a.a;), [], [], [], [
            :f => ([:A, :C], [], [], [])
        ])
        @test testee(:(function f(x::T; k=1) where T return x + 1 end), [], [], [], [
            :f => ([], [], [:+], [])
        ])
        @test testee(:(function f(x::T; k=1) where {T,S <: R} return x + 1 end), [], [], [], [
            :f => ([:R], [], [:+], [])
        ])
        @test testee(:(f(x)::String = x), [], [], [], [
            :f => ([:String], [], [], [])
        ])
        @test testee(:(MIME"text/html"), [], [], [], [], [Symbol("@MIME_str")])
        @test testee(:(function f(::MIME"text/html") 1 end), [], [], [], [
            :f => ([], [], [], [], [Symbol("@MIME_str")])
        ])
        @test testee(:(a(a::AbstractArray{T}) where T = 5), [], [], [], [
            :a => ([:AbstractArray], [], [], [])
        ])
        @test testee(:(a(a::AbstractArray{T,R}) where {T,S} = a + b), [], [], [], [
            :a => ([:AbstractArray, :b, :R], [], [:+], [])
        ])
        @test testee(:(f(::A) = 1), [], [], [], [
            :f => ([:A], [], [], [])
        ])
        @test testee(:(f(::A, ::B) = 1), [], [], [], [
            :f => ([:A, :B], [], [], [])
        ])
        @test testee(:(f(a::A, ::B, c::C...) = a + c), [], [], [], [
            :f => ([:A, :B, :C], [], [:+], [])
        ])

        @test testee(:((obj::MyType)(x,y) = x + z), [], [], [], [
            :MyType => ([:z], [], [:+], [])
        ])
        @test testee(:((obj::MyType)() = 1), [], [], [], [
            :MyType => ([], [], [], [])
        ])
        @test testee(:((obj::MyType)(x, args...; kwargs...) = [x, y, args..., kwargs...]), [], [], [], [
            :MyType => ([:y], [], [], [])
        ])
        @test testee(:(function (obj::MyType)(x, y) x + z end), [], [], [], [
            :MyType => ([:z], [], [:+], [])
        ])
        @test testee(:(begin struct MyType x::String end; (obj::MyType)(y) = obj.x + y; end), [], [:MyType], [], [
            :MyType => ([:String], [], [:+], [])
        ])
        @test testee(:(begin struct MyType x::String end; function(obj::MyType)(y) obj.x + y; end; end), [], [:MyType], [], [
            :MyType => ([:String], [], [:+], [])
        ])
        @test testee(:((::MyType)(x,y) = x + y), [], [], [], [
            :MyType => ([], [], [:+], [])
        ])
    end
    @testset "Scope modifiers" begin
        @test testee(:(let global a, b = 1, 2 end), [], [:a, :b], [], [])
        @test_broken testee(:(let global a = b = 1 end), [], [:a], [], []; verbose=false)
        @test testee(:(let global k = 3 end), [], [:k], [], [])
        @test_broken testee(:(let global k = r end), [], [:k], [], []; verbose=false)
        @test testee(:(let global k = 3; k end), [], [:k], [], [])
        @test testee(:(let global k += 3 end), [:k], [:k], [:+], [])
        @test testee(:(let global k; k = 4 end), [], [:k], [], [])
        @test testee(:(let global k; b = 5 end), [], [], [], [])
        @test testee(:(let a = 1, b = 2; show(a + b) end), [], [], [:show, :+], [])

        @test testee(:(begin local a, b = 1, 2 end), [], [], [], [])
        @test testee(:(begin local a = b = 1 end), [], [:b], [], [])
        @test testee(:(begin local k = 3 end), [], [], [], [])
        @test testee(:(begin local k = r end), [:r], [], [], [])
        @test testee(:(begin local k = 3; k; b = 4 end), [], [:b], [], [])
        @test testee(:(begin local k += 3 end), [], [], [:+], []) # does not reference global k
        @test testee(:(begin local k; k = 4 end), [], [], [], [])
        @test testee(:(begin local k; b = 5 end), [], [:b], [], [])
        @test testee(:(begin local r[1] = 5 end), [:r], [], [], [])
        @test_broken testee(:(begin begin local a = 2 end; a end), [:a], [], [], []; verbose=false)
        
        @test testee(:(function f(x) global k = x end), [], [], [], [
            :f => ([], [:k], [], [])
        ])
        @test testee(:((begin x = 1 end, y)), [:y], [:x], [], [])
        @test testee(:(x = let global a += 1 end), [:a], [:x, :a], [:+], [])
    end
    @testset "`import` & `using`" begin
        @test testee(:(using Plots), [], [:Plots], [], [])
        @test testee(:(using Plots.ExpressionExplorer), [], [:ExpressionExplorer], [], [])
        @test testee(:(using JSON, UUIDs), [], [:JSON, :UUIDs], [], [])
        @test testee(:(import Pluto), [], [:Pluto], [], [])
        @test testee(:(import Pluto: wow, wowie), [], [:wow, :wowie], [], [])
        @test testee(:(import Pluto.ExpressionExplorer.wow, Plutowie), [], [:wow, :Plutowie], [], [])
        @test testee(:(import .Pluto: wow), [], [:wow], [], [])
        @test testee(:(import ..Pluto: wow), [], [:wow], [], [])
        @test testee(:(let; import Pluto.wow, Dates; end), [], [:wow, :Dates], [], [])
        @test testee(:(while false; import Pluto.wow, Dates; end), [], [:wow, :Dates], [], [])
        @test testee(:(try; using Pluto.wow, Dates; catch; end), [], [:wow, :Dates], [], [])
        @test testee(:(module A; import B end), [], [:A], [], [])
    end
    @testset "Foreign macros" begin
        # parameterizedfunctions
        @test testee(quote
        f = @ode_def LotkaVolterra begin
            dx = a*x - b*x*y
            dy = -c*y + d*x*y
          end a b c d
        end, [], [:f], [], [], [Symbol("@ode_def")])
        @test testee(quote
        f = @ode_def begin
            dx = a*x - b*x*y
            dy = -c*y + d*x*y
          end a b c d
        end, [], [:f], [], [], [Symbol("@ode_def")])
        # flux
        @test testee(:(@functor Asdf), [], [], [], [], [Symbol("@functor")])
        # symbolics
        @test testee(:(@variables a b c), [], [], [], [], [Symbol("@variables")])
        @test testee(:(@variables a b[1:2] c(t) d(..)), [], [], [], [], [Symbol("@variables")])
        @test testee(:(@variables a b[1:x] c[1:10](t) d(..)), [], [], [], [], [Symbol("@variables")])
        @test_nowarn testee(:(@variables(m, begin
            x
            y[i=1:2] >= i, (start = i, base_name = "Y_$i")
            z, Bin
        end)), [:m, :Bin], [:x, :y, :z], [Symbol("@variables")], [], verbose=false)
        # jump
    #     @test testee(:(@variable(m, x)), [:m], [:x], [Symbol("@variable")], [])
    #     @test testee(:(@variable(m, 1<=x)), [:m], [:x], [Symbol("@variable")], [])
    #     @test testee(:(@variable(m, 1<=x<=2)), [:m], [:x], [Symbol("@variable")], [])
    #     @test testee(:(@variable(m, r <= x[i=keys(asdf)] <= ub[i])), [:m, :r, :asdf, :ub], [:x], [:keys, Symbol("@variable")], [])
    #     @test testee(:(@variable(m, x, lower_bound=0)), [:m], [:x], [Symbol("@variable")], [])
    #     @test testee(:(@variable(m, base_name="x", lower_bound=0)), [:m], [], [Symbol("@variable")], [])
    #     @test testee(:(@variables(m, begin
    #     x
    #     y[i=1:2] >= i, (start = i, base_name = "Y_$i")
    #     z, Bin
    # end)), [:m, :Bin], [:x, :y, :z], [Symbol("@variables")], [])
    end
    @testset "Macros" begin
        # Macros tests are not just in ExpressionExplorer now

        @test testee(:(@time a = 2), [], [], [], [], [Symbol("@time")])
        @test testee(:(@f(x; y=z)), [], [], [], [], [Symbol("@f")])
        @test testee(:(@f(x, y = z)), [], [], [], [], [Symbol("@f")]) # https://github.com/fonsp/Pluto.jl/issues/252
        @test testee(:(Base.@time a = 2), [], [], [], [], [[:Base, Symbol("@time")]])
        # @test_nowarn testee(:(@enum a b = d c), [:d], [:a, :b, :c], [Symbol("@enum")], [])
        # @enum is tested in test/React.jl instead
        @test testee(:(@gensym a b c), [], [:a, :b, :c], [:gensym], [], [Symbol("@gensym")])
        @test testee(:(Base.@gensym a b c), [], [:a, :b, :c], [:gensym], [], [[:Base, Symbol("@gensym")]])
        @test testee(:(Base.@kwdef struct A; x = 1; y::Int = two; z end), [], [], [], [
            :A => ([:two], [], [], [])
        ], [[:Base, Symbol("@kwdef")], [:Base, Symbol("@__doc__")]])
        @test testee(quote "asdf" f(x) = x end, [], [], [], [], [Symbol("@doc")])

        @test testee(:(@bind a b), [:b, :PlutoRunner, :Base, :Core], [:a], [[:PlutoRunner, :Bond], [:Core, :applicable], [:Base, :get]], [], [Symbol("@bind")])
        @test testee(:(PlutoRunner.@bind a b), [:b, :PlutoRunner, :Base, :Core], [:a], [[:PlutoRunner, :Bond], [:Core, :applicable], [:Base, :get]], [], [[:PlutoRunner, Symbol("@bind")]])
        @test_broken testee(:(Main.PlutoRunner.@bind a b), [:b, :PlutoRunner, :Base, :Core], [:a], [[:Base, :get], [:Core, :applicable], [:PlutoRunner, :Bond], [:PlutoRunner, Symbol("@bind")]], [], verbose=false)
        @test testee(:(let @bind a b end), [:b, :PlutoRunner, :Base, :Core], [:a], [[:PlutoRunner, :Bond], [:Core, :applicable], [:Base, :get]], [], [Symbol("@bind")])

        @test testee(:(@asdf a = x1 b = x2 c = x3), [], [], [], [], [Symbol("@asdf")]) # https://github.com/fonsp/Pluto.jl/issues/670

        @test testee(:(@einsum a[i,j] := x[i]*y[j]), [], [], [], [], [Symbol("@einsum")])
        @test testee(:(@tullio a := f(x)[i+2j, k[j]] init=z), [], [], [], [], [Symbol("@tullio")])
        @test testee(:(Pack.@asdf a[1,k[j]] := log(x[i]/y[j])), [], [], [], [], [[:Pack, Symbol("@asdf")]])

        @test testee(:(`hey $(a = 1) $(b)`), [:b], [], [:cmd_gen], [], [Symbol("@cmd")])
        @test testee(:(md"hey $(@bind a b) $(a)"), [:b, :PlutoRunner, :Base, :Core], [:a], [[:PlutoRunner, :Bond], [:Core, :applicable], [:Base, :get], :getindex], [], [Symbol("@md_str"), Symbol("@bind")])
        @test testee(:(md"hey $(a) $(@bind a b)"), [:a, :b, :PlutoRunner, :Base, :Core], [:a], [[:PlutoRunner, :Bond], [:Core, :applicable], [:Base, :get], :getindex], [], [Symbol("@md_str"), Symbol("@bind")])
        @test testee(:(html"a $(b = c)"), [], [], [], [], [Symbol("@html_str")])
        @test testee(:(md"a $(b = c) $(b)"), [:c], [:b], [:getindex], [], [Symbol("@md_str")])
        @test testee(:(md"\* $r"), [:r], [], [:getindex], [], [Symbol("@md_str")])
        @test testee(:(md"a \$(b = c)"), [], [], [:getindex], [], [Symbol("@md_str")])
        @test testee(:(macro a() end), [], [], [], [
            Symbol("@a") => ([], [], [], [])
        ])
        @test testee(:(macro a(b::Int); b end), [], [], [], [
            Symbol("@a") => ([:Int], [], [], [])
        ])
        @test testee(:(macro a(b::Int=c) end), [], [], [], [
            Symbol("@a") => ([:Int, :c], [], [], [])
        ])
        @test testee(:(macro a(); b = c; return b end), [], [], [], [
            Symbol("@a") => ([:c], [], [], [])
        ])
    end
    @testset "String interpolation & expressions" begin
        @test testee(:("a $b"), [:b], [], [], [])
        @test testee(:("a $(b = c)"), [:c], [:b], [], [])
        # @test_broken testee(:(`a $b`), [:b], [], [], [])
        # @test_broken testee(:(`a $(b = c)`), [:c], [:b], [], [])
        @test testee(:(ex = :(yayo)), [], [:ex], [], [])
        @test testee(:(ex = :(yayo + $r)), [], [:ex], [], [])
        # @test_broken testee(:(ex = :(yayo + $r)), [:r], [:ex], [], [], verbose=false)
    end
    @testset "Extracting `using` and `import`" begin
        expr = quote
            using A
            import B
            if x
                using .C: r
                import ..D.E: f, g
            else
                import H.I, J, K.L
            end
            
            quote
                using Nonono
            end
        end
        result = ExpressionExplorer.compute_usings_imports(expr)
        @test result.usings == Set{Expr}([
            :(using A),
            :(using .C: r),
        ])
        @test result.imports == Set{Expr}([
            :(import B),
            :(import ..D.E: f, g),
            :(import H.I, J, K.L),
        ])

        @test ExpressionExplorer.external_package_names(result) == Set{Symbol}([
            :A, :B, :H, :J, :K
        ])

        @test ExpressionExplorer.external_package_names(:(using Plots, Something.Else, .LocalModule)) == Set([:Plots, :Something])
        @test ExpressionExplorer.external_package_names(:(import Plots.A: b, c)) == Set([:Plots])
    end
end
