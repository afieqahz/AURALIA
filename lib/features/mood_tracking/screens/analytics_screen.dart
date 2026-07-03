import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:auralia_app/core/models/mood.dart';
import 'package:auralia_app/core/services/auralia_scope.dart';
import 'package:auralia_app/core/widgets/floating_bubbles.dart';

enum _AnalyticsRange { weekly, monthly }

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  _AnalyticsRange _range = _AnalyticsRange.weekly;
  int _periodOffset = 0;
  bool _didRequestRefresh = false;

  @override
  Widget build(BuildContext context) {
    final state = AuraliaScope.of(context);
    if (!_didRequestRefresh) {
      _didRequestRefresh = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          state.refreshMoodHistory().catchError((_) {});
        }
      });
    }

    return AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        final analytics = _MoodAnalytics.fromEntries(
          state.moodHistory,
          range: _range,
          periodOffset: _periodOffset,
        );

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _AnalyticsHeader(
                analytics: analytics,
                range: _range,
                onRangeChanged: (range) => setState(() {
                  _range = range;
                  _periodOffset = 0;
                }),
              ),
              const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _MetricCard(
                  color: const Color(0xFFEADFFF),
                  icon: Icons.fact_check_outlined,
                  iconColor: const Color(0xFF5A2C62),
                  label: 'Mood Entries',
                  value: '${analytics.totalMoodEntries}',
                  infoTitle: 'Mood Entries',
                  infoText:
                      'This is how many moods you recorded in the selected period. In Week view, it counts moods from the selected Sunday to Saturday. In Month view, it counts moods from the selected month. Each time you choose a mood, AURALIA adds one mood entry.',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MetricCard(
                  color: const Color(0xFFE2F7ED),
                  icon: _moodIcon(analytics.dominantMood),
                  iconColor: const Color(0xFF348557),
                  label: 'Mood Baseline',
                  value: analytics.baselineLabel,
                  infoTitle: 'Mood Baseline',
                  infoText:
                      'This shows your average mood level for the selected period. AURALIA gives each mood a score: Sad 22%, Stressed 32%, Neutral 50%, Happy 76%, and Motivated 88%. The scores are averaged to show whether your overall mood was low, mixed, or positive. This is different from your most frequent mood.',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _MetricCard(
                  color: const Color(0xFFFFE8EC),
                  icon: Icons.compare_arrows_rounded,
                  iconColor: const Color(0xFFB64C63),
                  label: 'Mood Change',
                  value: analytics.moodChangeLabel,
                  infoTitle: 'Mood Change',
                  infoText:
                      'This compares your mood before listening with your mood after finishing a playlist. A positive value means your self-reported mood moved upward after listening. A negative value means it moved lower. This only updates after you complete the post-listening check-in.',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MetricCard(
                  color: const Color(0xFFFFF0D9),
                  icon: Icons.favorite_outline_rounded,
                  iconColor: const Color(0xFFB26B00),
                  label: 'Helpful Sessions',
                  value: analytics.helpfulSessionsLabel,
                  infoTitle: 'Helpful Sessions',
                  infoText:
                      'This shows how often you said the playlist helped after listening. A session is counted as helpful when you answer Yes or A little in the post-listening feedback. It helps AURALIA understand whether the generated playlists are supporting your mood.',
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          _TrendCard(
            analytics: analytics,
            onPrevious: () => setState(() => _periodOffset--),
            onNext: () => setState(() => _periodOffset++),
            canGoNext: _periodOffset < 0,
          ),
          const SizedBox(height: 22),
          const _SectionTitle(
            title: 'Insights',
            infoText:
                'Insights turn your mood records into short explanations. AURALIA may show your most frequent mood, whether your average mood improved or decreased compared with the previous period, whether playlists were helpful, and whether repeated low moods were detected.',
          ),
          const SizedBox(height: 12),
          if (analytics.entries.isEmpty)
            const _EmptyAnalyticsCard()
          else
            ...analytics.insights.map(
              (insight) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _InsightTile(
                  insight: insight,
                  onAction: insight.actionLabel == null
                      ? null
                      : _showWellnessSuggestions,
                ),
              ),
            ),
          const SizedBox(height: 12),
          const _SectionTitle(
            title: 'Mood Distribution',
            infoText:
                'This shows how your recorded moods are divided in the selected period. For example, if 4 out of 10 mood entries are Sad, Sad will show 40%. This helps you see which moods appeared most often.',
          ),
          const SizedBox(height: 12),
          _MoodDistributionCard(analytics: analytics),
            ],
          ),
        );
      },
    );
  }

  void _showWellnessSuggestions() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _WellnessSuggestionSheet(),
    );
  }
}

class _AnalyticsHeader extends StatelessWidget {
  const _AnalyticsHeader({
    required this.analytics,
    required this.range,
    required this.onRangeChanged,
  });

