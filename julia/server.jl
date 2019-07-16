"""
    JSONMetadom

A simple server for [JSONMetadom](https://github.com/zot/JSONMetadom).

Remember that there will be some "soak time" at the start because of Julia's JIT behavior, it should be quite zippy after that.

To start it, use the start function like this:

start(JSON, DIRECTORY, HANDLER)

JSON is a JSON-compatible Julia object (arrays, dicts, strings, numbers, booleans, etc.) as detailed in [JSONMetadom](https://github.com/zot/JSONMetadom).

DIRECTORY the server uses for your HTML files, etc.

HANDLER is an event handler. You can use patternhandler() for easy event handling (see documentation). A "raw" event handler (patternhandler creates one of these) is a function(EVENT, CON, LOCATION, ARG)

- EVENT is :key, :click, or :set
- CON is the JSONMetadom connection object
- LOCATION the path in the JSON document (contained in CON.document) for the event
- ARG is the JSON property for the event
"""
module JSONMetadom

using HTTP, Sockets, JSON

export start, doc, parent, OBJ, patternhandler, useverbose, document

usingverbose = false

useverbose(flag) = global usingverbose = flag

"A Metadom connection"
mutable struct Connection
    document
    queuing
    queue
    index
    handler::Function
    socket::HTTP.WebSockets.WebSocket
    host
    port
    properties
    Connection(document, handler, socket, host, port) = new(document, false, [], Dict(), handler, socket, host, port, Dict())
end

"""
    DocPath

A path within a Metadom document.

You can access and change items in the document using the . and [] operators with a DocPath like this:

docp[3]
docp.a.b.c = 3

If the location referenced by a . or [] operator is an array or a dict, the operator will return a new DocPath for the path so if the document is `[Dict([:a=>2])]` and docp is an empty DocPath on it,

* docp[1] will return a new DocPath with the path [1]
* docp[1].a will return 2
* docp[1].a = 3 will set :a to 3 in the document's dict
"""
struct DocPath
    connection
    path
    DocPath(doc::DocPath, indices...) = new(connection(doc), vcat(path(doc), [indices...]))
    DocPath(con::Connection, indices...) = new(con, [indices...])
    DocPath(con::Connection, path::Array) = new(con, path)
end

"Create a DocPath"
doc(con::Connection)::DocPath = (verbose("doc path on $(repr(con.document[:contents]))"); DocPath(con))
"Create a new DocPath that extends a DocPath"
doc(d::DocPath, path)::DocPath = (verbose("doc path on $(repr(con.document[:contents]))"); DocPath(d, path))
"Get a DocPath's connection"
connection(doc::DocPath) = getfield(doc, :connection)
"Get a DocPath's path"
path(doc::DocPath) = getfield(doc, :path)
"Make a new that represents the parent of a DocPath"
parent(doc::DocPath) = DocPath(connection(doc), path(doc)[1:end -1])

docValue(con::Connection, path) = docValue(con, path, getpath(con, path))
docValue(con::Connection, path, value::AbstractArray) = DocPath(con, path)
docValue(con::Connection, path, value::AbstractDict) = DocPath(con, path)
docValue(con::Connection, path, value) = value

Base.getproperty(doc::DocPath, name::Symbol) = docValue(connection(doc), vcat(path(doc), [name]))
Base.getindex(doc::DocPath, indices...) = docValue(connection(doc), vcat(path(doc), [indices...]))
Base.setproperty!(doc::DocPath, name::Symbol, value) = setpath(connection(doc), vcat(path(doc), [name]), value)
Base.setindex!(doc::DocPath, value, indices...) = setpath(connection(doc), vcat(path(doc), [indices...]), value)

"print a message if usingverbose is true"
function verbose(args...)
    if usingverbose
        println(args...)
    end
end

"low-level event handler invoked by a socket message"
function handleset(con, location, value)
    verbose("SET $(repr(location)) = $(repr(value))")
    location = web2julia(location)
    adjustindex(con.index, location, getpath(con, location), value)
    basicsetpath(con, location, value)
    con.handler(:set, con, location, value)
end

cmds = Dict([
    :click => (con::Connection, name, location)-> con.handler(:click, con, web2julia(location), name)
    :set => handleset
    :key => (con::Connection, name, location)-> con.handler(:key, con, web2julia(location), name)
])

nullhandler(args...) = nothing

