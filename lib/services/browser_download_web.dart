import 'package:web/web.dart' as web;

void saveBrowserDownload(String downloadUrl, String fileName) {
  final url = Uri.parse(downloadUrl);
  if (url.hasScheme ||
      url.hasAuthority ||
      !url.path.startsWith('/api/files/browser-download/')) {
    throw ArgumentError('Invalid browser download URL');
  }
  final anchor = web.HTMLAnchorElement()
    ..href = downloadUrl
    ..download = fileName
    ..style.display = 'none';
  try {
    web.document.body!.appendChild(anchor);
    anchor.click();
  } finally {
    anchor.remove();
  }
}
