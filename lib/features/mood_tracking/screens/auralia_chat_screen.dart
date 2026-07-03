import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:auralia_app/core/models/mood.dart';
import 'package:auralia_app/core/models/playlist.dart';
import 'package:auralia_app/core/services/auralia_scope.dart';
import 'package:auralia_app/core/services/auralia_state.dart';
import 'package:auralia_app/core/widgets/floating_bubbles.dart';

class AuraliaChatScreen extends StatefulWidget {
  const AuraliaChatScreen({super.key, this.onOpenPlayer});

  final VoidCallback? onOpenPlayer;

  @override
  State<AuraliaChatScreen> createState() => _AuraliaChatScreenState();
}

class _AuraliaChatScreenState extends State<AuraliaChatScreen> {
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<_ChatMessage> _messages = [];
  final Random _phraseRandom = Random();
  final Map<String, int> _lastPhraseIndexes = {};
  AuraliaMood? _selectedMood;
  bool _isGenerating = false;
  bool _isTyping = false;
  bool _showPlaylists = false;

  @override
  void initState() {
    super.initState();
    _messages.add(
      const _ChatMessage(
        text:
            'Hi, I am AURALIA. Tell me how you feel and I will build an ISO-Principle music journey for you.',
        isUser: false,
      ),
    );
  }