  final _MoodAnalytics analytics;
  final _AnalyticsRange range;
  final ValueChanged<_AnalyticsRange> onRangeChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2A0736), Color(0xFF64226D), Color(0xFF9B5A91)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4A154B).withValues(alpha: 0.24),
            blurRadius: 28,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          const FloatingBubbles(count: 14, opacity: 0.16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Mood Analytics',
                maxLines: 1,
                overflow: TextOverflow.visible,
                style: GoogleFonts.poppins(
                  fontSize: 23,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      range == _AnalyticsRange.weekly
                          ? 'Your emotional pattern this week'
                          : 'Your emotional pattern this month',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        height: 1.25,
                        color: Colors.white.withValues(alpha: 0.78),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  _RangeSelector(value: range, onChanged: onRangeChanged),
                ],
              ),
              if (range == _AnalyticsRange.weekly) ...[
                const SizedBox(height: 6),
                Text(
                  'Week runs Sunday to Saturday, so totals may include a few days from the previous month.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 10,
                    height: 1.2,
                    fontStyle: FontStyle.italic,
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.infoText});

  final String title;
  final String infoText;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF38143E),
            ),
          ),
        ),
        _InfoButton(title: title, text: infoText),
      ],
    );
  }
}

class _InfoButton extends StatelessWidget {
  const _InfoButton({
    required this.title,
    required this.text,
    this.size = 20,
  });

  final String title;
  final String text;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'About $title',
      child: InkWell(
        onTap: () => _showInfoDialog(context),
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            Icons.info_outline_rounded,
            size: size,
            color: const Color(0xFF7C5B80),
          ),
        ),
      ),
    );
  }

  Future<void> _showInfoDialog(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
        contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        title: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: const Color(0xFFEADFFF),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(
                Icons.info_outline_rounded,
                size: 20,
                color: Color(0xFF5A2C62),
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                title,
                style: GoogleFonts.poppins(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF38143E),
                ),
              ),
            ),
          ],
        ),
        content: Text(
          text,
          style: GoogleFonts.poppins(
            fontSize: 13,
            height: 1.45,
            color: Colors.black54,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(
              'Got it',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700,
                color: const Color(0xFF5A2C62),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RangeSelector extends StatelessWidget {
  const _RangeSelector({required this.value, required this.onChanged});

  final _AnalyticsRange value;
  final ValueChanged<_AnalyticsRange> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFEDE4EE),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _RangeButton(
            label: 'Week',
            selected: value == _AnalyticsRange.weekly,
            onTap: () => onChanged(_AnalyticsRange.weekly),
          ),
          _RangeButton(
            label: 'Month',
            selected: value == _AnalyticsRange.monthly,
            onTap: () => onChanged(_AnalyticsRange.monthly),
          ),
        ],
      ),
    );
  }
}

class _RangeButton extends StatelessWidget {
  const _RangeButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF5A2C62) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : const Color(0xFF5A2C62),
          ),
        ),
      ),
    );
  }
}

class _TrendCard extends StatefulWidget {
  const _TrendCard({
    required this.analytics,
    required this.onPrevious,
    required this.onNext,
    required this.canGoNext,
  });

  final _MoodAnalytics analytics;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final bool canGoNext;

  @override
  State<_TrendCard> createState() => _TrendCardState();
}

class _TrendCardState extends State<_TrendCard> {
  int? _selectedBucketIndex;

  @override
  void didUpdateWidget(covariant _TrendCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.analytics.periodLabel != widget.analytics.periodLabel ||
        oldWidget.analytics.range != widget.analytics.range) {
      _selectedBucketIndex = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final analytics = widget.analytics;
    final selectedIndex =
        (_selectedBucketIndex != null &&
            _selectedBucketIndex! < analytics.buckets.length)
        ? _selectedBucketIndex
        : null;
    final selectedBucket = selectedIndex == null
        ? null
        : analytics.buckets[selectedIndex];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Colors.white, Color(0xFFFFFBFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4A154B).withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
        border: Border.all(color: const Color(0xFFF4EAF5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFEADFFF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.stacked_bar_chart_rounded,
                  color: Color(0xFF5A2C62),
                  size: 20,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  'Mood Trends',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF38143E),
                  ),
                ),
              ),
              const _InfoButton(
                title: 'Mood Trends',
                text:
                    'This chart shows when your moods were recorded. In Week view, each bar is one day from Sunday to Saturday. In Month view, each bar is one week inside the selected month. Taller bars mean more mood entries were recorded. The colours show which moods were selected.',
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            analytics.trendSubtitle,
            style: GoogleFonts.poppins(fontSize: 11, color: Colors.black45),
          ),
          const SizedBox(height: 10),
          _TrendPeriodControl(
            label: analytics.periodLabel,
            onPrevious: widget.onPrevious,
            onNext: widget.onNext,
            canGoNext: widget.canGoNext,
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 5,
            children: AuraliaMood.values
                .map(
                  (mood) => _LegendItem(
                    label: mood.label,
                    color: _moodColor(mood),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 220,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final bucketCount = analytics.buckets.length;
                final slotWidth = bucketCount == 0
                    ? constraints.maxWidth
                    : constraints.maxWidth / bucketCount;
                final tooltipWidth = constraints.maxWidth < 240 ? 112.0 : 136.0;
                final double tooltipLeft = selectedIndex == null
                    ? 0.0
                    : (slotWidth * selectedIndex.toDouble() + slotWidth * 0.58)
                        .clamp(
                        0.0,
                        (constraints.maxWidth - tooltipWidth)
                            .clamp(
                          0.0,
                          constraints.maxWidth,
                        )
                            .toDouble(),
                      )
                        .toDouble();
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      top: 26,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: List.generate(analytics.buckets.length, (index) {
                          final bucket = analytics.buckets[index];
                          return Expanded(
                            child: _MoodBar(
                              bucket: bucket,
                              maxCount: analytics.maxBucketCount,
                              selected: index == selectedIndex,
                              onTap: () {
                                setState(() {
                                  _selectedBucketIndex =
                                      selectedIndex == index ? null : index;
                                });
                              },
                            ),
                          );
                        }),
                      ),
                    ),
                    if (selectedBucket != null)
                      Positioned(
                        top: 0,
                        left: tooltipLeft,
                        width: tooltipWidth,
                        child: _MoodBucketPopup(
                          bucket: selectedBucket,
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MoodBar extends StatelessWidget {
  const _MoodBar({
    required this.bucket,
    required this.maxCount,
    required this.selected,
    required this.onTap,
  });

  final _MoodBucket bucket;
  final int maxCount;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final total = bucket.total;
    final height = total == 0
        ? 8.0
        : 140.0 * (total / maxCount.clamp(1, 999));

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            '$total',
            style: GoogleFonts.poppins(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: total == 0 ? Colors.black26 : const Color(0xFF5A2C62),
            ),
          ),
          const SizedBox(height: 5),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 8, end: height.clamp(8.0, 140.0).toDouble()),
            duration: const Duration(milliseconds: 520),
            curve: Curves.easeOutCubic,
            builder: (context, animatedHeight, child) {
              return AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: selected ? 28 : 24,
                height: animatedHeight,
                padding: selected ? const EdgeInsets.all(2) : EdgeInsets.zero,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: const Color(0xFFEDE4EE),
                  borderRadius: BorderRadius.circular(99),
                  border: selected
                      ? Border.all(color: const Color(0xFF5A2C62), width: 1.2)
                      : null,
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: const Color(0xFF5A2C62).withValues(alpha: 0.22),
                            blurRadius: 14,
                            offset: const Offset(0, 7),
                          ),
                        ]
                      : null,
                ),
                child: child,
              );
            },
            child: total == 0
                ? null
                : ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: AuraliaMood.values
                          .where((mood) => bucket.counts[mood]! > 0)
                          .map(
                            (mood) => Expanded(
                              flex: bucket.counts[mood]!,
                              child: Container(color: _moodColor(mood)),
                            ),
                          )
                          .toList(),
                    ),
                  ),
          ),
          const SizedBox(height: 8),
          Text(
            bucket.label,
            style: GoogleFonts.poppins(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: selected ? const Color(0xFF5A2C62) : Colors.black45,
            ),
          ),
        ],
      ),
    );
  }
}

