# Copyright (C) 2019, by Bill Burdick, ZLIB licensed, https://github.com/zot/domdom

"""
    Domdom

A simple server for [Domdom](https://github.com/zot/domdom).

Remember that there will be some "soak time" at the start because of Julia's JIT behavior, it should be quite zippy after that.

To start it, use the start function like this:

start(JSON, DIRECTORY, HANDLER)

JSON is a JSON-compatible Julia object (arrays, dicts, strings, numbers, booleans, etc.) as detailed in [Domdom](https://github.com/zot/domdom).

DIRECTORY the server uses for your HTML files, etc.

HANDLER is an event handler. You can use patternhandler() for easy event handling (see documentation). A "raw" event handler (patternhandler creates one of these) is a function(EVENT, CON, LOCATION, ARG)

- EVENT is :key, :click, or :set
- CON is the Domdom connection object
- LOCATION the path in the JSON document (contained in CON.document) for the event
- ARG is the JSON property for the event
"""
module Domdom

using HTTP, Sockets, JSON

export start, useverbose, document, web2julia, julia2web
export Connection, Dom, DomArray, DomObject
export connection, path, contents, parent, root, clone, domproperties, domproperties!
export getpath, isdirty, dirty!, clean!, cleanall!

usingverbose = false

useverbose(flag) = global usingverbose = flag

"A Domdom connection"
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
    dirty
    domproperties
    Connection(document, handler, socket, host, port) = new(document, false, [], Dict(), handler, socket, host, port, Dict(), WeakKeyDict(), WeakKeyDict())
end

domid = 0

"""
    DomArray

An array within a Domdom document. This functions like an array but it also contains the path
of the array. Domdom documents are trees, placing the same array in more than one place in the
document is not allowed.
"""
mutable struct DomArray <: AbstractArray{Any, 1}
    connection::Connection
    path::Array
    contents::Array{Any, 1}
    id
    DomArray(con::Connection, path::Array, values::Array) = new(con, path, values, [global domid += 1])
end

"""
    DomObject

An object within a Domdom document. This functions like a dictionary but it also contains the path
of the array. Domdom documents are trees, placing the same object in more than one place in the
document is not allowed.
"""
mutable struct DomObject <: AbstractDict{String, Any}
    connection::Connection
    path::Array
    contents::Dict
    id
    DomObject(con::Connection, path::Array, contents::Dict) = new(con, path, contents, [global domid += 1])
end

"Either a DomObject or a DomArray"
const Dom = Union{DomObject, DomArray}
"Either a DomObject, a DomArray, or a Connection"
const DomCon = Union{Connection, Dom}

DomArray(con::Dom, values...) = DomArray(connection(con), [], collect(values))
DomObject(con::DomCon, type::Symbol; props...) = DomObject(connection(con), [], Dict([:type=>type, props...]))
DomObject(con::DomCon; props...) = DomObject(connection(con), [], Dict([props...]))

id(el::Dom) = getfield(el, :id)
connection(el::Dom) = getfield(el, :connection)
connection(con::Connection) = con
path(el::Dom) = getfield(el, :path)
Base.parent(el::Dom) = getpath(connection(el), web2julia(path(el)[1:end - 1]))
function Base.replace(el::Dom, el2::Dom)
    println("REPLACING:\n  $(el)\nwith\n  $(el2)")
    con = connection(el)
    path = absolutepath(con, web2julia(path(el)))
    setpath(con, path, el2)
    queue(con, [:set, julia2web(path), juliaobj2webobj(value)])
end
clone(x) = x
clone(el::DomArray) = DomArray(connection(el), [], Any[clone(x) for x in el.contents])
clone(el::DomObject) = DomObject(connection(el), [], Dict(Any[k => clone(v) for (k, v) in contents(el)]))
contents(el::Dom) = getfield(el, :contents)
"Root of the document"
root(con::Connection) = con.document.contents
root(el::Dom) = root(connection(el))
domproperties(el::Dom) = get(connection(el).domproperties, id(el), nothing)
domproperties!(el::Dom, value) = connection(el).domproperties[id(el)] = value
Base.show(io::IO, el::DomArray) = print(io, "DomArray(",join(map(stringFor, path(el)), ", "),")[", join(map(repr, el), ", "), "]")
Base.show(io::IO, el::DomObject) = print(io, "DomObject(",join(map(stringFor, path(el)), ", "),")[", join(map(p->"$(String(p[1]))=>$(repr(p[2]))", collect(contents(el))), ", "), "]")
Base.getproperty(el::DomObject, name::Symbol) = el[name]
Base.setproperty!(el::DomObject, name::Symbol, value) = el[name] = value
Base.getindex(el::DomObject, name) = get(contents(el), name, nothing)
Base.getindex(el::DomArray, index) = if index in 1:length(contents(el)) contents(el)[index] else nothing end
function Base.setindex!(el::DomObject, value, name)
    subsetindex(el, value, get(contents(el), name, nothing), name)
    contents(el)[name] = value
