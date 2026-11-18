import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

/// Extract JPEG frames across arbitrary HTTP chunk/multipart boundaries.
/// Bounds incomplete frames so a malformed camera response cannot grow forever.
class JpegFrameParser {
  JpegFrameParser({this.maxFrameBytes = 4 * 1024 * 1024})
      : _frame = Uint8List(maxFrameBytes);
  final int maxFrameBytes;
  final Uint8List _frame;
  int _length = 0;
  bool _inside = false;
  int _previous = -1;

  Iterable<Uint8List> add(List<int> chunk) sync* {
    for (final byte in chunk) {
      if (!_inside) {
        if (_previous == 0xff && byte == 0xd8) {
          _inside = true;
          _frame[0] = 0xff;
          _frame[1] = 0xd8;
          _length = 2;
        }
      } else {
        if (_length >= maxFrameBytes) {
          _length = 0;
          _inside = false;
          throw const FormatException('Camera frame exceeds the size limit.');
        }
        _frame[_length++] = byte;
        if (_previous == 0xff && byte == 0xd9) {
          _inside = false;
          yield Uint8List.fromList(_frame.sublist(0, _length));
          _length = 0;
        }
      }
      _previous = byte;
    }
  }
}

Future<void> _parseMjpegChunksInBackground(SendPort replyPort) async {
  final commands = ReceivePort();
  replyPort.send(commands.sendPort);
  final parser = JpegFrameParser();
  await for (final message in commands) {
    if (message == 'close') break;
    if (message is! TransferableTypedData) continue;
    try {
      final chunk = message.materialize().asUint8List();
      for (final frame in parser.add(chunk)) {
        replyPort.send(TransferableTypedData.fromList([frame]));
      }
    } catch (error) {
      replyPort.send(error.toString());
    }
  }
  commands.close();
}

/// One cancellable MJPEG connection. Closing it also aborts pending HTTP work.
class MjpegStream {
  MjpegStream({
    http.Client? client,
    this.connectionTimeout = const Duration(seconds: 8),
    this.frameTimeout = const Duration(seconds: 8),
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final Duration connectionTimeout;
  final Duration frameTimeout;
  StreamSubscription<List<int>>? _subscription;
  StreamSubscription<dynamic>? _workerSubscription;
  ReceivePort? _workerReplies;
  Isolate? _parserWorker;
  SendPort? _parserCommands;
  Timer? _watchdog;
  bool _closed = false;
  bool _started = false;

  Future<void> start(
    Uri uri, {
    required void Function(Uint8List) onFrame,
    required void Function(Object) onError,
  }) async {
    if (_closed || _started) return;
    _started = true;
    void fail(Object error) {
      if (_closed) return;
      close();
      onError(error);
    }

    void armWatchdog() {
      _watchdog?.cancel();
      _watchdog = Timer(frameTimeout,
          () => fail(TimeoutException('No complete camera frame received.')));
    }

    try {
      final request = http.Request('GET', uri)
        ..headers['Accept'] = 'multipart/x-mixed-replace'
        ..headers['Cache-Control'] = 'no-cache';
      final response = await _client.send(request).timeout(connectionTimeout);
      if (_closed) return;
      if (response.statusCode != 200) {
        throw http.ClientException(
            'Camera returned HTTP ${response.statusCode}.');
      }
      final contentType = response.headers['content-type']?.toLowerCase() ?? '';
      if (!contentType.contains('multipart/x-mixed-replace')) {
        throw const FormatException(
            'This address is not an MJPEG stream. Use port 81 and /stream.');
      }
      final replies = ReceivePort();
      _workerReplies = replies;
      final ready = Completer<SendPort>();
      _workerSubscription = replies.listen((message) {
        if (message is SendPort) {
          if (!ready.isCompleted) ready.complete(message);
        } else if (message is TransferableTypedData) {
          armWatchdog();
          onFrame(message.materialize().asUint8List());
        } else if (message is String) {
          fail(FormatException(message));
        }
      });
      _parserWorker = await Isolate.spawn(
          _parseMjpegChunksInBackground, replies.sendPort,
          debugName: 'mjpeg-frame-parser');
      _parserCommands = await ready.future.timeout(connectionTimeout);
      armWatchdog();
      _subscription = response.stream.listen((chunk) {
        if (_closed) return;
        _parserCommands?.send(
            TransferableTypedData.fromList([Uint8List.fromList(chunk)]));
      },
          onError: fail,
          onDone: () =>
              fail(http.ClientException('Camera stream disconnected.')));
    } catch (error) {
      fail(error);
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _watchdog?.cancel();
    _subscription?.cancel();
    _workerSubscription?.cancel();
    _parserCommands?.send('close');
    _parserWorker?.kill(priority: Isolate.immediate);
    _workerReplies?.close();
    _client.close();
  }
}
