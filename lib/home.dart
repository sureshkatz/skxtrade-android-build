part of 'main.dart';

class HomePage extends StatelessWidget {
  final VoidCallback onTrade;
  const HomePage({super.key, required this.onTrade});

  @override
  Widget build(BuildContext context) {
    final m = TradeScope.of(context), t = m.style;
    final a = obj(m.snapshot['account']);
    final has = a.isNotEmpty;
    final balance = numv(a['balance']), equity = numv(a['equity']);
    final floating = numv(a['profit'] ?? (equity - balance));
    final daily = m.snapshot['todayRealized'];
    final opening = balance - numv(daily);
    final currency = '${a['currency'] ?? '—'}';
    final running = m.strategies.where((s) => s['status'] == 'Running').length;
    final paused = m.strategies.where((s) => s['status'] == 'Paused').length;
    final company = '${a['company'] ?? ''}'.trim();
    final mode = a['trade_mode'] == 0
        ? 'DEMO'
        : a['trade_mode'] == 2
        ? 'LIVE'
        : 'ACCOUNT';
    String amount(dynamic x) => x == null ? '—' : money(x);
    String signed(dynamic x) =>
        x == null ? '—' : '${numv(x) > 0 ? '+' : ''}${money(x)}';
    void positions(bool pending) => openPage(
      context,
      Scaffold(
        appBar: AppBar(title: Text(pending ? 'Pending orders' : 'Positions')),
        body: SafeArea(child: PositionsPage(initialPending: pending)),
      ),
    );
    final tools = <(IconData, String, VoidCallback)>[
      (Icons.candlestick_chart_outlined, 'Trading', onTrade),
      (
        Icons.show_chart_rounded,
        'Backtest',
        () => openPage(context, const ResearchPage(optimize: false)),
      ),
      (
        Icons.tune_rounded,
        'Optimize',
        () => openPage(context, const ResearchPage(optimize: true)),
      ),
      (
        Icons.auto_awesome_outlined,
        'AI Trading',
        () => openPage(context, const AiFullPage()),
      ),
      (
        Icons.desktop_windows_outlined,
        'MetaTrader 5',
        () => openPage(context, const Mt5Page()),
      ),
    ];
    return LayoutBuilder(
      builder: (c, constraints) {
        final short = constraints.maxHeight < 640;
        final compact = constraints.maxHeight < 740;
        final pad = short ? 12.0 : 16.0;
        final cardPad = short ? 10.0 : 14.0;
        final label = short ? 10.0 : 11.5;
        final number = short ? 14.0 : 16.0;
        Widget caption(String s) => Text(
          s,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: label, color: t.muted),
        );
        Widget datum(String name, String value, {Color? color}) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            caption(name),
            const SizedBox(height: 3),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: number,
                fontWeight: FontWeight.w600,
                color: color ?? t.ink,
              ),
            ),
          ],
        );
        Widget panel(Widget child) => SizedBox(
          width: double.infinity,
          child: Material(
            color: t.paper,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              side: BorderSide(color: t.border),
              borderRadius: BorderRadius.circular(t.radius),
            ),
            child: Padding(padding: EdgeInsets.all(cardPad), child: child),
          ),
        );
        return Padding(
          padding: EdgeInsets.fromLTRB(pad, short ? 4 : 8, pad, 6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: short ? 38 : 44,
                child: Row(
                  children: [
                    brand(),
                    const Spacer(),
                    IconButton.filledTonal(
                      tooltip: 'Settings',
                      style: IconButton.styleFrom(
                        backgroundColor: t.paper,
                        side: BorderSide(color: t.border),
                      ),
                      onPressed: () => openPage(c, const SettingsPage()),
                      icon: const Icon(Icons.settings_outlined, size: 20),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  CircleAvatar(
                    radius: short ? 14 : 17,
                    backgroundColor: t.soft,
                    foregroundColor: t.primary,
                    child: Text(
                      company.isEmpty ? 'M' : company.substring(0, 1),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          company.isEmpty ? 'Your trading account' : company,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: short ? 12 : 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        caption(
                          '${a['server'] ?? 'Connect your Windows terminal'} · ${a['login'] ?? '—'}',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: t.soft,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          mode,
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: t.primary,
                          ),
                        ),
                      ),
                      if (a['leverage'] != null) caption('1:${a['leverage']}'),
                    ],
                  ),
                ],
              ),
              panel(
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: caption('Account balance')),
                        caption(currency),
                      ],
                    ),
                    Text(
                      has ? money(balance) : '—',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: short
                            ? 28
                            : compact
                            ? 32
                            : 36,
                        height: 1.2,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -1.2,
                      ),
                    ),
                    Divider(height: short ? 12 : 20),
                    ValueListenableBuilder<Map<String, dynamic>>(
                      valueListenable: m.accountQuotes,
                      builder: (context, _, child) {
                        final live = m.liveAccount;
                        final profit = numv(live['profit'] ?? floating);
                        return Row(
                          children: [
                            Expanded(
                              child: datum(
                                'Current equity',
                                has ? money(live['equity'] ?? equity) : '—',
                              ),
                            ),
                            Expanded(
                              child: datum(
                                'Unrealized P&L',
                                has ? signed(profit) : '—',
                                color: profit >= 0 ? t.good : t.bad,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: datum(
                      'Realized P&L · UTC today',
                      signed(daily),
                      color: numv(daily) >= 0 ? t.good : t.bad,
                    ),
                  ),
                  if (daily != null && opening > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: (numv(daily) >= 0 ? t.good : t.bad).withValues(
                          alpha: .08,
                        ),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Text(
                        '${numv(daily) > 0 ? '+' : ''}${money(numv(daily) / opening * 100)}%',
                        style: TextStyle(
                          fontSize: label,
                          fontWeight: FontWeight.w600,
                          color: numv(daily) >= 0 ? t.good : t.bad,
                        ),
                      ),
                    ),
                ],
              ),
              panel(
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Funds & margin',
                            style: TextStyle(
                              fontSize: short ? 12 : 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        caption(currency),
                      ],
                    ),
                    SizedBox(height: short ? 5 : 9),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: datum('Available', amount(a['free_margin'])),
                        ),
                        Expanded(
                          child: datum('Used margin', amount(a['margin'])),
                        ),
                        Expanded(
                          child: datum(
                            'Margin level',
                            a['margin_level'] != null
                                ? '${money(a['margin_level'])}%'
                                : numv(a['margin']) > 0
                                ? '${money(equity / numv(a['margin']) * 100)}%'
                                : '—',
                          ),
                        ),
                      ],
                    ),
                    Divider(height: short ? 10 : 16),
                    Row(
                      children: [
                        for (final pending in [false, true])
                          Expanded(
                            child: InkWell(
                              onTap: () => positions(pending),
                              borderRadius: BorderRadius.circular(6),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 5,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${arr(m.snapshot[pending ? 'orders' : 'positions']).length} ${pending ? 'Pending orders' : 'Open positions'}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: label,
                                          fontWeight: FontWeight.w500,
                                          color: t.primary,
                                        ),
                                      ),
                                    ),
                                    Icon(
                                      Icons.chevron_right_rounded,
                                      size: 16,
                                      color: t.muted,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Trading tools',
                    style: TextStyle(
                      fontSize: short ? 12 : 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: short ? 6 : 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: tools
                        .map(
                          (tool) => Expanded(
                            child: Semantics(
                              button: true,
                              label: tool.$2,
                              child: InkWell(
                                onTap: tool.$3,
                                borderRadius: BorderRadius.circular(10),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: short ? 35 : 42,
                                      height: short ? 35 : 42,
                                      decoration: BoxDecoration(
                                        color: t.soft,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Icon(
                                        tool.$1,
                                        size: short ? 20 : 23,
                                        color: t.primary,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      tool.$2 == 'MetaTrader 5'
                                          ? 'MT5'
                                          : tool.$2,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: short ? 9 : 10.5,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
              panel(
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Strategy connections',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: short ? 12 : 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: () =>
                              openPage(c, const Mt5Page(initialTab: 1)),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 2,
                              vertical: 5,
                            ),
                            child: Text(
                              'View all',
                              style: TextStyle(
                                fontSize: label,
                                color: t.primary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: short ? 3 : 7),
                    Row(
                      children: [
                        for (final stat in <(String, String, Color)>[
                          ('$running', 'Running', t.good),
                          ('$paused', 'Paused', t.muted),
                          ('${m.strategies.length}', 'Total', t.ink),
                        ])
                          Expanded(
                            child: Row(
                              children: [
                                Text(
                                  stat.$1,
                                  style: TextStyle(
                                    fontSize: number,
                                    fontWeight: FontWeight.w600,
                                    color: stat.$3,
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Flexible(
                                  child: Text(
                                    stat.$2,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: label,
                                      color: t.muted,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              InkWell(
                onTap: () => showConnection(c),
                child: SizedBox(
                  height: 20,
                  child: Row(
                    children: [
                      Icon(
                        Icons.circle,
                        size: 6,
                        color: m.connection == 'Connected' ? t.good : t.bad,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          m.connection,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 10, color: t.muted),
                        ),
                      ),
                      Text(
                        m.updated == null
                            ? 'Waiting for server'
                            : 'Updated ${TimeOfDay.fromDateTime(m.updated!).format(c)}',
                        style: TextStyle(fontSize: 10, color: t.muted),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void showConnection(BuildContext c) {
    final m = TradeScope.of(c);
    showModalBottomSheet(
      context: c,
      showDragHandle: true,
      useSafeArea: true,
      builder: (d) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              m.connection,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            gap(),
            Text(m.error.isEmpty ? 'Connected to ${m.api.address}' : m.error),
            gap(),
            Text(
              m.patchAvailable ? 'Android backend update available.' : 'Install the Windows mobile-backend update to enable daily P&L and research jobs.',
              style: TextStyle(color: m.style.muted),
            ),
            gap(20),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(d);
                m.refresh();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh connection'),
            ),
          ],
        ),
      ),
    );
  }
}
