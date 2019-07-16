include("server.jl")

println(JSONMetadom)

using Main.JSONMetadom

(dir,) = splitdir(@__FILE__)
(dir,) = splitdir(dir)

println("dir: ", dir)

#useverbose(true)

function exampleStartFunc()
    start(dir * "/html", patternhandler(Dict([
        :set => Dict([
            (:account, :username) => function (docpath, key, arg, obj, event)
            println("SETTING USERNAME TO $arg, path: $(repr(docpath)), obj: $(repr(obj)), key: $key")
            docpath.currentusername = docpath.username
            end
        ])
        :click => Dict([
            (:account, :login) => function (docpath, key, arg, obj, event)
            println("LOGIN: $(docpath.username), $(docpath.password)")
            docpath.currentpassword = docpath.password
            end
        ])
    ]))) do con
        # Start by pushing a JSON document to the connection
        # This uses the OBJ() helper function
        # You could just use a Dict here -- see [JSONMetadom](https://github.com/zot/JSONMetadom) for details on the format of the JSON object
        document(con, OBJ(:document, [
            :contents => Any[
                OBJ(:account, [
                    :username => ""
                    :password => ""
                    :currentusername => ""
                    :currentpassword => ""
                ])
            ]
        ]))
        doc(con)[1].username = "Bubba"
        doc(con)[1].password = "fred"
    end
end

if isinteractive()
    @async exampleStartFunc()
else
    exampleStartFunc()
end
