import 'package:sembast_web/sembast_web.dart';

/// Abre um banco sembast persistido no IndexedDB do navegador.
Future<Database> openAppDatabase(String name) =>
    databaseFactoryWeb.openDatabase(name);

Future<void> deleteAppDatabase(String name) =>
    databaseFactoryWeb.deleteDatabase(name);
