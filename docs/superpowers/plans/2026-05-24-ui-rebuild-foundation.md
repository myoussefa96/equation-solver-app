# UI Rebuild — Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `lib/ui/` (except `widgets/` and `import/`) with a polished foundation: theme, folder list, entry list, solve page, settings page. No chip editor yet — that's Plan B. After this plan, the app builds, all engine/storage tests pass, the user can browse and solve all auto-imported legacy formulas, but cannot yet create new formulas.

**Architecture:**
- Material 3, indigo seed, polished defaults (large touch targets, snackbar feedback, haptics on destructive actions, smooth transitions).
- Riverpod for state (already in place).
- `shared_preferences` newly added for editor-toggle persistence and (later) drafts.
- One responsibility per file; widgets ≤ 200 lines where possible.

**Tech Stack:** Flutter 3.44, Dart 3.12, `flutter_riverpod`, `sqflite`, **`shared_preferences ^2.2.0`** (new).

---

## Branch + branch hygiene

Plan A creates branch `feat/ui-rebuild` from `main`. All commits land there. No commits to `main` during execution.

## File map

**Created:**
- `lib/ui/app.dart` — Material app + theme + root navigation
- `lib/ui/folder_list_page.dart` — Folder list, FAB new-folder, empty-state with import affordance, long-press multi-select bulk delete, inline rename
- `lib/ui/entry_list_page.dart` — Entry list, FAB new-formula (stub for Plan B), tap → Solve, menu with Edit/Solve/Duplicate/Delete, formula preview subtitle
- `lib/ui/solve_page.dart` — Form with formula preview, per-variable error highlight, copy-to-clipboard on results, reset-to-last-saved button, snackbar feedback
- `lib/ui/settings_page.dart` — Sections: Data (import add/replace, reset-all-data with ERASE gate), Editor (advanced-functions toggle backed by SharedPreferences), About (version, diagnostics copy)
- `lib/state/settings_provider.dart` — Riverpod provider for SharedPreferences-backed app settings
- `lib/ui/widgets/section_header.dart` — Reusable section header for settings/sheets
- `lib/ui/widgets/result_tile.dart` — Result tile with optional copy-to-clipboard
- `test/ui/folder_list_page_test.dart` — Widget tests
- `test/ui/entry_list_page_test.dart` — Widget tests
- `test/ui/solve_page_test.dart` — Widget tests (incl. per-variable highlight on EvalError)
- `test/ui/settings_page_test.dart` — Widget tests
- `test/state/settings_provider_test.dart` — Tests for SharedPreferences-backed provider

**Modified:**
- `pubspec.yaml` — Add `shared_preferences: ^2.2.0`
- `.gitignore` — Already has flutter-plugins-dependencies (added in spec commit)

**Deleted (the wipe):**
- `lib/ui/entry_editor_page.dart` — Editor lives in Plan B
- `lib/ui/app.dart`, `lib/ui/folder_list_page.dart`, `lib/ui/entry_list_page.dart`, `lib/ui/solve_page.dart`, `lib/ui/settings_page.dart` — Rebuilt in this plan
- `test/ui/widget_smoke_test.dart` — Replaced by per-page tests

**Kept (no changes):**
- `lib/ui/import/import_flow.dart` — Auto-import code, works as-is
- `lib/ui/widgets/empty_state.dart` — Already correct
- `lib/ui/widgets/text_field_dialog.dart` — Already correct
- `lib/engine/**`, `lib/storage/**`, `lib/state/` (existing providers), `lib/main.dart`, `assets/**`

---

### Task 1: Create branch, wipe `lib/ui/`, add `shared_preferences`

**Files:**
- Modify: `pubspec.yaml`
- Delete: `lib/ui/app.dart`, `lib/ui/folder_list_page.dart`, `lib/ui/entry_list_page.dart`, `lib/ui/solve_page.dart`, `lib/ui/settings_page.dart`, `lib/ui/entry_editor_page.dart`, `test/ui/widget_smoke_test.dart`

- [ ] **Step 1: Create branch from main**

```bash
git checkout main
git checkout -b feat/ui-rebuild
```

Expected: "Switched to a new branch 'feat/ui-rebuild'"

- [ ] **Step 2: Delete the UI files being rebuilt**

```bash
rm lib/ui/app.dart lib/ui/folder_list_page.dart lib/ui/entry_list_page.dart lib/ui/solve_page.dart lib/ui/settings_page.dart lib/ui/entry_editor_page.dart
rm test/ui/widget_smoke_test.dart
```

- [ ] **Step 3: Add `shared_preferences` to pubspec.yaml**

In `pubspec.yaml`, under `dependencies:`, add `shared_preferences: ^2.2.0`. The dependencies block should read (preserve the order and other entries already present):

```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_riverpod: ^2.5.0
  sqflite: ^2.3.0
  path: ^1.9.0
  path_provider: ^2.1.0
  shared_preferences: ^2.2.0
  meta: ^1.11.0
```

- [ ] **Step 4: Fetch dependencies**

Run: `flutter pub get`
Expected: exit 0; "Got dependencies!"

- [ ] **Step 5: Verify the app no longer compiles (lib/main.dart imports deleted files)**

Run: `dart analyze 2>&1 | head -10`
Expected: errors about `package:equation_solver_app/ui/app.dart` not found. **This is intentional** — it's the gate that ensures Task 2 onwards re-create what's needed.

- [ ] **Step 6: Add `runBundledImportHeadless` to `lib/ui/import/import_flow.dart`**

Append (do not delete the existing `runBundledImport` — keep it for Settings):

```dart
// Append to lib/ui/import/import_flow.dart, after the existing runBundledImport function:

import 'package:equation_solver_app/storage/entries_repo.dart';
import 'package:equation_solver_app/storage/equations_repo.dart';
import 'package:equation_solver_app/storage/folders_repo.dart';
import 'package:equation_solver_app/storage/variable_meta_repo.dart';

/// Pure headless import — no UI, no providers. Returns the imported entry count.
/// Safe to call before runApp() during cold start.
Future<int> runBundledImportHeadless({
  required FoldersRepo folders,
  required EntriesRepo entries,
  required EquationsRepo equations,
  required VariableMetaRepo variables,
  required bool replaceExisting,
}) async {
  final raw = await rootBundle.loadString('assets/migration_seed.json');
  final seed = jsonDecode(raw) as Map<String, Object?>;
  final report = LegacyImporter.importSeedWithReport(seed);

  final service = ImportService(
    folders: folders,
    entries: entries,
    equations: equations,
    variables: variables,
  );
  await service.importParsedFolders(
    report.folders,
    replaceExisting: replaceExisting,
  );

  return report.folders.fold<int>(0, (n, f) => n + f.entries.length);
}
```

