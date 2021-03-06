CodeMirror = require 'codemirror'
require 'codemirror/addon/runmode/runmode'
URI = require 'URIjs'
_ = require 'underscore'
Markdown = require './markdown'
modules = require './modules'
http = require './http'
Documentation = require './documentation'
React = require './react_abuse'
Components = require './components'
Context = require './context'
App = require './app'

Documentation.register_documentation 'introduction', complete: """
# Welcome to lead.js

Press <kbd>Shift</kbd><kbd>Enter</kbd> to execute the CoffeeScript in the console. Try running

<!-- noinline -->
```
browser '*'
```

Look at

<!-- noinline -->
```
docs
```

to see what you can do with Graphite.
"""

ExampleComponent = Components.ExampleComponent

get_fn_documentation = (fn) ->
  Documentation.get_documentation [fn.module_name, fn.name]

fn_help_index = (ctx, fns) ->
  docs = _.map fns, (fn, name) ->
    if fn?
      doc = get_fn_documentation fn
      if doc?
        {name, doc}
  documented_fns = _.sortBy _.filter(docs, _.identity), 'name'
  Documentation.DocumentationIndexComponent entries: documented_fns, ctx: ctx

Documentation.register_documentation 'imported_context_fns', complete: (ctx, doc) -> fn_help_index ctx, ctx.imported_context_fns

