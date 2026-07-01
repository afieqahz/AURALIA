import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:auralia_app/core/models/mood.dart';
import 'package:auralia_app/core/models/playlist.dart';
import 'package:auralia_app/core/services/auralia_scope.dart';
import 'package:auralia_app/core/services/auralia_state.dart';

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
    return switch (mood) {
      AuraliaMood.sad => const [
        'Oh, I am sorry you are feeling sad. Thank you for telling me.',
        'I will not rush you into happy songs right away. I will start with music that understands the heaviness first.',
        'Then I will gently guide the playlist toward something lighter, one step at a time.',
      ],
      AuraliaMood.stressed => const [
        'That sounds like a lot to carry. Let us slow things down for a moment.',
        'I will begin with tracks that reduce the pressure instead of adding more noise.',
        'After that, I will move toward calmer focus so your mind has room to breathe.',
      ],
      AuraliaMood.neutral => const [
        'Okay, I hear you. Neutral days can still need the right kind of support.',
        'I will keep the playlist steady at first, so it does not push your mood too suddenly.',
        'Then I will add a soft lift to help the rest of your day feel a little warmer.',
      ],
      AuraliaMood.happy => const [
        'I love that you are feeling happy. Let us keep that good feeling with you.',
        'I will choose songs that match your brightness without making the playlist feel too intense.',
        'Then I will build toward a playful finish so the mood stays alive.',
      ],
      AuraliaMood.motivated => const [
        'That is a strong place to start. I can feel the drive in that mood.',
        'I will match your energy with songs that keep you moving without distracting you.',
        'Then I will build momentum so the playlist supports focus and action.',
      ],
    };
  }

  List<String> _generationMessagesFor(AuraliaMood mood) {
    return switch (mood) {
      AuraliaMood.sad => const [
        'I am shaping the first songs to validate how you feel.',
        'Now I am looking for a gentle transition toward comfort.',
      ],
      AuraliaMood.stressed => const [
        'I am choosing a calmer starting point.',
        'Now I am arranging the next tracks to release tension slowly.',
      ],
      AuraliaMood.neutral => const [
        'I am keeping the opening balanced and easy.',
        'Now I am adding a light lift without changing the mood too sharply.',
      ],
      AuraliaMood.happy => const [
        'I am matching the playlist to your good mood.',
        'Now I am arranging the final tracks to keep that brightness going.',
      ],
      AuraliaMood.motivated => const [
        'I am matching your drive with steady energy.',
        'Now I am building a focused progression for the next tracks.',
      ],
    };
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
  _WellnessReset? _selected;
  Timer? _breathingTimer;
  int _secondsRemaining = 24;

  bool get _isBreathing =>
      _selected == _WellnessReset.breathe && _breathingTimer != null;

  String get _breathingLabel {
    if (_secondsRemaining == 0) {
      return 'Nice work. Take that calm with you.';
    }
    final elapsed = 24 - _secondsRemaining;
    return elapsed % 8 < 4 ? 'Breathe in slowly' : 'Breathe out gently';
  }

  @override
  void dispose() {
    _breathingTimer?.cancel();
    super.dispose();
  }

  void _selectReset(_WellnessReset reset) {
    _breathingTimer?.cancel();
    setState(() {
      _selected = reset;
      _breathingTimer = null;
      _secondsRemaining = 24;
    });
  }

  void _startBreathing() {
    _breathingTimer?.cancel();
    setState(() => _secondsRemaining = 24);
    _breathingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _secondsRemaining--);
      if (_secondsRemaining <= 0) {
        timer.cancel();
        setState(() => _breathingTimer = null);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
      decoration: const BoxDecoration(
        color: Color(0xFFF9F6FA),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
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
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8D8EA),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.favorite_rounded,
                  color: Color(0xFF6E2D72),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'A gentle check-in',
                style: GoogleFonts.poppins(
                  fontSize: 21,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF38143E),
                ),
              ),
              const SizedBox(height: 5),
              Text(
                'You have recorded three low moods in a row. That can happen, and you do not have to fix everything at once. Would one small reset feel useful?',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  height: 1.45,
                  color: Colors.black54,
                ),
              ),
              const SizedBox(height: 18),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _ResetOption(
                      icon: Icons.air_rounded,
                      label: 'Breathe',
                      selected: _selected == _WellnessReset.breathe,
                      onTap: () => _selectReset(_WellnessReset.breathe),
                    ),
                    _ResetOption(
                      icon: Icons.spa_rounded,
                      label: 'Ground',
                      selected: _selected == _WellnessReset.ground,
                      onTap: () => _selectReset(_WellnessReset.ground),
                    ),
                    _ResetOption(
                      icon: Icons.accessibility_new_rounded,
                      label: 'Move',
                      selected: _selected == _WellnessReset.move,
                      onTap: () => _selectReset(_WellnessReset.move),
                    ),
                    _ResetOption(
                      icon: Icons.people_outline_rounded,
                      label: 'Connect',
                      selected: _selected == _WellnessReset.connect,
                      onTap: () => _selectReset(_WellnessReset.connect),
                    ),
                    _ResetOption(
                      icon: Icons.edit_note_rounded,
                      label: 'Journal',
                      selected: _selected == _WellnessReset.journal,
                      onTap: () => _selectReset(_WellnessReset.journal),
                    ),
                    _ResetOption(
                      icon: Icons.check_circle_outline_rounded,
                      label: 'One step',
                      selected: _selected == _WellnessReset.plan,
                      onTap: () => _selectReset(_WellnessReset.plan),
                    ),
                  ],
                ),
              ),
              if (_selected != null) ...[
                const SizedBox(height: 16),
                _selectedResetPanel(),
              ],
              const SizedBox(height: 16),
              Text(
                'AURALIA supports wellbeing but cannot diagnose or replace professional care. If you feel unsafe or overwhelmed, contact someone you trust or local emergency support.',
                style: GoogleFonts.poppins(
                  fontSize: 10,
                  height: 1.4,
                  color: Colors.black45,
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    'Continue to my playlists',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF5A2C62),
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

  Widget _selectedResetPanel() {
    switch (_selected!) {
      case _WellnessReset.breathe:
        final progress = (24 - _secondsRemaining) / 24;
        return _ResetPanel(
          child: Column(
            children: [
              SizedBox(
                width: 78,
                height: 78,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: _isBreathing || _secondsRemaining == 0
                          ? progress
                          : 0,
                      strokeWidth: 6,
                      backgroundColor: const Color(0xFFE4D9E5),
                      color: const Color(0xFF6E2D72),
                    ),
                    Icon(
                      _secondsRemaining == 0
                          ? Icons.check_rounded
                          : Icons.air_rounded,
                      color: const Color(0xFF5A2C62),
                      size: 30,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _breathingLabel,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF38143E),
                ),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: _isBreathing ? null : _startBreathing,
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(
                  _secondsRemaining == 0 ? 'Do it again' : 'Start 24 seconds',
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF5A2C62),
                ),
              ),
            ],
          ),
        );
      case _WellnessReset.ground:
        return const _ResetPanel(
          child: _ResetSteps(
            icon: Icons.spa_rounded,
            title: '5-4-3-2-1 grounding',
            intro: 'Use your senses to bring your attention back to now.',
            steps: [
              'Name 5 things you can see.',
              'Name 4 things you can feel.',
              'Name 3 things you can hear.',
              'Name 2 things you can smell.',
              'Name 1 kind thing you can say to yourself.',
            ],
          ),
        );
      case _WellnessReset.move:
        return const _ResetPanel(
          child: _ResetSteps(
            icon: Icons.directions_walk_rounded,
            title: 'Two-minute body reset',
            intro:
                'A tiny movement can lower tension without needing a full workout.',
            steps: [
              'Drop your shoulders and unclench your jaw.',
              'Stretch your hands, neck, or back gently.',
              'Walk to get water, then come back slowly.',
            ],
          ),
        );
      case _WellnessReset.connect:
        return const _ResetPanel(
          child: _ResetCopy(
            icon: Icons.chat_bubble_outline_rounded,
            title: 'Send one simple message',
            text:
                'Try: "I have had a difficult few days. Could we talk for a little while?" You do not need to explain everything at once.',
          ),
        );
      case _WellnessReset.journal:
        return const _ResetPanel(
          child: _ResetSteps(
            icon: Icons.edit_note_rounded,
            title: 'Three-line journal',
            intro: 'Write it small. The goal is clarity, not perfect words.',
            steps: [
              'Right now I feel...',
              'The hardest part is...',
              'One thing I need next is...',
            ],
          ),
        );
      case _WellnessReset.plan:
        return const _ResetPanel(
          child: _ResetSteps(
            icon: Icons.check_circle_outline_rounded,
            title: 'Choose one gentle step',
            intro: 'Pick only one. Small counts.',
            steps: [
              'Drink water or eat something light.',
              'Take a shower or change clothes.',
              'Open a window or tidy one tiny area.',
              'Save one playlist for later and rest.',
            ],
          ),
        );
    }
  }
}