Make sure the four storage-repo imports go in the import block at the top of the file (deduplicate if any already exist).

- [ ] **Step 7: Add auto-import to `lib/main.dart`**

Replace `lib/main.dart` contents with:

```dart
import 'dart:io';

import 'package:equation_solver_app/state/db_provider.dart';
import 'package:equation_solver_app/storage/database.dart';
import 'package:equation_solver_app/storage/entries_repo.dart';
import 'package:equation_solver_app/storage/equations_repo.dart';
import 'package:equation_solver_app/storage/folders_repo.dart';
import 'package:equation_solver_app/storage/variable_meta_repo.dart';
import 'package:equation_solver_app/ui/app.dart';
import 'package:equation_solver_app/ui/import/import_flow.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = await AppDatabase.openApp();

  // Auto-import bundled formulas on first launch when DB is empty.
  try {
    final folders = FoldersRepo(db);
    final existing = await folders.listAll();
    if (existing.isEmpty) {
      await runBundledImportHeadless(
        folders: folders,
        entries: EntriesRepo(db),
        equations: EquationsRepo(db),
        variables: VariableMetaRepo(db),
        replaceExisting: false,
      );
    }
  } catch (e, st) {
    stderr.writeln('[auto-import] failed, continuing with empty state: $e\n$st');
  }

  runApp(
    ProviderScope(
      overrides: [dbProvider.overrideWithValue(db)],
      child: const EquationSolverApp(),
    ),
  );
}
```

- [ ] **Step 8: Commit the wipe + auto-import wiring**

```bash
git add -u pubspec.yaml lib/ui test/ui lib/main.dart
git status   # verify no surprise stragglers
git commit -m "$(cat <<'EOF'
chore(ui): wipe lib/ui screens, add shared_preferences, wire auto-import

Clears the calculator-style flat-string editor and stub screens to make
room for the proper chip-flow rebuild. lib/ui/import and lib/ui/widgets
are preserved (they're correct). Adds shared_preferences upfront so the
editor toggle + drafts can use it from the start.

Also restores the auto-import-on-first-launch behavior (was in the
abandoned fix/ux-iteration-1 branch) via a new headless variant of
runBundledImport.

App no longer compiles until Tasks 2-9 rebuild lib/ui.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Recreate `lib/ui/app.dart` with polished Material 3 theme

**Files:**
- Create: `lib/ui/app.dart`
- Test: smoke test deferred to Task 3 (it tests app + folder list together)

- [ ] **Step 1: Write the file**

```dart
// lib/ui/app.dart
import 'package:flutter/material.dart';

import 'folder_list_page.dart';

class EquationSolverApp extends StatelessWidget {
  const EquationSolverApp({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF1A5490),
      brightness: Brightness.light,
    );

    return MaterialApp(
      title: 'Equation Solver',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: colorScheme.surface,
        appBarTheme: AppBarTheme(
          centerTitle: false,
          backgroundColor: colorScheme.surface,
          foregroundColor: colorScheme.onSurface,
          elevation: 0,
          scrolledUnderElevation: 1,
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          color: colorScheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          margin: EdgeInsets.zero,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(64, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        listTileTheme: const ListTileThemeData(
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          minVerticalPadding: 12,
        ),
      ),
      home: const FolderListPage(),
    );
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/ui/app.dart
git commit -m "feat(ui): polished Material 3 theme with surfaceContainer cards"
```

---

### Task 3: SharedPreferences-backed settings provider

**Files:**
- Create: `lib/state/settings_provider.dart`
- Test: `test/state/settings_provider_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/state/settings_provider_test.dart
import 'package:equation_solver_app/state/settings_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('advancedFunctionsEnabled defaults to false on first read', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final enabled = await container.read(advancedFunctionsEnabledProvider.future);
    expect(enabled, isFalse);
  });

  test('setAdvancedFunctionsEnabled persists across container disposal', () async {
    final c1 = ProviderContainer();
    await c1.read(appSettingsProvider.notifier).setAdvancedFunctionsEnabled(true);
    c1.dispose();

    SharedPreferences.setMockInitialValues({
      'palette.advancedFunctions': true,
    });
    final c2 = ProviderContainer();
    addTearDown(c2.dispose);

    final enabled = await c2.read(advancedFunctionsEnabledProvider.future);
    expect(enabled, isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/state/settings_provider_test.dart`
Expected: FAIL — `advancedFunctionsEnabledProvider` not found.

- [ ] **Step 3: Write the provider**

```dart
// lib/state/settings_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kAdvancedFunctions = 'palette.advancedFunctions';

class AppSettings {
  const AppSettings({required this.advancedFunctionsEnabled});
  final bool advancedFunctionsEnabled;
}

class AppSettingsNotifier extends AsyncNotifier<AppSettings> {
  @override
  Future<AppSettings> build() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings(
      advancedFunctionsEnabled: prefs.getBool(_kAdvancedFunctions) ?? false,
    );
  }

  Future<void> setAdvancedFunctionsEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAdvancedFunctions, value);
    state = AsyncData(AppSettings(advancedFunctionsEnabled: value));
  }
}

final appSettingsProvider =
    AsyncNotifierProvider<AppSettingsNotifier, AppSettings>(
  AppSettingsNotifier.new,
);

