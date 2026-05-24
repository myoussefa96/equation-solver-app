# UI Rebuild — Design Spec

**Date:** 2026-05-24
**Status:** approved (brainstorming complete)
**Supersedes (UI parts only):** `2026-05-22-equation-app-mobile-renovation-design.md` §6, §8

The engine (Plan 1), storage (Plan 2), and import (in `lib/main.dart`) layers from the original design are kept. This spec replaces only the UI layer.

---

## 1. Goal

Rebuild `lib/ui/` from scratch to honor the chip-flow editor promised in the original spec §6. The currently-shipped UI (`fix/ux-iteration-1`) is a calculator-style text accumulator masquerading as a chip editor; it is being thrown out. Full §6 scope — no features deferred.

The primary user is a mechanical engineer with no software-development background. UI copy uses engineering terms: **formula, variable, value, result, unit, group**. Never: identifier, AST, slug, token, parse.

## 2. Scope

In scope:
- Full §6 chip-flow editor, container-chip variant
- Full §6.4 variable creation flow (name + unit + role radio)
- Full §6.5 progressive disclosure (Advanced-functions toggle + sub-tabs)
- §6.6 multi-formula rows with drag-reorder and swipe-delete
- §6.7 undo/redo (50-step per-entry)
- §6.8 draft auto-save with restore banner
- §8.2 priority-ordered error banner
- §8.3 per-variable solve-time error highlighting
- Solve page formula preview + result copy-to-clipboard
- Entry list formula preview
- Settings: advanced-functions master toggle, reset-all-data, diagnostics copy

Out of scope (explicit):
- Bulk variable management screen
- Unit parsing or unit-checking
- Theming/dark mode toggle
- Multi-language UI

## 3. Branch and file layout

Branch: `feat/ui-rebuild` cut from `main`. The existing `fix/ux-iteration-1` stays in place as a historical record.

Wipe everything under `lib/ui/` except `widgets/empty_state.dart` and `widgets/text_field_dialog.dart`. Keep `lib/engine/`, `lib/storage/`, `lib/state/`, `lib/main.dart`, `assets/`, `pubspec.yaml`.

New layout:

```
lib/ui/
  app.dart                          (theme + root)
  folder_list_page.dart             (rebuilt minimal)
  entry_list_page.dart              (rebuilt minimal + formula preview)
  settings_page.dart                (extended: advanced toggle, reset, diagnostics)
  solve_page.dart                   (rebuilt minimal + formula preview + per-var highlight)
  editor/
    entry_editor_page.dart          (host: header, rows, palette, banner, save)
    chip_node.dart                  (sealed ChipNode union + Caret + flatten + chipsFromAst)
    chip_history.dart               (undo/redo stack)
    chip_renderer.dart              (widget walking ChipNode list)
    row_state.dart                  (per-row: chip tree, caret, errors, draft variable metadata)
    drafts.dart                     (SharedPreferences-backed draft slot)
  palette/
    palette.dart                    (host: tab bar + content + header)
    numbers_tab.dart
    variables_tab.dart
    operators_tab.dart
    functions_tab.dart
    number_sheet.dart
    variable_sheet.dart             (insert / swap / output modes)
    function_picker_sheet.dart
  widgets/
    chip_widget.dart                (one ChipNode → tappable widget)
    caret_indicator.dart            (blinking caret between chips)
    empty_state.dart                (kept)
    text_field_dialog.dart          (kept)
```

## 4. Chip data model

### 4.1 `ChipNode` sealed union

```dart
sealed class ChipNode { const ChipNode(); }

class NumberChip      extends ChipNode { final String text; }                           // "12", "12.5", "1.4e-3"
class VarChip         extends ChipNode { final String name; }                           // identifier
class ConstChip       extends ChipNode { final String name; }                           // "PI", "E"
class OpChip          extends ChipNode { final String op; }                             // "+" "-" "*" "/" "^"
class UnaryMinusChip  extends ChipNode { final ChipNode operand; }
class GroupChip       extends ChipNode { final List<ChipNode> children; }               // explicit ()
class FunctionChip    extends ChipNode { final String name; final List<List<ChipNode>> args; }
```

