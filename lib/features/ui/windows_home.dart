import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/protocol/shared_protocol.dart';
import '../../core/theme/app_theme.dart';
import '../connection/windows_adb_manager.dart';
import '../streaming/windows_receiver.dart';
import '../virtual_camera/virtual_camera_ffi.dart';

class WindowsHomeScreen extends StatefulWidget {
  const WindowsHomeScreen({super.key});

  @override
  State<WindowsHomeScreen> createState() => _WindowsHomeScreenState();
}

class _WindowsHomeScreenState extends State<WindowsHomeScreen> {
  final WindowsReceiver _receiver = WindowsReceiver();

  final TextEditingController _ipController = TextEditingController(text: '192.168.1.100');
  final TextEditingController _pinController = TextEditingController();

  ConnectionMode _connectionMode = ConnectionMode.wifi;
  Uint8List? _currentFrameBytes;
  String _statusMessage = 'Ready to connect over Wi-Fi or USB';
  String? _errorType;
  bool _isConnecting = false;
  bool _isVirtualCamRegistered = false;
  bool _showAdvancedDiagnostics = false;

  List<AdbDeviceInfo> _adbDevices = [];
  bool _isAdbAvailable = false;
  String _resolvedAdbPath = '';
  String _selectedDeviceSerial = '';
  Timer? _statsTimer;
  final List<String> _diagnosticLogs = [];

