# JSONMetadom: a simple, dynamic HTML presentation system that supports local or client/server usage

JSONMetadom uses a JSON object to implement its own Document Object Model that you can share with your local JavaScipt code or with a server. JSONMetadom renders the JSON object in the browser using definitions you provide and it re-renders parts of the GUI when you change values in the JSON object. You can manage the model either in local JavaScript or on a server. JSONMetadom also binds parts of the JSON object and changes it when users interact with the GUI, transmitting those changes to the local JavaScript code or to the server.

JSONMetadom is engineered to be simple and lightweight, defined in roughly 500 lines of CoffeeScript.

# Overview

JSONMetadom chooses a "view" for each nested object in the JSON object you provide by using the object's "type" property. Views are defined using Handlebars, displaying with the JSON object as their context. JSONMetadom also supports namespaces for views, i.e. you can define different views on the same type for different contexts (an object could render as a form in one namespace and a list item in another namespace).

When the Javascript model (or server, if connected) changes some of JSONMetadom's JSON objects, it automatically rerenders the views for those objects.

JSONMetadom can bind values in its HTML views to paths in its JSON objects so that the HTML can display and/or change the values at thoses paths. When the user changes one of those values, JSONMetadom changes the JSON object at that path and sends an event to the Javascript model (or the server, if connected).

# History

I came up with the original concept around 2000 or 2001, as the next step in evolution for Classic Blend (a remote presentation system I first developed in 1995). The idea of the next step was that if you abstracted an entire GUI into a set of shared variables, you could use the variables to control a remote GUI from a server kind of like a [tuple space](https://en.wikipedia.org/wiki/Tuple_space) or like [SNMP](https://en.wikipedia.org/wiki/Simple_Network_Management_Protocol). Beyond this, you could reskin the GUI in dramatically different ways -- far more radically than GTK themes, for instance -- switching from a web browser to the Unreal engine, for example, where menus might be presented as shops (I actually prototyped a Quake-based front end at one point).

I've been using an earlier and quite different variation of this idea since 2006 on an extremely large project. The browser side of the presentation is fully automatic now and we don't write any JavaScript for our front ends anymore, unless we're adding new kinds of widgets.

This version of the concept, JSONMetadom, grew out of the Leisure project (which will be updated to use JSONMetadom, in time) and I've use variations of this JavaScript and server code in several of my personal projects.

Oh, and the [Xus](https://github.com/zot/Xus) project is also related to this. It really implements the shared variables.

# Views

Views can also contain other views because JSONMetadom defines a "view" Handlebar plugin.

Views can contain elements with `data-path` attributes that specifying a
*path* to a property in the JSON object, example:

`<input type=text data-path="a.b.c">`

If an element has a non-null data-bind-keypress attribute, any keypresses that are not enter or return will be sent as "key" events to the Javascript model (or server, if connected).

An element is considered to be a button if it has a data-path property and it is either a non-input element, a button element, or a submit element. The behavior on the JSON object depends on its "value" attribute (if there is one):

* no value attribute: when you press the button, JSONMetadom does not change the JSON object but it sends a click event to the model (see Events, below)
* the value is a boolean: it acts as a checkbox and when you press it, JSONMetadom sets the boolean value in the JSON object and sends a "set" event (see Events, below)
* otherwise: when the input element changes (like by focusing out of a field), JSONMetadom sets the JSON path in the object to the value property, parsed as a JSON value (see Events, below)

# Main JSON object

views: {NAMESPACE: {TYPE: HANDLEBARSDEF}, ...}
type: top
content: [DATA, ...]

The main JSON object supplied to JSONMetadom can optionally provide

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

# Using JSONMetadom

On the web side, you need to make sure the files in the js and css directories are available to your HTML file and include these elements (altered to fit your file layout, of course):

\<link rel="stylesheet" href="css/jsonmetadom.css">\</link>
\<script src="js/lib/handlebars-v4.0.5.js">\</script>
\<script src="js/jsonmetadom.js">\</script>

It's also compatible with AMD style so you can use something like require.js:

\<link rel="stylesheet" href="css/metadom.css">\</link>
\<script data-main="js/config" src="js/lib/require-2.1.18.js">\</script>

You can implement the model in local JavaScript or in a server. Metadom currently supports Julia servers.

# Connecting to a server
Put this at the bottom of the body of your web page, with the HOST and PORT of your server in it:

\<script>JSONMetadom.connect({}, "ws://HOST:PORT")\</script>

The Julia server code supports its own version of event handlers and DocPath (see the JavaScript model documentation below)

# Using JSONMetadom with a JavaScript model

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
- `docp.PROP = VALUE` sets the value in the document and cause JSONMetadom to re-render it
- `docPathParts(docp)` returns the "parts" of a DocPath, the JSONMetadom object, the context, and the path array

You can use `batch(con, func)` if you need to change DocPaths outside of an event handler for "event compression". Batch eliminates re-rendering of the same object multiple times.
