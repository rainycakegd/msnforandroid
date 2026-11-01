import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/firebase_service.dart';
import '../utils/constants.dart';

class NudgeController extends ChangeNotifier {
  int _shakeCount = 0;
  int get shakeCount => _shakeCount;

  void shake() {
    _shakeCount++;
    notifyListeners();
  }
}

class NudgeAnimation extends ConsumerStatefulWidget {
  final String peerId;
  final Widget child;
  final NudgeController controller;

  const NudgeAnimation({
    super.key,
    required this.peerId,
    required this.child,
    required this.controller,
  });

  @override
  ConsumerState<NudgeAnimation> createState() => _NudgeAnimationState();
}

class _NudgeAnimationState extends ConsumerState<NudgeAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _shakeAnimation;
  final AudioPlayer _audioPlayer = AudioPlayer();
  StreamSubscription<DateTime>? _nudgeSub;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: AppConstants.nudgeShakeDuration,
    );
    _shakeAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 15.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 15.0, end: -15.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -15.0, end: 15.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 15.0, end: -15.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -15.0, end: 0.0), weight: 1),
    ]).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );

    widget.controller.addListener(_onLocalShake);

    // Listen for incoming nudges using the REAL provider
    _nudgeSub = ref
        .read(firebaseServiceProvider)
        .incomingNudgeStream(widget.peerId)
        .listen((_) => _triggerShake());
  }

  void _onLocalShake() {
    _triggerShake();
  }

  void _triggerShake() {
    if (!mounted) return;
    _animController.forward(from: 0.0);
    _playSound();
  }

  Future<void> _playSound() async {
    try {
      await _audioPlayer.stop();
      await _audioPlayer.play(AssetSource(AppConstants.soundNudge));
    } catch (_) {
      // Ignore if sound file is missing.
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onLocalShake);
    _nudgeSub?.cancel();
    _animController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _shakeAnimation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(_shakeAnimation.value, 0),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}