`NumberChip.text` is a **string** so mid-edit states like `"1.4e"` don't fail. `FunctionChip.args` is a list-of-lists for multi-arg functions (`root(x, n)`).

Binary operators live as flat `OpChip` siblings in the parent list. Precedence is the engine parser's job at save time. No `BinaryOpChip`.

### 4.2 Caret

```dart
class Caret {
  final List<ChipNode> parent;   // which list the caret is in
  final int index;               // 0..parent.length inclusive
}
```

Exactly one caret in the active row. Each row remembers its caret across active-row switches.

### 4.3 Insertion rules

When the user taps a palette button:

- **Number / var / const / op** → inserted as one chip at `parent[index]`, caret advances to `index+1`.
- **Function from palette** → inserts `FunctionChip(name, [[]])` (one empty arg slot), caret jumps into `args[0]` at index 0.
- **`(` from palette** → inserts `GroupChip([])`, caret jumps inside.
- **`)` from palette** → moves caret out of current group/function arg to the parent level, just past the container. No chip inserted.

### 4.4 Flatten to string (chip → engine)

`flatten(List<ChipNode>) -> String` produces a parser-ready string. The only chip→engine bridge; called at save time.

```
NumberChip("1.4e-3")               → "1.4e-3"
VarChip("Pm")                      → "Pm"
ConstChip("PI")                    → "PI"
OpChip("+")                        → " + "
UnaryMinusChip(operand)            → "-" + flatten([operand])
GroupChip(children)                → "(" + flatten(children) + ")"
FunctionChip("sqrt", [[1, +, x]])  → "sqrt(" + flatten([1,+,x]) + ")"
FunctionChip("root", [[x], [3]])   → "root(" + flatten([x]) + ", " + flatten([3]) + ")"
```

Save flow: `Parser(flatten(row.chips)).parseExpression()` → existing AST pipeline.

### 4.5 Round-trip from AST (engine → chip, for loading)

`chipsFromAst(AstNode)` for loading existing formulas:

```
NumberLit(v)       → NumberChip(v.toString())
Identifier(name)   → ConstChip(name) if OpRegistry.constants.containsKey(name) else VarChip(name)
UnaryMinus(x)      → UnaryMinusChip(chipsFromAst(x))
BinaryOp(L, op, R) → [chipsFromAst(L), OpChip(op), chipsFromAst(R)]   // flat into parent list
FunctionCall(n, a) → FunctionChip(n, a.map(chipsFromAst).map(wrap).toList())
```

`wrap(node)` returns `[node]` for atoms and the full child sequence for binary ops. The constant-vs-var dispatch checks `OpRegistry.constants` specifically — *not* `isReservedIdentifier`, which would also match function names and is wrong here.

Round-trip `flatten(chipsFromAst(parse(s)))` is **not byte-identical to `s`** but re-parses to the same AST. Tested via a golden test on the 15 legacy formulas.

### 4.6 What this DOESN'T track

- No precedence-aware paren elision when loading. If the source AST has explicit groups, the chip tree shows them.
- No syntactic validity check during editing. The user can have `[+] [+]` mid-edit. Save-time parse catches it.

## 5. Editor screen

### 5.1 Layout

```
┌─────────────────────────────────────────────────────────┐
│  ←   Steam ejector — nozzle exit Mach          ⤺ ⤻ ✓   │  AppBar
├─────────────────────────────────────────────────────────┤
│  ⓘ  banner (only when there is an error)               │
├─────────────────────────────────────────────────────────┤
│  Formula 1                                        ⋮     │
│  ┌───────────────────────────────────────────────────┐  │
│  │  [Me] = √( (2/(K-1)) · ((Pm/Pe)^((K-1)/K) - 1) ) │  │  read-only preview
│  ├───────────────────────────────────────────────────┤  │
│  │  [Me] = [√[ ([2]/([K]−[1])) · …  ]] ▌           │  │  editable chip strip
│  └───────────────────────────────────────────────────┘  │
│                                                         │
│  Formula 2 (inactive — preview hidden)            ⋮     │
│                                                         │
│  ＋ Add formula                                         │
├─────────────────────────────────────────────────────────┤
│  Editing: Me           ⌫    Advanced functions ⏻       │
│  [123] [Vars] [+−×÷] [fn]                              │
│  ┌─────────────────────────────────────────────────┐    │
│  │  context-aware keys                             │    │
│  └─────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────┘
```

