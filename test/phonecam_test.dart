import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:phonecam/core/protocol/shared_protocol.dart';

void main() {
  group('PhoneCam Protocol Unit Tests', () {
    test('FrameHeader serialization and deserialization', () {
      final header = FrameHeader(
        payloadLength: 1024,
        sequenceNumber: 42,
        timestampMs: 1600000000,
        width: 1280,
        height: 720,
      );

      final bytes = header.toBytes();
      expect(bytes.length, equals(ProtocolConstants.headerSize));

      final parsedHeader = FrameHeader.fromBytes(bytes);
      expect(parsedHeader, isNotNull);
      expect(parsedHeader!.payloadLength, equals(1024));
      expect(parsedHeader.sequenceNumber, equals(42));
      expect(parsedHeader.width, equals(1280));
      expect(parsedHeader.height, equals(720));
    });

    test('Invalid FrameHeader magic bytes rejected', () {
      final invalidBytes = Uint8List(16);
      invalidBytes[0] = 0x00; // Invalid magic
      final parsedHeader = FrameHeader.fromBytes(invalidBytes);
      expect(parsedHeader, isNull);
    });

    test('HandshakePayload serialization and deserialization', () {
      final handshake = HandshakePayload(
        deviceName: 'Pixel 7',
        token: '123456',
        version: '1.0.0',
        supportedResolutions: ['1080p', '720p', '480p'],
        supportedFramerates: [24, 30, 60],
        currentQuality: StreamQuality.res720p,
        currentLens: CameraLens.back,
        currentFps: 30,
      );

      final json = handshake.toJson();
      expect(json['device_name'], equals('Pixel 7'));
      expect(json['token'], equals('123456'));

      final reconstructed = HandshakePayload.fromJson(json);
      expect(reconstructed.deviceName, equals('Pixel 7'));
      expect(reconstructed.currentQuality, equals(StreamQuality.res720p));
      expect(reconstructed.currentLens, equals(CameraLens.back));
    });

    test('ControlMessage serialization and deserialization', () {
      final control = ControlMessage(
        action: 'set_resolution',
        quality: StreamQuality.res1080p,
      );

      final json = control.toJson();
      expect(json['action'], equals('set_resolution'));
      expect(json['quality'], equals('1080p (FHD)'));

      final reconstructed = ControlMessage.fromJson(json);
      expect(reconstructed.action, equals('set_resolution'));
      expect(reconstructed.quality, equals(StreamQuality.res1080p));
    });
  });
}
