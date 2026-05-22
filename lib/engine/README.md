# Engine layer

Pure Dart math engine. **No Flutter imports.** Enforced by
`test/engine/purity_test.dart`.

## Components

- `ast.dart` — sealed `AstNode` hierarchy: `NumberLit`, `Identifier`,
  `UnaryMinus`, `BinaryOp`, `FunctionCall`.
- `ast_json.dart` — `astToJson` / `astFromJson` (lossless) + `prettyPrint`
  (parser-symmetric formatter used for round-trip tests).
- `op_registry.dart` — **the single source of truth for operations**.
  Adding an operation = one entry in `OpRegistry.functions`. Tokenizer,
  parser, evaluator, and UI palette all dispatch via this registry.
- `tokenizer.dart` — produces a flat `List<Token>`.
- `parser.dart` — Pratt parser; precedence: `^` > unary `-` > `* /` > `+ -`,
  right-assoc on `^`. Only used for legacy import + future power-user paste.
- `errors.dart` — `EngineError` sealed hierarchy. Every error has a plain-
  English `userMessage` (never expose `toString()` to users).
- `evaluator.dart` — recursive walk against a `scope` map, with explicit
  domain checks (÷0, log≤0, √<0).
- `dependency_resolver.dart` — Kahn's algorithm topo-sort + cycle detection;
  classifies every identifier as input / intermediate / output.
- `slugify.dart` — `label → identifier` with collision-suffix allocator.
- `legacy_importer.dart` — JSON seed → `ParsedFolder`/`ParsedEntry` list.
- `parsed_entry.dart` — in-memory models the importer emits.

## Contract for adding a new operation

```dart
// In op_registry.dart
'asin': OpDef('asin', 1, OpCategory.trigInverse, (a) => math.asin(a[0])),
```

That's it. The UI palette picks it up in the right sub-tab via
`OpRegistry.byCategory()`. The parser accepts it as a function call. The
evaluator dispatches via `OpRegistry.lookup(name)`. **Do not** add ad-hoc
branches in evaluator/parser for specific functions — keep all knowledge
in the registry.

## Testing

```bash
dart test test/engine/                              # full engine suite
dart test test/engine/migration_golden_test.dart    # the 15 legacy formulas
dart test test/engine/purity_test.dart              # purity guard
```

If you change anything in this directory, the golden test MUST still pass.
That contract protects the user's existing formulas from regressions.
