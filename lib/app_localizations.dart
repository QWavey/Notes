import 'package:flutter/widgets.dart';

// Full multi-language support: en, de, fr, es, it, pt, nl, pl, ru, ja, zh, ko, ar
class AppLocalizations {
  final Locale locale;
  const AppLocalizations(this.locale);

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  String get _lang => locale.languageCode;

  String _t(Map<String, String> m) => m[_lang] ?? m['en']!;

  String get appTitle => _t({'en': 'Notes', 'de': 'Notizen', 'fr': 'Notes',
    'es': 'Notas', 'it': 'Note', 'pt': 'Notas', 'nl': 'Notities',
    'pl': 'Notatki', 'ru': 'Заметки', 'ja': 'ノート', 'zh': '笔记', 'ko': '노트', 'ar': 'ملاحظات'});

  String get notebooks => _t({'en': 'Notebooks', 'de': 'Notizbücher', 'fr': 'Carnets',
    'es': 'Cuadernos', 'it': 'Quaderni', 'pt': 'Cadernos', 'nl': 'Notitieboeken',
    'pl': 'Zeszyty', 'ru': 'Блокноты', 'ja': 'ノートブック', 'zh': '笔记本', 'ko': '노트북', 'ar': 'دفاتر'});

  String get newNotebook => _t({'en': 'New Notebook', 'de': 'Neues Notizbuch', 'fr': 'Nouveau carnet',
    'es': 'Nuevo cuaderno', 'it': 'Nuovo quaderno', 'pt': 'Novo caderno', 'nl': 'Nieuw notitieboek',
    'pl': 'Nowy zeszyt', 'ru': 'Новый блокнот', 'ja': '新しいノート', 'zh': '新笔记本', 'ko': '새 노트북', 'ar': 'دفتر جديد'});

  String get notebookName => _t({'en': 'Name', 'de': 'Name', 'fr': 'Nom',
    'es': 'Nombre', 'it': 'Nome', 'pt': 'Nome', 'nl': 'Naam',
    'pl': 'Nazwa', 'ru': 'Название', 'ja': '名前', 'zh': '名称', 'ko': '이름', 'ar': 'اسم'});

  String get rename => _t({'en': 'Rename', 'de': 'Umbenennen', 'fr': 'Renommer',
    'es': 'Renombrar', 'it': 'Rinomina', 'pt': 'Renomear', 'nl': 'Hernoemen',
    'pl': 'Zmień nazwę', 'ru': 'Переименовать', 'ja': '名前変更', 'zh': '重命名', 'ko': '이름 변경', 'ar': 'إعادة تسمية'});

  String get delete => _t({'en': 'Delete', 'de': 'Löschen', 'fr': 'Supprimer',
    'es': 'Eliminar', 'it': 'Elimina', 'pt': 'Excluir', 'nl': 'Verwijderen',
    'pl': 'Usuń', 'ru': 'Удалить', 'ja': '削除', 'zh': '删除', 'ko': '삭제', 'ar': 'حذف'});

  String get cancel => _t({'en': 'Cancel', 'de': 'Abbrechen', 'fr': 'Annuler',
    'es': 'Cancelar', 'it': 'Annulla', 'pt': 'Cancelar', 'nl': 'Annuleren',
    'pl': 'Anuluj', 'ru': 'Отмена', 'ja': 'キャンセル', 'zh': '取消', 'ko': '취소', 'ar': 'إلغاء'});

  String get create => _t({'en': 'Create', 'de': 'Erstellen', 'fr': 'Créer',
    'es': 'Crear', 'it': 'Crea', 'pt': 'Criar', 'nl': 'Aanmaken',
    'pl': 'Utwórz', 'ru': 'Создать', 'ja': '作成', 'zh': '创建', 'ko': '만들기', 'ar': 'إنشاء'});

  String get save => _t({'en': 'Save', 'de': 'Speichern', 'fr': 'Enregistrer',
    'es': 'Guardar', 'it': 'Salva', 'pt': 'Salvar', 'nl': 'Opslaan',
    'pl': 'Zapisz', 'ru': 'Сохранить', 'ja': '保存', 'zh': '保存', 'ko': '저장', 'ar': 'حفظ'});

  String get ok => 'OK';

