include("server.jl")

module App

using Main.Domdom

(dir,) = splitdir(@__FILE__)
(dir,) = splitdir(dir)

println("dir: ", dir)

useverbose(true)

newheader(item) = DocObject(item, :header, heading = "")
newloginview(item) = DocObject(item, :account, name="", password="")
newloginview(item, id) = DocObject(item, :account, name="", password="", id=id)
neweditview(item) = DocObject(item, :namespace, namespace = "edit", content = newloginview(item))
newholder(item) = DocObject(item, :holder, contents = item)
newhidden(item) = DocObject(item, :hidden, contents = item)
newref(con, ref) = DocObject(con, :ref, ref = ref)

function displayview(top, views...)
    con = connection(top)
    top[1] = newheader(con)
    idx = 1
    for view in views
        idx += 1
        top[idx] = view
    end
    while length(top) > length(views) + 1
        println("DELETE LAST FROM: ", top)
        pop!(top)
    end
    cleanall!(top)
end

function message(top, msg)
    push!(top, OBJ(:message, message = msg))
end

mutable struct Properties
    editing
    Properties() = new(false)
end

props(doc::Union{DocArray,DocObject}) = props(connection(doc))
props(con::Connection) = get!(con.properties, :aqua, Properties())

on(handler, event, dict) = dict[event] = handler

function withhandler(block)
    dict = Dict()
    handler = (on = (hnd, event...)-> dict[if length(event) == 1 event[1] else event end] = hnd, )
    block(handler)
    dict
end

function exampleStartFunc()
    sethandlers = withhandler() do sets
        sets.on(:account, :name) do doc, key, arg, obj, event
            println("SETTING USERNAME TO $arg")
            doc.currentusername = doc.name
        end
    end
    changedhandlers = withhandler() do changed
        changed.on(:account) do doc, key, arg, obj, event
            println("CHANGED: $key in $(repr(obj))")
            if props(doc).editing
                root(doc)[1].heading = "EDITING*"
            end
        end
    end
    clickhandlers = withhandler() do clicked
        clicked.on(:header, :login) do doc, key, arg, obj, event
            top = root(doc)
            displayview(top, newloginview(doc))
            top[1].heading = "LOGIN"
        end
        clicked.on(:header, :edit) do doc, key, arg, obj, event
            props(doc).editing = true
            top = root(doc)
            displayview(top, neweditview(doc))
            top[1].heading = "EDITING"
            cleanall!(top)
        end
        clicked.on(:header, :holder) do doc, key, arg, obj, event
            top = root(doc)
            displayview(top, newholder(newloginview(doc)))
            top[1].heading = "LOGIN (HOLDER)"
        end
        clicked.on(:header, :ref) do doc, key, arg, obj, event
            top = root(doc)
            displayview(top, newhidden(newloginview(doc, "login")))
            top[1].heading = "LOGIN (REF)"
            top[3] = newref(doc, "@login")
        end
        clicked.on(:account, :login) do doc, key, arg, obj, event
            println("LOGIN: $(doc.username), $(doc.password)")
            doc.currentpassword = doc.password
        end
        clicked.on(:account, :save) do doc, key, arg, obj, event
            println("Save: $(doc)")
        end
        clicked.on(:account, :cancel) do doc, key, arg, obj, event
            println("Cancel: $(doc)")
        end
    end
    start(dir * "/html", patternhandler(Dict([
        :set => sethandlers
        :changed => changedhandlers
        :click => clickhandlers
    ]))) do con
        document(con, DocObject(con, :document, contents = DocArray(con, newheader(con))))
        global mainDoc = con.document
    end
end

if isinteractive()
    @async exampleStartFunc()
else
    exampleStartFunc()
end

end
