part of 'main.dart';

class ChatGPTSettingsPage extends StatefulWidget {
  const ChatGPTSettingsPage({super.key});

  @override
  State<ChatGPTSettingsPage> createState() => _ChatGPTSettingsPageState();
}

class _ChatGPTSettingsPageState extends State<ChatGPTSettingsPage> with WidgetsBindingObserver {
  Map<String, dynamic> account = {};
  Map<String, dynamic> signIn = {};
  String? draft;
  String? error;
  bool busy = false;
  bool initialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && signIn.isNotEmpty) update();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (initialized) return;
    initialized = true;
    Future.microtask(() {
      if (mounted) update();
    });
  }

  Future<void> update([String? action]) async {
    if (busy) return;
    final api = TradeScope.of(context).api;
    setState(() { busy = true; error = null; });
    try {
      if (action == 'connect') {
        final pending = obj(await api.post('/api/ai-trading/connect'));
        final url = Uri.tryParse('${pending['verificationUrl'] ?? ''}');
        if (url == null || url.scheme != 'https' ||
            !const {'auth.openai.com', 'chatgpt.com', 'login.openai.com'}.contains(url.host)) {
          throw ApiError('The server did not return an approved ChatGPT sign-in page.');
        }
        if (mounted) setState(() => signIn = pending);
      } else if (action == 'disconnect') {
        await api.post('/api/ai-trading/disconnect', {'confirm': true});
        if (mounted) setState(() { draft = null; signIn = {}; });
      } else if (action == 'save') {
        final model = draft!;
        await api.put('/api/ai-trading/chatgpt-settings', {'model': model});
        if (mounted) setState(() { account['model'] = model; draft = null; });
      }
      final next = obj(await api.get('/api/ai-trading/chatgpt-settings'));
      if (mounted) setState(() {
        account = next;
        if (account['connected'] == true) signIn = {};
        if (account['connected'] != true || account['active'] == true) draft = null;
      });
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final connected = account['connected'] == true;
    final active = account['active'] == true;
    final saved = '${account['model'] ?? ''}';
    final email = '${account['email'] ?? ''}';
    final models = {
      '': 'Automatic (default)',
      for (final row in arr(account['models']).map(obj))
        if (row['id'] is String && row['id'] != '') '${row['id']}': '${row['label'] ?? row['id']}',
    };
    final message = (error ?? account['error'] ?? '').toString().trim();
    return Scaffold(
      appBar: AppBar(title: const Text('ChatGPT'), actions: [
        IconButton(
          onPressed: busy ? null : () => update(),
          icon: const Icon(Icons.refresh),
          tooltip: 'Refresh account',
        ),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (busy) const LinearProgressIndicator(),
        if (message.isNotEmpty) ...[gap(), Text(message)],
        gap(),
        box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          heading(connected ? 'Connected' : account.isEmpty ? 'Checking connection' : 'Disconnected'),
          if (connected) Text(email.isEmpty ? 'Account email unavailable' : email),
          if (active) const Text('Stop the current AI run to change the connection or model.'),
          gap(),
          if (connected)
            OutlinedButton(
              onPressed: busy || active ? null : () async {
                final confirmed = await confirm(context, 'Disconnect ChatGPT?',
                  'Disconnect the ChatGPT account from this SKXTRADE workspace.',
                  action: 'Disconnect');
                if (confirmed && context.mounted) await update('disconnect');
              },
              child: const Text('Disconnect'),
            )
          else
            OutlinedButton(
              onPressed: busy || account.isEmpty ? null : () => update('connect'),
              child: Text(signIn.isEmpty ? 'Connect ChatGPT' : 'Request a new code'),
            ),
          if (signIn.isNotEmpty) ...[
            gap(),
            const Text('Enter this code on the ChatGPT sign-in page.'),
            SelectableText('${signIn['userCode'] ?? ''}',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            Wrap(spacing: 8, children: [
              FilledButton(
                onPressed: busy ? null : () async {
                  final opened = await launchUrl(Uri.parse('${signIn['verificationUrl']}'),
                    mode: LaunchMode.externalApplication);
                  if (!opened && context.mounted) notice(context, 'Could not open the sign-in page.');
                },
                child: const Text('Open sign-in page'),
              ),
              TextButton(onPressed: busy ? null : () => update(),
                child: const Text('Check connection')),
            ]),
          ],
        ])),
        gap(),
        box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          heading('Model'),
          if (draft == null)
            Row(children: [
              Expanded(child: Text(models[saved] ?? saved)),
              OutlinedButton(
                onPressed: busy || !connected || active ? null :
                  () => setState(() => draft = models.containsKey(saved) ? saved : ''),
                child: const Text('Edit'),
              ),
            ])
          else ...[
            MobileSelect(label: 'Choose a model', value: draft!, options: models,
              onChanged: busy ? null : (v) => setState(() => draft = v)),
            gap(),
            Wrap(spacing: 8, children: [
              FilledButton(onPressed: busy ? null : () => update('save'),
                child: const Text('Save')),
              TextButton(onPressed: busy ? null : () => setState(() => draft = null),
                child: const Text('Cancel')),
            ]),
          ],
        ])),
      ]),
    );
  }
}
