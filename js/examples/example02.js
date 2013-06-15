// Generated by CoffeeScript 1.6.3
(function() {
  var choc, escodegen, esmorph, esprima, inspect, puts, scrubNotify, source, source_todo, _, _ref;

  _ref = require("util"), puts = _ref.puts, inspect = _ref.inspect;

  esprima = require("esprima");

  escodegen = require("escodegen");

  esmorph = require("esmorph");

  _ = require("underscore");

  choc = require("../src/choc");

  if ((typeof require !== "undefined" && require !== null) && (require.main === module)) {
    source_todo = "function add(a, b) {\n  var c = 3;\n  return a + b;\n}\n\nvar sub = function(a, b) {\n  var c = 3;\n  return a - b;\n}\nwhile (shift <= 200) {\n  // console.log(shift);\n  var x = add(1, shift);\n  shift += 14; // increment\n}";
    source = "var foo = 1;\nvar bar = foo + 2 < 3;\nif(foo + 2 < 3) {\n  console.log('it is');\n}\nconsole.log(foo);";
    source = "var foo = 1;";
    scrubNotify = function(info) {
      return puts(inspect(info));
    };
    puts(choc._hoist(source));
  }

}).call(this);
