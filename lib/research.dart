part of 'main.dart';

const timeframes = {
  'M1': 'M1',
  'M3': 'M3',
  'M5': 'M5',
  'M10': 'M10',
  'M15': 'M15',
  'M30': 'M30',
  'M45': 'M45',
  'H1': 'H1',
  'H4': 'H4',
  'D1': 'D1',
};
const executionModes = {
  'broker_close': 'On candle close',
  'broker_tick': 'On every tick',
};
const historicalExecutionModes = {
  ...executionModes,
  'open_only': 'Chart OHLC — Fast',
  'ohlc_1m': '1-minute OHLC — Detailed',
  'real_ticks': 'Real broker ticks',
};
int? chartTime(dynamic x) {
  if (x == null || x == '') return null;
  final n = x is num ? x.toDouble() : double.tryParse('$x');
  if (n != null && n.isFinite)
    return (n > 1e14
            ? n / 1e6
            : n > 1e11
            ? n / 1000
            : n)
        .floor();
  final parsed = DateTime.tryParse('$x');
  return parsed == null ? null : parsed.millisecondsSinceEpoch ~/ 1000;
}

Map<String, dynamic> equityConfig(
  Map<String, dynamic> report,
  int from,
  int to, {
  String key = 'equity',
}) {
  final curve = arr(report['equityCurve']),
      values = arr(report['equity']),
      times = arr(report['equityTimes']);
  final points = <Map<String, dynamic>>[];
  final initial = numv(report['initialCapital'] ?? report['initialBalance']);
  for (final p in curve) {
    final x = obj(p);
    final stamp = chartTime(x['time']);
    if (stamp != null && x['equity'] != null)
      points.add({'time': stamp, 'value': numv(x['equity']) - initial});
  }
  if (points.isEmpty && values.length == times.length) {
    for (var i = 0; i < values.length; i++) {
      final stamp = chartTime(times[i]);
      if (stamp != null)
        points.add({'time': stamp, 'value': numv(values[i]) - initial});
    }
  }
  points.sort((a, b) => (a['time'] as int).compareTo(b['time'] as int));
  final exits = <int, double>{};
  for (final trade in arr(report['trades'])) {
    final x = obj(trade);
    final stamp = chartTime(x['exit_time'] ?? x['exitTime'] ?? x['close_time']);
    final pnl = x['pnl'] ?? x['profit'] ?? x['realized_pnl'];
    if (stamp != null && pnl != null)
      exits[stamp] = (exits[stamp] ?? 0) + numv(pnl);
  }
  final context = obj(report['executionContext']);
  final start = chartTime(context['firstBar'] ?? report['firstBar']) ?? from;
  final end = chartTime(context['lastBar'] ?? report['lastBar']) ?? to;
  final cumulative = <Map<String, dynamic>>[
    {'time': start, 'value': 0},
  ];
  double sum = 0;
  final sorted = exits.keys.toList()..sort();
  for (final stamp in sorted) {
    if (stamp < start || stamp > end) continue;
    sum += exits[stamp]!;
    cumulative.add({'time': stamp, 'value': sum});
  }
  cumulative.add({
    'time': end,
    'value': report['net'] != null ? numv(report['net']) : sum,
  });
  final excursions = sorted
      .where((stamp) => stamp >= start && stamp <= end)
      .map(
        (stamp) => {
          'time': stamp,
          'value': exits[stamp],
          'color': exits[stamp]! >= 0 ? '#009b8188' : '#d04c6688',
        },
      )
      .toList();
  final prices = arr(report['priceHistory'])
      .map(obj)
      .where((x) => numv(x['close']) > 0 && chartTime(x['time']) != null)
      .toList();
  final hold = prices.isEmpty || initial <= 0
      ? <Map<String, dynamic>>[]
      : prices
            .map(
              (x) => {
                'time': chartTime(x['time']),
                'value':
                    initial *
                    (numv(x['close']) / numv(prices.first['close']) - 1),
              },
            )
            .toList();
  return {
    'hold': hold,
    'kind': 'equity',
    'key': key,
    'data': points,
    'cumulative': cumulative,
    'excursions': excursions,
    'from': start,
    'to': end,
  };
}