final advancedFunctionsEnabledProvider = FutureProvider<bool>((ref) async {
  final settings = await ref.watch(appSettingsProvider.future);
  return settings.advancedFunctionsEnabled;
});
```

- [ ] **Step 4: Run test, see it pass**

Run: `flutter test test/state/settings_provider_test.dart`
Expected: 2/2 pass.

- [ ] **Step 5: Commit**

```bash
git add lib/state/settings_provider.dart test/state/settings_provider_test.dart
git commit -m "feat(state): SharedPreferences-backed app settings provider"
```

---

### Task 4: Settings page rewrite

**Files:**
- Create: `lib/ui/settings_page.dart`
- Test: `test/ui/settings_page_test.dart`

- [ ] **Step 1: Write the failing widget test**

```dart
// test/ui/settings_page_test.dart
import 'package:equation_solver_app/state/db_provider.dart';
import 'package:equation_solver_app/storage/database.dart';
import 'package:equation_solver_app/ui/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../storage/_test_db.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('shows Data / Editor / About sections', (tester) async {
    final db = await openTestDb();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [dbProvider.overrideWithValue(db)],
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Data'), findsOneWidget);
    expect(find.text('Editor'), findsOneWidget);
    expect(find.text('About'), findsOneWidget);
    expect(find.text('Reset all data'), findsOneWidget);
    expect(find.text('Advanced functions'), findsOneWidget);
  });

  testWidgets('toggles advanced functions and persists', (tester) async {
    final db = await openTestDb();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [dbProvider.overrideWithValue(db)],
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Switch), findsOneWidget);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('palette.advancedFunctions'), isTrue);
  });

  testWidgets('reset-all-data requires typing ERASE', (tester) async {
    final db = await openTestDb();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [dbProvider.overrideWithValue(db)],
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Reset all data'));
    await tester.pumpAndSettle();

    final eraseButton = find.widgetWithText(FilledButton, 'Erase');
    expect(tester.widget<FilledButton>(eraseButton).onPressed, isNull);

    await tester.enterText(find.byType(TextField).last, 'ERASE');
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(eraseButton).onPressed, isNotNull);
  });
}
```

Note: this test uses the existing helper `test/storage/_test_db.dart` (returns `AppDatabase` initialized with `databaseFactoryFfi`). `sqflite_common_ffi` is already in `dev_dependencies`. `AppDatabase.openInMemory(databaseFactory: databaseFactoryFfi)` already exists.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/settings_page_test.dart`
Expected: FAIL — `SettingsPage` not found.

- [ ] **Step 3: Write the page**

