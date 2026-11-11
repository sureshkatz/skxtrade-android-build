import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';

import 'api.dart';
import 'themes.dart';
import 'chart.dart';
import 'original_chart.dart';
import 'pine_inputs.dart';
part 'research.dart';
part 'ai.dart';
part 'mt5.dart';
part 'home.dart';
part 'mobile_controls.dart';
part 'trade_details.dart';
part 'closed_positions.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'TradingView Lightweight Charts',
    ], await rootBundle.loadString('assets/CHART_LICENSE.txt'));
    yield LicenseEntryWithLineBreaks([
      'Figtree',
    ], await rootBundle.loadString('assets/fonts/OFL.txt'));
  });
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'OpenAlgo Charts 2.6.0',
    ], await rootBundle.loadString('assets/openalgo/LICENSE.txt'));
  });
  final model = AppModel();
  await model.initialize();
  runApp(TradeApp(model: model));
}

class AppModel extends ChangeNotifier with WidgetsBindingObserver {
  final TradeApi api;
  AppModel({TradeApi? api}) : api = api ?? TradeApi();
  late SharedPreferences prefs;
  TradeStyle style = styles.first;
  Map<String, dynamic> snapshot = {}, scripts = {}, protection = {};
  List<dynamic> strategies = [], symbols = [];
  String connection = 'Offline',
      error = '',
      selectedSymbol = '',
      selectedTf = 'M30';
  bool loading = false,
      hasSession = false,
      patchAvailable = false,
      resumed = true;
  Timer? timer;
  DateTime? updated;
  final ValueNotifier<Map<String, dynamic>> marketQuote = ValueNotifier({});
  WebSocket? _marketSocket;
  Timer? _marketRetry;
  int _marketGeneration = 0;
  final ValueNotifier<String> marketStatus = ValueNotifier('Connecting');

  void connectMarket() {
    final generation = ++_marketGeneration;
    _marketRetry?.cancel();
    unawaited(_marketSocket?.close());
    _marketSocket = null;
    marketQuote.value = {};
    marketStatus.value = 'Connecting';
    if (hasSession && resumed && selectedSymbol.isNotEmpty) {
      unawaited(_listenMarket(generation, selectedSymbol, selectedTf));
    }
  }