  @override
  void dispose() {
    _chatController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _recordMood(
    AuraliaMood mood, {
    bool addUserMessage = true,
    String? userText,
  }) async {
    if (_isGenerating || _isTyping) {
      return;
    }

    setState(() {
      _selectedMood = mood;
      _showPlaylists = false;
      if (addUserMessage) {
        _messages.add(
          _ChatMessage(
            text: userText ?? 'I feel ${mood.label.toLowerCase()}.',
            isUser: true,
          ),
        );
      }
      _isTyping = true;
    });
    _scrollToBottom();

    await _showAssistantMessages(_responseSequenceFor(mood));
    if (!mounted) {
      return;
    }

    setState(() {
      _isTyping = false;
      _isGenerating = true;
    });
    _scrollToBottom();

    final state = AuraliaScope.of(context);
    final generation = state.recordMood(mood);
    await _showAssistantMessages(_generationMessagesFor(mood));
    final success = await generation;
    if (!mounted) {
      return;
    }

    setState(() {
      _isGenerating = false;
      if (success) {
        _messages.add(
          const _ChatMessage(text: 'Playlists generated.', isUser: false),
        );
        _showPlaylists = true;
      } else {
        _selectedMood = null;
        _showPlaylists = false;
        _messages.add(
          _ChatMessage(
            text: state.errorMessage ?? 'I could not generate playlists right now.',
            isUser: false,
            isError: true,
          ),
        );
      }
    });
    _scrollToBottom();
    if (success && state.shouldShowWellnessSuggestion) {
      state.markWellnessSuggestionShown();
      await _showWellnessSuggestion();
    }
  }

  Future<void> _showWellnessSuggestion() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => const _WellnessSuggestionSheet(),
    );
  }

  void _sendMessage() {
    final text = _chatController.text.trim();
    if (text.isEmpty || _isGenerating || _isTyping) {
      return;
    }
    _chatController.clear();

    final mood = _moodFromText(text);
    setState(() {
      _messages.add(_ChatMessage(text: text, isUser: true));
      if (mood == null) {
        _messages.add(
          const _ChatMessage(
            text:
                'I can help through music. Choose a mood below, or say something like "I feel stressed" or "I am happy today."',
            isUser: false,
          ),
        );
      }
    });
    _scrollToBottom();

    if (mood != null) {
      _recordMood(mood, addUserMessage: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AuraliaScope.of(context);
    final hasPlaylists =
        _selectedMood != null &&
        !_isGenerating &&
        !_isTyping &&
        _showPlaylists &&
        state.currentPlaylist.tracks.isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F1F8),
      body: SafeArea(
        child: Column(
          children: [
            _ChatHeader(onBack: () => Navigator.pop(context)),
            Expanded(
              child: Stack(
                children: [
                  const Positioned(
                    top: 24,
                    right: -70,
                    child: _ChatGlow(size: 180, color: Color(0xFFE8D8EA)),
                  ),
                  const Positioned(
                    bottom: 80,
                    left: -84,
                    child: _ChatGlow(size: 190, color: Color(0xFFF3E7F5)),
                  ),
                  ListView(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 22),
                    children: [
                      ..._messages.map(
                        (message) => _MessageBubble(message: message),
                      ),
                      if (!_isGenerating && !_isTyping)
                        _MoodPrompt(
                          enabled: !_isGenerating && !_isTyping,
                          onSelected: _recordMood,
                        ),
                      if (_isTyping) const _TypingBubble(),
                      if (_isGenerating) const _GeneratingBubble(),
                      if (hasPlaylists) ...[
                        const _PlaylistReadyHeader(),
                        _PlaylistReveal(
                          child: Column(
                            children: [
                              if (state.playlistOptions.isNotEmpty) ...[
                                _PlaylistOptions(
                                  playlists: state.playlistOptions,
                                  activePlaylist: state.currentPlaylist,
                                  onSelected: state.selectPlaylist,
                                ),
                                const SizedBox(height: 14),
                              ],
                              _SelectedPlaylistCard(
                                playlist: state.currentPlaylist,
                                isSaved: state.isCurrentPlaylistLiked,
                                isBusy: state.isBusy,
                                onSave: () => _toggleSave(state),
                                onPlay: () {
                                  state.playCurrentPlaylist();
                                  Navigator.pop(context);
                                  widget.onOpenPlayer?.call();
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            _ChatComposer(
              controller: _chatController,
              enabled: !_isGenerating && !_isTyping,
              onSend: _sendMessage,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleSave(AuraliaState state) async {
    final wasSaved = state.isCurrentPlaylistLiked;
    final success = wasSaved
        ? await state.toggleCurrentPlaylistFavorite()
        : await state.saveCurrentPlaylist();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? wasSaved
                    ? 'Removed from favourites.'
                    : 'Playlist saved.'
              : state.errorMessage ?? 'Unable to update playlist.',
        ),
        backgroundColor: success
            ? const Color(0xFF4A154B)
            : Colors.redAccent,
      ),
    );
  }

  AuraliaMood? _moodFromText(String text) {
    final value = text.toLowerCase();
    if (_containsAny(value, ['sad', 'down', 'cry', 'heartbroken', 'lonely'])) {
      return AuraliaMood.sad;
    }
    if (_containsAny(value, ['stress', 'anxious', 'pressure', 'overwhelmed'])) {
      return AuraliaMood.stressed;
    }
    if (_containsAny(value, ['happy', 'great', 'good mood', 'joy', 'excited'])) {
      return AuraliaMood.happy;
    }
    if (_containsAny(value, ['motivated', 'productive', 'focus', 'energized'])) {
      return AuraliaMood.motivated;
    }
    if (_containsAny(value, ['neutral', 'okay', 'normal', 'fine', 'calm'])) {
      return AuraliaMood.neutral;
    }
    return null;
  }

  bool _containsAny(String text, List<String> words) {
    return words.any(text.contains);
  }

  Future<void> _showAssistantMessages(List<String> messages) async {
    for (final message in messages) {
      await Future.delayed(const Duration(milliseconds: 420));
      if (!mounted) {
        return;
      }
      setState(() {
        _messages.add(_ChatMessage(text: message, isUser: false));
      });
      _scrollToBottom();
      if (message != messages.last) {
        await Future.delayed(const Duration(milliseconds: 280));
      }
    }
  }

  List<String> _responseSequenceFor(AuraliaMood mood) {
    return _phrasesFromPools(
      mood: mood,
      group: 'response',
      pools: _responsePhrasePools[mood]!,
    );
  }

  List<String> _generationMessagesFor(AuraliaMood mood) {
    return _phrasesFromPools(
      mood: mood,
      group: 'generation',
      pools: _generationPhrasePools[mood]!,
    );
  }

  List<String> _phrasesFromPools({
    required AuraliaMood mood,
    required String group,
    required List<List<String>> pools,
  }) {
    return List.generate(
      pools.length,
      (index) => _pickPhrase(
        key: '$group-${mood.name}-$index',
        options: pools[index],
      ),
    );
  }

  String _pickPhrase({required String key, required List<String> options}) {
    if (options.length == 1) {
      return options.first;
    }

    var selectedIndex = _phraseRandom.nextInt(options.length);
    final lastIndex = _lastPhraseIndexes[key];
    if (lastIndex != null && selectedIndex == lastIndex) {
      selectedIndex = (selectedIndex + 1) % options.length;
    }
    _lastPhraseIndexes[key] = selectedIndex;
    return options[selectedIndex];
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    });
  }
}

const Map<AuraliaMood, List<List<String>>> _responsePhrasePools = {
  AuraliaMood.sad: [
    [
      'Oh, I am sorry you are feeling sad. Thank you for telling me.',
      'I am sorry today feels sad. Thank you for sharing that with me.',
      'I hear the sadness in that. Thank you for letting me know.',
    ],
    [
      'I will not rush you into happy songs right away. I will start with music that understands the heaviness first.',
      'I will not jump straight into bright songs. I will begin with music that meets the heaviness first.',
      'I will start gently, with songs that make space for the sadness before asking it to shift.',
    ],
    [
      'Then I will gently guide the playlist toward something lighter, one step at a time.',
      'Then I will move the playlist slowly toward a softer, lighter feeling step by step.',
      'After that, I will guide the sound toward comfort and a little more light.',
    ],
  ],
  AuraliaMood.stressed: [
    [
      'That sounds like a lot to carry. Let us slow things down for a moment.',
      'That sounds heavy on your mind. Let us give everything a little more space.',
      'I hear the pressure there. Let us slow the pace for a moment.',
    ],
    [
      'I will begin with tracks that reduce the pressure instead of adding more noise.',
      'I will start with songs that soften the pressure rather than adding more stimulation.',
      'I will choose an opening that eases the tension instead of crowding your thoughts.',
    ],
    [
      'After that, I will move toward calmer focus so your mind has room to breathe.',
      'Then I will guide the playlist toward steadier focus, so your mind can breathe.',
      'After the first tracks, I will shift toward calm energy and clearer focus.',
    ],
  ],
  AuraliaMood.neutral: [
    [
      'Okay, I hear you. Neutral days can still need the right kind of support.',
      'Okay, I understand. Even a neutral mood can use the right kind of soundtrack.',
      'Got it. A steady day still deserves music that supports where you are.',
    ],
    [
      'I will keep the playlist steady at first, so it does not push your mood too suddenly.',
      'I will begin with a steady sound, so the playlist does not shift your mood too sharply.',
      'I will keep the opening balanced and easy, matching your mood without forcing it.',
    ],
    [
      'Then I will add a soft lift to help the rest of your day feel a little warmer.',
      'Then I will bring in a gentle lift to add a little warmth to the day.',
      'After that, I will let the playlist rise softly toward a warmer feeling.',
    ],
  ],
  AuraliaMood.happy: [
    [
      'I love that you are feeling happy. Let us keep that good feeling with you.',
      'I am glad you are feeling happy. Let us help that feeling stay with you.',
      'That is lovely to hear. I will help keep that brightness around you.',
    ],
    [
      'I will choose songs that match your brightness without making the playlist feel too intense.',
      'I will start with songs that match the brightness without pushing it too hard.',
      'I will keep the energy warm and bright, without making it feel overwhelming.',
    ],
    [
      'Then I will build toward a playful finish so the mood stays alive.',
      'Then I will build the playlist toward a playful finish that keeps the mood glowing.',
      'After that, I will lift the ending so the good feeling keeps moving with you.',
    ],
  ],
  AuraliaMood.motivated: [
    [
      'That is a strong place to start. I can feel the drive in that mood.',
      'That is a focused place to begin. I can feel the energy in that mood.',
      'I hear the drive in that. Let us turn it into steady momentum.',
    ],
    [
      'I will match your energy with songs that keep you moving without distracting you.',
      'I will choose songs that match your drive while keeping the focus clear.',
      'I will start with tracks that support your energy without pulling attention away.',
    ],
    [
      'Then I will build momentum so the playlist supports focus and action.',
      'Then I will build the sequence toward momentum, focus, and action.',
      'After that, I will keep the progression moving so your focus can stay strong.',
    ],
  ],
};

const Map<AuraliaMood, List<List<String>>> _generationPhrasePools = {
  AuraliaMood.sad: [
    [
      'I am shaping the first songs to validate how you feel.',
      'I am choosing the opening songs to gently validate this feeling.',
      'I am setting the first tracks to meet your sadness with care.',
    ],
    [
      'Now I am looking for a gentle transition toward comfort.',
      'Now I am finding a soft transition toward comfort.',
      'Now I am guiding the middle tracks toward something more comforting.',
    ],
  ],
  AuraliaMood.stressed: [
    [
      'I am choosing a calmer starting point.',
      'I am setting up a calmer opening for the playlist.',
      'I am finding tracks that start with less pressure.',
    ],
    [
      'Now I am arranging the next tracks to release tension slowly.',
      'Now I am shaping the next songs to let tension loosen slowly.',
      'Now I am building a slow release from pressure into steadier focus.',
    ],
  ],
  AuraliaMood.neutral: [
    [
      'I am keeping the opening balanced and easy.',
      'I am setting the first songs to feel steady and easy.',
      'I am choosing a balanced opening that meets you where you are.',
    ],
    [
      'Now I am adding a light lift without changing the mood too sharply.',
      'Now I am adding a gentle lift without pushing the mood too fast.',
      'Now I am guiding the playlist upward in a soft, natural way.',
    ],
  ],
  AuraliaMood.happy: [
    [
      'I am matching the playlist to your good mood.',
      'I am choosing songs that match your bright mood.',
      'I am shaping the opening around the happiness you are feeling.',
    ],
    [
      'Now I am arranging the final tracks to keep that brightness going.',
      'Now I am building the ending so the brightness can continue.',
      'Now I am setting the final songs to keep the good feeling alive.',
    ],
  ],
  AuraliaMood.motivated: [
    [
      'I am matching your drive with steady energy.',
      'I am choosing tracks that match your drive with steady energy.',
      'I am setting the opening to support your motivation and focus.',
    ],
    [
      'Now I am building a focused progression for the next tracks.',
      'Now I am arranging the next tracks into a focused progression.',
      'Now I am building momentum so the playlist keeps you moving.',
    ],
  ],
};

class _ChatHeader extends StatelessWidget {
  const _ChatHeader({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 18, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFEAE1EB))),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.chevron_left_rounded, size: 30),
          ),
          Container(
            width: 42,
            height: 42,
            decoration: const BoxDecoration(
              color: Color(0xFF5A2C62),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              color: Colors.white,
              size: 21,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AURALIA',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF38143E),
                  ),
                ),
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: Color(0xFF4FA36C),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'Mood music assistant',
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        color: Colors.black45,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatGlow extends StatelessWidget {
  const _ChatGlow({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.62),
              blurRadius: 70,
              spreadRadius: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final _ChatMessage message;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 300),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
        decoration: BoxDecoration(
          color: message.isUser
              ? const Color(0xFF5A2C62)
              : message.isError
              ? const Color(0xFFFFE7E7)
              : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(17),
            topRight: const Radius.circular(17),
            bottomLeft: Radius.circular(message.isUser ? 17 : 4),
            bottomRight: Radius.circular(message.isUser ? 4 : 17),
          ),
          boxShadow: message.isUser
              ? null
              : [
                  BoxShadow(
                    color: const Color(0xFF4A154B).withValues(alpha: 0.04),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
        ),
        child: Text(
          message.text,
          style: GoogleFonts.poppins(
            fontSize: 12,
            height: 1.4,
            color: message.isUser
                ? Colors.white
                : message.isError
                ? const Color(0xFFA33E45)
                : const Color(0xFF4E3A50),
          ),
        ),
      ),
    );
  }
}

class _MoodPrompt extends StatelessWidget {
  const _MoodPrompt({required this.enabled, required this.onSelected});

  final bool enabled;
  final ValueChanged<AuraliaMood> onSelected;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFEADFEA)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF4A154B).withValues(alpha: 0.05),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8D8EA),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(
                    Icons.auto_awesome_rounded,
                    size: 18,
                    color: Color(0xFF5A2C62),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'How are you feeling today?',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF38143E),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: AuraliaMood.values.map((mood) {
                final style = _MoodChipStyle.forMood(mood);
                return ActionChip(
                  onPressed: enabled ? () => onSelected(mood) : null,
                  avatar: Icon(_moodIcon(mood), size: 16, color: style.accent),
                  label: Text(mood.label),
                  backgroundColor: style.background,
                  side: BorderSide(color: style.border),
                  labelStyle: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: style.text,
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(17),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _TypingDots(),
            const SizedBox(width: 9),
            Text(
              'AURALIA is thinking...',
              style: GoogleFonts.poppins(
                fontSize: 11,
                color: Colors.black54,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GeneratingBubble extends StatelessWidget {
  const _GeneratingBubble();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(15, 13, 16, 13),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFEADFEA)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF4A154B).withValues(alpha: 0.05),
              blurRadius: 16,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _MiniEqualizer(),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Shaping your playlist',
                  style: GoogleFonts.poppins(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF38143E),
                  ),
                ),
                Text(
                  'Finding tracks that fit your mood...',
                  style: GoogleFonts.poppins(
                    fontSize: 10,
                    color: Colors.black45,
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

class _PlaylistReveal extends StatelessWidget {
  const _PlaylistReveal({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 18 * (1 - value)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

class _PlaylistReadyHeader extends StatelessWidget {
  const _PlaylistReadyHeader();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: const Color(0xFFE8D8EA),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.queue_music_rounded,
              size: 15,
              color: Color(0xFF5A2C62),
            ),
            const SizedBox(width: 6),
            Text(
              'Choose a playlist',
              style: GoogleFonts.poppins(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF5A2C62),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            final active = ((_controller.value * 3).floor() % 3) == index;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: const EdgeInsets.only(right: 3),
              width: 5,
              height: active ? 8 : 5,
              decoration: BoxDecoration(
                color: const Color(0xFF5A2C62).withValues(
                  alpha: active ? 0.85 : 0.28,
                ),
                shape: BoxShape.circle,
              ),
            );
          }),
        );
      },
    );
  }
}

class _MiniEqualizer extends StatefulWidget {
  const _MiniEqualizer();

  @override
  State<_MiniEqualizer> createState() => _MiniEqualizerState();
}

class _MiniEqualizerState extends State<_MiniEqualizer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 780),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(5, (index) {
            final phase = ((_controller.value + index * 0.18) % 1.0);
            final height = 7 + (phase < 0.5 ? phase : 1 - phase) * 22;
            return Container(
              width: 4,
              height: height,
              margin: const EdgeInsets.only(right: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF5A2C62),
                borderRadius: BorderRadius.circular(4),
              ),
            );
          }),
        );
      },
    );
  }
}