  String get color => _t({'en': 'Color', 'de': 'Farbe', 'fr': 'Couleur',
    'es': 'Color', 'it': 'Colore', 'pt': 'Cor', 'nl': 'Kleur',
    'pl': 'Kolor', 'ru': 'Цвет', 'ja': '色', 'zh': '颜色', 'ko': '색상', 'ar': 'لون'});

  String get paperType => _t({'en': 'Paper Type', 'de': 'Papiertyp', 'fr': 'Type de papier',
    'es': 'Tipo de papel', 'it': 'Tipo carta', 'pt': 'Tipo de papel', 'nl': 'Papiertype',
    'pl': 'Typ papieru', 'ru': 'Тип бумаги', 'ja': '用紙タイプ', 'zh': '纸张类型', 'ko': '종이 유형', 'ar': 'نوع الورق'});

  String get defaultPaperType => _t({'en': 'Default Paper Type', 'de': 'Standard-Papiertyp', 'fr': 'Papier par défaut',
    'es': 'Papel predeterminado', 'it': 'Carta predefinita', 'pt': 'Papel padrão', 'nl': 'Standaard papier',
    'pl': 'Domyślny typ papieru', 'ru': 'Тип бумаги по умолчанию', 'ja': 'デフォルト用紙', 'zh': '默认纸张', 'ko': '기본 종이 유형', 'ar': 'نوع الورق الافتراضي'});

  String get addPage => _t({'en': 'Add Page', 'de': 'Seite hinzufügen', 'fr': 'Ajouter une page',
    'es': 'Agregar página', 'it': 'Aggiungi pagina', 'pt': 'Adicionar página', 'nl': 'Pagina toevoegen',
    'pl': 'Dodaj stronę', 'ru': 'Добавить страницу', 'ja': 'ページ追加', 'zh': '添加页面', 'ko': '페이지 추가', 'ar': 'إضافة صفحة'});

  String get deletePage => _t({'en': 'Delete Page', 'de': 'Seite löschen', 'fr': 'Supprimer la page',
    'es': 'Eliminar página', 'it': 'Elimina pagina', 'pt': 'Excluir página', 'nl': 'Pagina verwijderen',
    'pl': 'Usuń stronę', 'ru': 'Удалить страницу', 'ja': 'ページ削除', 'zh': '删除页面', 'ko': '페이지 삭제', 'ar': 'حذف الصفحة'});

  String get renamePage => _t({'en': 'Rename Page', 'de': 'Seite umbenennen', 'fr': 'Renommer la page',
    'es': 'Renombrar página', 'it': 'Rinomina pagina', 'pt': 'Renomear página', 'nl': 'Pagina hernoemen',
    'pl': 'Zmień nazwę strony', 'ru': 'Переименовать страницу', 'ja': 'ページ名変更', 'zh': '重命名页面', 'ko': '페이지 이름 변경', 'ar': 'إعادة تسمية الصفحة'});

  String get pageName => _t({'en': 'Page Name', 'de': 'Seitenname', 'fr': 'Nom de la page',
    'es': 'Nombre de página', 'it': 'Nome pagina', 'pt': 'Nome da página', 'nl': 'Paginanaam',
    'pl': 'Nazwa strony', 'ru': 'Имя страницы', 'ja': 'ページ名', 'zh': '页面名称', 'ko': '페이지 이름', 'ar': 'اسم الصفحة'});

  String get draw => _t({'en': 'Draw', 'de': 'Zeichnen', 'fr': 'Dessiner',
    'es': 'Dibujar', 'it': 'Disegna', 'pt': 'Desenhar', 'nl': 'Tekenen',
    'pl': 'Rysuj', 'ru': 'Рисовать', 'ja': '描画', 'zh': '绘制', 'ko': '그리기', 'ar': 'رسم'});

  String get document => _t({'en': 'Document', 'de': 'Dokument', 'fr': 'Document',
    'es': 'Documento', 'it': 'Documento', 'pt': 'Documento', 'nl': 'Document',
    'pl': 'Dokument', 'ru': 'Документ', 'ja': 'ドキュメント', 'zh': '文档', 'ko': '문서', 'ar': 'وثيقة'});

  String get textBox => _t({'en': 'Text Box', 'de': 'Textfeld', 'fr': 'Zone de texte',
    'es': 'Cuadro de texto', 'it': 'Casella di testo', 'pt': 'Caixa de texto', 'nl': 'Tekstvak',
    'pl': 'Pole tekstowe', 'ru': 'Текстовое поле', 'ja': 'テキストボックス', 'zh': '文本框', 'ko': '텍스트 상자', 'ar': 'مربع نص'});

