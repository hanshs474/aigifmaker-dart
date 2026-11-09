import 'dart:io';

import 'package:aigifmaker/aigifmaker.dart';

Future<void> main() async {
  final gif = Aigifmaker(); // reads AIGIFMAKER_API_KEY
  try {
    print(await gif
        .generate('a corgi in sunglasses dancing on a beach, looping'));
  } on AigifmakerException catch (e) {
    stderr.writeln(e);
    exitCode = 1;
  } finally {
    gif.close();
  }
}
