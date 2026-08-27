/// Asking the app a question.
///
/// Everything else here answers a question the app chose: what is this
/// garment, what goes with what, which loads to run. This is the one place the
/// user gets to ask their own, which is worth having because most laundry
/// questions are not ones a screen can anticipate — what the triangle with two
/// lines means, whether a jumper that says 30° can go at 40°, how much
/// detergent for half a drum.
///
/// It knows the wardrobe, so "can I tumble dry the navy jumper" works without
/// explaining what the navy jumper is. What it deliberately cannot do is
/// *change* anything: it has no way to add a garment, start a wash, or edit a
/// care label. An assistant that could act on a misread question is a much
/// worse thing to have than one that can only answer.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../widgets/app_drawer.dart';
import 'chat_controller.dart';

/// Openers, shown on an empty screen.
///
/// An empty chat box is a hard thing to start using — it asks you to guess
/// what it is for. These are the three shapes of question this can actually
/// answer, so the first one is a tap rather than a leap.
const _openers = [
  'What does the triangle symbol mean?',
  'How much detergent for a half load?',
  'Can I wash towels with bedding?',
];

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send([String? preset]) {
    final text = preset ?? _input.text;
    if (text.trim().isEmpty) return;
    _input.clear();
    ref.read(chatControllerProvider.notifier).ask(text);
    _toBottom();
  }

  /// Scrolls after the frame that adds the message, not before it.
  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatControllerProvider);
    ref.listen(chatControllerProvider, (_, _) => _toBottom());

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ask'),
        actions: [
          if (!state.isEmpty)
            IconButton(
              onPressed: ref.read(chatControllerProvider.notifier).clear,
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Clear',
            ),
        ],
      ),
      drawer: const AppDrawer(current: AppDestination.ask),
      body: Column(
        children: [
          Expanded(
            child: state.isEmpty
                ? _Empty(onPick: _send)
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(16),
                    itemCount: state.messages.length + (state.waiting ? 1 : 0),
                    itemBuilder: (context, index) =>
                        index < state.messages.length
                        ? _Bubble(message: state.messages[index])
                        : const _Thinking(),
                  ),
          ),
          _InputBar(controller: _input, enabled: !state.waiting, onSend: _send),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onPick});

  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 44,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text('Ask about laundry', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'It knows what is in your wardrobe, so you can ask about a '
              'garment by name. It cannot change anything — it only answers.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (final opener in _openers)
                  ActionChip(
                    label: Text(opener),
                    onPressed: () => onPick(opener),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mine = message.fromUser;

    final background = message.failed
        ? theme.colorScheme.errorContainer
        : mine
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surfaceContainerHighest;
    final foreground = message.failed
        ? theme.colorScheme.onErrorContainer
        : mine
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurface;

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          // Never the full width. A bubble that reaches both edges stops
          // reading as one side of a conversation.
          maxWidth: MediaQuery.sizeOf(context).width * 0.82,
        ),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(16),
        ),
        child: SelectableText(
          message.text,
          style: theme.textTheme.bodyMedium?.copyWith(color: foreground),
        ),
      ),
    );
  }
}

/// Three dots, while an answer is on its way.
class _Thinking extends StatelessWidget {
  const _Thinking();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.enabled,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          12,
          8,
          12,
          MediaQuery.viewInsetsOf(context).bottom > 0 ? 8 : 12,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                enabled: enabled,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: InputDecoration(
                  hintText: 'Ask a question',
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: enabled ? onSend : null,
              icon: const Icon(Icons.arrow_upward),
              tooltip: 'Send',
            ),
          ],
        ),
      ),
    );
  }
}