end
function Base.setindex!(el::DomArray, value, index)
    if length(el) == index - 1
        subsetindex(el, value, nothing, index)
        push!(contents(el), value)
    else
        subsetindex(el, value, contents(el)[index], index)
        contents(el)[index] = value
    end
end
function subsetindex(el::Dom, value, oldValue, index)
    newpath = checkpath([path(el)..., julia2web(index)], value)
    adjustindex(connection(el).index, newpath, oldValue, value)
    queue(connection(el), [:set, newpath, juliaobj2webobj(value)])
end
Base.length(el::Dom) = length(contents(el))
Base.iterate(el::Dom, state...) = iterate(contents(el), state...)
Base.size(el::DomArray) = size(el.contents)
Base.IndexStyle(::Type{DomArray}) = IndexLinear()
Base.pairs(el::DomObject) = pairs(contents(el))
Base.keys(el::DomObject) = keys(contents(el))
Base.values(el::DomObject) = values(contents(el))
function Base.push!(el::DomArray, items...)
    for item in items
        el[end + 1] = item
    end
end
function Base.pop!(dom::DomArray)
    adjustindex(connection(dom).index, [path(dom)..., length(dom) - 1], dom[end], nothing)
    pop!(dom.contents)
    queue(connection(dom), [:deleteLast, path(dom)])
end

function checkpath(elpath, value::Dom)
    if path(value) == []
        for (k, v) in pairs(contents(value))
            checkpath([elpath..., julia2web(k)], v)
        end
        setfield!(value, :path, elpath)
    elseif path(value) != elpath
        throw(ArgumentError("Attempt to move a tree value from [$(join(path(value), ", "))] to [$(join(elpath, ", "))]"))
    end
    elpath
end
checkpath(path, value) = path

function absolutepath(con::Connection, path)
    if isa(path, Symbol)
        con.index[path]
    elseif length(path) > 0 && isa(path[1], String) && startswith(path[1], "@")
        [con.index[Symbol(path[1][2:end])]..., path[2:end]...]
    else
        path
    end
end

"""
    getpath(CON::Connection, PATH) -> Any

Return the value at PATH in CON

CON is a domdom connection

PATH is a path in the conneciton
"""
getpath(con::Connection, path::AbstractArray{T, 1} where T) = walk(con, path)

walk(con::Connection, path::AbstractArray{T, 1} where T) = walk(con, con.document.contents, path)
function walk(con::Connection, obj::Dom, path::AbstractArray{T, 1} where T)
    local key, curindex

    path = absolutepath(con, path)
    try
        for index in eachindex(path)
            curindex = index
            key = path[index]
            obj = obj[key]
        end
    catch err
        if isa(err, ArgumentError)
            println("ERROR: Could not find index $key at $curindex in path $(join([path[1:curindex]], ", "))")
            throw(err)
        end
    end
    obj
end

function setpath(con::Connection, path, value)
    path = absolutepath(con, path)
    adjustindex(con.index, path, getpath(con, path), value)
    local parent = getpath(con, path[1:end - 1])
    if isa(path[end], Integer) # append item if it's an array of len-1
        if length(parent) >= path[end]
            contents(parent)[path[end]] = value
        elseif length(parent) == path[end] - 1
            push!(parent, value)
        else
            throw(BoundsError(parent, path[end]))
        end
    else
        contents(parent)[path[end]] = value
        dirty!(con, path) #mark only objects dirty because they can have handlers
    end
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
    queue(con, [:insert, julia2web(path), juliaobj2webobj(value)])
end

