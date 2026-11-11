import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'api.dart';

class OriginalChartController {
  WebViewController? view;
  Future<void> quotes(String symbol, String tf, List<dynamic> ticks) async =>
      view?.runJavaScript('marketQuotes(${jsonEncode(symbol)},${jsonEncode(tf)},${jsonEncode(ticks)})');
  Future<void> action(String name) async =>
      view?.runJavaScript('chartAction(${jsonEncode(name)})');
  Future<void> strategy(Map<String, dynamic> data, String key) async => view
      ?.runJavaScript('strategyResult(${jsonEncode(data)},${jsonEncode(key)})');
}

class OriginalChart extends StatefulWidget {
  final TradeApi api;
  final Map<String, dynamic> config;
  final OriginalChartController controller;
  final void Function(String, String) onMarket;
  const OriginalChart({
    super.key,
    required this.api,
    required this.config,
    required this.controller,
    required this.onMarket,
  });
  @override
  State<OriginalChart> createState() => _OriginalChartState();
}

class _OriginalChartState extends State<OriginalChart> {
  late final WebViewController view;
  bool ready = false;
  @override
  void initState() {
    super.initState();
    view = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'ChartBridge',
        onMessageReceived: (m) => message(m.message),
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (r) =>
              r.url.startsWith('about:') || r.url.startsWith('data:')
              ? NavigationDecision.navigate
              : NavigationDecision.prevent,
        ),
      );
    widget.controller.view = view;
    load();
  }

  Future<void> load() async {
    var html = await rootBundle.loadString('assets/openalgo/chart.html');
    for (final e in {
      'CORE': '',
      'INDICATORS': '.indicators',
      'DRAW': '.draw',
      'WIDGET': '.widget',
    }.entries) {
      html = html.replaceFirst(
        '/*OPENALGO_${e.key}*/',
        await rootBundle.loadString(
          'assets/openalgo/openalgo-charts${e.value}.standalone.js',
        ),
      );
    }
    if (mounted) await view.loadHtmlString(html);
  }

  Future<void> message(String raw) async {
    dynamic id;
    try {
      final msg = obj(jsonDecode(raw));
      id = msg['id'];
      final type = msg['type'];
      if (type == 'ready') {
        ready = true;
        paint();
        return;
      }
      if (type == 'market') {
        widget.onMarket('${msg['symbol']}', '${msg['tf']}');
        return;
      }
      dynamic result;
      switch (type) {
        case 'drawings':
          result = await widget.api.get('/api/drawings');
          break;
        case 'drawingSave':
          final key = Uri.encodeComponent('${msg['key']}');
          result = msg['remove'] == true
              ? await widget.api.request(
                  '/api/drawings?key=$key',
                  method: 'DELETE',
                )
              : await widget.api.put('/api/drawings', {
                  'key': msg['key'],
                  'document': msg['document'],
                });
          break;
        case 'bars':
          final symbol = Uri.encodeComponent('${msg['symbol']}'),
              tf = '${msg['tf']}';
          if (!RegExp(r'^(M(1|3|5|10|15|30|45)|H(1|4)|D1)$').hasMatch(tf))
            throw ApiError('Unsupported interval');
          int sec(dynamic x) {
            final n = numv(x);
            return (n > 1e11 ? n / 1000 : n).floor();
          }
          var from = sec(msg['from']), to = sec(msg['to']);
          if (to <= 0) to = DateTime.now().millisecondsSinceEpoch ~/ 1000;
          if (tf == 'M1' && to - from > 45 * 86400) from = to - 45 * 86400;
          result = await widget.api.get(
            '/api/candles/$symbol?timeframe=$tf&start_date=$from&end_date=$to',
          );
          if (arr(result).isEmpty && arr(obj(result)['bars']).isEmpty) {
            result = await widget.api.get(
              '/api/candles/$symbol?timeframe=$tf&bars=5000',
            );
            final all = result is List ? result : arr(obj(result)['bars']);
            result = all.where((b) {
              final t = sec(obj(b)['time']);
              return t >= from && t <= to;
            }).toList();
          }
          break;
        default:
          throw ApiError('Unsupported chart request');
      }
      if (mounted)
        await view.runJavaScript(
          'chartReply(${jsonEncode(id)},${jsonEncode(result)},null)',
        );
    } catch (e) {
      if (mounted && id != null)
        await view.runJavaScript(
          'chartReply(${jsonEncode(id)},null,${jsonEncode('$e')})',
        );
    }
  }

  void paint() {
    if (ready) view.runJavaScript('chartConfig(${jsonEncode(widget.config)})');
  }

  @override
  void didUpdateWidget(covariant OriginalChart old) {
    super.didUpdateWidget(old);
    paint();
  }

  @override
  void dispose() {
    widget.controller.view = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => WebViewWidget(controller: view);
}

