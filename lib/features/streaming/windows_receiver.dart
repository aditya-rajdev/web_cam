import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../core/protocol/shared_protocol.dart';
import '../virtual_camera/virtual_camera_ffi.dart';

typedef OnReceiverFrameAvailable = void Function(Uint8List frameBytes, int width, int height, int latencyMs);
typedef OnReceiverStateChanged = void Function(bool isConnected, String message, String? errorType);

class ReceiverStats {
  double fps = 0.0;
  double throughputMbps = 0.0;
  int latencyMs = 0;
  int framesReceived = 0;
  int bytesReceived = 0;
  int decodeErrors = 0;
}

class WindowsReceiver {
  WebSocketChannel? _channel;
  bool _isConnected = false;
  String _currentIp = '';

  int _frameCountInSecond = 0;
  int _bytesInSecond = 0;
  DateTime _lastStatsTime = DateTime.now();

  final ReceiverStats stats = ReceiverStats();
  OnReceiverFrameAvailable? onFrameAvailable;
  OnReceiverStateChanged? onStateChanged;

  bool get isConnected => _isConnected;
  String get currentIp => _currentIp;

  Future<void> connect({
    required String ip,
    int port = ProtocolConstants.defaultPort,
    required String token,
  }) async {
    _currentIp = ip;

    final uri = Uri(
      scheme: 'ws',
      host: ip,
      port: port,
      queryParameters: (token.trim().isNotEmpty) ? {'token': token.trim()} : null,
    );

    try {
      if (onStateChanged != null) {
        onStateChanged!(false, 'Connecting to WebSocket $uri...', null);
      }

      _channel = WebSocketChannel.connect(uri);
      await _channel!.ready;

      _isConnected = true;
      if (onStateChanged != null) {
        onStateChanged!(true, 'Connected to PhoneCam stream at $ip:$port', null);
      }

      _channel!.stream.listen(
        (data) {
          if (data is Uint8List) {
            _handleBinaryFrame(data);
          } else if (data is String) {
            _handleTextMessage(data);
          }
        },
        onDone: () {
          _handleDisconnect('Connection closed by phone server', 'ServerClosed');
        },
        onError: (err) {
          _handleDisconnect('WebSocket Stream Error: $err', 'StreamError');
        },
      );
    } on SocketException catch (e) {
      final msg = 'Server Not Running on $ip:$port (${e.message}). Ensure PhoneCam app is open on phone.';
      _handleDisconnect(msg, 'ServerNotRunningError');
      rethrow;
    } on WebSocketChannelException catch (e) {
      final msg = 'WebSocket Connection Failed on ws://$ip:$port ($e). Check Security PIN or phone app status.';
      _handleDisconnect(msg, 'WebSocketHandshakeError');
      rethrow;
    } catch (e) {
      final errString = e.toString();
      if (errString.contains('was not upgraded to websocket')) {
        final msg = 'Authentication Error / Wrong Endpoint: Android server on $ip:$port rejected WebSocket upgrade. Ensure Security PIN matches phone screen.';
        _handleDisconnect(msg, 'AuthenticationError');
      } else {
        final msg = 'Connection Error on $ip:$port: $e';
        _handleDisconnect(msg, 'ConnectionError');
      }
      rethrow;
    }
  }

  void _handleBinaryFrame(Uint8List data) {
    final header = FrameHeader.fromBytes(data);
    if (header == null) {
      stats.decodeErrors++;
      if (onStateChanged != null) {
        onStateChanged!(_isConnected, 'Video Decoding Warning: Invalid header magic bytes in frame.', 'VideoDecodingError');
      }
      return;
    }

    if (data.length < ProtocolConstants.headerSize + header.payloadLength) {
      stats.decodeErrors++;
      if (onStateChanged != null) {
        onStateChanged!(_isConnected, 'Video Decoding Warning: Truncated JPEG payload.', 'VideoDecodingError');
      }
      return;
    }

    final frameBytes = Uint8List.view(
      data.buffer,
      data.offsetInBytes + ProtocolConstants.headerSize,
      header.payloadLength,
    );

    final now = DateTime.now().millisecondsSinceEpoch;
    final latency = (now - header.timestampMs).clamp(0, 10000);
    stats.latencyMs = latency;

    // Direct memory delivery to C++ Virtual Camera shared memory
    VirtualCameraFFI.writeFrame(header.width, header.height, frameBytes, true);

    if (onFrameAvailable != null) {
      onFrameAvailable!(frameBytes, header.width, header.height, latency);
    }

    _updateStats(data.length);
  }

  void _handleTextMessage(String text) {
    try {
      final json = jsonDecode(text);
      if (json['type'] == 'handshake') {
        final handshake = HandshakePayload.fromJson(json);
        debugPrint('Handshake received from ${handshake.deviceName} (${handshake.currentQuality.label})');
      }
    } catch (e) {
      stats.decodeErrors++;
      debugPrint('Text message decode error: $e');
    }
  }

  void sendControlAction(ControlMessage control) {
    if (_channel != null && _isConnected) {
      _channel!.sink.add(jsonEncode(control.toJson()));
    }
  }

  void _updateStats(int bytesReceivedThisFrame) {
    _frameCountInSecond++;
    _bytesInSecond += bytesReceivedThisFrame;
    stats.bytesReceived += bytesReceivedThisFrame;
    stats.framesReceived++;

    final now = DateTime.now();
    final elapsedMs = now.difference(_lastStatsTime).inMilliseconds;
    if (elapsedMs >= 1000) {
      stats.fps = (_frameCountInSecond * 1000.0) / elapsedMs;
      stats.throughputMbps = ((_bytesInSecond * 8.0) / 1000000.0) / (elapsedMs / 1000.0);

      _frameCountInSecond = 0;
      _bytesInSecond = 0;
      _lastStatsTime = now;
    }
  }

  void _handleDisconnect(String reason, String errorType) {
    _isConnected = false;
    VirtualCameraFFI.writeFrame(1280, 720, [], false);
    if (onStateChanged != null) {
      onStateChanged!(false, reason, errorType);
    }
  }

  Future<void> disconnect() async {
    _isConnected = false;
    if (_channel != null) {
      await _channel!.sink.close();
      _channel = null;
    }
    VirtualCameraFFI.writeFrame(1280, 720, [], false);
    if (onStateChanged != null) {
      onStateChanged!(false, 'Disconnected by user', null);
    }
  }
}
