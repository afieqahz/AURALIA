import 'package:flutter/material.dart';

class AmbientBackground extends StatefulWidget {
  final Widget child;
  const AmbientBackground({super.key, required this.child});

  @override
  State<AmbientBackground> createState() => _AmbientBackgroundState();
}

class _AmbientBackgroundState extends State<AmbientBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat(reverse: true);
    _animation = Tween<double>(
      begin: -1.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(
                _animation.value * 0.3,
                -1.0 + (_animation.value * 0.2),
              ),
              end: Alignment(
                -_animation.value * 0.3,
                1.0 - (_animation.value * 0.2),
              ),
              colors: [
                Color.lerp(
                  const Color(0xFFAC7099),
                  const Color(0xFF5A2C62),
                  (_animation.value + 1) / 2,
                )!,
                Color.lerp(
                  const Color(0xFFE599C5),
                  const Color(0xFFAC7099),
                  (_animation.value + 1) / 2,
                )!,
              ],
            ),
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