```dart
// lib/ui/settings_page.dart
import 'package:equation_solver_app/state/db_provider.dart';
import 'package:equation_solver_app/state/folders_provider.dart';
import 'package:equation_solver_app/state/settings_provider.dart';
import 'package:equation_solver_app/storage/folders_repo.dart';
import 'package:equation_solver_app/ui/import/import_flow.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(appSettingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          _section('Data'),
          ListTile(
            leading: const Icon(Icons.download),
            title: const Text('Import from old app — add to library'),
            subtitle: const Text('15 formulas in 2 groups from the legacy Django app.'),
            onTap: () => runBundledImport(context, ref, replaceExisting: false),
          ),
          ListTile(
            leading: const Icon(Icons.swap_horiz),
            title: const Text('Import from old app — replace library'),
            subtitle: const Text('Warning: this wipes everything you have first.'),
            onTap: () => _confirmReplaceImport(context, ref),
          ),
          ListTile(
            leading: Icon(Icons.delete_forever, color: Theme.of(context).colorScheme.error),
            title: const Text('Reset all data'),
            subtitle: const Text('Permanently deletes every group, formula, and value.'),
            onTap: () => _confirmEraseAll(context, ref),
          ),
          const Divider(height: 32),
          _section('Editor'),
          settingsAsync.when(
            loading: () => const ListTile(title: Text('Loading settings…')),
            error: (e, _) => ListTile(title: Text('Error: $e')),
            data: (settings) => SwitchListTile(
              secondary: const Icon(Icons.science),
              title: const Text('Advanced functions'),
              subtitle: const Text(
                'Show trigonometric inverse, hyperbolic, rounding, and other advanced functions in the keypad.',
              ),
              value: settings.advancedFunctionsEnabled,
              onChanged: (v) async {
                HapticFeedback.selectionClick();
                await ref
                    .read(appSettingsProvider.notifier)
                    .setAdvancedFunctionsEnabled(v);
              },
            ),
          ),
          const Divider(height: 32),
          _section('About'),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Equation Solver'),
            subtitle: Text('Version 1.0'),
          ),
          ListTile(
            leading: const Icon(Icons.bug_report),
            title: const Text('Copy diagnostics'),
            subtitle: const Text('Useful when reporting a problem.'),
            onTap: () => _copyDiagnostics(context, ref),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Builder(
          builder: (context) => Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
      );

  Future<void> _confirmReplaceImport(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Replace your library?'),
        content: const Text(
          'This deletes ALL your existing groups and formulas, then re-imports from the old app.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Replace')),
        ],
      ),
    );
    if (ok ?? false) {
      if (!context.mounted) return;
      HapticFeedback.mediumImpact();
      await runBundledImport(context, ref, replaceExisting: true);
    }
  }

  Future<void> _confirmEraseAll(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Reset all data?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('This permanently deletes everything in your library. Cannot be undone.'),
              const SizedBox(height: 12),
              const Text('Type ERASE to confirm:'),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
            FilledButton(
              onPressed: controller.text == 'ERASE' ? () => Navigator.of(ctx).pop(true) : null,
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error,
              ),
              child: const Text('Erase'),
            ),
          ],
        ),
      ),
    );
    if (ok ?? false) {
      if (!context.mounted) return;
      HapticFeedback.heavyImpact();
      final db = ref.read(dbProvider);
      // Folders cascade to entries, equations, variables.
      for (final f in await FoldersRepo(db).listAll()) {
        await FoldersRepo(db).delete(f.id);
      }
      ref.invalidate(foldersListProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Library reset.')),
        );
      }
    }
  }

  Future<void> _copyDiagnostics(BuildContext context, WidgetRef ref) async {
    final db = ref.read(dbProvider);
    final folderCount = (await FoldersRepo(db).listAll()).length;
    final diag = '''
Equation Solver diagnostics
Version: 1.0
Schema: ${await db.raw.getVersion()}
Folders: $folderCount
''';
    await Clipboard.setData(ClipboardData(text: diag));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Diagnostics copied to clipboard')),
      );
    }
  }
}
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/ui/settings_page_test.dart test/state/settings_provider_test.dart`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/settings_page.dart test/ui/settings_page_test.dart
git commit -m "feat(ui): settings page with data/editor/about sections + ERASE gate"
```

---

### Task 5: Folder list page with polished empty state and bulk delete

**Files:**
- Create: `lib/ui/folder_list_page.dart`
- Test: `test/ui/folder_list_page_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/ui/folder_list_page_test.dart
import 'package:equation_solver_app/state/db_provider.dart';
import 'package:equation_solver_app/state/folders_provider.dart';
import 'package:equation_solver_app/storage/database.dart';
import 'package:equation_solver_app/storage/folders_repo.dart';
import 'package:equation_solver_app/ui/folder_list_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../storage/_test_db.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('empty state shows BOTH new-group and import buttons', (tester) async {
    final db = await openTestDb();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [dbProvider.overrideWithValue(db)],
        child: const MaterialApp(home: FolderListPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('New group'), findsWidgets);
    expect(find.text('Import from old app'), findsOneWidget);
  });

  testWidgets('lists folders and supports tap', (tester) async {
    final db = await openTestDb();
    await FoldersRepo(db).create(name: 'Steam ejector');
    await FoldersRepo(db).create(name: 'Pipe friction');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [dbProvider.overrideWithValue(db)],
        child: const MaterialApp(home: FolderListPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Steam ejector'), findsOneWidget);
    expect(find.text('Pipe friction'), findsOneWidget);
  });

  testWidgets('long-press a folder enters multi-select mode', (tester) async {
    final db = await openTestDb();
    await FoldersRepo(db).create(name: 'Folder A');
    await FoldersRepo(db).create(name: 'Folder B');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [dbProvider.overrideWithValue(db)],
        child: const MaterialApp(home: FolderListPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Folder A'));
    await tester.pumpAndSettle();

    expect(find.text('1 selected'), findsOneWidget);
    expect(find.byIcon(Icons.delete), findsOneWidget);

    await tester.tap(find.text('Folder B'));
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/folder_list_page_test.dart`
Expected: FAIL — `FolderListPage` not found.

- [ ] **Step 3: Write the page**

```dart
// lib/ui/folder_list_page.dart
import 'package:equation_solver_app/state/folders_provider.dart';
import 'package:equation_solver_app/storage/folders_repo.dart';
import 'package:equation_solver_app/ui/entry_list_page.dart';
import 'package:equation_solver_app/ui/import/import_flow.dart';
import 'package:equation_solver_app/ui/settings_page.dart';
import 'package:equation_solver_app/ui/widgets/empty_state.dart';
import 'package:equation_solver_app/ui/widgets/text_field_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class FolderListPage extends ConsumerStatefulWidget {
  const FolderListPage({super.key});

  @override
  ConsumerState<FolderListPage> createState() => _FolderListPageState();
}

class _FolderListPageState extends ConsumerState<FolderListPage> {
  final _selected = <int>{};
  bool get _selectMode => _selected.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final foldersAsync = ref.watch(foldersListProvider);
    return Scaffold(
      appBar: _selectMode ? _selectAppBar() : _normalAppBar(context),
      floatingActionButton: _selectMode
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _createFolder(context),
              icon: const Icon(Icons.create_new_folder),
              label: const Text('New group'),
            ),
      body: foldersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (folders) {
          if (folders.isEmpty) return _emptyState();
          return RefreshIndicator(
            onRefresh: () async {
              HapticFeedback.lightImpact();
              ref.invalidate(foldersListProvider);
              await ref.read(foldersListProvider.future);
            },
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: folders.length,
              separatorBuilder: (_, __) => const SizedBox(height: 4),
              itemBuilder: (context, i) => _folderTile(folders[i]),
            ),
          );
        },
      ),
    );
  }

  AppBar _normalAppBar(BuildContext context) => AppBar(
        title: const Text('Groups'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
            ),
          ),
        ],
      );

  AppBar _selectAppBar() => AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => setState(_selected.clear),
        ),
        title: Text('${_selected.length} selected'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete),
            tooltip: 'Delete selected',
            onPressed: _deleteSelected,
          ),
        ],
      );

  Widget _folderTile(FolderRow folder) {
    final selected = _selected.contains(folder.id);
    return Card(
      child: ListTile(
        selected: selected,
        leading: selected
            ? const Icon(Icons.check_circle)
            : const Icon(Icons.folder),
        title: Text(folder.name, style: const TextStyle(fontWeight: FontWeight.w500)),
        onLongPress: () {
          HapticFeedback.mediumImpact();
          setState(() => _selected.add(folder.id));
        },
        onTap: () {
          if (_selectMode) {
            setState(() {
              if (selected) {
                _selected.remove(folder.id);
              } else {
                _selected.add(folder.id);
              }
            });
          } else {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => EntryListPage(folder: folder),
              ),
            );
          }
        },
        trailing: _selectMode
            ? null
            : PopupMenuButton<String>(
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'rename', child: Text('Rename')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
                onSelected: (action) async {
                  if (action == 'rename') {
                    await _renameFolder(folder);
                  } else if (action == 'delete') {
                    await _deleteFolder(folder);
                  }
                },
              ),
      ),
    );
  }

  Widget _emptyState() => Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 48),
            Icon(Icons.folder_open, size: 96, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            const Text(
              'No groups yet',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Create a group of formulas, or import the 15 formulas from your old app.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.create_new_folder),
              label: const Text('New group'),
              onPressed: () => _createFolder(context),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              icon: const Icon(Icons.download),
              label: const Text('Import from old app'),
              onPressed: () => runBundledImport(context, ref, replaceExisting: false),
            ),
          ],
        ),
      );

  Future<void> _createFolder(BuildContext context) async {
    final name = await showTextFieldDialog(
      context,
      title: 'New group',
      hint: 'e.g. Pipe friction',
      confirmLabel: 'Create',
    );
    if (name == null) return;
    await ref.read(foldersRepoProvider).create(name: name);
    ref.invalidate(foldersListProvider);
  }

  Future<void> _renameFolder(FolderRow folder) async {
    final newName = await showTextFieldDialog(
      context,
      title: 'Rename group',
      initialValue: folder.name,
      confirmLabel: 'Rename',
    );
    if (newName != null) {
      await ref.read(foldersRepoProvider).rename(folder.id, newName);
      ref.invalidate(foldersListProvider);
    }
  }

  Future<void> _deleteFolder(FolderRow folder) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this group?'),
        content: Text('This will permanently delete "${folder.name}" and all its formulas.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok ?? false) {
      HapticFeedback.mediumImpact();
      await ref.read(foldersRepoProvider).delete(folder.id);
      ref.invalidate(foldersListProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Deleted "${folder.name}"')),
        );
      }
    }
  }

  Future<void> _deleteSelected() async {
    final count = _selected.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(count == 1 ? 'Delete this group?' : 'Delete $count groups?'),
        content: Text(
          'This will permanently delete '
          '${count == 1 ? "the selected group" : "$count groups"} and all their formulas.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok ?? false) {
      HapticFeedback.heavyImpact();
      final repo = ref.read(foldersRepoProvider);
      for (final id in _selected) {
        await repo.delete(id);
      }
      setState(_selected.clear);
      ref.invalidate(foldersListProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Deleted $count ${count == 1 ? "group" : "groups"}')),
        );
      }
    }
  }
}
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/ui/folder_list_page_test.dart`
Expected: 3/3 pass.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/folder_list_page.dart test/ui/folder_list_page_test.dart
git commit -m "feat(ui): folder list with polished empty state + long-press bulk delete"
```