  Future<void> _listenMarket(int generation, String symbol, String timeframe) async {
    try {
      final socket = await api.marketSocket(symbol, timeframe);
      if (generation != _marketGeneration) {
        await socket.close();
        return;
      }
      _marketSocket = socket;
      socket.pingInterval = const Duration(seconds: 15);
      await for (final raw in socket) {
        if (generation != _marketGeneration) break;
        if (raw is! String) continue;
        final update = obj(jsonDecode(raw));
        if (update['error'] != null) {
          marketStatus.value = 'Price feed delayed';
          continue;
        }
        marketStatus.value = 'MT5 feed connected';
        final ticks = arr(update['ticks']);
        if (ticks.isNotEmpty) {
          marketQuote.value = {...obj(ticks.last), 'ticks': ticks,
            'chartSignals': update['signals'], 'resync': update['resync']};
        }
      }
    } catch (_) {
      // Keep the last quote visible during a reconnect.
    } finally {
      if (generation == _marketGeneration && hasSession && resumed) {
        unawaited(_marketSocket?.close());
        _marketSocket = null;
        marketStatus.value = 'Price feed reconnecting';
        _marketRetry = Timer(const Duration(seconds: 1), () {
          if (generation == _marketGeneration) {
            unawaited(_listenMarket(generation, symbol, timeframe));
          }
        });
      }
    }
  }
  Future<void> initialize() async {
    WidgetsBinding.instance.addObserver(this);
    prefs = await SharedPreferences.getInstance();
    style = styles.firstWhere(
      (s) => s.id == prefs.getString('theme'),
      orElse: () => styles.first,
    );
    selectedSymbol = prefs.getString('symbol') ?? '';
    selectedTf = prefs.getString('timeframe') ?? 'M30';
    try {
      await api.restore();
      if (api.server != null) hasSession = await api.checkSession();
    } catch (e) {
      error = '$e';
    }
    if (hasSession) {
      unawaited(refresh());
      connectMarket();
      timer = Timer.periodic(const Duration(seconds: 5), (_) {
        if (resumed) refresh();
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    resumed = state == AppLifecycleState.resumed;
    if (resumed && hasSession) refresh();
    connectMarket();
  }

  Future<void> loggedIn() async {
    hasSession = true;
    error = '';
    connectMarket();
    timer?.cancel();
    timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (resumed) refresh();
    });
    notifyListeners();
    await refresh();
  }

  Future<void> refresh() async {
    if (loading || !hasSession) return;
    loading = true;
    try {
      final path = selectedSymbol.isEmpty
          ? ''
          : '?symbol=${Uri.encodeQueryComponent(selectedSymbol)}';
      dynamic d;
      try {
        d = await api.get('/api/mobile/snapshot$path');
        patchAvailable = true;
      } on ApiError catch (e) {
        if (e.status == 404) {
          d = await api.get('/api/mt5/details$path');
          patchAvailable = false;
        } else {
          rethrow;
        }
      }
      snapshot = obj(d);
      connection = snapshot['connected'] == true ? 'Connected' : 'MT5 offline';
      updated = DateTime.now();
      error = snapshot['connected'] == true
          ? ''
          : '${snapshot['error'] ?? 'MT5 unavailable'}';
      strategies = arr(obj(await api.get('/api/mt5/strategies'))['strategies']);
      if (symbols.isEmpty) {
        final x = await api.get('/api/symbols?limit=0');
        symbols = x is List ? x : arr(obj(x)['symbols']);
        if (selectedSymbol.isEmpty && symbols.isNotEmpty) {
          selectedSymbol = symbolName(symbols.first);
          connectMarket();
        }
      }
      if (scripts.isEmpty)
        scripts = obj(
          obj(await api.get('/api/shared/scripts'))['monaco_files'],
        );
      protection = obj(obj(snapshot['protection'])['config']);
    } catch (e) {
      connection = 'Offline';
      error = '$e';
      if (e is ApiError && e.status == 401) {
        hasSession = false;
        timer?.cancel();
        connectMarket();
      }
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> reloadScripts() async {
    scripts = obj(obj(await api.get('/api/shared/scripts'))['monaco_files']);
    notifyListeners();
  }

  Future<void> setTheme(TradeStyle s) async {
    style = s;
    await prefs.setString('theme', s.id);
    notifyListeners();
  }

  Future<void> selectMarket(String symbol, String tf) async {
    selectedSymbol = symbol;
    selectedTf = tf;
    connectMarket();
    await prefs.setString('symbol', symbol);
    await prefs.setString('timeframe', tf);
    notifyListeners();
  }

  Future<void> logout() async {
    await api.logout();
    hasSession = false;
    timer?.cancel();
    connectMarket();
    snapshot = {};
    scripts = {};
    strategies = [];
    symbols = [];
    connection = 'Offline';
    notifyListeners();
  }
}

String symbolName(dynamic x) =>
    x is String ? x : '${obj(x)['symbol'] ?? obj(x)['name'] ?? ''}';

class TradeScope extends InheritedNotifier<AppModel> {
  const TradeScope({super.key, required AppModel model, required super.child})
    : super(notifier: model);
  static AppModel of(BuildContext c) =>
      c.dependOnInheritedWidgetOfExactType<TradeScope>()!.notifier!;
}

class TradeApp extends StatelessWidget {
  final AppModel model;
  const TradeApp({super.key, required this.model});
  @override
  Widget build(BuildContext c) => AnimatedBuilder(
    animation: model,
    builder: (_, __) => TradeScope(
      model: model,
      child: MaterialApp(
        title: 'SKX Trade',
        debugShowCheckedModeBanner: false,
        theme: model.style.theme(),
        builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
          value:
              (model.style.dark
                      ? SystemUiOverlayStyle.light
                      : SystemUiOverlayStyle.dark)
                  .copyWith(
                    statusBarColor: Colors.transparent,
                    systemNavigationBarColor: model.style.background,
                  ),
          child: child ?? const SizedBox(),
        ),
        home: model.hasSession ? const TradeShell() : const ConnectScreen(),
      ),
    ),
  );
}

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});
  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final url = TextEditingController(),
      user = TextEditingController(),
      password = TextEditingController(),
      additional = TextEditingController();
  bool busy = false,
      remember = true,
      extraRequired = false,
      restoredUser = false;
  String message = '';
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (url.text.isEmpty)
      url.text = TradeScope.of(context).api.address.isEmpty
          ? 'https://sureshkatz.shop'
          : TradeScope.of(context).api.address;
    if (!restoredUser) {
      restoredUser = true;
      extraRequired = TradeScope.of(context).api.additionalPasswordRequired;
      TradeScope.of(context).api.storage.read(key: 'username').then((v) {
        if (mounted && user.text.isEmpty) user.text = v ?? '';
      });
    }
  }

  @override
  void dispose() {
    for (final c in [url, user, password, additional]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> connect(bool login) async {
    setState(() {
      busy = true;
      message = '';
    });
    final m = TradeScope.of(context);
    try {
      await m.api.setServer(url.text);
      if (login) {
        await m.api.login(
          user.text,
          password.text,
          additional.text,
          remember: remember,
        );
        password.clear();
        additional.clear();
        await m.loggedIn();
      } else {
        final status = obj(await m.api.request('/api/auth/status'));
        extraRequired = status['additionalPasswordRequired'] == true;
        if (mounted)
          setState(
            () => message =
                'Server reached. Sign in with your existing SKXTRADE account.',
          );
      }
    } catch (e) {
      if (mounted)
        setState(() {
          message = '$e';
          if (e is ApiError && e.additionalRequired) extraRequired = true;
        });
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                brand(),
                const SizedBox(height: 28),
                const Text(
                  'Connect your workspace',
                  style: TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -.8,
                  ),
                ),
                const SizedBox(height: 9),
                const Text(
                  'Use the HTTPS address for your Windows trading backend. MT5 stays on your PC.',
                ),
                const SizedBox(height: 22),
                field(
                  url,
                  'HTTPS server URL',
                  hint: 'https://sureshkatz.shop',
                  keyboard: TextInputType.url,
                ),
                const SizedBox(height: 12),
                field(user, 'SKXTRADE username'),
                const SizedBox(height: 12),
                field(password, 'Password', secret: true),
                const SizedBox(height: 12),
                if (extraRequired)
                  field(
                    additional,
                    'Additional password required',
                    secret: true,
                  ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: remember,
                  onChanged: busy
                      ? null
                      : (v) => setState(() => remember = v ?? false),
                  title: const Text('Remember me'),
                  subtitle: const Text(
                    'Save username and encrypted session on this device.',
                  ),
                ),
                const SizedBox(height: 12),
                if (message.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      message,
                      style: TextStyle(color: TradeScope.of(c).style.bad),
                    ),
                  ),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: busy ? null : () => connect(true),
                    icon: busy
                        ? const SizedBox(
                            width: 17,
                            height: 17,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.lock_outline, size: 17),
                    label: const Text('Sign in'),
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: busy ? null : () => connect(false),
                    child: const Text('Test connection'),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Use your normal app login. The Cloudflare tunnel token belongs in the Windows app, not here.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

Widget brand() => Container(
  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
  decoration: BoxDecoration(
    color: const Color(0xfff0f5eb),
    borderRadius: BorderRadius.circular(8),
    border: Border.all(color: const Color(0xffd4dfcc)),
  ),
  child: Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 3,
        height: 16,
        margin: const EdgeInsets.only(right: 8),
        decoration: BoxDecoration(
          color: const Color(0xff356348),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const Text(
        'SKX Trade',
        style: TextStyle(
          color: Color(0xff153f35),
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: -.4,
        ),
      ),
    ],
  ),
);
Widget field(
  TextEditingController c,
  String label, {
  bool secret = false,
  String? hint,
  TextInputType? keyboard,
  ValueChanged<String>? change,
}) => TextField(
  controller: c,
  obscureText: secret,
  keyboardType: keyboard,
  onChanged: change,
  decoration: InputDecoration(labelText: label, hintText: hint),
);
Widget box(Widget child, {EdgeInsets? padding}) => Card(
  child: Padding(padding: padding ?? const EdgeInsets.all(14), child: child),
);
Widget gap([double h = 12]) => SizedBox(height: h);
Widget heading(String text) => Padding(
  padding: const EdgeInsets.only(bottom: 12),
  child: Text(
    text,
    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
  ),
);
Widget keyval(String k, String v, {Color? color}) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 8),
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: Text(k, style: const TextStyle(fontSize: 12))),
      const SizedBox(width: 12),
      Flexible(
        child: Text(
          v,
          textAlign: TextAlign.right,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: color,
          ),
        ),
      ),
    ],
  ),
);
Widget pair(Widget a, Widget b) => Row(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Expanded(child: a),
    const SizedBox(width: 10),
    Expanded(child: b),
  ],
);
void notice(BuildContext c, Object text) {
  ScaffoldMessenger.of(c).showSnackBar(
    SnackBar(content: Text('$text'), behavior: SnackBarBehavior.floating),
  );
}

