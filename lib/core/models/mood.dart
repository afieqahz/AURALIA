enum AuraliaMood { sad, stressed, neutral, happy, motivated }

enum MoodCheckInType { beforeListening, afterListening }

enum ListeningHelpfulness { yes, aLittle, no }

extension AuraliaMoodDetails on AuraliaMood {
  String get label {
    switch (this) {
      case AuraliaMood.sad:
        return 'Sad';
      case AuraliaMood.stressed:
        return 'Stressed';
      case AuraliaMood.neutral:
        return 'Neutral';
      case AuraliaMood.happy:
        return 'Happy';
      case AuraliaMood.motivated:
        return 'Motivated';
    }
  }

  String get emoji {
    switch (this) {
      case AuraliaMood.sad:
        return ':(';
      case AuraliaMood.stressed:
        return '!';
      case AuraliaMood.neutral:
        return '-';
      case AuraliaMood.happy:
        return ':)';
      case AuraliaMood.motivated:
        return '^';
    }
  }

  bool get isNegative =>
      this == AuraliaMood.sad || this == AuraliaMood.stressed;

  double get score {
    switch (this) {
      case AuraliaMood.sad:
        return 0.22;
      case AuraliaMood.stressed:
        return 0.32;
      case AuraliaMood.neutral:
        return 0.5;
      case AuraliaMood.happy:
        return 0.76;
      case AuraliaMood.motivated:
        return 0.88;
    }
  }
}

class MoodEntry {
  const MoodEntry({
    this.id,
    required this.mood,
    required this.createdAt,
    this.checkInType = MoodCheckInType.beforeListening,
    this.playlistName,
    this.helpfulness,
  });

  final String? id;
  final AuraliaMood mood;
  final DateTime createdAt;
  final MoodCheckInType checkInType;
  final String? playlistName;
  final ListeningHelpfulness? helpfulness;

  Map<String, dynamic> toJson({String? userId}) {
    final json = <String, dynamic>{
      'mood_type': mood.name,
      'created_at': createdAt.toIso8601String(),
      'check_in_type': checkInType.name,
      'playlist_name': playlistName,
      'helpfulness': helpfulness?.name,
    };
    if (id != null) {
      json['id'] = id;
    }
    if (userId != null) {
      json['user_id'] = userId;
    }
    return json;
  }

  factory MoodEntry.fromJson(Map<String, dynamic> json) {
    final helpfulnessName = json['helpfulness']?.toString();
    ListeningHelpfulness? helpfulness;
    if (helpfulnessName != null) {
      for (final value in ListeningHelpfulness.values) {
        if (value.name == helpfulnessName) {
          helpfulness = value;
          break;
        }
      }
    }

    return MoodEntry(
      id: json['id']?.toString(),
      mood: AuraliaMood.values.firstWhere(
        (mood) => mood.name == json['mood_type'],
        orElse: () => AuraliaMood.neutral,
      ),
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      checkInType: MoodCheckInType.values.firstWhere(
        (type) => type.name == json['check_in_type'],
        orElse: () => MoodCheckInType.beforeListening,
      ),
      playlistName: json['playlist_name']?.toString(),
      helpfulness: helpfulness,
    );
  }
}
