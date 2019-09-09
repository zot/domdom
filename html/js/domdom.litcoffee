# Domdom: a simple, dynamic HTML presentation system that supports local or client/server usage

Copyright (C) 2019, by Bill Burdick, ZLIB licensed, https://github.com/zot/domdom

Domdom uses a JSON object to implement its own Document Object Model that you can share with your local JavaScipt code or with a server. Domdom renders the JSON object in the browser using definitions you provide and it re-renders parts of the GUI when you change values in the JSON object. You can manage the model either in local JavaScript or on a server. Domdom also binds parts of the JSON object and changes it when users interact with the GUI, transmitting those changes to the local JavaScript code or to the server.

Domdom is engineered to be simple and lightweight, defined in roughly 500 lines of CoffeeScript.

# Overview

Domdom chooses a "view" for each nested object in the JSON object you provide by using the object's "type" property. Views are defined using Handlebars, displaying with the JSON object as their context. Domdom also supports namespaces for views, i.e. you can define different views on the same type for different contexts (an object could render as a form in one namespace and a list item in another namespace).

When the Javascript model (or server, if connected) changes some of Domdom's JSON objects, it automatically rerenders the views for those objects.

Domdom can bind values in its HTML views to paths in its JSON objects so that the HTML can display and/or change the values at thoses paths. When the user changes one of those values, Domdom changes the JSON object at that path and sends an event to the Javascript model (or the server, if connected).

# Views

Views can also contain other views because Domdom defines a "view" Handlebar plugin.

Views can contain elements with `data-path` attributes that specifying a
*path* to a property in the JSON object, example:

`<input type=text data-path="a.b.c">`

If an element has a non-null data-bind-keypress attribute, any keypresses that are not enter or return will be sent as "key" events to the Javascript model (or server, if connected).

An element is considered to be a button if it has a data-path property and it is either a non-input element, a button element, or a submit element. The behavior on the JSON object depends on its "value" attribute (if there is one):

* no value attribute: when you press the button, Domdom does not change the JSON object but it sends a click event to the model (see Events, below)
* the value is a boolean: it acts as a checkbox and when you press it, Domdom sets the boolean value in the JSON object and sends a "set" event (see Events, below)
* otherwise: when the input element changes (like by focusing out of a field), Domdom sets the JSON path in the object to the value property, parsed as a JSON value (see Events, below)

# Main JSON object

views: {NAMESPACE: {TYPE: HANDLEBARSDEF}, ...}
type: top
content: [DATA, ...]

The main JSON object supplied to Domdom can optionally provide

# Events
The Javascript model (or the server, if you are connecting to one) recieves events for clicks and sets with the JSON path and the new value, if there is one. The model (or server) can then change the JSON model in response to trigger an update on the screen, which re-renders the parts of the model that have changed.

# Viewdefs

You define views with viewdefs and this is normally in the HTML file by putting `data-viewdef` attributes in HTML elements. the value of the `data-viewdef` element can be:

- `TYPE`, where TYPE is any string value a JSON object might have in its `type` property
- `NAMESPACE/TYPE`, where namespace is any name you choose to make a namespace and TYPE is as above

You can use a namespace with the `view` Handlebars plugin (see below).

You can also define viewdefs in the `views` property of the main JSON object.

# The namespace type
The namespace type sets the namespace for its content object or array of objects, like this:

{"type": "namespace", "namespace": "bubba", "content": ...}

This will set the namespace to bubba for the content object or array of objects.

# The view plugin for Handlebars

The predefined `view` plugin lets you show a view on an object or array of objects and you can optionally set the namespace, like this:

{{{view `path.in.JSON.object`}}}

or

{{{view `path.in.JSON.object` `namespace-name`}}}

# Events
There are two types of events:

- set(path, value): the user changed something in the GUI that triggered a set event
- click(path, value): the user clicked a button, which can optionally include a value, depending on the view

