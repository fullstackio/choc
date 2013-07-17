# Choc: An Experiment in Learnable Programming
#
# References: 
# 
#
{puts,inspect} = require("util"); pp = (x) -> puts inspect(x, null, 1000)
esprima = require("esprima")
escodegen = require("escodegen")
esmorph = require("esmorph")
estraverse = require('../../lib/estraverse')
_ = require("underscore")
readable = require("./readable")
debug = require("debug")("choc")
deep = require("deep")

# TODOs 
# * return a + b in a function ReturnStatement placement
# * function returns - i think we're going to need to transform every ReturnStatement to hoist its argument into a variable - then give the language for that variable and pause on that line right before you return it
# * function calls on the line
# * return syntax errors for parsing in a digestable way

Choc = 
  VERSION: "0.0.1"
  TRACE_FUNCTION_NAME: "__choc_trace"
  PAUSE_ERROR_NAME: "__choc_pause"
  EXECUTION_FINISHED_ERROR_NAME: "__choc_finished"

# Given string nodeType, returns true if the nodeType is (loosely, not strictly)
# a statement (e.g. unit of interest). Returns false otherwise

PLAIN_STATEMENTS = [
 'BreakStatement', 'ContinueStatement', 'DoWhileStatement',
 'DebuggerStatement', 'EmptyStatement', 'ExpressionStatement',
 'ForStatement', 'ForInStatement',  'LabeledStatement',
 'SwitchStatement', 'ThrowStatement', 'TryStatement',
 'WithStatement',
 'VariableDeclaration'
]

HOIST_STATEMENTS = [
  'ReturnStatement', 'WhileStatement', 'IfStatement',
]

ALL_STATEMENTS = PLAIN_STATEMENTS.concat(HOIST_STATEMENTS)
isStatement      = (nodeType) -> _.contains(ALL_STATEMENTS, nodeType)
isPlainStatement = (nodeType) -> _.contains(PLAIN_STATEMENTS, nodeType)
isHoistStatement = (nodeType) -> _.contains(HOIST_STATEMENTS, nodeType)

# varInit: e.g. { type: 'Literal', value: 1 } 
generateVariableDeclaration = (varInit) ->
  identifier = "__choc_var_" + Math.floor(Math.random() * 1000000) # TODO - real uuid
  { 
   type: 'VariableDeclaration'
   kind: 'var' 
   declarations: [ { 
     type: 'VariableDeclarator',
     id: { type: 'Identifier', name:  identifier },
     init: varInit
     } 
   ]
  }

generateVariableAssignment = (identifier, valueNode) ->
  { 
  type: 'ExpressionStatement'
  expression:
    type: 'AssignmentExpression'
    operator: '='
    left: { type: 'Identifier', name: identifier }
    right: valueNode
  }

generateStatement = (code) -> esprima.parse(code).body[0]

# create the call to the trace function here. It's a lot easier to write
# the string and then call esprima.parse for now. But we might get a
# performance boost if we wrote the raw parse tree here. That said, composing
# 'messagesString' is tricky so it's a lot clearer to just use parse, if it's
# fast enough.
generateTraceTree = (node, opts={}) ->
  nodeType = node.type
  line = node.loc.start.line
  range = node.range

  messagesString = readable.readableNode(node, opts)
  signature = """
  #{Choc.TRACE_FUNCTION_NAME}({ lineNumber: #{line}, range: [ #{range[0]}, #{range[1]} ], type: '#{nodeType}', messages: #{messagesString} });
  """
  console.log(signature)

  return esprima.parse(signature).body[0]

