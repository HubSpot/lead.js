expect = require 'expect.js'
notebook = require '../app/notebook'

describe 'notebooks', ->
  it 'can be created', ->
    nb = notebook.create_notebook({})
