import 'package:auralia_app/features/auth/screens/reset_password_screen.dart';
import 'package:auralia_app/features/auth/screens/splash_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:auralia_app/core/services/auralia_scope.dart';
import 'package:auralia_app/core/services/auralia_state.dart';
import 'package:auralia_app/core/services/post_listening_notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await PostListeningNotificationService.instance.initialize();
  runApp(AuraliaScope(state: AuraliaState(), child: const MyApp()));
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  static const _deepLinkChannel = MethodChannel('auralia/deep_links');
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    _deepLinkChannel.setMethodCallHandler((call) async {
      if (call.method == 'onLink') {
        _handleDeepLink(call.arguments?.toString());
      }
    });
    _readInitialLink();
  }

  Future<void> _readInitialLink() async {
    try {
      final link = await _deepLinkChannel.invokeMethod<String>(
        'getInitialLink',
      );
      _handleDeepLink(link);
    } catch (_) {
      // Deep-link handling is only needed on Android for this build.
    }
  }

  void _handleDeepLink(String? link) {
    final accessToken = _recoveryAccessToken(link);
    if (accessToken == null || accessToken.isEmpty) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final navigator = _navigatorKey.currentState;
      if (navigator == null) {
        return;
      }
      navigator.pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => ResetPasswordScreen(accessToken: accessToken),
        ),
        (_) => false,
      );
    });
  }

  String? _recoveryAccessToken(String? link) {
    if (link == null || link.isEmpty) {
      return null;
    }

    final uri = Uri.tryParse(link);
    if (uri == null) {
      return null;
    }

    final params = <String, String>{...uri.queryParameters};
    if (uri.fragment.isNotEmpty) {
      params.addAll(Uri.splitQueryString(uri.fragment));
    }

    final type = params['type'];
    if (type != null && type != 'recovery') {
      return null;
    }
    return params['access_token'];
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'Auralia App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff4a154b)),
        // Sets Poppins as the global fallback typography for the entire application
        textTheme: GoogleFonts.poppinsTextTheme(Theme.of(context).textTheme),
      ),
      home: const SplashScreen(),
    );
  }
}
