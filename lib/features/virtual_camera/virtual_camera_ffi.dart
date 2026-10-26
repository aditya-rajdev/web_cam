import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

typedef NativeWriteFrame = Uint8 Function(
  Uint32 width,
  Uint32 height,
  Pointer<Uint8> rgbData,
  Uint32 dataSize,
  Uint32 isConnected,
);
typedef DartWriteFrame = int Function(
  int width,
  int height,
  Pointer<Uint8> rgbData,
  int dataSize,
  int isConnected,
);

typedef NativeIsFilterRegistered = Uint8 Function();
typedef DartIsFilterRegistered = int Function();

typedef NativeDiagnoseDirectShow = Uint8 Function();
typedef DartDiagnoseDirectShow = int Function();

typedef NativeRegisterFilter = Uint8 Function(Pointer<Utf16> dllPath);
typedef DartRegisterFilter = int Function(Pointer<Utf16> dllPath);

typedef NativeUnregisterFilter = Uint8 Function(Pointer<Utf16> dllPath);
typedef DartUnregisterFilter = int Function(Pointer<Utf16> dllPath);

class VirtualCameraFFI {
  static DynamicLibrary? _lib;
  static DartWriteFrame? _writeFrame;
  static DartIsFilterRegistered? _isFilterRegistered;
  static DartDiagnoseDirectShow? _diagnoseDirectShow;
  static DartRegisterFilter? _registerFilter;
  static DartUnregisterFilter? _unregisterFilter;

  static void initialize() {
    if (!Platform.isWindows) return;

    try {
      _lib = DynamicLibrary.executable();

      _writeFrame = _lib?.lookupFunction<NativeWriteFrame, DartWriteFrame>('PhoneCam_WriteFrame');
      _isFilterRegistered = _lib?.lookupFunction<NativeIsFilterRegistered, DartIsFilterRegistered>('PhoneCam_IsFilterRegistered');
      _diagnoseDirectShow = _lib?.lookupFunction<NativeDiagnoseDirectShow, DartDiagnoseDirectShow>('PhoneCam_DiagnoseDirectShow');
      _registerFilter = _lib?.lookupFunction<NativeRegisterFilter, DartRegisterFilter>('PhoneCam_RegisterFilter');
      _unregisterFilter = _lib?.lookupFunction<NativeUnregisterFilter, DartUnregisterFilter>('PhoneCam_UnregisterFilter');
    } catch (e) {
      debugPrint('VirtualCameraFFI initialization error: $e');
    }
  }

  static bool writeFrame(int width, int height, List<int> rgbBytes, bool isConnected) {
    if (_writeFrame == null || !Platform.isWindows) return false;

    final pointer = malloc<Uint8>(rgbBytes.length);
    final nativeList = pointer.asTypedList(rgbBytes.length);
    nativeList.setAll(0, rgbBytes);

    final result = _writeFrame!(width, height, pointer, rgbBytes.length, isConnected ? 1 : 0);
    malloc.free(pointer);

    return result != 0;
  }

  static bool isFilterRegistered() {
    if (_isFilterRegistered == null || !Platform.isWindows) return false;
    final isReg = _isFilterRegistered!() != 0;
    if (!isReg) return false;
    if (_diagnoseDirectShow != null) {
      return _diagnoseDirectShow!() != 0;
    }
    return isReg;
  }

  static bool registerFilter(String dllPath) {
    if (_registerFilter == null || !Platform.isWindows) return false;
    final pathPointer = dllPath.toNativeUtf16();
    final result = _registerFilter!(pathPointer);
    malloc.free(pathPointer);
    return result != 0;
  }

  static bool unregisterFilter(String dllPath) {
    if (_unregisterFilter == null || !Platform.isWindows) return false;
    final pathPointer = dllPath.toNativeUtf16();
    final result = _unregisterFilter!(pathPointer);
    malloc.free(pathPointer);
    return result != 0;
  }
}
