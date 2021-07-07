import HTTP
import Markdown: htmlesc
import UUIDs: UUID
import JSON
import Distributed: RemoteException
import Serialization

# Serve everything from `/frontend`, and create HTTP endpoints to open notebooks.

"Attempts to find the MIME pair corresponding to the extension of a filename. Defaults to `text/plain`."
function mime_fromfilename(filename)
    # This bad boy is from: https://developer.mozilla.org/en-US/docs/Web/HTTP/Basics_of_HTTP/MIME_types/Common_types
    mimepairs = Dict(".aac" => "audio/aac", ".bin" => "application/octet-stream", ".bmp" => "image/bmp", ".css" => "text/css", ".csv" => "text/csv", ".eot" => "application/vnd.ms-fontobject", ".gz" => "application/gzip", ".gif" => "image/gif", ".htm" => "text/html", ".html" => "text/html", ".ico" => "image/vnd.microsoft.icon", ".jpeg" => "image/jpeg", ".jpg" => "image/jpeg", ".js" => "text/javascript", ".json" => "application/json", ".jsonld" => "application/ld+json", ".mjs" => "text/javascript", ".mp3" => "audio/mpeg", ".mp4" => "video/mp4", ".mpeg" => "video/mpeg", ".oga" => "audio/ogg", ".ogv" => "video/ogg", ".ogx" => "application/ogg", ".opus" => "audio/opus", ".otf" => "font/otf", ".png" => "image/png", ".pdf" => "application/pdf", ".rtf" => "application/rtf", ".sh" => "application/x-sh", ".svg" => "image/svg+xml", ".tar" => "application/x-tar", ".tif" => "image/tiff", ".tiff" => "image/tiff", ".ttf" => "font/ttf", ".txt" => "text/plain", ".wav" => "audio/wav", ".weba" => "audio/webm", ".webm" => "video/webm", ".webp" => "image/webp", ".woff" => "font/woff", ".woff2" => "font/woff2", ".xhtml" => "application/xhtml+xml", ".xml" => "application/xml", ".xul" => "application/vnd.mozilla.xul+xml", ".zip" => "application/zip")
    file_extension = getkey(mimepairs, '.' * split(filename, '.')[end], ".txt")
    MIME(mimepairs[file_extension])
end

function asset_response(path)
    if !isfile(path) && !endswith(path, ".html")
        return asset_response(path * ".html")
    end
    try
        @assert isfile(path)
        response = HTTP.Response(200, read(path, String))
        m = mime_fromfilename(path)
        push!(response.headers, "Content-Type" => Base.istextmime(m) ? "$(m); charset=UTF-8" : string(m))
        push!(response.headers, "Access-Control-Allow-Origin" => "*")
        response
    catch e
        HTTP.Response(404, "Not found!")
    end
end

function error_response(status_code::Integer, title, advice, body="")
    template = read(project_relative_path("frontend", "error.jl.html"), String)

    body_title = body == "" ? "" : "Error message:"
    filled_in = replace(replace(replace(replace(template, "\$TITLE" => title), "\$ADVICE" => advice), "\$BODYTITLE" => body_title), "\$BODY" => htmlesc(body))

    response = HTTP.Response(status_code, filled_in)
    push!(response.headers, "Content-Type" => string(mime_fromfilename(".html")))
    response
end

function notebook_response(notebook; home_url="./", as_redirect=true)
    if as_redirect
        response = HTTP.Response(302, "")
        push!(response.headers, "Location" => home_url * "edit?id=" * string(notebook.notebook_id))
        return response
    else
        HTTP.Response(200, string(notebook.notebook_id))
    end
end

function get_header(request::HTTP.Request, key::AbstractString)
    validx = findfirst(x -> (lowercase(x.first) == lowercase(key)), request.headers)
    if isnothing(validx)
        return nothing
    end

    val = request.headers[validx]
    if !isnothing(val)
        return val.second
    end

    nothing
end

function with_json!(response::HTTP.Response)
    push!(response.headers, "Content-Type" => "application/json")
    response