- AppBar: back, inline-editable entry name, undo, redo, save.
- Save icon `✓` disabled while parse/resolve errors exist.
- Active row: emphasized border, preview row visible. Inactive rows: editable strip only.
- Per-row `⋮` menu: Reorder, Delete.
- Swipe-left on a row deletes with a snackbar UNDO (4s window).
- Output chip `[Me]` is a `VarChip` rendered at row level — same widget as expression vars.
- `=` is a static label, not a chip.
- Palette pinned to bottom, 280-300px tall. Form area scrolls.

### 5.2 Per-chip tap behavior

| Chip type | Tap | Long press |
|---|---|---|
| NumberChip | Open Number sheet (prefilled, OK/Cancel) | Delete chip (snackbar undo) |
| VarChip | Open Variable sheet in **swap mode** | Delete chip |
| ConstChip (π, e) | Popover: `π · e · Number…` (third converts via number sheet) | Delete chip |
| OpChip | Popover with other 4 operators; swap | Delete chip |
| UnaryMinusChip | Toggle (remove the minus, promote operand) | Same as tap |
| GroupChip | Tap inside = caret inside; tap parens = caret just inside | Delete group, leave children in parent list |
| FunctionChip name | Open Function picker in swap mode | Delete function, leave `args[0]` in parent list |
| Gap between chips | Position caret | n/a |
| Far-right gap | Caret to end of row | n/a |

### 5.3 Backspace

`⌫` button in palette header. Removes the chip immediately before the caret. At start of `FunctionChip.args[0]`, dissolves the function. At top-level index 0, no-op (no error sound).

### 5.4 Save flow

1. Validate entry name non-empty → otherwise inline error.
2. For each row: `flatten(row.chips)` → `Parser.parseExpression()`. Catch `FormatException` → per-row inline error + red border.
3. Build `List<EqEntry>`, run `DependencyResolver.resolve(...)`. Catch `EngineError` → banner + (if `UnknownIdentifierError` / `DuplicateOutputError`) highlight offending row.
4. Persist via existing `EquationsRepo` + `VariableMetaRepo` (transactional `replaceAll`).
5. Pop back to entry list.

### 5.5 Inline entry-name edit

Tap the title text in the AppBar → it becomes a `TextField` in-place; tap outside or press done → commits the rename.

## 6. Variable creation flow

### 6.1 Three sheet modes

| Trigger | Mode | Body |
|---|---|---|
| Palette Vars tab → tap a chip | **Insert** | Pick var for caret position |
| Tap existing `VarChip` in expression | **Swap** | Same list as Insert; current selection highlighted |
| Tap row's output chip | **Output** | Only vars eligible as output (no value source); `+ New computed variable` |

### 6.2 Insert / Swap layout

```
┌─ Pick a variable ──────────────────────────────────┐
│  You enter                                         │
│    Pm   Motive pressure              [bar]         │   green chip
│    Pe   Exit pressure                [bar]         │
│    K    Specific heat ratio          [—]           │
│  Computed from earlier formulas                    │
│    Me   Nozzle exit Mach             [—]           │   blue chip
│  Constants                                         │
│    π    3.14159…                                   │
│    e    2.71828…                                   │
│  ＋ New variable…                                  │
│                              [ Cancel ]            │
└────────────────────────────────────────────────────┘
```

`DraggableScrollableSheet` starting at 60% height. Cancel closes; tapping a row inserts/swaps and closes.

### 6.3 Output mode layout

