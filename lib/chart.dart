import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'themes.dart';

class TradeChart extends StatefulWidget {
  final Map<String, dynamic> config;
  final TradeStyle style;
  const TradeChart({super.key, required this.config, required this.style});
  @override
  State<TradeChart> createState() => _TradeChartState();
}

class _TradeChartState extends State<TradeChart> {
  late final WebViewController controller;
  bool ready = false;
  @override
  void initState() {
    super.initState();
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(widget.style.paper)
      ..addJavaScriptChannel(
        'Ready',
        onMessageReceived: (_) {
          ready = true;
          paint();
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (r) {
            final u = Uri.tryParse(r.url);
            if (u?.host == 'www.tradingview.com' ||
                u?.host == 'tradingview.com') {
              launchUrl(u!, mode: LaunchMode.externalApplication);
              return NavigationDecision.prevent;
            }
            return r.url.startsWith('about:') || r.url.startsWith('data:')
                ? NavigationDecision.navigate
                : NavigationDecision.prevent;
          },
        ),
      );
    load();
  }

  Future<void> load() async {
    final html = await rootBundle.loadString('assets/chart.html');
    final js = await rootBundle.loadString('assets/lightweight-charts.js');
    if (mounted)
      await controller.loadHtmlString(
        html.replaceFirst('/*CHART_LIBRARY*/', js),
      );
  }

  String hex(Color c) => '#${c.toARGB32().toRadixString(16).substring(2)}';
  void paint() {
    if (!ready) return;
    final t = widget.style;
    final cfg = {
      ...widget.config,
      'background': hex(t.paper),
      'primary': hex(t.primary),
      'muted': hex(t.muted),
      'border': hex(t.border),
      'good': hex(t.good),
      'bad': hex(t.bad),
    };
    controller.runJavaScript('renderChart(${jsonEncode(cfg)});');
  }

  @override
  void didUpdateWidget(covariant TradeChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    paint();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(widget.style.radius),
          child: WebViewWidget(controller: controller),
        ),
      ),
      SizedBox(
        height: 32,
        child: Row(
          children: [
            for (final pair in <String, int>{
              '1D': 1,
              '1M': 30,
              '3M': 90,
              '6M': 180,
              'All': 0,
            }.entries)
              TextButton(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 7),
                  minimumSize: const Size(25, 30),
                ),
                onPressed: () =>
                    controller.runJavaScript('chartRange(${pair.value});'),
                child: Text(pair.key, style: const TextStyle(fontSize: 10)),
              ),
            const Spacer(),
            IconButton(
              tooltip: 'Landscape chart',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => LandscapeChart(
                    config: widget.config,
                    style: widget.style,
                  ),
                ),
              ),
              icon: const Icon(Icons.fullscreen, size: 20),
            ),
          ],
        ),
      ),
    ],
  );
}

class LandscapeChart extends StatefulWidget {
  final Map<String, dynamic> config;
  final TradeStyle style;
  const LandscapeChart({super.key, required this.config, required this.style});
  @override
  State<LandscapeChart> createState() => _LandscapeChartState();
}

class _LandscapeChartState extends State<LandscapeChart> {
  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(toolbarHeight: 40, title: const Text('Chart')),
    body: TradeChart(config: widget.config, style: widget.style),
  );
}
