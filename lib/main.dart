import 'dart:ui' show PlatformDispatcher;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'core/api.dart';
import 'core/nav.dart';
import 'core/session.dart';
import 'core/theme.dart';
import 'screens/login.dart';
import 'screens/shell.dart';

final GlobalKey<ScaffoldMessengerState> messengerKey = GlobalKey<ScaffoldMessengerState>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // أي خطأ غير متوقع يظهر برسالة حمراء بدل ما العنصر «ما يشتغلش» بصمت
  PlatformDispatcher.instance.onError = (error, stack) {
    messengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(error is ApiException ? error.message : 'خطأ غير متوقع: $error'),
        backgroundColor: Colors.red.shade700,
        duration: const Duration(seconds: 8),
      ));
    return true;
  };
  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => Session()..restore()),
      ChangeNotifierProvider(create: (_) => NavState()),
    ],
    child: const ErpApp(),
  ));
}

class ErpApp extends StatelessWidget {
  const ErpApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ERP المصنع',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: messengerKey,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: buildTheme(),
      home: Consumer<Session>(builder: (context, s, _) {
        if (!s.ready) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        return s.loggedIn ? const Shell() : const LoginPage();
      }),
    );
  }
}
