# Tasks

## GitHub issues (synced 2026-10-24)

Source: QWavey/Notes issue #1, "[Audit] Bugs and improvements (2026-10-20)". It is the only open issue. Every bullet of the issue is one item below. Where the issue lists the same defect twice, the repeat is marked as a duplicate and shares the fix of the first entry.

Not verified in this pass: Gradle and Flutter builds (not run by instruction), Kotlin compilation, and on-device behaviour. Dart files were checked with `dart format` (parse only).

### Security hygiene

- [ ] #1 Release build signed with the debug keystore — android/app/build.gradle.kts:32 — FIX — open
- [ ] #1 FileProvider maps whole storage roots — android/app/src/main/res/xml/file_provider_paths.xml:3-6 — FIX — open
- [ ] #1 Note data stored unencrypted in Hive — lib/services/storage_service.dart:34-38 — SKIP — encryption at rest is a feature (key storage, new dependency) and the issue makes it conditional on a confidentiality requirement that is not stated
- [ ] #1 App data backup not disabled — android/app/src/main/AndroidManifest.xml:10-14 — FIX — open
- [ ] #1 Note titles used unsanitized in file names — lib/services/export_service.dart:65, 91, 96 — FIX — open
- [ ] #1 Generated Gradle report is committed — android/build/reports/problems/problems-report.html — FIX — open

### Bugs

- [ ] #1 LowLatencyDrawingView shares stroke lists between UI and render threads — android/app/src/main/kotlin/com/example/notes/LowLatencyDrawingView.kt:42-43, 95, 114, 124, 145, 181-190, 193, 301-303, 386, 394-425 — FIX — open
- [ ] #1 Overlay data silently wiped when a page's canvas JSON fails to parse — lib/services/storage_service.dart:132-140, 144-156; lib/models/canvas_item.dart:252-265 — FIX — open
- [ ] #1 PDF share and save confirmations dropped after the export dialog closes — lib/services/export_service.dart:148-151, 173-178, 64-66, 99-101 — FIX — open
- [ ] #1 Canvas stops drawing and hides existing strokes after surface recreation — android/app/src/main/kotlin/com/example/notes/LowLatencyDrawingView.kt:220-227, 312-317, 320-321, 342-350, 356-361, 62-65 — FIX — open
- [ ] #1 JPG export writes PNG data under a .jpg name — lib/services/export_service.dart:42, 80, 90-91, 96-97, 131 — FIX — open
- [ ] #1 Deleting a notebook clears its trash marker before the data is removed — lib/services/storage_service.dart:92-102 — FIX — open
- [ ] #1 Deleting a page leaves its rich-text span data behind — lib/services/storage_service.dart:118-123, 169-175 — FIX — open
- [ ] #1 Unsaved canvas edits can be lost on autosave failure or when leaving a page — lib/canvas/canvas_page.dart:59-60, 64-71, 75-80 — FIX — open
- [ ] #1 Storage init failure crashes startup with no fallback — lib/main.dart:9-12 — FIX — open
- [ ] #1 TableItem.fromJson bypasses the default rows x cols grid — lib/models/canvas_item.dart:183-194, 212-224 — FIX — open

### Improvements

- [ ] #1 Duplicate of the JPG bug above: JPG export saves PNG bytes under a .jpg name — lib/services/export_service.dart:42 — FIX — open
- [ ] #1 Duplicate of the overlay wipe bug above: one malformed canvas item can wipe the whole page overlay — lib/services/storage_service.dart:148 — FIX — open
- [ ] #1 Duplicate of the surface recreation bug above: cached GL program is not reset when the surface is recreated — android/app/src/main/kotlin/com/example/notes/LowLatencyDrawingView.kt:62 — FIX — open
- [ ] #1 Duplicate of the thread bug above: completedStrokes is mutated and iterated across threads without locking — android/app/src/main/kotlin/com/example/notes/LowLatencyDrawingView.kt:42 — FIX — open
- [ ] #1 Duplicate of the export confirmation bug above: PDF export can silently do nothing after the dialog closes — lib/services/export_service.dart:149 — FIX — open
- [ ] #1 Duplicate of the span data bug above: deleting a page leaves rich-text span data behind — lib/services/storage_service.dart:118 — FIX — open
- [ ] #1 DrawModeState is a 3,000-plus-line class with duplicated feature state — lib/canvas/draw_mode.dart:86 — SKIP — refactor with no defect described. The DrawSettings.ultraLowLatency setter at draw_mode.dart:39-40 is a no-op on purpose (the getter is fixed to true, commented "ALWAYS ON")
- [ ] #1 Settings and app-root logic are tangled into the detail screen — lib/screens/notebook_detail_screen.dart:258 — SKIP — refactor with no defect described
- [ ] #1 Widget test name and assertion do not match, and it writes to the working directory — test/widget_test.dart:8 — FIX — open
- [ ] #1 Codegen is undeclared and build output is tracked — pubspec.yaml:46 — FIX — open (partly: tracked build output and scratch files are untracked; the codegen dev dependencies and the share_plus pin are left as they are, since choosing matching versions needs a pub resolution this pass does not run)
