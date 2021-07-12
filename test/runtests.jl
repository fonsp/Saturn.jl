include("./helpers.jl")

# tests that start new processes:
include("./WorkspaceManager.jl")
include("./packages/Basic.jl")
VERSION > v"1.6.99" || include("./RichOutput.jl")
include("./React.jl")
include("./Dynamic.jl")
include("./MacroAnalysis.jl")

# for SOME reason 😞 the Notebook.jl tests need to run AFTER all the tests above, or the Github Actions runner on Windows gets internal julia errors.
include("./Notebook.jl")

# tests that don't start new processes:
include("./packages/PkgCompat.jl")
include("./ExpressionExplorer.jl")
include("./MethodSignatures.jl")
VERSION > v"1.6.99" || include("./Configuration.jl")
include("./Analysis.jl")
include("./Firebasey.jl")
include("./DependencyCache.jl")
include("./Throttled.jl")
include("./cell_disabling.jl")

# TODO: test PlutoRunner functions like:
# - from_this_notebook

# TODO: test include() inside notebooks

# TODO: test async execution order
# TODO: test @bind

# TODO: test if notebooks are saved correctly after edits
