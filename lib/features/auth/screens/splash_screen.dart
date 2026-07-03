import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:auralia_app/core/services/app_ready_notifier.dart';
import 'package:auralia_app/core/services/auralia_scope.dart';
import 'package:auralia_app/core/services/connectivity_watcher.dart';
import 'package:auralia_app/features/auth/widgets/ambient_background.dart';
import 'package:auralia_app/features/home/screens/main_layout.dart';
import 'package:auralia_app/shared/widgets/connection_error_card.dart';
import 'auth_screen.dart';
import 'package:google_fonts/google_fonts.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _entranceController;
  late AnimationController _motionController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _titleSlideAnimation;
  late Animation<double> _logoScaleAnimation;
  bool _isOffline = false;
  bool _isRetryingConnection = false;

  @override
  void initState() {
    super.initState();

    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _motionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: Curves.easeOut,
      ),
    );
    _titleSlideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.18),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.12, 1.0, curve: Curves.easeOutCubic),
      ),
    );
    _logoScaleAnimation = Tween<double>(
      begin: 0.86,
      end: 1.0,
    ).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.0, 0.82, curve: Curves.easeOutBack),
      ),
    );
    _entranceController.forward();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openNextScreen();
    });
  }

  Future<void> _openNextScreen() async {
    if (!await ConnectivityWatcher.hasInternetConnection()) {
      if (mounted) {
        setState(() {
          _isOffline = true;
          _isRetryingConnection = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() => _isOffline = false);
    }

    var isLoggedIn = false;
    try {
      final state = AuraliaScope.of(context);
      final results = await Future.wait([
        Future<void>.delayed(const Duration(seconds: 3)).then((_) => false),
        state.restoreSession().timeout(
          const Duration(seconds: 4),
          onTimeout: () => false,
        ),
      ]);
      isLoggedIn = results[1];
    } catch (_) {
      await Future<void>.delayed(const Duration(seconds: 3));
      isLoggedIn = false;
    }

    if (!mounted) {
      return;
    }

    AppReadyNotifier.instance.value = true;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            isLoggedIn ? const MainLayout() : const AuthScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 800),
      ),
    );
  }

  Future<void> _retryConnection() async {
    if (_isRetryingConnection) {
      return;
    }
    setState(() => _isRetryingConnection = true);
    await _openNextScreen();
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _motionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AmbientBackground(
        child: AnimatedBuilder(
          animation: _motionController,
          builder: (context, child) {
            final t = _motionController.value;
            final floatOffset = math.sin(t * math.pi * 2) * 8;
            return Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _SplashParticlePainter(progress: t),
                  ),
                ),
                Center(
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: SlideTransition(
                      position: _titleSlideAnimation,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Transform.translate(
                              offset: Offset(0, floatOffset),
                              child: Transform.scale(
                                scale:
                                    _logoScaleAnimation.value +
                                    (math.sin(t * math.pi * 2) * 0.025),
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    Container(
                                      width: 132,
                                      height: 132,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.white.withValues(
                                              alpha: 0.16 +
                                                  (math.sin(t * math.pi * 2) *
                                                      0.05),
                                            ),
                                            blurRadius: 44,
                                            spreadRadius: 8,
                                          ),
                                        ],
                                      ),
                                    ),
                                    SizedBox(
                                      width: 116,
                                      height: 116,
                                      child: Image.asset(
                                        'assets/auralia_logo.png',
                                        fit: BoxFit.contain,
                                        errorBuilder:
                                            (context, error, stackTrace) {
                                          return const Icon(
                                            Icons.bubble_chart_rounded,
                                            size: 62,
                                            color: Colors.white,
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 34),
                            Text(
                              'AURALIA',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.poppins(
                                fontSize: 34,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 6.0,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'When Your Mood Finds Its Melody',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                letterSpacing: 1.1,
                                color: Colors.white.withValues(alpha: 0.76),
                              ),
                            ),
                            const SizedBox(height: 30),
                            _SplashEqualizer(progress: t),
                            const SizedBox(height: 14),
                            Text(
                              _isOffline
                                  ? 'waiting for connection'
                                  : 'shaping your sound',
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1.4,
                                color: Colors.white.withValues(alpha: 0.64),
                              ),
                            ),
                            if (_isOffline) ...[
                              const SizedBox(height: 28),
                              ConnectionErrorCard(
                                isRetrying: _isRetryingConnection,
                                onRetry: _retryConnection,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SplashEqualizer extends StatelessWidget {
  const _SplashEqualizer({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 30,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(11, (index) {
          final phase = (progress * math.pi * 2) + (index * 0.58);
          final height = 8 + (math.sin(phase).abs() * 19);
          return AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: 4,
            height: height,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.42 + (height / 80)),
              borderRadius: BorderRadius.circular(4),
            ),
          );
        }),
      ),
    );
  }
}

class _SplashParticlePainter extends CustomPainter {
  const _SplashParticlePainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.white.withValues(alpha: 0.18);
    final accentPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.14);

    final points = [
      const Offset(0.18, 0.22),
      const Offset(0.78, 0.20),
      const Offset(0.12, 0.68),
      const Offset(0.84, 0.72),
      const Offset(0.28, 0.82),
      const Offset(0.68, 0.38),
    ];

    for (var i = 0; i < points.length; i++) {
      final wave = math.sin((progress * math.pi * 2) + i);
      final x = (points[i].dx * size.width) + (wave * 8);
      final y =
          (points[i].dy * size.height) -
          ((progress * 18 + i * 5) % 20) +
          (wave * 5);
      final radius = 2.3 + ((i % 3) * 1.1);
      canvas.drawCircle(Offset(x, y), radius, paint);
    }

    final centerY = size.height * 0.5;
    final path = Path();
    for (var i = 0; i <= 36; i++) {
      final x = size.width * (i / 36);
      final y =
          centerY +
          math.sin((i * 0.55) + (progress * math.pi * 2)) * 14;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, accentPaint);
  }

  @override
  bool shouldRepaint(covariant _SplashParticlePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