class _PlaylistOptions extends StatelessWidget {
  const _PlaylistOptions({
    required this.playlists,
    required this.activePlaylist,
    required this.onSelected,
  });

  final List<AuraliaPlaylist> playlists;
  final AuraliaPlaylist activePlaylist;
  final ValueChanged<AuraliaPlaylist> onSelected;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(
        height: 146,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: playlists.length,
          separatorBuilder: (_, _) => const SizedBox(width: 10),
          itemBuilder: (context, index) {
            final playlist = playlists[index];
            final active = playlist.name == activePlaylist.name;
            final imageUrl = _playlistImage(playlist);
            return TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: 1),
              duration: Duration(milliseconds: 260 + index * 45),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) {
                return Opacity(
                  opacity: value,
                  child: Transform.translate(
                    offset: Offset(20 * (1 - value), 0),
                    child: child,
                  ),
                );
              },
              child: InkWell(
                onTap: () => onSelected(playlist),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  width: 205,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: active ? const Color(0xFF5A2C62) : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: active
                          ? const Color(0xFF5A2C62)
                          : const Color(0xFFE2D1DF),
                    ),
                  ),
                  child: Row(
                    children: [
                      _TrackImage(url: imageUrl, size: 72, radius: 12),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              playlist.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: active
                                    ? Colors.white
                                    : const Color(0xFF38143E),
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              '${playlist.tracks.length} tracks',
                              style: GoogleFonts.poppins(
                                fontSize: 10,
                                color: active ? Colors.white70 : Colors.black45,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SelectedPlaylistCard extends StatelessWidget {
  const _SelectedPlaylistCard({
    required this.playlist,
    required this.isSaved,
    required this.isBusy,
    required this.onSave,
    required this.onPlay,
  });

  final AuraliaPlaylist playlist;
  final bool isSaved;
  final bool isBusy;
  final VoidCallback onSave;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              playlist.name,
              style: GoogleFonts.poppins(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF38143E),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              playlist.summary,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                fontSize: 11,
                height: 1.35,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 13),
            ...playlist.tracks.take(4).map(
              (track) => Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: Row(
                  children: [
                    _TrackImage(
                      url: track.imageUrl,
                      size: 40,
                      radius: 9,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            track.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                              fontSize: 10,
                              color: Colors.black45,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (playlist.tracks.length > 4)
              Text(
                '+ ${playlist.tracks.length - 4} more tracks',
                style: GoogleFonts.poppins(
                  fontSize: 10,
                  color: Colors.black45,
                ),
              ),
            const SizedBox(height: 13),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: isBusy ? null : onSave,
                    icon: Icon(
                      isSaved
                          ? Icons.bookmark_rounded
                          : Icons.bookmark_border_rounded,
                    ),
                    label: Text(isSaved ? 'Saved' : 'Save'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onPlay,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF5A2C62),
                    ),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Play'),
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

enum _WellnessReset { breathe, ground, move, connect, journal, plan }

class _WellnessSuggestionSheet extends StatefulWidget {
  const _WellnessSuggestionSheet();

  @override
  State<_WellnessSuggestionSheet> createState() =>
      _WellnessSuggestionSheetState();
}

class _WellnessSuggestionSheetState
    extends State<_WellnessSuggestionSheet> {
  _WellnessReset _selected = _WellnessReset.breathe;
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

  void _selectReset(_WellnessReset reset) {
    _timer?.cancel();
    setState(() {
      _selected = reset;
      _timer = null;
      _breatheSeconds = 24;
      _moveSeconds = 30;
    });
  }

  void _startTimedReset() {
    _timer?.cancel();
    setState(() {
      if (_selected == _WellnessReset.breathe) {
        _breatheSeconds = 24;
      } else if (_selected == _WellnessReset.move) {
        _moveSeconds = 30;
      }
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_selected == _WellnessReset.breathe) {
          _breatheSeconds = (_breatheSeconds - 1).clamp(0, 24).toInt();
          if (_breatheSeconds == 0) {
            timer.cancel();
            _timer = null;
          }
        } else if (_selected == _WellnessReset.move) {
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
                  width: 42,
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
                    _ResetOption(
                      icon: Icons.air_rounded,
                      title: 'Breathe',
                      subtitle: '24 sec',
                      selected: _selected == _WellnessReset.breathe,
                      onTap: () => _selectReset(_WellnessReset.breathe),
                    ),
                    _ResetOption(
                      icon: Icons.spa_rounded,
                      title: 'Ground',
                      subtitle: '5 things',
                      selected: _selected == _WellnessReset.ground,
                      onTap: () => _selectReset(_WellnessReset.ground),
                    ),
                    _ResetOption(
                      icon: Icons.accessibility_new_rounded,
                      title: 'Move',
                      subtitle: '30 sec',
                      selected: _selected == _WellnessReset.move,
                      onTap: () => _selectReset(_WellnessReset.move),
                    ),
                    _ResetOption(
                      icon: Icons.people_outline_rounded,
                      title: 'Connect',
                      subtitle: 'Text one',
                      selected: _selected == _WellnessReset.connect,
                      onTap: () => _selectReset(_WellnessReset.connect),
                    ),
                    _ResetOption(
                      icon: Icons.edit_note_rounded,
                      title: 'Journal',
                      subtitle: '1 line',
                      selected: _selected == _WellnessReset.journal,
                      onTap: () => _selectReset(_WellnessReset.journal),
                    ),
                    _ResetOption(
                      icon: Icons.check_circle_outline_rounded,
                      title: 'Tiny step',
                      subtitle: 'One task',
                      selected: _selected == _WellnessReset.plan,
                      onTap: () => _selectReset(_WellnessReset.plan),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 240),
                child: _ResetPanel(
                  key: ValueKey(_selected),
                  reset: _selected,
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
                    'Continue to my playlists',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w800,
                    ),
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

class _ResetOption extends StatelessWidget {
  const _ResetOption({
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
      padding: const EdgeInsets.only(right: 9),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 170),
          width: 92,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF6E2D72) : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected
                  ? const Color(0xFF6E2D72)
                  : const Color(0xFFE8D8EA),
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

class _ResetPanel extends StatelessWidget {
  const _ResetPanel({
    super.key,
    required this.reset,
    required this.breatheSeconds,
    required this.breatheLabel,
    required this.moveSeconds,
    required this.moveLabel,
    required this.isTimerRunning,
    required this.onStartTimer,
  });

  final _WellnessReset reset;
  final int breatheSeconds;
  final String breatheLabel;
  final int moveSeconds;
  final String moveLabel;
  final bool isTimerRunning;
  final VoidCallback onStartTimer;

  @override
  Widget build(BuildContext context) {
    final content = switch (reset) {
      _WellnessReset.breathe => (
          Icons.air_rounded,
          'Try a soft breathing loop',
          'Inhale for 4 counts, hold for 2, then exhale for 6. Repeat this three times and let your shoulders drop.',
        ),
      _WellnessReset.ground => (
          Icons.spa_rounded,
          'Name what is around you',
          'Find 5 things you can see, 4 you can feel, 3 you can hear, 2 you can smell, and 1 thing you can taste.',
        ),
      _WellnessReset.move => (
          Icons.accessibility_new_rounded,
          'Loosen the body first',
          'Roll your shoulders, stretch your neck gently, and walk slowly for 30 seconds before choosing the next song.',
        ),
      _WellnessReset.connect => (
          Icons.people_outline_rounded,
          'Reach one safe person',
          'Send a simple message such as: I am having a low moment. Can you stay with me for a little while?',
        ),
      _WellnessReset.journal => (
          Icons.edit_note_rounded,
          'Write one honest line',
          'Try: Right now I feel..., and one thing I need is... Keep it short. It does not need to be perfect.',
        ),
      _WellnessReset.plan => (
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
                if (reset == _WellnessReset.breathe ||
                    reset == _WellnessReset.move) ...[
                  const SizedBox(height: 14),
                  _ResetTimerControl(
                    secondsRemaining: reset == _WellnessReset.breathe
                        ? breatheSeconds
                        : moveSeconds,
                    totalSeconds: reset == _WellnessReset.breathe ? 24 : 30,
                    label: reset == _WellnessReset.breathe
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
    if (reset == _WellnessReset.breathe) {
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

class _ChatComposer extends StatelessWidget {
  const _ChatComposer({
    required this.controller,
    required this.enabled,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFEAE1EB))),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              style: GoogleFonts.poppins(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Tell AURALIA how you feel...',
                hintStyle: GoogleFonts.poppins(
                  fontSize: 12,
                  color: Colors.black38,
                ),
                filled: true,
                fillColor: const Color(0xFFF5EFF6),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 11,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            tooltip: 'Send',
            onPressed: enabled ? onSend : null,
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFF5A2C62),
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.arrow_upward_rounded),
          ),
        ],
      ),
    );
  }
}

class _TrackImage extends StatelessWidget {
  const _TrackImage({required this.url, required this.size, required this.radius});

  final String? url;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: url == null || url!.isEmpty
            ? Container(
                color: const Color(0xFFE2D1DF),
                child: const Icon(
                  Icons.music_note_rounded,
                  color: Color(0xFF5A2C62),
                ),
              )
            : Image.network(
                url!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  color: const Color(0xFFE2D1DF),
                  child: const Icon(
                    Icons.music_note_rounded,
                    color: Color(0xFF5A2C62),
                  ),
                ),
              ),
      ),
    );
  }
}

class _ChatMessage {
  const _ChatMessage({
    required this.text,
    required this.isUser,
    this.isError = false,
  });

  final String text;
  final bool isUser;
  final bool isError;
}

class _MoodChipStyle {
  const _MoodChipStyle({
    required this.background,
    required this.border,
    required this.accent,
    required this.text,
  });

  final Color background;
  final Color border;
  final Color accent;
  final Color text;

  factory _MoodChipStyle.forMood(AuraliaMood mood) {
    return switch (mood) {
      AuraliaMood.sad => const _MoodChipStyle(
        background: Color(0xFFEFF2FF),
        border: Color(0xFFD5DBF6),
        accent: Color(0xFF5E76D6),
        text: Color(0xFF37466F),
      ),
      AuraliaMood.stressed => const _MoodChipStyle(
        background: Color(0xFFFFEFF2),
        border: Color(0xFFF3CDD4),
        accent: Color(0xFFD06674),
        text: Color(0xFF713B45),
      ),
      AuraliaMood.neutral => const _MoodChipStyle(
        background: Color(0xFFF3F1F4),
        border: Color(0xFFE1DCE4),
        accent: Color(0xFF8A838D),
        text: Color(0xFF514A55),
      ),
      AuraliaMood.happy => const _MoodChipStyle(
        background: Color(0xFFFFF7E6),
        border: Color(0xFFF1DFAE),
        accent: Color(0xFFDFAE35),
        text: Color(0xFF72581E),
      ),
      AuraliaMood.motivated => const _MoodChipStyle(
        background: Color(0xFFEEF8F1),
        border: Color(0xFFCFE8D7),
        accent: Color(0xFF4FA36C),
        text: Color(0xFF315D3E),
      ),
    };
  }
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

String? _playlistImage(AuraliaPlaylist playlist) {
  for (final track in playlist.tracks) {
    final image = track.imageUrl;
    if (image != null && image.isNotEmpty) {
      return image;
    }
  }
  return null;
}