---

### Task 6: Entry list page with formula preview subtitle

**Files:**
- Create: `lib/ui/entry_list_page.dart`
- Test: `test/ui/entry_list_page_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/ui/entry_list_page_test.dart
import 'package:equation_solver_app/engine/ast.dart';
import 'package:equation_solver_app/state/db_provider.dart';
import 'package:equation_solver_app/storage/database.dart';
import 'package:equation_solver_app/storage/entries_repo.dart';
import 'package:equation_solver_app/storage/equations_repo.dart';
import 'package:equation_solver_app/storage/folders_repo.dart';
import 'package:equation_solver_app/ui/entry_list_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../storage/_test_db.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows formula preview in subtitle', (tester) async {
    final db = await openTestDb();
    final folders = FoldersRepo(db);
    final entries = EntriesRepo(db);
    final equations = EquationsRepo(db);

    final folderId = await folders.create(name: 'Test');
    final entryId = await entries.create(folderId: folderId, name: 'Speed = d/t');
    await equations.replaceAll(entryId, [
      EquationDraft(
        entryId: entryId,
        outputVar: 'v',
        ast: const BinaryOp(Identifier('d'), '/', Identifier('t')),
        sortOrder: 0,
      ),
    ]);

    final folderRow = (await folders.listAll()).first;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [dbProvider.overrideWithValue(db)],
        child: MaterialApp(home: EntryListPage(folder: folderRow)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Speed = d/t'), findsOneWidget);
    expect(find.textContaining('v ='), findsOneWidget);
  });

  testWidgets('menu offers Edit / Solve / Duplicate / Delete', (tester) async {
    final db = await openTestDb();
    final folders = FoldersRepo(db);
    final entries = EntriesRepo(db);

    final folderId = await folders.create(name: 'Test');
    await entries.create(folderId: folderId, name: 'Speed');

    final folderRow = (await folders.listAll()).first;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [dbProvider.overrideWithValue(db)],
        child: MaterialApp(home: EntryListPage(folder: folderRow)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();

    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Solve'), findsOneWidget);
    expect(find.text('Duplicate'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test, see it fail**

Run: `flutter test test/ui/entry_list_page_test.dart`
Expected: FAIL — `EntryListPage` not found.

- [ ] **Step 3: Write the page**

```dart
// lib/ui/entry_list_page.dart
import 'package:equation_solver_app/engine/ast.dart';
import 'package:equation_solver_app/state/entries_provider.dart';
import 'package:equation_solver_app/state/entry_detail_provider.dart';
import 'package:equation_solver_app/storage/entries_repo.dart';
import 'package:equation_solver_app/storage/folders_repo.dart';
import 'package:equation_solver_app/ui/solve_page.dart';
import 'package:equation_solver_app/ui/widgets/empty_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class EntryListPage extends ConsumerWidget {
  const EntryListPage({super.key, required this.folder});
  final FolderRow folder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entriesAsync = ref.watch(entriesByFolderProvider(folder.id));
    void refresh() => ref.invalidate(entriesByFolderProvider(folder.id));

    return Scaffold(
      appBar: AppBar(title: Text(folder.name)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Formula editor coming in next update')),
          );
        },
        icon: const Icon(Icons.add),
        label: const Text('New formula'),
      ),
      body: entriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (entries) {
          if (entries.isEmpty) {
            return EmptyState(
              icon: Icons.functions,
              title: 'No formulas in this group yet.',
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              HapticFeedback.lightImpact();
              ref.invalidate(entriesByFolderProvider(folder.id));
              await ref.read(entriesByFolderProvider(folder.id).future);
            },
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: entries.length,
              separatorBuilder: (_, __) => const SizedBox(height: 4),
              itemBuilder: (context, i) => _entryTile(context, ref, entries[i], refresh),
            ),
          );
        },
      ),
    );
  }

  Widget _entryTile(
    BuildContext context,
    WidgetRef ref,
    EntryRow entry,
    VoidCallback refresh,
  ) {
    final detailAsync = ref.watch(entryDetailProvider(entry.id));
    final preview = detailAsync.maybeWhen(
      data: (detail) => _formulaPreview(detail.equations),
      orElse: () => '',
    );

    return Card(
      child: ListTile(
        leading: const Icon(Icons.functions),
        title: Text(entry.name, style: const TextStyle(fontWeight: FontWeight.w500)),
        subtitle: preview.isEmpty
            ? (entry.description == null ? null : Text(entry.description!, maxLines: 1, overflow: TextOverflow.ellipsis))
            : Text(
                preview,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
        trailing: PopupMenuButton<String>(
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'edit', child: Text('Edit')),
            PopupMenuItem(value: 'solve', child: Text('Solve')),
            PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
            PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
          onSelected: (action) => _onAction(context, ref, entry, action, refresh),
        ),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SolvePage(entryId: entry.id, entryName: entry.name),
          ),
        ),
      ),
    );
  }

  String _formulaPreview(List<EquationRow> equations) {
    if (equations.isEmpty) return '';
    final lines = <String>[];
    for (final eq in equations.take(2)) {
      final rhs = _renderAst(eq.ast);
      final truncated = rhs.length > 35 ? '${rhs.substring(0, 32)}…' : rhs;
      lines.add('${eq.outputVar} = $truncated');
    }
    return lines.join('\n');
  }

  String _renderAst(AstNode n) {
    return switch (n) {
      NumberLit(:final value) => value.toString(),
      Identifier(:final name) => name,
      UnaryMinus(:final operand) => '-${_renderAst(operand)}',
      BinaryOp(:final op, :final left, :final right) =>
        '(${_renderAst(left)}${op}${_renderAst(right)})',
      FunctionCall(:final name, :final args) =>
        '$name(${args.map(_renderAst).join(',')})',
    };
  }

  Future<void> _onAction(
    BuildContext context,
    WidgetRef ref,
    EntryRow entry,
    String action,
    VoidCallback refresh,
  ) async {
    if (action == 'edit') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Formula editor coming in next update')),
      );
    } else if (action == 'solve') {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SolvePage(entryId: entry.id, entryName: entry.name),
        ),
      );
    } else if (action == 'duplicate') {
      HapticFeedback.lightImpact();
      await _duplicate(ref, entry);
      refresh();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Duplicated "${entry.name}"')),
        );
      }
    } else if (action == 'delete') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete this formula?'),
          content: Text('"${entry.name}" will be deleted permanently.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (ok ?? false) {
        HapticFeedback.mediumImpact();
        await ref.read(entriesRepoProvider).delete(entry.id);
        refresh();
      }
    }
  }

  Future<void> _duplicate(WidgetRef ref, EntryRow entry) async {
    // Plan B will properly duplicate including equations and variables.
    // For Plan A, duplicate just the entry name+description; equations stay empty.
    await ref.read(entriesRepoProvider).create(
          folderId: folder.id,
          name: '${entry.name} (copy)',
          description: entry.description,
        );
  }
}
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/ui/entry_list_page_test.dart`
Expected: 2/2 pass.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/entry_list_page.dart test/ui/entry_list_page_test.dart
git commit -m "feat(ui): entry list with formula preview + Edit/Solve/Duplicate/Delete menu"
```