end
function with_msgpack!(response::HTTP.Response)
    push!(response.headers, "Content-Type" => "application/x-msgpack")
    response
end
function with_julia!(response::HTTP.Response)
    push!(response.headers, "Content-Type" => "application/x-julia")
    response
end
function with_cors!(response::HTTP.Response)
    push!(response.headers, "Access-Control-Allow-Origin" => "*")
    response
end

"""
Return whether the `request` was authenticated in one of two ways:
1. the session's `secret` was included in the URL as a search parameter, or
2. the session's `secret` was included in a cookie.
"""
function is_authenticated(session::ServerSession, request::HTTP.Request)
    (
        secret_in_url = try
            uri = HTTP.URI(request.target)
            query = HTTP.queryparams(uri)
            get(query, "secret", "") == session.secret
        catch e
            @warn "Failed to authenticate request using URL" exception = (e, catch_backtrace())
            false
        end
    ) || (
        secret_in_cookie = try
            cookies = HTTP.cookies(request)
            any(cookies) do cookie
                cookie.name == "secret" && cookie.value == session.secret
            end
        catch e
            @warn "Failed to authenticate request using cookies" exception = (e, catch_backtrace())
            false
        end
    )
    # that ) || ( kind of looks like Krabs from spongebob
end

function http_router_for(session::ServerSession)
    router = HTTP.Router()
    security = session.options.security

    function add_set_secret_cookie!(response::HTTP.Response)
        push!(response.headers, "Set-Cookie" => "secret=$(session.secret); SameSite=Strict; HttpOnly")
        response
    end

    """
        with_authentication(f::Function)
    
    Returns a function `HTTP.Request → HTTP.Response` which does three things:
    1. Check whether the request is authenticated (by calling `is_authenticated`), if not, return a 403 error.
    2. Call your `f(request)` to create the response message.
    3. Add a `Set-Cookie` header to the response with the session's `secret`.
    """
    function with_authentication(f::Function; required::Bool)::Function
        return function (request::HTTP.Request)
            if !required || is_authenticated(session, request)
                response = f(request)
                add_set_secret_cookie!(response)
                if !required
                    filter!(p -> p[1] != "Access-Control-Allow-Origin", response.headers)
                    push!(response.headers, "Access-Control-Allow-Origin" => "*")
                end
                response
            else
                error_response(403, "Not yet authenticated", "<b>Open the link that was printed in the terminal where you launched Pluto.</b> It includes a <em>secret</em>, which is needed to access this server.<br><br>If you are running the server yourself and want to change this configuration, have a look at the keyword arguments to <em>Pluto.run</em>. <br><br>Please <a href='https://github.com/fonsp/Pluto.jl/issues'>report this error</a> if you did not expect it!")
            end
        end
    end
    
    function create_serve_onefile(path)
        return request::HTTP.Request -> asset_response(normpath(path))
    end
    
    # / does not need security.require_secret_for_open_links
    # because this is how we handle the case:
    #    require_secret_for_open_links == true
    #    require_secret_for_access == false
    # Access to all 'risky' endpoints is still restricted to requests that have the secret cookie, but visiting `/` is allowed, and it will set the cookie. From then on the security situation is identical to 
    #    secret_for_access == true
    HTTP.@register(router, "GET", "/", with_authentication(
        create_serve_onefile(project_relative_path("frontend", "index.html"));
        required=security.require_secret_for_access
        ))
    HTTP.@register(router, "GET", "/edit", with_authentication(
        create_serve_onefile(project_relative_path("frontend", "editor.html"));
        required=security.require_secret_for_access || 
        security.require_secret_for_open_links,
    ))
    # the /edit page also uses with_authentication, but this is not how access to notebooks is secured: this is done by requiring the WS connection to be authenticated.
    # we still use it for /edit to do the cookie stuff, and show a more helpful error, instead of the WS never connecting.
    
    HTTP.@register(router, "GET", "/ping", r -> HTTP.Response(200, "OK!"))
    HTTP.@register(router, "GET", "/possible_binder_token_please", r -> session.binder_token === nothing ? HTTP.Response(200,"") : HTTP.Response(200, session.binder_token))
    
    function try_launch_notebook_response(action::Function, path_or_url::AbstractString; title="", advice="", home_url="./", as_redirect=true, action_kwargs...)
        try
            nb = action(session, path_or_url; action_kwargs...)
            notebook_response(nb; home_url=home_url, as_redirect=as_redirect)
        catch e
            if e isa SessionActions.NotebookIsRunningException
                notebook_response(e.notebook; home_url=home_url, as_redirect=as_redirect)
            else
                error_response(500, title, advice, sprint(showerror, e, stacktrace(catch_backtrace())))
            end
        end
    end

    serve_newfile = with_authentication(;
        required=security.require_secret_for_access || 
        security.require_secret_for_open_links
    ) do request::HTTP.Request
        notebook_response(SessionActions.new(session); as_redirect=(request.method == "GET"))
    end
    HTTP.@register(router, "GET", "/new", serve_newfile)
    HTTP.@register(router, "POST", "/new", serve_newfile)

    serve_openfile = with_authentication(;
        required=security.require_secret_for_access || 
        security.require_secret_for_open_links
    ) do request::HTTP.Request
        try
            uri = HTTP.URI(request.target)
            query = HTTP.queryparams(uri)
            as_sample = haskey(query, "as_sample")
            if haskey(query, "path")
                path = tamepath(query["path"])
                if isfile(path)
                    return try_launch_notebook_response(SessionActions.open, path, as_redirect=(request.method == "GET"), as_sample=as_sample, title="Failed to load notebook", advice="The file <code>$(htmlesc(path))</code> could not be loaded. Please <a href='https://github.com/fonsp/Pluto.jl/issues'>report this error</a>!")
                else
                    return error_response(404, "Can't find a file here", "Please check whether <code>$(htmlesc(path))</code> exists.")
                end
            elseif haskey(query, "url")
                url = query["url"]
                return try_launch_notebook_response(SessionActions.open_url, url, as_redirect=(request.method == "GET"), as_sample=as_sample, title="Failed to load notebook", advice="The notebook from <code>$(htmlesc(url))</code> could not be loaded. Please <a href='https://github.com/fonsp/Pluto.jl/issues'>report this error</a>!")
            else
                error("Empty request")
            end
        catch e
            return error_response(400, "Bad query", "Please <a href='https://github.com/fonsp/Pluto.jl/issues'>report this error</a>!", sprint(showerror, e, stacktrace(catch_backtrace())))
        end
    end

    HTTP.@register(router, "GET", "/open", serve_openfile)
    HTTP.@register(router, "POST", "/open", serve_openfile)
    
    serve_sample = with_authentication(;
        required=security.require_secret_for_access || 
        security.require_secret_for_open_links
    ) do request::HTTP.Request
        uri = HTTP.URI(request.target)
        sample_filename = split(HTTP.unescapeuri(uri.path), "sample/")[2]
        sample_path = project_relative_path("sample", sample_filename)
        
        try_launch_notebook_response(SessionActions.open, sample_path; as_redirect=(request.method == "GET"), home_url="../", as_sample=true, title="Failed to load sample", advice="Please <a href='https://github.com/fonsp/Pluto.jl/issues'>report this error</a>!")
    end
    HTTP.@register(router, "GET", "/sample/*", serve_sample)
    HTTP.@register(router, "POST", "/sample/*", serve_sample)




    function get_notebook_from_api_request(request::HTTP.Request)
        uri = HTTP.URI(request.target)
        query = HTTP.queryparams(uri)
        splitpath = HTTP.URIs.splitpath(request.target)

        sess_id = get(query, "session", splitpath[3])
        file = get(query, "file", HTTP.unescapeuri(splitpath[3]))

        notebook = nothing
        if !isnothing(file)
            notebook_id = findfirst(session.notebooks) do nb
                basename(nb.path) == file
            end

            if !isnothing(notebook_id)
                notebook = session.notebooks[notebook_id]
            end
        else
            uid = UUID(sess_id)
            if uid ∈ keys(session.notebooks)
                notebook = session.notebooks[uid]
            end
        end

        notebook
    end
    function rest_parse(body::Vector{UInt8}, mime_type::Union{AbstractString, Nothing})
        if mime_type == "application/x-msgpack"
            return MsgPack.unpack(body)
        elseif mime_type == "application/x-julia"
            return Serialization.deserialize(IOBuffer(body))
        else
            # For some reason JSON.parse mutates body
            # so we need to make a copy of it
            jsonstr = String(copy(body))
            return JSON.parse(jsonstr)
        end
    end
    function rest_parameter(request::HTTP.Request, key::AbstractString, default=nothing)
        uri = HTTP.URI(request.target)
        query = HTTP.queryparams(uri)

        content_type = get_header(request, "Content-Type")
        if haskey(query, key)
            return rest_parse(Vector{UInt8}(get(query, key, "")), content_type)
        end

        parsed_body = rest_parse(request.body, content_type)
        get(parsed_body, key, default)
    end
    function rest_serialize(request::HTTP.Request, body)
        accept_type = get_header(request, "Accept")
        try
            if accept_type == "application/x-msgpack"
                return HTTP.Response(200, Pluto.pack(body)) |> with_msgpack! |> with_cors!
            elseif accept_type == "application/x-julia"
                out_io = IOBuffer()
                Serialization.serialize(out_io, body)
                serialized_msg = take!(out_io)
                return HTTP.Response(200, serialized_msg) |> with_julia! |> with_cors!
            else 
                return HTTP.Response(200, JSON.json(body)) |> with_json! |> with_cors!
            end
        catch e
            # Likely an error serializing the object
            showerror(stderr, e)
            return HTTP.Response(400, "Cannot serialize requested output. See server logs for details")
        end
    end

    if session.options.server.enable_rest
        function serve_notebook_eval(request::HTTP.Request)
            out_symbols = Symbol.(rest_parameter(request, "outputs"))

            # Get notebook from request parameters
            notebook = get_notebook_from_api_request(request)

            inputs = rest_parameter(request, "inputs")
            outputs = nothing
            try
                outputs = REST.get_notebook_output(session, notebook, notebook.topology, Dict{Symbol, Any}(Symbol(k) => v for (k, v) ∈ inputs), out_symbols)
            catch e
                if isa(e, RemoteException) # Happens when Julia can't send an object (ex. a function)
                    return HTTP.Response(400, "Distributed serialization error. Is the requested variable a function?")
                else
                    showerror(stdout, e) # TODO: This line is for debug. Remove later
                    return HTTP.Response(400, e.msg)
                end
            end

            rest_serialize(request, outputs)
        end
        HTTP.@register(router, "GET", "/$(REST.WYSIWYR_VERSION)/notebook/*/eval", serve_notebook_eval)
        HTTP.@register(router, "POST", "/$(REST.WYSIWYR_VERSION)/notebook/*/eval", serve_notebook_eval)

        function serve_notebook_call(request::HTTP.Request)
            # Get notebook from request parameters
            notebook = get_notebook_from_api_request(request)

            fn_name = Symbol(rest_parameter(request, "function"))
            args = rest_parameter(request, "args")
            kwargs = rest_parameter(request, "kwargs")

            fn_result = REST.get_notebook_call(session, notebook, fn_name, args, kwargs)

            rest_serialize(request, fn_result)
        end
        HTTP.@register(router, "GET", "/$(REST.WYSIWYR_VERSION)/notebook/*/call", serve_notebook_call)
        HTTP.@register(router, "POST", "/$(REST.WYSIWYR_VERSION)/notebook/*/call", serve_notebook_call)

        function serve_notebook_static_fn(request::HTTP.Request)
            uri = HTTP.URI(request.target)
            query = HTTP.queryparams(uri)

            out_symbols = Symbol.(split(query["outputs"], ","))

            notebook = get_notebook_from_api_request(request)

            input_symbols = Symbol.(split(query["inputs"], ","))
            out_fn = REST.get_notebook_static_function(session, notebook, notebook.topology, input_symbols, out_symbols)

            res = HTTP.Response(200, string(out_fn))
            push!(res.headers, "Content-Type" => "text/plain; charset=utf-8")
            res
        end
        HTTP.@register(router, "GET", "/$(REST.WYSIWYR_VERSION)/notebook/*/static", serve_notebook_static_fn)
    end

    notebook_from_uri(request) = let
        uri = HTTP.URI(request.target)        
        query = HTTP.queryparams(uri)
        id = UUID(query["id"])
        session.notebooks[id]
    end
    serve_notebookfile = with_authentication(; 
        required=security.require_secret_for_access || 
        security.require_secret_for_open_links
    ) do request::HTTP.Request
        try
            notebook = notebook_from_uri(request)
            response = HTTP.Response(200, sprint(save_notebook, notebook))
            push!(response.headers, "Content-Type" => "text/julia; charset=utf-8")
            push!(response.headers, "Content-Disposition" => "inline; filename=\"$(basename(notebook.path))\"")
            response
        catch e
            return error_response(400, "Bad query", "Please <a href='https://github.com/fonsp/Pluto.jl/issues'>report this error</a>!", sprint(showerror, e, stacktrace(catch_backtrace())))
        end
    end
    HTTP.@register(router, "GET", "/notebookfile", serve_notebookfile)

    serve_statefile = with_authentication(; 
        required=security.require_secret_for_access || 
        security.require_secret_for_open_links
    ) do request::HTTP.Request
        try
            notebook = notebook_from_uri(request)
            response = HTTP.Response(200, Pluto.pack(Pluto.notebook_to_js(notebook)))
            push!(response.headers, "Content-Type" => "application/octet-stream")
            push!(response.headers, "Content-Disposition" => "inline; filename=\"$(without_pluto_file_extension(basename(notebook.path))).plutostate\"")
            response
        catch e
            return error_response(400, "Bad query", "Please <a href='https://github.com/fonsp/Pluto.jl/issues'>report this error</a>!", sprint(showerror, e, stacktrace(catch_backtrace())))
        end
    end
    HTTP.@register(router, "GET", "/statefile", serve_statefile)

    serve_notebookexport = with_authentication(; 
        required=security.require_secret_for_access || 
        security.require_secret_for_open_links
    ) do request::HTTP.Request
        try
            notebook = notebook_from_uri(request)
            response = HTTP.Response(200, generate_html(notebook))
            push!(response.headers, "Content-Type" => "text/html; charset=utf-8")
            push!(response.headers, "Content-Disposition" => "inline; filename=\"$(basename(notebook.path)).html\"")
            response
        catch e
            return error_response(400, "Bad query", "Please <a href='https://github.com/fonsp/Pluto.jl/issues'>report this error</a>!", sprint(showerror, e, stacktrace(catch_backtrace())))
        end
    end
    HTTP.@register(router, "GET", "/notebookexport", serve_notebookexport)
    
    serve_notebookupload = with_authentication(; 
        required=security.require_secret_for_access || 
        security.require_secret_for_open_links
    ) do request::HTTP.Request
        save_path = SessionActions.save_upload(request.body)
        try_launch_notebook_response(
            SessionActions.open,
            save_path,
            as_redirect=false,
            as_sample=false,
            title="Failed to load notebook",
            advice="Make sure that you copy the entire notebook file. Please <a href='https://github.com/fonsp/Pluto.jl/issues'>report this error</a>!"
        )
    end
    HTTP.@register(router, "POST", "/notebookupload", serve_notebookupload)
    
    function serve_asset(request::HTTP.Request)
        uri = HTTP.URI(request.target)
        
        filepath = project_relative_path("frontend", relpath(HTTP.unescapeuri(uri.path), "/"))
        asset_response(filepath)
    end
    HTTP.@register(router, "GET", "/*", serve_asset)
    HTTP.@register(router, "GET", "/favicon.ico", create_serve_onefile(project_relative_path("frontend", "img", "favicon.ico")))

    return router
end