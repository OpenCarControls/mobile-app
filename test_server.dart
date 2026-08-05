import 'package:flutter_inappwebview/flutter_inappwebview.dart';
void main() {
  final server = InAppLocalhostServer();
  print(server.documentRoot);
}
