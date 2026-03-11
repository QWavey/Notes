// Web implementation — path_provider not needed on web
Future<String> getDocsDir() async {
  return ''; // Hive on web uses IndexedDB, no path required
}