class _TrendPeriodControl extends StatelessWidget {
  const _TrendPeriodControl({
    required this.label,
    required this.onPrevious,
    required this.onNext,
    required this.canGoNext,
  });

  final String label;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final bool canGoNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _PeriodArrowButton(
          icon: Icons.chevron_left_rounded,
          onTap: onPrevious,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF5A2C62),
            ),
          ),
        ),
        _PeriodArrowButton(
          icon: Icons.chevron_right_rounded,
          onTap: canGoNext ? onNext : null,
        ),
      ],
    );
  }
}

class _PeriodArrowButton extends StatelessWidget {
  const _PeriodArrowButton({
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: onTap == null
              ? const Color(0xFFF3ECF4)
              : const Color(0xFFF6EEF7),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: 20,
          color: onTap == null
              ? Colors.black26
              : const Color(0xFF5A2C62),
        ),
      ),
    );
  }
}

class _MoodBucketPopup extends StatelessWidget {
  const _MoodBucketPopup({required this.bucket});

  final _MoodBucket bucket;

  @override
  Widget build(BuildContext context) {
    final activeMoods = AuraliaMood.values
        .where((mood) => bucket.counts[mood]! > 0)
        .toList();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5D9E7)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4A154B).withValues(alpha: 0.12),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            bucket.label,
            style: GoogleFonts.poppins(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF38143E),
            ),
          ),
          Text(
            'Entries:',
            style: GoogleFonts.poppins(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: Colors.black54,
            ),
          ),
          const SizedBox(height: 5),
          if (bucket.total == 0)
            Text(
              'No mood entries',
              style: GoogleFonts.poppins(fontSize: 9, color: Colors.black45),
            )
          else
            ...activeMoods.map(
              (mood) => Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: _moodColor(mood),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        mood.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          fontSize: 9,
                          color: Colors.black54,
                        ),
                      ),
                    ),
                    Text(
                      '${bucket.counts[mood]}',
                      style: GoogleFonts.poppins(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF38143E),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: GoogleFonts.poppins(fontSize: 9, color: Colors.black54),
        ),
      ],
    );
  }
}

class _InsightTile extends StatelessWidget {
  const _InsightTile({required this.insight, this.onAction});

