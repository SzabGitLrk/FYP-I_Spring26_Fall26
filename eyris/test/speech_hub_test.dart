import 'package:eyris_app/services/speech_hub.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The camera warns about obstacles while navigation reads out directions
/// ("turn left", "turn right"), and both are active at once (for example with
/// the camera page open). They share one speaker, [SpeechHub]; these tests pin
/// down who may interrupt whom, and that directions are never lost.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final spoken = <String>[]; // texts handed to the speech engine, in order
  final engineCalls = <MethodCall>[];
  var stops = 0;

  setUp(() {
    SpeechHub.instance.resetForTest();
    SpeechHub.minUtterance = Duration.zero;
    spoken.clear();
    engineCalls.clear();
    stops = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_tts'),
            (call) async {
      engineCalls.add(call);
      if (call.method == 'speak') {
        // Android sends {text, focus}; other platforms send the bare string.
        final args = call.arguments;
        spoken.add(args is Map ? args['text'] as String : args as String);
      }
      if (call.method == 'stop') stops++;
      return 1;
    });
  });

  /// Lets queued microtasks run.
  Future<void> settle() async {
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }

  /// The engine reports that the sentence it was speaking has finished.
  Future<void> sentenceFinished() async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
            'flutter_tts',
            const StandardMethodCodec()
                .encodeMethodCall(const MethodCall('speak.onComplete', true)),
            (_) {});
    await settle();
  }

  final hub = SpeechHub.instance;

  test('regression: the engine is never told to wait for completion, which '
      'makes it silently drop speech said while it is busy', () async {
    await hub.speakNavigation('Turn left');
    await settle();
    final awaitCalls = engineCalls
        .where((c) => c.method == 'awaitSpeakCompletion')
        .where((c) => c.arguments == true);
    expect(awaitCalls, isEmpty);
  });

  test('a route instruction is spoken even though the camera has just spoken',
      () async {
    await hub.speakDetection('Chair ahead', priority: SpeechPriority.normal);
    await settle();
    await hub.speakNavigation('Turn left in 20 meters');
    await settle();
    // The instruction cuts routine camera chatter off and goes first.
    expect(spoken, ['Chair ahead', 'Turn left in 20 meters']);
  });

  test('an urgent warning interrupts a route instruction, which is repeated '
      'afterwards', () async {
    await hub.speakNavigation('Turn right in 50 meters');
    await settle();
    await hub.speakDetection('Pole ahead, about 1 meter',
        priority: SpeechPriority.urgent);
    await settle();
    expect(spoken, ['Turn right in 50 meters', 'Pole ahead, about 1 meter']);

    await sentenceFinished(); // the warning ends
    expect(spoken.last, 'Turn right in 50 meters');
    expect(spoken.length, 3);
  });

  test('a route instruction waits for an urgent warning instead of cutting '
      'it off', () async {
    await hub.speakDetection('Door straight ahead');
    await settle();
    await hub.speakNavigation('Continue straight');
    await settle();
    expect(spoken, ['Door straight ahead']);

    await sentenceFinished();
    expect(spoken, ['Door straight ahead', 'Continue straight']);
  });

  test('routine camera chatter waits for a route instruction to finish',
      () async {
    await hub.speakNavigation('Turn left');
    await settle();
    await hub.speakDetection('Person on the right',
        priority: SpeechPriority.normal);
    await settle();
    expect(spoken, ['Turn left'], reason: 'must not cut the instruction off');

    await sentenceFinished();
    expect(spoken, ['Turn left', 'Person on the right']);
  });

  test('"Path clear" is skipped while anything is being spoken', () async {
    await hub.speakNavigation('Turn left');
    await settle();
    await hub.speakDetection('Path clear', priority: SpeechPriority.low);
    await settle();
    await sentenceFinished();
    expect(spoken, ['Turn left']);

    await hub.speakDetection('Path clear', priority: SpeechPriority.low);
    await settle();
    expect(spoken, ['Turn left', 'Path clear']);
  });

  test('only the newest waiting instruction is spoken', () async {
    await hub.speakDetection('Person left');
    await settle();
    await hub.speakNavigation('Turn right');
    await hub.speakNavigation('Turn left');
    await settle();

    await sentenceFinished();
    expect(spoken, ['Person left', 'Turn left']);
  });

  test('directions keep coming while the camera talks continuously',
      () async {
    // The camera announces something new every moment; three route
    // instructions arrive among them. Every one must reach the speaker.
    final instructions = [
      'Turn left in 30 meters',
      'Turn right in 20 meters',
      'You have reached your destination',
    ];
    for (var i = 0; i < 6; i++) {
      await hub.speakDetection('Chair $i', priority: SpeechPriority.normal);
      await settle();
      if (i.isOdd) {
        await hub.speakNavigation(instructions[i ~/ 2]);
        await settle();
        await sentenceFinished();
      }
    }
    for (final instruction in instructions) {
      expect(spoken, contains(instruction));
    }
  });

  test('stopping the camera does not silence a route instruction', () async {
    await hub.speakNavigation('Arrive in 100 meters');
    await settle();

    await hub.stopDetection();
    expect(stops, 0);

    await hub.stopNavigation();
    expect(stops, 1);
  });

  test('stopping the camera cuts off its own warning', () async {
    await hub.speakDetection('Pole ahead');
    await settle();

    await hub.stopDetection();
    expect(stops, 1);
  });
}