modules.export exports, 'builtins', ({doc, fn, cmd, component_fn, component_cmd}) ->
  help_component = (ctx, cmd) ->
    if _.isString cmd
      doc = Documentation.get_documentation cmd
      if doc?
        return Documentation.DocumentationItemComponent {ctx, name: cmd, doc}
      op = ctx.imported_context_fns[cmd]
      if op?
        doc = get_fn_documentation op
        if doc?
          return Documentation.DocumentationItemComponent {ctx, name: cmd, doc}
    else if cmd?._lead_context_name
      name = cmd._lead_context_name
      if cmd._lead_context_fn?
        doc = get_fn_documentation cmd._lead_context_fn
        return Documentation.DocumentationItemComponent {ctx, name, doc}
      else
        fns = _.object _.map cmd, (v, k) -> [k, v._lead_context_fn]
        return fn_help_index ctx, fns

    # TODO shouldn't be pre
    return React.DOM.pre null, "Documentation for #{cmd} not found."

  component_cmd 'help', 'Shows this help', (ctx, cmd) ->
    if arguments.length > 1
      help_component ctx, cmd
    else
      help_component ctx, 'imported_context_fns'

  KeySequenceComponent = React.createClass
    displayName: 'KeySequenceComponent'
    render: -> React.DOM.span {}, _.map @props.keys, (k) -> React.DOM.kbd {}, k

  KeyBindingComponent = React.createClass
    displayName: 'KeyBindingComponent'
    render: ->
      React.DOM.table {}, _.map @props.keys, (command, key) =>
        React.DOM.tr {}, [
          React.DOM.th {}, KeySequenceComponent keys: key.split('-')
          React.DOM.td {}, React.DOM.strong {}, command.name
          React.DOM.td {}, command.doc
        ]

  component_cmd 'keys', 'Shows the key bindings', (ctx) ->
    all_keys = {}
    # TODO some commands are functions instead of names
    build_map = (map) ->
      for key, command of map
        fn = CodeMirror.commands[command]
        unless key == 'fallthrough' or all_keys[key]? or not fn?
          all_keys[key] = name: command, doc: fn.doc
      fallthroughs = map.fallthrough
      if fallthroughs?
        build_map CodeMirror.keyMap[name] for name in fallthroughs
    build_map CodeMirror.keyMap.lead

    KeyBindingComponent keys: all_keys, commands: CodeMirror.commands

  fn 'In', 'Gets previous input', (ctx, n) ->
    Context.value ctx.get_input_value n

  doc 'object',
    'Prints an object as JSON'
    """
    `object` converts an object to a string using `JSON.stringify` if possible and `new String` otherwise.
    The result is displayed using syntax highlighting.

    For example:

    ```
    object a: 1, b: 2, c: 3
    ```
    """

  component_fn 'object', (ctx, o) ->
    try
      s = JSON.stringify(o, null, '  ')
    catch
      s = null
    s ||= new String o
    Components.SourceComponent value: s, language: 'json'

  component_fn 'md', 'Renders Markdown', (ctx, string, opts) ->
    Markdown.MarkdownComponent value: string, opts: opts

  HtmlComponent = React.createClass
    displayName: 'HtmlComponent'
    render: -> React.DOM.div className: 'user-html', dangerouslySetInnerHTML: __html: @props.value

  component_fn 'text', 'Prints text', (ctx, string) ->
    React.DOM.p {}, string

  component_fn 'pre', 'Prints preformatted text', (ctx, string) ->
    React.DOM.pre null, string

  component_fn 'html', 'Adds some HTML', (ctx, string) ->
    HtmlComponent value: string

  ErrorComponent = React.createClass
    displayName: 'ErrorComponent'
    render: ->
      message = @props.message
      if not message?
        message = 'Unknown error'
        # TODO include stack trace?
      else if not _.isString message
        message = message.toString()
        # TODO handle exceptions better
      React.DOM.pre {className: 'error'}, message

  component_fn 'error', 'Shows a preformatted error message', (ctx, message) ->
    ErrorComponent {message}

  component_fn 'example', 'Makes a clickable code example', (ctx, value, opts) ->
    ExampleComponent value: value, run: opts?.run ? true

  component_fn 'source', 'Shows source code with syntax highlighting', (ctx, language, value) ->
    Components.SourceComponent {language, value}

  fn 'options', 'Gets or sets options', (ctx, options) ->
    if options?
      _.extend ctx.current_options, options
    Context.value ctx.current_options

  component_cmd 'permalink', 'Create a link to the code in the input cell above', (ctx, code) ->
    code ?= ctx.previously_run()
    uri = App.raw_cell_url code
    React.DOM.a {href: uri}, uri

  PromiseResolvedComponent = React.createClass
    displayName: 'PromiseResolvedComponent'
    getInitialState: ->
      @props.promise.then (v) =>
        @setState value: v, resolved: true

      value: null
      resolved: false
    render: ->
      if @state.resolved
        React.DOM.div null, @props.constructor @state.value
      else
        null

  PromiseStatusComponent = React.createClass
    displayName: 'PromiseStatusComponent'
    render: ->
      if @state?.duration?
        ms = @state.duration
        duration = if ms >= 1000
          s = (ms / 1000).toFixed 1
          "#{s} s"
        else
          "#{ms} ms"
        if @props.promise.isFulfilled()
          text = "Loaded in #{duration}"
        else
          text = "Failed after #{duration}"
      else
        text = "Loading"
      React.DOM.div {className: 'promise-status'}, text
    getInitialState: ->
      if @props.promise.isPending()
        null
      else
        return duration: 0
    finished: ->
      @setState duration: new Date - @props.start_time
    componentWillMount: ->
      # TODO this should probably happen earlier, in case the promise finishes before componentWillMount
      @props.promise.finally @finished

  component_fn 'promise_status', 'Displays the status of a promise', (ctx, promise, start_time=new Date) ->
    PromiseStatusComponent {promise, start_time}

  ComponentAndError = React.createClass
    displayName: 'ComponentAndError'
    componentWillMount: ->
      @props.promise.fail (e) =>
        @setState error: e
    getInitialState: -> error: null
    render: ->
      if @state.error?
        error = ErrorComponent {message: @state.error}
      React.DOM.div null, @props.children, error

  GridComponent = React.createClass
    displayName: 'GridComponent'
    propTypes:
      cols: React.PropTypes.number.isRequired
    render: ->
      rows = []
      row = null
      cols = @props.cols
      _.each @props.children, (component, i) ->
        if i % cols == 0
          row = []
          rows.push row
        row.push React.DOM.div {style: {flex: 1}}, component
      React.DOM.div null, _.map rows, (row) -> React.DOM.div {style: {display: 'flex'}}, row

  FlowComponent = React.createClass
    displayName: 'FlowComponent'
    render: ->
      React.DOM.div {style: {display: 'flex', flexWrap: 'wrap'}}, @props.children

  fn 'grid', 'Generates a grid with a number of columns', (ctx, cols, fn) ->
    nested_context = Context.create_nested_context ctx, layout: GridComponent, layout_props: {cols}
    Context.add_component ctx, nested_context.component
    Context.apply_to nested_context, fn

  fn 'flow', 'Flows components next to each other', (ctx, fn) ->
    nested_context = Context.create_nested_context ctx, layout: FlowComponent
    Context.add_component ctx, nested_context.component
    Context.apply_to nested_context, fn

  {help_component, ExampleComponent, PromiseStatusComponent, ComponentAndError, PromiseResolvedComponent, ErrorComponent}