# Controllers
If you need custom javascript code, you can use a script element. You an use `element.query()`, `element.queryAll()`, `element.closest()`, etc. to access your view. In addition, these properties will be available:

- `document.currentScript` will be the script element (as usual)
- `Domdom.currentScript` will also hold the script element
- `Domdom.activating` will be true, check this to verify that a view is actually initializing
- `Domdom.context` will be the current context object
- `Domdom.docPath` will be the current docPath (see DocPaths, below)

Also, each view will have a `data-location` attribute set to its path and a `data-namespace` attribute set to the view's namespace.

# Using Domdom

On the web side, you need to make sure the files in the js and css directories are available to your HTML file and include these elements (altered to fit your file layout, of course):

\<link rel="stylesheet" href="css/domdom.css">\</link>
\<script src="js/lib/handlebars-v4.0.5.js">\</script>
\<script src="js/domdom.js">\</script>

It's also compatible with AMD style so you can use something like require.js:

\<link rel="stylesheet" href="css/metadom.css">\</link>
\<script data-main="js/config" src="js/lib/require-2.1.18.js">\</script>

You can implement the model in local JavaScript or in a server. Metadom currently supports Julia servers.

# Connecting to a server
Put this at the bottom of the body of your web page, with the HOST and PORT of your server in it:

\<script>Domdom.connect({}, "ws://HOST:PORT")\</script>

The Julia server code supports its own version of event handlers and DocPath (see the JavaScript model documentation below)

# Using Domdom with a JavaScript model

* Create a Javascript object with
```
{type: 'document',
 views: {default: {viewdefs...},
 NAMESPACE1: {viewdefs...}},
 contents: [CONTENTS...]}
```

Views are optional in the object since they can also be in the HTML page.

- Create a context with {top: JSON, handler: HANDLER}
  - JSON is the JSON object you have created
  - HANDLER is an event handler
    - You can use the patternHandler() function to easily specify event handlers (see source for documentation).
    - Otherwise, the handler is {clickButton: (evt)=> ..., changedValue: (evt)=> ..., key: (evt)=> ...}
    - the dispatchClick, dispatchKey, and dispatchSet functions dispatch events in a high-level way, using DocPaths (see below)
## DocPaths
A DocPath is proxy that makes it easy navigate paths in the JSON object and it lets you change the JSON object and automatically trigger re-rendering for those changes. It's called DocPath because the JSON object is the "document" of the Document Object Model. PatternHandler and the three dispatch functions (dispatchClick, dispatchKey, and dispatchSet) each send a DocPath as the first argument to your provided event handler function.

Given docp is a DocPath...