```
┌─ What does this formula compute? ──────────────────┐
│  Pick a variable already used in this entry        │
│    Me   (used in formulas 2, 3)                    │
│  ＋ New computed variable…                         │
│                              [ Cancel ]            │
└────────────────────────────────────────────────────┘
```

Shows vars that appear in some expression but have no formula producing them. `+ New` opens create form with role locked to "app calculates it".

### 6.4 Create form

```
┌─ Add a variable ───────────────────────────────────┐
│  Name        [ y(t) air                       ]    │
│  Unit (opt)  [ kg/m³                          ]    │
│  Role                                              │
│  ◉ I'll type this in    (like Pm, Pe, K…)          │
│  ○ The app calculates it from another formula      │
│                              [ Cancel ] [ Add ]    │
└────────────────────────────────────────────────────┘
```

- **Name** validation: non-empty, trimmed; spaces / parens / digits allowed. Identifier derived via `slugify` + `SlugAllocator` collision suffix.
- **Unit** is free text, stored on `VariableMetaRow.unit`.
- **Role** is required; no default. Locked to "app calculates it" in Output mode.

### 6.5 On `Add`

1. `slugify(name)` → candidate identifier.
2. **Collision check (interactive):** if the candidate already exists in this entry's variable set, reject with the inline error in §6.7. Do NOT auto-suffix — that behavior is for the migration-time `SlugAllocator` only. In interactive creation we want the user to consciously pick a distinct name.
3. `VarChip(identifier)` inserted at caret / replaces tapped chip / set as row output.
4. Draft `{identifier, displayLabel, unit, role}` held in row state — **not** persisted until entry is saved.

### 6.6 Color coding

- Green container (`tertiaryContainer`) → role = input
- Blue container (`secondaryContainer`) → role = output
- Grey container → constant
- Surface → number / operator / function name

### 6.7 Edge cases

| Case | Behavior |
|---|---|
| Name collides with reserved identifier (`PI`, `E`, function names) | Block at submit with inline error "This name is reserved — try `pi_val` instead." |
| Name collides with existing var in this entry | Block at submit with inline error "Already used by another variable — pick a different name." |
| Output mode, no eligible existing vars | Show "(no orphan variables)"; user must use `+ New computed variable` |
| Insert mode, brand new entry | "You enter" shows "(none yet — create one)"; "Computed" shows "(none yet — earlier formulas will appear here)" |

## 7. Palette

Four tabs: `123` · `Vars` · `±×÷` · `fn`. Fixed content height 260px.

### 7.1 `123` tab — Numbers

4×4 grid:

```
7  8  9  .
4  5  6  (
1  2  3  )
0  ±  EE  ⌫
```

- Digits and `.` append into the current open `NumberChip` if the caret is immediately after one; otherwise start a new `NumberChip`.
- `±` toggles a leading `UnaryMinusChip`.
- `EE` continues the current number with `e`, accepts one more `±`, then digits — all into the same `NumberChip.text`.
- `(` `)` always available.
- `⌫` mirrors the header backspace.

### 7.2 `Vars` tab — Variables

`Wrap` of variable chips (already-used in this entry, color-coded by role) plus a leading `+` button. Tapping any chip opens the variable sheet in Insert mode. `+` skips to the create form. Two optional filter chips: `Inputs only` / `Computed only` (off by default; shown only with 10+ vars).

### 7.3 `±×÷` tab — Operators

Buttons: `+ − × ÷ ^` / `( )`. Context-aware highlight: the soft-glow button (theme `primaryContainer`) is the one immediately valid at the caret. Rules:

- After number / var / const / `)`: operators glow.
- At row start / after operator / after `(` / after function open-paren: operands and unary `−` glow.

Nothing is ever disabled.

### 7.4 `fn` tab — Functions

Header: `Advanced functions ⏻` toggle + search field. Toggle persists in `SharedPreferences` key `palette.advancedFunctions`.

- **Off (default):** single grid of `OpCategory.basic` — `sqrt sin cos tan ln log exp abs`.
- **On:** five sub-tabs `Basic · Trig⁻¹ · Hyper · Round · More`, sourced directly from `OpCategory` enum.

