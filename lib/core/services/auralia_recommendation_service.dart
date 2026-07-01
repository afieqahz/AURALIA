import '../models/mood.dart';
import '../models/playlist.dart';

class AuraliaRecommendationService {
  const AuraliaRecommendationService();

  List<AuraliaPlaylist> generatePlaylistOptions(AuraliaMood mood) {
    final base = generatePlaylist(mood);
    final variants = _variantsForMood(mood);

    return List.generate(variants.length, (index) {
      final variant = variants[index];
      return AuraliaPlaylist(
        name: variant.name,
        sourceMood: mood,
        summary: variant.summary,
        tracks: _variantTracks(base.tracks, variant.trackPrefix, index),
      );
    });
  }

  AuraliaPlaylist generatePlaylist(AuraliaMood mood) {
    switch (mood) {
      case AuraliaMood.sad:
        return const AuraliaPlaylist(
          name: 'Gentle Lift Sequence',
          sourceMood: AuraliaMood.sad,
          summary:
              'A 9-song Iso-Principle playlist: 3 validation songs, 3 transition songs, and 3 elevation songs.',
          tracks: [
            AuraliaTrack(
              title: 'Rain on Quiet Windows',
              artist: 'Auralia Validation',
              stage: 'Validation',
              valence: 0.20,
              energy: 0.22,
            ),
            AuraliaTrack(
              title: 'Soft Room Echoes',
              artist: 'Auralia Validation',
              stage: 'Validation',
              valence: 0.24,
              energy: 0.25,
            ),
            AuraliaTrack(
              title: 'Blue Hour Breathing',
              artist: 'Auralia Validation',
              stage: 'Validation',
              valence: 0.28,
              energy: 0.28,
            ),
            AuraliaTrack(
              title: 'Slow Breathing Lights',
              artist: 'Auralia Transition',
              stage: 'Transition',
              valence: 0.42,
              energy: 0.36,
            ),
            AuraliaTrack(
              title: 'Clouds Begin to Move',
              artist: 'Auralia Transition',
              stage: 'Transition',
              valence: 0.48,
              energy: 0.42,
            ),
            AuraliaTrack(
              title: 'Warm Tea Interlude',
              artist: 'Auralia Transition',
              stage: 'Transition',
              valence: 0.54,
              energy: 0.46,
            ),
            AuraliaTrack(
              title: 'Morning Opens Slowly',
              artist: 'Auralia Elevation',
              stage: 'Elevation',
              valence: 0.68,
              energy: 0.54,
            ),
            AuraliaTrack(
              title: 'Small Steps Forward',
              artist: 'Auralia Elevation',
              stage: 'Elevation',
              valence: 0.74,
              energy: 0.60,
            ),
            AuraliaTrack(
              title: 'Light Finds the Window',
              artist: 'Auralia Elevation',
              stage: 'Elevation',
              valence: 0.80,
              energy: 0.64,
            ),
          ],
        );
      case AuraliaMood.stressed:
        return const AuraliaPlaylist(
          name: 'Stress Release Flow',
          sourceMood: AuraliaMood.stressed,
          summary:
              'A 9-song Iso-Principle playlist that validates tension, lowers intensity, then builds steady focus.',
          tracks: [
            AuraliaTrack(
              title: 'Static Leaves the Room',
              artist: 'Auralia Validation',
              stage: 'Validation',
              valence: 0.30,
              energy: 0.62,
            ),
            AuraliaTrack(
              title: 'Crowded Thoughts',
              artist: 'Auralia Validation',
              stage: 'Validation',
              valence: 0.34,
              energy: 0.58,
            ),
            AuraliaTrack(
              title: 'Tense Shoulders Fade',
              artist: 'Auralia Validation',
              stage: 'Validation',
              valence: 0.38,
              energy: 0.54,
            ),
            AuraliaTrack(
              title: 'Pulse to Calm',
              artist: 'Auralia Transition',
              stage: 'Transition',
              valence: 0.50,
              energy: 0.48,
            ),
            AuraliaTrack(
              title: 'Evening Reset',
              artist: 'Auralia Transition',
              stage: 'Transition',
              valence: 0.56,
              energy: 0.44,
            ),
            AuraliaTrack(
              title: 'Quiet Desk Rhythm',
              artist: 'Auralia Transition',
              stage: 'Transition',
              valence: 0.62,
              energy: 0.46,
            ),
            AuraliaTrack(
              title: 'Clear Desk Afternoon',
              artist: 'Auralia Elevation',
              stage: 'Elevation',
              valence: 0.72,
              energy: 0.56,
            ),
            AuraliaTrack(
              title: 'Steady Focus Line',
              artist: 'Auralia Elevation',
              stage: 'Elevation',
              valence: 0.78,
              energy: 0.60,
            ),
            AuraliaTrack(
              title: 'Everything in Order',
              artist: 'Auralia Elevation',
              stage: 'Elevation',
              valence: 0.84,
              energy: 0.64,
            ),
          ],
        );
      case AuraliaMood.neutral:
        return const AuraliaPlaylist(
          name: 'Balanced Study Drift',
          sourceMood: AuraliaMood.neutral,
          summary:
              'A 9-song Iso-Principle playlist that starts balanced, adds warmth, then gently lifts motivation.',
          tracks: [
            AuraliaTrack(
              title: 'Soft Baseline',
              artist: 'Auralia Validation',
              stage: 'Validation',
              valence: 0.48,
              energy: 0.38,
            ),
            AuraliaTrack(
              title: 'Plain Sky Notes',
              artist: 'Auralia Validation',
              stage: 'Validation',
              valence: 0.50,
              energy: 0.40,
            ),
            AuraliaTrack(
              title: 'Still Page Rhythm',
              artist: 'Auralia Validation',
              stage: 'Validation',
              valence: 0.52,
              energy: 0.42,
            ),
            AuraliaTrack(
              title: 'Light Through Notes',
              artist: 'Auralia Transition',
              stage: 'Transition',
              valence: 0.60,
              energy: 0.46,
            ),
            AuraliaTrack(
              title: 'Open Notebook',
              artist: 'Auralia Transition',
              stage: 'Transition',
              valence: 0.64,
              energy: 0.50,
            ),
            AuraliaTrack(
              title: 'Tiny Spark Loop',
              artist: 'Auralia Transition',
              stage: 'Transition',
              valence: 0.68,
              energy: 0.52,
            ),
            AuraliaTrack(
              title: 'Steady Forward',
              artist: 'Auralia Elevation',
              stage: 'Elevation',
              valence: 0.74,
              energy: 0.56,
            ),
            AuraliaTrack(
              title: 'Bright Margin',
              artist: 'Auralia Elevation',
              stage: 'Elevation',
              valence: 0.78,
              energy: 0.60,
            ),
            AuraliaTrack(
              title: 'Good Pace',
              artist: 'Auralia Elevation',
              stage: 'Elevation',
              valence: 0.82,
              energy: 0.64,
            ),
          ],
        );
      case AuraliaMood.happy:
        return const AuraliaPlaylist(
          name: 'Positive Mood Keeper',
          sourceMood: AuraliaMood.happy,
          summary:
              'A 9-song Iso-Principle playlist that validates happiness, keeps it stable, then strengthens positive energy.',
          tracks: [
            AuraliaTrack(
              title: 'Golden Hour Loop',
              artist: 'Auralia Validation',
              stage: 'Validation',
              valence: 0.76,
              energy: 0.58,
            ),
            AuraliaTrack(
              title: 'Easy Smile Rhythm',
              artist: 'Auralia Validation',
              stage: 'Validation',
              valence: 0.78,
              energy: 0.62,
            ),
            AuraliaTrack(
              title: 'Light Weekend Air',
              artist: 'Auralia Validation',
              stage: 'Validation',
              valence: 0.80,
              energy: 0.64,
            ),
            AuraliaTrack(
              title: 'Warm Steps',
              artist: 'Auralia Transition',
              stage: 'Transition',
              valence: 0.82,
              energy: 0.66,
            ),
            AuraliaTrack(
              title: 'Good News Walk',
              artist: 'Auralia Transition',
              stage: 'Transition',
              valence: 0.84,
              energy: 0.68,
            ),
            AuraliaTrack(
              title: 'Bright Walk Home',
              artist: 'Auralia Transition',
              stage: 'Transition',
              valence: 0.86,
              energy: 0.70,
            ),
            AuraliaTrack(
              title: 'Keep This Feeling',
              artist: 'Auralia Elevation',
              stage: 'Elevation',
              valence: 0.88,
              energy: 0.72,
            ),
            AuraliaTrack(
              title: 'Sunlit Chorus',
              artist: 'Auralia Elevation',
              stage: 'Elevation',
              valence: 0.90,
              energy: 0.74,
            ),
            AuraliaTrack(
              title: 'One More Smile',
              artist: 'Auralia Elevation',
              stage: 'Elevation',
              valence: 0.92,
              energy: 0.76,
            ),
          ],
        );
      case AuraliaMood.motivated:
        return const AuraliaPlaylist(
          name: 'Momentum Builder',
          sourceMood: AuraliaMood.motivated,
          summary:
              'A 9-song Iso-Principle playlist that matches motivation, stabilizes focus, then builds momentum.',
          tracks: [
            AuraliaTrack(
              title: 'Ready Mode',
              artist: 'Auralia Validation',
              stage: 'Validation',
              valence: 0.78,
              energy: 0.72,
            ),
            AuraliaTrack(
              title: 'Forward Signal',
              artist: 'Auralia Validation',
              stage: 'Validation',
              valence: 0.80,
              energy: 0.76,
            ),
            AuraliaTrack(
              title: 'Task Light On',
              artist: 'Auralia Validation',
              stage: 'Validation',
              valence: 0.82,
              energy: 0.78,
            ),
            AuraliaTrack(
              title: 'Clean Momentum',
              artist: 'Auralia Transition',
              stage: 'Transition',
              valence: 0.84,
              energy: 0.80,
            ),
            AuraliaTrack(
              title: 'Productive Pulse',
              artist: 'Auralia Transition',
              stage: 'Transition',
              valence: 0.86,
              energy: 0.82,
            ),
            AuraliaTrack(
              title: 'Focus Forward',
              artist: 'Auralia Transition',
              stage: 'Transition',
              valence: 0.88,
              energy: 0.84,
            ),
            AuraliaTrack(
              title: 'Finish Line Focus',
              artist: 'Auralia Elevation',
              stage: 'Elevation',
              valence: 0.90,
              energy: 0.86,
            ),
            AuraliaTrack(
              title: 'Push Through Brightly',
              artist: 'Auralia Elevation',
              stage: 'Elevation',
              valence: 0.92,
              energy: 0.88,
            ),
            AuraliaTrack(
              title: 'Done and Rising',
              artist: 'Auralia Elevation',
              stage: 'Elevation',
              valence: 0.94,
              energy: 0.90,
            ),
          ],
        );
    }
  }