  final _MoodInsight insight;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            insight.color.withValues(alpha: 0.16),
            Colors.white,
          ],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: insight.color.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: insight.color.withValues(alpha: 0.08),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.74),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(insight.icon, size: 20, color: insight.color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  insight.text,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: const Color(0xFF4E3A50),
                    height: 1.35,
                  ),
                ),
                if (insight.actionLabel != null && onAction != null) ...[
                  const SizedBox(height: 10),
                  InkWell(
                    onTap: onAction,
                    borderRadius: BorderRadius.circular(999),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: insight.color.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: insight.color.withValues(alpha: 0.24),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            insight.actionLabel!,
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: insight.color,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Icon(
                            Icons.arrow_forward_rounded,
                            size: 15,
                            color: insight.color,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _WellnessIdea { breathe, ground, move, connect, journal, tinyStep }

class _WellnessSuggestionSheet extends StatefulWidget {
  const _WellnessSuggestionSheet();

  @override
  State<_WellnessSuggestionSheet> createState() =>
      _WellnessSuggestionSheetState();
}

class _WellnessSuggestionSheetState extends State<_WellnessSuggestionSheet> {
  _WellnessIdea _selected = _WellnessIdea.breathe;
  Timer? _timer;
  int _breatheSeconds = 24;
  int _moveSeconds = 30;

  bool get _isTimerRunning => _timer != null;

  String get _breatheLabel {
    if (_breatheSeconds == 0) {
      return 'Nice work. Let that calm stay with you.';
    }
    final elapsed = 24 - _breatheSeconds;
    return elapsed % 8 < 4 ? 'Breathe in slowly' : 'Breathe out gently';
  }

  String get _moveLabel {
    if (_moveSeconds == 0) {
      return 'Good. Notice if your body feels a little lighter.';
    }
    return 'Move gently for $_moveSeconds seconds';
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _selectIdea(_WellnessIdea idea) {
    _timer?.cancel();
    setState(() {
      _selected = idea;
      _timer = null;
      _breatheSeconds = 24;
      _moveSeconds = 30;
    });
  }

  void _startTimedReset() {
    _timer?.cancel();
    setState(() {
      if (_selected == _WellnessIdea.breathe) {
        _breatheSeconds = 24;
      } else if (_selected == _WellnessIdea.move) {
        _moveSeconds = 30;
      }
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() {
        if (_selected == _WellnessIdea.breathe) {
          _breatheSeconds = (_breatheSeconds - 1).clamp(0, 24).toInt();
          if (_breatheSeconds == 0) {
            timer.cancel();
            _timer = null;
          }
        } else if (_selected == _WellnessIdea.move) {
          _moveSeconds = (_moveSeconds - 1).clamp(0, 30).toInt();
          if (_moveSeconds == 0) {
            timer.cancel();
            _timer = null;
          }
        } else {
          timer.cancel();
          _timer = null;
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.only(top: 80),
        padding: const EdgeInsets.fromLTRB(22, 12, 22, 22),
        decoration: const BoxDecoration(
          color: Color(0xFFFFF8FF),
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFF2A0736),
                      Color(0xFF64226D),
                      Color(0xFF9B5A91),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF4A154B).withValues(alpha: 0.18),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    const FloatingBubbles(count: 12, opacity: 0.14),
                    Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(
                            Icons.favorite_rounded,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'A gentle check-in',
                                style: GoogleFonts.poppins(
                                  fontSize: 21,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Three low moods in a row can feel heavy. Pick one small reset for right now.',
                                style: GoogleFonts.poppins(
                                  fontSize: 11.5,
                                  height: 1.35,
                                  color: Colors.white.withValues(alpha: 0.78),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Choose a tiny reset',
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF38143E),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 96,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _WellnessOptionCard(
                      icon: Icons.air_rounded,
                      title: 'Breathe',
                      subtitle: '24 sec',
                      selected: _selected == _WellnessIdea.breathe,
                      onTap: () => _selectIdea(_WellnessIdea.breathe),
                    ),
                    _WellnessOptionCard(
                      icon: Icons.spa_rounded,
                      title: 'Ground',
                      subtitle: '5 things',
                      selected: _selected == _WellnessIdea.ground,
                      onTap: () => _selectIdea(_WellnessIdea.ground),
                    ),
                    _WellnessOptionCard(
                      icon: Icons.accessibility_new_rounded,
                      title: 'Move',
                      subtitle: '30 sec',
                      selected: _selected == _WellnessIdea.move,
                      onTap: () => _selectIdea(_WellnessIdea.move),
                    ),
                    _WellnessOptionCard(
                      icon: Icons.people_outline_rounded,
                      title: 'Connect',
                      subtitle: 'Text one',
                      selected: _selected == _WellnessIdea.connect,
                      onTap: () => _selectIdea(_WellnessIdea.connect),
                    ),
                    _WellnessOptionCard(
                      icon: Icons.edit_note_rounded,
                      title: 'Journal',
                      subtitle: '1 line',
                      selected: _selected == _WellnessIdea.journal,
                      onTap: () => _selectIdea(_WellnessIdea.journal),
                    ),
                    _WellnessOptionCard(
                      icon: Icons.check_circle_outline_rounded,
                      title: 'Tiny step',
                      subtitle: 'One task',
                      selected: _selected == _WellnessIdea.tinyStep,
                      onTap: () => _selectIdea(_WellnessIdea.tinyStep),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 240),
                child: _WellnessIdeaPanel(
                  key: ValueKey(_selected),
                  idea: _selected,
                  breatheSeconds: _breatheSeconds,
                  breatheLabel: _breatheLabel,
                  moveSeconds: _moveSeconds,
                  moveLabel: _moveLabel,
                  isTimerRunning: _isTimerRunning,
                  onStartTimer: _startTimedReset,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5EDF8),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFE8D8EA)),
                ),
                child: Text(
                  'AURALIA supports wellbeing, but it cannot diagnose or replace professional care. If you feel unsafe or overwhelmed, contact someone you trust or local emergency support.',
                  style: GoogleFonts.poppins(
                    fontSize: 10.5,
                    height: 1.4,
                    color: Colors.black54,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    elevation: 0,
                    backgroundColor: const Color(0xFF6E2D72),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: Text(
                    'Back to analytics',
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WellnessOptionCard extends StatelessWidget {
  const _WellnessOptionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 92,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF6E2D72) : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? const Color(0xFF6E2D72) : const Color(0xFFE8D8EA),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF4A154B).withValues(
                  alpha: selected ? 0.18 : 0.06,
                ),
                blurRadius: selected ? 18 : 12,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon,
                size: 22,
                color: selected ? Colors.white : const Color(0xFF6E2D72),
              ),
              const Spacer(),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: selected ? Colors.white : const Color(0xFF38143E),
                ),
              ),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontSize: 9.5,
                  color: selected
                      ? Colors.white.withValues(alpha: 0.76)
                      : Colors.black45,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WellnessIdeaPanel extends StatelessWidget {
  const _WellnessIdeaPanel({
    super.key,
    required this.idea,
    required this.breatheSeconds,
    required this.breatheLabel,
    required this.moveSeconds,
    required this.moveLabel,
    required this.isTimerRunning,
    required this.onStartTimer,
  });

  final _WellnessIdea idea;
  final int breatheSeconds;
  final String breatheLabel;
  final int moveSeconds;
  final String moveLabel;
  final bool isTimerRunning;
  final VoidCallback onStartTimer;

  @override
  Widget build(BuildContext context) {
    final content = switch (idea) {
      _WellnessIdea.breathe => (
        Icons.air_rounded,
        'Try a soft breathing loop',
        'Inhale for 4 counts, hold for 2, then exhale for 6. Repeat this three times and let your shoulders drop.',
      ),
      _WellnessIdea.ground => (
          Icons.spa_rounded,
          'Name what is around you',
          'Find 5 things you can see, 4 you can feel, 3 you can hear, 2 you can smell, and 1 thing you can taste.',
        ),
      _WellnessIdea.move => (
        Icons.accessibility_new_rounded,
        'Loosen the body first',
        'Roll your shoulders, stretch your neck gently, and walk slowly for 30 seconds before choosing the next song.',
      ),
      _WellnessIdea.connect => (
          Icons.people_outline_rounded,
          'Reach one safe person',
          'Send a simple message such as: I am having a low moment. Can you stay with me for a little while?',
        ),
      _WellnessIdea.journal => (
          Icons.edit_note_rounded,
          'Write one honest line',
          'Try: Right now I feel..., and one thing I need is... Keep it short. It does not need to be perfect.',
        ),
      _WellnessIdea.tinyStep => (
          Icons.check_circle_outline_rounded,
          'Pick one doable step',
          'Choose one tiny action under two minutes: drink water, sit near light, tidy one item, or open a comforting playlist.',
        ),
    };

    return Container(
      key: key,
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Colors.white, Color(0xFFF8EFF8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE8D8EA)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4A154B).withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFE8D8EA),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(content.$1, color: const Color(0xFF6E2D72)),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  content.$2,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF38143E),
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  content.$3,
                  style: GoogleFonts.poppins(
                    fontSize: 11.5,
                    height: 1.45,
                    color: Colors.black54,
                  ),
                ),
                if (idea == _WellnessIdea.breathe ||
                    idea == _WellnessIdea.move) ...[
                  const SizedBox(height: 14),
                  _ResetTimerControl(
                    secondsRemaining: idea == _WellnessIdea.breathe
                        ? breatheSeconds
                        : moveSeconds,
                    totalSeconds: idea == _WellnessIdea.breathe ? 24 : 30,
                    label: idea == _WellnessIdea.breathe
                        ? breatheLabel
                        : moveLabel,
                    buttonLabel: _timerButtonLabel,
                    isRunning: isTimerRunning,
                    onStart: onStartTimer,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String get _timerButtonLabel {
    if (idea == _WellnessIdea.breathe) {
      return breatheSeconds == 0 ? 'Do it again' : 'Start 24 seconds';
    }
    return moveSeconds == 0 ? 'Move again' : 'Start 30 seconds';
  }
}

class _ResetTimerControl extends StatelessWidget {
  const _ResetTimerControl({
    required this.secondsRemaining,
    required this.totalSeconds,
    required this.label,
    required this.buttonLabel,
    required this.isRunning,
    required this.onStart,
  });

  final int secondsRemaining;
  final int totalSeconds;
  final String label;
  final String buttonLabel;
  final bool isRunning;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final progress = (totalSeconds - secondsRemaining) / totalSeconds;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF5EDF8),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 58,
            height: 58,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: isRunning || secondsRemaining == 0 ? progress : 0,
                  strokeWidth: 5,
                  backgroundColor: const Color(0xFFE2D1DF),
                  valueColor: const AlwaysStoppedAnimation(Color(0xFF6E2D72)),
                ),
                Text(
                  '${secondsRemaining}s',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF38143E),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF38143E),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 34,
                  child: ElevatedButton(
                    onPressed: isRunning ? null : onStart,
                    style: ElevatedButton.styleFrom(
                      elevation: 0,
                      backgroundColor: const Color(0xFF6E2D72),
                      disabledBackgroundColor: const Color(0xFFE2D1DF),
                      foregroundColor: Colors.white,
                      disabledForegroundColor: const Color(0xFF6E2D72),
                      padding: const EdgeInsets.symmetric(horizontal: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    child: Text(
                      isRunning ? 'In progress...' : buttonLabel,
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyAnalyticsCard extends StatelessWidget {
  const _EmptyAnalyticsCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.insights_rounded, color: Color(0xFF5A2C62)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Choose and record a mood to begin seeing your trends.',
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: Colors.black54,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MoodDistributionCard extends StatelessWidget {
  const _MoodDistributionCard({required this.analytics});

  final _MoodAnalytics analytics;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[
      Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Text(
          analytics.distributionSubtitle,
          style: GoogleFonts.poppins(
            fontSize: 11,
            color: Colors.black45,
          ),
        ),
      ),
      ...AuraliaMood.values.map((mood) {
        final count = analytics.moodCounts[mood] ?? 0;
        final percentage = analytics.entries.isEmpty
            ? 0.0
            : count / analytics.entries.length;
        return Padding(
          padding: EdgeInsets.only(
            bottom: mood == AuraliaMood.values.last ? 0 : 15,
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: _moodColor(mood).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _moodIcon(mood),
                  size: 20,
                  color: _moodColor(mood),
                ),
              ),
              const SizedBox(width: 11),
              SizedBox(
                width: 72,
                child: Text(
                  mood.label,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Expanded(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: percentage),
                  duration: const Duration(milliseconds: 620),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, _) => ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: value,
                      minHeight: 10,
                      backgroundColor: const Color(0xFFF0E8F1),
                      valueColor: AlwaysStoppedAnimation(_moodColor(mood)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 38,
                child: Text(
                  '${(percentage * 100).round()}%',
                  textAlign: TextAlign.right,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF38143E),
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Colors.white, Color(0xFFFFFBFF)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFF4EAF5)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4A154B).withValues(alpha: 0.07),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: rows,
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.color,
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    this.infoTitle,
    this.infoText,
  });

  final Color color;
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final String? infoTitle;
  final String? infoText;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) {
        return Transform.translate(
          offset: Offset(0, 12 * (1 - t)),
          child: Opacity(opacity: t, child: child),
        );
      },
      child: Container(
        constraints: const BoxConstraints(minHeight: 126),
        clipBehavior: Clip.antiAlias,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: iconColor.withValues(alpha: 0.12),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
          border: Border.all(color: Colors.white.withValues(alpha: 0.7)),
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.62),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, color: iconColor, size: 21),
                    ),
                    const Spacer(),
                    if (infoTitle != null && infoText != null)
                      _InfoButton(
                        title: infoTitle!,
                        text: infoText!,
                        size: 18,
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  label,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: const Color(0xFF4E3A50).withValues(alpha: 0.68),
                  ),
                ),
                const SizedBox(height: 3),
                SizedBox(
                  width: double.infinity,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      value,
                      maxLines: 1,
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF38143E),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MoodAnalytics {
  const _MoodAnalytics({
    required this.entries,
    required this.buckets,
    required this.moodCounts,
    required this.range,
    required this.totalMoodEntries,
    required this.dominantMood,
    required this.baselineLabel,
    required this.moodChangeLabel,
    required this.helpfulSessionsLabel,
    required this.insights,
    required this.periodLabel,
  });

  final List<MoodEntry> entries;
  final List<_MoodBucket> buckets;
  final Map<AuraliaMood, int> moodCounts;
  final _AnalyticsRange range;
  final int totalMoodEntries;
  final AuraliaMood dominantMood;
  final String baselineLabel;
  final String moodChangeLabel;
  final String helpfulSessionsLabel;
  final List<_MoodInsight> insights;
  final String periodLabel;

  int get maxBucketCount {
    var maximum = 1;
    for (final bucket in buckets) {
      if (bucket.total > maximum) {
        maximum = bucket.total;
      }
    }
    return maximum;
  }

  String get trendSubtitle => range == _AnalyticsRange.weekly
      ? 'Each colour shows the moods recorded in this week.'
      : 'Each colour shows the moods recorded by week in this month.';

  String get distributionSubtitle => range == _AnalyticsRange.weekly
      ? 'Based on ${entries.length} mood entries from this week.'
      : 'Based on ${entries.length} mood entries from this month.';

  factory _MoodAnalytics.fromEntries(
    List<MoodEntry> allEntries, {
    required _AnalyticsRange range,
    int periodOffset = 0,
  }) {
    final allBeforeEntries = allEntries
        .where((entry) => entry.checkInType == MoodCheckInType.beforeListening)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final allAfterEntries = allEntries
        .where((entry) => entry.checkInType == MoodCheckInType.afterListening)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final currentDay = today;
    final anchorDay = range == _AnalyticsRange.weekly
        ? today.add(Duration(days: periodOffset * 7))
        : DateTime(today.year, today.month + periodOffset, today.day);
    final start = range == _AnalyticsRange.weekly
        ? _weekStartSunday(anchorDay)
        : DateTime(anchorDay.year, anchorDay.month);
    final exclusiveEnd = range == _AnalyticsRange.weekly
        ? start.add(const Duration(days: 7))
        : DateTime(anchorDay.year, anchorDay.month + 1);
    final previousStart = range == _AnalyticsRange.weekly
        ? start.subtract(const Duration(days: 7))
        : DateTime(anchorDay.year, anchorDay.month - 1);
    final previousEnd = start;
    final periodLabel = range == _AnalyticsRange.weekly
        ? _weekPeriodLabel(start, exclusiveEnd.subtract(const Duration(days: 1)))
        : _monthPeriodLabel(anchorDay);

    final entries = allEntries
        .where(
          (entry) =>
              entry.checkInType == MoodCheckInType.beforeListening &&
              !_analyticsDay(entry.createdAt, currentDay).isBefore(start) &&
              _analyticsDay(entry.createdAt, currentDay).isBefore(exclusiveEnd),
        )
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final previousEntries = allEntries
        .where(
          (entry) =>
              entry.checkInType == MoodCheckInType.beforeListening &&
              !_analyticsDay(entry.createdAt, currentDay)
                  .isBefore(previousStart) &&
              _analyticsDay(entry.createdAt, currentDay).isBefore(previousEnd),
        )
        .toList();
    final afterEntries = allAfterEntries
        .where(
          (entry) =>
              !_analyticsDay(entry.createdAt, currentDay).isBefore(start) &&
              _analyticsDay(entry.createdAt, currentDay).isBefore(exclusiveEnd),
        )
        .toList();
    final sessions = _listeningSessions(
      allEntries
          .where(
            (entry) =>
                !_analyticsDay(entry.createdAt, currentDay).isBefore(start) &&
                _analyticsDay(entry.createdAt, currentDay)
                    .isBefore(exclusiveEnd),
          )
          .toList(),
    );

    final moodCounts = {
      for (final mood in AuraliaMood.values)
        mood: entries.where((entry) => entry.mood == mood).length,
    };
    final dominantMood = AuraliaMood.values.reduce(
      (a, b) => moodCounts[a]! >= moodCounts[b]! ? a : b,
    );
    final currentAverage = _averageScore(entries);
    final previousAverage = _averageScore(previousEntries);
    final buckets = range == _AnalyticsRange.weekly
        ? _dailyBuckets(entries, start, currentDay)
        : _monthlyBuckets(entries, start, exclusiveEnd, currentDay);
    final averageChange = sessions.isEmpty
        ? 0.0
        : sessions.fold<double>(
                0,
                (total, session) =>
                    total + session.after.mood.score - session.before.mood.score,
              ) /
              sessions.length;
    final helpfulSessions = afterEntries
        .where(
          (entry) =>
              entry.helpfulness == ListeningHelpfulness.yes ||
              entry.helpfulness == ListeningHelpfulness.aLittle,
        )
        .length;

    return _MoodAnalytics(
      entries: entries,
      buckets: buckets,
      moodCounts: moodCounts,
      range: range,
      totalMoodEntries: entries.length,
      dominantMood: dominantMood,
      baselineLabel: entries.isEmpty
          ? 'No data'
          : _baselineLabel(currentAverage),
      moodChangeLabel: sessions.isEmpty
          ? 'No data'
          : '${averageChange >= 0 ? '+' : ''}${(averageChange * 100).round()}%',
      helpfulSessionsLabel: afterEntries.isEmpty
          ? 'No data'
          : '${(helpfulSessions / afterEntries.length * 100).round()}%',
      periodLabel: periodLabel,
      insights: _buildInsights(
        entries: entries,
        dominantMood: dominantMood,
        currentAverage: currentAverage,
        previousAverage: previousAverage,
        hasPreviousData: previousEntries.isNotEmpty,
        sessions: sessions,
        afterEntryCount: afterEntries.length,
        helpfulSessionCount: helpfulSessions,
      ),
    );
  }

  static DateTime _weekStartSunday(DateTime date) {
    return _dateOnly(date).subtract(Duration(days: date.weekday % 7));
  }

  static String _weekPeriodLabel(DateTime start, DateTime end) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final startLabel = '${months[start.month - 1]} ${start.day}';
    final endLabel = start.year == end.year
        ? '${months[end.month - 1]} ${end.day}'
        : '${months[end.month - 1]} ${end.day}, ${end.year}';
    return '$startLabel - $endLabel';
  }

  static String _monthPeriodLabel(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.year}';
  }

  static List<_MoodBucket> _dailyBuckets(
    List<MoodEntry> entries,
    DateTime start,
    DateTime anchorDay,
  ) {
    const labels = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    return List.generate(7, (index) {
      final date = start.add(Duration(days: index));
      final counts = _emptyCounts();
      for (final entry in entries) {
        if (_sameDay(_analyticsDay(entry.createdAt, anchorDay), date)) {
          counts[entry.mood] = counts[entry.mood]! + 1;
        }
      }
      return _MoodBucket(
        label: '${labels[index]} ${date.day}',
        counts: counts,
      );
    });
  }

  static List<_MoodBucket> _monthlyBuckets(
    List<MoodEntry> entries,
    DateTime monthStart,
    DateTime monthEnd,
    DateTime anchorDay,
  ) {
    final daysInMonth = monthEnd.difference(monthStart).inDays;
    final weekLength = (daysInMonth / 4).ceil();

    return List.generate(4, (index) {
      final bucketStart = monthStart.add(Duration(days: index * weekLength));
      final rawBucketEnd = index == 3
          ? monthEnd
          : monthStart.add(Duration(days: (index + 1) * weekLength));
      final bucketEnd = rawBucketEnd.isAfter(monthEnd) ? monthEnd : rawBucketEnd;
      final counts = _emptyCounts();
      for (final entry in entries) {
        final entryDay = _analyticsDay(entry.createdAt, anchorDay);
        if (!entryDay.isBefore(bucketStart) && entryDay.isBefore(bucketEnd)) {
          counts[entry.mood] = counts[entry.mood]! + 1;
        }
      }
      return _MoodBucket(
        label: 'W${index + 1}',
        counts: counts,
      );
    });
  }

  static List<_MoodInsight> _buildInsights({
    required List<MoodEntry> entries,
    required AuraliaMood dominantMood,
    required double currentAverage,
    required double previousAverage,
    required bool hasPreviousData,
    required List<_ListeningSession> sessions,
    required int afterEntryCount,
    required int helpfulSessionCount,
  }) {
    if (entries.isEmpty) {
      return const [];
    }

    final insights = <_MoodInsight>[
      _MoodInsight(
        icon: _moodIcon(dominantMood),
        color: _moodColor(dominantMood),
        text:
            'Your most frequently recorded mood is ${dominantMood.label.toLowerCase()}.',
      ),
    ];

    if (afterEntryCount > 0) {
      insights.add(
        _MoodInsight(
          icon: Icons.music_note_rounded,
          color: const Color(0xFF348557),
          text:
              '$helpfulSessionCount of $afterEntryCount completed listening sessions were marked helpful.',
        ),
      );
    }

    if (hasPreviousData) {
      final difference = currentAverage - previousAverage;
      if (difference.abs() < 0.04) {
        insights.add(
          const _MoodInsight(
            icon: Icons.balance_rounded,
            color: Color(0xFF6E2D72),
            text: 'Your average mood is stable compared with the last period.',
          ),
        );
      } else {
        insights.add(
          _MoodInsight(
            icon: difference > 0
                ? Icons.trending_up_rounded
                : Icons.trending_down_rounded,
            color: difference > 0
                ? const Color(0xFF348557)
                : const Color(0xFFD16A72),
            text: difference > 0
                ? 'Your average mood improved compared with the last period.'
                : 'Your average mood decreased compared with the last period.',
          ),
        );
      }
    }

    final recent = entries.length <= 3
        ? entries
        : entries.sublist(entries.length - 3);
    final repeatedLowMood =
        recent.length == 3 && recent.every((entry) => entry.mood.isNegative);
    insights.add(
      _MoodInsight(
        icon: repeatedLowMood
            ? Icons.self_improvement_rounded
            : Icons.spa_rounded,
        color: repeatedLowMood
            ? const Color(0xFFB26B00)
            : const Color(0xFF6E2D72),
        text: repeatedLowMood
            ? 'Your last three entries were low moods. Consider a short reset or speaking with someone you trust.'
            : 'No repeated low-mood pattern was detected in your latest entries.',
        actionLabel: repeatedLowMood ? 'View reset ideas' : null,
      ),
    );

    return insights;
  }

  static double _averageScore(List<MoodEntry> entries) {
    if (entries.isEmpty) {
      return 0;
    }
    return entries.fold<double>(
          0,
          (total, entry) => total + entry.mood.score,
        ) /
        entries.length;
  }

  static String _baselineLabel(double averageScore) {
    final percentage = (averageScore * 100).round();
    if (averageScore < 0.4) {
      return '$percentage% low';
    }
    if (averageScore < 0.65) {
      return '$percentage% mixed';
    }
    return '$percentage% positive';
  }

  static List<_ListeningSession> _listeningSessions(
    List<MoodEntry> allEntries,
  ) {
    final ordered = List<MoodEntry>.from(allEntries)
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final sessions = <_ListeningSession>[];
    MoodEntry? pendingBefore;

    for (final entry in ordered) {
      if (entry.checkInType == MoodCheckInType.beforeListening) {
        pendingBefore = entry;
      } else if (pendingBefore != null) {
        sessions.add(_ListeningSession(before: pendingBefore, after: entry));
        pendingBefore = null;
      }
    }
    return sessions;
  }

  static Map<AuraliaMood, int> _emptyCounts() {
    return {for (final mood in AuraliaMood.values) mood: 0};
  }

  static bool _sameDay(DateTime first, DateTime second) {
    final firstDay = _dateOnly(first);
    final secondDay = _dateOnly(second);
    return firstDay.year == secondDay.year &&
        firstDay.month == secondDay.month &&
        firstDay.day == secondDay.day;
  }

  static DateTime _dateOnly(DateTime value) {
    final local = value.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  static DateTime _analyticsDay(DateTime value, DateTime anchorDay) {
    final day = _dateOnly(value);
    return day.isAfter(anchorDay) ? anchorDay : day;
  }
}

class _ListeningSession {
  const _ListeningSession({required this.before, required this.after});

  final MoodEntry before;
  final MoodEntry after;
}

class _MoodBucket {
  const _MoodBucket({
    required this.label,
    required this.counts,
  });

  final String label;
  final Map<AuraliaMood, int> counts;

  int get total => counts.values.fold(0, (total, count) => total + count);
}

class _MoodInsight {
  const _MoodInsight({
    required this.icon,
    required this.color,
    required this.text,
    this.actionLabel,
  });

  final IconData icon;
  final Color color;
  final String text;
  final String? actionLabel;
}

Color _moodColor(AuraliaMood mood) {
  return switch (mood) {
    AuraliaMood.sad => const Color(0xFF5C72D8),
    AuraliaMood.stressed => const Color(0xFFD16A72),
    AuraliaMood.neutral => const Color(0xFF8D8290),
    AuraliaMood.happy => const Color(0xFFE0A83A),
    AuraliaMood.motivated => const Color(0xFF5A9E68),
  };
}

IconData _moodIcon(AuraliaMood mood) {
  return switch (mood) {
    AuraliaMood.sad => Icons.water_drop_rounded,
    AuraliaMood.stressed => Icons.bolt_rounded,
    AuraliaMood.neutral => Icons.remove_circle_outline_rounded,
    AuraliaMood.happy => Icons.wb_sunny_rounded,
    AuraliaMood.motivated => Icons.rocket_launch_rounded,
  };
}
