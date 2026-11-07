part of 'main.dart';

class AiFullPage extends StatelessWidget {
  const AiFullPage({super.key});
  @override
  Widget build(BuildContext c) =>
      const Scaffold(body: SafeArea(child: AiPage(active: true)));
}

class AiPage extends StatefulWidget {
  final bool active;
  const AiPage({super.key, required this.active});
  @override
  State<AiPage> createState() => _AiPageState();
}

class _AiPageState extends State<AiPage> {
  int tab = 0, setupTab = 0, page = 0;
  Map<String, dynamic> setup = {}, status = {}, account = {};
  List<dynamic> saved = [], runs = [];
  Set<String> checked = {};
  String error = '', search = '', equityFilter = 'all';
  bool loading = false, busy = false;
  Timer? poll, saveTimer;
  TradeApi? pageApi;
  bool started = false;
  @override
  void initState() {
    super.initState();
    poll = Timer.periodic(const Duration(seconds: 5), (_) {
      if (widget.active && TradeScope.of(context).resumed) loadStatus();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    pageApi = TradeScope.of(context).api;
    if (widget.active && !started) {
      started = true;
      Future.microtask(load);
    }
  }

  @override
  void didUpdateWidget(covariant AiPage old) {
    super.didUpdateWidget(old);
    if (widget.active && !started) {
      started = true;
      load();
    } else if (widget.active && !old.active) {
      loadStatus();
    }
  }

  @override
  void dispose() {
    poll?.cancel();
    if (saveTimer?.isActive ?? false) {
      final api = pageApi!;
      final snapshot = jsonDecode(jsonEncode(setup));
      saveQueue = saveQueue
          .then((_) async {
            await api.put('/api/ai-trading/setup', snapshot);
          })
          .catchError((Object _) {});
    }
    saveTimer?.cancel();
    super.dispose();
  }

  bool get running => [
    'running',
    'paused',
    'pausing',
    'stopping',
    'starting',
  ].contains(status['status']);
  Future<void> load() async {
    if (loading) return;
    loading = true;
    try {
      final api = TradeScope.of(context).api;
      final x = await api.get('/api/ai-trading/setup');
      if (!mounted) return;
      setState(() => setup = obj(x));
      listsChecked = null;
      await loadStatus();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      loading = false;
    }
  }

  bool statusLoading = false, statusAgain = false;
  int statusGeneration = 0;
  DateTime? accountChecked, listsChecked;
  int listsTab = -1;
  Future<void> saveQueue = Future<void>.value();
  Future<void> loadStatus() async {
    if (statusLoading) {
      statusAgain = true;
      return;
    }
    statusLoading = true;
    final selectedTab = tab;
    final generation = statusGeneration;
    try {
      final api = TradeScope.of(context).api;
      final nextStatus = obj(await api.get('/api/ai-trading/status'));
      if (!mounted || generation != statusGeneration) return;
      final changed =
          nextStatus['id'] != status['id'] ||
          nextStatus['completed'] != status['completed'];
      setState(() {
        status = nextStatus;
        error = '';
      });
      if ((selectedTab == 2 || selectedTab == 3) &&
          (changed ||
              listsTab != selectedTab ||
              listsChecked == null ||
              DateTime.now().difference(listsChecked!).inSeconds >= 30)) {
        final rows = await api.get(
          selectedTab == 2 ? '/api/ai-trading/saved' : '/api/ai-trading/runs',
        );
        if (!mounted || generation != statusGeneration) return;
        if (tab == selectedTab) {
          setState(() {
            if (selectedTab == 2)
              saved = arr(rows);
            else
              runs = rows is List ? rows : arr(obj(rows)['runs']);
            listsTab = selectedTab;
            listsChecked = DateTime.now();
          });
        }
      }
      unawaited(refreshAccount());
    } catch (e) {
      if (mounted && generation == statusGeneration)
        setState(() => error = '$e');
    } finally {
      statusLoading = false;
      if (mounted && statusAgain) {
        statusAgain = false;
        Future.microtask(loadStatus);
      }
    }
  }

  bool accountLoading = false;
  Future<void> refreshAccount() async {
    if (accountLoading ||
        !mounted ||
        (accountChecked != null &&
            DateTime.now().difference(accountChecked!).inSeconds < 30))
      return;
    accountLoading = true;
    final api = pageApi!;
    try {
      final value = obj(await api.get('/api/ai-trading/account'));
      if (mounted) setState(() => account = value);
    } catch (_) {
      /* Account availability must not block research/list refresh. */
    } finally {
      accountChecked = DateTime.now();
      accountLoading = false;
    }
  }

  void changed(String key, dynamic value) {
    setup[key] = value;
    saveTimer?.cancel();
    saveTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) persist();
    });
  }

  Future<void> persist() async {
    final api = TradeScope.of(context).api;
    final snapshot = jsonDecode(jsonEncode(setup));
    final task = saveQueue.then((_) async {
      await api.put('/api/ai-trading/setup', snapshot);
    });
    saveQueue = task.catchError((Object _) {});
    try {
      await task;
    } catch (e) {
      if (mounted) setState(() => error = 'Settings not saved: $e');
    }
  }

  Future<void> startRun() async {
    if (running) return;
    if (!account.containsKey('connected') || account['connected'] != true) {
      notice(context, 'Connect ChatGPT first.');
      return;
    }
    if ('${setup['instructions'] ?? ''}'.trim().isEmpty) {
      notice(context, 'Enter strategy instructions.');
      return;
    }
    setState(() => busy = true);
    saveTimer?.cancel();
    try {
      await saveQueue;
      await TradeScope.of(context).api.put('/api/ai-trading/setup', setup);
      final x = await TradeScope.of(context).api
          .post('/api/ai-trading/start', setup);
      if (mounted)
        setState(() {
          status = obj(x);
          tab = 1;
        });
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> connectChatGPT() async {
    try {
      final x = obj(
        await TradeScope.of(context).api.post('/api/ai-trading/connect'),
      );
      final url = Uri.tryParse('${x['verificationUrl'] ?? ''}');
      if (url == null ||
          url.scheme != 'https' ||
          ![
            'auth.openai.com',
            'chatgpt.com',
            'login.openai.com',
          ].contains(url.host))
        throw ApiError(
          'The backend did not return an approved OpenAI sign-in URL.',
        );
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('Connect ChatGPT'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Open the official sign-in page and enter this code:'),
              gap(),
              SelectableText(
                '${x['userCode'] ?? ''}',
                style: const TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w600,
                ),
              ),
              gap(),
              const Text(
                'The sign-in session is handled by your Windows backend. No API key is required.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(d),
              child: const Text('Close'),
            ),
            FilledButton(
              onPressed: () =>
                  launchUrl(url, mode: LaunchMode.externalApplication),
              child: const Text('Open sign-in page'),
            ),
          ],
        ),
      );
      listsChecked = null;
      await loadStatus();
    } catch (e) {
      if (mounted) notice(context, e);
    }
  }

  Future<void> control(String action) async {
    if (action == 'stop' &&
        !await confirm(
          context,
          'Stop AI research',
          'Stop the current research run? Saved strategies and run history remain.',
        ))
      return;
    if (!mounted) return;
    await perform(
      context,
      () => TradeScope.of(context).api.post('/api/ai-trading/control/$action'),
    );
    await loadStatus();
  }

  @override
  Widget build(BuildContext c) {
    final m = TradeScope.of(c);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'AI Trading',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.w600),
                ),
              ),
              TextButton(
                onPressed: connectChatGPT,
                child: Text(
                  account['connected'] == true
                      ? '● ChatGPT connected'
                      : 'Connect ChatGPT',
                  style: TextStyle(
                    fontSize: 10,
                    color: account['connected'] == true
                        ? m.style.good
                        : m.style.primary,
                  ),
                ),
              ),
            ],
          ),
          gap(6),
          tabs(c, ['Setup', 'Progress', 'Saved', 'Run history'], tab, (i) {
            setState(() {
              tab = i;
              statusGeneration++;
              page = 0;
            });
            loadStatus();
          }),
          gap(),
          if (error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                error,
                style: TextStyle(fontSize: 11, color: m.style.bad),
              ),
            ),
          Expanded(
            child: setup.isEmpty
                ? Center(
                    child: loading
                        ? const CircularProgressIndicator()
                        : OutlinedButton(
                            onPressed: load,
                            child: const Text('Load AI workspace'),
                          ),
                  )
                : tab == 0
                ? setupView(c)
                : tab == 1
                ? progressView(c)
                : tab == 2
                ? savedView(c)
                : historyView(c),
          ),
        ],
      ),
    );
  }

  Widget setting(
    String key,
    String label, {
    bool numeric = false,
    int lines = 1,
  }) => TextFormField(
    key: ValueKey('ai:$key'),
    initialValue: '${setup[key] ?? ''}',
    enabled: !running,
    decoration: InputDecoration(labelText: label),
    maxLines: lines,
    keyboardType: numeric
        ? const TextInputType.numberWithOptions(decimal: true)
        : TextInputType.text,
    onChanged: (v) => changed(key, numeric ? (num.tryParse(v) ?? 0) : v),
  );
  Widget setupView(BuildContext c) => Column(
    children: [
      tabs(
        c,
        ['Run setup', 'Acceptance', 'Limits & costs'],
        setupTab,
        (i) => setState(() => setupTab = i),
      ),
      gap(),
      Expanded(
        child: ListView(
          children: [
            box(
              setupTab == 0
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        pair(
                          setting('symbol', 'Market'),
                          dropdown(
                            'Timeframe',
                            '${setup['timeframe'] ?? 'M5'}',
                            timeframes,
                            (v) => setState(() => changed('timeframe', v)),
                          ),
                        ),
                        gap(),
                        pair(aiDate('from', 'From'), aiDate('to', 'To')),
                        gap(),
                        pair(
                          setting('balance', 'Balance', numeric: true),
                          setting('candidates', 'Candidates', numeric: true),
                        ),
                        gap(),
                        pair(
                          setting('minutes', 'Limit (min)', numeric: true),
                          dropdown(
                            'Model',
                            '${setup['tickModel'] ?? 'open_only'}',
                            executionModes,
                            (v) => setState(() => changed('tickModel', v)),
                          ),
                        ),
                        gap(16),
                        heading('Strategy instructions'),
                        setting(
                          'instructions',
                          'Entries, exits and restrictions',
                          lines: 4,
                        ),
                        gap(),
                        rule('stop', 'Stop-loss required', flag: true),
                        rule('noGrid', 'No martingale / grid', flag: true),
                      ],
                    )
                  : setupTab == 1
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        heading('Acceptance rules'),
                        const Text(
                          'Enabled rules are checked after modeled costs.',
                          style: TextStyle(fontSize: 11),
                        ),
                        gap(),
                        rule('pf', 'Min profit factor'),
                        rule('drawdown', 'Max drawdown', unit: '%'),
                        rule('trades', 'Minimum trades'),
                        rule('netProfit', 'Min net profit', unit: '%'),
                        gap(),
                        dropdown(
                          'Lot sizing',
                          '${obj(setup['sizing'])['mode'] ?? 'fixed'}',
                          {'fixed': 'Fixed lot', 'auto': 'Auto lot'},
                          (v) {
                            final z = obj(setup['sizing']);
                            z['mode'] = v;
                            setState(() => changed('sizing', z));
                          },
                        ),
                        gap(),
                        TextFormField(
                          initialValue:
                              '${obj(setup['sizing'])['fixedLot'] ?? .01}',
                          enabled:
                              !running &&
                              obj(setup['sizing'])['mode'] == 'fixed',
                          decoration: const InputDecoration(
                            labelText: 'Fixed lot size',
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          onChanged: (v) {
                            final z = obj(setup['sizing']);
                            z['fixedLot'] = double.tryParse(v) ?? .01;
                            changed('sizing', z);
                          },
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        heading('Trading limits & costs'),
                        rule('positions', 'Maximum open trades'),
                        rule('daily', 'Daily loss limit', unit: '%'),
                        gap(),
                        dropdown(
                          'Overnight positions',
                          '${obj(obj(setup['rules'])['overnight'])['value'] ?? 'allow'}',
                          {
                            'close': 'Close at session end',
                            'allow': 'Allow overnight',
                          },
                          (v) {
                            final rules = obj(setup['rules']);
                            rules['overnight'] = {
                              ...obj(rules['overnight']),
                              'value': v,
                            };
                            setState(() => changed('rules', rules));
                          },
                        ),
                        gap(),
                        rule('spread', 'Custom spread', unit: 'points'),
                        rule(
                          'slippage',
                          'Slippage',
                          unit: setup['slippageUnit'] == 'ticks'
                              ? 'ticks'
                              : 'points',
                        ),
                        rule(
                          'commission',
                          'Custom commission',
                          unit: 'per lot, each way',
                        ),
                        gap(),
                        const Text(
                          'Custom costs override broker defaults. The strategy chooses its session from your instructions.',
                          style: TextStyle(fontSize: 11),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
      gap(8),
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: busy || running ? null : startRun,
          icon: const Icon(Icons.auto_awesome, size: 17),
          label: Text(busy ? 'Starting…' : 'Start AI'),
        ),
      ),
      gap(5),
      const Text(
        'No live orders from AI Trading',
        style: TextStyle(fontSize: 10),
      ),
    ],
  );
  Widget aiDate(String key, String label) => OutlinedButton(
    onPressed: running
        ? null
        : () async {
            final d = await showDatePicker(
              context: context,
              initialDate: DateTime.tryParse('${setup[key]}') ?? DateTime.now(),
              firstDate: DateTime(2000),
              lastDate: DateTime.now(),
            );
            if (d != null && mounted)
              setState(
                () => changed(key, d.toIso8601String().split('T').first),
              );
          },
    child: Text('$label ${setup[key]}', style: const TextStyle(fontSize: 10)),
  );
  Widget rule(String key, String title, {bool flag = false, String? unit}) {
    final rules = obj(setup['rules']);
    final r = obj(rules[key]);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Checkbox(
            value: r['enabled'] == true,
            onChanged: running
                ? null
                : (v) {
                    rules[key] = {...r, 'enabled': v ?? false};
                    setState(() => changed('rules', rules));
                  },
          ),
          Expanded(child: Text(title, style: const TextStyle(fontSize: 12))),
          if (!flag)
            SizedBox(
              width: 100,
              child: TextFormField(
                key: ValueKey('rule-$key'),
                initialValue: '${r['value'] ?? 0}',
                enabled: !running && r['enabled'] == true,
                decoration: InputDecoration(helperText: unit),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (v) {
                  rules[key] = {
                    ...obj(rules[key]),
                    'value': num.tryParse(v) ?? 0,
                  };
                  changed('rules', rules);
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget progressView(BuildContext c) {
    final cur = obj(status['current']),
        cfg = obj(status['config']),
        results = arr(status['results']);
    final count = numv(cfg['candidates']), done = numv(status['completed']);
    return ListView(
      children: [
        box(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              heading(
                '${status['name'] ?? 'Research run'} · ${status['status'] ?? 'Ready'}',
              ),
              Text(
                '${cfg['symbol'] ?? ''} · ${cfg['timeframe'] ?? ''} · ${cfg['from'] ?? ''} → ${cfg['to'] ?? ''}',
                style: const TextStyle(fontSize: 11),
              ),
              gap(),
              LinearProgressIndicator(
                value: count > 0 ? (done / count).clamp(0, 1) : 0,
                minHeight: 5,
              ),
              gap(),
              keyval(
                'Completed / candidates',
                '${done.round()} / ${count.round()}',
              ),
              keyval('Elapsed', '${money(status['elapsed'], decimals: 0)} sec'),
              if (status['message'] != null)
                Text(
                  '${status['message']}',
                  style: const TextStyle(fontSize: 11),
                ),
              if (running)
                pair(
                  OutlinedButton(
                    onPressed: () => control(
                      status['status'] == 'paused' ? 'resume' : 'pause',
                    ),
                    child: Text(
                      status['status'] == 'paused' ? 'Resume' : 'Pause',
                    ),
                  ),
                  OutlinedButton(
                    onPressed: () => control('stop'),
                    child: const Text('Stop'),
                  ),
                ),
              if ([
                'error',
                'interrupted',
                'stopped',
              ].contains(status['status']))
                OutlinedButton(
                  onPressed: () => perform(
                    c,
                    () => TradeScope.of(c).api.post('/api/ai-trading/retry'),
                  ).then((_) => loadStatus()),
                  child: const Text('Retry current candidate'),
                ),
            ],
          ),
        ),
        gap(),
        box(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              heading('Current strategy'),
              Text('${cur['name'] ?? 'No strategy running'}'),
              gap(7),
              Text(
                '${cur['stage'] ?? 'Waiting'} · ${cur['progress'] ?? 0}% ',
                style: const TextStyle(fontSize: 12),
              ),
              if (cur['source'] != null)
                OutlinedButton(
                  onPressed: () => openPage(
                    c,
                    PineEditorPage(
                      name: '${cur['name'] ?? 'Generated strategy'}',
                      source: '${cur['source']}',
                    ),
                  ),
                  child: const Text('View full Pine code'),
                ),
            ],
          ),
        ),
        gap(),
        box(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              heading('Run summary'),
              pair(
                metric(c, 'Tried', '${done.round()}'),
                metric(
                  c,
                  'Saved',
                  '${results.where((r) => r['status'] == 'saved').length}',
                ),
              ),
              gap(),
              metric(
                c,
                'Rejected',
                '${results.where((r) => r['status'] == 'rejected').length}',
              ),
            ],
          ),
        ),
        gap(),
        heading('AI Activity'),
        aiActivity(c, arr(status['logs'])),
        gap(),
        OutlinedButton(
          onPressed: () => openPage(
            c,
            JsonDetailPage(title: 'Strategy results', data: results),
          ),
          child: const Text('Strategy results & rejection reasons'),
        ),
      ],
    );
  }

  Widget savedView(BuildContext c) {
    final rows = saved
        .map(obj)
        .where(
          (s) => '${s['name']} ${obj(s['config'])['symbol']}'
              .toLowerCase()
              .contains(search.toLowerCase()),
        )
        .where(
          (s) =>
              equityFilter == 'all' ||
              (obj(s['equityTrend'])['status'] ?? 'pending') == equityFilter,
        )
        .toList();
    final pages = math.max(1, (rows.length / 4).ceil());
    page = page.clamp(0, pages - 1);
    return Column(
      children: [
        TextField(
          decoration: InputDecoration(
            hintText: 'Search saved strategies',
            labelText: equityFilter == 'all'
                ? null
                : equityTrendLabels[equityFilter],
            suffixIcon: PopupMenuButton<String>(
              tooltip: 'Filter equity trend',
              icon: const Icon(Icons.filter_alt_outlined, size: 20),
              initialValue: equityFilter,
              onSelected: (value) => setState(() {
                equityFilter = value;
                page = 0;
              }),
              itemBuilder: (_) => equityTrendLabels.entries
                  .map((e) => PopupMenuItem(value: e.key, child: Text(e.value)))
                  .toList(),
            ),
            prefixIcon: Icon(Icons.search, size: 18),
          ),
          onChanged: (v) => setState(() {
            search = v;
            page = 0;
          }),
        ),
        gap(8),
        Row(
          children: [
            TextButton(
              onPressed: checked.length >= 2 && checked.length <= 4
                  ? () => compare(c)
                  : null,
              child: Text(
                'Compare (${checked.length})',
                style: const TextStyle(fontSize: 11),
              ),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Backup AI data',
              onPressed: () => backup(c),
              icon: const Icon(Icons.file_download_outlined, size: 20),
            ),
            IconButton(
              tooltip: 'Restore AI backup',
              onPressed: () => restore(c),
              icon: const Icon(Icons.file_upload_outlined, size: 20),
            ),
            IconButton(
              tooltip: 'Delete selected',
              onPressed: checked.isEmpty ? null : () => deleteSelected(c),
              icon: const Icon(Icons.delete_outline, size: 20),
            ),
          ],
        ),
        Expanded(
          child: rows.isEmpty
              ? empty(
                  'No saved strategies',
                  'Accepted strategies appear here after an AI research run.',
                )
              : ListView(
                  children: rows
                      .skip(page * 4)
                      .take(4)
                      .map(
                        (s) => Padding(
                          padding: const EdgeInsets.only(bottom: 9),
                          child: Card(
                            child: ListTile(
                              leading: Checkbox(
                                value: checked.contains('${s['id']}'),
                                onChanged: (v) => setState(() {
                                  if (v == true) {
                                    checked.add('${s['id']}');
                                  } else {
                                    checked.remove('${s['id']}');
                                  }
                                }),
                              ),
                              title: Text(
                                '${s['name']}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${obj(s['config'])['symbol']} · ${obj(s['config'])['timeframe']}\nNet ${money(obj(s['metrics'])['net'])} · PF ${money(obj(s['metrics'])['pf'])}',
                                    style: const TextStyle(fontSize: 10),
                                  ),
                                  equityTrendInfo(
                                    c,
                                    s['equityTrend'],
                                    compact: true,
                                  ),
                                ],
                              ),
                              trailing: const Icon(
                                Icons.chevron_right,
                                size: 18,
                              ),
                              onTap: () =>
                                  openPage(c, AiSavedDetail(id: '${s['id']}')),
                            ),
                          ),
                        ),
                      )
                      .toList(),
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

  Future<void> compare(BuildContext c) async {
    try {
      final all = await Future.wait(
        checked.map(
          (id) =>
              TradeScope.of(c).api
                  .get('/api/ai-trading/saved/${Uri.encodeComponent(id)}'),
        ),
      );
      if (c.mounted) openPage(c, AiComparePage(items: all.map(obj).toList()));
    } catch (e) {
      if (c.mounted) notice(c, e);
    }
  }

  Future<void> backup(BuildContext c) async {
    try {
      final x = await TradeScope.of(c).api.get('/api/ai-trading/backup');
      if (c.mounted) await exportText(c, 'skxtrade-ai-backup.json', pretty(x));
    } catch (e) {
      if (c.mounted) notice(c, e);
    }
  }

  Future<void> restore(BuildContext c) async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (file == null || !c.mounted) return;
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in file.readAsByteStream()) {
        if (bytes.length + chunk.length > 64 * 1024 * 1024)
          throw ApiError('Backup exceeds 64 MB');
        bytes.add(chunk);
      }
      final data = jsonDecode(utf8.decode(bytes.takeBytes()));
      if (obj(data)['format'] != 'skxtrade-ai-backup')
        throw ApiError('Choose a SKXTRADE AI backup file');
      if (!c.mounted ||
          !await confirm(
            c,
            'Restore AI backup',
            'Restore strategies and run histories? Duplicate content is skipped. Credentials are not restored.',
          ))
        return;
      if (!c.mounted) return;
      await TradeScope.of(c).api.post('/api/ai-trading/restore', {
        'backup': data,
        'restoreSetup': false,
      });
      listsChecked = null;
      await loadStatus();
      if (c.mounted) notice(c, 'AI backup restored');
    } catch (e) {
      if (c.mounted) notice(c, e);
    }
  }

  Future<void> deleteSelected(BuildContext c) async {
    if (!await confirm(
      c,
      'Delete selected strategies',
      'Delete ${checked.length} saved strategies? Export a backup first if needed.',
      action: 'Delete',
    ))
      return;
    if (!c.mounted) return;
    await perform(
      c,
      () =>
          TradeScope.of(c).api
              .post('/api/ai-trading/delete', {'ids': checked.toList()}),
    );
    checked.clear();
    listsChecked = null;
    await loadStatus();
  }

  Widget historyView(BuildContext c) {
    final rows = runs
        .map(obj)
        .where(
          (r) => '${r['name']} ${r['status']} ${obj(r['config'])['symbol']}'
              .toLowerCase()
              .contains(search.toLowerCase()),
        )
        .toList();
    return Column(
      children: [
        TextField(
          decoration: const InputDecoration(
            hintText: 'Search runs, market, or status',
            prefixIcon: Icon(Icons.search, size: 18),
          ),
          onChanged: (v) => setState(() => search = v),
        ),
        gap(),
        Expanded(
          child: rows.isEmpty
              ? empty(
                  'No run history',
                  'Completed and interrupted research runs are stored on Windows.',
                )
              : ListView(
                  children: rows
                      .map(
                        (r) => Padding(
                          padding: const EdgeInsets.only(bottom: 9),
                          child: Card(
                            child: ListTile(
                              title: Text(
                                '${r['name'] ?? r['id']}',
                                style: const TextStyle(fontSize: 13),
                              ),
                              subtitle: Text(
                                '${r['status']} · ${obj(r['config'])['symbol'] ?? ''} · ${r['completed'] ?? 0} completed',
                                style: const TextStyle(fontSize: 11),
                              ),
                              trailing: const Icon(
                                Icons.chevron_right,
                                size: 18,
                              ),
                              onTap: () =>
                                  openPage(c, AiRunDetail(id: '${r['id']}')),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
        ),
      ],
    );
  }
}

class PineEditorPage extends StatefulWidget {
  final String name, source;
  const PineEditorPage({super.key, required this.name, required this.source});
  @override
  State<PineEditorPage> createState() => _PineEditorPageState();
}

class _PineEditorPageState extends State<PineEditorPage> {
  late final TextEditingController code;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    code = TextEditingController(text: widget.source);
  }

  @override
  void dispose() {
    code.dispose();
    super.dispose();
  }

  Future<void> save(BuildContext c) async {
    final m = TradeScope.of(c);
    final latest = obj(await m.api.get('/api/shared/scripts'));
    final files = obj(latest['monaco_files']);
    files[widget.name] = {
      'source': code.text,
      'language': 'pine',
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    };
    await m.api.put('/api/shared/scripts', {'monaco_files': files});
    await m.reloadScripts();
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(
      title: Text(widget.name),
      actions: [
        IconButton(
          tooltip: 'Copy Pine',
          onPressed: () => Clipboard.setData(ClipboardData(text: code.text)),
          icon: const Icon(Icons.copy, size: 18),
        ),
        IconButton(
          tooltip: 'Download Pine',
          onPressed: () => exportText(
            c,
            '${widget.name.replaceAll(RegExp(r'[^\w.-]'), '_')}.pine',
            code.text,
          ),
          icon: const Icon(Icons.ios_share, size: 18),
        ),
      ],
    ),
    body: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Expanded(
            child: TextField(
              controller: code,
              expands: true,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
          ),
          gap(),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: busy
                      ? null
                      : () async {
                          setState(() => busy = true);
                          await perform(
                            c,
                            () => TradeScope.of(c).api.post(
                              '/api/pine/compile',
                              {'source': code.text},
                            ),
                            success: 'Pine compiled successfully',
                          );
                          if (mounted) setState(() => busy = false);
                        },
                  child: const Text('Compile'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: busy
                      ? null
                      : () => perform(
                          c,
                          () => save(c),
                          success: 'Pine strategy saved',
                        ),
                  child: const Text('Save strategy'),
                ),
              ),
            ],
          ),
          gap(5),
          const Text(
            'Saving or compiling does not deploy live trading.',
            style: TextStyle(fontSize: 10),
          ),
        ],
      ),
    ),
  );
}

