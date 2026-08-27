/// A conversation with the assistant.
///
/// Held in memory for the life of the app rather than written to the database.
/// That is a decision, not an omission. This is for quick questions asked
/// standing at a machine — "can this go in the dryer", "what does that symbol
/// mean" — and the value of an answer is almost entirely in the next thirty
/// seconds. Persisting it would mean a schema migration, a place in sync, and
/// a permanent record on disk of everything somebody asked, in exchange for a
/// scrollback nobody re-reads.
///
/// What it does keep is the thread within a session, because follow-ups are
/// the whole point: "and the black one?" is a question that only means
/// anything with what came before it.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../core/providers.dart';
import '../../data/api/ai_gateway.dart';
import '../../data/api/scan_dto.dart';

/// One thing said, by either side.
final class ChatMessage {
  const ChatMessage({
    required this.fromUser,
    required this.text,
    this.failed = false,
  });

  final bool fromUser;
  final String text;

  /// Whether this is an error standing in for an answer.
  ///
  /// Kept in the transcript rather than shown as a banner, so a question that
  /// went unanswered stays visible next to the question it failed.
  final bool failed;
}

final class ChatState {
  const ChatState({this.messages = const [], this.waiting = false});

  final List<ChatMessage> messages;

  /// Whether an answer is on its way.
  final bool waiting;

  bool get isEmpty => messages.isEmpty;
}

class ChatController extends StateNotifier<ChatState> {
  ChatController(this._ref) : super(const ChatState());

  final Ref _ref;

  /// Asks a question and appends the answer.
  Future<void> ask(String question) async {
    final trimmed = question.trim();
    if (trimmed.isEmpty || state.waiting) return;

    // The history sent is what was on screen *before* this question, and only
    // the turns that succeeded: replaying "the server was unreachable" back to
    // the model as something it said would have it apologise for an outage it
    // knows nothing about.
    final history = [
      for (final message in state.messages)
        if (!message.failed) (fromUser: message.fromUser, text: message.text),
    ];

    state = ChatState(
      messages: [
        ...state.messages,
        ChatMessage(fromUser: true, text: trimmed),
      ],
      waiting: true,
    );

    String reply;
    var failed = false;
    try {
      reply = await _ref
          .read(aiGatewayProvider)
          .askQuestion(
            question: trimmed,
            wardrobe: await _wardrobe(),
            history: history,
          );
    } on ScanFailure catch (failure) {
      reply = failure.message;
      failed = true;
    } on ScanContractError {
      reply =
          'The server sent something this version cannot read. It may need '
          'updating.';
      failed = true;
    } on Exception {
      reply =
          'Could not reach the server. Check your connection and try again.';
      failed = true;
    }

    if (!mounted) return;
    state = ChatState(
      messages: [
        ...state.messages,
        ChatMessage(fromUser: false, text: reply, failed: failed),
      ],
      waiting: false,
    );
  }

  /// The garments the question may be about.
  ///
  /// Owned items only. A garment that has been donated or thrown away is not
  /// something anybody is standing over asking about, and including them would
  /// spend the wardrobe budget on clothes that no longer exist.
  Future<List<WardrobeItem>> _wardrobe() async {
    try {
      return await _ref.read(ownedItemsProvider.future);
    } on Exception {
      // A question that is not about the wardrobe — "what does the triangle
      // mean" — is answerable with no wardrobe at all, so a failure to read it
      // must not become a failure to answer.
      return const [];
    }
  }

  /// Starts again, throwing the thread away.
  void clear() => state = const ChatState();
}

final chatControllerProvider = StateNotifierProvider<ChatController, ChatState>(
  ChatController.new,
);
