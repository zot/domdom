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

props(dom::Dom) = props(connection(dom))
props(con::Connection) = get!(con.properties, :aqua, Properties())

headerdom(item) = DomObject(item, :header, heading = "")

logindom(item) = DomObject(item, :login, name="", password="")

editdom(item) = DomObject(item, :view, namespace = "edit", contents = logindom(item))

refdom(item) = refdom(connection(item), path(item))
refdom(con, ref) = DomObject(con, :ref, path = ref)

function accountsdom(con)
    items = map(accountdom(con), sort(collect(values(props(con).accounts)), by=x->x.name))
    accounts = DomArray(connection(con), [], items)
    DomObject(con, :accounts, accounts = accounts)
end

accountdom(dom) = acct-> accountdom(dom, acct)
accountdom(dom, acctid::Integer) = accountdom(dom, props(dom).accounts[acctid])
function accountdom(dom, acct::Account)
    DomObject(dom, :account, acctId=acct.id, name=acct.name, address=acct.address)
end

function fixaccountrefs(refs)
    accounts = root(refs).accounts
    while length(accounts) > length(refs)
        push!(path(refs) != [] ? refs : refs.contents, refdom(accounts[length(refs) + 1]))
    end
    while length(refs) > length(accounts)
        pop!(refs)
    end
    refs
end

function displayview(main, views...)
    con = connection(main)
    main[1] = headerdom(con)
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

function exampleStartFunc()
    start(dir * "/html") do con, events
        events.onset(:login, :name) do dom, key, arg, obj, event
            println("SETTING USERNAME TO $arg")
            dom.currentusername = dom.name
        end
        events.onchanged(:login) do dom, key, arg, obj, event
            top = root(dom).main
            println("CHANGED: $key in $(repr(obj))")
            if props(dom).editing
                top[1].heading = "EDITING*"
            end
        end
        events.onclick(:header, :login) do dom, key, arg, obj, event
            top = root(dom).main
            displayview(top, logindom(dom))
            top[1].heading = "LOGIN"
        end
        events.onclick(:header, :edit) do dom, key, arg, obj, event
            props(dom).editing = true
            top = root(dom).main
            displayview(top, editdom(dom))
            top[1].heading = "EDITING"
            cleanall!(top)
        end
        events.onclick(:header, :accounts) do dom, key, arg, obj, event
            println("CLICKED ACCOUNTS")
            top = root(dom).main
            # show a list of refs
            # not using a ref to the list here so that each ref can be replaced with an editor
            displayview(top, DomObject(dom, :accounts, accounts = fixaccountrefs(DomArray(dom))))
            top[1].heading = "ACCOUNTS"
        end
        events.onclick(:header, :newaccount) do dom, key, arg, obj, event
            println("CLICKED ACCOUNTS")
            top = root(dom).main
            acct = DomObject(dom, :account, name="", address="")
            domproperties!(acct, :new)
            push!(top, DomObject(dom, :newaccount, account = acct))
        end
        events.onclick(:login, :login) do dom, key, arg, obj, event
            println("LOGIN: $(dom.username), $(dom.password)")
            dom.currentpassword = dom.password
        end
        events.onclick(:login, :save) do dom, key, arg, obj, event
            println("Save: $(dom)")
        end
        events.onclick(:login, :cancel) do dom, key, arg, obj, event
            println("Cancel: $(dom)")
        end
        events.onclick(:account, :edit) do dom, key, arg, obj, event
            println("EDIT $(path(dom)), $(dom)")
            root(dom).main[2].accounts[web2julia(path(dom)[end])] = DomObject(dom, :view, namespace="edit", contents = accountdom(dom, dom.acctId))
        end
        events.onclick(:account, :save) do dom, key, arg, obj, event
            if domproperties(dom) == :new
                println("Save new account: $(dom)")
                pop!(root(dom).main)
            else
                println("Save: $(dom)")
            end
        end
        events.onclick(:account, :cancel) do dom, key, arg, obj, event
            println("Cancel: $(path(dom)) $(dom)")
            p = parent(parent(dom))
            key = web2julia(path(parent(dom))[end])
            p[key] = refdom(root(dom).accounts[key])
        end
        events.onclick(:account, :delete) do dom, key, arg, obj, event
            println("Delete (Cancel): $(path(dom)) $(dom)")
            p = parent(parent(dom))
            key = web2julia(path(parent(dom))[end])
            p[key] = refdom(root(dom).accounts[key])
        end
        initaccounts(con)
        global mainDom = DomObject(con, :document, contents = DomObject(con, :top, main = DomArray(con, [], [headerdom(con)]), accounts = accountsdom(con).accounts))
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
