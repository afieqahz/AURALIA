import '../models/mood.dart';

abstract class MoodRepository {
  Future<List<MoodEntry>> loadMoodHistory(String userId);

  Future<MoodEntry> saveMoodEntry({
    required String userId,
    required AuraliaMood mood,
    MoodCheckInType checkInType = MoodCheckInType.beforeListening,
    String? playlistName,
    ListeningHelpfulness? helpfulness,
  });
}

class LocalMoodRepository implements MoodRepository {
  final List<MoodEntry> _entries = [];

  @override
  Future<List<MoodEntry>> loadMoodHistory(String userId) async {
    if (_entries.isEmpty) {
      _seedDemoHistory();
    }
    return List.unmodifiable(_entries);
  }

  @override
  Future<MoodEntry> saveMoodEntry({
    required String userId,
    required AuraliaMood mood,
    MoodCheckInType checkInType = MoodCheckInType.beforeListening,
    String? playlistName,
    ListeningHelpfulness? helpfulness,
  }) async {
    final entry = MoodEntry(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      mood: mood,
      createdAt: DateTime.now(),
      checkInType: checkInType,
      playlistName: playlistName,
      helpfulness: helpfulness,
    );
    _entries.add(entry);
    return entry;
  }

  void _seedDemoHistory() {
    final now = DateTime.now();
    final seededMoods = [
      AuraliaMood.stressed,
      AuraliaMood.sad,
      AuraliaMood.neutral,
      AuraliaMood.happy,
      AuraliaMood.stressed,
      AuraliaMood.neutral,
    ];

    for (var i = 0; i < seededMoods.length; i++) {
      _entries.add(
        MoodEntry(
          id: 'seed-$i',
          mood: seededMoods[i],
          createdAt: DateTime(
            now.year,
            now.month,
            now.day,
          ).subtract(Duration(days: 6 - i)),
        ),
      );
    }
  }
}