  String get table => _t({'en': 'Table', 'de': 'Tabelle', 'fr': 'Tableau',
    'es': 'Tabla', 'it': 'Tabella', 'pt': 'Tabela', 'nl': 'Tabel',
    'pl': 'Tabela', 'ru': 'Таблица', 'ja': 'テーブル', 'zh': '表格', 'ko': '표', 'ar': 'جدول'});

  String get pen => _t({'en': 'Pen', 'de': 'Stift', 'fr': 'Stylo',
    'es': 'Pluma', 'it': 'Penna', 'pt': 'Caneta', 'nl': 'Pen',
    'pl': 'Długopis', 'ru': 'Ручка', 'ja': 'ペン', 'zh': '钢笔', 'ko': '펜', 'ar': 'قلم'});

  String get eraser => _t({'en': 'Eraser', 'de': 'Radierer', 'fr': 'Gomme',
    'es': 'Borrador', 'it': 'Gomma', 'pt': 'Borracha', 'nl': 'Gum',
    'pl': 'Gumka', 'ru': 'Ластик', 'ja': '消しゴム', 'zh': '橡皮', 'ko': '지우개', 'ar': 'ممحاة'});

  String get move => _t({'en': 'Move', 'de': 'Verschieben', 'fr': 'Déplacer',
    'es': 'Mover', 'it': 'Sposta', 'pt': 'Mover', 'nl': 'Verplaatsen',
    'pl': 'Przesuń', 'ru': 'Переместить', 'ja': '移動', 'zh': '移动', 'ko': '이동', 'ar': 'نقل'});

  String get shape => _t({'en': 'Shape', 'de': 'Form', 'fr': 'Forme',
    'es': 'Forma', 'it': 'Forma', 'pt': 'Forma', 'nl': 'Vorm',
    'pl': 'Kształt', 'ru': 'Фигура', 'ja': '図形', 'zh': '形状', 'ko': '도형', 'ar': 'شكل'});

  String get lasso => _t({'en': 'Lasso', 'de': 'Lasso', 'fr': 'Lasso',
    'es': 'Lazo', 'it': 'Lazo', 'pt': 'Laço', 'nl': 'Lasso',
    'pl': 'Lasso', 'ru': 'Лассо', 'ja': 'なげなわ', 'zh': '套索', 'ko': '올가미', 'ar': 'حبل'});

  String get undo => _t({'en': 'Undo', 'de': 'Rückgängig', 'fr': 'Annuler',
    'es': 'Deshacer', 'it': 'Annulla', 'pt': 'Desfazer', 'nl': 'Ongedaan',
    'pl': 'Cofnij', 'ru': 'Отменить', 'ja': '元に戻す', 'zh': '撤销', 'ko': '실행 취소', 'ar': 'تراجع'});

  String get redo => _t({'en': 'Redo', 'de': 'Wiederholen', 'fr': 'Refaire',
    'es': 'Rehacer', 'it': 'Ripeti', 'pt': 'Refazer', 'nl': 'Opnieuw',
    'pl': 'Ponów', 'ru': 'Повторить', 'ja': 'やり直し', 'zh': '重做', 'ko': '다시 실행', 'ar': 'إعادة'});

  String get clearAll => _t({'en': 'Clear All', 'de': 'Alles löschen', 'fr': 'Tout effacer',
    'es': 'Borrar todo', 'it': 'Cancella tutto', 'pt': 'Limpar tudo', 'nl': 'Alles wissen',
    'pl': 'Wyczyść wszystko', 'ru': 'Очистить всё', 'ja': 'すべて消去', 'zh': '清除全部', 'ko': '모두 지우기', 'ar': 'مسح الكل'});

  String get importImage => _t({'en': 'Import Image', 'de': 'Bild importieren', 'fr': 'Importer image',
    'es': 'Importar imagen', 'it': 'Importa immagine', 'pt': 'Importar imagem', 'nl': 'Afbeelding importeren',
    'pl': 'Importuj obraz', 'ru': 'Импорт изображения', 'ja': '画像インポート', 'zh': '导入图片', 'ko': '이미지 가져오기', 'ar': 'استيراد صورة'});

