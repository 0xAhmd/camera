import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'services/streaming_service.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => StreamingService(),
        ),
      ],
      child: const PhoneCamApp(),
    ),
  );
}

class PhoneCamApp extends StatelessWidget {
  const PhoneCamApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PhoneCam',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const HomeScreen(),
    );
  }
}

class AppTheme {
  static const _bg = Color(0xFF0D0D0F);
  static const _surface = Color(0xFF1A1A1F);
  static const _card = Color(0xFF232328);
  static const _accent = Color(0xFF00E5A0);
  static const _text = Color(0xFFEEEEF0);
  static const _muted = Color(0xFF888890);

  static final dark = ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: _bg,
    colorScheme: const ColorScheme.dark(
      surface: _surface,
      primary: _accent,
      onPrimary: Colors.black,
      onSurface: _text,
    ),
    cardColor: _card,
    fontFamily: 'Inter',
    appBarTheme: const AppBarTheme(
      backgroundColor: _bg,
      elevation: 0,
      titleTextStyle: TextStyle(
        color: _text,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
      iconTheme: IconThemeData(
        color: _text,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: _accent,
        foregroundColor: Colors.black,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: _card,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(
          color: _accent,
          width: 1.5,
        ),
      ),
    ),
    extensions: const [
      AppColors(
        bg: _bg,
        surface: _surface,
        card: _card,
        accent: _accent,
        text: _text,
        muted: _muted,
      ),
    ],
  );
}

@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.bg,
    required this.surface,
    required this.card,
    required this.accent,
    required this.text,
    required this.muted,
  });

  final Color bg;
  final Color surface;
  final Color card;
  final Color accent;
  final Color text;
  final Color muted;

  @override
  AppColors copyWith({
    Color? bg,
    Color? surface,
    Color? card,
    Color? accent,
    Color? text,
    Color? muted,
  }) {
    return AppColors(
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      card: card ?? this.card,
      accent: accent ?? this.accent,
      text: text ?? this.text,
      muted: muted ?? this.muted,
    );
  }

  @override
  AppColors lerp(
    ThemeExtension<AppColors>? other,
    double t,
  ) {
    if (other is! AppColors) {
      return this;
    }

    return AppColors(
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      card: Color.lerp(card, other.card, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      text: Color.lerp(text, other.text, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
    );
  }
}