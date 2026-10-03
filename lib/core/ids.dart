import 'dart:math';

final _rng = Random.secure();

/// Gera identificadores únicos (timestamp + aleatório), ordenáveis por criação.
String newId([String prefix = '']) {
  final ts = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final rnd = List.generate(
    8,
    (_) => _rng.nextInt(36).toRadixString(36),
  ).join();
  return '$prefix$ts$rnd';
}
