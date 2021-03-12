import UUIDs: UUID, uuid1
import .ExpressionExplorer: SymbolsState

"The building block of a `Notebook`. Contains code, output, reactivity data, mitochondria and ribosomes."
Base.@kwdef mutable struct Cell
    "Because Cells can be reordered, they get a UUID. The JavaScript frontend indexes cells using the UUID."
    cell_id::UUID=uuid1()

    code::String=""
    # code_last_updated::Float64=0
    # code_last_updated_by::Union{String,Nothing}=nothing
    code_folded::Bool=false
    
    output_repr::Union{Nothing,String,Vector{UInt8},Dict}=nothing
    repr_mime::MIME=MIME("text/plain")
    errored::Bool=false
    runtime::Union{Nothing,UInt64}=nothing
    queued::Bool=false
    running::Bool=false

    "Time that the last output was created, used only on the frontend to rerender the output"
    last_run_timestamp::Float64=0
    "Whether `this` inside `<script id=something>` should refer to the previously returned object in HTML output. This is used for fancy animations. true iff a cell runs as a reactive consequence."
    persist_js_state::Bool=false
    
    parsedcode::Union{Nothing,Expr}=nothing
    module_usings::Set{Expr}=Set{Expr}()
    rootassignee::Union{Nothing,Symbol}=nothing
    function_wrapped::Bool=false

    # information to display cell dependencies
    downstream_cells_map::Dict{Symbol,Vector{Cell}}=Dict{Symbol,Vector{Cell}}()
    upstream_cells_map::Dict{Symbol,Vector{Cell}}=Dict{Symbol,Vector{Cell}}()
    precedence_heuristic::Int=99

    # execution barrier
    "user defined execution barrier"
    has_execution_barrier::Bool=false
    "is this barrier active? requires `has_execution_barrier=true`"
    barrier_is_active::Bool=false
    "is this cell deactivated, either by having itself an activated execution barrier or upstream?"
    is_deactivated::Bool=false

end

Cell(cell_id, code) = Cell(cell_id=cell_id, code=code)
Cell(code) = Cell(uuid1(), code)

cell_id(cell::Cell) = cell.cell_id

function Base.convert(::Type{Cell}, cell::Dict)
	Cell(
        cell_id=UUID(cell["cell_id"]),
        code=cell["code"],
        code_folded=cell["code_folded"],
        has_execution_barrier=cell["has_execution_barrier"],
    )
end
function Base.convert(::Type{UUID}, string::String)
    UUID(string)
end