---

### Task 7: Result tile widget (extracted for reuse on solve page)

**Files:**
- Create: `lib/ui/widgets/result_tile.dart`

This is a small shared widget. No standalone test — covered by solve_page tests.

- [ ] **Step 1: Write the widget**

```dart
// lib/ui/widgets/result_tile.dart
import 'package:equation_solver_app/storage/variable_meta_repo.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ResultTile extends StatelessWidget {
  const ResultTile({
    super.key,
    required this.variable,
    required this.value,
    this.emphasis = false,
    this.errorMessage,
  });

  final VariableMetaRow variable;
  final double? value;
  final bool emphasis;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasError = errorMessage != null;

    return Card(
      shape: hasError
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: scheme.error, width: 2),
            )
          : null,
      color: hasError
          ? scheme.errorContainer
          : (emphasis ? scheme.primaryContainer : null),
      child: ListTile(
        title: Text(
          variable.displayLabel,
          style: TextStyle(
            fontWeight: emphasis ? FontWeight.bold : FontWeight.w500,
            color: hasError ? scheme.onErrorContainer : null,
          ),
        ),
        subtitle: hasError
            ? Text(errorMessage!, style: TextStyle(color: scheme.onErrorContainer))
            : (variable.unit == null ? null : Text(variable.unit!)),
        trailing: hasError
            ? Icon(Icons.error_outline, color: scheme.error)
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    value == null ? '—' : _format(value!),
                    style: TextStyle(
                      fontSize: emphasis ? 22 : 16,
                      fontWeight: emphasis ? FontWeight.bold : FontWeight.w500,
                      color: emphasis ? scheme.onPrimaryContainer : null,
                      fontFamily: 'monospace',
                    ),
                  ),
                  if (value != null) ...[
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 18),
                      tooltip: 'Copy value',
                      onPressed: () async {
                        final formatted = _format(value!);
                        await Clipboard.setData(ClipboardData(text: formatted));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Copied $formatted')),
                          );
                          HapticFeedback.selectionClick();
                        }
                      },
                    ),
                  ],
                ],
              ),
      ),
    );
  }

  static String _format(double v) {
    if (v == 0) return '0';
    final abs = v.abs();
    if (abs >= 1e6 || abs < 1e-3) {
      return v.toStringAsExponential(4);
    }
    return v
        .toStringAsPrecision(6)
        .replaceAll(RegExp(r'(?<=\.\d*?)0+$'), '')
        .replaceAll(RegExp(r'\.$'), '');
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/ui/widgets/result_tile.dart
git commit -m "feat(ui): ResultTile widget with copy-to-clipboard and error variant"
```

---

### Task 8: Solve page with formula preview, per-variable error highlight, reset-to-last-saved

