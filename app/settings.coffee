_ = require 'underscore'
$ = require 'jquery'
Bacon = require 'baconjs'
modules = require './modules'
Context = require './context'

init = ->
  modules.export exports, 'settings', ({fn}) ->
    fn 'set', 'Sets a user setting', (ctx, keys..., value) ->
      user_settings.set keys..., value
    fn 'get', 'Gets a setting', (ctx, keys...) ->
      Context.value global_settings.get keys...

create = (overrides=get:->) ->
  data = {}
  change_bus = new Bacon.Bus
  change_bus.plug overrides.changes if overrides.changes?

  get = (d, keys) ->
    return d if keys.length is 0
    return d unless d?
    [key, keys...] = keys
    get d[key], keys

  set = (d, value, keys) ->
    [key, keys...] = keys
    if keys.length is 0
      d[key] = value
    else
      set d[key] ?= {}, value, keys

  with_prefix = (prefix...) ->
    get: (keys...) ->
      k = prefix.concat keys
      override = overrides.get k...
      value = get data, k
      unless override?
        value
      else if _.isObject(override) and _.isObject(value)
        # TODO use lodash?
        $.extend true, {}, value, override
      else
        override

    set: (keys..., value) ->
      k = prefix.concat keys
      set data, value, k
      change_bus.push k
      @
    default: (keys..., value) ->
      @get(keys...) or @set keys..., value

  settings = with_prefix()
  # TODO is this necessary? i just want a normal EventStream that isn't pluggable or pushable
  settings.changes = change_bus.map _.identity
  settings.with_prefix = with_prefix
  settings

user_settings = create()

global_settings = create(user_settings)

_.extend exports, global_settings, {create, user_settings, init}
