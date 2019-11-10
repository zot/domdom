# Copyright (C) 2019, by Bill Burdick, ZLIB licensed, https://github.com/zot/domdom

using Domdom

module App

using Main.Domdom

dir = dirname(dirname(dirname(@__FILE__)))

#useverbose(true)

verbose("dir: ", dir)

mutable struct AccountMgr
    editing
    currentid
    accounts
    dialogs
    mode
    AccountMgr() = new(false, 0, Dict(), [], :none)
end

struct Dialog
    dom
    okfunc
    cancelfunc
end

mutable struct Account
    id
    name
    address
end

app(dom::Dom) = app(connection(dom))
app(con::Connection) = get!(con.properties, :aqua, AccountMgr())
props = domproperties

headerdom(item) = DomObject(item, :header, heading = "")

logindom(item) = DomObject(item, :login, name="", password="")

editdom(item) = DomObject(item, :view, namespace = "edit", contents = logindom(item))

refdom(item) = refdom(connection(item), webpath(item))
refdom(con, ref) = DomObject(con, :ref, path = ref)
deref(ref::DomObject) = getpath(connection(ref), web2julia(ref.path))

function accountsdom(dom)
    items = map(accountdomf(dom), sort(collect(values(app(dom).accounts)), by=x->x.name))
    accounts = DomArray(connection(dom), [], items)
    DomObject(dom, :accounts, accounts = accounts)
end

accountdomf(dom) = acct-> accountdom(dom, acct)
accountdom(dom, acctid::Integer) = accountdom(dom, app(dom).accounts[acctid])
function accountdom(dom, acct::Account)
    DomObject(dom, :account, acctId=acct.id, name=acct.name, address=acct.address)
end

function fixaccountdoms(acctdoms)
    accounts = sort(collect(values(app(acctdoms).accounts)), by = a-> a.name)
    verbose("ACCOUNTS: $(accounts)")
    i = 1
    while i <= max(length(acctdoms), length(accounts))
        if length(accounts) < i
            pop!(acctdoms)
        else
            if length(acctdoms) < i || acctdoms[i].acctId != accounts[i].id
                acctdoms[i] = accountdom(acctdoms, accounts[i])
            end
            i += 1
        end
    end
    acctdoms
end

function pushDialog(dom::Dom, ok, cancel)
    push!(app(dom).dialogs, Dialog(dom, ok, cancel))
end

function displayview(main, mode::Symbol, views...)
    con = connection(main)
    app(main).mode = mode
    main[1] = headerdom(con)
    idx = 1
    for view in views
        idx += 1
        main[idx] = view
    end
    while length(main) > length(views) + 1
        verbose("DELETE LAST FROM: ", main)
        pop!(main)
    end
    cleanall!(main)
end

function arrayitem(dom)
    while !isa(path(dom)[end], Number)
        dom = parent(dom)
    end
    (parent(dom), path(dom)[end])
end

function exampleStartFunc()
    start(dir * "/html") do con, events
        events.onset(:login, :name) do dom, key, arg, obj, event
            verbose("SETTING USERNAME TO $arg")
            dom.currentusername = dom.name
        end
        events.onclick(:header, :login) do dom, key, arg, obj, event
            top = root(dom).main
            displayview(top, :login, logindom(dom))
            top[1].heading = "LOGIN"
        end
        events.onclick(:header, :edit) do dom, key, arg, obj, event
            app(dom).editing = true
            top = root(dom).main
            displayview(top, :edit, editdom(dom))
            top[1].heading = "EDITING"
            cleanall!(top)
            verbose("MODE: $(app(top).mode)")
        end
        events.onclick(:header, :accounts) do dom, key, arg, obj, event
            verbose("CLICKED ACCOUNTS")
            top = root(dom).main
            # show a list of refs
            # not using a ref to the list here so that each ref can be replaced with an editor
            displayview(top, :accounts, DomObject(dom, :accounts, accounts = fixaccountdoms(DomArray(dom))))
            top[1].heading = "ACCOUNTS"
        end
        events.onclick(:login, :login) do dom, key, arg, obj, event
            verbose("LOGIN: $(dom.username), $(dom.password)")
            dom.currentpassword = dom.password
        end
        events.onclick(:login, :save) do dom, key, arg, obj, event
            verbose("Save: $(dom)")
        end
        events.onclick(:login, :cancel) do dom, key, arg, obj, event
            verbose("Cancel: $(dom)")
        end
        events.onclick(:accounts, :newaccount) do dom, key, arg, obj, event
            verbose("CLICKED ACCOUNTS")
            top = root(dom).main
            acct = DomObject(dom, :account, name="", address="")
            props(acct).mode = :new
            push!(top, DomObject(dom, :newaccount, account = acct))
            props(acct).save = function()
                verbose("Save NEW ACCOUNT")
                mgr = app(dom)
                (id, acct) = newaccount(mgr, acct.name, acct.address)
                mgr.accounts[id] = acct
                push!(root(dom).accounts, accountdom(top, acct))
                fixaccountdoms(top[2].accounts)
                pop!(root(dom).main)
            end
            props(acct).cancel = function()
                verbose("Cancel NEW ACCOUNT")
                pop!(root(dom).main)
            end
        end
        events.onclick(:account, :edit) do dom, key, arg, obj, event
            index = path(dom)[end]
            verbose("EDIT[$(index)]: $(path(dom)), $(dom), $(key)")
            acctdom = accountdom(dom, dom.acctId)
            root(dom).main[2].accounts[index] = DomObject(dom, :view, namespace="edit", contents = acctdom)
            props(acctdom).cancel = function()
                verbose("Cancel")
                root(dom).main[2].accounts[index] = accountdom(root(dom), dom.acctId)
            end
            props(acctdom).save = function()
                verbose("Save: $(dom)")
            end
        end
        events.onclick(:account, :save) do dom, key, arg, obj, event
            props(dom).save()
        end
        events.onclick(:account, :cancel) do dom, key, arg, obj, event
            props(dom).cancel()
        end
        events.onclick(:account, :delete) do dom, key, arg, obj, event
            verbose("Delete: $(path(dom)), key = $(key), arg = $(arg), $(dom),\nArrayItem: $(arrayitem(dom))\nID: $(dom.acctId)")
            delete!(app(dom).accounts, dom.acctId)
            (array, index) = arrayitem(dom)
            deleteat!(array, index)
        end
        initaccounts(con)
        global mainDom = DomObject(con, :document, contents = DomObject(con, :top, main = DomArray(con, [], [headerdom(con)]), accounts = accountsdom(con).accounts))
    end
end

#delegate(dom, key, arg, obj, event)

function newaccount(mgr, name, address)
    id = mgr.currentid
    mgr.currentid += 1
    id => Account(id, name, address)
end

function initaccounts(con)
    mgr = app(con)
    mgr.accounts = Dict([
        newaccount(mgr, "herman", "1313 A")
        newaccount(mgr, "lilly", "1313 B")
    ])
end

if isinteractive()
    @async exampleStartFunc()
else
    exampleStartFunc()
end

end
