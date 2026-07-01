import 'dart:math';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../models/playlist.dart';

class PostListeningNotificationService {
  PostListeningNotificationService._();

  static final PostListeningNotificationService instance =
      PostListeningNotificationService._();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  static const _feedbackNotificationId = 2401;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    tz.initializeTimeZones();

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const settings = InitializationSettings(android: androidSettings);
    await _notifications.initialize(settings);

    final androidPlugin = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidPlugin?.requestNotificationsPermission();

    _initialized = true;
  }

  Future<void> schedulePlaylistFeedback(AuraliaPlaylist playlist) async {
    await initialize();
    await cancelPlaylistFeedback();

    final delay = _playlistDuration(playlist);
    final scheduledAt = tz.TZDateTime.now(tz.local).add(delay);

    await _notifications.zonedSchedule(
      _feedbackNotificationId,
      'How do you feel now?',
      'Your AURALIA playlist is done. Tap to save your post-listening check-in.',
      scheduledAt,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'auralia_post_listening',
          'Post-listening check-ins',
          channelDescription:
              'Reminders to record how you feel after a playlist finishes.',
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.reminder,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: 'post_listening_check_in',
    );
  }

  Future<void> cancelPlaylistFeedback() async {
    await _notifications.cancel(_feedbackNotificationId);
  }

  Duration _playlistDuration(AuraliaPlaylist playlist) {
    final totalMs = playlist.tracks.fold<int>(
      0,
      (total, track) => total + (track.durationMs ?? 240000),
    );

    final clampedMs = max(totalMs, const Duration(minutes: 1).inMilliseconds);
    return Duration(milliseconds: clampedMs);
  }
}
