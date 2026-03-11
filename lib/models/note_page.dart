import 'package:hive/hive.dart';
import 'enums.dart';

class NotePage extends HiveObject {
  String id;
  String notebookId;
  String name;
  int order;
  int paperTypeIndex;
  String documentText;
  DateTime createdAt;

  NotePage({
    required this.id,
    required this.notebookId,
    required this.name,
    required this.order,
    required this.paperTypeIndex,
    this.documentText = '',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  PaperType get paperType => PaperType.values[paperTypeIndex];
  set paperType(PaperType t) => paperTypeIndex = t.index;
}

class NotePageAdapter extends TypeAdapter<NotePage> {
  @override
  final int typeId = 1;

  @override
  NotePage read(BinaryReader reader) {
    final id = reader.readString();
    final notebookId = reader.readString();
    final name = reader.readString();
    final order = reader.readInt();
    final paperTypeIndex = reader.readInt();
    final documentText = reader.readString();
    // createdAt added later — read with fallback
    DateTime createdAt = DateTime.now();
    try {
      createdAt = DateTime.fromMillisecondsSinceEpoch(reader.readInt());
    } catch (_) {}
    return NotePage(
      id: id,
      notebookId: notebookId,
      name: name,
      order: order,
      paperTypeIndex: paperTypeIndex,
      documentText: documentText,
      createdAt: createdAt,
    );
  }

  @override
  void write(BinaryWriter writer, NotePage obj) {
    writer.writeString(obj.id);
    writer.writeString(obj.notebookId);
    writer.writeString(obj.name);
    writer.writeInt(obj.order);
    writer.writeInt(obj.paperTypeIndex);
    writer.writeString(obj.documentText);
    writer.writeInt(obj.createdAt.millisecondsSinceEpoch);
  }
}
