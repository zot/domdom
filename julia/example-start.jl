include("server.jl")

module App

using Main.Domdom

(dir,) = splitdir(@__FILE__)
(dir,) = splitdir(dir)

println("dir: ", dir)

useverbose(true)

mutable struct Properties
    editing
    currentid
    accounts
    Properties() = new(false, 0, Dict())
end

mutable struct Account
    id
    name
    address
end

props(doc::Union{DocArray,DocObject}) = props(connection(doc))
props(con::Connection) = get!(con.properties, :aqua, Properties())

newheader(item) = DocObject(item, :header, heading = "")
newloginview(item) = DocObject(item, :login, name="", password="")
newloginview(item, id) = DocObject(item, :login, name="", password="", id=id)
neweditview(item) = DocObject(item, :namespace, namespace = "edit", content = newloginview(item))
newholder(item) = DocObject(item, :holder, contents = item)
newhidden(item) = DocObject(item, :hidden, contents = item)
newref(item) = newref(connection(item), path(item))
newref(con, ref) = DocObject(con, :ref, ref = ref)
function newaccounts(con, disabled = nothing)
    items = map(accountdoc(con, disabled), sort(collect(values(props(con).accounts)), by=x->x.name))
    println("ITEMS: $(items)")
    println("ITEMS ARRAY: $(DocArray(con, items...))")
    accounts = DocArray(con, items...)
    hidden = clone(accounts)
    for obj in hidden
        obj.refDisabled = true
    end        
    DocObject(con, :accounts, accounts = accounts, hidden = hidden)
end

accountdoc(doc, disabled) = function(acct)
    obj = DocObject(doc, :account, acctId=acct.id, name=acct.name, address=acct.address)
    if disabled != nothing
        println("Setting $(disabled) = true")
        obj[disabled] = true
    end
    obj
end

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

on(handler, event, dict) = dict[event] = handler

function withhandler(block)
    dict = Dict()
    handler = (on = (hnd, event...)-> dict[if length(event) == 1 event[1] else event end] = hnd, )
    block(handler)
    dict
end

function exampleStartFunc()
    sethandlers = withhandler() do sets
        sets.on(:login, :name) do doc, key, arg, obj, event
            println("SETTING USERNAME TO $arg")
            doc.currentusername = doc.name
        end
    end
    changedhandlers = withhandler() do changed
        changed.on(:login) do doc, key, arg, obj, event
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
        clicked.on(:header, :accounts) do doc, key, arg, obj, event
            println("CLICKED ACCOUNTS")
            top = root(doc)
            displayview(top, newaccounts(doc, :directDisabled))
            top[1].heading = "ACCOUNTS"
        end
        clicked.on(:login, :login) do doc, key, arg, obj, event
            println("LOGIN: $(doc.username), $(doc.password)")
            doc.currentpassword = doc.password
        end
        clicked.on(:login, :save) do doc, key, arg, obj, event
            println("Save: $(doc)")
        end
        clicked.on(:login, :cancel) do doc, key, arg, obj, event
            println("Cancel: $(doc)")
        end
        clicked.on(:account, :direct) do doc, key, arg, obj, event
            println("Account direct$(path(doc)): $(doc)")
            p = parent(doc)
            if p.type == :holder
                replace(doc, clone(doc))
            elseif p.type == :ref
                replace(doc, clone(getpath(connection(doc), doc.ref)))
            end
        end
        clicked.on(:account, :ref) do doc, key, arg, obj, event
            println("Account ref$(path(doc)): $(doc)")
            p = parent(doc)
            if isa(p, DocArray)
                replace(doc, newref(doc))
            elseif p.type == :holder
                replace(doc, newref(doc.contents))
            end
        end
        clicked.on(:account, :holder) do doc, key, arg, obj, event
            println("Account holder$(path(doc)): $(doc)")
            p = parent(doc)
            ** patch path **
            if isa(p, DocArray)
                replace(doc, newholder(clone(doc)))
            elseif p.type == :ref
                replace(doc, newholder(clone(getpath(connection(doc), doc.ref))))
            end
        end
    end
    start(dir * "/html", patternhandler(Dict([
        :set => sethandlers
        :changed => changedhandlers
        :click => clickhandlers
    ]))) do con
        initaccounts(con)
        document(con, DocObject(con, :document, contents = DocArray(con, newheader(con))))
        global mainDoc = con.document
    end
end

function newaccount(prop, name, address)
    id = prop.currentid
    prop.currentid += 1
    id => Account(id, name, address)
end

function initaccounts(con)
    properties = props(con)
    properties.accounts = Dict([
        newaccount(properties, "herman", "1313 A")
        newaccount(properties, "lilly", "1313 B")
    ])
end

if isinteractive()
    @async exampleStartFunc()
else
    exampleStartFunc()
end

end
