base_url = 'http://grodan.biz'

_lead_finished = new Object

default_options = {}

graphite_function_docs = {}
$.getJSON 'functions.fjson', (data) ->
  prefix_length = "graphite.render.functions.".length

  html = $.parseHTML(data.body)[0]
  for tag in html.getElementsByTagName 'dt'
    for a in tag.getElementsByTagName 'a'
      a.remove()
    graphite_function_docs[tag.id[prefix_length..]] = tag.parentNode


CodeMirror.keyMap.lead =
  Tab: (cm) ->
    if cm.somethingSelected()
      cm.indentSelection 'add'
    else
      spaces = Array(cm.getOption("indentUnit") + 1).join(" ")
      cm.replaceSelection(spaces, "end", "+input")
  'Shift-Enter': (cm) ->
    run cm.getValue()
  fallthrough: ['default']

$code = $ '#code'
$output = $ '#output'
#$code.height '100px'

editor = CodeMirror $code.get(0),
  mode: 'coffeescript'
  keyMap: 'lead'
  tabSize: 2
  autofocus: true
  viewportMargin: Infinity

$output.css 'padding-bottom': $code.height() + 'px'
editor.on 'viewportChange', ->
  $output.css 'padding-bottom': $code.height() + 'px'

scroll_to_result = ->
  setTimeout ->
    $('html, body').scrollTop $(document).height()
  , 10

create_ns = (context) ->
  current_options = {}

  args_to_params = (args) ->
    is_target = (x) ->
      $.type(x) == 'string' or lead.is_lead_node x

    if args.legnth == 0
      # you're doing it wrong
      {}
    if args.length == 1
      arg = args[0]
      if arg.targets
        targets = arg.targets
        if arg.options
          options = arg.options
        else
          options = arg
          delete options.targets
      else
        targets = args[0]
        options = {}
    else
      last = args[args.length - 1]

      if is_target last
        targets = args
        options = {}
      else
        [targets..., options] = args

    targets = [targets] unless $.isArray targets

    params = $.extend {}, default_options, current_options, options
    params.target = (lead.to_target_string(target) for target in targets)
    params

  cmd = (doc, wrapped) ->
    wrapped._lead_cli_fn = wrapped
    wrapped._lead_doc = doc
    wrapped

  fn = (doc, wrapped) ->
    wrapped._lead_cli_fn = ->
      cli.pre 'Did you forget to call a function?'
    wrapped._lead_doc = doc
    wrapped

  output_object = (o) ->
    $pre = $ '<pre>'
    CodeMirror.runMode JSON.stringify(o, null, '  '), {name: 'javascript', json: true}, $pre.get(0)
    context.$result.append $pre
    context.success()
    _lead_finished

  json = (url) ->
    $.ajax
      url: url
      dataType: 'json'
      success: (response) ->
        output_object response
    _lead_finished

  cli =
    help:
      cmd 'Shows this help', ->
        commands = ("  #{cmd}:\n    #{cli[cmd]._lead_doc}" for cmd in cli_commands).join('\n\n')
        cli.pre "Check out these awesome built-in functions:\n\n#{commands}"

    object:
      fn 'Prints an object as JSON', output_object

    pre:
      fn 'Prints a preformatted string', (string) ->
        $pre = $ '<pre class="cm-string">'
        $pre.text string
        context.$result.append $pre
        context.success()

    html:
      fn 'Adds some HTML', (html) ->
        context.$result.append html
        context.success()

    example:
      fn 'Makes a clickable code example', (string, opts) ->
        $pre = $ '<pre class="example">'
        CodeMirror.runMode string, 'coffeescript', $pre.get(0)
        $pre.on 'click', ->
          if opts?.run ? true
            run string
          else
            set_code string
        context.$result.append $pre
        context.success()

    intro:
      cmd 'Shows the intro message', ->
        cli.pre "Welcome to lead.js!\n\nPress Shift+Enter to execute the CoffeeScript in the console. Try running"
        cli.example "find '*'"
        cli.pre 'Look at'
        cli.example 'lead.functions'
        cli.pre 'to see what you can do with Graphite.'

    docs:
      cmd 'Shows the documentation for a graphite function', (fn) ->
        if fn?
          fn = fn._lead[1]._lead_ if fn._lead
          dl = graphite_function_docs[fn]
          if dl?
            pres = dl.getElementsByTagName 'pre'
            examples = []
            for pre in pres
              for line in pre.innerText.split '\n'
                if line.indexOf('&target=') == 0
                  examples.push line[8..]
            context.$result.append dl.cloneNode true
            for example in examples
              cli.example "q(#{JSON.stringify example})", run: false
          else
            cli.pre 'Documentation not found'
          context.success()
        else
          names = (name for name of graphite_function_docs)
          names.sort()
          for name in names
            sig = $(graphite_function_docs[name].getElementsByTagName('dt')[0]).text().trim()
            cli.example "docs #{JSON.stringify name}  # #{sig}"
          context.success()

    clear:
      cmd 'Clears the screen', ->
        $output.empty()
        context.success()

    options:
      fn 'Gets or sets options', (options) ->
        if options?
          $.extend current_options, options
        current_options


    defaults:
      cmd 'Gets or sets default options', (options) ->
        if options?
          $.extend default_options, options
        cli.object default_options

    url:
      fn 'Generates a URL for a Graphite image', (args...) ->
        params = args_to_params args
        query_string = $.param params, true
        url = "#{base_url}/render?#{query_string}"
        $a = $ "<a href='#{url}' target='blank'/>"
        $a.text url
        $pre = $ '<pre>'
        $pre.append $a
        context.$result.append($pre)
        context.success()

    img:
      fn 'Renders a Graphite graph image', (args...) ->
        params = args_to_params args
        query_string = $.param params, true
        $img = $ "<img src='#{base_url}/render?#{query_string}'/>"
        $img.on 'load', -> context.success()
        context.$result.append($img)
        _lead_finished

    data:
      fn 'Fetches Graphite graph data', (args...) ->
        params = args_to_params args
        params.format = 'json'
        query_string = $.param params, true
        json "#{base_url}/render?#{query_string}"

    find:
      fn 'Finds named Graphite metrics using a wildcard query', (query) ->
        url = "#{base_url}/metrics/find?query=#{encodeURIComponent query}&format=completer"
        $.ajax
          url: url
          dataType: 'json'
          success: (response) ->
            $ul = $ '<ul class="find-results"/>'
            for node in response.metrics
              $li = $ '<li class="cm-string"/>'
              text = node.path
              text += '*' if node.is_leaf == '0'
              do (text) ->
                $li.on 'click', ->
                  if node.is_leaf == '0'
                    run "find #{JSON.stringify text}"
                  else
                    run "q(#{JSON.stringify text})"
              $li.text text
              $ul.append $li
            context.$result.append $ul
            context.success()
        _lead_finished

    q: do ->
      result = (targets...) ->
        _lead: ['q', _lead_to_string: -> targets.join ',']
      result._lead_doc = 'Escapes a Graphite metric query'
      result

  cli_commands = (k for k of cli)
  cli_commands.sort()

  cli

