part of 'main.dart';

String liveQuote(AppModel app, String symbol, String side, int digits) {
  var tick = app.marketQuote.value;
  if ('${tick['symbol']}'.toLowerCase() != symbol.toLowerCase()) {
    tick = app.snapshot['symbol'] == symbol ? obj(app.snapshot['tick']) : {};
  }
  return numv(tick[side]) > 0 ? money(tick[side], decimals: digits) : '—';
}

class ClosedPositions extends StatefulWidget {
  const ClosedPositions({super.key});
  @override
  State<ClosedPositions> createState() => _ClosedPositionsState();
}

class _ClosedPositionsState extends State<ClosedPositions> {
  static const periods = {
    'today': 'Today',
    'yesterday': 'Yesterday',
    'week': 'This week',
    'month': 'This month',
    'custom': 'Custom dates',
  };
  String period = 'today', symbol = '';
  DateTimeRange? dates;
  Future<Map<String, dynamic>>? history;

  String date(DateTime value) => value.toIso8601String().substring(0, 10);

  void load() {
    final params = <String, String>{
      'period': period,
      if (period == 'custom' && dates != null) ...{
        'start': date(dates!.start), 'end': date(dates!.end),
      },
    };
    final query = Uri(queryParameters: params).query;
    final api = TradeScope.of(context).api;
    history = api.get('/api/mobile/closed-positions?$query').then(obj);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (history == null) load();
  }

  Future<void> select(String next) async {
    if (next == 'custom') {
      final now = DateTime.now().toUtc();
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2000),
        lastDate: DateTime(now.year, now.month, now.day),
        initialDateRange: dates,
      );
      if (!mounted || picked == null) return;
      dates = picked;
    }
    setState(() {
      period = next;
      symbol = '';
      load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(children: [
          Expanded(child: dropdown('Closed period', period, periods, select)),
          IconButton(
            tooltip: 'Refresh closed history',
            onPressed: () => setState(load),
            icon: const Icon(Icons.refresh),
          ),
        ]),
        if (period == 'custom' && dates != null)
          Text('${date(dates!.start)} to ${date(dates!.end)} UTC'),
        gap(),
        Expanded(child: FutureBuilder<Map<String, dynamic>>(
          future: history,
          builder: (context, result) {
            if (result.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (result.hasError) return empty('Closed history unavailable', '${result.error}');
            final data = result.data ?? {};
            final rows = arr(data['rows']).map(obj).toList();
            final names = rows.map((row) => '${row['symbol']}').toSet().toList()..sort();
            final active = names.contains(symbol) ? symbol : '';
            final shown = rows.where((row) => active.isEmpty || row['symbol'] == active).toList();
            final net = shown.fold<double>(0, (total, row) => total + numv(row['net']));
            return Column(children: [
              dropdown('Symbol', active, {'': 'All symbols', for (final name in names) name: name},
                (value) => setState(() => symbol = value)),
              gap(),
              Text('${shown.length} closing fills · Net ${money(net)} ${data['currency'] ?? ''} · UTC'),
              gap(),
              Expanded(child: shown.isEmpty ? empty('No closed positions', 'Choose another period or symbol.') :
                ListView.builder(itemCount: shown.length, itemBuilder: (context, index) {
                  final row = shown[index];
                  final time = DateTime.fromMillisecondsSinceEpoch(numv(row['closedAt']).toInt()*1000, isUtc: true);
                  return ListTile(
                    title: Text('${row['symbol']} · ${row['side']} · ${row['volume']} lots'),
                    subtitle: Text('Entry ${row['entryPrice'] ?? '—'}   Exit ${row['exitPrice']}\n${time.toIso8601String().substring(0, 16).replaceFirst('T', ' ')} UTC · #${row['ticket']}'),
                    trailing: Text(money(row['net'])),
                  );
                }),
              ),
            ]);
          },
        )),
      ],
    );
  }
}

Widget mt5Diagnostics(BuildContext context) {
  final model = TradeScope.of(context);
  String time(dynamic value) {
    final stamp = numv(value);
    if (stamp <= 0) return '—';
    return DateTime.fromMillisecondsSinceEpoch((stamp * 1000).round())
        .toString().split('.').first;
  }

  return box(Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      heading('MT5 Diagnostics'),
      const Text('Entry signals, broker responses and stop-loss / take-profit updates'),
      if (model.strategies.isEmpty) const ListTile(title: Text('No strategy connections yet')),
      for (final strategy in model.strategies.map(obj))
        Builder(builder: (context) {
          final diagnostics = obj(strategy['diagnostics']);
          final signal = obj(diagnostics['lastEntrySignal']);
          final order = obj(diagnostics['lastOrder']);
          final protection = obj(diagnostics['lastProtection']);
          final reason = diagnostics['startError'] ?? diagnostics['feedError'] ??
              obj(diagnostics['positionMismatch'])['reason'] ?? order['reason'];
          return ExpansionTile(
            title: Text('${strategy['name']} · ${strategy['symbol']}'),
            subtitle: Text('${strategy['timeframe']} · ${strategy['calcMode'] == 'tick' ? 'On every tick' : 'On candle close'} · ${diagnostics['feedError'] != null ? 'Feed error' : strategy['status']}'),
            children: [
              ListTile(title: const Text('Last MT5 quote'), subtitle: Text(time(diagnostics['lastTick']))),
              ListTile(title: const Text('Last strategy check'), subtitle: Text(time(diagnostics['lastEvaluation']))),
              ListTile(title: const Text('Last entry signal'), subtitle: Text(signal.isEmpty ? 'Waiting for signal' :
                  '${signal['side'] ?? signal['type']} · ${signal['price'] ?? '—'} · ${time(signal['receivedAt'])}')),
              ListTile(title: const Text('Broker order result'), subtitle: Text(order.isEmpty ? 'No order yet' :
                  '${order['status']} · Ticket ${order['ticket'] ?? '—'} · ${time(order['time'])}')),
              ListTile(title: const Text('SL/TP'), subtitle: Text(protection.isEmpty ? 'No update yet' :
                  '${protection['status']} · ${protection['reason'] ?? ''}')),
              if (reason != null && '$reason'.isNotEmpty) ListTile(title: Text('$reason')),
              if (arr(diagnostics['history']).isNotEmpty) ExpansionTile(
                title: const Text('Recent activity'),
                children: [
                  for (final event in arr(diagnostics['history']).reversed.map(obj))
                    ListTile(title: Text('${event['status']}'), subtitle: Text(
                        '${time(event['time'])} · ${event['side'] ?? ''} ${event['reason'] ?? ''}')),
                ],
              ),
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: const JsonEncoder.withIndent('  ').convert(strategy)));
                  if (context.mounted) notice(context, 'MT5 diagnostic details copied');
                },
                icon: const Icon(Icons.copy), label: const Text('Copy details'),
              ),
            ],
          );
        }),
    ],
  ));
}