Adding a function = one `OpDef` entry in `OpRegistry`. Zero UI code change.

Search filters live, matching prefix on function name and aliases.

Tapping a function: inserts `FunctionChip(name, [[]])` (or `[[], []]` for multi-arg) and jumps caret into `args[0]` at index 0.

### 7.5 Palette header

```
Editing: Me                          ⌫    Advanced fns ⏻
```

`Editing: Me` shows the active row's output identifier (or "row 2" if not yet set). Toggle visible only when the `fn` tab is active.

## 8. Multi-row, output chip, drag/swipe

- Rows in a `ReorderableListView`. Drag handle on the right of each row, visible always.
- Swipe-left → `Dismissible` triggers; snackbar `Formula deleted — UNDO` (4s).
- `+ Add formula` button at the bottom; new row becomes active, palette resets to `123`.
- Active row determined by last interaction (output chip, expression area, 3-dot menu).
- Output chip when empty: dashed-border pill `( tap to pick )`. When set: blue (computed) `VarChip` with display label.
- Dependency resolution runs after every chip change, debounced 150ms. `CycleError` / `DuplicateOutputError` → banner + red row borders.

## 9. Undo / redo + drafts

### 9.1 Undo / redo

`UndoStack` lives on the editor page state, scoped to the session. Each entry: `{snapshot: List<RowSnapshot>, caret: Caret}`. Cap 50; oldest dropped silently.

One push per logical operation:

- Insert from palette → 1 push
- Open number sheet, edit, commit → 1 push
- Drag-reorder a row → 1 push
- Delete a row (after snackbar timeout) → 1 push; undo restores at original index
- Output chip change → 1 push

Header buttons `⤺ ⤻` enabled only when their direction has items.

### 9.2 Draft auto-save

Draft = `{entryId: int | null, name: String, descr: String, rows: List<RowSnapshot>}` JSON.

`SharedPreferences` key: `editor.draft.<entryId-or-new-<folderId>>`. Written debounced 500ms after last edit. Cleared on successful save or explicit Discard.

On opening the editor with a matching draft, show a top-of-screen banner:

```
You have unsaved changes from [time-ago].   [Restore]   [Discard]
```

App-crash recovery uses the same draft; orphaned drafts are offered Restore/Discard on first reopen of that entry (or new-formula path for that folder).

## 10. Other screens

### 10.1 Folder list

- Empty state gets a second button: `Import from old app` (calls `runBundledImport`). §8.1 affordance.
- Long-press a folder → multi-select mode for bulk delete.
- Inline-editable title for rename (tap and edit, no dialog).

### 10.2 Entry list

- Subtitle shows up to two formula previews (output = `flatten` truncated to ~30 chars).
- Trailing menu: `Edit` · `Solve` · `Duplicate` · `Delete`.
- Tap row → Solve (unchanged).

### 10.3 Solve page

- Per-input error highlighting on `EvalError`: offending variable's chip in result list gets red border + tooltip with `userMessage`. Engine identifies cause via eval trace.
- Formula preview at top: read-only typeset rendering via chip-renderer in disabled mode.
- Per-result copy-to-clipboard icon.
- Reset-inputs-to-last-saved button under the form.
- European decimal-comma support kept; helper text once per field.

### 10.4 Settings

Sections:

1. **Data** — Import (add); Import (replace); **Reset all data** (typed "ERASE" confirmation gate).
2. **Editor** — Advanced-functions master toggle (canonical location; also reachable from palette).
3. **About** — version; legacy app link; `Copy diagnostics` (DB row counts + version).

## 11. Errors, banners, copy

### 11.1 Banner priority (§8.2)

Single banner at top; one message in priority order. As soon as priority N is fixed, priority N+1 (if any) appears.