  List<AuraliaTrack> _variantTracks(
    List<AuraliaTrack> baseTracks,
    String prefix,
    int variantIndex,
  ) {
    final adjustment = variantIndex * 0.02;

    return List.generate(baseTracks.length, (index) {
      final track = baseTracks[index];
      return AuraliaTrack(
        title: '$prefix ${index + 1}: ${track.title}',
        artist: track.artist,
        stage: track.stage,
        valence: (track.valence + adjustment).clamp(0.0, 1.0),
        energy: (track.energy + adjustment).clamp(0.0, 1.0),
      );
    });
  }

  List<_PlaylistVariant> _variantsForMood(AuraliaMood mood) {
    switch (mood) {
      case AuraliaMood.sad:
        return const [
          _PlaylistVariant(
            'Gentle Lift Sequence',
            'A soft emotional recovery playlist that validates sadness, transitions gently, then lifts mood.',
            'Gentle',
          ),
          _PlaylistVariant(
            'Soft Hope Mix',
            'A slower Iso-Principle route for users who want calm validation before hopeful songs.',
            'Hope',
          ),
          _PlaylistVariant(
            'Night Calm Reset',
            'A quiet late-night recovery playlist designed to reduce rumination and end warmly.',
            'Night',
          ),
          _PlaylistVariant(
            'Emotional Recovery Flow',
            'A reflective sequence that starts low, moves through acceptance, and ends brighter.',
            'Recovery',
          ),
          _PlaylistVariant(
            'Rainy Window Comfort',
            'A gentle comfort mix for low-energy moments that need softness before lift.',
            'Rainy',
          ),
          _PlaylistVariant(
            'Slow Healing Session',
            'A careful emotional support route that keeps the first stage validating and unhurried.',
            'Healing',
          ),
          _PlaylistVariant(
            'Quiet Hope Radio',
            'A lighter recovery set that gradually introduces warmth, hope, and emotional movement.',
            'Quiet',
          ),
          _PlaylistVariant(
            'After Tears Lift',
            'A post-cry playlist that starts tender, steadies breathing, and ends gently brighter.',
            'Lift',
          ),
        ];
      case AuraliaMood.stressed:
        return const [
          _PlaylistVariant(
            'Stress Release Flow',
            'A tension-aware sequence that lowers intensity before building steady focus.',
            'Release',
          ),
          _PlaylistVariant(
            'Deadline Decompression',
            'A study-friendly playlist for academic stress, moving from pressure to clarity.',
            'Deadline',
          ),
          _PlaylistVariant(
            'Breath and Reset',
            'A calmer sequence built around breathing space, focus, and emotional grounding.',
            'Reset',
          ),
          _PlaylistVariant(
            'Study Calm Mode',
            'A practical focus playlist that turns stress into a stable work rhythm.',
            'Study',
          ),
          _PlaylistVariant(
            'Anxiety Ease Radio',
            'A grounding sequence for anxious moments that reduces intensity before adding clarity.',
            'Ease',
          ),
          _PlaylistVariant(
            'Calm Focus Station',
            'A low-distraction playlist for study sessions that need calm momentum.',
            'Calm',
          ),
          _PlaylistVariant(
            'Pressure to Progress',
            'A structured stress playlist that turns nervous energy into manageable action.',
            'Progress',
          ),
          _PlaylistVariant(
            'Unwind and Continue',
            'A reset mix for breaks between tasks, easing tension without losing productivity.',
            'Unwind',
          ),
        ];
      case AuraliaMood.neutral:
        return const [
          _PlaylistVariant(
            'Balanced Study Drift',
            'A balanced playlist that starts neutral, adds warmth, and gently improves motivation.',
            'Balance',
          ),
          _PlaylistVariant(
            'Light Focus Flow',
            'A clean study sequence for neutral days that need a little brightness.',
            'Focus',
          ),
          _PlaylistVariant(
            'Warm Routine Mix',
            'A soft everyday playlist that keeps mood stable while adding positive movement.',
            'Routine',
          ),
          _PlaylistVariant(
            'Steady Mood Builder',
            'A gradual playlist that turns neutral energy into comfortable momentum.',
            'Steady',
          ),
          _PlaylistVariant(
            'Easy Morning Start',
            'A warm low-pressure playlist for beginning the day with stable energy.',
            'Morning',
          ),
          _PlaylistVariant(
            'Soft Productivity Radio',
            'A balanced work mix that keeps attention steady while adding quiet brightness.',
            'Soft',
          ),
          _PlaylistVariant(
            'Neutral Glow Up',
            'A subtle mood-lift route for ordinary days that could use more color.',
            'Glow',
          ),
          _PlaylistVariant(
            'Everyday Balance Mix',
            'A repeatable daily playlist that keeps mood even and gently forward-moving.',
            'Everyday',
          ),
        ];
      case AuraliaMood.happy:
        return const [
          _PlaylistVariant(
            'Positive Mood Keeper',
            'A feel-good sequence that validates happiness and sustains positive energy.',
            'Happy',
          ),
          _PlaylistVariant(
            'Bright Energy Mix',
            'A more upbeat option for users who want to amplify an already good mood.',
            'Bright',
          ),
          _PlaylistVariant(
            'Feel Good Flow',
            'A smooth positive playlist that maintains joy without becoming overwhelming.',
            'Flow',
          ),
          _PlaylistVariant(
            'Social Vibes',
            'An energetic positive route for social, active, or confident moods.',
            'Social',
          ),
          _PlaylistVariant(
            'Sunny Day Radio',
            'A bright everyday playlist for keeping good mood fresh and easy.',
            'Sunny',
          ),
          _PlaylistVariant(
            'Confidence Glow',
            'A polished feel-good route for confident, expressive, and upbeat moments.',
            'Glow',
          ),
          _PlaylistVariant(
            'Weekend Spark',
            'A playful positive playlist that keeps energy high without losing warmth.',
            'Weekend',
          ),
          _PlaylistVariant(
            'Joy Ride Mix',
            'A lively happy sequence for movement, errands, or celebrating small wins.',
            'Joy',
          ),
        ];
      case AuraliaMood.motivated:
        return const [
          _PlaylistVariant(
            'Momentum Builder',
            'A goal-focused sequence that sustains motivation and builds productive energy.',
            'Momentum',
          ),
          _PlaylistVariant(
            'Deep Work Drive',
            'A stronger focus playlist for assignments, coding, writing, or revision sessions.',
            'Work',
          ),
          _PlaylistVariant(
            'Power Through Mix',
            'A higher-energy sequence for users who want to push through tasks.',
            'Power',
          ),
          _PlaylistVariant(
            'Goal Mode Sequence',
            'A confident playlist that maintains drive and ends with high forward momentum.',
            'Goal',
          ),
          _PlaylistVariant(
            'Assignment Sprint',
            'A task-focused sequence for short bursts of productive energy.',
            'Sprint',
          ),
          _PlaylistVariant(
            'Confidence Boost Radio',
            'A motivating route that keeps confidence high while staying focused.',
            'Boost',
          ),
          _PlaylistVariant(
            'Finish Line Energy',
            'A high-momentum playlist for the last stretch of work or study.',
            'Finish',
          ),
          _PlaylistVariant(
            'Main Character Focus',
            'A bold productivity playlist for users who want drive, confidence, and lift.',
            'Focus',
          ),
        ];
    }
  }
}

class _PlaylistVariant {
  const _PlaylistVariant(this.name, this.summary, this.trackPrefix);

  final String name;
  final String summary;
  final String trackPrefix;
}