- `docp.PROP` returns the value in the document at PROP if it is atomic or, if the value is an array or object, it returns a new DocPath for that location (with docp's path extended to include PROP)
- `docp[INDEX]` returns the value in the document at INDEX if it is atomic or, if the value is an array or object, it returns a new DocPath for that location (with docp's path extended to include INDEX)
- `docPathValue(docp)` returns docp's value
- `docp.PROP = VALUE` sets the value in the document and cause Domdom to re-render it
- `docPathParts(docp)` returns the "parts" of a DocPath, the Domdom object, the context, and the path array

You can use `batch(con, func)` if you need to change DocPaths outside of an event handler for "event compression". Batch eliminates re-rendering of the same object multiple times.

# History

I came up with the original concept around 2000 or 2001, as the next step in evolution for Classic Blend (a remote presentation system I first developed in 1995). The idea of the next step was that if you abstracted an entire GUI into a set of shared variables, you could use the variables to control a remote GUI from a server kind of like a [tuple space](https://en.wikipedia.org/wiki/Tuple_space) or like [SNMP](https://en.wikipedia.org/wiki/Simple_Network_Management_Protocol). Beyond this, you could reskin the GUI in dramatically different ways -- far more radically than GTK themes, for instance -- switching from a web browser to the Unreal engine, for example, where menus might be presented as shops (I actually prototyped a Quake-based front end at one point).

I've been using an earlier and quite different variation of this idea since 2006 on an extremely large project. The browser side of the presentation is fully automatic now and we don't write any JavaScript for our front ends anymore, unless we're adding new kinds of widgets.

This version of the concept, Domdom, grew out of the Leisure project (which will eventually be updated to use Domdom) and I've used variations of this JavaScript and server code in several of my personal projects.

The [Xus](https://github.com/zot/Xus) project is also related to this. It really implements the shared variables.

    define = window.define ? (n, func)-> window.Domdom = func(window.Handlebars)

    define ['handlebars'], (Handlebars)->
      {
        compile
        registerHelper
      } = Handlebars

      curId = 0

      keyCode = (evt)->
        if !(evt.key.toLowerCase() in ['shift', 'control', 'alt'])
          key = evt.key
          if key.toLowerCase().startsWith 'arrow'
            key = key[5...].toLowerCase()
          if evt.shiftKey && key.length > 1 then key = "S-" + key
          if evt.ctrlKey then key = "C-" + key
          if evt.altKey || evt.metaKey then key = "M-" + key
          key

      nodeToTop = new WeakMap()

      parsingDiv = document.createElement 'div'

      query = document.querySelector.bind document

      queryAll = document.querySelectorAll.bind document

      find = (node, selector)-> node.querySelectorAll selector

      parseHtml = (str)->
        parsingDiv.innerHTML = "<div>#{str}</div>"
        dom = parsingDiv.firstChild
        parsingDiv.innerHTML = ''
        if dom.childNodes.length == 1 && dom.firstChild.nodeType == 1 then dom.firstChild else dom

      locationToString = (loc)->
        str = ""
        for coord in loc
          if str then str += " "
          str += coord
        str

      stringToLocation = (str)->
        (if String(Number(coord)) == coord then Number(coord) else coord) for coord in str.split ' '

      resolvePath = (doc, location)->
        if typeof location == 'string'
          [j, path, parent] = doc.index[location]
          location = path
        if typeof location[0] == 'string' && location[0][0] == '@'
          first = location[0][1...]
          [j, path, parent] = doc.index[first]
          location = if location.length > 1 then [path..., location[1...]...] else path
        location

      normalizePath = (path, index)->
        if Array.isArray path then path
        else
          [ignore, path] = index[if typeof path == 'object' then path.id else path]
          path

      findIds = (parent, json, ids = {}, location = [])->
        if Array.isArray json
          for el, i in json
            findIds json, el, ids, [location..., i]
        else if json != null && typeof json == 'object'
          if json.type?
            if !json.id?
              json.id = ++curId
              json.__assignedID = true
            ids[json.id] = [json, location, parent]
          for k, v of json
            findIds json, v, ids, [location..., k]
        ids

      closestLocation = (node)-> node.closest('[data-location]').getAttribute 'data-location'

      globalContext = namespace: 'default'

      replace = (oldDom, newDom)->
        # prefer mutating the old dom to replacing it
        if oldDom && oldDom.nodeName == newDom.nodeName && oldDom.childNodes.length == 0 && newDom.childNodes.length == 0
          na = new Set newDom.getAttributeNames()
          for n in oldDom.getAttributeNames()
            if !na.has(n) then oldDom.removeAttribute n
          for n of na
            nav = newDom.getAttribute n
            if nav != oldDom.getAttribute n
              oldDom.setAttribute n, nav
          oldDom
        else
          oldDom.replaceWith newDom
          newDom

      metadoms = []

      metadomBlur = (event)->
        for md in metadoms
          if event.target.nodeType == 1 && md.top.contains event.target
              md.blurring = true

      metadomFocus = (event)->
        for md in metadoms
          if md.blurring
            md.blurring = false
            md.runRefreshQueue()

      metadomChange = (event)->

      class Domdom
        constructor: (@top)->
          if !@top then throw new Error "No top node for Domdom"
          @refreshQueue = [] # queued refresh commands that execute after the current event
          @specialTypes =
            document: (dom, json, context)=> @renderTop dom, json, context
            namespace: (dom, json, context)=> @renderNamespace dom, json, context
          if !metadoms.length
            window.addEventListener "blur", metadomBlur, true
            window.addEventListener "focus", metadomFocus, true
            window.addEventListener "change", metadomChange, true
          metadoms.push this

        activateScripts: (el, ctx)->
          if !Domdom.activating
            Domdom.activating = true
            Domdom.context = ctx
            Domdom.docPath = docPath this, ctx, ctx.location
            try
              for script in el.querySelectorAll 'script'
                if (!script.type || script.type.toLowerCase() == 'text/javascript') && (text = script.textContent)
                  newScript = document.createElement 'script'
                  newScript.type = 'text/javascript'
                  if script.src then newScript.src = script.src
                  newScript.textContent = text
                  #keep the current script here in case the code needs access to it
                  Domdom.currentScript = newScript
                  script.parentNode.insertBefore newScript, script
                  script.parentNode.removeChild script
            finally
              Domdom.currentScript = null
              Domdom.activating = false
              Domdom.context = null

Find view for json and replace dom with the rendered view. Context contains global info like the
current namespace, etc.

        render: (dom, json, context)->
          context.views ?= {}
          newDom = @baseRender dom, json, Object.assign {location: []}, context
          @analyzeInputs newDom, context
          newDom

        baseRender: (dom, json, context)->
          context = Object.assign {}, globalContext, context
          id = json.id ? dom.getAttribute('id') ? ++curId
          dom.setAttribute 'id', id
          if Array.isArray json
            newDom = parseHtml("<div data-location='#{locationToString context.location}'></div>")
            newDom.setAttribute 'id', id
            dom.replaceWith newDom
            for childDom, i in json
              el = document.createElement 'div'
              newDom.appendChild el
              @baseRender el, childDom, Object.assign {}, context, {location: [context.location..., i]}
            newDom
          else if special = @specialTypes[json.type]
            special dom, json, context
          else @normalRender dom, json, context

        # special renderers can use this to modify how their views render
        normalRender: (dom, json, context)->
          def = @findViewdef json.type, context
          newDom = parseHtml(if def
            try
              old = globalContext
              globalContext = context
              def json, data: Object.assign {metadom: this}, {context}
            finally
              globalContext = old
          else "COULD NOT RENDER TYPE #{json.type}, NAMESPACE #{context.namespace}")
          newDom.setAttribute 'data-location', locationToString context.location
          newDom.setAttribute 'data-namespace', context.namespace
          newDom.setAttribute 'id', json.id
          newDom = replace dom, newDom
          @populateInputs newDom, json, context
          @activateScripts newDom, context
          newDom

        findViewdef: (type, context)->
          if def = context.views?[context.namespace]?[type] then return def
          else if el = query "[data-viewdef='#{context.namespace}/#{type}']" then namespace = context.namespace
          else if def = context.views?.default?[type] then return def
          else if !(el = query "[data-viewdef='#{type}']") then return null
          if !context.views? then context.views = {}
          if !context.views[namespace]? then context.views[namespace] = {}
          domClone = el.cloneNode true
          domClone.removeAttribute 'data-viewdef'
          context.views[namespace][type] = compile domClone.outerHTML

        rerender: (json, context, thenBlock)->
            @queueRefresh =>
                oldDom = query "[id='#{json.id}']"
                context = Object.assign {}, context, location: stringToLocation oldDom.getAttribute 'data-location'
                if oldDom.getAttribute 'data-namespace' then context.namespace = oldDom.getAttribute 'data-namespace'
                newDom = @render query("[id='#{json.id}']"), json, context
                top = newDom.closest('[data-top]')
                for node in find newDom, '[data-path-full]'
                    @valueChanged top, node
                thenBlock newDom

        renderTop: (dom, json, context)->
          {views, contents} = json
          json.index = findIds null, contents
          json.compiledViews = {}
          context.views ?= {}
          for namespace, types of views
            json.compiledViews[namespace] ?= {}
            context.views[namespace] ?= {}
            for type, def of types
              #destructively modify context's views
              context.views[namespace][type] = json.compiledViews[namespace][type] = compile(def)
          newDom = @baseRender dom, contents, Object.assign context, {top: json, location: []}
          newDom.setAttribute 'data-top', 'true'
          nodeToTop.set newDom, context
          newDom

        renderNamespace: (dom, json, context)->
          if !json.namespace then throw new Error("No namespace in namespace element #{JSON.stringify json}")
          @baseRender dom, json.content, Object.assign {}, context, {namespace: json.namespace, location: [context.location..., "content"]}

        queueRefresh: (cmd)->
            @refreshQueue.push cmd
            if !@pressed && !@blurring && document.activeElement != document.body
                @runRefreshQueue()

        runRefreshQueue: ->
            if @refreshQueue.length > 0
                q = @refreshQueue
                @refreshQueue = []
                setTimeout (->
                    for cmd in q
                        # TODO this selects even if the focus event was a mouse click instead of a tab
                        if activeInput = document.activeElement.getAttribute 'data-path-full'
                            index = Array.prototype.slice.call(queryAll("[data-path-full='#{activeInput}']")).indexOf document.activeElement
                        cmd()
                        if activeInput && input = queryAll("[data-path-full='#{activeInput}']")[index]
                            input.focus()
                            input.select?()
                ), 5

        addSpecialType: (typeName, func)-> @specialTypes[typeName] = func

        replace: (top, path, json, context)->
          if !context
            context = json
            json = path
            path = {id: json.id}
          if !(index = top.index) then index = top.index = {}
          context = Object.assign {views: top.compiledViews, top: top}, context
          namespace = 'default'
          path = normalizePath path, index
          oldJson = top.contents
          parent = oldJson
          property = null
          for location in path
            parent = oldJson
            oldJson = oldJson[location]
          parent[location[location.length - 1]] = oldJson
          if oldJson.id then json.id = oldJson.id
          @adjustIndex index, parent, oldJson, json
          context.location = path
          @rerender json, context, ->

        adjustIndex: (index, parent, oldJson, newJson)->
          oldIds = findIds parent, oldJson
          newIds = findIds parent, newJson
          oldKeys = new Set(Object.keys(oldIds))
          for k, v of newIds
            if v[1].length == 0
              if Object.keys(newIds).length == 1 && Object.keys(oldIds).length == 1
                k = Object.keys(oldIds)[0]
                v[1] = index[k][1]
                if v[0].__assignedID && index[k][0].__assignedID then v[0].id = k
              else v[1] = index[k][1]
            index[k] = v
            oldKeys.delete(k)
          for k of oldKeys
            delete index[k]

        analyzeInputs: (dom, context)->
          for node in find dom, "input, textarea, button, [data-path]"
            do (node)=> if fullpath = node.getAttribute 'data-path-full'
              path = stringToLocation node.getAttribute 'data-path-full'
              if node.getAttribute 'data-bind-keypress'
                node.on 'keydown', (e)->
                  if !(keyCode(e) in ['C-r', 'C-J'])
                    e.preventDefault()
                    e.stopPropagation()
                    context.handler.keyPress? e.originalEvent
              if (node.type in ['button', 'submit']) || node.type != 'text'
                # using onmousedown, onclick, path, and @pressed because
                # the view can render out from under the button if focus changes
                # which replaces the button with ta new one in the middle of a click event
                node.onmousedown = (evt)=> @pressed = path
                node.onclick = (evt)=>
                  if @pressed == path || evt.detail == 0
                    @pressed = false
                    newValue = if v = node.getAttribute 'value'
                      try
                        JSON.parse v
                      catch err
                        v
                    else if typeof (oldValue = @getPath context.top, context.top.contents, path) == 'boolean'
                      newValue = !oldValue
                    if newValue
                      @setValueFromUser node, evt, dom, context, path, newValue
                    else
                      context.handler.clickButton? evt
                    @runRefreshQueue()
              else
                node.onchange = (evt)=>
                  ownerPathString = evt.srcElement.closest('[data-location]').getAttribute 'data-location'
                  ownerPath = stringToLocation ownerPathString
                  @setValueFromUser node, evt, dom, context, path, node.value

        setValueFromUser: (node, evt, dom, context, path, value)->
          ownerPathString = node.closest('[data-location]').getAttribute 'data-location'
          ownerPath = stringToLocation ownerPathString
          json = @getPath context.top, context.top.contents, ownerPath
          @setPath context.top, context.top.contents, path, value
          context.handler.changedValue? evt, value
          @valueChanged evt.srcElement.closest('[data-top]'), evt.srcElement
          @queueRefresh =>
            for node in queryAll "[data-location='#{ownerPathString}']"
              namespace = node.getAttribute 'data-namespace'
              @render node, json, Object.assign {}, context, {namespace: namespace, location: ownerPath}

        populateInputs: (dom, json, context)->
          if dom.getAttribute 'data-location'
            setSome = false
            location = stringToLocation dom.getAttribute 'data-location'
            for node in find dom, "[data-path]"
              if node.closest('[data-location]') == dom
                path = node.getAttribute('data-path').split('.')
                fullpath = locationToString [location..., path...]
                if node.type == 'text' then node.setAttribute 'value', @getPath context.top, json, path
                node.setAttribute 'data-path-full', fullpath
                setSome = true
            setSome

        valueChanged: (dom, source)->
          value = source.value
          fullpath = source.getAttribute 'data-path-full'
          for node in find(dom, "[data-path-full='#{fullpath}']") when node != source
            node.value = value

        getPath: (doc, json, location)->
          location = resolvePath doc, location
          for i in location
            json = json[i]
          json

        setPath: (document, json, location, value)->
          last = json
          lastI = 0
          location = resolvePath document, location
          for i, index in location
            if index + 1 == location.length
              if value.type?
                @adjustIndex document.index, json, json[i], value
              else
                newJson = Object.assign {}, last
                newJson[lastI] = value
                @adjustIndex document.index, last, json, newJson
              json[i] = value
            else
              last = json
              lastI = i
              json = json[i]

        defView: (context, namespace, type, def)->
          context.views[namespace][type] = compile def

      Handlebars.registerHelper 'view', (item, namespace, options)->
        if typeof item != 'string' then throw new Error("View must be called with one or two strings")
        if !options?
          options = namespace
          namespace = null
        location = stringToLocation item
        context = options.data.context
        context = Object.assign {}, context, location: [context.location..., location...]
        if namespace then context.namespace = namespace
        data = this
        for i in location
          data = data[i]
        if data
          node = options.data.metadom.baseRender(parseHtml('<div></div>'), data, context)
          if node.nodeType == 1 then node.outerHTML else node.data
        else ""

Command processor clients (if using client/server)

      messages =
        batch: (con, items)->
          con.batchLevel++
          for item in items
            handleMessage con, item
          con.batchLevel--
        document: (con, doc)->
          con.document = doc
          con.context.top = doc
          con.dom = con.md.render con.dom, doc, con.context
          con.context.views = con.document.compiledViews
        set: (con, path, value)->
          con.md.setPath con.document, con.document.contents, path, value
          if !value.type? then path.pop()
          con.changedJson.add locationToString path
          path
        delete: (con, path)->
          obj = con.document.contents
          last = obj
          for i, index in path
            if index + 1 == path.length
              obj = Object.assign {}, obj
              if typeof i == 'number' then obj.splice(i, 1)
              else delete obj[i]
              path.pop()
              con.md.setPath con.document, con.document.contents, path, obj
              if !obj.type? then path.pop()
              con.changedJson.add locationToString path
              break
            else
              last = obj
              obj = obj[i]
        insert: (con, path, json)->
          obj = con.document.contents
          for i, index in path
            if index + 2 == path.length
              if typeof i == 'number' then obj.splice(i, 0, null)
              con.md.setPath con.document, con.document.contents, path, json
              path.pop()
              while !con.md.getPath(con.document, con.document.contents, path).type? then path.pop()
              con.changedJson.add locationToString path
              break
            else obj = obj[i]
        defView: (con, namespace, type, def)-> con.md.defView con.context, namespace, type, def

#Change handler

      handleChanges = (ctx)->
        if ctx.batchLevel == 0
          for path from ctx.changedJson
            ctx.md.rerender ctx.md.getPath(ctx.doc, ctx.doc.contents, stringToLocation path), ctx, (dom)->
              if dom.getAttribute('data-top')? then ctx.setTopFunc dom
          ctx.changedJson.clear()
          ctx.md.runRefreshQueue()

      change = (ctx, path)->
        ctx.changedJson.add locationToString path
        if ctx.batchLevel == 0 then handleChanges ctx

      initChangeContext = (md, ctx, doc, setTopFunc)->
        ctx.batchLevel = 0
        ctx.changedJson = new Set()
        ctx.md = md
        ctx.doc = doc
        ctx.setTopFunc = setTopFunc

`batch(CTX, FUNC)` executes FUNC, queuing up re-rendering requests and then processing the requests all at once after FUNC finishes.

      batch = (ctx, func)->
        if typeof ctx.batchLevel == 'number'
            ctx.batchLevel++
            try
                func()
            finally
                ctx.batchLevel--
                handleChanges ctx
        else func()

#Local Code

      isDocPathSym = Symbol("isDocPath")

      partsSym = Symbol("parts")

      syms = [isDocPathSym, partsSym]

`isDocPath(obj)` returns true if the object is a docPath

      isDocPath = (obj)-> obj[isDocPathSym]

`docPathParts(docp)` returns the "parts" you used to create the doc path: [md, ctx, path]

      docPathParts = (docp)-> docp[partsSym]

`docPathParent(docp)` returns a parent DocPath for docp (i.e. a DocPath without the last path element)

      docPathParent = (docp)->
        [md, ctx, path] = docPathParts docp
        if !path.length then docp
        else docPath md, ctx, path[...-1]

`docPathValue(docp)` returns the value for the DocPath

      docPathValue = (docp)->
        [md, ctx, path] = docPathParts docp
        docValue(md, ctx, path)

`docPath(md, ctx, path = [])` creates a DocPath

      docPath = (md, ctx, path = [])->
        new Proxy {},
          get: (target, name)->
            if name == isDocPathSym then true
            else if name == partsSym then [md, ctx, path]
            else if name == 'toString()' then ()-> printDocPath(md, ctx, path)
            else docValue md, ctx, [...path, name]
          set: (target, name, value)->
            if !(name in syms)
              path = [...path, name]
              md.setPath ctx.top, ctx.top.contents, path, value
              change ctx, resolvePath ctx.top, path

      docValue = (md, ctx, path, value)->
        if value == undefined
            val = md.getPath ctx.top, ctx.top.contents, path
            if val == undefined then val
            else docValue md, ctx, path, md.getPath ctx.top, ctx.top.contents, path
        else if Array.isArray value then docPath md, ctx, path
        else if typeof value == 'object' then docPath md, ctx, path
        else value

      eventPaths = (md, ctx, evt)->
        node = evt.srcElement
        fullPath = stringToLocation(node.getAttribute('data-path-full'))
        path = stringToLocation(node.getAttribute('data-path'))
        objPath = stringToLocation(node.closest('[data-location]').getAttribute('data-location'))
        obj = md.getPath ctx.top, ctx.top.contents, objPath
        value = md.getPath ctx.top, ctx.top.contents, [objPath..., path...]
        [fullPath, obj, objPath, path, value]

      dispatchClick = (md, ctx, handlers, evt)->
        [fullPath, obj, objPath, path, value] = eventPaths md, ctx, evt
        docp = docPath(md, ctx, fullPath)
        batch ctx, ->
          handlers[[obj.type, locationToString(path), "click"].join(',')]?(docp, obj, objPath, path, value, evt)
          handlers[obj.type]?[locationToString(path)]?.click?(docp, obj, objPath, path, value, evt)

      dispatchKey = (md, ctx, handlers, evt)->
        [fullPath, obj, objPath, path, value] = eventPaths md, ctx, evt
        docp = docPath(md, ctx, fullPath)
        batch ctx, ->
          handlers[[obj.type, locationToString(path), "key"].join(',')]?(docp, obj, objPath, path, value, evt)
          handlers[obj.type]?[locationToString(path)]?.key?(docp, obj, objPath, path, value, evt)

      dispatchSet = (md, ctx, handlers, evt)->
        [fullPath, obj, objPath, path, value] = eventPaths md, ctx, evt
        docp = docPath(md, ctx, fullPath)
        batch ctx, ->
          handlers[[obj.type, locationToString(path), "set"].join(',')]?(docp, obj, objPath, path, value, evt)
          handlers[obj.type]?[locationToString(path)]?.set?(docp, obj, objPath, path, value, evt)

patternHandler(MD, CTX, HANDLERS) returns an event handler and makes it easy to define event handlers for types and paths

HANDLERS specify event handlers in one of two ways (you can mix them, using whichever is more convenient):
- "TYPE,FIELD,EVENT": (OBJ, PATH, KEY, VALUE, EVT)=> ...
- TYPE: {FIELD: {EVENT: (OBJ, PATH, KEY, VALUE, EVT)=> ...}}

      patternHandler = (md, ctx, handlers)->
        ctx.handler =
          clickButton: (evt)-> dispatchClick md, ctx, handlers, evt
          changedValue: (evt)-> dispatchSet md, ctx, handlers, evt

#Client Code

Connect to WebSocket server

      handleMessage = (con, [cmd, args...])->
        messages[cmd](con, args...)
        if con.batchLevel == 0
          for path from con.changedJson
            con.md.rerender con.md.getPath(con.document, con.document.contents, stringToLocation path), con.context, (dom)->
                if dom.getAttribute('data-top')? then con.dom = dom
          con.changedJson.clear()

      connect = (con, url)->
        con.md = new Domdom query('#top')
        con.batchLevel = 0
        con.changedJson = new Set()
        con.dom = query('#top')
        con.context = Object.assign {}, con.context,
          top: null
          handler:
            keyPress: (evt)->
              if key = keyCode evt
                ws.send JSON.stringify(['key', key, stringToLocation evt.currentTarget.closest('[data-location]').getAttribute 'data-location'])
            clickButton: (evt)->
              path = stringToLocation evt.currentTarget.getAttribute('data-path-full')
              name = path.pop()
              ws.send JSON.stringify ['click', name, path]
            changedValue: (evt, value)->
              node = evt.currentTarget
              ws.send JSON.stringify ['set', stringToLocation(node.getAttribute 'data-path-full'), value ? node.value]
        ws = con.socket = new WebSocket url
        ws.onmessage = (msg)-> handleMessage con, JSON.parse msg.data
        ws

      Object.assign Domdom, {
        locationToString
        stringToLocation
        closestLocation
        query
        queryAll
        find
        parseHtml
        keyCode
        connect
        messages
        docPath
        docPathValue
        isDocPath
        docPathParts
        docPathParent
        initChangeContext
        batch
        change
        patternHandler
        dispatchClick
        dispatchKey
        dispatchSet
      }

      Domdom
