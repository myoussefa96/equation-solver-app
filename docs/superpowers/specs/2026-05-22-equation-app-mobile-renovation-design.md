# Equation Solver — Mobile Renovation Design

**Date:** 2026-05-22
**Author:** youssef (with Claude)
**Status:** Approved design, ready for implementation planning
**Predecessor:** Django web app at `/home/repon/workspace/youssef/equationsolver` (kept as data source only).

---

## 1. Goals and non-goals

### Goals

- A cross-platform mobile app that **replaces** the legacy Django equation-solver web app for the primary user: a mechanical engineer with no software-development background. The existing dump contains real engineering work (steam-ejector sizing, Hazen-Williams pipe friction).
- **Eliminate the two pain points of the legacy app:**
  - The comma-separated grammar (`variables`, `finalvars` columns the user had to keep in sync with the equation text by hand).
  - Substring-based formula substitution that misbehaves when one variable name is a substring of another (`M` inside `Me`).
- **Make formula entry as effortless as a scientific calculator.** Visual block builder, no typed grammar in the common case, no commas.
- **Stay clean as the math scope grows.** Start with the operations of the legacy app; allow expansion to a full scientific-calculator surface without ever cluttering the basic UI.
- **Work entirely offline on the device.** No accounts, no backend, no cloud sync.
- **One-time migration of the legacy data** so the user keeps their 15 existing formulas.

### Non-goals

- Multi-user accounts or device sync (explicitly out of scope).
- Symbolic algebra (CAS) — numeric evaluation only.
- A backend service. The legacy Django app is retained only as the source of `latest.dump`; the mobile app does not talk to it.
- Web parity / responsive desktop client. Mobile only (Android + iOS via Flutter).
- Real-time collaboration, sharing, export to other apps (out of scope for v1; possible later).

---

## 2. Persona and language constraints

The user is a **mechanical engineer with no software-development background.** This is a hard design constraint that affects every visible string in the app:

- **Use engineering language:** *formula, variable, value, result, unit, group*.
- **Never use CS terminology in user-facing text:** *identifier, AST, slug, namespace, cycle, token, scope, regex, parse, topological.*
- **Errors must be plain English with a concrete fix**, naming the specific variable or formula at fault. "Cycle detected" is wrong. "These formulas reference each other in a loop — edit one of them to break the loop" is right.
- **Defaults favor the casual case.** Basic math operations visible; scientific operations behind an "Advanced functions" toggle.
- **The mental model is a scientific calculator with saveable, named formulas grouped into folders** — not a programming IDE.

---

## 3. Architecture

Four layers, each independently testable, communicating through narrow interfaces:

```
 ┌──────────────────────────────────────────────────────┐
 │  UI layer (Flutter widgets)                          │
 │  - Folder list / Entry list / Block builder / Solve  │
 │  - Imports OpRegistry to render the palette          │
 └───────────────┬──────────────────────────────────────┘
                 │ commands / state
 ┌───────────────▼──────────────────────────────────────┐
 │  State layer (Riverpod providers)                    │
 │  - FoldersNotifier, EntryNotifier, BuilderNotifier   │
 │  - Owns the working AST; no math knowledge           │
 └───────────────┬──────────────────────────────────────┘
                 │ pure functions
 ┌───────────────▼──────────────────────────────────────┐
 │  Engine layer (pure Dart, no Flutter imports)        │
 │  - OpRegistry  ◄── single source of truth for ops    │
 │  - Tokenizer → Parser → AST                          │
 │  - Evaluator                                         │
 │  - DependencyResolver (topo-sort, cycle detection)   │
 │  - LegacyImporter (parses old equation strings)      │
 └───────────────┬──────────────────────────────────────┘
                 │
 ┌───────────────▼──────────────────────────────────────┐
 │  Storage layer (sqflite)                             │
 │  - Folders, Entries, Equations, Variables tables     │
 │  - Reads/writes serialized AST (JSON)                │
 └──────────────────────────────────────────────────────┘
```

### 3.1 Stack

- **Flutter (Dart)** for the cross-platform mobile UI. Chosen over React Native because Flutter renders identically on iOS and Android and offers stronger primitives (`CustomPainter`, `Draggable`, `AnimatedSwitcher`) for the custom block-builder UI.
- **`sqflite`** for local persistence (SQLite via FFI on iOS/Android).
- **`riverpod`** for state management.
- **No backend, no network calls.** The app ships as a single binary per platform.
- **Pure-Dart math engine** — no FFI, no JS bridge.

