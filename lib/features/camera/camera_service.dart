import 'dart:async';
import 'package:camera/camera.dart' as cam;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../core/protocol/shared_protocol.dart';

typedef OnFrameAvailable = void Function(Uint8List jpegBytes, int width, int height);

class CameraService {
  static const MethodChannel _platform = MethodChannel('com.example.phonecam/camera');

  List<cam.CameraDescription> _availableCameras = [];
  cam.CameraController? _controller;
  cam.CameraDescription? _currentCamera;

  bool _isStreaming = false;
  bool _isProcessingFrame = false;
  bool _isInitializing = false;
  bool _isMirrored = false;

  double _minZoom = 1.0;
  double _maxZoom = 1.0;
  double _currentZoom = 1.0;

  bool _hasTorch = false;
  bool _isTorchOn = false;

  cam.FocusMode _focusMode = cam.FocusMode.auto;

  StreamQuality _currentQuality = StreamQuality.res720p;
  CameraLens _currentLens = CameraLens.back;
  int currentFps = 30;

  OnFrameAvailable? onFrameAvailable;

  List<cam.CameraDescription> get availableCameras => _availableCameras;
  cam.CameraController? get controller => _controller;
  bool get isInitialized => _controller != null && _controller!.value.isInitialized && !_isInitializing;
  bool get isInitializing => _isInitializing;
  bool get isStreaming => _isStreaming;
  bool get isMirrored => _isMirrored;

  double get minZoom => _minZoom;
  double get maxZoom => _maxZoom;
  double get currentZoom => _currentZoom;

  bool get hasTorch => _hasTorch;
  bool get isTorchOn => _isTorchOn;

  cam.FocusMode get focusMode => _focusMode;

  StreamQuality get currentQuality => _currentQuality;
  CameraLens get currentLens => _currentLens;

  Future<void> initialize() async {
    if (_isInitializing) return;
    _isInitializing = true;

    try {
      _availableCameras = await cam.availableCameras();
      if (_availableCameras.isNotEmpty) {
        _currentCamera = _selectCameraForLens(_currentLens);
        await _initializeController();
      }
    } catch (e) {
      debugPrint('Camera initialization error: $e');
    } finally {
      _isInitializing = false;
    }
  }

  cam.CameraDescription _selectCameraForLens(CameraLens lens) {
    if (_availableCameras.isEmpty) {
      throw Exception('No cameras found');
    }

    if (lens == CameraLens.front) {
      return _availableCameras.firstWhere(
        (c) => c.lensDirection == cam.CameraLensDirection.front,
        orElse: () => _availableCameras.first,
      );
    } else {
      return _availableCameras.firstWhere(
        (c) => c.lensDirection == cam.CameraLensDirection.back,
        orElse: () => _availableCameras.first,
      );
    }
  }

  cam.ResolutionPreset _qualityToPreset(StreamQuality quality) {
    switch (quality) {
      case StreamQuality.res1080p:
        return cam.ResolutionPreset.high;
      case StreamQuality.res720p:
        return cam.ResolutionPreset.high;
      case StreamQuality.res480p:
        return cam.ResolutionPreset.medium;
    }
  }

  Future<void> _initializeController() async {
    if (_currentCamera == null) return;

    if (_controller != null) {
      final oldController = _controller;
      _controller = null;
      try {
        if (oldController!.value.isStreamingImages) {
          await oldController.stopImageStream();
        }
      } catch (_) {}
      try {
        await oldController!.dispose();
      } catch (_) {}
    }

    final newController = cam.CameraController(
      _currentCamera!,
      _qualityToPreset(_currentQuality),
      enableAudio: false,
      imageFormatGroup: cam.ImageFormatGroup.yuv420,
    );

    try {
      await newController.initialize();
      _controller = newController;

      // Query runtime zoom capabilities
      _minZoom = await newController.getMinZoomLevel();
      _maxZoom = await newController.getMaxZoomLevel();
      _currentZoom = _minZoom.clamp(_minZoom, _maxZoom);

      // Query torch availability (Back cameras usually have flash/torch)
      _hasTorch = _currentCamera!.lensDirection == cam.CameraLensDirection.back;
      _isTorchOn = false;

      _focusMode = cam.FocusMode.auto;
    } catch (e) {
      debugPrint('Error initializing camera controller: $e');
      try {
        await newController.dispose();
      } catch (_) {}
      rethrow;
    }
  }

