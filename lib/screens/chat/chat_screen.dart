// lib/screens/chat/chat_screen.dart
import 'dart:async';
import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../services/firebase_service.dart';
import '../../theme/aero_theme.dart';
import '../../utils/constants.dart';
import '../../widgets/emoticon_parser.dart';
import '../../widgets/nudge_animation.dart';
import '../buddy_list/buddy_list_screen.dart'
    show blockedIdsProvider, contactsServiceProvider;

class ChatScreen extends ConsumerStatefulWidget {
  final String peerId;
  final String peerName;

  const ChatScreen({
    super.key,
    required this.peerId,
    required this.peerName,
  });

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final NudgeController _nudgeController = NudgeController();

  late final FirebaseService _service;

  Timer? _typingTimer;
  bool _isTyping = false;
  DateTime _lastTypingSent = DateTime.fromMillisecondsSinceEpoch(0);

  bool _showEmoticons = false;
  bool _markingRead = false;
  bool _nudgeBusy = false;

  @override
  void initState() {
    super.initState();
    _service = ref.read(firebaseServiceProvider);
    _controller.addListener(_onTextChanged);
    _focusNode.addListener(() {
      if (_focusNode.hasFocus && _showEmoticons && mounted) {
        setState(() => _showEmoticons = false);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _service.markMessagesRead(widget.peerId).catchError((_) {});
    });
  }

  @override
  void dispose() {
    _stopTyping();
    _typingTimer?.cancel();
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Typing indicator
  // ---------------------------------------------------------------------------

  void _onTextChanged() {
    final hasText = _controller.text.trim().isNotEmpty;
    if (!hasText) {
      _stopTyping();
      return;
    }

    final now = DateTime.now();
    if (!_isTyping ||
        now.difference(_lastTypingSent) > const Duration(seconds: 2)) {
      _isTyping = true;
      _lastTypingSent = now;
      _service.setTyping(widget.peerId, true).catchError((_) {});
    }

    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 3), _stopTyping);
  }

