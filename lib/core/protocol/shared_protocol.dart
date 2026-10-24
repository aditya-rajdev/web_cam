import 'dart:typed_data';

class ProtocolConstants {
  static const int defaultPort = 8080;
  static const List<int> magicHeader = [0x50, 0x43, 0x41, 0x4D]; // 'PCAM'
  static const int headerSize = 16;
}

enum ConnectionMode { wifi, usb }

enum CameraLens { back, front, ultraWide, telephoto }

enum StreamQuality {
  res1080p(width: 1920, height: 1080, label: "1080p (FHD)"),
  res720p(width: 1280, height: 720, label: "720p (HD)"),
  res480p(width: 640, height: 480, label: "480p (SD)");

  final int width;
  final int height;
  final String label;

  const StreamQuality({
    required this.width,
    required this.height,
    required this.label,
  });
}

class HandshakePayload {
  final String deviceName;
  final String token;
  final String version;
  final List<String> supportedResolutions;
  final List<int> supportedFramerates;
  final StreamQuality currentQuality;
  final CameraLens currentLens;
  final int currentFps;

  HandshakePayload({
    required this.deviceName,
    required this.token,
    required this.version,
    required this.supportedResolutions,
    required this.supportedFramerates,
    required this.currentQuality,
    required this.currentLens,
    required this.currentFps,
  });

  Map<String, dynamic> toJson() => {
    'type': 'handshake',
    'device_name': deviceName,
    'token': token,
    'version': version,
    'supported_resolutions': supportedResolutions,
    'supported_framerates': supportedFramerates,
    'current_quality': currentQuality.label,
    'current_lens': currentLens.name,
    'current_fps': currentFps,
  };

  factory HandshakePayload.fromJson(Map<String, dynamic> json) {
    return HandshakePayload(
      deviceName: json['device_name'] ?? 'Unknown Device',
      token: json['token'] ?? '',
      version: json['version'] ?? '1.0.0',
      supportedResolutions: List<String>.from(json['supported_resolutions'] ?? ['720p']),
      supportedFramerates: List<int>.from(json['supported_framerates'] ?? [30]),
      currentQuality: StreamQuality.values.firstWhere(
        (q) => q.label == json['current_quality'],
        orElse: () => StreamQuality.res720p,
      ),
      currentLens: CameraLens.values.firstWhere(
        (l) => l.name == json['current_lens'],
        orElse: () => CameraLens.back,
      ),
      currentFps: json['current_fps'] ?? 30,
    );
  }
}

class ControlMessage {
  final String action;
  final StreamQuality? quality;
  final CameraLens? lens;
  final int? fps;

  ControlMessage({
    required this.action,
    this.quality,
    this.lens,
    this.fps,
  });

  Map<String, dynamic> toJson() => {
    'type': 'control',
    'action': action,
    if (quality != null) 'quality': quality!.label,
    if (lens != null) 'lens': lens!.name,
    if (fps != null) 'fps': fps,
  };

  factory ControlMessage.fromJson(Map<String, dynamic> json) {
    return ControlMessage(
      action: json['action'] ?? '',
      quality: json['quality'] != null
          ? StreamQuality.values.firstWhere(
              (q) => q.label == json['quality'],
              orElse: () => StreamQuality.res720p,
            )
          : null,
      lens: json['lens'] != null
          ? CameraLens.values.firstWhere(
              (l) => l.name == json['lens'],
              orElse: () => CameraLens.back,
            )
          : null,
      fps: json['fps'],
    );
  }
}

class FrameHeader {
  final int payloadLength;
  final int sequenceNumber;
  final int timestampMs;
  final int width;
  final int height;

  FrameHeader({
    required this.payloadLength,
    required this.sequenceNumber,
    required this.timestampMs,
    required this.width,
    required this.height,
  });

  Uint8List toBytes() {
    final buffer = ByteData(ProtocolConstants.headerSize);
    buffer.setUint8(0, ProtocolConstants.magicHeader[0]);
    buffer.setUint8(1, ProtocolConstants.magicHeader[1]);
    buffer.setUint8(2, ProtocolConstants.magicHeader[2]);
    buffer.setUint8(3, ProtocolConstants.magicHeader[3]);
    buffer.setUint32(4, payloadLength, Endian.big);
    buffer.setUint32(8, sequenceNumber, Endian.big);
    buffer.setUint16(12, width, Endian.big);
    buffer.setUint16(14, height, Endian.big);
    return buffer.buffer.asUint8List();
  }

  static FrameHeader? fromBytes(Uint8List bytes) {
    if (bytes.length < ProtocolConstants.headerSize) return null;
    if (bytes[0] != ProtocolConstants.magicHeader[0] ||
        bytes[1] != ProtocolConstants.magicHeader[1] ||
        bytes[2] != ProtocolConstants.magicHeader[2] ||
        bytes[3] != ProtocolConstants.magicHeader[3]) {
      return null;
    }

    final buffer = ByteData.view(bytes.buffer, bytes.offsetInBytes, ProtocolConstants.headerSize);
    final length = buffer.getUint32(4, Endian.big);
    final seq = buffer.getUint32(8, Endian.big);
    final w = buffer.getUint16(12, Endian.big);
    final h = buffer.getUint16(14, Endian.big);

    return FrameHeader(
      payloadLength: length,
      sequenceNumber: seq,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      width: w,
      height: h,
    );
  }
}
