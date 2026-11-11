part of 'main.dart';

class TradingPage extends StatefulWidget {
  final bool active;
  const TradingPage({super.key, required this.active});
  @override
  State<TradingPage> createState() => _TradingPageState();
}

class _TradingPageState extends State<TradingPage> {
  Timer? poll;
  List<dynamic> bars = [];
  String symbol = '',
      tf = 'M30',
      chartType = 'candles',
      error = '',
      strategy = '',
      strategySource = '';
  Map<String, dynamic> strategyValues = {};
  DateTime? lastPineRun;
  bool loading = false,
      initialized = false,
      strategyBusy = false,
      landscape = false;
  final chart = OriginalChartController();
  AppModel? app;
  void onQuote() {
    final quote = app?.marketQuote.value ?? {};
    if (widget.active && '${quote['symbol']}'.toLowerCase() == symbol.toLowerCase()) {
      unawaited(chart.quotes(symbol, tf, arr(quote['ticks'])).catchError((Object _) {}));
    }
  }
  @override
  void initState() {
    super.initState();
    poll = Timer.periodic(const Duration(seconds: 5), (_) {
      if (widget.active && app?.marketStatus.value != 'MT5 feed connected') load();
      if (widget.active && strategy.isNotEmpty && !strategyBusy &&
          (lastPineRun == null || DateTime.now().difference(lastPineRun!).inSeconds >= 15)) {
        unawaited(updateStrategy(strategy, strategySource, strategyValues));
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!initialized) {
      initialized = true;
      final m = TradeScope.of(context);
      app = m;
      m.marketQuote.addListener(onQuote);
      symbol = m.selectedSymbol;
      tf = m.selectedTf;
      if (widget.active) Future.microtask(load);
    }
  }

  @override
  void didUpdateWidget(covariant TradingPage old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) load();
    if (!widget.active && old.active && landscape) {
      landscape = false;
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    }
  }

  @override
  void dispose() {
    poll?.cancel();
    app?.marketQuote.removeListener(onQuote);
    if (landscape)
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  Future<void> load() async {
    if (!mounted || loading || !widget.active || symbol.isEmpty) return;
    loading = true;
    final requested = '$symbol:$tf';
    try {
      final r = await TradeScope.of(context).api.get(
        '/api/candles/${Uri.encodeComponent(symbol)}?timeframe=$tf&bars=1500',
      );
      if (mounted && requested == '$symbol:$tf')
        setState(() {
          bars = arr(r);
          error = '';
        });
      if (mounted &&
          strategy.isNotEmpty &&
          !strategyBusy &&
          (lastPineRun == null ||
              DateTime.now().difference(lastPineRun!).inSeconds >= 15))
        unawaited(updateStrategy(strategy, strategySource, strategyValues));
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<String?> choose(
    String title,
    String current,
    Map<String, String> choices,
  ) async {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (d) {
        String query = '';
        return StatefulBuilder(
          builder: (d, update) => SizedBox(
            height: MediaQuery.sizeOf(d).height * .67,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                children: [
                  heading(title),
                  if (choices.length > 12)
                    TextField(
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Search',
                      ),
                      onChanged: (s) => update(() => query = s.toLowerCase()),
                    ),
                  Expanded(
                    child: Builder(
                      builder: (d) {
                        final rows = choices.entries
                            .where((e) => e.value.toLowerCase().contains(query))
                            .toList();
                        return ListView.builder(
                          itemCount: rows.length,
                          itemBuilder: (d, i) => ListTile(
                            title: Text(rows[i].value),
                            trailing: rows[i].key == current
                                ? const Icon(Icons.check)
                                : null,
                            onTap: () => Navigator.pop(d, rows[i].key),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> market(String next, String frame) async {
    if (next == symbol && frame == tf) return;
    setState(() {
      symbol = next;
      tf = frame;
      bars = [];
      strategy = '';
    });
    final m = TradeScope.of(context);
    m.selectMarket(symbol, tf);
    m.refresh();
    load();
  }

  Future<void> strategies() async {
    final m = TradeScope.of(context);
    try {
      await m.reloadScripts();
      if (!mounted) return;
      final name = await choose('Saved Pine strategies', strategy, {
        '': 'Remove chart strategy',
        for (final n in m.scripts.keys) n: n,
      });
      if (name == null || !mounted) return;
      if (name.isEmpty) {
        await chart.strategy({}, '');
        setState(() => strategy = '');
        return;
      }
      final source = '${obj(m.scripts[name])['source'] ?? ''}';
      final inputs = parsePineInputs(source);
      final values = <String, dynamic>{for (final p in inputs) p.name: p.value};
      if (inputs.isNotEmpty) {
        final apply = await showModalBottomSheet<bool>(
          context: context,
          showDragHandle: true,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (d) => StatefulBuilder(
            builder: (d, update) => Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(d).bottom,
              ),
              child: SizedBox(
                height: MediaQuery.sizeOf(d).height * .65,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      heading(name),
                      Expanded(
                        child: ListView(
                          children: inputs
                              .map(
                                (p) => Padding(
                                  padding: const EdgeInsets.only(top: 10),
                                  child: p.type == 'bool'
                                      ? SwitchListTile(
                                          title: Text(p.title),
                                          value: values[p.name] == true,
                                          onChanged: (v) =>
                                              update(() => values[p.name] = v),
                                        )
                                      : p.options.isNotEmpty
                                      ? dropdown(
                                          p.title,
                                          '${values[p.name]}',
                                          {for (final x in p.options) x: x},
                                          (v) =>
                                              update(() => values[p.name] = v),
                                        )
                                      : TextFormField(
                                          initialValue: '${p.value}',
                                          decoration: InputDecoration(
                                            labelText: p.title,
                                          ),
                                          keyboardType: p.numeric
                                              ? const TextInputType.numberWithOptions(
                                                  decimal: true,
                                                  signed: true,
                                                )
                                              : TextInputType.text,
                                          onChanged: (v) =>
                                              values[p.name] = p.type == 'int'
                                              ? int.tryParse(v)
                                              : p.type == 'float'
                                              ? double.tryParse(v)
                                              : v,
                                        ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(d, true),
                        child: const Text('Apply to chart'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        if (apply != true || !mounted) return;
      }
      if (values.values.any((v) => v == null))
        throw const FormatException('Enter valid strategy input values.');
      await updateStrategy(name, source, values);
    } catch (e) {
      if (mounted) notice(context, '$e');
    }
  }

  Future<void> updateStrategy(
    String name,
    String source,
    Map<String, dynamic> values,
  ) async {
    if (strategyBusy || bars.isEmpty) return;
    setState(() => strategyBusy = true);
    lastPineRun = DateTime.now();
    final requested = '$symbol:$tf';
    try {
      final result = obj(
        await TradeScope.of(context).api.request(
          '/api/pine/chart',
          method: 'POST',
          data: {
            'source': source,
            'symbol': symbol,
            'timeframe': tf,
            'bars': bars,
            'values': values,
          },
          timeout: const Duration(minutes: 15),
        ),
      );
      if (mounted && requested == '$symbol:$tf') {
        await chart.strategy(result, name);
        setState(() {
          strategy = name;
          strategySource = source;
          strategyValues = Map.of(values);
        });
      }
    } catch (e) {
      if (mounted) notice(context, 'Pine chart: $e');
    } finally {
      if (mounted) setState(() => strategyBusy = false);
    }
  }

  Future<void> order(String side) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (d) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(d).bottom),
        child: SizedBox(
          height: math.min(530, MediaQuery.sizeOf(d).height * .85),
          child: TestEntryForm(initialSymbol: symbol, initialSide: side),
        ),
      ),
    );
  }

  Widget control(
    String label,
    String value,
    IconData icon,
    VoidCallback? action,
  ) => Expanded(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: SizedBox(
        height: 65,
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(11),
            ),
          ),
          onPressed: action,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 17),
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 9,
                  height: 1.1,
                  letterSpacing: -.3,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext c) {
    final m = TradeScope.of(c);
    final names = m.symbols.map(symbolName).where((s) => s.isNotEmpty).toSet();
    if (symbol.isEmpty && names.isNotEmpty) symbol = names.first;
    final digits = numv(
      obj(m.snapshot['symbol_info'])['digits'],
    ).toInt().clamp(0, 8).toInt();
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Column(
        children: [
          Row(
            children: [
              control('Symbol', symbol, Icons.search, () async {
                final s = await choose('Symbol', symbol, {
                  for (final n in names) n: n,
                });
                if (s != null && mounted) market(s, tf);
              }),
              control(
                'Type',
                chartType == 'candles' ? 'Candles' : chartType,
                Icons.candlestick_chart_outlined,
                () async {
                  final v = await choose('Chart type', chartType, const {
                    'candles': 'Candles',
                    'line': 'Line',
                    'area': 'Area',
                    'bar': 'OHLC bars',
                  });
                  if (v != null && mounted) setState(() => chartType = v);
                },
              ),
              control(
                'Indicators',
                'Studies',
                Icons.tune,
                () => chart.action('indicators'),
              ),
              control('Timeframe', tf, Icons.schedule, () async {
                final v = await choose('Timeframe', tf, {
                  for (final t in [
                    'M1',
                    'M3',
                    'M5',
                    'M10',
                    'M15',
                    'M30',
                    'M45',
                    'H1',
                    'H4',
                    'D1',
                  ])
                    t: t,
                });
                if (v != null && mounted) market(symbol, v);
              }),
              control(
                'Strategies',
                strategy.isEmpty ? 'Select' : strategy,
                Icons.code,
                strategyBusy || bars.isEmpty ? null : strategies,
              ),
            ],
          ),
          gap(8),
          if (strategyBusy) const LinearProgressIndicator(minHeight: 2),
          if (error.isNotEmpty)
            Row(
              children: [
                Expanded(
                  child: Text(
                    error,
                    maxLines: 2,
                    style: TextStyle(color: m.style.bad, fontSize: 10),
                  ),
                ),
                IconButton(
                  onPressed: () {
                    load();
                    chart.action('reload');
                  },
                  icon: const Icon(Icons.refresh, size: 17),
                ),
              ],
            ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: symbol.isEmpty
                  ? empty(
                      'Choose a symbol',
                      'Connect MT5 to load the original chart.',
                    )
                  : OriginalChart(
                      api: m.api,
                      controller: chart,
                      onMarket: (s, t) {
                        if (mounted) market(s, t);
                      },
                      config: {
                        'symbol': symbol,
                        'tf': tf,
                        'chartType': chartType,
                        'symbols': names.toList(),
                        'data': bars,
                        'dark': Theme.of(c).brightness == Brightness.dark,
                      },
                    ),
            ),
          ),
          SizedBox(
            height: 34,
            child: Row(
              children: [
                Expanded(
                  child: ValueListenableBuilder<String>(
                    valueListenable: m.marketStatus,
                    builder: (context, status, _) => Text(
                    strategy.isEmpty ? '$status · $tf' : '$strategy · $status',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10, color: m.style.muted),
                  ),
                ),
                ),
                IconButton(
                  tooltip: 'Chart settings',
                  onPressed: () => chart.action('settings'),
                  icon: const Icon(Icons.tune, size: 18),
                ),
                IconButton(
                  tooltip: 'Drawing objects',
                  onPressed: () => chart.action('objects'),
                  icon: const Icon(Icons.layers_outlined, size: 18),
                ),
                IconButton(
                  tooltip: 'Rotate chart',
                  onPressed: () async {
                    landscape = !landscape;
                    await SystemChrome.setPreferredOrientations(
                      landscape
                          ? [
                              DeviceOrientation.landscapeLeft,
                              DeviceOrientation.landscapeRight,
                            ]
                          : [DeviceOrientation.portraitUp],
                    );
                  },
                  icon: const Icon(Icons.fullscreen, size: 20),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                for (final side in ['SELL', 'BUY'])
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: FilledButton(
                        onPressed: () => order(side),
                        style: FilledButton.styleFrom(
                          backgroundColor: side == 'SELL'
                              ? const Color(0xffd6425b)
                              : const Color(0xff009a7b),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              side,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 10),
                            ValueListenableBuilder<Map<String, dynamic>>(
                              valueListenable: m.marketQuote,
                              builder: (context, tick, _) => Text(
                              liveQuote(m, symbol, side == 'SELL' ? 'bid' : 'ask', digits),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class PositionsPage extends StatefulWidget {
  final bool initialPending;
  const PositionsPage({super.key, this.initialPending = false});
  @override
  State<PositionsPage> createState() => _PositionsPageState();
}

class _PositionsPageState extends State<PositionsPage> {
  String search = '';
  int page = 0;
  late bool pending;
  bool closed = false;
  @override
  void initState() {
    super.initState();
    pending = widget.initialPending;
  }

  Future<void> modify(Map<String, dynamic> p) async {
    final sl = TextEditingController(
          text: numv(p['sl']) == 0 ? '' : '${p['sl']}',
        ),
        tp = TextEditingController(
          text: numv(p['tp']) == 0 ? '' : '${p['tp']}',
        );
    final yes = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Modify SL / TP'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${p['symbol']} · Ticket ${p['ticket']}'),
            gap(14),
            field(
              sl,
              'Stop loss',
              keyboard: const TextInputType.numberWithOptions(decimal: true),
            ),
            gap(12),
            field(
              tp,
              'Take profit',
              keyboard: const TextInputType.numberWithOptions(decimal: true),
            ),
            gap(12),
            const Text(
              'Blank removes that level. Only this position is modified.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(d, true),
            child: const Text('Apply changes'),
          ),
        ],
      ),
    );
    if (yes == true && mounted) {
      if ((sl.text.isNotEmpty && double.tryParse(sl.text) == null) ||
          (tp.text.isNotEmpty && double.tryParse(tp.text) == null)) {
        notice(context, 'Enter valid prices or leave blank.');
      } else {
        final m = TradeScope.of(context);
        await perform(
          context,
          () => m.api.post('/api/mt5/live/modify', {
            'ticket': p['ticket'],
            'sl': double.tryParse(sl.text) ?? 0,
            'tp': double.tryParse(tp.text) ?? 0,
            'confirm': true,
          }),
          success: 'Position protection updated',
        );
      }
    }
    sl.dispose();
    tp.dispose();
  }

  @override
  Widget build(BuildContext c) {
    final m = TradeScope.of(c), t = m.style;
    final all = arr(
      m.snapshot[pending ? 'orders' : 'positions'],
    ).map(obj).toList();
    final filtered = all
        .where(
          (p) => '${p['symbol']} ${p['ticket']} ${p['magic']}'
              .toLowerCase()
              .contains(search.toLowerCase()),
        )
        .toList();
    final pages = math.max(1, (filtered.length / 2).ceil());
    if (page >= pages) page = pages - 1;
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Row(
            children: [
              const Text(
                'Positions',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Refresh',
                onPressed: m.refresh,
                icon: const Icon(Icons.refresh, size: 20),
              ),
            ],
          ),
          gap(8),
          box(
            Row(
              children: [
                Expanded(
                  child: metric(
                    c,
                    'Floating P&L',
                    money(
                      all.fold<double>(0, (sum, p) => sum + numv(p['profit'])),
                    ),
                    color: t.good,
                  ),
                ),
                Text(
                  '${all.length} ${pending ? 'pending' : 'open'}',
                  style: TextStyle(fontSize: 11, color: t.muted),
                ),
              ],
            ),
          ),
          gap(),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('Open')),
              ButtonSegment(value: 1, label: Text('Pending')),
              ButtonSegment(value: 2, label: Text('Closed')),
            ],
            selected: {closed ? 2 : pending ? 1 : 0},
            onSelectionChanged: (v) => setState(() {
              closed = v.first == 2;
              pending = v.first == 1;
              page = 0;
            }),
          ),
          gap(),
          if (closed) const Expanded(child: ClosedPositions()),
          if (!closed) ...[
          TextField(
            decoration: const InputDecoration(
              hintText: 'Search symbol, ticket, or strategy ID',
              prefixIcon: Icon(Icons.search, size: 18),
            ),
            onChanged: (v) => setState(() {
              search = v;
              page = 0;
            }),
          ),
          gap(),
          Expanded(
            child: filtered.isEmpty
                ? empty(
                    pending ? 'No pending orders' : 'No open positions',
                    m.error.isEmpty
                        ? 'Positions will appear here when opened in MT5.'
                        : m.error,
                  )
                : ListView(
                    children: filtered.skip(page * 2).take(2).map((p) {
                      final link = m.strategies
                          .map(obj)
                          .where(
                            (s) => arr(
                              s['tickets'],
                            ).any((x) => obj(x)['ticket'] == p['ticket']),
                          )
                          .toList();
                      final side = numv(p['type']) == 0 ? 'BUY' : 'SELL';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: box(
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    '$side · ${p['symbol']}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    money(p['profit']),
                                    style: TextStyle(
                                      color: numv(p['profit']) >= 0
                                          ? t.good
                                          : t.bad,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              gap(5),
                              Text(
                                '${link.isNotEmpty ? link.first['name'] : 'MT5 position'} · ${p['magic']}',
                                style: TextStyle(color: t.muted, fontSize: 10),
                              ),
                              gap(13),
                              pair(
                                metric(
                                  c,
                                  'Volume',
                                  '${p['volume']} lots',
                                  small: true,
                                ),
                                metric(
                                  c,
                                  'Ticket',
                                  '${p['ticket']}',
                                  small: true,
                                ),
                              ),
                              gap(12),
                              pair(
                                metric(
                                  c,
                                  'Entry',
                                  '${p['price_open']}',
                                  small: true,
                                ),
                                metric(
                                  c,
                                  'Current',
                                  '${p['price_current']}',
                                  small: true,
                                ),
                              ),
                              gap(12),
                              pair(
                                metric(
                                  c,
                                  'Stop loss',
                                  '${p['sl']}',
                                  small: true,
                                ),
                                metric(
                                  c,
                                  'Take profit',
                                  '${p['tp']}',
                                  small: true,
                                ),
                              ),
                              if (!pending) ...[
                                gap(),
                                pair(
                                  OutlinedButton(
                                    onPressed: () => modify(p),
                                    child: const Text(
                                      'Modify SL / TP',
                                      style: TextStyle(fontSize: 11),
                                    ),
                                  ),
                                  OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: t.bad,
                                    ),
                                    onPressed: () async {
                                      if (await confirm(
                                        c,
                                        'Close position',
                                        'Close only ticket ${p['ticket']} (${p['symbol']}, ${p['volume']} lots)? This sends a real MT5 close request.',
                                        action: 'Close position',
                                      )) {
                                        if (c.mounted)
                                          await brokerAction(
                                            c,
                                            'close:${p['ticket']}',
                                            () => m.api.post(
                                              '/api/mt5/positions/${p['ticket']}/close',
                                            ),
                                            closing: true,
                                          );
                                      }
                                    },
                                    child: const Text(
                                      'Close position',
                                      style: TextStyle(fontSize: 11),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: page > 0 ? () => setState(() => page--) : null,
                child: const Text('Previous'),
              ),
              Text(
                '${page + 1} / $pages',
                style: TextStyle(fontSize: 11, color: t.muted),
              ),
              TextButton(
                onPressed: page + 1 < pages
                    ? () => setState(() => page++)
                    : null,
                child: const Text('Next'),
              ),
            ],
          ),
          ],
        ],
      ),
    );
  }
}

class Mt5Page extends StatefulWidget {
  final int initialTab;
  const Mt5Page({super.key, this.initialTab = 0});
  @override
  State<Mt5Page> createState() => _Mt5PageState();
}

class _Mt5PageState extends State<Mt5Page> {
  late int tab;
  int page = 0;
  String search = '';
  Map<String, dynamic>? protect;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    tab = widget.initialTab;
  }

  Future<void> action(Map<String, dynamic> s, String action) async {
    final m = TradeScope.of(context);
    final text = action == 'stop'
        ? 'Stops only this Pine engine. Existing MT5 positions and broker-side SL/TP may remain active. Close positions separately.'
        : action == 'pause'
        ? 'No new strategy-generated orders while paused. Existing MT5 positions and broker-side SL/TP remain active.'
        : 'New Pine signals may send real MT5 orders.';
    if (await confirm(
      context,
      '${action[0].toUpperCase()}${action.substring(1)} ${s['name']}',
      '${s['symbol']} · ${s['timeframe']}\nConnection ${s['id']}\n\n$text',
    )) {
      if (mounted)
        await perform(
          context,
          () => m.api.post(
            '/api/mt5/strategies/${Uri.encodeComponent('${s['id']}')}/$action',
          ),
          success: 'Strategy $action submitted',
        );
    }
  }

  Future<void> deploy() async {
    final m = TradeScope.of(context);
    await m.reloadScripts();
    if (!mounted) return;
    openPage(context, const DeployStrategyPage());
  }

  @override
  Widget build(BuildContext c) {
    final m = TradeScope.of(c);
    protect ??= Map<String, dynamic>.from(m.protection);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Meta 5 Connection'),
        actions: [
          IconButton(
            onPressed: m.refresh,
            icon: const Icon(Icons.refresh, size: 20),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        child: Column(
          children: [
            tabs(
              c,
              ['Account', 'Strategies', 'Protection', 'Test entry'],
              tab,
              (i) => setState(() => tab = i),
            ),
            gap(),
            Expanded(
              child: tab == 0
                  ? account(c)
                  : tab == 1
                  ? connections(c)
                  : tab == 2
                  ? protection(c)
                  : ListView(
                      children: [
                        const TestEntryForm(embedded: true),
                        gap(),
                        mt5Diagnostics(c),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget account(BuildContext c) {
    final m = TradeScope.of(c), a = obj(m.snapshot['account']);
    return ListView(
      children: [
        box(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              heading('MT5 Connection'),
              for (final row in {
                'Broker': '${a['company'] ?? '—'}',
                'Server': '${a['server'] ?? '—'}',
                'Account': '${a['login'] ?? '—'}',
                'Symbol': m.selectedSymbol,
                'Status': m.connection,
              }.entries)
                keyval(row.key, row.value),
              gap(),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () async {
                    if (await confirm(
                      c,
                      'Reconnect MT5',
                      'Stop all live strategy connections first. Reconnect the desktop MT5 terminal?',
                    )) {
                      if (c.mounted)
                        await perform(
                          c,
                          () => m.api.post('/api/mt5/reconnect'),
                          success: 'MT5 reconnected',
                        );
                    }
                  },
                  icon: const Icon(Icons.sync, size: 17),
                  label: const Text('Reconnect MT5'),
                ),
              ),
            ],
          ),
        ),
        gap(),
        box(
          const Text(
            'Log in to MT5 on Windows, then reconnect here. Account settings and your Cloudflare tunnel token stay on Windows.',
            style: TextStyle(fontSize: 12),
          ),
        ),
        gap(),
        OutlinedButton(
          onPressed: () => openPage(
            c,
            const Scaffold(body: SafeArea(child: PositionsPage())),
          ),
          child: const Text('Active positions'),
        ),
      ],
    );
  }

  Widget connections(BuildContext c) {
    final m = TradeScope.of(c), t = m.style;
    final rows = m.strategies
        .map(obj)
        .where(
          (s) => '${s['name']} ${s['symbol']} ${s['id']}'
              .toLowerCase()
              .contains(search.toLowerCase()),
        )
        .toList();
    final pages = math.max(1, (rows.length / 3).ceil());
    page = page.clamp(0, pages - 1);
    return Column(
      children: [
        TextField(
          decoration: const InputDecoration(
            hintText: 'Search strategies or symbols',
            prefixIcon: Icon(Icons.search, size: 18),
          ),
          onChanged: (v) => setState(() {
            search = v;
            page = 0;
          }),
        ),
        gap(8),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: deploy,
            icon: const Icon(Icons.add, size: 17),
            label: const Text('Create Strategy Connection'),
          ),
        ),
        gap(8),
        Expanded(
          child: rows.isEmpty
              ? empty(
                  'No strategy connections',
                  'Choose a saved Pine strategy to deploy through your Windows backend.',
                )
              : ListView(
                  children: rows.skip(page * 3).take(3).map((s) {
                    final status = '${s['status']}';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 9),
                      child: box(
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${s['name']}',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                Text(
                                  status,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: status == 'Running'
                                        ? t.good
                                        : t.muted,
                                  ),
                                ),
                              ],
                            ),
                            gap(5),
                            Text(
                              '${s['symbol']} · ${s['timeframe']} · ${s['lotMode'] == 'fixed' ? 'Fixed ${s['lotSize']}' : 'Pine / Auto'}',
                              style: TextStyle(fontSize: 10, color: t.muted),
                            ),
                            gap(8),
                            Text(
                              'Connection ${s['id']}',
                              style: TextStyle(fontSize: 10, color: t.muted),
                            ),
                            gap(8),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () => action(
                                      s,
                                      status == 'Running'
                                          ? 'pause'
                                          : status == 'Paused'
                                          ? 'resume'
                                          : 'start',
                                    ),
                                    child: Text(
                                      status == 'Running'
                                          ? 'Pause'
                                          : status == 'Paused'
                                          ? 'Resume'
                                          : 'Start',
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: t.bad,
                                    ),
                                    onPressed: status == 'Stopped'
                                        ? null
                                        : () => action(s, 'stop'),
                                    child: const Text(
                                      'Stop',
                                      style: TextStyle(fontSize: 11),
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Delete connection',
                                  color: t.bad,
                                  onPressed: () async {
                                    if (await confirm(
                                      c,
                                      'Delete ${s['name']}?',
                                      '${s['symbol']} · ${s['timeframe']}\nConnection ${s['id']}\n\nStops and removes only this connection. Saved Pine source and existing broker positions remain.',
                                      action: 'Delete',
                                    )) {
                                      if (c.mounted)
                                        await perform(
                                          c,
                                          () => m.api.request(
                                            '/api/mt5/strategies/${Uri.encodeComponent('${s['id']}')}',
                                            method: 'DELETE',
                                          ),
                                          success: 'Connection deleted',
                                        );
                                    }
                                  },
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    size: 19,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Connection details',
                                  onPressed: () => openPage(
                                    c,
                                    JsonDetailPage(
                                      title: '${s['name']}',
                                      data: s,
                                    ),
                                  ),
                                  icon: const Icon(
                                    Icons.info_outline,
                                    size: 19,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(12),
                      ),
                    );
                  }).toList(),
                ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: page > 0 ? () => setState(() => page--) : null,
              child: const Text('Previous'),
            ),
            Text('${page + 1} / $pages', style: const TextStyle(fontSize: 11)),
            TextButton(
              onPressed: page + 1 < pages ? () => setState(() => page++) : null,
              child: const Text('Next'),
            ),
          ],
        ),
      ],
    );
  }

  Widget protection(BuildContext c) {
    final m = TradeScope.of(c);
    final p = protect!;
    return ListView(
      children: [
        box(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              heading('Funded Account Protection'),
              Text(
                '${obj(obj(m.snapshot['protection'])['guard'])['reason'] ?? 'Protection settings from the Windows backend'}',
                style: const TextStyle(fontSize: 11),
              ),
              gap(),
              for (final x in [
                ('daily', 'Daily loss limit', 'dailyLimitPct', '%'),
                ('perEntry', 'Per-entry loss limit', 'perEntryLimitPct', '%'),
                (
                  'overallLot',
                  'Maximum overall lot size',
                  'maxOverallLotSize',
                  'lots',
                ),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Checkbox(
                        value: p[x.$1] == true,
                        onChanged: (v) => setState(() => p[x.$1] = v),
                      ),
                      Expanded(
                        child: Text(x.$2, style: const TextStyle(fontSize: 12)),
                      ),
                      SizedBox(
                        width: 77,
                        child: TextFormField(
                          initialValue: '${p[x.$3] ?? 0}',
                          decoration: InputDecoration(suffixText: x.$4),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          onChanged: (v) => p[x.$3] = double.tryParse(v) ?? 0,
                        ),
                      ),
                    ],
                  ),
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text(
                  'Hedging protection',
                  style: TextStyle(fontSize: 12),
                ),
                value: p['hedge'] == true,
                onChanged: (v) => setState(() => p['hedge'] = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text(
                  'Black Friday protection',
                  style: TextStyle(fontSize: 12),
                ),
                value: p['friday'] == true,
                onChanged: (v) => setState(() => p['friday'] = v),
              ),
              gap(),
              pair(
                TextFormField(
                  initialValue: '${p['fridayCloseTime'] ?? '20:00'}',
                  decoration: const InputDecoration(
                    labelText: 'Friday close HH:mm',
                  ),
                  onChanged: (v) => p['fridayCloseTime'] = v,
                ),
                TextFormField(
                  initialValue: '${p['mondayResumeTime'] ?? '00:00'}',
                  decoration: const InputDecoration(
                    labelText: 'Monday resume HH:mm',
                  ),
                  onChanged: (v) => p['mondayResumeTime'] = v,
                ),
              ),
              gap(),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: busy
                      ? null
                      : () async {
                          if (await confirm(
                            c,
                            'Save protection',
                            'These limits affect your live MT5 account. Apply the displayed settings?',
                          )) {
                            setState(() => busy = true);
                            await perform(
                              c,
                              () => m.api.post('/api/mt5/protection', p),
                              success: 'Protection saved',
                            );
                            if (mounted) setState(() => busy = false);
                          }
                        },
                  child: const Text('Save protection settings'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

Widget tabs(
  BuildContext c,
  List<String> labels,
  int current,
  ValueChanged<int> select,
) {
  final t = TradeScope.of(c).style;
  return Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: t.soft,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: List.generate(
        labels.length,
        (i) => Expanded(
          child: Semantics(
            selected: current == i,
            button: true,
            child: InkWell(
              onTap: () {
                HapticFeedback.selectionClick();
                select(i);
              },
              borderRadius: BorderRadius.circular(9),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                constraints: const BoxConstraints(minHeight: 38),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
                decoration: BoxDecoration(
                  color: current == i ? t.paper : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                  boxShadow: current == i
                      ? [
                          BoxShadow(
                            color: t.ink.withValues(alpha: .04),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  labels[i],
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: labels.length > 4 ? 10 : 11.5,
                    fontWeight: current == i
                        ? FontWeight.w600
                        : FontWeight.w500,
                    color: current == i ? t.primary : t.muted,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class JsonDetailPage extends StatelessWidget {
  final String title;
  final dynamic data;
  const JsonDetailPage({super.key, required this.title, required this.data});
  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(
      title: Text(title),
      actions: [
        IconButton(
          tooltip: 'Export',
          onPressed: () => exportText(c, 'skxtrade-report.json', pretty(data)),
          icon: const Icon(Icons.ios_share, size: 20),
        ),
      ],
    ),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: SelectableText(
        pretty(data),
        style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
      ),
    ),
  );
}

class DeployStrategyPage extends StatefulWidget {
  const DeployStrategyPage({super.key});
  @override
  State<DeployStrategyPage> createState() => _DeployStrategyPageState();
}

class _DeployStrategyPageState extends State<DeployStrategyPage> {
  String? strategy;
  String tf = 'M30', calc = 'tick';
  bool busy = false;
  final symbol = TextEditingController();
  @override
  void dispose() {
    symbol.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    final m = TradeScope.of(c);
    strategy ??= m.scripts.keys.firstOrNull;
    if (symbol.text.isEmpty) symbol.text = m.selectedSymbol;
    return Scaffold(
      appBar: AppBar(title: const Text('Create Live Strategy')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: strategy,
            decoration: const InputDecoration(labelText: 'Saved Pine strategy'),
            items: m.scripts.keys
                .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                .toList(),
            onChanged: (s) => setState(() => strategy = s),
          ),
          gap(),
          field(symbol, 'Broker symbol'),
          gap(),
          dropdown('Timeframe', tf, {
            'M1': 'M1',
            'M5': 'M5',
            'M15': 'M15',
            'M30': 'M30',
            'H1': 'H1',
            'H4': 'H4',
            'D1': 'D1',
          }, (v) => setState(() => tf = v)),
          gap(),
          dropdown('Calculate', calc, {
            'tick': 'On every tick',
            'close': 'On candle close',
          }, (v) => setState(() => calc = v)),
          gap(),
          box(
            const Text(
              'Pine / Auto Lot: this backend uses each Pine entry quantity. Set position sizing in your Pine strategy before deploying. The app does not silently override quantities.',
              style: TextStyle(fontSize: 12),
            ),
          ),
          gap(),
          FilledButton(
            onPressed: busy || strategy == null
                ? null
                : () async {
                    if (!await confirm(
                      c,
                      'Create & deploy',
                      'Deploy $strategy on ${symbol.text} ($tf)? This strategy may place real MT5 orders.',
                    ))
                      return;
                    setState(() => busy = true);
                    try {
                      final s = obj(m.scripts[strategy]);
                      final x = obj(
                        await m.api.post('/api/mt5/strategies', {
                          'name': strategy,
                          'source': s['source'],
                          'symbol': symbol.text.trim(),
                          'timeframe': tf,
                          'calcMode': calc,
                          'lotMode': 'pine',
                          'start': true,
                        }),
                      );
                      await m.refresh();
                      if (c.mounted) {
                        notice(c, 'Deployed connection ${x['id']}');
                        Navigator.pop(c);
                      }
                    } catch (e) {
                      if (c.mounted) notice(c, e);
                    } finally {
                      if (mounted) setState(() => busy = false);
                    }
                  },
            child: Text(busy ? 'Deploying…' : 'Create & Deploy'),
          ),
        ],
      ),
    );
  }
}

Widget dropdown(
  String label,
  String value,
  Map<String, String> options,
  ValueChanged<String> changed,
) => MobileSelect(
  label: label,
  value: value,
  options: options,
  onChanged: changed,
);

class TestEntryForm extends StatefulWidget {
  final String? initialSymbol, initialSide;
  final bool embedded;
  const TestEntryForm({super.key, this.initialSymbol, this.initialSide, this.embedded = false});
  @override
  State<TestEntryForm> createState() => _TestEntryFormState();
}

class _TestEntryFormState extends State<TestEntryForm> {
  final symbol = TextEditingController(),
      lot = TextEditingController(text: '0.01'),
      sl = TextEditingController(),
      tp = TextEditingController();
  bool busy = false;
  @override
  void dispose() {
    for (final c in [symbol, lot, sl, tp]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> send(String side) async {
    if (busy) return;
    final m = TradeScope.of(context);
    final amount = double.tryParse(lot.text);
    if (amount == null || !amount.isFinite || amount <= 0) {
      notice(context, 'Enter a valid lot size');
      return;
    }
    for (final control in [sl, tp]) {
      if (control.text.isNotEmpty &&
          (double.tryParse(control.text) == null ||
              !double.parse(control.text).isFinite ||
              double.parse(control.text) < 0)) {
        notice(context, 'Enter a valid SL / TP price');
        return;
      }
    }
    setState(() => busy = true);
    if (!await confirm(
      context,
      'Send real $side order',
      '${symbol.text} · $amount lots\nStop loss: ${sl.text.isEmpty ? 'None' : sl.text}\nTake profit: ${tp.text.isEmpty ? 'None' : tp.text}\n\nThis sends a real MT5 market order. Use a demo account for testing.',
      action: 'Send $side',
    )) {
      if (mounted) setState(() => busy = false);
      return;
    }
    if (!mounted) return;
    setState(() => busy = true);
    await brokerAction(
      context,
      'order:${symbol.text}',
      () => m.api.post('/api/mt5/live/order', {
        'symbol': symbol.text.trim(),
        'side': side,
        'volume': amount,
        'sl': double.tryParse(sl.text),
        'tp': double.tryParse(tp.text),
        'confirm': true,
      }),
    );
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext c) {
    if (symbol.text.isEmpty)
      symbol.text = widget.initialSymbol ?? TradeScope.of(c).selectedSymbol;
    return ListView(
      shrinkWrap: widget.embedded,
      physics: widget.embedded ? const NeverScrollableScrollPhysics() : null,
      children: [
        box(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              heading(
                widget.initialSide == null
                    ? 'Test Entry'
                    : '${widget.initialSide} · ${widget.initialSymbol}',
              ),
              field(symbol, 'Symbol'),
              gap(),
              field(
                lot,
                'Lot size',
                keyboard: const TextInputType.numberWithOptions(decimal: true),
              ),
              gap(),
              pair(
                field(
                  sl,
                  'Stop loss (optional)',
                  keyboard: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
                field(
                  tp,
                  'Take profit (optional)',
                  keyboard: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
              ),
              gap(),
              pair(
                FilledButton(
                  onPressed: busy || widget.initialSide == 'SELL'
                      ? null
                      : () => send('BUY'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xff009a7b),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Buy'),
                ),
                OutlinedButton(
                  onPressed: busy || widget.initialSide == 'BUY'
                      ? null
                      : () => send('SELL'),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: const Color(0xffd6425b),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Sell'),
                ),
              ),
              gap(),
              const Text(
                'These actions execute real orders through your Windows MT5 terminal.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

