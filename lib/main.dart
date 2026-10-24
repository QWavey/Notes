import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'app_localizations.dart';
import 'theme/app_theme.dart';
import 'screens/notebooks_screen.dart';
import 'screens/notebook_detail_screen.dart';
import 'services/storage_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await StorageService().init();
  } catch (e, st) {
    // Show an error screen with a retry button instead of exiting before any UI.
    debugPrint('Storage init failed: $e\n$st');
    runApp(StartupErrorApp(error: e));
    return;
  }
  runApp(const NotesApp());
}

/// Shown when the local note store cannot be opened.
class StartupErrorApp extends StatefulWidget {
  final Object error;
  const StartupErrorApp({super.key, required this.error});

  @override
  State<StartupErrorApp> createState() => _StartupErrorAppState();
}

class _StartupErrorAppState extends State<StartupErrorApp> {
  late Object _error = widget.error;
  bool _retrying = false;

  Future<void> _retry() async {
    setState(() => _retrying = true);
    try {
      await StorageService().init();
    } catch (e, st) {
      debugPrint('Storage init retry failed: $e\n$st');
      if (mounted) {
        setState(() {
          _error = e;
          _retrying = false;
        });
      }
      return;
    }
    runApp(const NotesApp());
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Notes',
      theme: AppTheme.theme,
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48),
                const SizedBox(height: 16),
                const Text(
                  'Die lokalen Notizen konnten nicht geöffnet werden.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 8),
                Text(
                  '$_error',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _retrying ? null : _retry,
                  child: Text(_retrying ? 'Wird geprüft...' : 'Erneut versuchen'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class NotesApp extends StatefulWidget {
  const NotesApp({super.key});

  static void rebuildApp() {
    _NotesAppState._rebuildCallback?.call();
  }

  @override
  State<NotesApp> createState() => _NotesAppState();
}

class _NotesAppState extends State<NotesApp> {
  static void Function()? _rebuildCallback;

  @override
  void initState() {
    super.initState();
    _rebuildCallback = () {
      if (mounted) {
        setState(() {});
      }
    };
  }

  @override
  void dispose() {
    _rebuildCallback = null;
    super.dispose();
  }

  static const _supportedLocales = [
    Locale('en'),
    Locale('de'),
    Locale('fr'),
    Locale('es'),
    Locale('it'),
    Locale('pt'),
    Locale('nl'),
    Locale('pl'),
    Locale('ru'),
    Locale('ja'),
    Locale('zh'),
    Locale('ko'),
    Locale('ar'),
  ];

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Notes',
      theme: AppTheme.theme,
      debugShowCheckedModeBanner: false,
      locale: AppSettings.instance.overrideLocale,
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: _supportedLocales,
      home: const NotebooksScreen(),
    );
  }
}