Future<bool> confirm(
  BuildContext c,
  String title,
  String text, {
  String action = 'Confirm',
}) async =>
    await showDialog<bool>(
      context: c,
      builder: (d) => AlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(d, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;
Future<void> perform(
  BuildContext c,
  Future<dynamic> Function() fn, {
  String? success,
}) async {
  try {
    await fn();
    if (c.mounted) {
      if (success != null) notice(c, success);
      await TradeScope.of(c).refresh();
    }
  } catch (e) {
    if (c.mounted) notice(c, e);
  }
}

Future<void> exportText(BuildContext c, String filename, String content) async {
  try {
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/$filename');
    await f.writeAsString(content);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(f.path)], subject: filename),
    );
  } catch (e) {
    if (c.mounted) notice(c, e);
  }
}

void openPage(BuildContext c, Widget page) {
  HapticFeedback.selectionClick();
  Navigator.of(c).push(MaterialPageRoute(builder: (_) => page));
}

Widget empty(
  String title,
  String detail, {
  IconData icon = Icons.inbox_outlined,
}) => Center(
  child: Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 34),
        gap(),
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 17),
        ),
        gap(7),
        Text(detail, textAlign: TextAlign.center),
      ],
    ),
  ),
);

class TradeShell extends StatefulWidget {
  const TradeShell({super.key});
  @override
  State<TradeShell> createState() => _TradeShellState();
}

