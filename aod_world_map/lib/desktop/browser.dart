import 'dart:io';

/// Opens [url] in the default browser. Errors come back through the future,
/// so sign-in can report them; callers that don't care can `.ignore()` it.
Future<void> openInBrowser(String url) async {
  if (!Platform.isWindows) return;
  await Process.start('rundll32', ['url.dll,FileProtocolHandler', url], mode: ProcessStartMode.detached);
}