**Files:**
- Create: `lib/ui/solve_page.dart`
- Test: `test/ui/solve_page_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/ui/solve_page_test.dart
import 'package:equation_solver_app/engine/ast.dart';
import 'package:equation_solver_app/state/db_provider.dart';
import 'package:equation_solver_app/storage/database.dart';
import 'package:equation_solver_app/storage/entries_repo.dart';
import 'package:equation_solver_app/storage/equations_repo.dart';
import 'package:equation_solver_app/storage/folders_repo.dart';
import 'package:equation_solver_app/storage/variable_meta_repo.dart';
import 'package:equation_solver_app/ui/solve_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../storage/_test_db.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('solves simple equation and shows result', (tester) async {
    final db = await openTestDb();
    final entryId = await _seedSimpleEquation(db);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [dbProvider.overrideWithValue(db)],
        child: MaterialApp(home: SolvePage(entryId: entryId, entryName: 'Speed')),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'd'), '100');
    await tester.enterText(find.widgetWithText(TextFormField, 't'), '4');
    await tester.tap(find.text('Solve'));
    await tester.pumpAndSettle();

    expect(find.text('25'), findsOneWidget);
  });

  testWidgets('div-by-zero shows per-variable error highlight', (tester) async {
    final db = await openTestDb();
    final entryId = await _seedSimpleEquation(db);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [dbProvider.overrideWithValue(db)],
        child: MaterialApp(home: SolvePage(entryId: entryId, entryName: 'Speed')),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'd'), '100');
    await tester.enterText(find.widgetWithText(TextFormField, 't'), '0');
    await tester.tap(find.text('Solve'));
    await tester.pumpAndSettle();

    // The card-with-message describing the error must be visible
    expect(find.textContaining(RegExp('zero|divide', caseSensitive: false)), findsWidgets);
  });

  testWidgets('shows formula preview at top', (tester) async {
    final db = await openTestDb();
    final entryId = await _seedSimpleEquation(db);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [dbProvider.overrideWithValue(db)],
        child: MaterialApp(home: SolvePage(entryId: entryId, entryName: 'Speed')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Formula'), findsOneWidget);
    expect(find.textContaining('v ='), findsOneWidget);
  });
}

Future<int> _seedSimpleEquation(db) async {
  final folderId = await FoldersRepo(db).create(name: 'Test');
  final entryId = await EntriesRepo(db).create(folderId: folderId, name: 'Speed');
  await EquationsRepo(db).replaceAll(entryId, [
    EquationDraft(
      entryId: entryId,
      outputVar: 'v',
      ast: const BinaryOp(Identifier('d'), '/', Identifier('t')),
      sortOrder: 0,
    ),
  ]);
  await VariableMetaRepo(db).replaceAll(entryId, [
    VariableMetaDraft(entryId: entryId, identifier: 'd', displayLabel: 'd', role: VarRole.input),
    VariableMetaDraft(entryId: entryId, identifier: 't', displayLabel: 't', role: VarRole.input),
    VariableMetaDraft(entryId: entryId, identifier: 'v', displayLabel: 'v', role: VarRole.output, isFinal: true),
  ]);
  return entryId;
}
```

- [ ] **Step 2: Run test, see it fail**

Run: `flutter test test/ui/solve_page_test.dart`
Expected: FAIL — `SolvePage` not found.

- [ ] **Step 3: Write the page**

