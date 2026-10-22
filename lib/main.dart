import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:go_router/go_router.dart';
import 'data/app_store.dart';
import 'ui/screens.dart';
import 'ui/app_back_scope.dart';
import 'features/security/app_lock.dart';
import 'package:firebase_auth/firebase_auth.dart';

String? firebaseError;
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (const bool.fromEnvironment('LIVE')) {
    try {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: String.fromEnvironment('FIREBASE_API_KEY'),
          appId: String.fromEnvironment('FIREBASE_APP_ID'),
          messagingSenderId: String.fromEnvironment('FIREBASE_SENDER_ID'),
          projectId: String.fromEnvironment('FIREBASE_PROJECT_ID'),
          authDomain: String.fromEnvironment('FIREBASE_AUTH_DOMAIN'),
        ),
      );
      if (const bool.fromEnvironment('APP_CHECK_ENABLED')) {
        await FirebaseAppCheck.instance.activate(
          providerWeb: ReCaptchaV3Provider(
            const String.fromEnvironment('APP_CHECK_SITE_KEY'),
          ),
          providerAndroid: kDebugMode
              ? const AndroidDebugProvider()
              : const AndroidPlayIntegrityProvider(),
        );
      }
    } catch (e) {
      firebaseError = e.toString();
    }
  }
  final app = AppStore();
  await app.init();
  final lock = AppLockController();
  if (Firebase.apps.isNotEmpty && FirebaseAuth.instance.currentUser != null) {
    await lock.bind(FirebaseAuth.instance.currentUser!.uid);
  } else if (Firebase.apps.isEmpty &&
      app.prefs.getBool('demo-lock-enabled') == true) {
    await lock.bind('demo');
  }
  runApp(
    ProviderScope(
      overrides: [
        appProvider.overrideWith((ref) => app),
        appLockProvider.overrideWith((ref) => lock),
      ],
      child: const HisabApp(),
    ),
  );
  // A slow/offline Firestore connection must not block the first frame or PIN.
  if (app.live) unawaited(app.refresh());
}

final router = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (c, s) => const HomeScreen()),
    GoRoute(
      path: '/entry',
      builder: (c, s) => NotebookEntryScreen(
        key: ValueKey(
          'notebook-${s.uri}-${(s.extra as Map<String, dynamic>?)?["id"] ?? ""}',
        ),
        initialType: s.uri.queryParameters['type'],
        initialParty: s.uri.queryParameters['party'],
        initialDraft: s.extra as Map<String, dynamic>?,
      ),
    ),
    GoRoute(path: '/registers', redirect: (c, s) => '/'),
    GoRoute(
      path: '/register/:module',
      builder: (c, s) => s.pathParameters['module'] == 'rent'
          ? const RegisterScreen(module: 'expenses')
          : RegisterScreen(module: s.pathParameters['module']!),
    ),
    GoRoute(
      path: '/entry/:type',
      builder: (c, s) {
        final type = s.pathParameters['type']!;
        final draft = s.extra as Map<String, dynamic>?;
        final entryKey = ValueKey(
          'entry-$type-${draft?['id'] ?? s.uri.queryParameters['party'] ?? ''}',
        );
        if ([
          'salary_accrual',
          'opening_supplier',
          'supplier_apply',
          'opening_loan_asset',
          'opening_loan_debt',
          'transfer',
        ].contains(type)) {
          return RegisterScreen(
            module: type == 'salary_accrual'
                ? 'salary'
                : ['opening_supplier', 'supplier_apply'].contains(type)
                ? 'suppliers'
                : type == 'transfer'
                ? 'cashbook'
                : 'loans',
          );
        }
        if (type == 'daily_sales') {
          return SimpleSaleScreen(key: entryKey, draft: draft);
        }
        if (type == 'rent_payment') {
          return EntryScreen(
            key: entryKey,
            type: 'expense',
            draft: {...?draft, 'category': 'Rent'},
          );
        }
        if (type == 'loan_borrow' || type == 'loan_repay') {
          final mapped = type == 'loan_borrow' ? 'loan_collect' : 'loan_lend';
          return EntryScreen(
            key: entryKey,
            type: mapped,
            draft: draft == null ? null : {...draft, 'type': mapped},
          );
        }
        if ([
          'customer_sale',
          'customer_collection',
          'customer_return',
          'customer_refund',
          'writeoff',
          'opening_customer',
          'rent_accrual',
          'rent_deposit',
          'rent_apply',
        ].contains(type)) {
          return const ProfilesScreen();
        }
        return EntryScreen(
          key: entryKey,
          type: type,
          party: s.uri.queryParameters['party'],
          draft: draft,
        );
      },
    ),
    GoRoute(
      path: '/recycle-bin',
      builder: (c, s) => const ProfilesScreen(recycleBin: true),
    ),
    GoRoute(path: '/profiles', builder: (c, s) => const ProfilesScreen()),
    GoRoute(
      path: '/profiles/:category',
      builder: (c, s) => s.pathParameters['category'] == 'rent'
          ? const RegisterScreen(module: 'expenses')
          : ProfilesScreen(category: s.pathParameters['category']),
    ),
    GoRoute(path: '/owners', builder: (c, s) => const OwnersScreen()),
    GoRoute(
      path: '/security',
      builder: (c, s) => AppBackScope(
        goHome: () => c.canPop() ? c.pop() : c.go('/'),
        child: const SecurityScreen(),
      ),
    ),
    GoRoute(
      path: '/reports',
      builder: (c, s) => ReportsScreen(
        initialModule: s.uri.queryParameters['module'],
        initialParty: s.uri.queryParameters['party'],
      ),
    ),
    GoRoute(path: '/more', builder: (c, s) => const MoreScreen()),
    GoRoute(path: '/login', builder: (c, s) => const LoginScreen()),
    GoRoute(path: '/drafts', builder: (c, s) => const DraftsScreen()),
    GoRoute(path: '/close', builder: (c, s) => const CloseScreen()),
  ],
);