  String get exportShare => _t({'en': 'Export / Share', 'de': 'Exportieren', 'fr': 'Exporter',
    'es': 'Exportar', 'it': 'Esporta', 'pt': 'Exportar', 'nl': 'Exporteren',
    'pl': 'Eksportuj', 'ru': 'Экспорт', 'ja': 'エクスポート', 'zh': '导出', 'ko': '내보내기', 'ar': 'تصدير'});

  String get fullscreen => _t({'en': 'Fullscreen', 'de': 'Vollbild', 'fr': 'Plein écran',
    'es': 'Pantalla completa', 'it': 'Schermo intero', 'pt': 'Tela cheia', 'nl': 'Volledig scherm',
    'pl': 'Pełny ekran', 'ru': 'На весь экран', 'ja': '全画面', 'zh': '全屏', 'ko': '전체 화면', 'ar': 'ملء الشاشة'});

  String get exitFullscreen => _t({'en': 'Exit Fullscreen', 'de': 'Vollbild verlassen', 'fr': 'Quitter plein écran',
    'es': 'Salir de pantalla completa', 'it': 'Esci da schermo intero', 'pt': 'Sair da tela cheia', 'nl': 'Volledig scherm verlaten',
    'pl': 'Wyjdź z pełnego ekranu', 'ru': 'Выйти из полного экрана', 'ja': '全画面を終了', 'zh': '退出全屏', 'ko': '전체 화면 종료', 'ar': 'الخروج من ملء الشاشة'});

  String get settings => _t({'en': 'Settings', 'de': 'Einstellungen', 'fr': 'Paramètres',
    'es': 'Configuración', 'it': 'Impostazioni', 'pt': 'Configurações', 'nl': 'Instellingen',
    'pl': 'Ustawienia', 'ru': 'Настройки', 'ja': '設定', 'zh': '设置', 'ko': '설정', 'ar': 'إعدادات'});

  String get settingsStub => _t({'en': 'Settings (coming soon)', 'de': 'Einstellungen (demnächst)',
    'fr': 'Paramètres (bientôt)', 'es': 'Configuración (pronto)', 'it': 'Impostazioni (presto)',
    'pt': 'Configurações (em breve)', 'nl': 'Instellingen (binnenkort)', 'pl': 'Ustawienia (wkrótce)',
    'ru': 'Настройки (скоро)', 'ja': '設定（近日公開）', 'zh': '设置（即将推出）', 'ko': '설정 (곧)', 'ar': 'الإعدادات (قريباً)'});

  String get strokeMode => _t({'en': 'Stroke', 'de': 'Strich', 'fr': 'Trait', 'es': 'Trazo',
    'it': 'Tratto', 'pt': 'Traço', 'nl': 'Streek', 'pl': 'Kreska', 'ru': 'Штрих',
    'ja': 'ストローク', 'zh': '描边', 'ko': '획', 'ar': 'خط'});

  String get circleMode => _t({'en': 'Circle', 'de': 'Kreis', 'fr': 'Cercle', 'es': 'Círculo',
    'it': 'Cerchio', 'pt': 'Círculo', 'nl': 'Cirkel', 'pl': 'Okrąg', 'ru': 'Круг',
    'ja': '円', 'zh': '圆形', 'ko': '원', 'ar': 'دائرة'});

  String get eraserMode => _t({'en': 'Eraser Mode', 'de': 'Radiermodus', 'fr': 'Mode gomme',
    'es': 'Modo borrador', 'it': 'Modalità gomma', 'pt': 'Modo borracha', 'nl': 'Gummodus',
    'pl': 'Tryb gumki', 'ru': 'Режим ластика', 'ja': '消しゴムモード', 'zh': '橡皮模式', 'ko': '지우개 모드', 'ar': 'وضع الممحاة'});

  String get strokeWidth => _t({'en': 'Stroke Width', 'de': 'Stiftbreite', 'fr': 'Épaisseur',
    'es': 'Grosor', 'it': 'Spessore', 'pt': 'Espessura', 'nl': 'Lijndikte',
    'pl': 'Grubość', 'ru': 'Толщина', 'ja': '線幅', 'zh': '线宽', 'ko': '선 굵기', 'ar': 'عرض الخط'});