### 3.2 Layer rules

- **The engine layer has zero Flutter imports.** It compiles and tests standalone with `dart test`.
- **The UI layer never re-implements engine logic** (no inline math). It calls the engine for evaluation, dependency resolution, and JSON round-trips.
- **Storage layer stores serialized ASTs**, never raw formula strings. The legacy parser exists only to bootstrap the import path.
- **`OpRegistry` is the single source of truth** for operations. The block palette is *generated from it*; the parser registers function names from it; the evaluator dispatches by it. Adding a new operator is a one-line registry entry — UI and parser pick it up automatically. This is the structural mechanism that lets the scientific surface grow without UI churn.

---

## 4. Data model

Five SQLite tables. Identifiers (internal) and display labels (user-facing) are stored separately so the engine can use strict identifiers while the user types whatever they want.

```sql
folders
  id              INTEGER PRIMARY KEY
  name            TEXT NOT NULL
  sort_order      INTEGER NOT NULL DEFAULT 0
  created_at      DATETIME NOT NULL
  updated_at      DATETIME NOT NULL

entries                              -- one "saved item" (≡ legacy Equation_solver row)
  id              INTEGER PRIMARY KEY
  folder_id       INTEGER NOT NULL REFERENCES folders(id) ON DELETE CASCADE
  name            TEXT NOT NULL
  description     TEXT
  sort_order      INTEGER NOT NULL DEFAULT 0
  created_at      DATETIME NOT NULL
  updated_at      DATETIME NOT NULL

equations                            -- one row per chained equation inside an entry
  id              INTEGER PRIMARY KEY
  entry_id        INTEGER NOT NULL REFERENCES entries(id) ON DELETE CASCADE
  output_var      TEXT NOT NULL      -- identifier assigned by this equation
  ast_json        TEXT NOT NULL      -- serialized AST (see §5.1)
  sort_order      INTEGER NOT NULL DEFAULT 0
  UNIQUE(entry_id, output_var)

variable_meta                        -- per-entry metadata on any identifier
  id              INTEGER PRIMARY KEY
  entry_id        INTEGER NOT NULL REFERENCES entries(id) ON DELETE CASCADE
  identifier      TEXT NOT NULL      -- e.g. "y_t_air"
  display_label   TEXT NOT NULL      -- e.g. "y(t) air" (shown in UI)
  unit            TEXT               -- e.g. "kg/hr", "m/s" (free text, optional)
  role            TEXT NOT NULL      -- 'input' | 'intermediate' | 'output'
  is_final        INTEGER NOT NULL DEFAULT 0
  last_value      REAL               -- remember last value the user solved with
  UNIQUE(entry_id, identifier)

solve_history                        -- recent solves, for "rerun" UX (optional, kept v1)
  id              INTEGER PRIMARY KEY
  entry_id        INTEGER NOT NULL REFERENCES entries(id) ON DELETE CASCADE
  inputs_json     TEXT NOT NULL
  outputs_json    TEXT NOT NULL
  solved_at       DATETIME NOT NULL
```

### 4.1 Key decisions

- **AST stored, not text.** No re-parsing per solve, no string-substitution bugs.
- **Each equation owns exactly one output variable.** The DependencyResolver builds the DAG across an entry's equations.
- **`role` and `is_final` are computed at save time** by the resolver and persisted. The Solve form is rendered directly from `variable_meta` filtered by `role = 'input'`.
- **`identifier` is restricted to `[A-Za-z_][A-Za-z0-9_]*`.** `display_label` may be anything. The user types the label; the system derives the identifier silently. The block builder never asks the user to enter or see an identifier in the casual flow.
- **`ON DELETE CASCADE` everywhere** — proper referential integrity, unlike the legacy `folder = IntegerField`.

---

## 5. Math engine

Pure Dart, no Flutter dependency. Lives under `lib/engine/`.

### 5.1 AST

```dart
sealed class AstNode {}
class NumberLit    extends AstNode { final double value; }
class Identifier   extends AstNode { final String name; }      // variable OR constant (PI, E)
class UnaryMinus   extends AstNode { final AstNode operand; }
class BinaryOp     extends AstNode { final String op;          // + - * / ^
                                     final AstNode left, right; }
class FunctionCall extends AstNode { final String name;
                                     final List<AstNode> args; }
```