  @override
  void initState() {
    super.initState();
    VirtualCameraFFI.initialize();
    _checkVirtualCamStatus();
    _checkAdbStatus();

    _receiver.onFrameAvailable = (bytes, w, h, latency) {
      if (mounted) {
        setState(() {
          _currentFrameBytes = bytes;
        });
      }
    };

    _receiver.onStateChanged = (connected, msg, errType) {
      if (mounted) {
        setState(() {
          _statusMessage = msg;
          _errorType = errType;
          _isConnecting = false;
        });
        _log('State [${errType ?? "OK"}]: $msg');
      }
    };

    _statsTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });
  }

  void _log(String msg) {
    if (!mounted) return;
    final timestamp = DateTime.now().toIso8601String().substring(11, 19);
    setState(() {
      _diagnosticLogs.insert(0, '[$timestamp] $msg');
      if (_diagnosticLogs.length > 50) _diagnosticLogs.removeLast();
    });
  }

  void _checkVirtualCamStatus() {
    final isRegistered = VirtualCameraFFI.isFilterRegistered();
    if (!mounted) return;
    setState(() {
      _isVirtualCamRegistered = isRegistered;
    });
    _log('Virtual Camera Filter COM status: ${isRegistered ? "REGISTERED (Ready for OBS/Meet/Zoom)" : "NOT REGISTERED"}');
  }

  Future<void> _checkAdbStatus() async {
    final adbPath = await WindowsAdbManager.getAdbExecutablePath();
    final available = adbPath != null;
    if (!mounted) return;
    setState(() {
      _isAdbAvailable = available;
      _resolvedAdbPath = adbPath ?? '';
    });
    if (available) {
      _log('ADB resolved at: $adbPath');
      _refreshAdbDevices();
    }
  }

  Future<void> _refreshAdbDevices() async {
    final devices = await WindowsAdbManager.getConnectedDevices();
    if (!mounted) return;
    final bestSerial = WindowsAdbManager.selectTargetDeviceSerial(devices);
    setState(() {
      _adbDevices = devices;
      _selectedDeviceSerial = bestSerial ?? (devices.isNotEmpty ? devices.first.serial : '');
    });
    _log('ADB scan: Found ${devices.length} USB device(s). Selected target: ${_selectedDeviceSerial.isEmpty ? "None" : _selectedDeviceSerial}');
  }

  Future<bool> _setupUsbTunnelInternal() async {
    _log('Setting up ADB port forwarding (tcp:8080 -> tcp:8080) for device $_selectedDeviceSerial...');
    final result = await WindowsAdbManager.setupPortForwarding(
      deviceSerial: _selectedDeviceSerial,
      port: ProtocolConstants.defaultPort,
    );

    if (result.success) {
      _log('ADB Forwarding Success! Port 8080 forwarded for device ${result.deviceSerial}.');
      if (mounted) {
        setState(() {
          _selectedDeviceSerial = result.deviceSerial;
        });
      }
      return true;
    } else {
      _log('ADB Forwarding Error: ${result.errorMessage}');
      if (mounted) {
        setState(() {
          _statusMessage = 'ADB Forwarding Error: ${result.errorMessage}';
          _errorType = 'AdbForwardingError';
        });
      }
      return false;
    }
  }

  Future<void> _registerVirtualCam() async {
    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      File dllFile = File('$exeDir\\PhoneCamFilter.dll');

      if (!dllFile.existsSync()) {
        dllFile = File('${Directory.current.path}\\PhoneCamFilter.dll');
      }

      if (!dllFile.existsSync()) {
        final appDir = await getApplicationSupportDirectory();
        dllFile = File('${appDir.path}\\PhoneCamFilter.dll');
      }

      _log('Registering DirectShow Filter DLL at: ${dllFile.path}');
      final success = VirtualCameraFFI.registerFilter(dllFile.path);
      _checkVirtualCamStatus();

      if (!mounted) return;
      if (success) {
        _log('PhoneCam Virtual Camera filter successfully registered in system registry!');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PhoneCam Virtual Camera registered! Select "PhoneCam" in OBS/Meet/Zoom/Teams.')),
        );
      } else {
        _log('Filter registration failed. Try running register_virtual_cam.bat as Administrator.');
        _showManualRegisterDialog();
      }
    } catch (e) {
      if (mounted) _showManualRegisterDialog();
    }
  }

  void _showManualRegisterDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.surfaceBorder),
        ),
        title: const Text('Register System Virtual Camera', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
        content: const Text(
          'To register PhoneCam Virtual WebCam for system-wide application support:\n\n'
          '1. Run scripts\\register_virtual_cam.bat as Administrator.\n'
          '2. Or run: regsvr32 PhoneCamFilter.dll in Administrator Command Prompt.\n\n'
          'Once registered, select "PhoneCam" as your camera in OBS Studio, Zoom, Google Meet, or Teams.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryAccent, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showUsbWizardDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.surfaceBorder),
        ),
        title: const Row(
          children: [
            Icon(Icons.usb, color: AppColors.primaryAccent),
            SizedBox(width: 8),
            Text('USB Connection Guide', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: const SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Why is USB Debugging Required?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textPrimary)),
              SizedBox(height: 6),
              Text(
                'Android OS requires USB Debugging authorization so trusted applications can route low-latency HD camera video over USB cable.\n\n'
                'Step-by-Step Setup:\n'
                '1. Open PhoneCam app on phone.\n'
                '2. Connect phone to PC using USB cable.\n'
                '3. On phone: Go to Settings -> About Phone -> Tap "Build Number" 7 times.\n'
                '4. Go to Settings -> Developer Options -> Enable "USB Debugging".\n'
                '5. Look at phone screen and accept "Allow USB Debugging" prompt.',
                style: TextStyle(fontSize: 13, height: 1.4, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryAccent, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Got It'),
          ),
        ],
      ),
    );
  }

  Future<void> _connectPhone() async {
    final String targetHost;
    final pin = _pinController.text.trim();

    if (_connectionMode == ConnectionMode.usb) {
      targetHost = '127.0.0.1';
      _log('Connecting in USB Mode via target 127.0.0.1:8080...');

      final adbOk = await _setupUsbTunnelInternal();
      if (!adbOk) {
        setState(() {
          _isConnecting = false;
        });
        return;
      }
    } else {
      targetHost = _ipController.text.trim();
      if (targetHost.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter phone IP address for Wi-Fi mode')),
        );
        return;
      }
      _log('Connecting in Wi-Fi Mode via target $targetHost:8080...');
    }

    setState(() {
      _isConnecting = true;
      _statusMessage = 'Connecting to ws://$targetHost:8080...';
      _errorType = null;
    });

    try {
      await _receiver.connect(
        ip: targetHost,
        port: ProtocolConstants.defaultPort,
        token: pin,
      );
    } catch (e) {
      _log('Connection failed: $e');
    }
  }

  Future<void> _disconnectPhone() async {
    await _receiver.disconnect();
    if (mounted) {
      setState(() {
        _currentFrameBytes = null;
      });
    }
  }

  String get resolvedAdbPath => _resolvedAdbPath.isEmpty ? 'Bundled ADB' : _resolvedAdbPath;

  @override
  void dispose() {
    _statsTimer?.cancel();
    _statsTimer = null;
    _receiver.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 5-Step Progress Checklist States
    final step1PhoneConnected = _connectionMode == ConnectionMode.wifi || _adbDevices.any((d) => d.isReady);
    final step2PermissionsGranted = true;
    final step3Authorized = _receiver.isConnected || step1PhoneConnected;
    final step4VideoActive = _receiver.isConnected && _currentFrameBytes != null;
    final step5VirtualCamReady = _isVirtualCamRegistered;

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.videocam_rounded, color: AppColors.primaryAccent, size: 26),
            SizedBox(width: 8),
            Text('PhoneCam PC Companion'),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _receiver.isConnected ? AppColors.success.withValues(alpha: 0.15) : AppColors.error.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _receiver.isConnected ? AppColors.success : AppColors.error),
                ),
                child: Text(
                  _receiver.isConnected ? 'CONNECTED' : 'DISCONNECTED',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    letterSpacing: 0.5,
                    color: _receiver.isConnected ? AppColors.success : AppColors.error,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: Row(
        children: [
          // Left Sidebar
          SizedBox(
            width: 390,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Virtual Cam Card
                  Card(
                    color: _isVirtualCamRegistered ? AppColors.success.withValues(alpha: 0.1) : AppColors.warning.withValues(alpha: 0.1),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                _isVirtualCamRegistered ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
                                color: _isVirtualCamRegistered ? AppColors.success : AppColors.warning,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _isVirtualCamRegistered
                                      ? 'System Virtual WebCam Registered'
                                      : 'Virtual WebCam Not Registered',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textPrimary),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.secondaryAccent,
                              foregroundColor: Colors.white,
                            ),
                            icon: const Icon(Icons.app_registration, size: 16),
                            label: Text(_isVirtualCamRegistered ? 'Re-register Virtual Cam' : 'Install / Register Virtual Cam'),
                            onPressed: _registerVirtualCam,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Mode Selector Segmented Button
                  SegmentedButton<ConnectionMode>(
                    segments: const [
                      ButtonSegment(value: ConnectionMode.wifi, label: Text('Recommended: Wi-Fi'), icon: Icon(Icons.wifi)),
                      ButtonSegment(value: ConnectionMode.usb, label: Text('Connect using USB'), icon: Icon(Icons.usb)),
                    ],
                    selected: {_connectionMode},
                    onSelectionChanged: (s) {
                      setState(() {
                        _connectionMode = s.first;
                        _statusMessage = _connectionMode == ConnectionMode.usb
                            ? 'USB Mode selected (target: ws://127.0.0.1:8080)'
                            : 'Wi-Fi Mode selected (target: ws://${_ipController.text}:8080)';
                        _errorType = null;
                      });
                    },
                  ),
                  const SizedBox(height: 12),

                  if (_connectionMode == ConnectionMode.wifi) ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.wifi, color: AppColors.success, size: 18),
                                SizedBox(width: 6),
                                Text('Connect over Wi-Fi (No Setup Required)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textPrimary)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _ipController,
                              decoration: const InputDecoration(
                                labelText: 'Phone Wi-Fi IP Address',
                                hintText: 'e.g. 192.168.1.105',
                                prefixIcon: Icon(Icons.network_ping, size: 18),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ] else ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  _isAdbAvailable ? Icons.usb : Icons.usb_off,
                                  color: _isAdbAvailable ? AppColors.success : AppColors.error,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'USB Debugging Required',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: _isAdbAvailable ? AppColors.success : AppColors.error,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                OutlinedButton.icon(
                                  icon: const Icon(Icons.help_outline, size: 15),
                                  label: const Text('Open Setup Guide'),
                                  onPressed: _showUsbWizardDialog,
                                ),
                                const SizedBox(width: 8),
                                OutlinedButton.icon(
                                  icon: const Icon(Icons.refresh, size: 15),
                                  label: const Text('Scan ADB'),
                                  onPressed: _refreshAdbDevices,
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            if (_adbDevices.isNotEmpty)
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Connected ADB Devices:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textSecondary)),
                                  ..._adbDevices.map((d) {
                                    final isSelected = d.serial == _selectedDeviceSerial;
                                    return Row(
                                      children: [
                                        Icon(
                                          isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                                          size: 14,
                                          color: isSelected ? AppColors.secondaryAccent : AppColors.textSecondary,
                                        ),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            '${d.serial} (${d.status})',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                              color: d.isReady ? (isSelected ? AppColors.secondaryAccent : AppColors.success) : AppColors.warning,
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                  }),
                                ],
                              )
                            else
                              const Text(
                                'No USB phone detected. Connect USB cable & allow USB Debugging prompt.',
                                style: TextStyle(fontSize: 12, color: AppColors.warning),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 8),
                  TextField(
                    controller: _pinController,
                    decoration: const InputDecoration(
                      labelText: 'Security PIN (from Phone app)',
                      hintText: 'Security PIN code from phone',
                      prefixIcon: Icon(Icons.lock_outline, size: 18),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),

                  SizedBox(
                    height: 48,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _receiver.isConnected ? AppColors.error : AppColors.success,
                        foregroundColor: Colors.white,
                      ),
                      icon: _isConnecting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : Icon(_receiver.isConnected ? Icons.power_settings_new_rounded : Icons.link_rounded),
                      label: Text(
                        _receiver.isConnected
                            ? 'Disconnect Stream'
                            : (_connectionMode == ConnectionMode.usb ? 'Connect using USB' : 'Connect over Wi-Fi'),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      onPressed: _isConnecting
                          ? null
                          : () {
                              if (_receiver.isConnected) {
                                _disconnectPhone();
                              } else {
                                _connectPhone();
                              }
                            },
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Connection Progress Checklist
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Connection Progress Checklist', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textPrimary)),
                          const Divider(color: AppColors.surfaceBorder),
                          _buildCheckStep('1. Phone connected', step1PhoneConnected),
                          _buildCheckStep('2. Required permissions granted', step2PermissionsGranted),
                          _buildCheckStep('3. PC paired or USB authorized', step3Authorized),
                          _buildCheckStep('4. Video stream available', step4VideoActive),
                          _buildCheckStep('5. Windows virtual webcam ready', step5VirtualCamReady),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Stats Card
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Performance Statistics', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textPrimary)),
                          const Divider(color: AppColors.surfaceBorder),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Latency:', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                              Text('${_receiver.stats.latencyMs} ms', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('FPS Received:', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                              Text(_receiver.stats.fps.toStringAsFixed(1), style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Bitrate:', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                              Text('${_receiver.stats.throughputMbps.toStringAsFixed(2)} Mbps', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const VerticalDivider(width: 1, color: AppColors.surfaceBorder),

          // Right Canvas
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 3,
                    child: Card(
                      clipBehavior: Clip.antiAlias,
                      color: Colors.black,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          _currentFrameBytes != null
                              ? Image.memory(
                                  _currentFrameBytes!,
                                  fit: BoxFit.contain,
                                  gaplessPlayback: true,
                                )
                              : const Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.videocam_off_rounded, size: 64, color: AppColors.surfaceBorder),
                                    SizedBox(height: 12),
                                    Text(
                                      'PhoneCam Stream Inactive',
                                      style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
                                    ),
                                    SizedBox(height: 6),
                                    Text(
                                      'Connect phone over Wi-Fi or USB to view camera feed and stream to OBS / Zoom / Meet',
                                      style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                                    ),
                                  ],
                                ),
                          Positioned(
                            bottom: 12,
                            left: 12,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppColors.surface.withValues(alpha: 0.85),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppColors.surfaceBorder),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _statusMessage,
                                    style: TextStyle(
                                      color: _errorType != null ? AppColors.error : AppColors.textPrimary,
                                      fontWeight: _errorType != null ? FontWeight.bold : FontWeight.normal,
                                      fontSize: 12,
                                    ),
                                  ),
                                  if (_errorType != null) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      'Category: $_errorType',
                                      style: const TextStyle(color: AppColors.warning, fontSize: 11),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Collapsible Advanced Diagnostics Panel
                  Card(
                    color: AppColors.surface,
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.terminal, size: 18, color: AppColors.primaryAccent),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Advanced Diagnostics Log (${_diagnosticLogs.length} events)',
                                    style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                ],
                              ),
                              Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.copy, size: 16, color: AppColors.textSecondary),
                                    onPressed: () {
                                      Clipboard.setData(ClipboardData(text: _diagnosticLogs.join('\n')));
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Diagnostic logs copied to clipboard')),
                                      );
                                    },
                                    tooltip: 'Copy logs',
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      _showAdvancedDiagnostics ? Icons.expand_less : Icons.expand_more,
                                      color: AppColors.textSecondary,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _showAdvancedDiagnostics = !_showAdvancedDiagnostics;
                                      });
                                    },
                                    tooltip: _showAdvancedDiagnostics ? 'Collapse logs' : 'Expand logs',
                                  ),
                                ],
                              ),
                            ],
                          ),
                          if (_showAdvancedDiagnostics) ...[
                            const Divider(color: AppColors.surfaceBorder),
                            SizedBox(
                              height: 120,
                              child: ListView.builder(
                                itemCount: _diagnosticLogs.length,
                                itemBuilder: (ctx, idx) => Text(
                                  _diagnosticLogs[idx],
                                  style: const TextStyle(color: AppColors.success, fontSize: 11, fontFamily: 'monospace'),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckStep(String title, bool isDone) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.0),
      child: Row(
        children: [
          Icon(
            isDone ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
            size: 15,
            color: isDone ? AppColors.success : AppColors.textSecondary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 12,
                color: isDone ? AppColors.textPrimary : AppColors.textSecondary,
                fontWeight: isDone ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
