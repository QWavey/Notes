# Tasks

## GitHub issues (synced 2026-10-24)

Source: QWavey/Notes issue #1, "[Audit] Bugs and improvements (2026-10-20)". It is the only open issue. Every bullet of the issue is one item below. Where the issue lists the same defect twice, the repeat is marked as a duplicate and shares the commit of the first entry.

Verification in this pass: Gradle and Flutter builds were not run (by instruction). Dart files were parse-checked with `dart format` and the XML files were parsed. Kotlin and Gradle were not compiled, and nothing was run on a device or with `flutter test`. Several fixes below are therefore unverified by build.

### Security hygiene

- [x] #1 Release build signed with the debug keystore — android/app/build.gradle.kts:32 — FIX — fixed in f3e74d7. Release uses android/key.properties (already git-ignored) when it exists. Without it, the debug key is still used and Gradle prints a warning.
- [x] #1 FileProvider maps whole storage roots — android/app/src/main/res/xml/file_provider_paths.xml:3-6 — FIX — fixed in 3d5f96a. Only cache/exports/ is exposed now. No code refers to this authority directly.
- [ ] #1 Note data stored unencrypted in Hive — lib/services/storage_service.dart:34-38 — SKIP — encryption at rest is a feature (key storage, new dependency), and the issue makes it conditional on a confidentiality requirement that is not stated
- [x] #1 App data backup not disabled — android/app/src/main/AndroidManifest.xml:10-14 — FIX — fixed in d7b8443. allowBackup="false" is set, so notes are no longer auto-backed up. Revert this if backup is wanted.
- [x] #1 Note titles used unsanitized in file names — lib/services/export_service.dart:65, 91, 96 — FIX — fixed in b812973
- [x] #1 Generated Gradle report is committed — android/build/reports/problems/problems-report.html — FIX — fixed in fc8a8a6. Untracked and ignored. Git history was not rewritten, so the file remains in past commits.

### Bugs

- [x] #1 LowLatencyDrawingView shares stroke lists between UI and render threads — android/app/src/main/kotlin/com/example/notes/LowLatencyDrawingView.kt:42-43, 95, 114, 124, 145, 181-190, 193, 301-303, 386, 394-425 — FIX — fixed in 9d9c3e3. The render thread reads an immutable snapshot. Not device-tested.
- [x] #1 Overlay data silently wiped when a page's canvas JSON fails to parse — lib/services/storage_service.dart:132-140, 144-156; lib/models/canvas_item.dart:252-265 — FIX — fixed in 759d0d0. Valid entries now load, and the original JSON is kept under a "_backup" key before a save can replace it. Problems are logged; there is no in-app message yet.
- [x] #1 PDF share and save confirmations dropped after the export dialog closes — lib/services/export_service.dart:148-151, 173-178, 64-66, 99-101 — FIX — fixed in de60e25
- [x] #1 Canvas stops drawing and hides existing strokes after surface recreation — android/app/src/main/kotlin/com/example/notes/LowLatencyDrawingView.kt:220-227, 312-317, 320-321, 342-350, 356-361, 62-65 — FIX — fixed in 60e0f5b. Not device-tested.
- [x] #1 JPG export writes PNG data under a .jpg name — lib/services/export_service.dart:42, 80, 90-91, 96-97, 131 — FIX — fixed in 1b0e4d0. The JPG option is removed (PNG only). On web the PNG is shared as image/png instead of through the PDF share call.
- [x] #1 Deleting a notebook clears its trash marker before the data is removed — lib/services/storage_service.dart:92-102 — FIX — fixed in 9d82273
- [x] #1 Deleting a page leaves its rich-text span data behind — lib/services/storage_service.dart:118-123, 169-175 — FIX — fixed in 9d82273 (the same commit also adds the span-key delete)
- [x] #1 Unsaved canvas edits can be lost on autosave failure or when leaving a page — lib/canvas/canvas_page.dart:59-60, 64-71, 75-80 — FIX — fixed in 328d34b. Remaining gap outside this item's files: draw_mode.dart:418-419 (saveAll) still swallows errors from the drawing save.
- [x] #1 Storage init failure crashes startup with no fallback — lib/main.dart:9-12 — FIX — fixed in ee265d9. Shows an error screen with a retry button. There is no reset-store option yet.
- [x] #1 TableItem.fromJson bypasses the default rows x cols grid — lib/models/canvas_item.dart:183-194, 212-224 — FIX — fixed in 759d0d0

### Improvements

- [x] #1 Duplicate of the JPG bug above: JPG export saves PNG bytes under a .jpg name — lib/services/export_service.dart:42 — FIX — fixed in 1b0e4d0
- [x] #1 Duplicate of the overlay wipe bug above: one malformed canvas item can wipe the whole page overlay — lib/services/storage_service.dart:148 — FIX — fixed in 759d0d0
- [x] #1 Duplicate of the surface recreation bug above: cached GL program is not reset when the surface is recreated — android/app/src/main/kotlin/com/example/notes/LowLatencyDrawingView.kt:62 — FIX — fixed in 60e0f5b
- [x] #1 Duplicate of the thread bug above: completedStrokes is mutated and iterated across threads without locking — android/app/src/main/kotlin/com/example/notes/LowLatencyDrawingView.kt:42 — FIX — fixed in 9d9c3e3
- [x] #1 Duplicate of the export confirmation bug above: PDF export can silently do nothing after the dialog closes — lib/services/export_service.dart:149 — FIX — fixed in de60e25
- [x] #1 Duplicate of the span data bug above: deleting a page leaves rich-text span data behind — lib/services/storage_service.dart:118 — FIX — fixed in 9d82273
- [ ] #1 DrawModeState is a 3,000-plus-line class with duplicated feature state — lib/canvas/draw_mode.dart:86 — SKIP — refactor with no defect described. The no-op DrawSettings.ultraLowLatency setter (draw_mode.dart:39-40) is deliberate: the getter is fixed to true with the comment "ALWAYS ON".
- [ ] #1 Settings and app-root logic are tangled into the detail screen — lib/screens/notebook_detail_screen.dart:258 — SKIP — refactor with no defect described
- [x] #1 Widget test name and assertion do not match, and it writes to the working directory — test/widget_test.dart:8 — FIX — fixed in 6885f8e. The test checks for NotebooksScreen and uses a temp directory. Not run. The extra unit tests the issue suggests were not added (not a defect fix).
- [ ] #1 Codegen is undeclared and build output is tracked — pubspec.yaml:46 — FIX — open (partly). Tracked build output and scratch files were untracked in fc8a8a6. Left open: the codegen dev dependencies and the exact share_plus pin. Choosing matching versions needs a pub resolution, which was not run.
