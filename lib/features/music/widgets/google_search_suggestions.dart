import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Gemini の検索グラウンディングが返す「Google 検索の候補」。
///
/// 規約で、検索結果を見せるときは Google が返した HTML をそのまま表示することになっているため
/// WebView で描く。候補を押したら外部のブラウザで Google 検索を開く。
class GoogleSearchSuggestions extends StatefulWidget {
  const GoogleSearchSuggestions({super.key, required this.html});

  final String html;

  static const double height = 56;

  @override
  State<GoogleSearchSuggestions> createState() =>
      _GoogleSearchSuggestionsState();
}

class _GoogleSearchSuggestionsState extends State<GoogleSearchSuggestions> {
  WebViewController? _controller;

  @override
  void initState() {
    super.initState();
    // テストなど WebView のない環境では何も出さない
    if (WebViewPlatform.instance == null) return;
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.disabled)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(onNavigationRequest: _onNavigationRequest),
      );
    _load();
  }

  @override
  void didUpdateWidget(GoogleSearchSuggestions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.html != widget.html) _load();
  }

  void _load() {
    _controller?.loadHtmlString(
      '<!DOCTYPE html><html><head>'
      '<meta name="viewport" content="width=device-width, initial-scale=1">'
      '<style>html,body{margin:0;padding:0;background:transparent;}</style>'
      '</head><body>${widget.html}</body></html>',
    );
  }

  NavigationDecision _onNavigationRequest(NavigationRequest request) {
    final uri = Uri.tryParse(request.url);
    if (uri != null && (uri.isScheme('https') || uri.isScheme('http'))) {
      launchUrl(uri, mode: LaunchMode.externalApplication);
      return NavigationDecision.prevent;
    }
    return NavigationDecision.navigate;
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) return const SizedBox.shrink();
    return SizedBox(
      height: GoogleSearchSuggestions.height,
      child: WebViewWidget(
        controller: controller,
        // 候補のチップは横に流れるので、横方向のドラッグは WebView に渡す
        gestureRecognizers: {
          Factory<HorizontalDragGestureRecognizer>(
            HorizontalDragGestureRecognizer.new,
          ),
        },
      ),
    );
  }
}