class HisabApp extends ConsumerWidget {
  const HisabApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = ref.watch(appProvider);
    return MaterialApp.router(
      title: 'Pharmacy Hisab',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      builder: (context, child) => AppAccessGate(
        login: () => LoginScreen(onSignedIn: () => router.go('/')),
        child: child!,
      ),
      locale: Locale(a.ur ? 'ur' : 'en'),
      supportedLocales: const [Locale('en'), Locale('ur')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      themeMode: a.dark ? ThemeMode.dark : ThemeMode.light,
      theme: theme(false, a.ur),
      darkTheme: theme(true, a.ur),
    );
  }
}

ThemeData theme(bool dark, bool ur) {
  final scheme = ColorScheme.fromSeed(
    seedColor: blue,
    brightness: dark ? Brightness.dark : Brightness.light,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme.copyWith(
      primary: blue,
      secondary: green,
      surface: dark ? const Color(0xff19243b) : Colors.white,
    ),
    fontFamily: ur ? 'NotoArabic' : 'Inter',
    fontFamilyFallback: const ['NotoArabic', 'Inter'],
    scaffoldBackgroundColor: dark ? const Color(0xff111a2e) : Colors.white,
    textTheme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light)
        .textTheme
        .apply(
          fontFamily: ur ? 'NotoArabic' : 'Inter',
          bodyColor: dark ? Colors.white : navy,
          displayColor: dark ? Colors.white : navy,
        ),
    appBarTheme: AppBarTheme(
      backgroundColor: dark ? const Color(0xff111a2e) : Colors.white,
      foregroundColor: dark ? Colors.white : navy,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: ur ? 'NotoArabic' : 'Inter',
        fontSize: 27,
        fontWeight: FontWeight.w800,
        color: dark ? Colors.white : navy,
      ),
      surfaceTintColor: Colors.transparent,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xff19243b) : Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(9),
        borderSide: const BorderSide(color: Color(0xffced6e1)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(9),
        borderSide: const BorderSide(color: Color(0xffced6e1)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: blue,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(58),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
        textStyle: TextStyle(
          fontFamily: ur ? 'NotoArabic' : 'Inter',
          fontFamilyFallback: const ['NotoArabic', 'Inter'],
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    dividerTheme: const DividerThemeData(color: Color(0xffe1e6ef), space: 22),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