"""
    isdirty(dom)

Determine if an object is dirty
"""
isdirty(dom::Dom) = haskey(connection(dom).dirty, path(dom))
"""
    clean!(dom)

State that an object is clean
"""
clean!(dom::Dom) = delete!(connection(dom).dirty, path(dom))
"""
    cleanall(dom)
    cleanall(con)

State that all objects in a connection are clean
"""
cleanall!(dom::Dom) = cleanall!(connection(dom))
cleanall!(con::Connection) = con.dirty = WeakKeyDict()
"""
    dirty!(dom)
    dirty!(con, path)

Make a field dirty
"""
dirty!(dom::Dom) = dirty!(connection(dom), path(dom))
function dirty!(con::Connection, path)
    par = path[1:end - 1]
    if haskey(con.dirty, par)
        push!(con.dirty[par], path[end])
    else
        con.dirty[par] = Set([path[end]])
    end
end

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
    setpath(con, location, value)
    con.handler(:set, con, location, value)
end

const cmds = Dict([
    :click => (con::Connection, name, location)-> con.handler(:click, con, web2julia(location), name)
    :set => handleset
    :key => (con::Connection, name, location)-> con.handler(:key, con, web2julia(location), name)
])

const nullhandler(args...) = nothing

const emptyDict = Dict()

web2julia(path::Number) = path + 1
web2julia(path::String) = Symbol(path)
web2julia(path::AbstractArray) = web2julia.(path)

julia2web(path::Number) = path - 1
julia2web(path::Symbol) = String(path)
julia2web(path::AbstractArray) = julia2web.(path)

stringFor(item) = repr(item)
stringFor(item::Symbol) = String(item)

juliaobj2webobj(x) = x
juliaobj2webobj(array::DomArray) = juliaobj2webobj.(array.contents)
juliaobj2webobj(obj::DomObject) = Dict(map(p->(p[1], juliaobj2webobj(p[2])), collect(contents(obj))))

call(con::Connection, cmd, args...) = cmds[Symbol(cmd)](con, args...)

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

function document(con::Connection, dom = con.document)
    con.document = dom
    local ids = findIds([], con.document[:contents])

    checkpath([], con.document[:contents])
    println("set document to ", repr(dom))
    if !isempty(ids)
        push!(con.index, ids...)
    end
    queue(con, ["document", juliaobj2webobj(con.document)])
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
    start(DIR::String, PORT = 8085; [browse = false]) do CONNECTION, EVENT
        event.onset(TYPE, PROPERTY) do dom, key, arg, obj, event
            ...
        end
        event.onclick(TYPE, PROPERTY) do dom, key, arg, obj, event
            ...
        end
        event.onchanged(TYPE) do dom, key, arg, obj, event
            ...
        end
        ...
    end

Start a Domdom server, given a function that configures the events and the new connection

The provided function must return the top-level document
"""
function start(eventfunc, dir::String, port = 8085; browse = false)
    set = Dict()
    changed = Dict()
    click = Dict()
    start(dir, patternhandler(Dict([:set=>set :changed=>changed :click=>click])), port, browse=browse) do con
        eventfunc(con, (
            onset = (hnd, type, attr)-> set[(type, attr)] = hnd,
            onchanged = (hnd, type)-> changed[type] = hnd,
            onclick = (hnd, type, attr)-> click[(type, attr)] = hnd,
        ))
    end
end
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
                    document(connection, conFunc(connection))
                    flushqueue(connection)
                    while !eof(ws)
                        frame = HTTP.WebSockets.readframe(ws)
                        startqueue(connection)
                        verbose("RECEIVED: ", String(frame))
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

"""
    patternhandler(DICT; clickhandler = nullhandler, sethandler = nullhandler, keyhandler = nullhandler)

DICT is a dictionary with optional :set, :click, and :key entries.

Each entry is (TYPE, FIELD)=> function(DOMITEM, KEY, ARG, OBJ, EVENT)

- TYPE is the type of the event's JSON object
- FIELD is the field in the event's JSON object that is being changed or clicked
- DOMITEM is the item in the document
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
        get(handlers, (objtype, key), get(handlers, objtype, defaulthandler))(getpath(con, location[1:end - 1]), key, arg, obj, event)
        if event == :set
            changedhandlers = get(dict, :changed, emptyDict)
            get(changedhandlers, objtype, nullhandler)(getpath(con, location[1:end - 1]), key, arg, obj, event)
        end
    end
end

end #module