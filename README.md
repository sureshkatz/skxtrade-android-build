# SKX Trade Android 1.2.0

Native Flutter/Dart screens with an embedded, locally bundled TradingView Lightweight Charts view. Android 8.0 or newer; the supplied release APK is ARM64. This is a mobile companion to your Windows SKXTRADE backend. It does not run MT5, PineForge, Cloudflare Tunnel or AI execution on the phone.

## Combined update 1.2.0

Trade embeds the actual OpenAlgo Charts 2.6.0 vendor module from the original desktop source. It exposes 112 indicators and 87 drawing tools, with the original mobile drawing palette, object/property editors and server-backed instrument drawings. Only the chart renderer uses WebView; the surrounding app, login, toolbar, account screens and order dialogs remain native Flutter. Session credentials stay in Dart, outside chart JavaScript.

Five equal controls: Symbol, Type, Indicators, Timeframe dropdown, Strategies. Saved Pine source and supported literal inputs run through the actual Windows `/api/pine/chart` engine. Plots and supplied/trade-derived entry/exit markers appear on the chart. Selected Pine overlays refresh at most every 15 seconds while Trade is active. The live strategy calculation uses the latest 1,500 bars; chart history can page independently. Changing markets clears the chart strategy. Chart selection does not deploy a live strategy.

Red Sell and green Buy show white labels/prices, open lot/SL/TP forms and require confirmation. Result dialogs distinguish executed/closed, partial, pending, failed and unknown states using actual MT5 return codes. Duplicate in-flight sends are blocked. Check Positions/history before retrying unknown or pending executions.

AI Saved, Backtest and Optimization share compact trade cards and readable details with entry/exit times, quantity and P&L. AI Activity groups candidate steps with outcomes and readable dates; raw logs are expandable. Each MT5 strategy connection has a confirmed individual delete action, preserving saved Pine source and broker positions.

Home, native navigation and ten themes are retained. Apply the supplied Windows 1.2 backend patch for the exact fifth-failure challenge and richer close feedback. Default HTTPS origin: `https://sureshkatz.shop`. Main login is required; Remember me keeps only the username/encrypted session. Configure the additional password locally on Windows if not already configured.

## Install and connect

1. Close Windows SKXTRADE, apply the supplied Windows mobile backend update, then start SKXTRADE again. Keep Windows, MT5 and the tunnel running.
2. Install the supplied signed APK on your phone. Allow installation from the application opening the APK when Android requests it.
3. Use the default `https://sureshkatz.shop` origin and your existing SKXTRADE user login. After five failed main logins, enter the additional password configured on Windows. Do not put the Cloudflare tunnel token in the Android app.
4. Home displays the actual connected account. Save a Pine strategy on the Windows app or in the Android Pine editor before selecting it in Backtest, Optimization or MT5 strategy deployment.

An independently configured Cloudflare Access browser login is not integrated with this native API client. Its browser cookies do not transfer to the app. Use your existing authenticated SKXTRADE API route and an appropriate Access configuration; do not disable the SKXTRADE API authentication. TLS certificates must be valid; HTTP and invalid certificates are rejected.

## Screens

- Home: compact SKX Trade title and Settings on one row; broker/account, balance, equity, unrealized P&L, today's realized P&L (UTC), margin, position/order counts and navigation to every workspace.
- Trade: original OpenAlgo chart, five equal controls, timeframe dropdown, saved Pine inputs, full indicator/drawing catalog, history ranges, landscape and confirmed Sell/Buy. No Home chart.
- AI Trading: setup, progress, saved strategies, code editor, versions, comparison, backup/restore and run history using the existing backend.
- Backtest/Optimization: Pine inputs, dates, execution model, persistent background jobs, per-job controls, results, full-period equity/realized P&L, buy and hold, trade excursions and exports.
- MT5: account, independent controls for each strategy connection, protection and confirmed test orders. Positions has individual close and SL/TP modification.
- Settings: HTTPS connection, sign out and ten themes, with colors, corners and typography variants.

Home fits the tested 320x640, 360x740, 390x844, 393x873 and 430x932 layouts with responsive spacing and typography. It does not scale a fixed page or use a vertical spacer to push strategy status down. Dense forms, editors and record lists use internal scrolling/pagination to keep fields and records accessible, including with the keyboard or larger system fonts.

## Execution behavior and limits

Windows is the execution host. Closing the mobile app does not stop an active server job or a running strategy. Shutting down Windows/backend stops execution. Research jobs persist results, but running jobs are marked interrupted after a backend restart, not silently resumed. One mobile backtest/optimization job runs at a time; optimization is capped at 500 combinations. Pause is cooperative and may wait for history preparation or the next engine update.

Pause/stop of a strategy does not imply closing broker positions. Use individual position controls when needed. Strategy sizing uses Pine quantity, matching the supplied server's implementation. Configure fixed quantity in the Pine script. Test orders and position changes require explicit confirmation.

The supplied desktop backend accepts six optimization method labels, but evaluates the supplied parameter grid for all of them. Android preserves that behavior; distinct genetic, Bayesian, walk-forward and Monte Carlo engines are not added by this release. Results depend on available broker history and the existing execution engine. Unsupported computed Pine input defaults must be edited in source.

## Build on Windows

Install Flutter stable with Dart >=3.10, Android SDK platforms 35 and 36, build tools 36.0.0, Android NDK 28.2.13676358, CMake 3.22.1, and JDK 17. Configure Android Studio/SDK and run `flutter doctor` and `flutter doctor --android-licenses`. The release was built with Flutter 3.47.9 / Dart 3.13.7, Gradle 9.3.1 and AGP 9.1.0. The checked-in lockfile pins resolved Dart dependencies. Increase the version and build number in pubspec.yaml for each future release, while retaining the same signing key.

Extract `SKXTRADE_Private_Signing.zip` beside this project:

```
SKXTRADE_Android\BUILD_ANDROID.cmd
SKXTRADE_Private_Signing\skxtrade-release.jks
SKXTRADE_Private_Signing\signing-password.txt
```

Open PowerShell in this project and run:

```powershell
.\BUILD_ANDROID.cmd
```

Or specify another key location:

```powershell
.\BUILD_ANDROID.cmd -SigningDirectory "E:\Private\SKXTRADE_Private_Signing"
```

The script resolves packages, runs analysis/tests, creates a signed release and prints the exact APK path. Android Studio and the Flutter SDK are external prerequisites; they are not included in the source ZIP. Keep the private signing archive: future app updates need the same key. Never publish the private archive. The project source contains no signing passwords, server credentials or tunnel tokens.

## Verification

See the included release validation report for the actual build and test results. No physical Android phone, Windows MT5 terminal or user Cloudflare endpoint was available for end-to-end trading validation. Test with your demo account before using live controls.

TradingView Lightweight Charts 5.0.9 is bundled under Apache-2.0. Its license/notice and visible chart attribution are retained in `assets/CHART_LICENSE.txt`. Other Flutter dependencies remain under their respective licenses; see Settings > Open-source licenses.

OpenAlgo Charts 2.6.0 retains its Apache-2.0 license in `assets/openalgo/LICENSE.txt`. Equity charts continue using Lightweight Charts with its existing license/attribution.
