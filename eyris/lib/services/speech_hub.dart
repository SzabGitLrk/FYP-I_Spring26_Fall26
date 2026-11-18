import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// How much a camera announcement matters while a route instruction is being
/// read out.
enum SpeechPriority {
  /// Something close or dangerous: interrupts a route instruction (which is
  /// repeated afterwards).
  urgent,

  /// Routine scene update: waits for the current sentence, spoken after it.
  normal,

  /// Nice to know ("Path clear"): skipped if anything is being spoken.
  low,
}

/// One shared voice for the whole app.
///
/// The camera (obstacle warnings) and the map (route instructions) both
/// speak, and run at the same time. On Android they share one text-to-speech
/// engine, so without coordination whichever spoke last cut the other off,
/// and the camera, which talks constantly, drowned out the directions.
///
///  * Route instructions are the default voice. Routine camera chatter
///    ([SpeechPriority.normal]) waits for an instruction to finish, and an
///    instruction cuts routine chatter off.
///  * A close obstacle ([SpeechPriority.urgent]) interrupts anything. An
///    instruction it cut off is spoken again once the warning is finished,
///    and an instruction that arrives during a warning waits for it.
///
/// Note: do not turn on `awaitSpeakCompletion` for the engine. In the
/// default flush mode the plugin then silently *drops* every speak() made
/// while something is being spoken. Sentence endings are tracked with the
/// completion callback instead.
class SpeechHub {
  SpeechHub._();
  static final SpeechHub instance = SpeechHub._();

  /// A sentence that has not reported completion after this long is treated
  /// as finished, so an engine that never reports back cannot hold up
  /// instructions forever.
  static const Duration _maxUtterance = Duration(seconds: 20);

  /// A completion callback this soon after a sentence started belongs to the
  /// sentence it replaced, not to the new one.
  @visibleForTesting
  static Duration minUtterance = const Duration(milliseconds: 250);

  final FlutterTts _tts = FlutterTts();
  bool _ready = false;

  int _seq = 0;
  _Utterance? _current;
  String? _waitingNavigation;
  String? _waitingDetection;

  /// Prepares the voice. Safe to call any number of times (setup is simply
  /// repeated until it has worked once); screens call it as they start so
  /// the first sentence is not delayed by setup.
  Future<void> ensureReady() async {
    if (_ready) return;
    try {
      _tts.setCompletionHandler(_onPlatformDone);
      _tts.setErrorHandler((_) => _onPlatformDone());
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.49);
      await _tts.setPitch(1.0);
      _ready = true;
    } catch (error) {
      debugPrint('[speech] init failed: $error');
    }
  }

  /// A camera announcement.
  Future<void> speakDetection(String text,
          {SpeechPriority priority = SpeechPriority.urgent}) =>
      _whenReady(() => _detection(text, priority));

  /// A route instruction.
  Future<void> speakNavigation(String text) =>
      _whenReady(() => _navigation(text));

  Future<void> _whenReady(void Function() action) {
    if (_ready) {
      action();
      return Future<void>.value();
    }
    return ensureReady().then((_) => action());
  }

  _Utterance? _freshCurrent() {
    final current = _current;
    if (current != null && current.isStale(_maxUtterance)) _current = null;
    return _current;
  }

  void _detection(String text, SpeechPriority priority) {
    if (text.trim().isEmpty) return;
    final current = _freshCurrent();
    switch (priority) {
      case SpeechPriority.urgent:
        if (current != null && current.isNavigation) {
          // Cut off: say the instruction again after the warning.
          _waitingNavigation = current.text;
        }
        _begin(text, _Kind.detection, priority);
      case SpeechPriority.normal:
        if (current == null) {
          _begin(text, _Kind.detection, priority);
        } else {
          _waitingDetection = text; // latest wins
        }
      case SpeechPriority.low:
        if (current == null) _begin(text, _Kind.detection, priority);
    }
  }

  void _navigation(String text) {
    if (text.trim().isEmpty) return;
    final current = _freshCurrent();
    if (current != null &&
        !current.isNavigation &&
        current.priority == SpeechPriority.urgent) {
      // A warning is being spoken: say the instruction right after it.
      _waitingNavigation = text;
      return;
    }
    // Nothing, an earlier instruction or routine chatter: the instruction
    // goes first. Chatter that was waiting is stale by now.
    _waitingNavigation = null;
    _waitingDetection = null;
    _begin(text, _Kind.navigation, SpeechPriority.normal);
  }

  void _begin(String text, _Kind kind, SpeechPriority priority) {
    final u = _Utterance(++_seq, text, kind, priority);
    _current = u;
    // Default queue mode: replaces whatever is being spoken right now.
    unawaited(_tts.speak(text).then<void>((_) {}, onError: (Object error) {
      debugPrint('[speech] speak failed: $error');
      if (_current?.id == u.id) _finished();
    }));
  }

  void _onPlatformDone() {
    final current = _current;
    if (current == null) return;
    if (DateTime.now().difference(current.startedAt) < minUtterance) return;
    _finished();
  }

  void _finished() {
    _current = null;
    final navigation = _waitingNavigation;
    if (navigation != null) {
      _waitingNavigation = null;
      _begin(navigation, _Kind.navigation, SpeechPriority.normal);
      return;
    }
    final detection = _waitingDetection;
    if (detection != null) {
      _waitingDetection = null;
      _begin(detection, _Kind.detection, SpeechPriority.normal);
    }
  }

  /// Stops camera speech only (the camera paused or closed); a route
  /// instruction keeps playing.
  Future<void> stopDetection() async {
    _waitingDetection = null;
    final current = _current;
    if (current == null || current.isNavigation) return;
    _current = null;
    await _stopEngine();
    _finished();
  }

  /// Stops route speech only; camera speech keeps playing.
  Future<void> stopNavigation() async {
    _waitingNavigation = null;
    final current = _current;
    if (current == null || !current.isNavigation) return;
    _current = null;
    await _stopEngine();
    _finished();
  }

  Future<void> _stopEngine() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }

  /// Forgets everything. Tests share the one hub, so they start clean.
  @visibleForTesting
  void resetForTest() {
    _ready = false;
    _current = null;
    _waitingNavigation = null;
    _waitingDetection = null;
    minUtterance = const Duration(milliseconds: 250);
  }
}

enum _Kind { detection, navigation }

class _Utterance {
  _Utterance(this.id, this.text, this.kind, this.priority)
      : startedAt = DateTime.now();
  final int id;
  final String text;
  final _Kind kind;
  final SpeechPriority priority;
  final DateTime startedAt;

  bool get isNavigation => kind == _Kind.navigation;
  bool isStale(Duration after) => DateTime.now().difference(startedAt) > after;
}
