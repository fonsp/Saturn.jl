module IntegrationsWithOtherPackages

import ..workspace_info
include("./Requires.jl/src/Requires.jl")

"Attempts to find the MIME pair corresponding to the extension of a filename. Defaults to `text/plain`."
function mime_fromfilename(filename)
    # This bad boy is from: https://developer.mozilla.org/en-US/docs/Web/HTTP/Basics_of_HTTP/MIME_types/Common_types
    mimepairs = Dict(".aac" => "audio/aac", ".bin" => "application/octet-stream", ".bmp" => "image/bmp", ".css" => "text/css", ".csv" => "text/csv", ".eot" => "application/vnd.ms-fontobject", ".gz" => "application/gzip", ".gif" => "image/gif", ".htm" => "text/html", ".html" => "text/html", ".ico" => "image/vnd.microsoft.icon", ".jpeg" => "image/jpeg", ".jpg" => "image/jpeg", ".js" => "text/javascript", ".json" => "application/json", ".jsonld" => "application/ld+json", ".mjs" => "text/javascript", ".mp3" => "audio/mpeg", ".mp4" => "video/mp4", ".mpeg" => "video/mpeg", ".oga" => "audio/ogg", ".ogv" => "video/ogg", ".ogx" => "application/ogg", ".opus" => "audio/opus", ".otf" => "font/otf", ".png" => "image/png", ".pdf" => "application/pdf", ".rtf" => "application/rtf", ".sh" => "application/x-sh", ".svg" => "image/svg+xml", ".tar" => "application/x-tar", ".tif" => "image/tiff", ".tiff" => "image/tiff", ".ttf" => "font/ttf", ".txt" => "text/plain", ".wav" => "audio/wav", ".weba" => "audio/webm", ".webm" => "video/webm", ".webp" => "image/webp", ".woff" => "font/woff", ".woff2" => "font/woff2", ".xhtml" => "application/xhtml+xml", ".xml" => "application/xml", ".xul" => "application/vnd.mozilla.xul+xml", ".zip" => "application/zip")
    file_extension = getkey(mimepairs, '.' * split(filename, '.')[end], ".txt")
    MIME(mimepairs[file_extension])
end

export handle_websocket_message, message_channel
"Called directly (through Distributed) from the main Pluto process"
function handle_websocket_message(message)
    try
        result = on_websocket_message(Val(Symbol(message[:module_name])), message[:body])
        if result !== nothing
            @warn """
            Integrations `on_websocket_message(:$(message[:module_name]), ...)` returned a value, but is expected to return `nothing`.

            If you want to send something back to the client, use `IntegrationsWithOtherPackages.message_channel`.
            """
        end
    catch ex
        bt = stacktrace(catch_backtrace())
        @error "Dispatching integrations websocket message failed:" message=message exception=(ex, bt)
    end
    nothing
end

"""
A [`Channel`](@ref) to send messages on demand to JS running in cell outputs. The message should be structured like the example below, and you can use any `MsgPack.jl`-encodable object in the body (including a `Vector{UInt8}` if that's your thing 👀).

# Example
```julia
put!(message_channel, Dict(
    :module_name => "WebIO",
    :body => mydata,
))
```
"""
const message_channel = Channel{Dict{Symbol,Any}}(10)

"""
Integrations should implement this to capture incoming websocket messages.
We force returning nothing, because returning might give you the idea that
the result is sent back to the client, which (right now) it isn't.
If you want to send something back to the client, use [`IntegrationsWithOtherPackages.message_channel`](@ref).

Do not call this function directly from notebook/package code!

    function on_websocket_message(::Val{:MyModule}, body)::Nothing
        # ...
    end
"""
function on_websocket_message(module_name, body)::Nothing
    error("No websocket message handler defined for '$(module_name)'")
end

function handle_http_request(request)
    try
        on_http_request(Val(Symbol(request[:module_name])), request)
    catch ex
        bt = stacktrace(catch_backtrace())
        @error "Dispatching integrations HTTP request failed:" request=request exception=(ex, bt)
    end
end

"""
Integrations should implement this to capture incoming http requests.
Expects to result in a Dict with at least `:status => Int`, but could include more,
as seen in the following example.

Do not call this function directly from notebook/package code!

    function on_http_request(::Val{:MyModule}, request)::Dict{Symbol,<:Any}
        Dict(
            :status => 200,
            :headers => ["Content-Type" => "text/html"],
            :body => "<html>Hi</html>",
        )
    end
"""
function on_http_request(module_name, request)::Dict{Symbol,<:Any}
    error("No http request handler defined for '$(module_name)'")
end

"Still a bit unsure about this, but it will for now give you the (relative) path for your module requests"
function get_base_url(module_name::Union{AbstractString, Symbol})
    "/integrations/$(workspace_info.notebook_id)/$(string(module_name))"
end

module AssetRegistryIntegrations
    import ..Requires
    import ..mime_fromfilename
    import ..workspace_info
    import ..get_base_url
    import ..on_http_request

    function __init__()
        Requires.@require AssetRegistry="bf4720bc-e11a-5d0c-854e-bdca1663c893" begin
            if workspace_info.notebook_id === nothing
                error("Couldn't load AssetRegistry integrations, notebook_id not set inside PlutoRunner")
            end

            AssetRegistry.baseurl[] = get_base_url(:AssetRegistry)

            function on_http_request(::Val{:AssetRegistry}, request)
                # local full_path = AssetRegistry.baseurl[] * "/" * request[:target]
                local full_path = request[:target]
                if haskey(AssetRegistry.registry, full_path)
                    local file_path = AssetRegistry.registry[full_path]
                    if isfile(file_path)
                        Dict(
                            :status => 200,
                            :headers => ["Content-Type" => mime_fromfilename(file_path)],
                            :body => read(file_path),
                        )
                    else
                        Dict(:status => 404)
                    end
                else
                    Dict(:status => 404)
                end
            end
        end
    end
end


module WebIOIntegrations
    import ..Requires
    import ..on_websocket_message
    import ..message_channel

    function __init__()
        Requires.@require WebIO="0f1e0344-ec1d-5b48-a673-e5cf874b6c29" begin
            import Sockets
            import .WebIO
                    
            struct WebIOConnection <: WebIO.AbstractConnection end
            Sockets.send(::WebIOConnection, data) = begin
                put!(message_channel, Dict(
                    :module_name => "WebIO",
                    :message => data,
                ))
            end
            Base.isopen(::WebIOConnection) = Base.isopen(message_channel)
            
            function on_websocket_message(::Val{:WebIO}, message)
                WebIO.dispatch(WebIOConnection(), message)
                nothing
            end
        end
    end
end

end
