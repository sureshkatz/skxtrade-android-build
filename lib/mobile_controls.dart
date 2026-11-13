part of 'main.dart';

Future<String?> pickBrokerSymbol(
  BuildContext context,
  String current, {
  Set<String>? historySymbols,
}) async {
  final model = TradeScope.of(context);
  try {
    var catalog = model.symbols;
    if (catalog.isEmpty && historySymbols == null) {
      final response = await model.api.get('/api/symbols?limit=0');
      catalog = response is List ? response : arr(obj(response)['symbols']);
    }
    if (!context.mounted) return null;
    final names = (historySymbols ?? catalog.map(symbolName).toSet())
        .where((name) => name.isNotEmpty).toList()..sort();
    return chooseMobileOption(context, 'Broker symbols', current, {
      if (historySymbols != null) '': 'All symbols',
      for (final name in names) name: name,
    }, searchHint: 'Search broker symbols');
  } catch (error) {
    if (context.mounted) notice(context, 'Could not load broker symbols. $error');
    return null;
  }
}

Widget brokerSymbolField(
  BuildContext context, String label, String value, ValueChanged<String> changed, {
  bool enabled = true,
  Set<String>? historySymbols,
}) => InputDecorator(
  decoration: InputDecoration(labelText: label, enabled: enabled),
  child: InkWell(
    onTap: enabled ? () async {
      final selected = await pickBrokerSymbol(context, value, historySymbols: historySymbols);
      if (selected != null && context.mounted) changed(selected);
    } : null,
    child: Row(
      children: [
        Expanded(child: Text(value.isEmpty
            ? (historySymbols == null ? 'Select broker symbol' : 'All symbols')
            : value, overflow: TextOverflow.ellipsis)),
        const Tooltip(message: 'Search broker symbols', child: Icon(Icons.arrow_drop_down)),
      ],
    ),
  ),
);

Future<String?> chooseMobileOption(
  BuildContext context,
  String title,
  String current,
  Map<String, String> choices, {
  String? searchHint,
}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (sheet) {
    var query = '';
    return StatefulBuilder(
      builder: (sheet, update) {
        final media = MediaQuery.of(sheet);
        final rows = choices.entries
            .where((entry) => entry.value.toLowerCase().contains(query))
            .toList();
        return Padding(
          padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
          child: SizedBox(
            height: (media.size.height - media.viewInsets.bottom) * .67,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                children: [
                  heading(title),
                  if (searchHint != null || choices.length > 12)
                    TextField(
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        hintText: searchHint ?? 'Search',
                      ),
                      onChanged: (value) =>
                          update(() => query = value.trim().toLowerCase()),
                    ),
                  Expanded(
                    child: rows.isEmpty
                        ? Center(
                            child: Text(
                              choices.isEmpty
                                  ? 'No broker symbols loaded'
                                  : 'No matching symbols',
                            ),
                          )
                        : ListView.builder(
                            itemCount: rows.length,
                            itemBuilder: (context, i) => ListTile(
                              title: Text(rows[i].value),
                              trailing: rows[i].key == current
                                  ? const Icon(Icons.check)
                                  : null,
                              onTap: () => Navigator.pop(sheet, rows[i].key),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  },
);

/// Shared native selection sheet. Long broker/strategy lists are built lazily.
class MobileSelect extends StatelessWidget {
  final String label, value;
  final Map<String, String> options;
  final ValueChanged<String> onChanged;
  final bool compact;
  const MobileSelect({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.compact = false,
  });
  @override
  Widget build(BuildContext c) {
    final t = TradeScope.of(c).style;
    final selected = options.containsKey(value)
        ? value
        : options.keys.firstOrNull;
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(t.radius.clamp(3, 12)),
        onTap: options.isEmpty
            ? null
            : () async {
                HapticFeedback.selectionClick();
                final result = await showModalBottomSheet<String>(
                  context: c,
                  isScrollControlled: true,
                  showDragHandle: true,
                  useSafeArea: true,
                  builder: (_) => _SelectionSheet(
                    label: label,
                    value: selected ?? '',
                    options: options,
                  ),
                );
                if (result != null && c.mounted) onChanged(result);
              },
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            contentPadding: EdgeInsets.symmetric(
              horizontal: compact ? 9 : 12,
              vertical: compact ? 11 : 13,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  options[selected] ?? 'Select',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: compact ? 12 : 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: t.muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectionSheet extends StatefulWidget {
  final String label, value;
  final Map<String, String> options;
  const _SelectionSheet({
    required this.label,
    required this.value,
    required this.options,
  });
  @override
  State<_SelectionSheet> createState() => _SelectionSheetState();
}

class _SelectionSheetState extends State<_SelectionSheet> {
  String query = '';
  @override
  Widget build(BuildContext c) {
    final rows = widget.options.entries
        .where((e) => e.value.toLowerCase().contains(query.toLowerCase()))
        .toList();
    final t = TradeScope.of(c).style;
    final keyboard = MediaQuery.viewInsetsOf(c).bottom;
    final height = math.min(
      widget.options.length > 7 ? 580.0 : widget.options.length * 62.0 + 64,
      MediaQuery.sizeOf(c).height - keyboard - 110,
    );
    return AnimatedPadding(
      duration: const Duration(milliseconds: 160),
      padding: EdgeInsets.only(bottom: keyboard),
      child: SizedBox(
        height: height.clamp(160.0, 580.0),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.label,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(c),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              if (widget.options.length > 7) ...[
                gap(8),
                TextField(
                  onChanged: (s) => setState(() => query = s),
                  decoration: const InputDecoration(
                    hintText: 'Search',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                ),
                gap(10),
              ],
              Expanded(
                child: rows.isEmpty
                    ? const Center(child: Text('No matching options'))
                    : ListView.builder(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        itemCount: rows.length,
                        itemBuilder: (c, i) {
                          final row = rows[i], on = row.key == widget.value;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Material(
                              color: on ? t.soft : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                              child: ListTile(
                                title: Text(
                                  row.value,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: on
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                  ),
                                ),
                                trailing: on
                                    ? Icon(
                                        Icons.check_circle_rounded,
                                        color: t.primary,
                                        size: 22,
                                      )
                                    : null,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  Navigator.pop(c, row.key);
                                },
                              ),
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
  }
}