class ResearchPage extends StatefulWidget {
  final bool optimize;
  final String? sourceName;
  const ResearchPage({super.key, required this.optimize, this.sourceName});
  @override
  State<ResearchPage> createState() => _ResearchPageState();
}

class _ResearchPageState extends State<ResearchPage> {
  int tab = 0, tradePage = 0;
  String? script;
  String tf = 'M30',
      model = 'broker_close',
      method = 'grid',
      period = '6M',
      error = '',
      jobId = '';
  DateTime from = DateTime.now().subtract(const Duration(days: 183)),
      to = DateTime.now();
  final symbol = TextEditingController(),
      maximum = TextEditingController(text: '500');
  List<PineInput> params = [];
  Map<String, dynamic> values = {}, job = {}, selected = {};
  Map<String, Map<String, dynamic>> ranges = {};
  Timer? poll;
  bool initialized = false,
      busy = false,
      refreshing = false,
      showEquity = true,
      showCumulative = true,
      showHold = false,
      showExcursions = true;
  @override
  void initState() {
    super.initState();
    poll = Timer.periodic(const Duration(seconds: 2), (_) {
      if (jobId.isNotEmpty &&
          (job.isEmpty || active) &&
          TradeScope.of(context).resumed)
        refreshJob();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!initialized) {
      initialized = true;
      final m = TradeScope.of(context);
      symbol.text = m.selectedSymbol;
      tf = m.selectedTf;
      script = widget.sourceName ?? m.scripts.keys.firstOrNull;
      loadScript();
      jobId =
          m.prefs.getString(
            widget.optimize ? 'optimizationJob' : 'backtestJob',
          ) ??
          '';
      if (jobId.isNotEmpty) Future.microtask(refreshJob);
    }
  }

  @override
  void dispose() {
    poll?.cancel();
    symbol.dispose();
    maximum.dispose();
    super.dispose();
  }

  void loadScript() {
    final m = TradeScope.of(context);
    final source = '${obj(m.scripts[script])['source'] ?? ''}';
    params = parsePineInputs(source);
    values = {for (final p in params) p.name: p.value};
    ranges = {
      for (final p in params.where((p) => p.numeric || p.type == 'timeframe'))
        p.name: {
          'use': false,
          'min': p.value,
          'max': p.value,
          'step': p.step ?? (p.type == 'int' ? 1 : .1),
          'integer': p.type == 'int',
          if (p.type == 'timeframe') 'single': p.value,
        },
    };
  }

  bool get active =>
      ['preparing', 'running', 'paused', 'stopping'].contains(job['status']);
  Future<void> refreshJob() async {
    if (refreshing || !mounted) return;
    refreshing = true;
    final requestedId = jobId;
    try {
      final api = TradeScope.of(context).api;
      var x = obj(await api.get('/api/mobile/jobs/$requestedId?compact=true'));
      if (!widget.optimize &&
          x['hasReport'] == true &&
          obj(job['report']).isEmpty) {
        x = obj(await api.get('/api/mobile/jobs/$requestedId'));
      } else if (!widget.optimize && job['id'] == requestedId) {
        x = {
          ...x,
          'report': job['report'],
          'priceHistory': job['priceHistory'],
        };
      }
      if (mounted && requestedId == jobId)
        setState(() {
          job = x;
          error = '';
        });
    } catch (e) {
      if (mounted && error != '$e') setState(() => error = '$e');
    } finally {
      refreshing = false;
    }
  }

  Future<void> selectResult(Map<String, dynamic> row) async {
    try {
      final result = obj(
        await TradeScope.of(context).api
            .get('/api/mobile/jobs/$jobId/results/${row['_index']}'),
      );
      if (mounted)
        setState(() {
          selected = result;
          tab = 3;
        });
    } catch (e) {
      if (mounted) notice(context, e);
    }
  }

  Future<void> run() async {
    final m = TradeScope.of(context);
    if (!m.patchAvailable) {
      setState(
        () => error = 'Install the included Windows mobile-backend update, restart the backend, and refresh Home first.',
      );
      return;
    }
    if (from.isAfter(to)) {
      setState(
        () => error = 'The start date must be on or before the end date.',
      );
      return;
    }
    if (script == null || symbol.text.trim().isEmpty) {
      setState(() => error = 'Select a Pine strategy and broker symbol.');
      return;
    }
    setState(() {
      busy = true;
      error = '';
    });
    try {
      final source = '${obj(m.scripts[script])['source'] ?? ''}';
      final combos = widget.optimize
          ? buildCombinations(ranges, int.tryParse(maximum.text) ?? 500)
          : null;
      final x = obj(
        await m.api.post('/api/mobile/jobs', {
          'kind': widget.optimize ? 'optimization' : 'backtest',
          'config': {
            'source': source,
            'symbol': symbol.text.trim(),
            'timeframe': tf,
            'start':
                DateTime.utc(
                  from.year,
                  from.month,
                  from.day,
                ).millisecondsSinceEpoch ~/
                1000,
            'end':
                DateTime.utc(
                  to.year,
                  to.month,
                  to.day,
                  23,
                  59,
                  59,
                ).millisecondsSinceEpoch ~/
                1000,
            'values': values,
            'tickModel': model,
            if (combos != null) 'combinations': combos,
            if (widget.optimize) 'optimizationType': method,
          },
        }),
      );
      jobId = '${x['id']}';
      await m.prefs.setString(
        widget.optimize ? 'optimizationJob' : 'backtestJob',
        jobId,
      );
      if (mounted)
        setState(() {
          job = x;
          selected = {};
          tab = 2;
        });
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> control(String action) async {
    if (action == 'stop' &&
        !await confirm(
          context,
          'Stop research job',
          'Stop this ${widget.optimize ? 'optimization' : 'backtest'} run? Completed partial results are retained.',
        ))
      return;
    if (!mounted) return;
    await perform(
      context,
      () => TradeScope.of(context).api.post('/api/mobile/jobs/$jobId/$action'),
    );
    await refreshJob();
  }

  Future<void> chooseDate(bool start) async {
    final d = await showDatePicker(
      context: context,
      initialDate: start ? from : to,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (d != null && mounted)
      setState(() {
        if (start)
          from = d;
        else
          to = d;
        period = 'Custom';
      });
  }

  String date(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  Map<String, dynamic> get report {
    final result = widget.optimize ? selected : obj(job['report']);
    if (result.isEmpty) return {};
    return {
      ...result,
      if (job['priceHistory'] != null) 'priceHistory': job['priceHistory'],
    };
  }

  @override
  Widget build(BuildContext c) {
    final m = TradeScope.of(c);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.optimize ? 'Optimization' : 'Backtest'),
        actions: [
          IconButton(
            tooltip: 'Job history',
            onPressed: () => history(c),
            icon: const Icon(Icons.history, size: 20),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
        child: Column(
          children: [
            tabs(
              c,
              widget.optimize
                  ? ['Setup', 'Parameters', 'Results', 'Selected', 'Trades']
                  : ['Setup', 'Inputs', 'Chart', 'Summary', 'Trades'],
              tab,
              (v) => setState(() => tab = v),
            ),
            gap(),
            if (error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  error,
                  style: TextStyle(color: m.style.bad, fontSize: 11),
                ),
              ),
            if (active || job.isNotEmpty) runStatus(c),
            if (active || job.isNotEmpty) gap(8),
            Expanded(
              child: tab == 0
                  ? setup(c)
                  : tab == 1
                  ? inputs(c)
                  : tab == 2
                  ? (widget.optimize ? optimizationResults(c) : chartResult(c))
                  : tab == 3
                  ? (widget.optimize ? chartResult(c) : summary(c))
                  : trades(c),
            ),
          ],
        ),
      ),
    );
  }

  Widget runStatus(BuildContext c) {
    final m = TradeScope.of(c), p = obj(job['progress']);
    final total = numv(p['total']), done = numv(p['done'] ?? p['processed']);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: m.style.soft,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                '${job['status'] ?? 'Ready'}'.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: m.style.primary,
                ),
              ),
              const Spacer(),
              if (active)
                TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(30, 24),
                    padding: const EdgeInsets.symmetric(horizontal: 7),
                  ),
                  onPressed: () =>
                      control(job['status'] == 'paused' ? 'resume' : 'pause'),
                  child: Text(
                    job['status'] == 'paused' ? 'Resume' : 'Pause',
                    style: const TextStyle(fontSize: 10),
                  ),
                ),
              if (active)
                TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(30, 24),
                    padding: const EdgeInsets.symmetric(horizontal: 7),
                  ),
                  onPressed: () => control('stop'),
                  child: const Text('Stop', style: TextStyle(fontSize: 10)),
                ),
            ],
          ),
          Text(
            '${job['message'] ?? ''}${total > 0 ? ' · ${done.round()}/${total.round()}' : ''}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10, color: m.style.muted),
          ),
          if (active) ...[
            gap(5),
            LinearProgressIndicator(
              value: total > 0 ? (done / total).clamp(0, 1) : null,
              minHeight: 3,
            ),
          ],
        ],
      ),
    );
  }

  Widget setup(BuildContext c) {
    final m = TradeScope.of(c);
    return ListView(
      children: [
        box(
          Column(
            children: [
              DropdownButtonFormField<String>(
                initialValue: script,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Saved Pine strategy',
                ),
                items: m.scripts.keys
                    .map(
                      (s) => DropdownMenuItem(
                        value: s,
                        child: Text(s, style: const TextStyle(fontSize: 12)),
                      ),
                    )
                    .toList(),
                onChanged: active
                    ? null
                    : (s) => setState(() {
                        script = s;
                        loadScript();
                      }),
              ),
              gap(),
              field(symbol, 'Broker symbol'),
              gap(),
              pair(
                dropdown(
                  'Timeframe',
                  tf,
                  timeframes,
                  (v) => setState(() => tf = v),
                ),
                dropdown(
                  'Period',
                  period,
                  {
                    '1M': '1 Month',
                    '3M': '3 Months',
                    '6M': '6 Months',
                    '1Y': '1 Year',
                    '1.5Y': '1.5 Years',
                    '2Y': '2 Years',
                    '3Y': '3 Years',
                    '5Y': '5 Years',
                    'Custom': 'Custom',
                  },
                  (v) => setState(() {
                    period = v;
                    final days = {
                      '1M': 30,
                      '3M': 90,
                      '6M': 183,
                      '1Y': 365,
                      '1.5Y': 548,
                      '2Y': 730,
                      '3Y': 1095,
                      '5Y': 1826,
                    }[v];
                    if (days != null) {
                      to = DateTime.now();
                      from = to.subtract(Duration(days: days));
                    }
                  }),
                ),
              ),
              gap(),
              pair(
                OutlinedButton(
                  onPressed: () => chooseDate(true),
                  child: Text(
                    'From ${date(from)}',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
                OutlinedButton(
                  onPressed: () => chooseDate(false),
                  child: Text(
                    'To ${date(to)}',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ),
              gap(),
              dropdown(
                'Strategy timing',
                model,
                executionModes,
                (v) => setState(() => model = v),
              ),
              if (widget.optimize) ...[
                gap(),
                dropdown('Optimization type', method, {
                  'grid': 'Grid Search',
                  'random': 'Random Search',
                  'genetic': 'Genetic Algorithm',
                  'bayesian': 'Bayesian Optimization',
                  'walkforward': 'Walk-Forward Optimization',
                  'montecarlo': 'Monte Carlo Analysis',
                }, (v) => setState(() => method = v)),
                gap(),
                field(
                  maximum,
                  'Maximum combinations (1–500)',
                  keyboard: TextInputType.number,
                ),
              ],
              gap(17),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: busy || active ? null : run,
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: Text(
                    busy
                        ? 'Starting…'
                        : widget.optimize
                        ? 'Start Optimization'
                        : 'Run Backtest',
                  ),
                ),
              ),
              gap(8),
              const Text(
                'Runs on the Windows backend. You can leave the app and return to the job. Keep the Windows app and tunnel running.',
                style: TextStyle(fontSize: 11),
              ),
            ],
          ),
        ),
        gap(10),
        OutlinedButton.icon(
          onPressed: () async {
            await m.reloadScripts();
            if (mounted) setState(() {});
          },
          icon: const Icon(Icons.sync, size: 16),
          label: const Text('Refresh saved strategies'),
        ),
      ],
    );
  }

  Widget inputs(BuildContext c) {
    if (params.isEmpty)
      return empty(
        'No Pine inputs detected',
        'The selected script has no supported literal input defaults. Its original source is used unchanged.',
      );
    return ListView(
      children: [
        if (widget.optimize)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'Select numeric/timeframe parameters. Define Min, Max, Step; other inputs keep their values.',
              style: TextStyle(
                color: TradeScope.of(c).style.muted,
                fontSize: 12,
              ),
            ),
          ),
        for (final p in params)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: box(
              widget.optimize && ranges.containsKey(p.name)
                  ? rangeEditor(c, p)
                  : inputWidget(p),
            ),
          ),
        if (widget.optimize)
          OutlinedButton(
            onPressed: () {
              try {
                final x = buildCombinations(
                  ranges,
                  int.tryParse(maximum.text) ?? 500,
                );
                notice(c, '${x.length} combinations');
              } catch (e) {
                notice(c, e);
              }
            },
            child: const Text('Check combination count'),
          ),
      ],
    );
  }

  Widget inputWidget(PineInput p) {
    if (p.type == 'bool')
      return SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(p.title, style: const TextStyle(fontSize: 12)),
        value: values[p.name] == true,
        onChanged: active ? null : (v) => setState(() => values[p.name] = v),
      );
    if (p.options.isNotEmpty)
      return dropdown(p.title, '${values[p.name]}', {
        for (final o in p.options) o: o,
      }, (v) => setState(() => values[p.name] = v));
    return TextFormField(
      key: ValueKey('${script}:${p.name}'),
      initialValue: '${values[p.name]}',
      decoration: InputDecoration(labelText: p.title, helperText: p.name),
      keyboardType: p.numeric
          ? const TextInputType.numberWithOptions(decimal: true, signed: true)
          : TextInputType.text,
      onChanged: (v) =>
          values[p.name] = p.numeric ? (num.tryParse(v) ?? p.value) : v,
      enabled: !active,
    );
  }

  Widget rangeEditor(BuildContext c, PineInput p) {
    final g = ranges[p.name]!;
    return Column(
      children: [
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: g['use'] == true,
          onChanged: active ? null : (v) => setState(() => g['use'] = v),
          title: Text(p.title, style: const TextStyle(fontSize: 12)),
          subtitle: Text(
            'Current: ${values[p.name]}',
            style: const TextStyle(fontSize: 10),
          ),
        ),
        if (p.type == 'timeframe')
          dropdown(
            'One timeframe',
            '${g['single']}',
            timeframes,
            (v) => setState(() => g['single'] = v),
          )
        else
          Row(
            children: [
              for (final k in ['min', 'max', 'step'])
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: TextFormField(
                      key: ValueKey('${script}:${p.name}:$k'),
                      initialValue: '${g[k]}',
                      enabled: !active,
                      decoration: InputDecoration(
                        labelText: k[0].toUpperCase() + k.substring(1),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      onChanged: (v) => g[k] = v,
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Widget chartResult(BuildContext c) {
    final r = report, m = TradeScope.of(c);
    if (r.isEmpty)
      return empty(
        'No result selected',
        active
            ? 'The server is running your test. Results appear when it completes.'
            : 'Run a test or select an optimization result.',
      );
    final fromSec = numv(job['from']).round(), toSec = numv(job['to']).round();
    final cfg = equityConfig(
      r,
      fromSec,
      toSec,
      key: jobId + (widget.optimize ? pretty(r['params']) : ''),
    );
    return Column(
      children: [
        box(
          Column(
            children: [
              pair(
                metric(
                  c,
                  'Net profit',
                  money(r['net']),
                  color: numv(r['net']) >= 0 ? m.style.good : m.style.bad,
                ),
                metric(
                  c,
                  'Max drawdown',
                  '${money(r['maxDrawdownPercent'])}%',
                  color: m.style.bad,
                ),
              ),
              gap(),
              pair(
                metric(c, 'Profit factor', money(r['pf'])),
                metric(c, 'Trades', '${arr(r['trades']).length}'),
              ),
              if (widget.optimize) ...[
                gap(),
                Text(pretty(r['params']), style: const TextStyle(fontSize: 11)),
              ],
            ],
          ),
        ),
        gap(9),
        Row(
          children: [
            Expanded(
              child: Text('Strategy timing used · ${historicalExecutionModes['${r['tickModel']}'] ?? '—'}'),
            ),
            IconButton(
              tooltip: 'Re-run with selected model',
              onPressed: active ? null : run,
              icon: const Icon(Icons.refresh, size: 20),
            ),
          ],
        ),
        Wrap(
          spacing: 8,
          children: [
            chartToggle(
              c,
              'Equity P&L',
              showEquity,
              (v) => setState(() => showEquity = v),
            ),
            chartToggle(
              c,
              'Cumulative P&L',
              showCumulative,
              (v) => setState(() => showCumulative = v),
            ),
          ],
        ),
        Wrap(
          spacing: 8,
          children: [
            chartToggle(
              c,
              'Buy and hold',
              showHold,
              (v) => setState(() => showHold = v),
            ),
            chartToggle(
              c,
              'Trade excursions',
              showExcursions,
              (v) => setState(() => showExcursions = v),
            ),
          ],
        ),
        Expanded(
          child: arr(cfg['data']).isEmpty
              ? empty(
                  'No timestamped equity points',
                  'The backend report did not return equity timestamps. Open Summary or export the full report.',
                )
              : TradeChart(
                  style: m.style,
                  config: {
                    ...cfg,
                    'showEquity': showEquity,
                    'showCumulative': showCumulative,
                    'showHold': showHold,
                    'showExcursions': showExcursions,
                  },
                ),
        ),
        if (r['tickWarning'] != null)
          Text(
            '${r['tickWarning']}',
            maxLines: 2,
            style: TextStyle(fontSize: 10, color: m.style.muted),
          ),
      ],
    );
  }

  Widget summary(BuildContext c) {
    final r = report;
    if (r.isEmpty)
      return empty('No report yet', 'Run a backtest to view its metrics.');
    final initial = numv(r['initialCapital'] ?? r['initialBalance']),
        net = numv(r['net']);
    final trades = arr(r['trades']);
    final winners = trades
            .map(obj)
            .where((t) => numv(t['profit'] ?? t['pnl']) > 0)
            .toList(),
        losers = trades
            .map(obj)
            .where((t) => numv(t['profit'] ?? t['pnl']) < 0)
            .toList();
    double profit(Map<String, dynamic> t) => numv(t['profit'] ?? t['pnl']);
    final all = trades.map(obj).map(profit).toList();
    final data = {
      'Model used': historicalExecutionModes['${r['tickModel']}'] ?? '—',
      'Initial balance': money(initial),
      'Final balance': money(initial + net),
      'Total return': initial != 0 ? '${money(net / initial * 100)}%' : '—',
      'Total trades': '${trades.length}',
      'Winning trades': '${r['wins'] ?? winners.length}',
      'Losing trades': '${r['losses'] ?? losers.length}',
      'Win rate': '${money(r['winRate'])}%',
      'Profit factor': money(r['pf']),
      'Max drawdown': '${money(r['maxDrawdownPercent'])}%',
      'Average win': winners.isEmpty
          ? '—'
          : money(winners.map(profit).reduce((a, b) => a + b) / winners.length),
      'Average loss': losers.isEmpty
          ? '—'
          : money(losers.map(profit).reduce((a, b) => a + b) / losers.length),
      'Largest win': all.isEmpty ? '—' : money(all.reduce(math.max)),
      'Largest loss': all.isEmpty ? '—' : money(all.reduce(math.min)),
      'Sharpe ratio': r['sharpe'] == null ? '—' : money(r['sharpe']),
      'Sortino ratio': r['sortino'] == null ? '—' : money(r['sortino']),
      'Calmar ratio': r['calmar'] == null ? '—' : money(r['calmar']),
      'Recovery factor': r['recoveryFactor'] == null
          ? '—'
          : money(r['recoveryFactor']),
      'Expectancy': trades.isEmpty ? '—' : money(net / trades.length),
    };
    return ListView(
      children: [
        box(
          Column(
            children: data.entries.map((e) => keyval(e.key, e.value)).toList(),
          ),
        ),
        gap(),
        OutlinedButton.icon(
          onPressed: () =>
              exportText(c, 'skxtrade-backtest-report.json', pretty(r)),
          icon: const Icon(Icons.ios_share, size: 17),
          label: const Text('Export full report'),
        ),
      ],
    );
  }

  Widget optimizationResults(BuildContext c) {
    final rows = arr(job['results']).map(obj).toList()
      ..sort((a, b) => numv(b['net']).compareTo(numv(a['net'])));
    if (rows.isEmpty)
      return empty(
        'No optimization results',
        active
            ? 'Completed combinations appear here.'
            : 'Configure parameters, then run optimization.',
      );
    return ListView(
      children: [
        box(
          Row(
            children: [
              Expanded(
                child: metric(c, 'Best net profit', money(rows.first['net'])),
              ),
              Expanded(child: metric(c, 'Results', '${rows.length}')),
            ],
          ),
        ),
        gap(),
        for (var i = 0; i < rows.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Card(
              child: ListTile(
                dense: true,
                title: Text(
                  '#${i + 1} · Net ${money(rows[i]['net'])}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  'PF ${money(rows[i]['pf'])} · DD ${money(rows[i]['maxDrawdownPercent'])}%\n${pretty(rows[i]['params'])}',
                  style: const TextStyle(fontSize: 10),
                ),
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () => selectResult(rows[i]),
              ),
            ),
          ),
      ],
    );
  }

  Widget trades(BuildContext c) =>
      TradeHistoryList(rows: arr(report['trades']), symbol: symbol.text);

  Future<void> history(BuildContext c) async {
    try {
      final all = arr(await TradeScope.of(c).api.get('/api/mobile/jobs'))
          .map(obj)
          .where(
            (x) => x['kind'] == (widget.optimize ? 'optimization' : 'backtest'),
          )
          .toList();
      if (!c.mounted) return;
      await showModalBottomSheet(
        context: c,
        isScrollControlled: true,
        builder: (d) => SafeArea(
          child: SizedBox(
            height: 420,
            child: Column(
              children: [
                const ListTile(title: Text('Backend job history')),
                Expanded(
                  child: all.isEmpty
                      ? const Center(child: Text('No previous jobs'))
                      : ListView(
                          children: all
                              .map(
                                (x) => ListTile(
                                  title: Text(
                                    '${x['symbol']} · ${x['timeframe']}',
                                  ),
                                  subtitle: Text(
                                    '${x['status']} · ${DateTime.fromMillisecondsSinceEpoch((numv(x['started']) * 1000).round()).toLocal()}',
                                  ),
                                  onTap: () {
                                    setState(() {
                                      jobId = '${x['id']}';
                                      job = {};
                                      selected = {};
                                      tab = 2;
                                    });
                                    TradeScope.of(c).prefs.setString(
                                      widget.optimize
                                          ? 'optimizationJob'
                                          : 'backtestJob',
                                      jobId,
                                    );
                                    Navigator.pop(d);
                                    refreshJob();
                                  },
                                ),
                              )
                              .toList(),
                        ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      if (c.mounted) notice(c, e);
    }
  }
}

Widget chartToggle(
  BuildContext c,
  String label,
  bool selected,
  ValueChanged<bool> change,
) => InkWell(
  onTap: () => change(!selected),
  child: Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        width: 27,
        height: 32,
        child: Checkbox(value: selected, onChanged: (v) => change(v ?? false)),
      ),
      Text(label, style: const TextStyle(fontSize: 10)),
    ],
  ),
);
String csv(List<dynamic> rows) {
  if (rows.isEmpty) return '';
  final keys = rows.map(obj).expand((r) => r.keys).toSet().toList();
  String quote(dynamic x) => '"${'$x'.replaceAll('"', '""')}"';
  return [
    keys.map(quote).join(','),
    ...rows.map((r) => keys.map((k) => quote(obj(r)[k] ?? '')).join(',')),
  ].join('\r\n');
}