emptyDict = Dict()

"""
    patternhandler(DICT; clickhandler = nullhandler, sethandler = nullhandler, keyhandler = nullhandler)

DICT is a dictionary with optional :set, :click, and :key entries.

Each entry is (TYPE, FIELD)=> function(DOCPATH, KEY, ARG, OBJ, EVENT)

- TYPE is the type of the event's JSON object
- FIELD is the field in the event's JSON object that is being changed or clicked
- DOCPATH is the path to the object
- KEY is the field name
- OBJ is the JSON object
- EVENT is the 
"""
function patternhandler(dict; clickhandler = nullhandler, sethandler = nullhandler, keyhandler = nullhandler)
    function (event, con, location, arg)
        local obj = event == :key ? con.document : getpath(con, event == :click ? location : location[1:end - 1])
        local objtype = obj[:type]
        local key = if event in [:click :key]
            location = [location..., arg]
            isa(arg, String) ? Symbol(arg) : arg
        elseif event == :set
            location[end]
        end
        local handlers = get(dict, event, emptyDict)
        local defaulthandler = event == :click ? clickhandler : event == :set ? sethandler : keyhandler

        verbose("EVENT $event LOCATION $(repr(location)) TYPE $(typeof(objtype)) $objtype KEY $(typeof(key)) $(repr(key)) ARG $(repr(arg)) VALUE $(repr(getpath(con, location)))")
        get(handlers, (objtype, key), get(handlers, objtype, defaulthandler))(DocPath(con, location[1:end - 1]), key, arg, obj, event)
    end
end

function getpath(con::Connection, path)
    local obj = con.document[:contents]
    local key, curindex
    global ERR

    path = absolutepath(con, path)
    try
        for index in eachindex(path)
            curindex = index
            key = path[index]
            if isa(obj, AbstractDict)
                verbose("GET $(repr(obj)) $key...")
                obj = get(obj, key, nothing)
            elseif isa(obj, AbstractArray)
                verbose("INDEX $(repr(obj)) $key...")
                obj = obj[key]
            end
        end
    catch err
        ERR = err
        if isa(err, ArgumentError)
            println("ERROR: Could not find index $key at $curindex in path $(join([path[1:curindex]], ", "))")
            throw(err)
        end
    end
    obj
end

function basicsetpath(con::Connection, path, value)
    path = absolutepath(con, path)
    adjustindex(con.index, path, getpath(con, path), value)
    getpath(con, path[1:end - 1])[path[end]] = value
end

function adjustindex(index, path, oldjson, newjson)
    local oldids = findIds(path, oldjson)
    local newids = findIds(path, newjson)
    local oldkeys = Set(keys(oldids))

    for (k, v) in newids
        index[k] = v
        delete!(oldkeys, k)
    end
    for k in oldkeys
        delete!(index, k)
    end
end

web2julia(path) = (k-> isa(k, Number) ? k + 1 : Symbol(k)).(path)

julia2web(path) = (k-> isa(k, Number) ? k - 1 : Symbol(k)).(path)

function absolutepath(con::Connection, path)
    if isa(path, Symbol)
        con.index[path]
    elseif isa(path[1], String) && startswith(path[1], "@")
        [con.index[Symbol(path[1][2:end])]..., path[2:end]...]
    else
        path
    end
end

ERR = nothing

function call(con::Connection, cmd, args...)
    cmds[Symbol(cmd)](con, args...)
end

function setpath(con::Connection, path, value)
    path = absolutepath(con, path)
    basicsetpath(con, path, value)
    queue(con, [:set, julia2web(path), value])
end

function deletepath(con::Connection, path)
    path = absolutepath(con, path)
    local endkey = path[end]
    local parent = getpath(con, path[1:end - 1])

    adjustindex(con.index, path, getpath(con, path), nothing)
    if isa(parent, Array)
        splice!(parent, endkey:endkey)
    elseif isa(parent, Dict)
        delete!(parent, endkey)
    end
    queue(con, [:delete, julia2web(path)])
end

function insertpath(con::Connection, path, value)
    path = absolutepath(con, path)
    local endkey = path[end]
    local parent = getpath(con, path[1:end - 1])

    adjustindex(con.index, path, nothing, value)
    if isa(parent, Array)
        splice!(parent, endkey:0, [value])
    elseif isa(parent, Dict)
        parent[endkey] = value
    end
    queue(con, [:insert, julia2web(path), value])
