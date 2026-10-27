import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavely/design_system/design_system.dart';
import 'package:wavely/features/ai_chat/ai_chat_providers.dart';
import 'package:wavely/features/ai_chat/data/ai_service.dart';
import 'package:wavely/features/ai_chat/data/mood_classifier.dart';
import 'package:wavely/features/library/data/track_launcher.dart';

/// One rendered chat row.
class _ChatEntry {
  const _ChatEntry({
    required this.isUser,
    required this.text,
    this.isError = false,
    this.queue,
  });

  final bool isUser;
  final String text;
  final bool isError;
  final QueueBuildSummary? queue;
}

/// Full-screen AI chat sheet (route '/ai-chat', registered by the
/// orchestrator — do not push it via showModalBottomSheet manually).
///
/// Styling: solid [WavelySemanticColors] surfaces only — deliberately NO
/// GlassCard, so the chat stays readable while the player runs behind it.
class AiChatScreen extends ConsumerStatefulWidget {
  const AiChatScreen({super.key});

  static const String route = '/ai-chat';

  @override
  ConsumerState<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends ConsumerState<AiChatScreen> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<_ChatEntry> _entries = <_ChatEntry>[];
  Mood? _selectedMood;
  bool _sending = false;
  int _dots = 0;
  int _generation = 0;
  Timer? _dotTimer;

  void _startDots() {
    _dotTimer?.cancel();
    _dots = 0;
    _dotTimer = Timer.periodic(const Duration(milliseconds: 400), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _dots = (_dots + 1) % 4);
    });
  }

  void _stopDots() {
    _dotTimer?.cancel();
    _dotTimer = null;
  }

  Future<void> _send(String text) async {
    final service = ref.read(aiServiceProvider);
    final trimmed = text.trim();
    if (service == null || trimmed.isEmpty || _sending) {
      return;
    }
    final mood = _selectedMood == null
        ? null
        : MoodResult(mood: _selectedMood);
    final request = ++_generation;
    setState(() {
      _entries.add(_ChatEntry(isUser: true, text: trimmed));
      _sending = true;
    });
    _input.clear();
    _startDots();
    _scrollToEnd();
    final result = await service.send(trimmed, mood: mood);
    if (!mounted || request != _generation) {
      return; // cancelled or screen disposed while awaiting
    }
    _stopDots();
    setState(() {
      _sending = false;
      result.fold(
        onErr: (failure) => _entries.add(
          _ChatEntry(isUser: false, text: failure.message, isError: true),
        ),
        onSuccess: (outcome) {
          for (final line in outcome.transcriptLines) {
            if (line.trim().isEmpty) {
              continue;
            }
            _entries.add(_ChatEntry(isUser: false, text: line));
          }
          final queue = outcome.queueBuilt;
          if (queue != null && _entries.isNotEmpty) {
            final last = _entries.removeLast();
            _entries.add(
              _ChatEntry(
                isUser: false,
                text: last.text,
                queue: queue,
              ),
            );
          }
        },
      );
    });
    _scrollToEnd();
  }

  void _cancel() {
    _generation++;
    _stopDots();
    setState(() {
      _sending = false;
      _entries.add(
        const _ChatEntry(isUser: false, text: 'Request cancelled.'),
      );
    });
  }

  void _regenerate() {
    for (var i = _entries.length - 1; i >= 0; i--) {
      if (_entries[i].isUser) {
        final text = _entries[i].text;
        setState(() {
          // Drop everything after (and including) the last assistant reply
          // block, keep the user's question.
          while (_entries.length > i + 1) {
            _entries.removeLast();
          }
        });
        _send(text);
        return;
      }
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _playAll(QueueBuildSummary queue) async {
    try {
      await ref.read(trackLauncherProvider).playTracks(queue.tracks);
    } on UnimplementedError {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Playback is not wired up yet.')),
        );
      }
    }
  }

  @override
  void dispose() {
    _stopDots();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.wavelyColors;
    final service = ref.watch(aiServiceProvider);
    final disabled = service == null;
    return Scaffold(
      backgroundColor: colors.bgBase,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'Ask Wavely AI',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  if (_sending)
                    TextButton(onPressed: _cancel, child: const Text('Cancel')),
                ],
              ),
            ),
            if (!disabled) _buildMoodChips(colors),
            Expanded(
              child: disabled
                  ? _buildDisabled(colors)
                  : _buildMessageList(colors),
            ),
            if (!disabled) _buildInputRow(colors),
          ],
        ),
      ),
    );
  }

  Widget _buildMoodChips(WavelySemanticColors colors) => SizedBox(
        height: 48,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          children: <Widget>[
            for (final mood in Mood.values)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(mood.label),
                  selected: _selectedMood == mood,
                  selectedColor: colors.accentColors.accent,
                  onSelected: (selected) =>
                      setState(() => _selectedMood = selected ? mood : null),
                ),
              ),
          ],
        ),
      );

  Widget _buildDisabled(WavelySemanticColors colors) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const EmptyState(
                icon: Icons.auto_awesome_outlined,
                title: 'AI chat is not set up yet',
                subtitle: 'Add an API key to unlock library-aware chat, '
                    'mood queues and listening stats.',
              ),
              const SizedBox(height: 16),
              Text(
                'Run the app with:\n'
                'flutter run --dart-define-from-file=.env\n\n'
                'Keys expected in .env:\n'
                'GEMINI_API_KEY=... (preferred)\n'
                'OPENAI_API_KEY=... (fallback)',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.textSecondary,
                    ),
              ),
            ],
          ),
        ),
      );

  Widget _buildMessageList(WavelySemanticColors colors) {
    if (_entries.isEmpty && !_sending) {
      return Center(
        child: Text(
          'Ask about your library, request a mood queue or your '
          'listening stats.',
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: colors.textSecondary),
        ),
      );
    }
    return SingleChildScrollView(
      controller: _scroll,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final entry in _entries) _buildEntry(entry, colors),
          if (_sending) _buildTypingIndicator(colors),
        ],
      ),
    );
  }

  Widget _buildEntry(_ChatEntry entry, WavelySemanticColors colors) {
    final bubbleColor = entry.isUser
        ? colors.accentColors.accent.withValues(alpha: 0.16)
        : entry.isError
            ? colors.error.withValues(alpha: 0.12)
            : colors.elevated;
    return Align(
      alignment: entry.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 480),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            MarkdownBody(
              data: entry.text,
              styleSheet: MarkdownStyleSheet(
                p: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: colors.textPrimary),
              ),
            ),
            if (entry.queue != null) ...<Widget>[
              const SizedBox(height: 8),
              Chip(
                avatar: const Icon(Icons.queue_music, size: 18),
                label: Text('Queued ${entry.queue!.queued} tracks'),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  TextButton.icon(
                    onPressed: () => _playAll(entry.queue!),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Play all'),
                  ),
                  TextButton(
                    onPressed: _sending ? null : _regenerate,
                    child: const Text('Regenerate'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTypingIndicator(WavelySemanticColors colors) => Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: colors.elevated,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            'Assistant is typing${'.' * _dots}',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: colors.textSecondary),
          ),
        ),
      );

  Widget _buildInputRow(WavelySemanticColors colors) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: _input,
                enabled: !_sending,
                textInputAction: TextInputAction.send,
                onSubmitted: _send,
                style: TextStyle(color: colors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Ask for music, moods or stats…',
                  filled: true,
                  fillColor: colors.elevated,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _sending ? null : () => _send(_input.text),
              icon: const Icon(Icons.send),
            ),
          ],
        ),
      );
}
