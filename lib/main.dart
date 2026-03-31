import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'app_localizations.dart';
import 'theme/app_theme.dart';
import 'screens/notebooks_screen.dart';
import 'screens/notebook_detail_screen.dart';
import 'services/storage_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await StorageService().init();
  runApp(const NotesApp());
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