class _TradeShellState extends State<TradeShell> {
  int index = 0;
  @override
  Widget build(BuildContext c) => Scaffold(
    body: SafeArea(
      child: IndexedStack(
        index: index,
        children: [
          HomePage(
            onTrade: () {
              HapticFeedback.selectionClick();
              setState(() => index = 1);
            },
          ),
          TradingPage(active: index == 1),
          AiPage(active: index == 2),
          const PositionsPage(),
        ],
      ),
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: index,
      onDestinationSelected: (i) {
        HapticFeedback.selectionClick();
        setState(() => index = i);
      },
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home),
          label: 'Home',
        ),
        NavigationDestination(
          icon: Icon(Icons.candlestick_chart_outlined),
          label: 'Trade',
        ),
        NavigationDestination(
          icon: Icon(Icons.auto_awesome_outlined),
          label: 'AI Trading',
        ),
        NavigationDestination(
          icon: Icon(Icons.list_alt_outlined),
          label: 'Positions',
        ),
      ],
    ),
  );
}

Widget metric(
  BuildContext c,
  String label,
  String value, {
  Color? color,
  bool small = false,
}) {
  final t = TradeScope.of(c).style;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: TextStyle(fontSize: small ? 9 : 10, color: t.muted),
      ),
      gap(4),
      Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: small ? 12 : 15,
          fontWeight: FontWeight.w500,
          color: color ?? t.ink,
        ),
      ),
    ],
  );
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});
  @override
  Widget build(BuildContext c) {
    final m = TradeScope.of(c);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          box(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                heading('Make SKX Trade yours'),
                Text(
                  'Connection and appearance for your mobile workspace.',
                  style: TextStyle(color: m.style.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          gap(20),
          const Text(
            'WORKSPACE CONNECTION',
            style: TextStyle(fontSize: 10, letterSpacing: 1),
          ),
          gap(),
          box(
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.cloud_outlined, color: m.style.primary),
              title: const Text('Connection settings'),
              subtitle: Text(
                m.api.address,
                style: const TextStyle(fontSize: 11),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => openPage(c, const ConnectionSettings()),
            ),
          ),
          gap(20),
          const Text(
            'APP APPEARANCE',
            style: TextStyle(fontSize: 10, letterSpacing: 1),
          ),
          gap(),
          box(
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.palette_outlined, color: m.style.primary),
              title: const Text('Themes'),
              subtitle: Text('${m.style.name} · 10 complete designs'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => openPage(c, const ThemesPage()),
            ),
          ),
          gap(),
          OutlinedButton(
            onPressed: () => showLicensePage(
              context: c,
              applicationName: 'SKX Trade',
              applicationVersion: '1.0.0',
            ),
            child: const Text('Open-source licenses'),
          ),
          TextButton(
            onPressed: () async {
              if (await confirm(
                c,
                'Sign out',
                'Sign out of the mobile app? Windows strategies continue running.',
              )) {
                await m.logout();
                if (c.mounted) Navigator.popUntil(c, (r) => r.isFirst);
              }
            },
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
  }
}

class ConnectionSettings extends StatefulWidget {
  const ConnectionSettings({super.key});
  @override
  State<ConnectionSettings> createState() => _ConnectionSettingsState();
}

class _ConnectionSettingsState extends State<ConnectionSettings> {
  final url = TextEditingController();
  bool initial = false;
  @override
  void dispose() {
    url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    final m = TradeScope.of(c);
    if (!initial) {
      url.text = m.api.address;
      initial = true;
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Connection settings')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            field(url, 'HTTPS server URL'),
            gap(),
            Text('Status: ${m.connection}'),
            gap(),
            const Text(
              'Use the same Windows backend through your Cloudflare HTTPS address. The tunnel token is configured in the Windows app.',
            ),
            gap(20),
            FilledButton(
              onPressed: () async {
                try {
                  final next = validatedServer(url.text);
                  if (next.toString() != m.api.address) {
                    if (!await confirm(
                      c,
                      'Change server',
                      'Changing the server signs you out of the current mobile session.',
                    ))
                      return;
                    await m.logout();
                    await m.api.setServer(url.text);
                    if (c.mounted) Navigator.popUntil(c, (r) => r.isFirst);
                  } else {
                    await m.refresh();
                    if (c.mounted)
                      notice(
                        c,
                        m.error.isEmpty ? 'Connection refreshed' : m.error,
                      );
                  }
                } catch (e) {
                  if (c.mounted) notice(c, e);
                }
              },
              child: const Text('Save & reconnect'),
            ),
          ],
        ),
      ),
    );
  }
}