class AiSavedDetail extends StatefulWidget {
  final String id;
  const AiSavedDetail({super.key, required this.id});
  @override
  State<AiSavedDetail> createState() => _AiSavedDetailState();
}

class _AiSavedDetailState extends State<AiSavedDetail> {
  Map<String, dynamic> data = {};
  List<dynamic> versions = [];
  int tab = 0;
  String error = '';
  @override
  void initState() {
    super.initState();
    Future.microtask(load);
  }

  Future<void> load() async {
    try {
      final m = TradeScope.of(context);
      final x = await Future.wait([
        m.api.get('/api/ai-trading/saved/${Uri.encodeComponent(widget.id)}'),
        m.api.get(
          '/api/ai-trading/saved/${Uri.encodeComponent(widget.id)}/versions',
        ),
      ]);
      if (mounted)
        setState(() {
          data = obj(x[0]);
          versions = arr(x[1]);
          error = '';
        });
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  @override
  Widget build(BuildContext c) {
    final m = TradeScope.of(c),
        metrics = obj(data['metrics']),
        cfg = obj(data['config']);
    final initial = numv(cfg['balance']);
    final r = {
      ...obj(data['report']),
      'initialCapital': initial,
      'net': metrics['net'],
    };
    final from =
            DateTime.tryParse('${cfg['from']}')?.millisecondsSinceEpoch ?? 0,
        to =
            DateTime.tryParse('${cfg['to']}')
                ?.add(const Duration(hours: 23, minutes: 59))
                .millisecondsSinceEpoch ??
            0;
    return Scaffold(
      appBar: AppBar(
        title: Text('${data['name'] ?? 'Saved strategy'}'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'delete') {
                if (await confirm(
                  c,
                  'Delete strategy',
                  'Delete ${data['name']} from Saved?',
                  action: 'Delete',
                )) {
                  if (c.mounted) {
                    await perform(
                      c,
                      () => m.api.post('/api/ai-trading/delete', {
                        'ids': [widget.id],
                      }),
                    );
                    if (c.mounted) Navigator.pop(c);
                  }
                }
              } else {
                await exportText(
                  c,
                  v == 'pine' ? 'strategy.pine' : 'strategy-report.json',
                  v == 'pine' ? '${data['source']}' : pretty(data),
                );
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'pine', child: Text('Download Pine')),
              PopupMenuItem(value: 'report', child: Text('Download report')),
              PopupMenuItem(value: 'delete', child: Text('Delete strategy')),
            ],
          ),
        ],
      ),
      body: data.isEmpty
          ? empty('Loading strategy', error)
          : Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Column(
                children: [
                  Text(
                    '${cfg['symbol']} · ${cfg['timeframe']} · Revision ${data['revision'] ?? 1}',
                    style: TextStyle(color: m.style.muted, fontSize: 11),
                  ),
                  gap(),
                  tabs(
                    c,
                    ['Overview', 'Trades', 'Pine code', 'Versions'],
                    tab,
                    (i) => setState(() => tab = i),
                  ),
                  gap(),
                  Expanded(
                    child: tab == 0
                        ? Column(
                            children: [
                              equityTrendInfo(c, data['equityTrend']),
                              box(
                                Column(
                                  children: [
                                    pair(
                                      metric(
                                        c,
                                        'Net profit',
                                        money(metrics['net']),
                                      ),
                                      metric(
                                        c,
                                        'Return',
                                        initial > 0
                                            ? '${money(numv(metrics['net']) / initial * 100)}%'
                                            : '—',
                                      ),
                                    ),
                                    gap(),
                                    pair(
                                      metric(
                                        c,
                                        'Profit factor',
                                        money(metrics['pf']),
                                      ),
                                      metric(
                                        c,
                                        'Max drawdown',
                                        '${money(metrics['drawdown'])}%',
                                      ),
                                    ),
                                    gap(),
                                    pair(
                                      metric(
                                        c,
                                        'Trades',
                                        '${metrics['trades'] ?? 0}',
                                      ),
                                      metric(
                                        c,
                                        'Win rate',
                                        '${money(metrics['winRate'])}%',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              gap(),
                              Expanded(
                                child: TradeChart(
                                  style: m.style,
                                  config: equityConfig(
                                    r,
                                    from ~/ 1000,
                                    to ~/ 1000,
                                    key: widget.id,
                                  ),
                                ),
                              ),
                              Text(
                                '${data['description'] ?? ''}',
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11),
                              ),
                            ],
                          )
                        : tab == 1
                        ? TradeHistoryList(
                            rows: arr(obj(data['report'])['trades']),
                            symbol: '${obj(data['config'])['symbol'] ?? ''}',
                          )
                        : tab == 2
                        ? SingleChildScrollView(
                            child: SelectableText(
                              '${data['source'] ?? ''}',
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                              ),
                            ),
                          )
                        : ListView(
                            children: [
                              const Text(
                                'Restoring creates a new revision and keeps the history.',
                                style: TextStyle(fontSize: 12),
                              ),
                              gap(),
                              for (final x in versions)
                                ListTile(
                                  title: Text('Revision ${x['revision']}'),
                                  trailing: OutlinedButton(
                                    onPressed: () async {
                                      if (await confirm(
                                        c,
                                        'Restore revision',
                                        'Restore revision ${x['revision']} as a new revision?',
                                      )) {
                                        if (c.mounted) {
                                          await perform(
                                            c,
                                            () => m.api.post(
                                              '/api/ai-trading/saved/${Uri.encodeComponent(widget.id)}/restore-version',
                                              {'revision': x['revision']},
                                            ),
                                          );
                                          await load();
                                        }
                                      }
                                    },
                                    child: const Text('Restore'),
                                  ),
                                ),
                            ],
                          ),
                  ),
                  gap(),
                  pair(
                    OutlinedButton(
                      onPressed: () => openPage(
                        c,
                        PineEditorPage(
                          name: '${data['name']}',
                          source: '${data['source']}',
                        ),
                      ),
                      child: const Text(
                        'Open in Trading',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                    FilledButton(
                      onPressed: () async {
                        final latest = obj(
                          await m.api.get('/api/shared/scripts'),
                        );
                        final files = obj(latest['monaco_files']);
                        files['${data['name']}'] = {
                          'source': data['source'],
                          'language': 'pine',
                          'updatedAt': DateTime.now().millisecondsSinceEpoch,
                        };
                        await m.api.put('/api/shared/scripts', {
                          'monaco_files': files,
                        });
                        await m.reloadScripts();
                        if (c.mounted)
                          openPage(
                            c,
                            ResearchPage(
                              optimize: false,
                              sourceName: '${data['name']}',
                            ),
                          );
                      },
                      child: const Text(
                        'Open in Backtest',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class AiComparePage extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  const AiComparePage({super.key, required this.items});
  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(title: const Text('Compare strategies')),
    body: ListView(
      padding: const EdgeInsets.all(15),
      children: [
        const Text(
          'Compare test periods, currency, and sizing before comparing returns.',
          style: TextStyle(fontSize: 12),
        ),
        gap(),
        for (final x in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: box(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  heading('${x['name']}'),
                  keyval(
                    'Market / TF',
                    '${obj(x['config'])['symbol']} / ${obj(x['config'])['timeframe']}',
                  ),
                  keyval(
                    'Period',
                    '${obj(x['config'])['from']} → ${obj(x['config'])['to']}',
                  ),
                  for (final e in obj(x['metrics']).entries)
                    keyval(e.key, '${e.value}'),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}

class AiRunDetail extends StatefulWidget {
  final String id;
  const AiRunDetail({super.key, required this.id});
  @override
  State<AiRunDetail> createState() => _AiRunDetailState();
}

class _AiRunDetailState extends State<AiRunDetail> {
  Map<String, dynamic> run = {};
  String error = '';
  @override
  void initState() {
    super.initState();
    Future.microtask(load);
  }

  Future<void> load() async {
    try {
      final x = await TradeScope.of(context).api
          .get('/api/ai-trading/runs/${Uri.encodeComponent(widget.id)}');
      if (mounted) setState(() => run = obj(x));
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(title: Text('${run['name'] ?? 'Run details'}')),
    body: run.isEmpty
        ? empty('Loading run', error)
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              box(
                Column(
                  children: [
                    keyval('Status', '${run['status']}'),
                    keyval('Completed', '${run['completed']}'),
                    keyval('Market', '${obj(run['config'])['symbol']}'),
                    keyval(
                      'Period',
                      '${obj(run['config'])['from']} → ${obj(run['config'])['to']}',
                    ),
                  ],
                ),
              ),
              gap(),
              OutlinedButton(
                onPressed: () => openPage(
                  c,
                  JsonDetailPage(
                    title: 'Results & rejection reasons',
                    data: run['results'],
                  ),
                ),
                child: const Text('Strategy results'),
              ),
              OutlinedButton(
                onPressed: () => openPage(
                  c,
                  JsonDetailPage(title: 'AI activity', data: run['logs']),
                ),
                child: const Text('AI Activity'),
              ),
              FilledButton(
                onPressed: () async {
                  if (await confirm(
                    c,
                    'Load run settings',
                    'Replace AI Setup with the settings from this historical run?',
                  )) {
                    if (c.mounted)
                      await perform(
                        c,
                        () =>
                            TradeScope.of(c).api
                                .put('/api/ai-trading/setup', run['config']),
                        success: 'Settings loaded. Reopen AI Setup to review.',
                      );
                  }
                },
                child: const Text('Load run settings'),
              ),
              OutlinedButton(
                onPressed: () async {
                  if (await confirm(
                    c,
                    'Retry run',
                    'Retry this interrupted AI research run?',
                  )) {
                    if (c.mounted)
                      await perform(
                        c,
                        () => TradeScope.of(c).api.post(
                          '/api/ai-trading/runs/${Uri.encodeComponent(widget.id)}/retry',
                        ),
                        success: 'Retry requested',
                      );
                  }
                },
                child: const Text('Retry interrupted run'),
              ),
            ],
          ),
  );
}

const equityTrendLabels = <String, String>{
  'all': 'All equity trends',
  'steady_up': 'Steady uptrend',
  'uneven_up': 'Uneven uptrend',
  'flat': 'Flat',
  'down': 'Downtrend',
  'insufficient': 'Insufficient data',
  'pending': 'Analysing',
};
Widget equityTrendInfo(BuildContext c, dynamic value, {bool compact = false}) {
  final t = obj(value), state = '${obj(value)['status'] ?? 'pending'}';
  final label = '${t['label'] ?? 'Analysing'}';
  final color = state == 'steady_up'
      ? Colors.green.shade700
      : state == 'down'
      ? Colors.red.shade700
      : Theme.of(c).colorScheme.primary;
  final reason =
      '${t['reason'] ?? 'Assessment is being calculated in the background.'}';
  return InkWell(
    onTap: () => showDialog<void>(
      context: c,
      builder: (d) => AlertDialog(
        title: Text('Equity trend · $label'),
        content: Text(
          '$reason${t.containsKey('returnPercent') ? "\n\nOverall: ${t['overall']} · Recent: ${t['recent']}\nReturn: ${t['returnPercent']}%\nRecent 25%: ${t['recentReturnPercent']}%\nCurve drawdown: ${t['maxDrawdownPercent']}%\nPositive segments: ${t['positiveSegmentsPercent']}%" : ""}\n\nHistorical equity shape only. Separate-period validation is not included.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d),
            child: const Text('Close'),
          ),
        ],
      ),
    ),
    child: Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 3 : 8),
      child: Row(
        children: [
          Icon(
            state == 'down' ? Icons.trending_down : Icons.insights_outlined,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: compact ? 10 : 12,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 5),
          Icon(Icons.info_outline, size: 13, color: color),
        ],
      ),
    ),
  );
}
