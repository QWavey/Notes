import 'package:hive/hive.dart';
import 'enums.dart';

class Notebook extends HiveObject {
  String id;
  String name;
  int colorValue;
  int paperTypeIndex;
  DateTime createdAt;

  Notebook({
    required this.id,
    required this.name,
    required this.colorValue,
    required this.paperTypeIndex,
    required this.createdAt,
  });

  PaperType get paperType => PaperType.values[paperTypeIndex];
  set paperType(PaperType t) => paperTypeIndex = t.index;
}

class NotebookAdapter extends TypeAdapter<Notebook> {
  @override
  final int typeId = 0;

  @override
  Notebook read(BinaryReader reader) {
    return Notebook(
      id: reader.readString(),
      name: reader.readString(),
      colorValue: reader.readInt(),
      paperTypeIndex: reader.readInt(),
      createdAt: DateTime.fromMillisecondsSinceEpoch(reader.readInt()),
    );
  }

  @override
  void write(BinaryWriter writer, Notebook obj) {
    writer.writeString(obj.id);
    writer.writeString(obj.name);
    writer.writeInt(obj.colorValue);
    writer.writeInt(obj.paperTypeIndex);
    writer.writeInt(obj.createdAt.millisecondsSinceEpoch);
  }
}