class ThemesPage extends StatelessWidget {
  const ThemesPage({super.key});
  @override
  Widget build(BuildContext c) {
    final m = TradeScope.of(c);
    return Scaffold(
      appBar: AppBar(title: const Text('Themes')),
      body: GridView.count(
        padding: const EdgeInsets.all(14),
        crossAxisCount: 2,
        childAspectRatio: 1.25,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        children: styles
            .map(
              (s) => InkWell(
                onTap: () => m.setTheme(s),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: s.background,
                    border: Border.all(
                      color: m.style.id == s.id ? s.primary : s.border,
                      width: m.style.id == s.id ? 2 : 1,
                    ),
                    borderRadius: BorderRadius.circular(s.radius),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              s.name,
                              style: TextStyle(
                                fontSize: 11,
                                color: s.ink,
                                fontFamily: s.font,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          if (m.style.id == s.id)
                            Icon(
                              Icons.check_circle,
                              color: s.primary,
                              size: 15,
                            ),
                        ],
                      ),
                      const Spacer(),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: s.paper,
                          border: Border.all(color: s.border),
                          borderRadius: BorderRadius.circular(s.radius),
                        ),
                        child: Text(
                          '10,460.81',
                          style: TextStyle(
                            color: s.ink,
                            fontSize: 17,
                            fontFamily: s.font,
                          ),
                        ),
                      ),
                      gap(8),
                      Row(
                        children: List.generate(
                          4,
                          (i) => Expanded(
                            child: Container(
                              height: 4,
                              margin: const EdgeInsets.only(right: 4),
                              decoration: BoxDecoration(
                                color: i == 0 ? s.primary : s.soft,
                                borderRadius: BorderRadius.circular(s.radius),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

