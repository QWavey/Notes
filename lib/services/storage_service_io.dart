// IO (desktop/mobile) implementation
import 'package:path_provider/path_provider.dart';

Future<String> getDocsDir() async {
  final dir = await getApplicationDocumentsDirectory();
  return dir.path;
}