generateAnnotatedSource = (source) ->
  try
    tree = esprima.parse(source, {range: true, loc: true})
    debug(inspect(tree, null, 100))
  catch e
    error = new Error("choc source parsing error")
    error.original = e
    throw error
  # puts inspect tree, null, 20

  candidates = []

  estraverse.traverse tree, {
    enter: (node, parent, element) ->
      if isStatement(node.type) 
        candidates.push({node: node, parent: parent, element: element})
  }

  hoister = 
    'IfStatement': 'test'
    'WhileStatement': 'test' 
    'ReturnStatement': 'argument'

  for candidate in candidates
    node = candidate.node
    parent = candidate.parent
    element = candidate.element 

    parentPathAttribute = element.path[0]
    parentPathIndex     = element.path[1]

    # if several siblings are added to the same node, we need to track how many we've added previously
    parent.__choc_offset = 0 unless parent.hasOwnProperty("__choc_offset")

    nodeType = node.type
    line = node.loc.start.line
    range = node.range
    pos = node.range[1]

    if isStatement(nodeType)
      newPosition = null

      if isHoistStatement(nodeType)
        # pull test expresion out
        originalExpression = node[hoister[nodeType]]

        # generate our new pre-variable
        newCodeTree = generateVariableDeclaration(originalExpression)
        newVariableName = newCodeTree.declarations[0].id.name

        # generate the trace tree before we actually perform the hoisting
        traceTree = generateTraceTree(node, hoistedAttributes: [hoister[nodeType], newVariableName])

        parent[parentPathAttribute].splice(parentPathIndex + parent.__choc_offset, 0, newCodeTree)

        # replace it with the name of our variable
        node[hoister[node.type]] = { type: 'Identifier', name: newVariableName }
        parent.__choc_offset = parent.__choc_offset + 1

        if _.isNumber(parentPathIndex)
          newPosition = parentPathIndex + parent.__choc_offset
          parent[parentPathAttribute].splice(newPosition, 0, traceTree)
          parent.__choc_offset = parent.__choc_offset + 1

        else 
          puts "WARNING: no parent idx"

        # I'm not so sure this is a great idea
        if nodeType == "WhileStatement"
          # re-assign our temporary variable the value it is going to need for the while statement  
          newAssignmentNode = generateVariableAssignment(newVariableName, originalExpression)
          innerBlockContainer = node.body.body # WhileStatement > BlockExpression
          innerBlockContainer.push(newAssignmentNode)
          innerBlockContainer.push(traceTree)

      else if isPlainStatement(nodeType)
        traceTree = generateTraceTree(node)
        if _.isNumber(parentPathIndex)
          newPosition = parentPathIndex + parent.__choc_offset + 1

          parent[parentPathAttribute].splice(newPosition, 0, traceTree)
          parent.__choc_offset = parent.__choc_offset + 1

        else 
          puts "WARNING: no parent idx"


  escodegen.generate(tree, format: { compact: false } )

# TODO - use an LRU memoize if you're planning on doing a lot of editing
generateAnnotatedSourceM = _.memoize(generateAnnotatedSource)

class Tracer
  constructor: (options={}) ->
    @frameCount = 0
    @onMessages = () ->
    @clearTimeline()

  clearTimeline: () ->
    @timeline = {
      steps: []
      stepMap: {}
      maxLines: 0
    }

  trace: (opts) =>
    @frameCount = 0
    (info) =>
      @timeline.steps[@frameCount] = {lineNumber: info.lineNumber}
      @timeline.stepMap[@frameCount] ||= {}
      @timeline.stepMap[@frameCount][info.lineNumber - 1] = info
      @timeline.maxLines = Math.max(@timeline.maxLines, info.lineNumber)
      info.frameNumber = @frameCount # todo revise this language

      @frameCount = @frameCount + 1
      # console.log("count:  #{@frameCount}/#{opts.count} type: #{info.type}")
      if @frameCount >= opts.count
        @onMessages(info.messages)
        error = new Error(Choc.PAUSE_ERROR_NAME)
        error.info = info
        throw error

noop = () -> 

scrub = (source, count, opts) ->
  onFrame     = opts.onFrame     || noop
  beforeEach  = opts.beforeEach  || noop
  afterEach   = opts.afterEach   || noop
  afterAll    = opts.afterAll    || noop
  onTimeline  = opts.onTimeline  || noop
  onMessages  = opts.onMessages  || noop
  onCodeError = opts.onCodeError || noop
  locals      = opts.locals      || {}

  newSource   = generateAnnotatedSourceM(source)
  debug(newSource)

  tracer = new Tracer()
  tracer.onMessages = onMessages
  tracer.onTimeline = onTimeline

  executionTerminated = false
  try
    beforeEach()

    # create a few functions to be used by the eval'd source
    __choc_trace         = tracer.trace(count: count)
    __choc_first_message = (messages) -> if _.isNull(messages[0]?.message) then "TODO" else messages[0].message

    # add our own local vars
    locals.Choc = Choc

    # define any user-given locals as a string for eval'ing
    localsStr = _.map(_.keys(locals), (name) -> "var #{name} = locals.#{name};").join("; ")
  
    # http://perfectionkills.com/global-eval-what-are-the-options/
    eval(localsStr + "\n" + newSource)

    # if you make it here without an exception, execution finished
    executionTerminated = true
    console.log("execution terminated")
  catch e
    # throwing a Choc.PAUSE_ERROR_NAME is how we pause execution (for now)
    # the most obvious consequence of this is that you can't have a catch-all
    # exception handler in the code you wish to trace
    if e.message == Choc.PAUSE_ERROR_NAME
      onFrame(e.info)
    else
      throw e
  finally
    # call afterEach after each frame no matter what happens. E.g. if we are
    # drawing a picture, we want to be able to update the canvas even if we
    # paused execution halfway through
    afterEach()

    # if no exceptions were raised then we've successfully run our whole
    # program. Call back to the client and let them know how many steps we've
    # taken and give them the tracer's timeline
    if executionTerminated
      afterAll({frameCount: tracer.frameCount})
      onTimeline(tracer.timeline)

exports.scrub = scrub
exports.generateAnnotatedSource = generateAnnotatedSource
exports.readable = readable
