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
neweditview(item) = DocObject(item, :view, namespace = "edit", contents = newloginview(item))
newholder(item) = DocObject(item, :holder, contents = item)
newhidden(item) = DocObject(item, :hidden, contents = item)
newref(item) = newref(connection(item), path(item))
newref(con, ref) = DocObject(con, :ref, ref = ref)
function newaccounts(con)
    items = map(accountdoc(con), sort(collect(values(props(con).accounts)), by=x->x.name))
    accounts = DocArray(connection(con), [], items)
    DocObject(con, :accounts, accounts = accounts)
end

accountdoc(doc, acctid::Integer) = accountdoc(doc, props(doc).accounts[acctid])
function accountdoc(doc, acct::Account)
    DocObject(doc, :account, acctId=acct.id, name=acct.name, address=acct.address)
end

accountdoc(doc) = acct-> accountdoc(doc, acct)

function addaccountrefs(refs)
    accounts = root(refs).accounts
    while length(accounts) > length(refs)
        push!(path(refs) != [] ? refs : refs.contents, DocObject(refs, :ref, ref = [path(accounts)..., length(refs)]))
    end
    refs
end

ref(el) = ref(el, path(el))

ref(el, path) = DocObject(el, :ref, ref = path)

function displayview(main, views...)
    con = connection(main)
    main[1] = newheader(con)
    idx = 1
    for view in views
        idx += 1
        main[idx] = view
    end
    while length(main) > length(views) + 1
        println("DELETE LAST FROM: ", main)
        pop!(main)
    end
    cleanall!(main)
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
            top = root(doc).main
            println("CHANGED: $key in $(repr(obj))")
            if props(doc).editing
                top[1].heading = "EDITING*"
            end
        end
    end
    clickhandlers = withhandler() do clicked
        clicked.on(:header, :login) do doc, key, arg, obj, event
            top = root(doc).main
            displayview(top, newloginview(doc))
            top[1].heading = "LOGIN"
        end
        clicked.on(:header, :edit) do doc, key, arg, obj, event
            props(doc).editing = true
            top = root(doc).main
            displayview(top, neweditview(doc))
            top[1].heading = "EDITING"
            cleanall!(top)
        end
        clicked.on(:header, :accounts) do doc, key, arg, obj, event
            println("CLICKED ACCOUNTS")
            top = root(doc).main
            displayview(top, DocObject(doc, :accounts, accounts = addaccountrefs(DocArray(doc))))
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
        clicked.on(:account, :edit) do doc, key, arg, obj, event
            println("EDIT $(path(doc)), $(doc)")
            root(doc).main.contents[2].accounts[web2julia(path(doc)[end])] = DocObject(doc, :view, namespace="edit", contents = accountdoc(doc, doc.acctId))
        end
        clicked.on(:account, :save) do doc, key, arg, obj, event
            println("Cancel: $(doc)")
        end
        clicked.on(:account, :cancel) do doc, key, arg, obj, event
            println("Cancel: $(path(doc)) $(doc)")
            p = parent(parent(doc))
            key = web2julia(path(parent(doc))[end])
            p[key] = ref(root(doc).accounts[key])
        end
    end
    start(dir * "/html", patternhandler(Dict([
        :set => sethandlers
        :changed => changedhandlers
        :click => clickhandlers
    ]))) do con
        initaccounts(con)
        document(con, DocObject(con, :document, contents = DocObject(con, :top, main = DocArray(con, [], [newheader(con)]), accounts = newaccounts(con).accounts)))
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