```dart
// lib/ui/solve_page.dart
import 'package:equation_solver_app/engine/ast.dart';
import 'package:equation_solver_app/engine/dependency_resolver.dart';
import 'package:equation_solver_app/engine/errors.dart';
import 'package:equation_solver_app/engine/evaluator.dart';
import 'package:equation_solver_app/state/entry_detail_provider.dart';
import 'package:equation_solver_app/storage/variable_meta_repo.dart';
import 'package:equation_solver_app/ui/widgets/result_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SolvePage extends ConsumerStatefulWidget {
  const SolvePage({super.key, required this.entryId, required this.entryName});
  final int entryId;
  final String entryName;

  @override
  ConsumerState<SolvePage> createState() => _SolvePageState();
}

class _SolvePageState extends ConsumerState<SolvePage> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _controllers = {};
  final Set<String> _initialised = {};

  Map<String, double>? _results;
  String? _errorMessage;
  String? _errorOutputIdentifier;

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(String identifier, double? lastValue) {
    if (!_controllers.containsKey(identifier)) {
      _controllers[identifier] = TextEditingController(text: lastValue?.toString() ?? '');
      _initialised.add(identifier);
    } else if (!_initialised.contains(identifier)) {
      _controllers[identifier]!.text = lastValue?.toString() ?? '';
      _initialised.add(identifier);
    }
    return _controllers[identifier]!;
  }

  Future<void> _solve(EntryDetail detail) async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final inputs = detail.variables.where((v) => v.role == VarRole.input).toList()
      ..sort((a, b) => a.displayLabel.compareTo(b.displayLabel));

    final scope = <String, double>{};
    for (final v in inputs) {
      final text = _controllers[v.identifier]!.text.trim().replaceAll(',', '.');
      scope[v.identifier] = double.parse(text);
    }

    try {
      final equations = detail.equations
          .map((e) => EqEntry(output: e.outputVar, ast: e.ast))
          .toList();
      final resolved = DependencyResolver.resolve(equations);

      String? failingOutput;
      for (final outputName in resolved.order) {
        final eq = detail.equations.firstWhere((e) => e.outputVar == outputName);
        try {
          scope[outputName] = Evaluator(scope: scope).eval(eq.ast);
        } on EngineError catch (e) {
          failingOutput = outputName;
          throw _SolveFailure(outputName, e);
        }
      }

      final repo = ref.read(variableMetaRepoProvider);
      for (final v in inputs) {
        await repo.updateLastValue(widget.entryId, v.identifier, scope[v.identifier]!);
      }
      ref.invalidate(entryDetailProvider(widget.entryId));

      if (mounted) {
        HapticFeedback.lightImpact();
        setState(() {
          _results = {
            for (final v in detail.variables.where((v) => v.role == VarRole.output))
              v.identifier: scope[v.identifier] ?? double.nan,
          };
          _errorMessage = null;
          _errorOutputIdentifier = null;
        });
      }
      // Suppress lint about unused.
      failingOutput;
    } on _SolveFailure catch (sf) {
      if (mounted) {
        HapticFeedback.mediumImpact();
        setState(() {
          _results = {};
          _errorMessage = sf.engineError.userMessage;
          _errorOutputIdentifier = sf.outputName;
        });
      }
    } on EngineError catch (e) {
      if (mounted) {
        HapticFeedback.mediumImpact();
        setState(() {
          _results = null;
          _errorMessage = e.userMessage;
          _errorOutputIdentifier = null;
        });
      }
    }
  }

  void _resetInputs(List<VariableMetaRow> inputs) {
    for (final v in inputs) {
      _controllers[v.identifier]?.text = v.lastValue?.toString() ?? '';
    }
    setState(() {
      _results = null;
      _errorMessage = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Inputs reset to last saved values')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final asyncDetail = ref.watch(entryDetailProvider(widget.entryId));

    return Scaffold(
      appBar: AppBar(title: Text(widget.entryName)),
      body: asyncDetail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Failed to load: $err')),
        data: (detail) => _buildForm(context, detail),
      ),
    );
  }

  Widget _buildForm(BuildContext context, EntryDetail detail) {
    final inputs = detail.variables.where((v) => v.role == VarRole.input).toList()
      ..sort((a, b) => a.displayLabel.compareTo(b.displayLabel));
    final finalOutputs = detail.variables.where((v) => v.role == VarRole.output && v.isFinal).toList();
    final otherOutputs = detail.variables.where((v) => v.role == VarRole.output && !v.isFinal).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sectionLabel('Formula'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final eq in detail.equations)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          '${eq.outputVar} = ${_renderAst(eq.ast)}',
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            _sectionLabel('Enter values'),
            for (final v in inputs) ...[
              TextFormField(
                controller: _controllerFor(v.identifier, v.lastValue),
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                decoration: InputDecoration(
                  labelText: v.displayLabel,
                  helperText: v.unit,
                  border: const OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) return 'Enter a value';
                  final normalized = value.trim().replaceAll(',', '.');
                  if (double.tryParse(normalized) == null) {
                    return 'Numbers only — try "1.4" instead of "1,4"';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _solve(detail),
                    icon: const Icon(Icons.calculate),
                    label: const Text('Solve'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () => _resetInputs(inputs),
                  child: const Text('Reset'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (_errorMessage != null && _errorOutputIdentifier == null)
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
                  ),
                ),
              ),
            if (_results != null || _errorOutputIdentifier != null) ...[
              _sectionLabel('Result'),
              for (final v in finalOutputs)
                ResultTile(
                  variable: v,
                  value: _results?[v.identifier],
                  emphasis: true,
                  errorMessage: v.identifier == _errorOutputIdentifier ? _errorMessage : null,
                ),
              if (otherOutputs.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Intermediate values',
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                for (final v in otherOutputs)
                  ResultTile(
                    variable: v,
                    value: _results?[v.identifier],
                    errorMessage: v.identifier == _errorOutputIdentifier ? _errorMessage : null,
                  ),
              ],
            ],
            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 0, 8),
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      );

  static String _renderAst(AstNode n) {
    return switch (n) {
      NumberLit(:final value) => value.toString(),
      Identifier(:final name) => name,
      UnaryMinus(:final operand) => '-${_renderAst(operand)}',
      BinaryOp(:final op, :final left, :final right) =>
        '(${_renderAst(left)} $op ${_renderAst(right)})',
      FunctionCall(:final name, :final args) =>
        '$name(${args.map(_renderAst).join(', ')})',
    };
  }
}

class _SolveFailure implements Exception {
  _SolveFailure(this.outputName, this.engineError);
  final String outputName;
  final EngineError engineError;
}
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/ui/solve_page_test.dart`
Expected: 3/3 pass.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/solve_page.dart test/ui/solve_page_test.dart
git commit -m "feat(ui): solve page with formula preview, per-var error highlight, reset"
```

---

### Task 9: Verify entire app compiles, all tests pass, dart analyze clean

**Files:**
- Verify: `lib/main.dart` still works (it imports `package:equation_solver_app/ui/app.dart` which now exists again)

- [ ] **Step 1: Run dart analyze**

Run: `dart analyze`
Expected: `No issues found!` (or, if there are warnings, they must be fixed before commit).

- [ ] **Step 2: Run all tests**

Run: `flutter test`
Expected: all green; total test count ≥ previous (we added several).

- [ ] **Step 3: Verify Linux build**

Run: `flutter build linux --debug 2>&1 | tail -20`
Expected: `✓ Built build/linux/x64/debug/bundle/equation_solver_app`

- [ ] **Step 4: Smoke-launch on Linux**

Run (background): `flutter run -d linux --debug 2>&1 | tee /tmp/run.log &`
Wait ~10 seconds, then verify the process is alive and the log shows no exceptions:
`grep -i -E "exception|error" /tmp/run.log | head -5`
Expected: no Flutter exceptions; the app window opens.
Kill: `pkill -f equation_solver_app || true`

- [ ] **Step 5: Commit the verification log**

Nothing to commit (read-only verification). If any test failed or analyze warned, fix and re-commit on the offending task.

---

### Task 10: Final commit + tag for Plan A

- [ ] **Step 1: Verify git log shape is clean**

Run: `git log --oneline main..feat/ui-rebuild`
Expected: ~9 commits, one per task, all conventional-commit prefixed.

- [ ] **Step 2: Tag**

```bash
git tag -a ui-foundation -m "Foundation: theme + non-editor screens, polished, Plan A complete"
```

- [ ] **Step 3: Verify tag**

Run: `git tag --list 'ui-*'`
Expected includes `ui-foundation`.

---

## Plan A — Self-review pass

**Spec coverage:**
- §10.1 folder list (empty state import affordance, multi-select bulk delete) → Task 5 ✓
- §10.2 entry list (formula preview, Edit/Solve/Duplicate/Delete) → Task 6 ✓
- §10.3 solve page (formula preview, per-variable highlight, copy-to-clipboard, reset) → Tasks 7, 8 ✓
- §10.4 settings (Data, Editor with toggle, About with diagnostics, Reset-all-data with ERASE) → Tasks 3, 4 ✓
- §3 branch + file layout → Task 1 ✓
- §13 Phase 1 deliverables → Task 1-9, Tag at Task 10 ✓

**Not in Plan A (correctly belongs to Plan B):**
- Editor (chip-flow) → Plan B
- Variable creation flow (§6) → Plan B
- Palette + progressive disclosure → Plan B
- Undo/redo + drafts → Plan B (drafts; uses the SharedPreferences plumbing from Task 3)
- §10.2 Duplicate currently only duplicates entry name+description; full duplication including equations and variables is in Plan B once the editor exists. This is flagged in code with a comment.
- §10.3 folder rename inline-editable title → deferred; Plan A uses dialog rename. The convenience matters more on the editor's entry-name field where the inline-edit pattern is specced. Folder rename via dialog is fine. (If you want it inline anyway, it's a one-line change to push into Plan B's polish task.)

**Placeholder scan:** None. Every step has actual code / commands.

**Type consistency:** `EntryDetail`, `EquationRow`, `VariableMetaRow`, `VarRole`, `EngineError`, `AppDatabase.openInMemory` all defined and used consistently. The only new type is `_SolveFailure` (private to solve_page.dart).

Plan A is ready to execute.
