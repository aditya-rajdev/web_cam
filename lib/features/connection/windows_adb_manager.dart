import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class AdbDeviceInfo {
  final String serial;
  final String status; // 'device', 'unauthorized', 'offline', 'unknown'

  AdbDeviceInfo({required this.serial, required this.status});

  bool get isReady => status == 'device';
  bool get isUnauthorized => status == 'unauthorized';
  bool get isOffline => status == 'offline';
  bool get isEmulator => serial.startsWith('emulator-');
}

class AdbForwardResult {
  final bool success;
  final String deviceSerial;
  final String errorMessage;
  final String adbExecutablePath;

  AdbForwardResult({
    required this.success,
    required this.deviceSerial,
    required this.errorMessage,
    required this.adbExecutablePath,
  });
}

class WindowsAdbManager {
  static const String priorityPhysicalSerial = '9HZT8TKFKBV4IJI7';
  static String? _cachedAdbPath;

  /// Resolves absolute path to bundled adb.exe without requiring PATH environment variable
  static Future<String?> getAdbExecutablePath() async {
    if (_cachedAdbPath != null && File(_cachedAdbPath!).existsSync()) {
      return _cachedAdbPath;
    }

    final candidatePaths = <String>[];

    // 1. Executable directory (Bundled platform-tools in production Release build)
    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      candidatePaths.add('$exeDir\\platform-tools\\adb.exe');
      candidatePaths.add('$exeDir\\tools\\platform-tools\\adb.exe');
    } catch (_) {}

    // 2. Development directory (project root during flutter run)
    candidatePaths.add('${Directory.current.path}\\windows\\runner\\tools\\platform-tools\\adb.exe');

    // 3. Application support directory
    try {
      final appDir = await getApplicationSupportDirectory();
      candidatePaths.add('${appDir.path}\\platform-tools\\adb.exe');
    } catch (_) {}

    // 4. Local Android SDK if installed
    final localAppData = Platform.environment['LOCALAPPDATA'];
    if (localAppData != null && localAppData.isNotEmpty) {
      candidatePaths.add('$localAppData\\Android\\Sdk\\platform-tools\\adb.exe');
    }
    final androidHome = Platform.environment['ANDROID_HOME'];
    if (androidHome != null && androidHome.isNotEmpty) {
      candidatePaths.add('$androidHome\\platform-tools\\adb.exe');
    }

    for (final path in candidatePaths) {
      if (File(path).existsSync()) {
        _cachedAdbPath = path;
        debugPrint('Resolved bundled ADB executable at: $path');
        return path;
      }
    }

    // 5. System PATH fallback as last resort
    try {
      final whereResult = await Process.run('where.exe', ['adb']);
      if (whereResult.exitCode == 0) {
        final path = (whereResult.stdout as String).split('\n').first.trim();
        if (path.isNotEmpty && File(path).existsSync()) {
          _cachedAdbPath = path;
          return path;
        }
      }
    } catch (_) {}

