part of 'main.dart';

const researchPeriods = {
  '1W': '1 Week',
  '1M': '1 Month',
  '3M': '3 Months',
  '6M': '6 Months',
  '1Y': '1 Year',
  '1.5Y': '1.5 Years',
  '2Y': '2 Years',
  '3Y': '3 Years',
  '5Y': '5 Years',
  'custom': 'Custom',
};

DateTime presetStart(String period, DateTime end) {
  if (period == '1W') return DateTime(end.year, end.month, end.day - 6);
  final months = const {
    '1M': 1, '3M': 3, '6M': 6, '1Y': 12, '1.5Y': 18,
    '2Y': 24, '3Y': 36, '5Y': 60,
  }[period]!;
  final month = DateTime(end.year, end.month - months);
  final last = DateTime(month.year, month.month + 1, 0).day;
  return DateTime(month.year, month.month, end.day.clamp(1, last).toInt());
}

String dateOnly(DateTime value) => value.toIso8601String().substring(0, 10);

Future<String?> pickBrokerSymbol(BuildContext context, String current, {Set<String>? historySymbols}) async {
  final app = TradeScope.of(context);
  try {
    var catalog = app.symbols;
    if (catalog.isEmpty && historySymbols == null) {
      final response = await app.api.get('/api/symbols?limit=0');
      catalog = response is List ? response : arr(obj(response)['symbols']);
    }
    if (!context.mounted) return null;
    final names = (historySymbols ?? catalog.map(symbolName).toSet())
        .where((name) => name.isNotEmpty).toList()..sort();
    final choices = {
      if (historySymbols != null) '': 'All symbols',
      for (final name in names) name: name,
    };
    if (choices.isEmpty) {
      notice(context, 'No broker symbols are available. Check the MT5 connection.');
      return null;
    }
    return chooseMobileOption(
      context, 'Broker symbols', current, choices,
      searchHint: 'Search broker symbols',
    );
  } catch (error) {
    if (context.mounted) notice(context, 'Could not load broker symbols. $error');
    return null;
  }
}

Widget brokerSymbolField(
  BuildContext context,
  String current,
  ValueChanged<String> onChanged, {
  String label = 'Broker symbol',
  bool enabled = true,
  Set<String>? historySymbols,
}) => MobileSelect(
  label: label,
  value: current,
  options: {if (current.isNotEmpty) current: current
    else if (historySymbols != null) '': 'All symbols'},
  tooltip: 'Search broker symbols',
  onChanged: enabled ? onChanged : null,
  openPicker: enabled ? () => pickBrokerSymbol(context, current, historySymbols: historySymbols) : null,
);

String? weekendCloseError(Map<String, dynamic> value) {
  if (value['enabled'] != true) return null;
  if (!RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$').hasMatch('${value['fridayClose']}')) {
    return 'Enter the Friday market close time.';
  }
  final minutes = int.tryParse('${value['minutesBefore']}');
  if (minutes == null || minutes < 0 || minutes > 1440) {
    return 'Enter whole minutes before close, from 0 to 1440.';
  }
  return null;
}

class WeekendCloseFields extends StatelessWidget {
  final Map<String, dynamic> value;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final bool enabled;

  const WeekendCloseFields({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  void update(String key, dynamic next) => onChanged({...value, key: next});

  @override
  Widget build(BuildContext context) {
    final on = value['enabled'] == true;
    final close = '${value['fridayClose'] ?? ''}';
    final hour = int.tryParse(close.split(':').first);
    final minute = int.tryParse(close.split(':').last);
    final validation = weekendCloseError(value);
    String? cutoff;
    if (on && validation == null) {
      final lead = int.parse('${value['minutesBefore']}');
      final clock = hour! * 60 + minute! - lead;
      final time = TimeOfDay(hour: (clock % 1440) ~/ 60, minute: clock % 60);
      cutoff = '${clock < 0 ? 'Thursday' : 'Friday'} ${time.format(context)} broker time';
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MobileSelect(
          label: 'Weekend Close Protection',
          value: on ? 'on' : 'off',
          options: const {'off': 'Off', 'on': 'On'},
          onChanged: enabled ? (v) => update('enabled', v == 'on') : null,
        ),
        if (on) ...[
          gap(8),
          pair(
            OutlinedButton(
              onPressed: !enabled ? null : () async {
                final picked = await showTimePicker(
                  context: context,
                  initialTime: hour == null || minute == null || hour > 23 ||
                          hour < 0 || minute > 59 || minute < 0
                      ? TimeOfDay.now()
                      : TimeOfDay(hour: hour, minute: minute),
                );
                if (picked == null || !context.mounted) return;
                final h = picked.hour.toString().padLeft(2, '0');
                final m = picked.minute.toString().padLeft(2, '0');
                update('fridayClose', '$h:$m');
              },
              child: Text(close.isEmpty ? 'Friday market close' : 'Friday close $close'),
            ),
            TextFormField(
              initialValue: '${value['minutesBefore'] ?? ''}',
              enabled: enabled,
              decoration: const InputDecoration(labelText: 'Minutes before close'),
              keyboardType: TextInputType.number,
              onChanged: (v) => update('minutesBefore', v.trim()),
            ),
          ),
          gap(6),
          Text(cutoff == null ? validation! : 'Close positions $cutoff',
              style: const TextStyle(fontSize: 11)),
        ],
      ],
    );
  }
}

class LivePineFields extends StatefulWidget {
  final String source;
  final Map<String, dynamic> values;
  final bool enabled;