end

function queue(con::Connection, item)
    if con.queuing > 0
        verbose("QUEUING ", JSON.json(item))
        push!(con.queue, item)
    else
        verbose("SENDING ", JSON.json(item))
        send(con, item)
    end
end

startqueue(con) = con.queuing += 1

function flushqueue(con::Connection)
    if con.queuing > 0
        con.queuing -= 1
        if con.queuing == 0 # send
            if length(con.queue) == 1
                send(con, con.queue[1])
            elseif length(con.queue) > 1
                send(con, [:batch, con.queue])
            end
        end
        empty!(con.queue)
    end
end

send(con::Connection, item) = write(con.socket, JSON.json(item))

function findIds(path, json, ids = Dict())
    if isa(json, Array)
        for k in 1:length(json)
            findIds([path..., k - 1], json[k], ids)
        end
    elseif isa(json, Dict)
        if haskey(json, :id)
            ids[Symbol(json[:id])] = path
        end
        for (k, v) in json
            findIds([path..., k], v, ids)
        end
    end
    ids
end

function document(con::Connection, doc = con.document)
    con.document = doc
    local ids = findIds([], con.document[:contents])

    if !isempty(ids)
        push!(con.index, ids...)
    end
    queue(con, ["document", con.document])
end

"""
    OBJ

Helper function that produces a Dict, optionally taking values for :type and :id entries.
"""
OBJ(array::Array) = Dict{Symbol, Any}(array)
function OBJ(otype::Symbol, array::Array)
    local d = Dict{Symbol, Any}(array)

    d[:type] = otype
    d
end
function OBJ(otype::Symbol, id::String, array::Array)
    local d = Dict{Symbol, Any}(array)

    d[:type] = otype
    d[:id] = id
    d
end

# open_file copied from Gadfly.jl, MIT license: https://github.com/GiovineItalia/Gadfly.jl
#
function open_file(filename)
    if Sys.isapple()
        run(`open $(filename)`)
    elseif Sys.islinux() || Sys.isbsd()
        run(`xdg-open $(filename)`)
    elseif Sys.iswindows()
        run(`$(ENV["COMSPEC"]) /c start $(filename)`)
    else
        @warn "Opening browseers is not supported on OS $(string(Sys.KERNEL))"
    end
end

"""
    start(json, dir::String, handler::Function, port = 8085)

Start a Metadom server
"""
function start(conFunc, dir::String, handler::Function, port = 8085; browse = false)
    verbose("STARTING HTTP ON PORT $port, DIR $dir")
    #host = Sockets.localhost
    local host = ip"0.0.0.0"

    if browse
        @async begin
            #sleep(3)
            open_file("http://localhost:8085")
        end
    end
    HTTP.listen(host, port) do http
        if HTTP.WebSockets.is_upgrade(http.message)
            HTTP.WebSockets.upgrade(http) do ws
                try
                    connection = Connection(Dict(), handler, ws, host == ip"0.0.0.0" ? Sockets.localhost : host, port)
                    startqueue(connection)
                    #document(connection)
                    conFunc(connection)
                    flushqueue(connection)
                    while !eof(ws)
                        frame = HTTP.WebSockets.readframe(ws)
                        startqueue(connection)
                        call(connection, JSON.Parser.parse(String(frame))...)
                        flushqueue(connection)
                    end
                catch err
                    #showerror(stderr, err, catch_backtrace())
                    Base.display_error(err, catch_backtrace())
                end
            end
        else
            local req = http.message
            local file = dir * replace(http.message.target, r"\?.*$" => "")

            req.body = read(http)
            closeread(http)
            if isdir(file) file = file * "/index.html" end
            body = read(file)
            req.response = HTTP.Response(body)
            HTTP.setheader(req.response, "Content-Type" => sniff(file, body))
            HTTP.setheader(req.response, "Access-Control-Allow-Origin" => "*")
            req.response.request = req
            startwrite(http)
            write(http, req.response.body)
        end
    end
end

filetypes = Dict([
    "css" => "text/css"
])

function sniff(file, body)
    local m = match(r"\.(.*)$", file)

    if m == nothing
        HTTP.sniff(body)
    else
        get(filetypes, m.captures[1]) do
            HTTP.sniff(body)
        end
    end
end

end #module