    return null;
  }

  static Future<bool> isAdbAvailable() async {
    final adbPath = await getAdbExecutablePath();
    if (adbPath == null) return false;

    try {
      final result = await Process.run(adbPath, ['version']);
      return result.exitCode == 0;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> ensureAdbServerRunning() async {
    final adbPath = await getAdbExecutablePath();
    if (adbPath == null) return false;

    try {
      final result = await Process.run(adbPath, ['start-server']);
      return result.exitCode == 0;
    } catch (e) {
      debugPrint('Error starting ADB server: $e');
      return false;
    }
  }

  static Future<List<AdbDeviceInfo>> getConnectedDevices() async {
    final devices = <AdbDeviceInfo>[];
    final adbPath = await getAdbExecutablePath();
    if (adbPath == null) return devices;

    await ensureAdbServerRunning();

    try {
      final result = await Process.run(adbPath, ['devices']);
      if (result.exitCode == 0) {
        final lines = (result.stdout as String).split('\n');
        for (var line in lines) {
          line = line.trim();
          if (line.isEmpty || line.startsWith('List of devices')) continue;

          final parts = line.split(RegExp(r'\s+'));
          if (parts.length >= 2) {
            devices.add(AdbDeviceInfo(
              serial: parts[0],
              status: parts[1],
            ));
          }
        }
      }
    } catch (e) {
      debugPrint('ADB device query error: $e');
    }
    return devices;
  }

  static String? selectTargetDeviceSerial(List<AdbDeviceInfo> devices) {
    if (devices.isEmpty) return null;

    final readyDevices = devices.where((d) => d.isReady).toList();
    if (readyDevices.isEmpty) return null;

    // Prioritize physical device '9HZT8TKFKBV4IJI7'
    final priorityDevice = readyDevices.firstWhere(
      (d) => d.serial == priorityPhysicalSerial,
      orElse: () => readyDevices.firstWhere(
        (d) => !d.isEmulator,
        orElse: () => readyDevices.first,
      ),
    );

    return priorityDevice.serial;
  }

  static Future<AdbForwardResult> setupPortForwarding({
    String? deviceSerial,
    int port = 8080,
  }) async {
    final adbPath = await getAdbExecutablePath();
    if (adbPath == null) {
      return AdbForwardResult(
        success: false,
        deviceSerial: '',
        errorMessage: 'Bundled adb.exe not found. Reinstall PhoneCam or extract bundled platform-tools.',
        adbExecutablePath: '',
      );
    }

    await ensureAdbServerRunning();

    try {
      String? serial = deviceSerial;
      if (serial == null || serial.isEmpty) {
        final devices = await getConnectedDevices();
        if (devices.isEmpty) {
          return AdbForwardResult(
            success: false,
            deviceSerial: '',
            errorMessage: 'No USB Android device detected. Connect phone via USB cable and enable USB Debugging in Developer Options.',
            adbExecutablePath: adbPath,
          );
        }

        final unauthorized = devices.where((d) => d.isUnauthorized).toList();
        if (unauthorized.isNotEmpty && !devices.any((d) => d.isReady)) {
          return AdbForwardResult(
            success: false,
            deviceSerial: unauthorized.first.serial,
            errorMessage: 'Device ${unauthorized.first.serial} is unauthorized. Check phone display to accept "Allow USB debugging" prompt.',
            adbExecutablePath: adbPath,
          );
        }

        serial = selectTargetDeviceSerial(devices);
        if (serial == null) {
          return AdbForwardResult(
            success: false,
            deviceSerial: '',
            errorMessage: 'No ready Android device available for ADB port forwarding.',
            adbExecutablePath: adbPath,
          );
        }
      }

      final result = await Process.run(adbPath, ['-s', serial, 'forward', 'tcp:$port', 'tcp:$port']);
      if (result.exitCode == 0) {
        return AdbForwardResult(
          success: true,
          deviceSerial: serial,
          errorMessage: '',
          adbExecutablePath: adbPath,
        );
      } else {
        final err = (result.stderr as String).trim();
        return AdbForwardResult(
          success: false,
          deviceSerial: serial,
          errorMessage: 'ADB forwarding failed for $serial: ${err.isEmpty ? result.stdout : err}',
          adbExecutablePath: adbPath,
        );
      }
    } catch (e) {
      return AdbForwardResult(
        success: false,
        deviceSerial: deviceSerial ?? '',
        errorMessage: 'ADB process error: $e',
        adbExecutablePath: adbPath,
      );
    }
  }

  static Future<bool> removePortForwarding({
    String? deviceSerial,
    int port = 8080,
  }) async {
    final adbPath = await getAdbExecutablePath();
    if (adbPath == null) return false;

    try {
      final args = deviceSerial != null && deviceSerial.isNotEmpty
          ? ['-s', deviceSerial, 'forward', '--remove', 'tcp:$port']
          : ['forward', '--remove', 'tcp:$port'];
      final result = await Process.run(adbPath, args);
      return result.exitCode == 0;
    } catch (e) {
      return false;
    }
  }
}