  String get eraserSize => _t({'en': 'Eraser Size', 'de': 'Radiergröße', 'fr': 'Taille gomme',
    'es': 'Tamaño borrador', 'it': 'Dimensione gomma', 'pt': 'Tamanho borracha', 'nl': 'Gumgrootte',
    'pl': 'Rozmiar gumki', 'ru': 'Размер ластика', 'ja': '消しゴムサイズ', 'zh': '橡皮大小', 'ko': '지우개 크기', 'ar': 'حجم الممحاة'});

  String get addTextBox => _t({'en': 'Add Text Box', 'de': 'Textfeld hinzufügen', 'fr': 'Ajouter zone texte',
    'es': 'Agregar cuadro', 'it': 'Aggiungi casella', 'pt': 'Adicionar caixa', 'nl': 'Tekstvak toevoegen',
    'pl': 'Dodaj pole tekstowe', 'ru': 'Добавить текстовое поле', 'ja': 'テキストボックス追加', 'zh': '添加文本框', 'ko': '텍스트 상자 추가', 'ar': 'إضافة مربع نص'});

  String get fontSize => _t({'en': 'Font Size', 'de': 'Schriftgröße', 'fr': 'Taille police',
    'es': 'Tamaño fuente', 'it': 'Dimensione font', 'pt': 'Tamanho fonte', 'nl': 'Lettergrootte',
    'pl': 'Rozmiar czcionki', 'ru': 'Размер шрифта', 'ja': 'フォントサイズ', 'zh': '字体大小', 'ko': '글꼴 크기', 'ar': 'حجم الخط'});

  String get bold => _t({'en': 'Bold', 'de': 'Fett', 'fr': 'Gras', 'es': 'Negrita',
    'it': 'Grassetto', 'pt': 'Negrito', 'nl': 'Vet', 'pl': 'Pogrubienie',
    'ru': 'Жирный', 'ja': '太字', 'zh': '粗体', 'ko': '굵게', 'ar': 'عريض'});

  String get italic => _t({'en': 'Italic', 'de': 'Kursiv', 'fr': 'Italique', 'es': 'Cursiva',
    'it': 'Corsivo', 'pt': 'Itálico', 'nl': 'Cursief', 'pl': 'Kursywa',
    'ru': 'Курсив', 'ja': 'イタリック', 'zh': '斜体', 'ko': '기울임', 'ar': 'مائل'});

  String get pageSize => _t({'en': 'Page Size', 'de': 'Seitengröße', 'fr': 'Format de page',
    'es': 'Tamaño de página', 'it': 'Dimensione pagina', 'pt': 'Tamanho da página', 'nl': 'Paginaformaat',
    'pl': 'Rozmiar strony', 'ru': 'Размер страницы', 'ja': 'ページサイズ', 'zh': '页面大小', 'ko': '페이지 크기', 'ar': 'حجم الصفحة'});

  String get fontFamily => _t({'en': 'Font Family', 'de': 'Schriftart', 'fr': 'Police',
    'es': 'Fuente', 'it': 'Font', 'pt': 'Fonte', 'nl': 'Lettertype',
    'pl': 'Czcionka', 'ru': 'Шрифт', 'ja': 'フォント', 'zh': '字体', 'ko': '글꼴', 'ar': 'خط'});

  String get confirmDelete => _t({'en': 'Confirm delete?', 'de': 'Wirklich löschen?', 'fr': 'Confirmer suppression?',
    'es': '¿Confirmar eliminación?', 'it': 'Confermare eliminazione?', 'pt': 'Confirmar exclusão?', 'nl': 'Verwijdering bevestigen?',
    'pl': 'Potwierdzić usunięcie?', 'ru': 'Подтвердить удаление?', 'ja': '削除しますか？', 'zh': '确认删除？', 'ko': '삭제를 확인하시겠어요?', 'ar': 'تأكيد الحذف؟'});

  String get deleteNotebookConfirm => _t({'en': 'Delete this notebook?', 'de': 'Notizbuch löschen?',
    'fr': 'Supprimer ce carnet?', 'es': '¿Eliminar este cuaderno?', 'it': 'Eliminare questo quaderno?',
    'pt': 'Excluir este caderno?', 'nl': 'Dit notitieboek verwijderen?', 'pl': 'Usunąć ten zeszyt?',
    'ru': 'Удалить этот блокнот?', 'ja': 'このノートを削除しますか？', 'zh': '删除此笔记本？', 'ko': '이 노트북을 삭제하시겠어요?', 'ar': 'حذف هذا الدفتر؟'});

