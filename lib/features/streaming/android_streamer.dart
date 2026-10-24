import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:network_info_plus/network_info_plus.dart';
import '../../core/protocol/shared_protocol.dart';

typedef OnControlMessageReceived = void Function(ControlMessage message);

class StreamStats {
  double fps = 0.0;
  double throughputMbps = 0.0;
  int framesSent = 0;
  int bytesSent = 0;
  int connectedClients = 0;
}

class AndroidStreamer {
  HttpServer? _server;
  final List<WebSocket> _clients = [];
  final NetworkInfo _networkInfo = NetworkInfo();

  String _localIp = '127.0.0.1';
  int _port = ProtocolConstants.defaultPort;
  String _pairingToken = '';
  bool _isListening = false;

  int _sequenceNumber = 0;
  int _frameCountInSecond = 0;
  int _bytesInSecond = 0;
  DateTime _lastStatsTime = DateTime.now();

  final StreamStats stats = StreamStats();
  OnControlMessageReceived? onControlMessage;

  String get localIp => _localIp;
  int get port => _port;
  String get pairingToken => _pairingToken;
  bool get isListening => _isListening;
  int get clientCount => _clients.length;

  String get connectionUrl => 'ws://$_localIp:$_port';
  String get qrPayload => 'phonecam://connect?ip=$_localIp&port=$_port&token=$_pairingToken';

  Future<void> startServer({int port = ProtocolConstants.defaultPort}) async {
    _port = port;
    _pairingToken = _generatePairingToken();

    try {
      final ip = await _networkInfo.getWifiIP();
      _localIp = ip ?? '127.0.0.1';
    } catch (e) {
      _localIp = '127.0.0.1';
    }

    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, _port);
      _isListening = true;
      debugPrint('PhoneCam WebSocket server running on 0.0.0.0:$_port with token $_pairingToken');

      _server!.listen((HttpRequest request) {
        if (WebSocketTransformer.isUpgradeRequest(request)) {
          final requestedToken = request.uri.queryParameters['token'];

          if (_pairingToken.isNotEmpty && requestedToken != null && requestedToken.isNotEmpty && requestedToken != _pairingToken) {
            request.response.statusCode = HttpStatus.unauthorized;
            request.response.headers.contentType = ContentType.text;
            request.response.write('UNAUTHORIZED_PIN');
            request.response.close();
            debugPrint('Rejected client connection with wrong PIN: "$requestedToken" (expected "$_pairingToken")');
            return;
          }

          WebSocketTransformer.upgrade(request).then((WebSocket ws) {
            _handleNewClient(ws);
          });
        } else {
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.contentType = ContentType.text;
          request.response.write('PhoneCam Android Streaming Server active on port $_port. Security PIN: $_pairingToken');
          request.response.close();
        }
      });
    } catch (e) {
      _isListening = false;
      debugPrint('Error starting PhoneCam server: $e');
      rethrow;
    }
  }

  void _handleNewClient(WebSocket ws) {
    _clients.add(ws);
    stats.connectedClients = _clients.length;
    debugPrint('Desktop client connected via WebSocket. Total clients: ${_clients.length}');

    final handshake = HandshakePayload(
      deviceName: Platform.operatingSystem,
      token: _pairingToken,
      version: '1.0.0',
      supportedResolutions: StreamQuality.values.map((q) => q.label).toList(),
      supportedFramerates: [24, 30, 60],
      currentQuality: StreamQuality.res720p,
      currentLens: CameraLens.back,
      currentFps: 30,
    );

    ws.add(jsonEncode(handshake.toJson()));

    // Auto-trigger camera capture start on client connection
    if (onControlMessage != null) {
      onControlMessage!(ControlMessage(action: 'start'));
    }

    ws.listen(
      (data) {
        if (data is String) {
          try {
            final json = jsonDecode(data);
            if (json['type'] == 'control') {
              final controlMsg = ControlMessage.fromJson(json);
              if (onControlMessage != null) {
                onControlMessage!(controlMsg);
              }
            }
          } catch (e) {
            debugPrint('Control message decode error: $e');
          }
        }
      },
      onDone: () {
        _clients.remove(ws);
        stats.connectedClients = _clients.length;
        debugPrint('Client disconnected. Remaining clients: ${_clients.length}');
      },
      onError: (err) {
        _clients.remove(ws);
        stats.connectedClients = _clients.length;
        debugPrint('Client socket error: $err');
      },
    );
  }

  void broadcastFrame(Uint8List jpegBytes, int width, int height) {
    if (_clients.isEmpty) return;

    _sequenceNumber++;
    final header = FrameHeader(
      payloadLength: jpegBytes.length,
      sequenceNumber: _sequenceNumber,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      width: width,
      height: height,
    );

    final headerBytes = header.toBytes();
    final combinedPacket = Uint8List(headerBytes.length + jpegBytes.length);
    combinedPacket.setRange(0, headerBytes.length, headerBytes);
    combinedPacket.setRange(headerBytes.length, combinedPacket.length, jpegBytes);

    final List<WebSocket> disconnected = [];
    for (final ws in _clients) {
      try {
        ws.add(combinedPacket);
      } catch (e) {
        disconnected.add(ws);
      }
    }

    for (final ws in disconnected) {
      _clients.remove(ws);
    }

    _updateStats(combinedPacket.length);
  }

  void _updateStats(int bytesSentThisFrame) {
    _frameCountInSecond++;
    _bytesInSecond += bytesSentThisFrame;
    stats.bytesSent += bytesSentThisFrame;
    stats.framesSent++;

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

  String _generatePairingToken() {
    final rand = Random();
    final code = rand.nextInt(900000) + 100000;
    return code.toString();
  }

  Future<void> stopServer() async {
    for (final ws in _clients) {
      await ws.close();
    }
    _clients.clear();

    if (_server != null) {
      await _server!.close(force: true);
      _server = null;
    }
    _isListening = false;
  }
}
