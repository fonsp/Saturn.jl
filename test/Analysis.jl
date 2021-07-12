using Test
import Pluto: Notebook, ServerSession, ClientSession, Cell, updated_topology, static_resolve_topology, is_just_text

@testset "Analysis" begin
    notebook = Notebook([
        Cell(""),
        Cell("md\"a\""),
        Cell("html\"a\""),
        Cell("md\"a \$b\$\""),
        Cell("md\"a ``b``\""),
        Cell("""
        let
            x = md"a"
            md"r \$x"
        end
        """),
        Cell("html\"a 7 \$b\""),

        Cell("md\"a 8 \$b\""),
        Cell("@a md\"asdf 9\""),
        Cell("x()"),
        Cell("x() = y()"),
        Cell("12 + 12"),
        Cell("import Dates"),
        Cell("import Dates"),
        Cell("while false end"),
        Cell("for i in [16]; end"),
        Cell("[i for i in [17]]"),
        Cell("module x18 end"),
        Cell("""
        module x19
            exit()
        end
        """),
        Cell("""quote end"""),
        Cell("""quote x = 21 end"""),
        Cell("""quote \$(x = 22) end"""),
        Cell("""asdf"23" """),
        Cell("""@asdf("24") """),
        Cell("""@x"""),
        Cell("""@y z 26"""),
        Cell("""f(g"27")"""),
    ])

    old = notebook.topology
    new = notebook.topology = updated_topology(old, notebook, notebook.cells) |> static_resolve_topology

    @testset "Only-text detection" begin
        @test is_just_text(new, notebook.cells[1])
        @test is_just_text(new, notebook.cells[2])
        @test is_just_text(new, notebook.cells[3])
        @test is_just_text(new, notebook.cells[4])
        @test is_just_text(new, notebook.cells[5])
        @test is_just_text(new, notebook.cells[6])
        @test is_just_text(new, notebook.cells[7])

        @test !is_just_text(new, notebook.cells[8])
        @test !is_just_text(new, notebook.cells[9])
        @test !is_just_text(new, notebook.cells[10])
        @test !is_just_text(new, notebook.cells[11])
        @test !is_just_text(new, notebook.cells[12])
        @test !is_just_text(new, notebook.cells[13])
        @test !is_just_text(new, notebook.cells[14])
        @test !is_just_text(new, notebook.cells[15])
        @test !is_just_text(new, notebook.cells[16])
        @test !is_just_text(new, notebook.cells[17])
        @test !is_just_text(new, notebook.cells[18])
        @test !is_just_text(new, notebook.cells[19])
        @test !is_just_text(new, notebook.cells[20])
        @test !is_just_text(new, notebook.cells[21])
        @test !is_just_text(new, notebook.cells[22])
        @test !is_just_text(new, notebook.cells[23])
        @test !is_just_text(new, notebook.cells[24])
        @test !is_just_text(new, notebook.cells[25])
        @test !is_just_text(new, notebook.cells[26])
        @test !is_just_text(new, notebook.cells[27])
    end
end