  String get deletePageConfirm => _t({'en': 'Delete this page?', 'de': 'Seite löschen?',
    'fr': 'Supprimer cette page?', 'es': '¿Eliminar esta página?', 'it': 'Eliminare questa pagina?',
    'pt': 'Excluir esta página?', 'nl': 'Deze pagina verwijderen?', 'pl': 'Usunąć tę stronę?',
    'ru': 'Удалить эту страницу?', 'ja': 'このページを削除しますか？', 'zh': '删除此页面？', 'ko': '이 페이지를 삭제하시겠어요?', 'ar': 'حذف هذه الصفحة؟'});

  String get importExportPages => _t({'en': 'Import/Export', 'de': 'Import/Export', 'fr': 'Importer/Exporter',
    'es': 'Importar/Exportar', 'it': 'Importa/Esporta', 'pt': 'Importar/Exportar', 'nl': 'Importeren/Exporteren',
    'pl': 'Importuj/Eksportuj', 'ru': 'Импорт/Экспорт', 'ja': 'インポート/エクスポート', 'zh': '导入/导出', 'ko': '가져오기/내보내기', 'ar': 'استيراد/تصدير'});

  String get prevPage => _t({'en': 'Previous', 'de': 'Vorherige', 'fr': 'Précédent',
    'es': 'Anterior', 'it': 'Precedente', 'pt': 'Anterior', 'nl': 'Vorige',
    'pl': 'Poprzednia', 'ru': 'Назад', 'ja': '前へ', 'zh': '上一页', 'ko': '이전', 'ar': 'السابق'});

  String get nextPage => _t({'en': 'Next', 'de': 'Nächste', 'fr': 'Suivant',
    'es': 'Siguiente', 'it': 'Successivo', 'pt': 'Próximo', 'nl': 'Volgende',
    'pl': 'Następna', 'ru': 'Вперёд', 'ja': '次へ', 'zh': '下一页', 'ko': '다음', 'ar': 'التالي'});

  String get quickNote => _t({'en': 'Quick Note', 'de': 'Schnellnotiz', 'fr': 'Note rapide',
    'es': 'Nota rápida', 'it': 'Nota rapida', 'pt': 'Nota rápida', 'nl': 'Snelle notitie',
    'pl': 'Szybka notatka', 'ru': 'Быстрая заметка', 'ja': 'クイックノート', 'zh': '快速笔记', 'ko': '빠른 메모', 'ar': 'ملاحظة سريعة'});

  // Extra strings used in draw_mode / detail screen
  String get showPages => _t({'en': 'Show pages', 'de': 'Seiten anzeigen', 'fr': 'Afficher les pages',
    'es': 'Mostrar páginas', 'it': 'Mostra pagine', 'pt': 'Mostrar páginas', 'nl': 'Pagina\'s weergeven',
    'pl': 'Pokaż strony', 'ru': 'Показать страницы', 'ja': 'ページ表示', 'zh': '显示页面', 'ko': '페이지 보기', 'ar': 'عرض الصفحات'});

  String get hidePages => _t({'en': 'Hide pages', 'de': 'Seiten ausblenden', 'fr': 'Masquer les pages',
    'es': 'Ocultar páginas', 'it': 'Nascondi pagine', 'pt': 'Ocultar páginas', 'nl': 'Pagina\'s verbergen',
    'pl': 'Ukryj strony', 'ru': 'Скрыть страницы', 'ja': 'ページ非表示', 'zh': '隐藏页面', 'ko': '페이지 숨기기', 'ar': 'إخفاء الصفحات'});

  String get fingerDrawing => _t({'en': 'Finger drawing', 'de': 'Fingerzeichnen erlauben',
    'fr': 'Dessin au doigt', 'es': 'Dibujo con dedo', 'it': 'Disegno a dito',
    'pt': 'Desenho com dedo', 'nl': 'Vingertekening', 'pl': 'Rysowanie palcem',
    'ru': 'Рисование пальцем', 'ja': '指描き', 'zh': '手指绘制', 'ko': '손가락 그리기', 'ar': 'الرسم بالإصبع'});
}

class AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => [
    'en','de','fr','es','it','pt','nl','pl','ru','ja','zh','ko','ar'
  ].contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) async =>
      AppLocalizations(locale);

  @override
  bool shouldReload(AppLocalizationsDelegate old) => false;
}