| Priority | Cause | Copy |
|---|---|---|
| 1 | Empty entry name | "Give this formula set a name." |
| 2 | `ParseError` on any row | "Formula {label}: {parser.userMessage}" |
| 3 | `CycleError` | "These formulas reference each other in a loop: {a → b → c → a}. Edit one of them to break the loop." |
| 4 | `DuplicateOutputError` | "Two formulas compute the same variable {v}. Pick a different name for one of them." |
| 5 | `UnknownIdentifierError` | "Variable {v} is used in formula {label} but never given a value. Add it to your inputs, or compute it in another formula." |
| 6 | Var marked output but never assigned | "Variable {v} is marked as computed but no formula calculates it. Either add a formula, or change it to 'I'll type this in'." |
| 7 | No formulas at all | "Add at least one formula." |

All messages name the specific variable/formula. No CS jargon.

### 11.2 Solve-time errors (§8.3)

`EngineError.userMessage` in a `Card` below Solve. Offending variable's input gets red border. If no specific variable can be identified, the formula row is highlighted.

### 11.3 Storage / import failures (§8.4)

`AlertDialog` with message and `Report` button (uses diagnostics-copy mechanism).

## 12. Testing

| Layer | What's tested | How |
|---|---|---|
| `chip_node.dart` | Flatten round-trip on 15 legacy formulas; insertion / deletion at every caret position; backspace edge cases | Pure Dart unit tests |
| `chip_history.dart` | Push / pop semantics; one-push-per-logical-op invariant | Pure Dart unit tests |
| `chip_renderer.dart` | Golden widget tests per ChipNode type, including nested function args | `flutter_test` golden files |
| `editor/entry_editor_page.dart` | Widget test: load entry → tap palette → save → verify DB and AST round-trip | `flutter_test` with mocked DB |
| `palette/variable_sheet.dart` | Widget test: create var with role+unit; reserved-identifier blocked; collision flow | `flutter_test` |
| `palette/number_sheet.dart` | Widget test: opens prefilled; commits replace chip text | `flutter_test` |
| `solve_page.dart` | Per-variable error highlight test | `flutter_test` |

Target: ≥80% widget coverage on `lib/ui/editor/` and `lib/ui/palette/`.

## 13. APK delivery cadence

Four APKs, one per phase. User installs and evaluates before next phase begins.

### Phase 1 — Skeleton

- New branch `feat/ui-rebuild` from `main`
- `lib/ui/` wiped except kept widgets
- **Add `shared_preferences: ^2.x` to `pubspec.yaml`** (needed for §7.4 advanced toggle and §9.2 drafts; cleaner to add up front than retroactively)
- Minimal rebuilt versions: `app.dart`, `folder_list_page.dart`, `entry_list_page.dart`, `solve_page.dart`, `settings_page.dart`
- Auto-import still works; existing engine/storage tests pass; new widget smoke test per screen
- "New formula" disabled; tapping an entry opens Solve only
- **APK 1**

### Phase 2 — Editor v1

- `chip_node.dart`, `chip_renderer.dart`, `chip_history.dart` (skeleton)
- `entry_editor_page.dart` host page
- Palette tabs Numbers / Vars (flat) / Operators / Functions (basic only)
- Number sheet, operator swap popover, function picker (basic)
- Save flow with banner + per-row errors
- Container chips, caret, backspace
- Multi-row with reorder + swipe-delete
- **APK 2**

### Phase 3 — Variable flow + disclosure

- Variable sheet full design (3 modes, role+unit form, color coding)
- Output mode wired to row-output chip
- Caret-aware palette highlighting
- Advanced-functions toggle + sub-tabs from `OpCategory`
- Function-name search
- **APK 3**

### Phase 4 — Undo / drafts / polish

- Undo/redo header buttons
- Draft auto-save + restore banner
- Solve page formula preview + per-variable error highlight + copy-to-clipboard
- Settings: reset-all-data, advanced toggle, diagnostics copy
- Entry list formula preview
- Folder-list empty-state import affordance
- Entry-name inline edit in AppBar
- **APK 4** — final spec compliance

## 14. Out of scope (explicit deferral list)

- Bulk variable management screen
- Unit parsing or dimensional checking
- Dark mode / theming toggle
- Multi-language UI
- Cloud sync / sharing
- Equation typesetting library (MathJax-style). Preview is plain chip render in disabled style.
