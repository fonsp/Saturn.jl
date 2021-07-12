import UUIDs: UUID, uuid1
import .ExpressionExplorer: SymbolsState, UsingsImports

Base.@kwdef struct CellOutput
    body::Union{Nothing,String,Vector{UInt8},Dict}=nothing
    mime::MIME=MIME("text/plain")
    rootassignee::Union{Symbol,Nothing}=nothing

    "Time that the last output was created, used only on the frontend to rerender the output"
    last_run_timestamp::Float64=0
    
    "Whether `this` inside `<script id=something>` should refer to the previously returned object in HTML output. This is used for fancy animations. true iff a cell runs as a reactive consequence."
    persist_js_state::Bool=false
end

struct CellDependencies{T} # T == Cell, but this has to be parametric to avoid a circular dependency of the structs
    downstream_cells_map::Dict{Symbol,Vector{T}}
    upstream_cells_map::Dict{Symbol,Vector{T}}
    precedence_heuristic::Int
    contains_user_defined_macrocalls::Bool
end

"The building block of a `Notebook`. Contains code, output, reactivity data, mitochondria and ribosomes."
Base.@kwdef mutable struct Cell
    "Because Cells can be reordered, they get a UUID. The JavaScript frontend indexes cells using the UUID."
    cell_id::UUID=uuid1()

    code::String=""
    code_folded::Bool=false
    
    output::CellOutput=CellOutput()
    queued::Bool=false
    running::Bool=false

    published_objects::Dict{String,Any}=Dict{String,Any}()
    
    errored::Bool=false
    runtime::Union{Nothing,UInt64}=nothing

    # note that this field might be moved somewhere else later. If you are interested in visualizing the cell dependencies, take a look at the cell_dependencies field in the frontend instead.
    cell_dependencies::CellDependencies{Cell}=CellDependencies{Cell}(Dict{Symbol,Vector{Cell}}(), Dict{Symbol,Vector{Cell}}(), 99, false)

    running_disabled::Bool=false
    depends_on_disabled_cells::Bool=false
end

Cell(cell_id, code) = Cell(cell_id=cell_id, code=code)
Cell(code) = Cell(uuid1(), code)

cell_id(cell::Cell) = cell.cell_id

function Base.convert(::Type{Cell}, cell::Dict)
	Cell(
        cell_id=UUID(cell["cell_id"]),
        code=cell["code"],
        code_folded=cell["code_folded"],
        running_disabled=cell["running_disabled"],
    )
end
function Base.convert(::Type{UUID}, string::String)
    UUID(string)
end
