import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast_io.dart';

/// Abre um banco sembast em arquivo no diretório de documentos do app.
Future<Database> openAppDatabase(String name) async {
  final dir = await getApplicationSupportDirectory();
  return databaseFactoryIo.openDatabase('${dir.path}/$name');
}

Future<void> deleteAppDatabase(String name) async {
  final dir = await getApplicationSupportDirectory();
  await databaseFactoryIo.deleteDatabase('${dir.path}/$name');
}
