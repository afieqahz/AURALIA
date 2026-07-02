import 'dart:math' as math;

import 'package:flutter/material.dart';

class FloatingBubbles extends StatefulWidget {
  const FloatingBubbles({
    super.key,
    this.color = Colors.white,
    this.opacity = 0.14,
    this.count = 14,
  });

  final Color color;
  final double opacity;
  final int count;

  @override
  State<FloatingBubbles> createState() => _FloatingBubblesState();
}

class _FloatingBubblesState extends State<FloatingBubbles>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  static const _seeds = <_BubbleSeed>[
    _BubbleSeed(0.10, 0.18, 9, 8, -5),
    _BubbleSeed(0.20, 0.72, 5, -7, 6),
    _BubbleSeed(0.34, 0.30, 4, 6, 7),
    _BubbleSeed(0.48, 0.82, 8, -6, -5),
    _BubbleSeed(0.60, 0.24, 6, 8, 5),
    _BubbleSeed(0.76, 0.68, 4, -8, 7),
    _BubbleSeed(0.88, 0.36, 10, 7, -6),
    _BubbleSeed(0.14, 0.48, 4, -4, 8),
    _BubbleSeed(0.42, 0.56, 6, 5, -8),
    _BubbleSeed(0.70, 0.12, 5, -6, 4),
    _BubbleSeed(0.90, 0.84, 5, 7, 6),
    _BubbleSeed(0.30, 0.10, 4, -5, -4),
    _BubbleSeed(0.56, 0.44, 3, 4, 5),
    _BubbleSeed(0.82, 0.18, 4, -4, -7),
    _BubbleSeed(0.08, 0.86, 6, 5, 4),
    _BubbleSeed(0.66, 0.92, 4, -6, -3),
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bubbleCount = widget.count.clamp(0, _seeds.length).toInt();
    final seeds = _seeds.take(bubbleCount).toList();

    return Positioned.fill(
      child: IgnorePointer(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return LayoutBuilder(
                builder: (context, constraints) {
                  return Stack(
                    children: seeds.asMap().entries.map((entry) {
                      final index = entry.key;
                      final seed = entry.value;
                      final phase =
                          (_controller.value + index * 0.09) * 2 * math.pi;
                      final left =
                          constraints.maxWidth * seed.x +
                          math.sin(phase) * seed.dx;
                      final top =
                          constraints.maxHeight * seed.y +
                          math.cos(phase) * seed.dy;
                      final alpha = widget.opacity *
                          (0.72 + 0.28 * math.sin(phase).abs());

                      return Positioned(
                        left: left,
                        top: top,
                        child: Container(
                          width: seed.size,
                          height: seed.size,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: widget.color.withValues(alpha: alpha),
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

class _BubbleSeed {
  const _BubbleSeed(this.x, this.y, this.size, this.dx, this.dy);

  final double x;
  final double y;
  final double size;
  final double dx;
  final double dy;
}
