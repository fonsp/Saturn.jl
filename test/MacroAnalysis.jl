using Test
import UUIDs
import Pluto: Notebook, WorkspaceManager, Cell, ServerSession, ClientSession, update_run!

@testset "Macro analysis" begin
    🍭 = ServerSession()
    🍭.options.evaluation.workspace_use_distributed = false

    fakeclient = ClientSession(:fake, nothing)
    🍭.connected_clients[fakeclient.id] = fakeclient

    @testset "Base macro call" begin
        notebook = Notebook([
            Cell("@enum Fruit 🍎 🍐"),
            Cell("my_fruit = 🍎"),
            Cell("jam(fruit::Fruit) = cook(fruit)"),
        ])
        cell(idx) = notebook.cells[idx]

        update_run!(🍭, notebook, notebook.cells)

        @test cell(1) |> noerror
        @test [:🍎, :🍐] ⊆ notebook.topology.nodes[cell(1)].definitions
        @test :Fruit ∈ notebook.topology.nodes[cell(1)].funcdefs_without_signatures
        @test Symbol("@enum") ∈ notebook.topology.nodes[cell(1)].references

        @test cell(2) |> noerror
        @test :🍎 ∈ notebook.topology.nodes[cell(2)].references

        @test cell(3) |> noerror
        @test :Fruit ∈ notebook.topology.nodes[cell(3)].references
    end

    @testset "User defined macro 1" begin
        notebook = Notebook([
            Cell("""macro my_assign(sym, val)
              :(\$(esc(sym)) = \$(val))
            end"""),
            Cell("@my_assign x 1+1"),
        ])
        cell(idx) = notebook.cells[idx]

        update_run!(🍭, notebook, notebook.cells)

        @test :x ∈ notebook.topology.nodes[cell(2)].definitions
        @test Symbol("@my_assign") ∈ notebook.topology.nodes[cell(2)].references

        update_run!(🍭, notebook, notebook.cells)

        # Works on second time because of old workspace
        @test :x ∈ notebook.topology.nodes[cell(2)].definitions
        @test Symbol("@my_assign") ∈ notebook.topology.nodes[cell(2)].references
    end
    
    @testset "User defined macro 2" begin
        notebook = Notebook([
            Cell("@my_identity(f(123))"),
            Cell(""),
            Cell(""),
        ])
        cell(idx) = notebook.cells[idx]

        update_run!(🍭, notebook, notebook.cells)
        
        setcode(cell(2), """macro my_identity(expr)
            esc(expr)
        end""")
        update_run!(🍭, notebook, cell(2))
        
        setcode(cell(3), "f(x) = x")
        update_run!(🍭, notebook, cell(3))
        
        @test cell(1) |> noerror
        @test cell(2) |> noerror
        @test cell(3) |> noerror
        @test cell(1).output.body == "123"
        
        update_run!(🍭, notebook, cell(1))
        @test cell(1) |> noerror
        @test cell(2) |> noerror
        @test cell(3) |> noerror
    end

    @testset "User defined macro 3" begin
        notebook = Notebook([
            Cell("""
            macro mymap()
                quote
                    [1, 2, 3] .|> sqrt
                end
            end
            """),
            Cell("@mymap")
        ])
        cell(idx) = notebook.cells[idx]

        update_run!(🍭, notebook, notebook.cells)

        @test cell(1) |> noerror
        @test cell(2) |> noerror

        update_run!(🍭, notebook, cell(1))

        @test cell(2) |> noerror
    end

    @testset "Package macro 1" begin
        notebook = Notebook([
            Cell("using Dates"),
            Cell("df = dateformat\"Y-m-d\""),
        ])
        cell(idx) = notebook.cells[idx]

        update_run!(🍭, notebook, cell(2))

        @test cell(2).errored == true
        @test occursinerror("UndefVarError: @dateformat_str", cell(2)) == true

        update_run!(🍭, notebook, notebook.cells)

        @test cell(1) |> noerror
        @test cell(2) |> noerror
        
        
        notebook = Notebook([
            Cell("using Dates"),
            Cell("df = dateformat\"Y-m-d\""),
        ])
        update_run!(🍭, notebook, notebook.cells)

        @test cell(1) |> noerror
        @test cell(2) |> noerror
    end

    @testset "Package macro 2" begin
        🍭.options.evaluation.workspace_use_distributed = true
        
        notebook = Notebook([
            Cell("z = x^2 + y"),
            Cell("@variables x y"),
            Cell("""
            begin
                import Pkg
                Pkg.activate(mktempdir())
                Pkg.add(Pkg.PackageSpec(name="Symbolics", version="1"))
                using Symbolics
            end
            """),
        ])
        cell(idx) = notebook.cells[idx]

        update_run!(🍭, notebook, notebook.cells)

        @test cell(1) |> noerror
        @test cell(2) |> noerror
        @test cell(3) |> noerror

        update_run!(🍭, notebook, cell(2))

        @test cell(1) |> noerror
        @test cell(2) |> noerror
        
        setcode(cell(2), "@variables 🐰 y")
        update_run!(🍭, notebook, cell(2))
        
        @test cell(1).errored
        @test cell(2) |> noerror
        
        
        setcode(cell(1), "z = 🐰^2 + y")
        update_run!(🍭, notebook, cell(1))
        
        @test cell(1) |> noerror
        @test cell(2) |> noerror
        
        WorkspaceManager.unmake_workspace((🍭, notebook))
        
        🍭.options.evaluation.workspace_use_distributed = false
    end

    @testset "Previous workspace for unknowns" begin
        notebook = Notebook([
            Cell("""macro my_identity(expr)
              expr
            end"""),
            Cell("(@__MODULE__, (@my_identity 1 + 1))"),
            Cell("@__MODULE__"),
        ])
        cell(idx) = notebook.cells[idx]

        update_run!(🍭, notebook, cell(1))
        update_run!(🍭, notebook, notebook.cells[2:end])

        @test cell(1) |> noerror
        @test cell(2) |> noerror
        @test cell(3) |> noerror

        module_from_cell2 = cell(2).output.body[:elements][1][2][1]
        module_from_cell3 = cell(3).output.body

        # Current limitation of using the previous module
        # for expansion of unknowns macros on the whole expression
        @test_broken module_from_cell2 == module_from_cell3
    end

    @testset "Definitions" begin
        notebook = Notebook([
            Cell("""macro my_assign(sym, val)
                :(\$(esc(sym)) = \$(val))
            end"""),
            Cell("c = :hello"),
            Cell("@my_assign b c"),
            Cell("b"),
        ])
        cell(idx) = notebook.cells[idx]

        update_run!(🍭, notebook, notebook.cells)
        update_run!(🍭, notebook, notebook.cells)

        @test ":hello" == cell(3).output.body
        @test ":hello" == cell(4).output.body
        @test :b ∈ notebook.topology.nodes[cell(3)].definitions
        @test [:c, Symbol("@my_assign")] ⊆ notebook.topology.nodes[cell(3)].references
        @test cell(3).cell_dependencies.contains_user_defined_macrocalls == true

        setcode(notebook.cells[2], "c = :world")
        update_run!(🍭, notebook, cell(2))

        @test ":world" == cell(3).output.body
        @test ":world" == cell(4).output.body
    end

    @testset "Macros using import" begin
        notebook = Notebook(Cell.([
            """
            @option "option_a" struct OptionA
                option_value::option_type
            end
            """,
            "option_type = String",
            "import Configurations: @option",
        ]))
        cell(idx) = notebook.cells[idx]

        update_run!(🍭, notebook, notebook.cells)

        @test :option_type ∈ notebook.topology.nodes[cell(1)].references
        @test cell(1) |> noerror
    end
end