  void _stopTyping() {
    _typingTimer?.cancel();
    if (_isTyping) {
      _isTyping = false;
      _service.setTyping(widget.peerId, false).catchError((_) {});
    }
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    _typingTimer?.cancel();
    _isTyping = false;
    _controller.clear();

    try {
      await _service.sendMessage(peerId: widget.peerId, text: text);
    } catch (_) {
      if (!mounted) return;
      _controller.text = text;
      _controller.selection = TextSelection.collapsed(offset: text.length);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Message could not be sent.')),
      );
    }
  }

  Future<void> _nudge() async {
    if (_nudgeBusy) return;
    _nudgeBusy = true;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final sent = await _service
          .sendNudge(widget.peerId)
          .timeout(const Duration(seconds: 5), onTimeout: () => true);
      if (!mounted) return;
      if (sent) {
        _nudgeController.shake();
      } else {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Please wait a moment before nudging again.'),
          ),
        );
      }
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not send the nudge.')),
      );
    } finally {
      _nudgeBusy = false;
    }
  }

  void _toggleEmoticons() {
    if (_showEmoticons) {
      setState(() => _showEmoticons = false);
      _focusNode.requestFocus();
    } else {
      _focusNode.unfocus();
      setState(() => _showEmoticons = true);
    }
  }

  void _insertEmoticon(String shortcut) {
    final text = _controller.text;
    final selection = _controller.selection;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    final insert = '$shortcut ';
    final newText = text.replaceRange(start, end, insert);
    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + insert.length),
    );
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final palette = ref.watch(aeroPaletteProvider);
    final peer = ref.watch(userProfileProvider(widget.peerId)).valueOrNull;
    final messagesAsync = ref.watch(messagesProvider(widget.peerId));
    final peerTyping =
        ref.watch(peerTypingProvider(widget.peerId)).valueOrNull ?? false;
    final blocked =
        (ref.watch(blockedIdsProvider).valueOrNull ?? const <String>[])
            .contains(widget.peerId);
    final me = _service.currentUser?.uid ?? '';
    final peerName = peer?.displayName ?? widget.peerName;

    ref.listen<AsyncValue<List<ChatMessage>>>(
      messagesProvider(widget.peerId),
      (previous, next) {
        final list = next.valueOrNull;
        if (list == null) return;
        final hasUnread = list.any(
          (m) =>
              m.senderId == widget.peerId &&
              !m.readBy.contains(me) &&
              !m.pending,
        );
        if (hasUnread && !_markingRead) {
          _markingRead = true;
          _service
              .markMessagesRead(widget.peerId)
              .catchError((_) {})
              .whenComplete(() => _markingRead = false);
        }
      },
    );

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(gradient: palette.backgroundGradient),
        child: NudgeAnimation(
          peerId: widget.peerId,
          controller: _nudgeController,
          child: Column(
            children: <Widget>[
              _buildHeader(palette, peer, peerName, blocked),
              Expanded(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                  decoration: AeroDecorations.glassPanel(palette, radius: 22),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: _buildMessages(palette, messagesAsync, me, peerName),
                  ),
                ),
              ),
              if (peerTyping) _buildTypingIndicator(palette, peerName),
              if (blocked)
                _buildBlockedBanner(peerName)
              else
                _buildInputBar(palette),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(
    AeroPalette palette,
    AppUser? peer,
    String peerName,
    bool blocked,
  ) {
    final top = MediaQuery.of(context).padding.top;
    final status = peer?.status ?? UserStatus.offline;
    final subtitle = (peer?.statusMessage.isNotEmpty ?? false)
        ? peer!.statusMessage
        : status.label;
    final nowPlaying = peer?.nowPlaying ?? '';

    return Container(
      padding: EdgeInsets.fromLTRB(8, top + 10, 12, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            palette.primaryDark,
            Color.lerp(palette.primaryDark, palette.primaryLight, 0.45)!,
          ],
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(26)),
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.8), width: 1.5),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: palette.primaryDark.withOpacity(0.5),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(26)),
        child: Stack(
          children: <Widget>[
            Positioned(
              top: -top - 10,
              left: -8,
              right: -12,
              height: top + 52,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      Colors.white.withOpacity(0.28),
                      Colors.white.withOpacity(0.0),
                    ],
                  ),
                ),
              ),
            ),
            Row(
              children: <Widget>[
                IconButton(
                  icon: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                _ChatAvatar(
                  name: peerName,
                  url: peer?.avatarUrl,
                  size: 48,
                  status: status,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        peerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AeroTextStyles.title.copyWith(fontSize: 18),
                      ),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AeroTextStyles.statusMessage.copyWith(
                          color: Colors.white.withOpacity(0.92),
                        ),
                      ),
                      if (nowPlaying.isNotEmpty)
                        Row(
                          children: <Widget>[
                            const Icon(
                              Icons.music_note_rounded,
                              size: 13,
                              color: Color(0xFFB8F5A8),
                            ),
                            const SizedBox(width: 2),
                            Expanded(
                              child: Text(
                                nowPlaying,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AeroTextStyles.nowPlaying.copyWith(
                                  color: const Color(0xFFB8F5A8),
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: 'Send a nudge',
                  child: GestureDetector(
                    onTap: blocked ? null : _nudge,
                    child: Opacity(
                      opacity: blocked ? 0.5 : 1.0,
                      child: Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: <Color>[
                              Color(0xFFFFE0B8),
                              Color(0xFFFFB05C),
                              AeroColors.busy,
                              Color(0xFFFF9442),
                            ],
                            stops: <double>[0.0, 0.49, 0.5, 1.0],
                          ),
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                              color: AeroColors.busy.withOpacity(0.55),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.vibration_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
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

  Widget _buildMessages(
    AeroPalette palette,
    AsyncValue<List<ChatMessage>> messagesAsync,
    String me,
    String peerName,
  ) {
    return messagesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Could not load messages.',
            style: AeroTextStyles.statusMessage,
          ),
        ),
      ),
      data: (messages) {
        if (messages.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    Icons.chat_bubble_outline_rounded,
                    size: 60,
                    color: palette.primaryDark.withOpacity(0.5),
                  ),
                  const SizedBox(height: 12),
                  Text('Say hi to $peerName!', style: AeroTextStyles.heading),
                  const SizedBox(height: 6),
                  Text(
                    'Your conversation will show up here.',
                    style: AeroTextStyles.statusMessage,
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.builder(
          reverse: true,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          itemCount: messages.length,
          itemBuilder: (context, index) {
            final message = messages[index];
            final older =
                index + 1 < messages.length ? messages[index + 1] : null;
            final showDate =
                older == null || !_sameDay(older.createdAt, message.createdAt);
            final mine = message.senderId == me;

            final Widget item = message.type == MessageType.nudge
                ? _NudgeNotice(
                    text: mine
                        ? 'You sent a nudge!'
                        : '$peerName sent you a nudge!',
                  )
                : _MessageBubble(
                    palette: palette,
                    message: message,
                    mine: mine,
                    read: message.readBy.contains(widget.peerId),
                  );

            return Column(
              children: <Widget>[
                if (showDate) _DateChip(date: message.createdAt),
                item,
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildTypingIndicator(AeroPalette palette, String peerName) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 2, 22, 4),
      child: Row(
        children: <Widget>[
          _TypingDots(color: palette.primaryDark),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              '$peerName is typing...',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AeroTextStyles.typing,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBlockedBanner(String peerName) {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[Color(0xFFFFE3E3), Color(0xFFFFBFBF)],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AeroColors.error.withOpacity(0.6)),
        ),
        child: Row(
          children: <Widget>[
            const Icon(Icons.block_rounded, color: AeroColors.error),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'You have blocked $peerName.',
                style: AeroTextStyles.body.copyWith(
                  color: const Color(0xFF7A1E1E),
                  fontSize: 13,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                ref
                    .read(contactsServiceProvider)
                    .unblockUser(widget.peerId)
                    .catchError((_) {});
              },
              child: const Text('Unblock'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar(AeroPalette palette) {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        decoration: AeroDecorations.glassPanel(palette, radius: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              child: _showEmoticons
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(10, 10, 10, 2),
                      child: EmoticonPicker(onSelected: _insertEmoticon),
                    )
                  : const SizedBox(width: double.infinity),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  GestureDetector(
                    onTap: _toggleEmoticons,
                    child: Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: <Color>[
                            Colors.white,
                            palette.primaryLight.withOpacity(0.7),
                          ],
                        ),
                        border: Border.all(
                          color: _showEmoticons
                              ? palette.accent
                              : Colors.white,
                          width: 2,
                        ),
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: palette.primaryDark.withOpacity(0.3),
                            blurRadius: 6,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const EmoticonImage(file: 'smile.png', size: 26),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      minLines: 1,
                      maxLines: 4,
                      keyboardType: TextInputType.multiline,
                      textCapitalization: TextCapitalization.sentences,
                      style: AeroTextStyles.body,
                      decoration: InputDecoration(
                        hintText: 'Type a message…',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: BorderSide(
                            color: palette.primaryDark.withOpacity(0.35),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: BorderSide(
                            color: palette.primaryDark.withOpacity(0.35),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide:
                              BorderSide(color: palette.accent, width: 2),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _controller,
                    builder: (context, value, _) {
                      final enabled = value.text.trim().isNotEmpty;
                      return GestureDetector(
                        onTap: enabled ? _send : null,
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 150),
                          opacity: enabled ? 1.0 : 0.5,
                          child: Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: palette.glossGradient,
                              border:
                                  Border.all(color: Colors.white, width: 2),
                              boxShadow: <BoxShadow>[
                                BoxShadow(
                                  color:
                                      palette.primaryDark.withOpacity(0.5),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.send_rounded,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Message widgets
// -----------------------------------------------------------------------------

class _MessageBubble extends StatelessWidget {
  final AeroPalette palette;
  final ChatMessage message;
  final bool mine;
  final bool read;

  const _MessageBubble({
    required this.palette,
    required this.message,
    required this.mine,
    required this.read,
  });

  @override
  Widget build(BuildContext context) {
    final maxWidth = MediaQuery.of(context).size.width * 0.78;
    final time = DateFormat('HH:mm').format(message.createdAt);

    IconData receiptIcon;
    String receiptLabel;
    Color receiptColor;
    if (message.pending) {
      receiptIcon = Icons.schedule_rounded;
      receiptLabel = 'Sending…';
      receiptColor = AeroColors.textMuted;
    } else if (read) {
      receiptIcon = Icons.done_all_rounded;
      receiptLabel = 'Read';
      receiptColor = AeroColors.msnBlueMid;
    } else {
      receiptIcon = Icons.done_rounded;
      receiptLabel = 'Sent';
      receiptColor = AeroColors.textMuted;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Column(
            crossAxisAlignment:
                mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: AeroDecorations.bubble(palette, mine: mine),
                child: EmoticonText(
                  text: message.text,
                  style: AeroTextStyles.chatMessage,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 3, 6, 0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(time, style: AeroTextStyles.timestamp),
                    if (mine) ...<Widget>[
                      const SizedBox(width: 6),
                      Icon(receiptIcon, size: 13, color: receiptColor),
                      const SizedBox(width: 2),
                      Text(
                        receiptLabel,
                        style: AeroTextStyles.timestamp
                            .copyWith(color: receiptColor),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NudgeNotice extends StatelessWidget {
  final String text;

  const _NudgeNotice({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[Color(0xFFFFF1DC), Color(0xFFFFD9A8)],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AeroColors.busy.withOpacity(0.6)),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: AeroColors.busy.withOpacity(0.2),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                Icons.vibration_rounded,
                size: 16,
                color: AeroColors.busy,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  text,
                  style: AeroTextStyles.bodyBold.copyWith(
                    fontSize: 12,
                    color: const Color(0xFF8A4300),
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

class _DateChip extends StatelessWidget {
  final DateTime date;

  const _DateChip({required this.date});

  String _label() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return DateFormat('EEE, MMM d').format(date);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: AeroColors.msnBlueDark.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            _label(),
            style: AeroTextStyles.timestamp.copyWith(
              fontWeight: FontWeight.w600,
              color: AeroColors.msnBlueDark,
            ),
          ),
        ),
      ),
    );
  }
}

class _TypingDots extends StatefulWidget {
  final Color color;

  const _TypingDots({required this.color});

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List<Widget>.generate(3, (i) {
            final phase = (_anim.value - i * 0.18) % 1.0;
            final v = (sin(phase * 2 * pi) + 1) / 2;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color.withOpacity(0.3 + 0.7 * v),
              ),
            );
          }),
        );
      },
    );
  }
}

class _ChatAvatar extends StatelessWidget {
  final String name;
  final String? url;
  final double size;
  final UserStatus status;

  const _ChatAvatar({
    required this.name,
    required this.size,
    required this.status,
    this.url,
  });

  Widget _initial() {
    final letter = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return Container(
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[AeroColors.msnBlueLight, AeroColors.msnBlueDark],
        ),
      ),
      child: Text(
        letter,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.45,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasUrl = url != null && url!.isNotEmpty;
    final orb = size * 0.34;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              border: Border.all(color: status.color, width: 2.5),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: status.color.withOpacity(0.4),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: ClipOval(
              child: hasUrl
                  ? CachedNetworkImage(
                      imageUrl: url!,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => _initial(),
                      errorWidget: (_, __, ___) => _initial(),
                    )
                  : _initial(),
            ),
          ),
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: orb,
              height: orb,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  center: const Alignment(-0.35, -0.45),
                  radius: 0.95,
                  colors: <Color>[
                    Colors.white,
                    status.highlightColor,
                    status.color,
                  ],
                  stops: const <double>[0.0, 0.3, 1.0],
                ),
                border: Border.all(color: Colors.white, width: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