Serialization: each node `toJson` tags itself with `"type"`. Deep round-trip is structurally lossless and covered by property-based tests.

### 5.2 OpRegistry — single source of truth

```dart
class OpDef {
  final String name;
  final int arity;                          // -1 = variadic
  final OpCategory category;                // basic | trig | trigInverse | hyperbolic
                                            // | rounding | combinatorics | ...
  final double Function(List<double>) impl;
}

abstract final class OpRegistry {
  static const Map<String, double> constants = {'PI': math.pi, 'E': math.e};

  static final Map<String, OpDef> functions = {
    // BASIC (visible by default — matches the legacy app exactly)
    'sqrt':  OpDef('sqrt',  1, OpCategory.basic,    (a) => math.sqrt(a[0])),
    'root':  OpDef('root',  1, OpCategory.basic,    (a) => math.sqrt(a[0])),   // legacy alias
    'abs':   OpDef('abs',   1, OpCategory.basic,    (a) => a[0].abs()),
    'exp':   OpDef('exp',   1, OpCategory.basic,    (a) => math.exp(a[0])),
    'ln':    OpDef('ln',    1, OpCategory.basic,    (a) => math.log(a[0])),
    'log':   OpDef('log',   1, OpCategory.basic,    (a) => math.log(a[0]) / math.ln10),
    'sin':   OpDef('sin',   1, OpCategory.trig,     (a) => math.sin(a[0])),
    'cos':   OpDef('cos',   1, OpCategory.trig,     (a) => math.cos(a[0])),
    'tan':   OpDef('tan',   1, OpCategory.trig,     (a) => math.tan(a[0])),
    'trunc': OpDef('trunc', 1, OpCategory.rounding, (a) => a[0].truncateToDouble()),
    'round': OpDef('round', 1, OpCategory.rounding, (a) => a[0].roundToDouble()),
    'sgn':   OpDef('sgn',   1, OpCategory.basic,    (a) => a[0].sign),
    // SCIENTIFIC (to be added incrementally; palette picks them up automatically)
    // 'asin', 'acos', 'atan', 'sinh', 'cosh', 'tanh',
    // 'min', 'max', 'mod', 'floor', 'ceil', 'pow', 'nroot', 'fact', ...
  };

  static OpDef? lookup(String name) => functions[name];
  static List<OpDef> byCategory(OpCategory c) =>
      functions.values.where((d) => d.category == c).toList();
}
```

Operator precedence (for the importer; the block builder constructs ASTs directly):

| Precedence | Operators | Associativity |
|---|---|---|
| 4 | `^` | Right |
| 3 | unary `-` | n/a |
| 2 | `*` `/` | Left |
| 1 | `+` `-` | Left |

### 5.3 Parser

Tokenizer → Pratt parser. Only ever invoked from:

- **Legacy import** (parsing the equation strings from `latest.dump`).
- An optional **"paste a formula"** power-user shortcut in the builder (not in v1 scope unless trivial).

The block builder constructs the AST directly via UI actions. There is no text grammar in the user's normal flow. Commas are not used anywhere in user input.

### 5.4 DependencyResolver

Per entry:

1. Build a graph: for each equation `OUT = expr`, add edges from every `Identifier` referenced in `expr` to `OUT`. Identifiers that match `OpRegistry.constants` are skipped.
2. Topological sort (Kahn's algorithm).
3. If any node retains in-degree > 0 → cycle exists; return the cycle members for the UI banner.
4. Classify identifiers:
   - referenced but never an LHS → `role = 'input'`
   - LHS and referenced by another equation → `role = 'intermediate'`
   - LHS, never referenced → `role = 'output'` (default `is_final = 1`)
5. Persist the topo order and roles on save.

Note: during builder editing, a user may create a variable via the "Add a variable" sheet before referencing it in any equation. The resolver tolerates `variable_meta` rows that don't appear in any AST yet — they're carried forward but classified as `role = 'input'` provisionally. Save-time validation does not require every declared variable to be used (a "you have unused variables" warning is acceptable but not blocking).

### 5.5 Evaluator

Pure recursive walk over the AST against a `Map<String, double> scope`. For an `Identifier`:

1. If in `scope` → return its value.
2. Else if in `OpRegistry.constants` → return the constant.
3. Else → throw `UnknownIdentifier` (guarded against by save-time validation; reaching this at solve time is a bug).

**Solve algorithm:**

1. Render a form with all `role = 'input'` variables (label, unit hint, prefilled with `last_value` if present).
2. User submits values.
3. Evaluator iterates equations in topo-sort order, growing `scope` as it goes.
4. Result map is split into "final" outputs (prominent) and intermediates (collapsible).
5. `variable_meta.last_value` is updated for inputs.

### 5.6 Error model

```dart
sealed class EngineError {}
class ParseError        extends EngineError { final int pos; final String msg; }
class CycleError        extends EngineError { final List<String> cycle; }
class UnknownIdentifier extends EngineError { final String name; }     // save-time only
class EvalError         extends EngineError { final String msg;
                                              final AstNode? location; } // ÷0, log≤0, √<0, NaN
```

All four are translated to the plain-English UI messages in §8.3 — no raw Dart exceptions ever surface to the user.

---

## 6. Block-builder UX

The heart of the renovation. Two ideas drive the design: **inline chip flow (not 2D canvas)** and **progressive disclosure (basic by default → scientific on demand)**.

### 6.1 Layout

A horizontally-scrolling chip flow per equation row. This is how engineers read formulas anyway, and on a phone vertical space is precious.

```
┌─────────────────────────────────────────────────────┐
│  Entry: Steam ejector — nozzle exit Mach          ✕ │
├─────────────────────────────────────────────────────┤
│  Formulas                                           │
│  ┌────────────────────────────────────────────────┐ │
│  │  [Me] = [√] ( ( [2] / ( [K] − [1] ) ) · …  )   │ │   ← typeset preview (read-only)
│  ├────────────────────────────────────────────────┤ │
│  │  Me =  √(  (2/(K-1)) · ((Pm/Pe)^((K-1)/K) - 1) │ │   ← editable chip row
│  │            ▲ caret                             │ │
│  ├────────────────────────────────────────────────┤ │
│  │  + Add formula                                 │ │
│  └────────────────────────────────────────────────┘ │
├─────────────────────────────────────────────────────┤
│  Palette                       [Advanced functions⏻]│   off by default
│  ┌──── Number ──── Variable ──── Op ──── Function ─┐│
│  │  0 1 2 3 4 5 6 7 8 9 . ±                        ││
│  │  ────────────────────────────────────────────── ││
│  │  +    −    ×    ÷    ^    (    )                ││
│  └─────────────────────────────────────────────────┘│
│                                          [ Save ✓ ] │
└─────────────────────────────────────────────────────┘
```

### 6.2 Block kinds (1:1 with AST nodes)

| Chip | Visual | Tap behavior |
|---|---|---|
| Number | `12.5` | Numeric keypad sheet |
| Variable | colored pill `K` (green = you enter; blue = computed) | Variable picker sheet |
| Constant | `π` / `e` | Replace via palette |
| Operator | `+` `−` `×` `÷` `^` | Swap menu (other four operators) |
| Function | `sin( ⎵ )` with nested chips inside parens | Children edit themselves |
| Group | `( ⎵ )` | Inserted manually via the `(` and `)` palette buttons for arithmetic grouping. Function-argument parens are auto-managed by the function chip itself. |

Functions render their own parens. The user never types parens for function arguments; only the explicit `( )` palette buttons create manual grouping.

### 6.3 Context-aware palette

The palette **highlights what's valid at the caret position** — operators glow after operands, operands glow after operators — but nothing is hidden. The user can still insert "incomplete" or "wrong" sequences; the save button will explain what to fix. We don't punish exploration.

### 6.4 Variable creation flow

Tap **Variable** in the palette → bottom sheet:

```
┌─ Pick a variable ──────────────────────────────┐
│  You enter                                     │
│    Pm  Motive pressure        [bar]            │
│    Pe  Exit pressure          [bar]            │
│    K   Specific heat ratio    [—]              │
│                                                │
│  Computed from earlier formulas                │
│    (none yet)                                  │
│                                                │
│  ＋ New variable…                              │
└────────────────────────────────────────────────┘
```

Tapping **＋ New variable** opens:

```
┌─ Add a variable ───────────────────────────────┐
│  Name:   [ y(t) air                         ]  │
│  Unit:   [ kg/m³                            ]  │
│                                                │
│  ◉ I'll type this in   (like Pm, Pe, K…)       │
│  ○ The app calculates it from another formula  │
│                                                │
│                    [ Cancel ]   [ Add ]        │
└────────────────────────────────────────────────┘
```

The identifier is derived from the label invisibly (slugify; collision suffix). No comma-separated lists exist anywhere in user-facing UI.

The radio choice tells the resolver the user's intent for that variable:
- *"I'll type this in"* → row inserted with `role = 'input'`. Will appear in the Solve form.
- *"The app calculates it from another formula"* → row inserted with `role = 'output'` provisionally. The save-time validator requires that some equation actually assigns it before save is allowed; otherwise banner §8.2 #3 fires.

### 6.5 Progressive disclosure of scientific functions

The `Advanced functions ⏻` switch in the palette header is **off by default**:

- **Off:** Function tab shows only `OpCategory.basic` (matches the legacy app's vocabulary).
- **On:** Function tab gains sub-tabs `Basic · Trig · Trig⁻¹ · Hyper · Round · Comb · More`.

The toggle persists per-app (saved to `SharedPreferences`). A power user flips it on once. A casual user never sees it expand.

**Contract:** adding a scientific operation is **one `OpDef` entry in `OpRegistry`**. The palette picks it up into the correct sub-tab automatically; no UI changes; no parser changes. This is the mechanism by which the math vocabulary grows without UX bloat.

### 6.6 Multi-equation handling (chained equations)

Each entry holds an ordered list of equation rows. Each row is `[OutputVar] = [chip flow]`. Toolbar actions: **add row**, drag-reorder, swipe-delete.

The DependencyResolver runs after every edit. A single banner at the top surfaces any problem in priority order (§8.2).

### 6.7 Undo / redo

Every AST mutation is a discrete event on a per-entry stack, capped at 50. Standard `⤺ ⤻` controls in the builder header.

### 6.8 Draft auto-save

Every AST mutation also writes to a draft slot keyed by entry id. If the app is killed mid-edit, reopening the entry offers: "**Pick up where you left off?** [Restore draft] [Discard]".

---

## 7. Migration from the legacy dump

One-time, **explicit, in Settings → "Import from old app"**. The user is never auto-migrated on first launch.

### 7.1 Build-time conversion (developer machine)

`equations_data.sql` → `migration_seed.json`, shipped as a Flutter asset. Generated by `tool/build_seed.dart` from the working tree's `equations_data.sql` (committed alongside the seed).

```json
{
  "folders": [
    {"old_id": 2, "name": "steam ejector sizing"},
    {"old_id": 3, "name": "Pipe Friction Pressure Drop (Hans William)"}
  ],
  "entries": [
    {
      "old_id": 6,
      "old_folder_id": 2,
      "name": "Temperature factor for suction mass of air",
      "description": "m eq=mair/y(t)",
      "equations_raw": "y(t) air=(-4.2857*10^-4)*t+1.01",
      "variables_raw": "t",
      "finalvars_raw": "y(t) air"
    }
    // … 14 more
  ]
}
```

### 7.2 Runtime import (in the app)

1. Load the seed asset.
2. For each entry, split `equations_raw` by top-level commas (legacy convention) and parse each sub-equation with the new Parser.
3. Slugify each label into an identifier. Resolve collisions deterministically (`y(t) air` → `y_t_air`; if taken, `y_t_air_2`, etc.).
4. Build the AST per equation and persist to `equations`.
5. Identifiers referenced in any AST but not assigned by any equation in the entry → declared as `role = 'input'` in `variable_meta`, with `display_label` = the original label string.
6. Flag `variable_meta.is_final = 1` for labels listed in `finalvars_raw`.
7. Re-validate: every imported entry must pass save-time validation and survive an evaluator smoke test (substitute `1.0` for every input → expect a finite real OR a whitelisted `EvalError`).
8. Any entry that fails any step is **skipped** (not silently mangled), and reported in the import summary at the end.

### 7.3 Handling legacy quirks

| Legacy quirk | New behavior |
|---|---|
| `y(t) air` as a "variable" name (spaces, parens) | Display label kept verbatim; internal identifier `y_t_air`. |
| Inconsistent whitespace `"E,C"` vs `"Q, Sv, D"` | Trim every token after splitting. |
| `E` used as Euler's constant in `E^(-0.3154)` | Reserved constant in `OpRegistry`; parsed as the `E` constant node, not as a variable. |
| Free-text descriptions with units (e.g. `"ms in kg/hr, pd in kgf/cm^2"`) | Stored as the entry `description` verbatim. We do not attempt to auto-extract units; the user can later edit each variable's `unit` field. |
| Folder IDs non-contiguous (2, 3) | Old IDs discarded; new folders get fresh sequential IDs. `old_id` retained in the seed file for traceability only. |
| Substring-collision-prone formulas (`Ar=(1/M)*…` while `Me` exists in another entry) | Doesn't happen in the new world — each equation has its own AST with explicit `Identifier` nodes. The same formula imports cleanly. |
| Legacy `root(x)` function (mapped to `sqrt`) | `root` is registered as an alias of `sqrt` in `OpRegistry`. Stays as an alias permanently for backward compatibility. |

### 7.4 Idempotency

Import dialog:

```
┌─ Import from old app ──────────────────────────┐
│  We found 15 formulas in 2 groups.             │
│                                                │
│  ◉ Add them to my library (recommended)        │
│  ○ Replace my library with these               │
│                                                │
│                  [ Cancel ]   [ Import ]       │
└────────────────────────────────────────────────┘
```

"Add" appends; name collisions get ` (imported)` suffix. "Replace" wipes and reseeds. The seed JSON ships with every release, so re-import is always possible.

---

## 8. Errors, empty states, recovery

### 8.1 Empty states

| Where | What the user sees |
|---|---|
| First launch (no folders) | Centered illustration + "**Start by creating a group of formulas, or import from your old app.**" Two buttons: `+ New group` / `Import from old app`. |
| Empty group | "**No formulas in this group yet.**" Button: `+ Add formula`. |
| Empty builder | Top row is `[output] = ⎵`. Caret pre-focused, palette open on **Variable** tab. Helper text: *"Pick the output name first, then build the right side."* |
| No "final result" flagged | Solve button replaced with banner: *"Mark at least one formula's output as a final result before solving."* with a `Show me how` link. |

### 8.2 Builder validation banner

One banner, top of builder, prioritized:

1. **Loop between formulas.** *"`Me` depends on `K`, and `K` depends on `Me`. Edit one of them so the loop is broken."* Offending rows get a red left border.
2. **Empty spot.** *"One spot is still empty. Tap the ⎵ to fill it in."* The empty chip pulses.
3. **Unknown name.** *"You're using `Sv` but it isn't defined yet. Tap it and pick `Add as input`."* Chip outlined.
4. **Reserved name.** *"`E` is a constant (Euler's number). Pick a different name for your variable."*
5. **No final result.** *"No final result chosen. Tap an output pill and turn on 'Final result'."*

Save is disabled while any banner is shown.

### 8.3 Solve-time errors

Always identifies the variable or formula at fault.

| Cause | Message |
|---|---|
| Empty input field | "**Enter a value.**" (inline) |
| Non-numeric input | "**Numbers only — try `1.4` instead of `1,4`.**" (catches European decimal-comma) |
| Division by zero | "**Can't divide by zero.** Check `D` — you entered 0." |
| Logarithm of ≤ 0 | "**Can't take the logarithm of `−2`.** Check `C`." |
| Square root of negative | "**Can't take the square root of `−1.5`.** Check `Pm/Pe`." |
| Result is `∞` or `NaN` | "**Result is undefined** — likely a divide-by-zero or out-of-range value upstream. Check your inputs." |
| Result outside `[1e−20, 1e20]` | Result still shown with info icon: *"Unusually large/small — double-check units."* |

### 8.4 Storage / import failures

| Cause | Behavior |
|---|---|
| Disk full | Modal: "**Can't save — your phone is out of space.**" Builder state preserved in memory. |
| DB corruption on open | Auto-restore from last good snapshot; if that fails, modal offering "Reset and re-import from old app." Never silently wipe. |
| Corrupted seed JSON | "**The seed file looks broken — please update the app.**" Import is blocked, not partial. |
| Single formula fails to parse during import | Skip that one; continue. Summary: *"Imported 14 of 15 formulas. 1 couldn't be read: Velocity in pipe — unexpected character at position 12. You can rebuild it manually."* |

---

## 9. Testing strategy

### 9.1 Engine — pure Dart unit tests

In `engine/test/`. Run with `dart test`. Cover:

- **Tokenizer:** every token kind, edge cases (`1e-3`, `1.`, `.5`, identifier vs constant `E` and `PI`).
- **Parser:** precedence/associativity (`2^3^2 == 2^9`, `-2^2 == -4`, `a-b-c == (a-b)-c`); parse errors with `(pos, msg)` assertions.
- **OpRegistry:** every registered op evaluated against `dart:math` references to ~1e-9.
- **Evaluator:** golden expressions + scope → expected value; full `EvalError` taxonomy.
- **DependencyResolver:** topo-sort correctness; cycle detection returns the right cycle on 2-node, 3-node, and self-loop cases.
- **AST JSON round-trip:** property-based testing — random AST → JSON → AST is structurally equal.

### 9.2 Migration — golden tests on the 15 legacy formulas

`engine/test/migration_golden_test.dart`. For each entry in `migration_seed.json`:

1. Run the import path end-to-end.
2. Validate: every referenced variable exists as an input or as another equation's output.
3. Smoke-evaluate with `1.0` for each input → expect a finite real OR a whitelisted `EvalError`.
4. AST → pretty-printer → text → re-parse → structural equality (parser ↔ printer symmetry).

**CI fails if any of the 15 stops importing or evaluating.** This contract protects against parser/engine regressions.

### 9.3 Storage — sqflite integration tests

`storage/test/` with `sqflite_common_ffi`. Cover:

- Schema migrations on a fresh DB.
- `ON DELETE CASCADE` cascades correctly (folder → entries → equations → variable_meta).
- AST JSON round-trip through SQLite without character mangling.
- Concurrent writes don't corrupt the DB.

### 9.4 UI — widget tests

Flutter widget tests, behavior-focused:

- Insert a Number chip at the caret → AST updates.
- Swipe-delete a chip → AST shrinks, caret repositions.
- Tap an operator → swap menu shows the four other operators.
- Cycle banner appears within one frame of typing a cycle.
- Save disabled iff a banner is shown.
- Undo/redo correctness over 50 random mutations.

### 9.5 End-to-end smoke

`integration_test/`. One canonical flow:

> Fresh install → Import from old app → open "Nozzle exit Mach number" → enter `Pm=10, Pe=1, K=1.4` → tap Solve → expect `Me ≈ 2.1572`.

### 9.6 Out of scope

- Pixel-level snapshot tests for math rendering (brittle).
- Animation timing tests.
- Automated iOS-vs-Android visual diff.

---

## 10. Repository layout (target)

```
equation-solver-app/
  pubspec.yaml
  lib/
    main.dart
    app.dart
    engine/                ← pure Dart, no Flutter imports
      ast.dart
      ast_json.dart
      op_registry.dart
      tokenizer.dart
      parser.dart
      evaluator.dart
      dependency_resolver.dart
      errors.dart
      legacy_importer.dart
    storage/
      database.dart
      folders_repo.dart
      entries_repo.dart
      equations_repo.dart
      variable_meta_repo.dart
    state/
      folders_notifier.dart
      entry_notifier.dart
      builder_notifier.dart
    ui/
      folders/
      entries/
      builder/
      solve/
      settings/
    assets/
      migration_seed.json
  tool/
    build_seed.dart
  test/
    engine/
    storage/
    ui/
    migration_golden_test.dart
  integration_test/
    smoke_test.dart
  docs/
    superpowers/
      specs/
        2026-05-22-equation-app-mobile-renovation-design.md   ← this document
```

The legacy Django app remains untouched at its current path; this repo never imports from it at runtime.

---

## 11. Out of scope for v1 (explicit deferral list)

- iOS / Android share-extension integration (export formula link).
- CSV export of solve results.
- Multi-language UI (English only in v1; copy is structured so adding more later is mechanical).
- Custom themes / dark mode toggle (follow OS setting only).
- "Paste a formula" text-input shortcut in the builder.
- Sympy-style symbolic simplification.
- Cloud sync, accounts, sharing.
- Web / desktop build targets.

---

## 12. Open questions resolved during brainstorming

- **Platform:** Cross-platform via Flutter.
- **Storage:** On-device only, no cloud.
- **Equation model:** Multiple chained equations per entry (kept from legacy).
- **Math scope:** Match legacy at launch; architecturally extensible to scientific without UI bloat.
- **Migration:** Explicit one-time import from `latest.dump`-derived seed JSON.
- **Auth:** None (no app PIN; OS-level lock is sufficient).
- **RN vs Flutter:** Flutter (rendering parity + UI primitives).
