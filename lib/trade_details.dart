part of 'main.dart';

dynamic firstValue(Map<String, dynamic> row, List<String> keys) {
  for (final k in keys) {
    if (row[k] != null && '${row[k]}'.isNotEmpty) return row[k];
  }
  return null;
}

String displayTime(dynamic raw) {
  if (raw == null || '$raw'.isEmpty) return '—';
  final t = chartTime(raw);
  if (t == null) return '—';
  final d = DateTime.fromMillisecondsSinceEpoch(
    (t * 1000).round(),
    isUtc: true,
  ).toLocal();
  String z(int n) => '$n'.padLeft(2, '0');
  return '${z(d.day)} ${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][d.month - 1]} ${d.year} · ${z(d.hour)}:${z(d.minute)}';
}

String tradeDirection(Map<String, dynamic> t) {
  final s = '${firstValue(t, ['side', 'type', 'direction', 'dir']) ?? ''}'
      .toLowerCase();
  return s.contains('short') || s == 'sell' || numv(s) < 0 ? 'SELL' : 'BUY';
}

Widget tradeCard(BuildContext c, Map<String, dynamic> t, {String symbol = ''}) {
  final style = TradeScope.of(c).style,
      side = tradeDirection(t),
      pnl = firstValue(t, ['pnl', 'profit']),
      qty = firstValue(t, ['qty', 'size', 'quantity', 'volume']),
      entry = firstValue(t, ['entryPrice', 'entry_price', 'entry']),
      exit = firstValue(t, ['exitPrice', 'exit_price', 'exit']);
  final details = {
    'Direction': side,
    'Symbol': t['symbol'] ?? (symbol.isEmpty ? '—' : symbol),
    'P&L': pnl == null ? '—' : money(pnl),
    'Entry price': entry ?? '—',
    'Exit price': exit ?? '—',
    'Entry time': displayTime(firstValue(t, ['entry_time', 'entryTime'])),
    'Exit time': displayTime(firstValue(t, ['exit_time', 'exitTime'])),
    'Quantity': qty ?? '—',
    'Exit reason':
        firstValue(t, ['exit_reason', 'exit_id', 'exitReason']) ?? '—',
    'Commission': t['commission'] ?? '—',
    'Ticket / entry ID':
        firstValue(t, ['ticket', 'entry_id', 'entryId']) ?? '—',
  };
  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: box(
      InkWell(
        onTap: () => showModalBottomSheet(
          context: c,
          showDragHandle: true,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (d) => FractionallySizedBox(
            heightFactor: .73,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              children: [
                heading('Trade details'),
                gap(),
                ...details.entries.map(
                  (e) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            e.key,
                            style: TextStyle(color: style.muted, fontSize: 12),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            '${e.value}',
                            textAlign: TextAlign.end,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                ExpansionTile(
                  title: const Text(
                    'Technical details',
                    style: TextStyle(fontSize: 12),
                  ),
                  children: [
                    SelectableText(
                      pretty(t),
                      style: const TextStyle(
                        fontSize: 10,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: (side == 'BUY' ? style.good : style.bad).withValues(
                      alpha: .1,
                    ),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    side,
                    style: TextStyle(
                      color: side == 'BUY' ? style.good : style.bad,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${t['symbol'] ?? symbol}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  pnl == null
                      ? '—'
                      : '${numv(pnl) > 0 ? '+' : ''}${money(pnl)}',
                  style: TextStyle(
                    color: numv(pnl) < 0 ? style.bad : style.good,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            gap(9),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Entry  ${entry ?? '—'}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                Expanded(
                  child: Text(
                    'Exit  ${exit ?? '—'}',
                    textAlign: TextAlign.end,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
            gap(5),
            Row(
              children: [
                Expanded(
                  child: Text(
                    displayTime(firstValue(t, ['entry_time', 'entryTime'])),
                    style: TextStyle(fontSize: 10, color: style.muted),
                  ),
                ),
                if (qty != null)
                  Text(
                    'Qty $qty',
                    style: TextStyle(fontSize: 10, color: style.muted),
                  ),
                const Icon(Icons.chevron_right, size: 16),
              ],
            ),
          ],
        ),
      ),
      padding: const EdgeInsets.all(12),
    ),
  );
}

class TradeHistoryList extends StatefulWidget {
  final List<dynamic> rows;
  final String symbol;
  const TradeHistoryList({super.key, required this.rows, this.symbol = ''});
  @override
  State<TradeHistoryList> createState() => _TradeHistoryListState();
}

class _TradeHistoryListState extends State<TradeHistoryList> {
  int page = 0;
  @override
  Widget build(BuildContext c) {
    if (widget.rows.isEmpty)
      return empty(
        'No trades',
        'Completed trades appear here after the strategy runs.',
      );
    final pages = math.max(1, (widget.rows.length / 5).ceil());
    page = page.clamp(0, pages - 1);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Text('${widget.rows.length} trades'),
              const Spacer(),
              TextButton.icon(
                onPressed: () =>
                    exportText(c, 'skxtrade-trades.csv', csv(widget.rows)),
                icon: const Icon(Icons.ios_share, size: 16),
                label: const Text('CSV'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            children: widget.rows
                .skip(page * 5)
                .take(5)
                .map((t) => tradeCard(c, obj(t), symbol: widget.symbol))
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
            Text('${page + 1} / $pages', style: const TextStyle(fontSize: 12)),
            TextButton(
              onPressed: page + 1 < pages ? () => setState(() => page++) : null,
              child: const Text('Next'),
            ),
          ],
        ),
      ],
    );
  }
}

String brokerOutcome(Map<String, dynamic> r, {bool closing = false}) {
  final code = numv(r['retcode']).toInt();
  if (r['ok'] == false) return 'Failed';
  if (r['orderType'] == 'limit' &&
      (code == 10008 || code == 10009) &&
      numv(r['deal']) == 0) {
    return 'Limit order placed';
  }
  if (code == 10009) return closing ? 'Position closed' : 'Order executed';
  if (code == 10010) return closing ? 'Partially closed' : 'Partially filled';
  if (code == 10008) return 'Pending broker execution';
  return 'Execution not confirmed';
}

final _brokerBusy = <String>{};
Future<void> brokerAction(
  BuildContext c,
  String key,
  Future<dynamic> Function() request, {
  bool closing = false,
}) async {
  if (!_brokerBusy.add(key)) return;
  final m = TradeScope.of(c);
  bool waiting = true;
  showDialog<void>(
    context: c,
    barrierDismissible: false,
    builder: (d) => PopScope(
      canPop: false,
      child: const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Expanded(child: Text('Waiting for broker response…')),
          ],
        ),
      ),
    ),
  ).whenComplete(() => waiting = false);
  try {
    final r = obj(await request());
    if (!c.mounted) return;
    if (waiting) {
      Navigator.of(c, rootNavigator: true).pop();
      waiting = false;
    }
    unawaited(m.refresh());
    await showDialog<void>(
      context: c,
      builder: (d) => AlertDialog(
        title: Text(brokerOutcome(r, closing: closing)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final e in {
                'Ticket': r['ticket'],
                'Deal': r['deal'],
                'Symbol': r['symbol'],
                'Fill price': r['price'],
                'Filled lots': r['closed_volume'] ?? r['volume'],
                'Remaining lots': r['remaining_volume'],
                'Broker code': r['retcode'],
                'Broker message': r['comment'],
              }.entries)
                if (e.value != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text('${e.key}: ${e.value}'),
                  ),
              if (numv(r['retcode']) != 10009)
                const Text(
                  'Check Positions and broker history before trying again.',
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  } catch (e) {
    if (c.mounted) {
      if (waiting) {
        Navigator.of(c, rootNavigator: true).pop();
        waiting = false;
      }
      await showDialog<void>(
        context: c,
        builder: (d) => AlertDialog(
          title: Text(
            e is ApiError && e.status != 0
                ? 'Request failed'
                : 'Execution status unknown',
          ),
          content: Text(
            '$e\n\nRefresh Positions and check broker history before retrying.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(d),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      await m.refresh();
    }
  } finally {
    _brokerBusy.remove(key);
  }
}

String humanActivity(String value) {
  var s = value.replaceAllMapped(
    RegExp(r'\b(\d{10}) to (\d{10})\b'),
    (m) => '${displayTime(m[1])} to ${displayTime(m[2])}',
  );
  s = s.replaceAll(RegExp(r'\s*[·|]\s*execution\s+[a-zA-Z0-9_-]+'), '');
  return s.replaceAllMapped(
    RegExp(r'\b(\d+) candles\b'),
    (m) => '${money(int.parse(m[1]!), decimals: 0)} candles',
  );
}

Widget aiActivity(BuildContext c, List<dynamic> raw) {
  final style = TradeScope.of(c).style;
  final groups = <List<Map<String, dynamic>>>[];
  for (final x in raw.reversed.take(60)) {
    final e = obj(x);
    if (groups.isEmpty || groups.last.first['candidate'] != e['candidate'])
      groups.add([]);
    groups.last.add(e);
  }
  return Column(
    children: groups.map((events) {
      final message = '${events.first['message'] ?? ''}',
          stage = '${events.first['step'] ?? 'Activity'}',
          lower = message.toLowerCase();
      final label = lower.contains('saved')
          ? 'Saved'
          : lower.contains('failed') || lower.contains('error')
          ? 'Failed'
          : lower.contains('required') || lower.contains('reject')
          ? 'Rejected'
          : stage;
      final color = label == 'Saved'
          ? style.good
          : label == 'Failed' || label == 'Rejected'
          ? style.bad
          : style.primary;
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: box(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    label == 'Saved'
                        ? Icons.check_circle_outline
                        : label == 'Failed'
                        ? Icons.error_outline
                        : Icons.auto_awesome,
                    size: 17,
                    color: color,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      '${events.first['candidate'] != null ? '#${events.first['candidate']} · ' : ''}$label',
                      style: TextStyle(
                        color: color,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    displayTime(
                      events.first['time'] ?? events.first['timestamp'],
                    ).replaceFirst('—', ''),
                    style: TextStyle(fontSize: 9, color: style.muted),
                  ),
                ],
              ),
              gap(6),
              Text(
                humanActivity(message),
                style: const TextStyle(fontSize: 12),
              ),
              if (events.length > 1)
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(
                    '${events.length - 1} earlier steps',
                    style: const TextStyle(fontSize: 11),
                  ),
                  children: events
                      .skip(1)
                      .map(
                        (e) => ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            Icons.circle,
                            size: 6,
                            color: style.primary,
                          ),
                          title: Text(
                            '${e['step'] ?? 'Activity'}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            humanActivity('${e['message'] ?? ''}'),
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                dense: true,
                title: const Text(
                  'Technical log',
                  style: TextStyle(fontSize: 10),
                ),
                children: [
                  SelectableText(
                    pretty(events),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10,
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
  );
}