  Future<void> setZoomLevel(double zoom) async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    final clampedZoom = zoom.clamp(_minZoom, _maxZoom);
    _currentZoom = clampedZoom;
    try {
      await _controller!.setZoomLevel(clampedZoom);
    } catch (e) {
      debugPrint('Error setting zoom level: $e');
    }
  }

  Future<void> toggleTorch() async {
    if (_controller == null || !_controller!.value.isInitialized || !_hasTorch) return;
    final newState = !_isTorchOn;
    try {
      await _controller!.setFlashMode(
        newState ? cam.FlashMode.torch : cam.FlashMode.off,
      );
      _isTorchOn = newState;
    } catch (e) {
      debugPrint('Error toggling torch: $e');
    }
  }

  Future<void> setFocusPoint(Offset relativeOffset) async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    try {
      await _controller!.setFocusPoint(relativeOffset);
      await _controller!.setFocusMode(cam.FocusMode.auto);
      _focusMode = cam.FocusMode.auto;
    } catch (e) {
      debugPrint('Error setting focus point: $e');
    }
  }

  Future<void> resetFocusMode() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    try {
      await _controller!.setFocusMode(cam.FocusMode.auto);
      _focusMode = cam.FocusMode.auto;
    } catch (e) {
      debugPrint('Error resetting focus mode: $e');
    }
  }

  Future<void> setQuality(StreamQuality quality) async {
    if (_currentQuality == quality || _isInitializing) return;
    _currentQuality = quality;
    await _recreateSession();
  }

  Future<void> setLens(CameraLens lens) async {
    if (_currentLens == lens || _isInitializing) return;
    _isInitializing = true;
    _currentLens = lens;

    try {
      if (_availableCameras.isEmpty) {
        _availableCameras = await cam.availableCameras();
      }
      _currentCamera = _selectCameraForLens(lens);

      if (lens == CameraLens.front) {
        _isMirrored = true;
      } else {
        _isMirrored = false;
      }

      await _recreateSession();
    } catch (e) {
      debugPrint('Error switching camera lens: $e');
    } finally {
      _isInitializing = false;
    }
  }

  Future<void> _recreateSession() async {
    final wasStreaming = _isStreaming;
    if (wasStreaming) {
      await stopStreaming();
    }

    try {
      await _initializeController();
    } catch (e) {
      debugPrint('Camera recreation error: $e');
    }

    if (wasStreaming && isInitialized) {
      await startStreaming();
    }
  }

  void toggleMirror() {
    _isMirrored = !_isMirrored;
  }

  Future<void> startStreaming() async {
    if (_controller == null || !_controller!.value.isInitialized || _isStreaming || _isInitializing) return;

    _isStreaming = true;

    try {
      await _platform.invokeMethod('startForegroundService');
    } catch (_) {}

    try {
      await _controller!.startImageStream((cam.CameraImage image) async {
        if (!_isStreaming || _isProcessingFrame) return;

        _isProcessingFrame = true;
        try {
          final Uint8List? jpegBytes = await _convertCameraImageToJpeg(image);
          if (jpegBytes != null && onFrameAvailable != null && _isStreaming) {
            onFrameAvailable!(jpegBytes, image.width, image.height);
          }
        } catch (_) {
        } finally {
          _isProcessingFrame = false;
        }
      });
    } catch (e) {
      debugPrint('Error starting image stream: $e');
      _isStreaming = false;
    }
  }

  Future<void> stopStreaming() async {
    if (!_isStreaming) return;
    _isStreaming = false;

    if (_controller != null && _controller!.value.isInitialized && _controller!.value.isStreamingImages) {
      try {
        await _controller!.stopImageStream();
      } catch (_) {}
    }

    try {
      await _platform.invokeMethod('stopForegroundService');
    } catch (_) {}
  }

  Future<Uint8List?> _convertCameraImageToJpeg(cam.CameraImage image) async {
    if (image.planes.length < 3) return null;

    try {
      final Uint8List? result = await _platform.invokeMethod('compressYuvToJpeg', {
        'yPlane': image.planes[0].bytes,
        'uPlane': image.planes[1].bytes,
        'vPlane': image.planes[2].bytes,
        'yRowStride': image.planes[0].bytesPerRow,
        'uvRowStride': image.planes[1].bytesPerRow,
        'uvPixelStride': image.planes[1].bytesPerPixel ?? 2,
        'width': image.width,
        'height': image.height,
        'quality': 80,
      });
      return result;
    } catch (e) {
      return null;
    }
  }

  Future<void> dispose() async {
    await stopStreaming();
    if (_controller != null) {
      try {
        await _controller!.dispose();
      } catch (_) {}
      _controller = null;
    }
  }
}
