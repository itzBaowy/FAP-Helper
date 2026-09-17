import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'data/markbook_store.dart';
import 'ui/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MainApp(store: MarkbookStore.forWindows()));
}

class MainApp extends StatelessWidget {
  const MainApp({super.key, required this.store, this.pickFile, this.now});
  final MarkbookStore store;
  final Future<String?> Function()? pickFile;
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xff163c3a);
    return MaterialApp(
      title: 'FAP Helper • FA26',
      debugShowCheckedModeBanner: false,
      locale: const Locale('vi'),
      supportedLocales: const [Locale('vi'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Segoe UI',
        scaffoldBackgroundColor: const Color(0xfff5f7f8),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff16786b),
          primary: const Color(0xff16786b),
          surface: Colors.white,
          onSurface: ink,
        ),
        textTheme: const TextTheme(
          headlineLarge: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.7,
            color: ink,
          ),
          headlineSmall: TextStyle(
            fontSize: 23,
            fontWeight: FontWeight.w700,
            color: ink,
          ),
          titleLarge: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w700,
            color: ink,
          ),
          bodyMedium: TextStyle(fontSize: 14, height: 1.5, color: ink),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xfff5f7f8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
        dividerTheme: const DividerThemeData(
          color: Color(0xffe6eceb),
          thickness: 1,
        ),
      ),
      home: HomeScreen(store: store, pickFile: pickFile, now: now),
    );
  }
}