class _ResetOption extends StatelessWidget {
  const _ResetOption({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 9),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 170),
          width: 86,
          height: 72,
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF5A2C62) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? const Color(0xFF5A2C62)
                  : const Color(0xFFE3D9E4),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: selected ? Colors.white : const Color(0xFF5A2C62),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : const Color(0xFF38143E),
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
  const _ResetPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8DFE9)),
      ),
      child: child,
    );
  }
}

class _ResetCopy extends StatelessWidget {
  const _ResetCopy({
    required this.icon,
    required this.title,
    required this.text,
  });

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: const Color(0xFF6E2D72)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF38143E),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                text,
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  height: 1.45,
                  color: Colors.black54,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ResetSteps extends StatelessWidget {
  const _ResetSteps({
    required this.icon,
    required this.title,
    required this.intro,
    required this.steps,
  });

  final IconData icon;
  final String title;
  final String intro;
  final List<String> steps;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ResetCopy(icon: icon, title: title, text: intro),
        const SizedBox(height: 12),
        ...List.generate(steps.length, (index) {
          return Padding(
            padding: EdgeInsets.only(top: index == 0 ? 0 : 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEDE4EE),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${index + 1}',
                    style: GoogleFonts.poppins(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF5A2C62),
                    ),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    steps[index],
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      height: 1.35,
                      color: Colors.black54,
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
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