set_code = (code) ->
  editor.setValue code
  editor.focus()
  editor.setCursor(line: editor.lineCount() - 1)


run = (string) ->
  $entry = $ '<div class="entry"/>'
  $input = $ '<pre class="input">'
  $input.on 'click', ->
    set_code string

  $result = $ '<div class="result">'

  CodeMirror.runMode string, 'coffeescript', $input.get(0)

  $entry.append $input
  $entry.append $result
  context =
    $result: $result
    success: ->
      scroll_to_result()
      _lead_finished
    failure: ->
      scroll_to_result()
      _lead_finished

  ns = create_ns context
  functions = {}

  lead.define_functions functions, lead.functions
  try
    `with (ns) { with (functions) {`
    result = eval "//@ sourceURL=console-coffeescript.js\n" +  CoffeeScript.compile(string, bare: true)
    unless result == _lead_finished
      if result?._lead_cli_fn
        result._lead_cli_fn()
      else if result?._lead
        lead_string = lead.to_string result
        if $.type(result) == 'function'
          ns.pre "#{lead_string} is a Graphite function"
          ns.docs result
        else
          ns.pre "What do you want to do with #{lead_string}?"
          safe_string = JSON.stringify lead_string
          for f in ['data', 'img', 'url']
            ns.example "#{f} #{safe_string}"
      else
        ns.object result
    `}}`
  catch e
    ns.pre printStackTrace({e}).join('\n')

  $output.append $entry

run 'intro'
