import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../../core/services/google_sheets_service.dart';
import '../../../core/widgets/ss.dart';

/// Google's own file picker, so people can choose any sheet in their Drive.
///
/// Picking a sheet grants ScanSheet drive.file access to it, so it shows in
/// [GoogleSheetsService.listSpreadsheets] from then on and never needs
/// picking again. This is what lets the app skip the restricted
/// drive.metadata.readonly scope. Android has no native picker, so it runs
/// in a web view. Pops with the picked [SpreadsheetInfo], or null.
class DrivePickerScreen extends StatefulWidget {
  const DrivePickerScreen({super.key});

  static Future<SpreadsheetInfo?> open(BuildContext context) =>
      Navigator.push<SpreadsheetInfo>(
        context,
        MaterialPageRoute(builder: (_) => const DrivePickerScreen()),
      );

  @override
  State<DrivePickerScreen> createState() => _DrivePickerScreenState();
}

// A browser key restricted to the Google Picker API and to [_origin] as the
// HTTP referrer, so it is safe to ship in the app.
const _apiKey = 'AIzaSyBaoQB8OCUA5c-I2-cylAsukUasd2sumVg';
// The Cloud project number: picked files are granted to this project's app.
const _appId = '1099311415728';
// The page's origin. The picker posts back to it, and the key allows it.
const _origin = 'https://scansheet-496017.firebaseapp.com';

class _DrivePickerScreenState extends State<DrivePickerScreen> {
  WebViewController? _controller;
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    setState(() {
      _ready = false;
      _error = null;
    });
    if (_apiKey.isEmpty) {
      setState(() => _error = 'Picking from Drive isn’t set up yet.');
      return;
    }
    final String token;
    try {
      token = await GoogleSheetsService.instance.accessToken();
    } on GSheetsException {
      if (mounted) {
        setState(() => _error = 'Sign in to Google again to pick a sheet.');
      }
      return;
    }
    if (!mounted) return;
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(context.ss.paper)
      ..addJavaScriptChannel('ScanSheet', onMessageReceived: _onMessage)
      ..setNavigationDelegate(
        NavigationDelegate(
          onWebResourceError: (e) {
            if (e.isForMainFrame ?? true) _fail();
          },
        ),
      );
    // The picker's iframe on docs.google.com needs its own cookies.
    final platform = controller.platform;
    if (platform is AndroidWebViewController) {
      await AndroidWebViewCookieManager(
        const PlatformWebViewCookieManagerCreationParams(),
      ).setAcceptThirdPartyCookies(platform, true);
    }
    await controller.loadHtmlString(_html(token), baseUrl: _origin);
    if (mounted) setState(() => _controller = controller);
  }

  void _fail() {
    if (mounted) {
      setState(
        () => _error = 'Couldn’t open Google Drive. Check your connection.',
      );
    }
  }

  void _onMessage(JavaScriptMessage message) {
    final msg = jsonDecode(message.message) as Map<String, dynamic>;
    switch (msg['type']) {
      case 'ready':
        setState(() => _ready = true);
      case 'picked':
        Navigator.pop(
          context,
          SpreadsheetInfo(
            id: msg['id'] as String,
            title: (msg['name'] as String?) ?? 'Untitled',
          ),
        );
      case 'cancel':
        Navigator.pop(context);
      default:
        _fail();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    return Scaffold(
      backgroundColor: c.paper,
      body: SafeArea(
        child: _error != null
            ? _errorView(c)
            : Stack(
                children: [
                  if (_controller != null)
                    WebViewWidget(controller: _controller!),
                  if (!_ready)
                    Center(child: CircularProgressIndicator(color: c.emerald)),
                ],
              ),
      ),
    );
  }

  Widget _errorView(SsColors c) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(LucideIcons.cloudOff, size: 36, color: c.muted),
        const SizedBox(height: 14),
        Text(
          _error!,
          textAlign: TextAlign.center,
          style: SsText.body(color: c.ink2),
        ),
        const SizedBox(height: 20),
        if (_apiKey.isNotEmpty) ...[
          SsButton('Try again', onPressed: _start),
          const SizedBox(height: 8),
        ],
        SsButton.secondary('Close', onPressed: () => Navigator.pop(context)),
      ],
    ),
  );
}

String _html(String token) =>
    '''
<!doctype html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>html, body { margin: 0; height: 100%; background: transparent; }</style>
</head>
<body>
<script>
  function post(msg) { ScanSheet.postMessage(JSON.stringify(msg)); }
  function onLoaded() {
    gapi.load('picker', { callback: show, onerror: function () { post({ type: 'error' }); } });
  }
  function show() {
    var view = new google.picker.DocsView(google.picker.ViewId.SPREADSHEETS)
      .setMode(google.picker.DocsViewMode.LIST);
    new google.picker.PickerBuilder()
      .setAppId(${jsonEncode(_appId)})
      .setOAuthToken(${jsonEncode(token)})
      .setDeveloperKey(${jsonEncode(_apiKey)})
      .setOrigin(${jsonEncode(_origin)})
      .addView(view)
      .enableFeature(google.picker.Feature.NAV_HIDDEN)
      .setTitle('Choose a spreadsheet')
      .setSize(window.innerWidth, window.innerHeight)
      .setCallback(function (data) {
        var action = data[google.picker.Response.ACTION];
        if (action === google.picker.Action.PICKED) {
          var doc = data[google.picker.Response.DOCUMENTS][0];
          post({
            type: 'picked',
            id: doc[google.picker.Document.ID],
            name: doc[google.picker.Document.NAME]
          });
        } else if (action === google.picker.Action.CANCEL) {
          post({ type: 'cancel' });
        } else if (action === google.picker.Action.LOADED) {
          post({ type: 'ready' });
        }
      })
      .build()
      .setVisible(true);
  }
</script>
<script src="https://apis.google.com/js/api.js" onload="onLoaded()"
  onerror="post({ type: 'error' })"></script>
</body>
</html>
''';
