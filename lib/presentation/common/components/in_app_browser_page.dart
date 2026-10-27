import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show LinearProgressIndicator;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/localization/l10n_x.dart';
import '../../../core/theme/app_theme.dart';
import '../app_toast.dart';
import 'frosted_header.dart';

/// 应用内网页浏览器，适合打开服务器上的管理控制台。
class InAppBrowserPage extends StatefulWidget {
  const InAppBrowserPage({
    super.key,
    required this.title,
    required this.initialUrl,
  });

  final String title;
  final Uri initialUrl;

  @override
  State<InAppBrowserPage> createState() => _InAppBrowserPageState();
}

class _InAppBrowserPageState extends State<InAppBrowserPage> {
  InAppWebViewController? _controller;
  double _progress = 0;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top + FrostedHeader.headerHeight;
    return CupertinoPageScaffold(
      backgroundColor: AppColors.background(context),
      child: Stack(
        children: [
          Positioned.fill(
            top: top,
            child: InAppWebView(
              initialUrlRequest: URLRequest(
                url: WebUri(widget.initialUrl.toString()),
              ),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                allowsInlineMediaPlayback: true,
                mediaPlaybackRequiresUserGesture: true,
                transparentBackground: false,
              ),
              onWebViewCreated: (controller) => _controller = controller,
              onProgressChanged: (_, progress) {
                if (mounted) setState(() => _progress = progress / 100);
              },
              onReceivedError: (_, request, error) {
                if (request.isForMainFrame != true || !mounted) return;
                showAppErrorToast(
                  context.l10n.databases_webPageLoadFailed,
                  description: error.description,
                );
              },
            ),
          ),
          if (_progress < 1)
            Positioned(
              top: top,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(
                value: _progress,
                minHeight: 2,
                color: CupertinoColors.activeBlue,
                backgroundColor: CupertinoColors.transparent,
              ),
            ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: FrostedHeader(
              title: widget.title,
              onBack: () => Navigator.of(context).maybePop(),
              isOverlapping: true,
              trailingBuilder: (_, _) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CupertinoButton(
                    padding: const EdgeInsets.all(6),
                    minimumSize: const Size.square(32),
                    onPressed: () => _controller?.reload(),
                    child: const Icon(TablerIcons.refresh, size: 19),
                  ),
                  CupertinoButton(
                    padding: const EdgeInsets.all(6),
                    minimumSize: const Size.square(32),
                    onPressed: () => launchUrl(
                      widget.initialUrl,
                      mode: LaunchMode.externalApplication,
                    ),
                    child: const Icon(TablerIcons.external_link, size: 19),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
