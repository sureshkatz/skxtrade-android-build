import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:skxtrade_mobile/api.dart';
import 'package:skxtrade_mobile/main.dart';
import 'package:skxtrade_mobile/pine_inputs.dart';
import 'package:skxtrade_mobile/themes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final side in ['BUY', 'SELL']) {
    testWidgets('Chart order sheet shows only the $side submit button', (tester) async {
      final model = AppModel();
      await tester.pumpWidget(
        TradeScope(
          model: model,
          child: MaterialApp(
            home: Scaffold(
              body: TestEntryForm(initialSymbol: 'XAUUSDm', initialSide: side),
            ),
          ),
        ),
      );
      final chosen = side == 'BUY' ? 'Buy' : 'Sell';
      final opposite = side == 'BUY' ? 'Sell' : 'Buy';
      expect(find.widgetWithText(FilledButton, chosen), findsOneWidget);
      expect(find.widgetWithText(FilledButton, opposite), findsNothing);
      await tester.tap(find.text('Market Order'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Limit Order').last);
      await tester.pumpAndSettle();
      expect(find.text('Limit price'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '$chosen Limit'), findsOneWidget);
    });
  }
  test('Closed fill prices use broker precision and hide floating-point noise', () {
    expect(brokerPrice(3957.2159999999994, 3), '3957.216');
    expect(brokerPrice(3960.3109999999997, null), '3960.311');
    expect(brokerPrice(73560.36, 2), '73560.36');
    expect(brokerPrice(null, 3), '—');
  });
  test('Trade quotes preserve decimals when the symbol snapshot is missing', () {
    final model = AppModel();
    model.snapshot = {
      'symbol': 'OTHER',
      'symbol_info': {'name': 'OTHER', 'digits': 0},
    };
    model.marketQuote.value = {'symbol': 'XAUUSDm', 'bid': 3944.15, 'ask': 3944.16};
    expect(liveQuote(model, 'XAUUSDM', 'bid'), '3944.15');
    model.marketQuote.value = {...model.marketQuote.value, 'digits': 3};
    expect(liveQuote(model, 'XAUUSDM', 'ask'), '3944.160');
    expect(liveQuote(model, 'BTCUSDm', 'ask'), '—');
  });
  for (final optimize in [false, true]) {
    testWidgets('Research broker symbol search applies selection (optimize: $optimize)', (
      tester,
    ) async {
      final model = AppModel()
        ..prefs = await SharedPreferences.getInstance()
        ..selectedSymbol = 'EURUSDm'
        ..symbols = ['EURUSDm', {'symbol': 'XAUUSDm'}, 'BTCUSDm'];
      await tester.pumpWidget(
        TradeScope(
          model: model,
          child: MaterialApp(home: ResearchPage(optimize: optimize)),
        ),
      );
      await tester.tap(find.byTooltip('Search broker symbols'));
      await tester.pumpAndSettle();
      final search = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == 'Search broker symbols',
      );
      await tester.enterText(search, 'xau');
      await tester.pumpAndSettle();
      expect(find.text('BTCUSDm'), findsNothing);
      await tester.tap(find.text('XAUUSDm'));
      await tester.pumpAndSettle();
      expect(find.text('XAUUSDm'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  }
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });
  testWidgets('Deploy strategy shows lot size only in Fixed Lot mode', (
    tester,
  ) async {
    final model = AppModel();
    model.scripts = {
      'EMA': {'source': 'strategy("EMA")'},
    };
    model.selectedSymbol = 'XAUUSDm';
    model.snapshot = {
      'account': {'login': 1234, 'trade_mode': 0},
    };
    await tester.pumpWidget(
      TradeScope(
        model: model,
        child: const MaterialApp(home: DeployStrategyPage()),
      ),
    );
    expect(find.text('Lot size'), findsNothing);
    await tester.tap(find.text('Pine / Auto Lot'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fixed Lot').last);
    await tester.pumpAndSettle();
    expect(find.text('Lot size'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Lot size'), '0.02');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.ensureVisible(find.text('Create & Deploy'));
    await tester.tap(find.text('Create & Deploy'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Demo MT5 account 1234'), findsOneWidget);
    expect(find.textContaining('0.02 lots'), findsOneWidget);
  });
  testWidgets('Equity trend badge opens its explanation', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (c) => equityTrendInfo(c, {
              'status': 'steady_up',
              'label': 'Steady uptrend',
              'reason': 'Distributed growth',
              'overall': 'up',
              'recent': 'up',
              'returnPercent': 14.0,
              'recentReturnPercent': 3.0,
              'maxDrawdownPercent': 2.0,
              'positiveSegmentsPercent': 80.0,
            }),
          ),
        ),
      ),
    );
    expect(find.text('Steady uptrend'), findsOneWidget);
    await tester.tap(find.text('Steady uptrend'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Distributed growth'), findsOneWidget);
    expect(
      find.textContaining('Separate-period validation is not included.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
  });
  testWidgets('Saved tab ignores old status response and slow account lookup', (
    tester,
  ) async {
    final firstStatus = Completer<http.Response>(),
        slowAccount = Completer<http.Response>();
    var statusCalls = 0;
    final api = TradeApi(
      client: MockClient((r) async {
        if (r.url.path.endsWith('/setup'))
          return http.Response(
            File('test/fixtures/ai_setup.json').readAsStringSync(),
            200,
          );
        if (r.url.path.endsWith('/status')) {
          statusCalls++;
          if (statusCalls == 1) return firstStatus.future;
          return http.Response(
            '{"status":"idle","completed":0,"results":[],"logs":[]}',
            200,
          );
        }
        if (r.url.path.endsWith('/account')) return slowAccount.future;
        if (r.url.path.endsWith('/saved'))
          return http.Response(
            '[{"id":"one","name":"Saved strategy one","config":{"symbol":"XAUUSDm","timeframe":"M5"},"metrics":{"net":120,"pf":1.5},"equityTrend":{"status":"steady_up","label":"Steady uptrend"}}]',
            200,
          );
        return http.Response('[]', 200);
      }),
    );
    await api.setServer('https://sureshkatz.shop');
    final m = AppModel(api: api);
    m.prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      TradeScope(
        model: m,
        child: MaterialApp(home: Scaffold(body: AiPage(active: true))),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Saved'));
    await tester.pump();
    firstStatus.complete(
      http.Response(
        '{"status":"idle","completed":0,"results":[],"logs":[]}',
        200,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Saved strategy one'), findsOneWidget);
    expect(tester.takeException(), isNull);
    final before = statusCalls;
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(statusCalls, greaterThan(before));
    await tester.pumpWidget(const SizedBox());
    slowAccount.complete(http.Response('{"connected":true}', 200));
    await tester.pump();
  });
  test('HTTPS origins exclude credentials and paths', () {
    expect(
      validatedServer('https://trade.example.com/').toString(),
      'https://trade.example.com',
    );
    for (final url in [
      'http://example.com',
      'https://user:secret@example.com',
      'https://example.com/api',
      'https://example.com?token=secret',
      'javascript:alert(1)',
    ]) {
      expect(() => validatedServer(url), throwsA(isA<ApiError>()));
    }
  });
  test('Login cookie is used on authenticated requests', () async {
    bool hadCookie = false;
    final api = TradeApi(
      client: MockClient((r) async {
        if (r.url.path == '/api/auth/login') {
          expect(jsonDecode(r.body)['password'], 'not-logged');
          return http.Response(
            '{"ok":true}',
            200,
            headers: {
              'set-cookie':
                  'skxtrade_session=session-value; HttpOnly; Secure; Path=/',
            },
          );
        }
        hadCookie = r.headers['Cookie'] == 'skxtrade_session=session-value';
        return http.Response('{"authenticated":true}', 200);
      }),
    );
    await api.setServer('https://trade.example.com');
    await api.login('test', 'not-logged', '');
    expect(hadCookie, true);
    expect(api.authenticated, true);
  });
  test(
    'Cross-origin API calls and authentication redirects are blocked',
    () async {
      final api = TradeApi(
        client: MockClient(
          (r) async => http.Response(
            '',
            302,
            headers: {'location': 'https://another.example.com'},
          ),
        ),
      );
      await api.setServer('https://trade.example.com');
      expect(
        () => api.uri('https://another.example.com/api'),
        throwsA(isA<ApiError>()),
      );
      await expectLater(api.get('/api/auth/status'), throwsA(isA<ApiError>()));
    },
  );
  test(
    'Pine inputs support named defaults, multiline strings and option lists',
    () {
      final p = parsePineInputs('''//@version=6
fast = input.int(defval=14, title="Fast EMA, period", minval=1, step=2)
slow = input.float(78.5, title="Slow", maxval=100)
buy = input.bool(true, title="Buy")
direction = input.string("One Side", options=["One Side", "Both"])
htf = input.timeframe("H1")
computed = input.int(someVariable)
''');
      expect(p.length, 5);
      expect(p.first.title, 'Fast EMA, period');
      expect(p.first.step, 2);
      expect(p[2].value, true);
      expect(p[3].options, ['One Side', 'Both']);
      expect(p.last.type, 'timeframe');
    },
  );
  test('Parameter combinations are exact and capped', () {
    final range = {
      'fast': {'use': true, 'min': 10, 'max': 14, 'step': 2, 'integer': true},
      'slow': {'use': true, 'min': 40, 'max': 50, 'step': 10},
    };
    final combos = buildCombinations(range, 10);
    expect(combos.length, 6);
    expect(combos.first, {'fast': 10, 'slow': 40.0});
    expect(combos.last, {'fast': 14, 'slow': 50.0});
    expect(() => buildCombinations(range, 5), throwsFormatException);
    expect(
      () => buildCombinations({
        'x': {'use': true, 'min': 2, 'max': 1, 'step': 0},
      }, 10),
      throwsFormatException,
    );
  });
  for (final size in [
    const Size(390, 844),
    const Size(360, 740),
    const Size(320, 640),
    const Size(393, 873),
    const Size(430, 932),
  ]) {
    testWidgets('Home fits ${size.width.toInt()}x${size.height.toInt()}', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final m = AppModel();
      m.prefs = await SharedPreferences.getInstance();
      m.hasSession = true;
      m.snapshot = {
        'connected': true,
        'todayRealized': 124.30,
        'account': {
          'login': 4821,
          'company': 'Demo Broker',
          'server': 'Demo Server',
          'currency': 'USD',
          'balance': 10460.81,
          'equity': 10491.71,
          'margin': 524.0,
          'free_margin': 9967.71,
          'leverage': 100,
          'trade_mode': 0,
        },
      };
      await tester.pumpWidget(
        TradeScope(
          model: m,
          child: MaterialApp(
            theme: styles.first.theme(),
            home: Scaffold(
              body: SafeArea(child: HomePage(onTrade: () {})),
              bottomNavigationBar: const SizedBox(height: 66),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('SKX Trade'), findsOneWidget);
      expect(find.text('MT5'), findsOneWidget);
      expect(find.text('0 Open positions'), findsOneWidget);
      expect(find.text('0 Pending orders'), findsOneWidget);
      expect(find.text('10,460.81'), findsOneWidget);
      expect(find.byType(FittedBox), findsNothing);
      expect(find.byType(Scrollable), findsNothing);
      expect(
        (tester.getCenter(find.text('SKX Trade')).dy -
                tester.getCenter(find.byTooltip('Settings')).dy)
            .abs(),
        lessThan(8),
      );
      expect(
        tester.getTopLeft(find.text('Strategy connections')).dy -
            tester.getBottomLeft(find.text('MT5')).dy,
        lessThan(80),
      );
    });
  }
  testWidgets('Settings previews ten themes without overflow', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final m = AppModel();
    m.prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      TradeScope(
        model: m,
        child: MaterialApp(
          theme: styles.first.theme(),
          home: const ThemesPage(),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Market Blue'), findsOneWidget);
    expect(styles.length, 10);
  });
  for (final entry in <String, Widget>{
    'Backtest': const ResearchPage(optimize: false),
    'Optimization': const ResearchPage(optimize: true),
    'MT5': const Mt5Page(),
    'Positions': const Scaffold(body: PositionsPage()),
    'AI Trading': const AiFullPage(),
  }.entries) {
    testWidgets('${entry.key} opens without layout overflow', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 740);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final m = AppModel();
      m.prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        TradeScope(
          model: m,
          child: MaterialApp(theme: styles.first.theme(), home: entry.value),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  test('Equity uses full period and distinct realized and floating P&L', () {
    final x = equityConfig(
      {
        'initialCapital': 10000,
        'net': 40,
        'equityCurve': [
          {'time': 100, 'equity': 10010},
          {'time': 200, 'equity': 10040},
        ],
        'trades': [
          {'exit_time': 150, 'profit': 35},
        ],
      },
      50,
      250,
    );
    expect(x['from'], 50);
    expect(x['to'], 250);
    expect((x['data'] as List).first['value'], 10);
    expect((x['cumulative'] as List)[1]['value'], 35);
    expect((x['cumulative'] as List).last['value'], 40);
    expect(chartTime(1700000000000), 1700000000);
  });
  testWidgets(
    'Mobile selector searches a long list and returns the chosen value',
    (tester) async {
      final m = AppModel();
      m.prefs = await SharedPreferences.getInstance();
      String selected = 'XAUUSD0';
      await tester.pumpWidget(
        TradeScope(
          model: m,
          child: MaterialApp(
            theme: styles.first.theme(),
            home: Scaffold(
              body: MobileSelect(
                label: 'Symbol',
                value: selected,
                options: {
                  for (var i = 0; i < 5000; i++) 'XAUUSD$i': 'XAUUSD$i',
                },
                onChanged: (v) => selected = v,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(MobileSelect));
      await tester.pumpAndSettle();
      expect(find.byType(ListTile).evaluate().length, lessThan(30));
      await tester.enterText(find.byType(TextField), 'XAUUSD4999');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'XAUUSD4999'));
      await tester.pumpAndSettle();
      expect(selected, 'XAUUSD4999');
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [const Size(320, 640), const Size(390, 844)]) {
    testWidgets('Five equal chart controls and dropdown at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final m = AppModel();
      m.prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        TradeScope(
          model: m,
          child: MaterialApp(
            theme: styles.first.theme(),
            home: const Scaffold(body: TradingPage(active: false)),
          ),
        ),
      );
      final bounds = ['Symbol', 'Type', 'Indicators', 'Timeframe', 'Strategies']
          .map(
            (l) => tester.getRect(
              find
                  .ancestor(
                    of: find.text(l),
                    matching: find.byType(OutlinedButton),
                  )
                  .first,
            ),
          )
          .toList();
      for (final r in bounds) {
        expect(r.width, closeTo(bounds.first.width, .1));
        expect(r.height, 65);
        expect(r.top, bounds.first.top);
      }
      expect(find.text('SELL'), findsOneWidget);
      expect(find.text('BUY'), findsOneWidget);
      await tester.tap(find.text('Timeframe'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text('M15'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  test('Server challenge propagated to login', () async {
    final api = TradeApi(
      client: MockClient(
        (r) async => http.Response(
          '{"detail":"Additional password required"}',
          401,
          headers: {'x-additional-password-required': '1'},
        ),
      ),
    );
    await api.setServer('https://sureshkatz.shop');
    await expectLater(
      api.login('test', 'wrong', ''),
      throwsA(
        isA<ApiError>().having((e) => e.additionalRequired, 'challenge', true),
      ),
    );
  });
  test('Default origin and optional session persistence', () async {
    final api = TradeApi(
      client: MockClient(
        (r) async => r.url.path.endsWith('login')
            ? http.Response(
                '{"ok":true}',
                200,
                headers: {
                  'set-cookie': 'skxtrade_session=test; HttpOnly; Secure',
                },
              )
            : http.Response('{"authenticated":true}', 200),
      ),
    );
    await api.restore();
    expect(api.address, 'https://sureshkatz.shop');
    await api.login('test', 'private', '', remember: false);
    expect(api.authenticated, true);
    expect(await api.storage.read(key: 'session'), isNull);
    expect(await api.storage.read(key: 'username'), isNull);
  });
  test('Broker result states are truthful', () {
    expect(brokerOutcome({'ok': true, 'retcode': 10009}), 'Order executed');
    expect(
      brokerOutcome({'ok': true, 'retcode': 10009}, closing: true),
      'Position closed',
    );
    expect(brokerOutcome({'ok': true, 'retcode': 10010}), 'Partially filled');
    expect(
      brokerOutcome({'ok': true, 'retcode': 10010}, closing: true),
      'Partially closed',
    );
    expect(
      brokerOutcome({'ok': true, 'retcode': 10008}),
      'Pending broker execution',
    );
    expect(brokerOutcome({'ok': true}), 'Execution not confirmed');
    expect(brokerOutcome({'ok': false, 'retcode': 10009}), 'Failed');
  });
  testWidgets('Trade cards show times quantity and details', (tester) async {
    final m = AppModel();
    m.prefs = await SharedPreferences.getInstance();
    final rows = [
      {
        'side': 'short',
        'symbol': 'XAUUSDm',
        'pnl': -6.27,
        'qty': 2,
        'entry_price': 3900,
        'exit_price': 3903,
        'entry_time': 1762041600,
        'exit_time': 1762041900,
      },
    ];
    await tester.pumpWidget(
      TradeScope(
        model: m,
        child: MaterialApp(
          theme: styles.first.theme(),
          home: Scaffold(body: TradeHistoryList(rows: rows)),
        ),
      ),
    );
    expect(find.text('SELL'), findsOneWidget);
    expect(find.text('-6.27'), findsOneWidget);
    expect(find.text('Qty 2'), findsOneWidget);
    await tester.tap(find.text('SELL'));
    await tester.pumpAndSettle();
    expect(find.text('Trade details'), findsOneWidget);
    expect(find.text('Entry time'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  test('AI activity formats times and hides raw execution IDs', () {
    final s = humanActivity(
      '59112 candles · 1767308700 to 1793393700 · execution 8d926deb9119',
    );
    expect(s, contains('59,112 candles'));
    expect(s, contains('2026'));
    expect(s, isNot(contains('execution')));
    expect(s, isNot(contains('1767308700')));
  });
  testWidgets('Broker dialog shows fill and blocks duplicate sends', (
    tester,
  ) async {
    var sends = 0;
    final api = TradeApi(
      client: MockClient((r) async {
        sends++;
        return http.Response(
          '{"ok":true,"retcode":10010,"ticket":71,"price":3900.2,"volume":0.4}',
          200,
        );
      }),
    );
    await api.setServer('https://sureshkatz.shop');
    final m = AppModel(api: api);
    m.prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      TradeScope(
        model: m,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (c) => TextButton(
                onPressed: () {
                  brokerAction(
                    c,
                    'test-order',
                    () => api.post('/api/mt5/live/order'),
                  );
                  brokerAction(
                    c,
                    'test-order',
                    () => api.post('/api/mt5/live/order'),
                  );
                },
                child: const Text('Place'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Place'));
    await tester.pumpAndSettle();
    expect(sends, 1);
    expect(find.text('Partially filled'), findsOneWidget);
    expect(find.text('Ticket: 71'), findsOneWidget);
    expect(find.text('Fill price: 3900.2'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets('Delete confirms only the selected MT5 connection', (
    tester,
  ) async {
    String? deleted;
    final api = TradeApi(
      client: MockClient((r) async {
        if (r.method == 'DELETE') deleted = r.url.path;
        return http.Response('{"ok":true}', 200);
      }),
    );
    await api.setServer('https://sureshkatz.shop');
    final m = AppModel(api: api);
    m.prefs = await SharedPreferences.getInstance();
    m.strategies = [
      {
        'id': 'one',
        'name': 'First',
        'symbol': 'XAUUSDm',
        'timeframe': 'M5',
        'status': 'Stopped',
      },
      {
        'id': 'two',
        'name': 'Second',
        'symbol': 'EURUSD',
        'timeframe': 'M15',
        'status': 'Stopped',
      },
    ];
    await tester.pumpWidget(
      TradeScope(
        model: m,
        child: MaterialApp(
          theme: styles.first.theme(),
          home: const Mt5Page(initialTab: 1),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Delete connection').last);
    await tester.pumpAndSettle();
    expect(find.text('Delete Second?'), findsOneWidget);
    expect(deleted, isNull);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(deleted, '/api/mt5/strategies/two');
    expect(tester.takeException(), isNull);
  });
  testWidgets('Leaving Trade restores portrait after chart rotation', (
    tester,
  ) async {
    final orientations = <List<dynamic>>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemChrome.setPreferredOrientations')
          orientations.add(List<dynamic>.from(call.arguments as List));
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final m = AppModel();
    m.prefs = await SharedPreferences.getInstance();
    Widget scene(bool active) => TradeScope(
      model: m,
      child: MaterialApp(
        theme: styles.first.theme(),
        home: Scaffold(
          body: TradingPage(key: const ValueKey('rotation'), active: active),
        ),
      ),
    );
    await tester.pumpWidget(scene(true));
    await tester.tap(find.byTooltip('Rotate chart'));
    await tester.pumpAndSettle();
    expect(orientations.last, contains('DeviceOrientation.landscapeLeft'));
    await tester.pumpWidget(scene(false));
    await tester.pumpAndSettle();
    expect(orientations.last, ['DeviceOrientation.portraitUp']);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
