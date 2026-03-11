import 'package:flutter/widgets.dart';

class AppLocalizations {
  final Locale locale;
  const AppLocalizations(this.locale);

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  bool get _isGerman => locale.languageCode == 'de';

  String get appTitle => _isGerman ? 'Notizen' : 'Notes';
  String get notebooks => _isGerman ? 'Notizbücher' : 'Notebooks';
  String get newNotebook => _isGerman ? 'Neues Notizbuch' : 'New Notebook';
  String get notebookName => _isGerman ? 'Name' : 'Name';
  String get rename => _isGerman ? 'Umbenennen' : 'Rename';
  String get delete => _isGerman ? 'Löschen' : 'Delete';
  String get cancel => _isGerman ? 'Abbrechen' : 'Cancel';
  String get create => _isGerman ? 'Erstellen' : 'Create';
  String get save => _isGerman ? 'Speichern' : 'Save';
  String get ok => 'OK';
  String get color => _isGerman ? 'Farbe' : 'Color';
  String get paperType => _isGerman ? 'Papiertyp' : 'Paper Type';
  String get defaultPaperType =>
      _isGerman ? 'Standard-Papiertyp' : 'Default Paper Type';
  String get addPage => _isGerman ? 'Seite hinzufügen' : 'Add Page';
  String get deletePage => _isGerman ? 'Seite löschen' : 'Delete Page';
  String get renamePage => _isGerman ? 'Seite umbenennen' : 'Rename Page';
  String get pageName => _isGerman ? 'Seitenname' : 'Page Name';
  String get draw => _isGerman ? 'Zeichnen' : 'Draw';
  String get document => _isGerman ? 'Dokument' : 'Document';
  String get textBox => _isGerman ? 'Textfeld' : 'Text Box';
  String get table => _isGerman ? 'Tabelle' : 'Table';
  String get pen => _isGerman ? 'Stift' : 'Pen';
  String get eraser => _isGerman ? 'Radierer' : 'Eraser';
  String get move => _isGerman ? 'Verschieben' : 'Move';
  String get shape => _isGerman ? 'Form' : 'Shape';
  String get lasso => _isGerman ? 'Lasso' : 'Lasso';
  String get undo => _isGerman ? 'Rückgängig' : 'Undo';
  String get redo => _isGerman ? 'Wiederholen' : 'Redo';
  String get clearAll => _isGerman ? 'Alles löschen' : 'Clear All';
  String get importImage => _isGerman ? 'Bild importieren' : 'Import Image';
  String get exportShare => _isGerman ? 'Exportieren' : 'Export / Share';
  String get fullscreen => _isGerman ? 'Vollbild' : 'Fullscreen';
  String get exitFullscreen =>
      _isGerman ? 'Vollbild verlassen' : 'Exit Fullscreen';
  String get settings => _isGerman ? 'Einstellungen' : 'Settings';
  String get settingsStub =>
      _isGerman ? 'Einstellungen (demnächst)' : 'Settings (coming soon)';
  String get strokeMode => _isGerman ? 'Strich' : 'Stroke';
  String get circleMode => _isGerman ? 'Kreis' : 'Circle';
  String get eraserMode => _isGerman ? 'Radiermodus' : 'Eraser Mode';
  String get strokeWidth => _isGerman ? 'Stiftbreite' : 'Stroke Width';
  String get eraserSize => _isGerman ? 'Radiergröße' : 'Eraser Size';
  String get addTextBox => _isGerman ? 'Textfeld hinzufügen' : 'Add Text Box';
  String get fontSize => _isGerman ? 'Schriftgröße' : 'Font Size';
  String get bold => 'Bold';
  String get italic => 'Italic';
  String get pageSize => _isGerman ? 'Seitengröße' : 'Page Size';
  String get fontFamily => _isGerman ? 'Schriftart' : 'Font Family';
  String get confirmDelete =>
      _isGerman ? 'Wirklich löschen?' : 'Confirm delete?';
  String get deleteNotebookConfirm =>
      _isGerman ? 'Notizbuch löschen?' : 'Delete this notebook?';
  String get deletePageConfirm =>
      _isGerman ? 'Seite löschen?' : 'Delete this page?';
  String get importExportPages =>
      _isGerman ? 'Import/Export' : 'Import/Export';
  String get prevPage => _isGerman ? 'Vorherige' : 'Previous';
  String get nextPage => _isGerman ? 'Nächste' : 'Next';
  String get quickNote => _isGerman ? 'Schnellnotiz' : 'Quick Note';
}

class AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      ['en', 'de'].contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) async =>
      AppLocalizations(locale);

  @override
  bool shouldReload(AppLocalizationsDelegate old) => false;
}