  const LivePineFields({
    super.key,
    required this.source,
    required this.values,
    this.enabled = true,
  });

  @override
  State<LivePineFields> createState() => _LivePineFieldsState();
}

class _LivePineFieldsState extends State<LivePineFields> {
  late final inputs = parsePineInputs(widget.source);

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      heading('Pine strategy inputs'),
      if (inputs.isEmpty) const Text('No editable inputs found.'),
      for (final p in inputs)
        Padding(
          padding: const EdgeInsets.only(bottom: 7),
          child: input(p),
        ),
    ],
  );

  Widget input(PineInput p) {
    final current = widget.values[p.name] ?? p.value;
    if (p.type == 'bool') {
      return SwitchListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        title: Text(p.title),
        value: current == true,
        onChanged: !widget.enabled ? null :
          (v) => setState(() => widget.values[p.name] = v),
      );
    }
    if (p.options.isNotEmpty) {
      return MobileSelect(
        label: p.title, value: '$current',
        options: {for (final option in p.options) option: option},
        onChanged: !widget.enabled ? null :
          (v) => setState(() => widget.values[p.name] = v),
      );
    }
    return TextFormField(
      initialValue: '$current',
      enabled: widget.enabled,
      decoration: InputDecoration(labelText: p.title),
      keyboardType: p.numeric
          ? TextInputType.numberWithOptions(decimal: p.type == 'float', signed: true)
          : TextInputType.text,
      validator: (v) {
        if (!p.numeric) return null;
        final n = p.type == 'int' ? int.tryParse(v?.trim() ?? '') : double.tryParse(v?.trim() ?? '');
        if (n == null || !n.isFinite) return 'Enter a valid ${p.type == 'int' ? 'whole number' : 'number'}.';
        if (p.min != null && n < p.min!) return 'Minimum: ${p.min}';
        if (p.max != null && n > p.max!) return 'Maximum: ${p.max}';
        return null;
      },
      onSaved: (v) {
        if (p.type == 'int') {
          widget.values[p.name] = int.parse(v!.trim());
        } else if (p.type == 'float') {
          widget.values[p.name] = double.parse(v!.trim());
        } else if (v != null) {
          widget.values[p.name] = v;
        }
      },
    );
  }
}

class EditLivePinePage extends StatefulWidget {
  final Map<String, dynamic> connection;
  const EditLivePinePage({super.key, required this.connection});

  @override
  State<EditLivePinePage> createState() => _EditLivePinePageState();
}

class _EditLivePinePageState extends State<EditLivePinePage> {
  final form = GlobalKey<FormState>();
  late final values = obj(widget.connection['pineInputs']);
  bool busy = false;

  Future<void> save() async {
    if (form.currentState?.validate() != true) return;
    form.currentState!.save();
    final model = TradeScope.of(context);
    final hasPositions = obj(widget.connection['tickets']).isNotEmpty ||
        arr(widget.connection['tickets']).isNotEmpty;
    setState(() => busy = true);
    try {
      if (hasPositions && !await confirm(context, 'Save Pine inputs?',
          'This strategy still tracks positions in MT5.', action: 'Save')) return;
      if (!mounted) return;
      final id = Uri.encodeComponent('${widget.connection['id']}');
      await model.api.put('/api/mt5/strategies/$id/inputs', {
        'pineInputs': values,
        if (hasPositions) 'confirmOpenPositions': true,
      });
      await model.refresh();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) notice(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.connection;
    final editable = row['status'] == 'Stopped';
    return Scaffold(
      appBar: AppBar(title: Text(editable ? 'Edit Pine inputs' : 'Pine inputs')),
      body: Form(
        key: form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Text('${row['name']} · ${row['symbol']}'),
          if (!editable) const Text('Stop the strategy to edit its inputs.'),
          gap(),
          LivePineFields(source: '${row['source'] ?? obj(TradeScope.of(context).scripts[row['name']])['source'] ?? ''}', values: values,
            enabled: editable && !busy),
          if (editable)
            FilledButton(onPressed: busy ? null : save, child: const Text('Save inputs')),
        ]),
      ),
    );
  }
}
