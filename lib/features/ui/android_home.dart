import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../core/protocol/shared_protocol.dart';
import '../../core/theme/app_theme.dart';
import '../auth/screens/profile_screen.dart';
import '../auth/services/auth_api_service.dart';
import '../camera/camera_service.dart';
import '../streaming/android_streamer.dart';
import '../subscription/subscription_dialogs.dart';
import '../subscription/subscription_service.dart';

class AndroidHomeScreen extends StatefulWidget {
  const AndroidHomeScreen({super.key});

  @override
  State<AndroidHomeScreen> createState() => _AndroidHomeScreenState();
}

class _AndroidHomeScreenState extends State<AndroidHomeScreen> {
  static const MethodChannel _platform = MethodChannel('com.example.phonecam/camera');

  final CameraService _cameraService = CameraService();
  final AndroidStreamer _androidStreamer = AndroidStreamer();
  final SubscriptionService _subService = SubscriptionService.instance;

  ConnectionMode _selectedMode = ConnectionMode.wifi;
  bool _isPermissionGranted = false;
  bool _isLoading = true;
  Timer? _statsTimer;

  Offset? _focusTapPosition;
  Timer? _focusRingTimer;
  double _baseZoomScale = 1.0;

  @override
  void initState() {
    super.initState();
    _requestPermissionsAndInit();
  }

  Future<void> _requestPermissionsAndInit() async {
    final cameraStatus = await Permission.camera.request();
    await Permission.notification.request();

    if (cameraStatus.isGranted) {
      setState(() => _isPermissionGranted = true);
      await _cameraService.initialize();
      await _androidStreamer.startServer();

      _cameraService.onFrameAvailable = (jpegBytes, w, h) {
        if (_androidStreamer.isListening && _androidStreamer.clientCount > 0) {
          _androidStreamer.broadcastFrame(jpegBytes, w, h);
        }
      };

      _androidStreamer.onControlMessage = (msg) async {
        if (msg.action == 'switch_camera' && msg.lens != null) {
          await _switchCameraLensTo(msg.lens!);
        } else if (msg.action == 'set_resolution' && msg.quality != null) {
          await _cameraService.setQuality(msg.quality!);
          if (mounted) setState(() {});
        } else if (msg.action == 'start') {
          await _startStreaming();
        } else if (msg.action == 'stop') {
          await _stopStreaming();
        }
      };

      _statsTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
        if (mounted) setState(() {});
      });
    }

    setState(() => _isLoading = false);
  }

  Future<void> _switchCameraLens() async {
    if (_cameraService.isInitializing) return;

    final newLens = _cameraService.currentLens == CameraLens.back
        ? CameraLens.front
        : CameraLens.back;

    await _switchCameraLensTo(newLens);
  }

  Future<void> _switchCameraLensTo(CameraLens lens) async {
    if (_cameraService.isInitializing) return;

    setState(() {});
    await _cameraService.setLens(lens);
    if (mounted) setState(() {});
  }

  Future<void> _startStreaming() async {
    await _cameraService.startStreaming();
    if (mounted) setState(() {});
  }

  Future<void> _stopStreaming() async {
    await _cameraService.stopStreaming();
    if (mounted) setState(() {});
  }

  void _handleTapToFocus(TapUpDetails details, BoxConstraints constraints) {
    if (!_cameraService.isInitialized) return;

    final Offset offset = details.localPosition;
    final double relativeX = (offset.dx / constraints.maxWidth).clamp(0.0, 1.0);
    final double relativeY = (offset.dy / constraints.maxHeight).clamp(0.0, 1.0);

    _cameraService.setFocusPoint(Offset(relativeX, relativeY));

    setState(() {
      _focusTapPosition = offset;
    });

    _focusRingTimer?.cancel();
    _focusRingTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _focusTapPosition = null;
        });
      }
    });
  }

  Future<void> _openDeveloperSettings() async {
    try {
      await _platform.invokeMethod('openDeveloperSettings');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Open Settings -> System -> Developer Options manually.')),
        );
      }
    }
  }

  void _showUsbWizardDialog() {
    showDialog(
      context: context,
      builder: (ctx) => DefaultTabController(
        length: 5,
        child: AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: AppColors.surfaceBorder),
          ),
          title: const Row(
            children: [
              Icon(Icons.usb, color: AppColors.primaryAccent),
              SizedBox(width: 8),
              Text('USB Debugging Guide', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: 380,
            child: Column(
              children: [
                const TabBar(
                  isScrollable: true,
                  labelColor: AppColors.primaryAccent,
                  unselectedLabelColor: AppColors.textSecondary,
                  indicatorColor: AppColors.primaryAccent,
                  tabs: [
                    Tab(text: 'Samsung'),
                    Tab(text: 'Xiaomi / Redmi'),
                    Tab(text: 'Vivo / Oppo / Realme'),
                    Tab(text: 'OnePlus'),
                    Tab(text: 'Pixel / Stock'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _buildBrandGuide(
                        'Samsung',
                        '1. Open Settings -> About Phone -> Software Information.\n'
                        '2. Tap "Build Number" 7 times until Developer Mode is enabled.\n'
                        '3. Go back to Settings -> Developer Options.\n'
                        '4. Toggle ON "USB Debugging".',
                      ),
                      _buildBrandGuide(
                        'Xiaomi / Redmi / Poco',
                        '1. Open Settings -> About Phone.\n'
                        '2. Tap "MIUI Version" / "HyperOS Version" 7 times.\n'
                        '3. Go to Settings -> Additional Settings -> Developer Options.\n'
                        '4. Toggle ON "USB Debugging" & "USB Debugging (Security Settings)".',
                      ),
                      _buildBrandGuide(
                        'Vivo / Oppo / Realme / iQOO',
                        '1. Open Settings -> About Phone / About Device -> Version Info.\n'
                        '2. Tap "Build Number" 7 times.\n'
                        '3. Go to Settings -> System / Additional Settings -> Developer Options.\n'
                        '4. Toggle ON "USB Debugging".',
                      ),
                      _buildBrandGuide(
                        'OnePlus',
                        '1. Open Settings -> About Device -> Version.\n'
                        '2. Tap "Build Number" 7 times.\n'
                        '3. Go to Settings -> System Settings -> Developer Options.\n'
                        '4. Toggle ON "USB Debugging".',
                      ),
                      _buildBrandGuide(
                        'Google Pixel / Stock Android',
                        '1. Open Settings -> About Phone.\n'
                        '2. Scroll down and tap "Build Number" 7 times.\n'
                        '3. Go back to Settings -> System -> Developer Options.\n'
                        '4. Toggle ON "USB Debugging".',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, size: 20, color: AppColors.warning),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Allow USB Debugging: When prompt appears on phone, check "Always allow from this computer" and tap Allow.',
                          style: TextStyle(fontSize: 11, color: AppColors.textPrimary),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            OutlinedButton.icon(
              icon: const Icon(Icons.settings, size: 16),
              label: const Text('Open Settings'),
              onPressed: () {
                Navigator.pop(ctx);
                _openDeveloperSettings();
              },
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryAccent, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Got It'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBrandGuide(String brand, String steps) {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(brand, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          Text(steps, style: const TextStyle(fontSize: 13, height: 1.4, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _focusRingTimer?.cancel();
    _statsTimer?.cancel();
    _cameraService.dispose();
    _androidStreamer.stopServer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppColors.primaryAccent)),
      );
    }

    if (!_isPermissionGranted) {
      return Scaffold(
        appBar: AppBar(title: const Text('PhoneCam')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.camera_alt, size: 64, color: AppColors.primaryAccent),
              const SizedBox(height: 16),
              const Text('Camera permission is required to stream video.', style: TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryAccent, foregroundColor: Colors.white),
                onPressed: _requestPermissionsAndInit,
                child: const Text('Grant Camera Permission'),
              ),
            ],
          ),
        ),
      );
    }

    final isCameraReady = _cameraService.isInitialized && !_cameraService.isInitializing;
    final ent = _subService.currentEntitlements;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12.0,
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videocam_rounded, color: AppColors.primaryAccent, size: 24),
            SizedBox(width: 6),
            Flexible(
              child: Text(
                'PhoneCam',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
          ],
        ),
        actions: [
          // Subscription / Pro Badge Action
          InkWell(
            onTap: () {
              if (!_subService.isLoggedIn) {
                SubscriptionDialogs.showAuthDialog(context, onSuccess: () {
                  setState(() {});
                });
              } else {
                SubscriptionDialogs.showSubscriptionUpgradeSheet(context, onUpdated: () {
                  setState(() {});
                });
              }
            },
            borderRadius: BorderRadius.circular(20),
            child: Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: ent?.hasProAccess == true
                    ? AppColors.success.withValues(alpha: 0.15)
                    : AppColors.primaryAccent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: ent?.hasProAccess == true ? AppColors.success : AppColors.primaryAccent,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    ent?.hasProAccess == true ? Icons.workspace_premium_rounded : Icons.bolt_rounded,
                    size: 13,
                    color: ent?.hasProAccess == true ? AppColors.success : AppColors.primaryAccent,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    ent?.accessReason == "active_subscription"
                        ? "PRO"
                        : (ent?.accessReason == "trial"
                            ? "TRIAL"
                            : "PRO"),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                      color: ent?.hasProAccess == true ? AppColors.success : AppColors.primaryAccent,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // User Profile / Account Icon (Replaces former linked-devices laptop icon)
          IconButton(
            icon: const Icon(Icons.person_rounded, color: AppColors.textPrimary, size: 22),
            onPressed: () {
              if (AuthApiService.instance.isAuthenticated || _subService.isLoggedIn) {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ProfileScreen()),
                );
              } else {
                SubscriptionDialogs.showAuthDialog(context, onSuccess: () {
                  setState(() {});
                });
              }
            },
            tooltip: 'Account Profile',
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Mode Selector
              SegmentedButton<ConnectionMode>(
                segments: const [
                  ButtonSegment(
                    value: ConnectionMode.wifi,
                    label: Text('Wi-Fi (Recommended)'),
                    icon: Icon(Icons.wifi),
                  ),
                  ButtonSegment(
                    value: ConnectionMode.usb,
                    label: Text('USB Mode'),
                    icon: Icon(Icons.usb),
                  ),
                ],
                selected: {_selectedMode},
                onSelectionChanged: (Set<ConnectionMode> selected) {
                  setState(() => _selectedMode = selected.first);
                },
              ),
              const SizedBox(height: 16),

              // Camera Preview Card
              Card(
                clipBehavior: Clip.antiAlias,
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: isCameraReady
                      ? LayoutBuilder(
                          builder: (ctx, constraints) {
                            return GestureDetector(
                              onScaleStart: (details) {
                                _baseZoomScale = _cameraService.currentZoom;
                              },
                              onScaleUpdate: (details) {
                                final newZoom = _baseZoomScale * details.scale;
                                _cameraService.setZoomLevel(newZoom);
                                setState(() {});
                              },
                              onTapUp: (details) => _handleTapToFocus(details, constraints),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  Transform(
                                    alignment: Alignment.center,
                                    transform: Matrix4.rotationY(_cameraService.isMirrored ? 3.14159 : 0),
                                    child: CameraPreview(_cameraService.controller!),
                                  ),

                                  // Visual Focus Ring Target
                                  if (_focusTapPosition != null)
                                    Positioned(
                                      left: _focusTapPosition!.dx - 24,
                                      top: _focusTapPosition!.dy - 24,
                                      child: Container(
                                        width: 48,
                                        height: 48,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(color: AppColors.primaryAccent, width: 2),
                                        ),
                                        child: const Icon(Icons.center_focus_weak, color: AppColors.primaryAccent, size: 28),
                                      ),
                                    ),

                                  // Top Controls Overlay (Torch, Mirror, Switch Lens)
                                  Positioned(
                                    top: 8,
                                    right: 8,
                                    child: Column(
                                      children: [
                                        IconButton.filledTonal(
                                          style: IconButton.styleFrom(
                                            backgroundColor: AppColors.surface.withValues(alpha: 0.8),
                                          ),
                                          icon: _cameraService.isInitializing
                                              ? const SizedBox(
                                                  width: 18,
                                                  height: 18,
                                                  child: CircularProgressIndicator(color: AppColors.primaryAccent, strokeWidth: 2),
                                                )
                                              : const Icon(Icons.switch_camera, color: AppColors.textPrimary),
                                          onPressed: _cameraService.isInitializing ? null : _switchCameraLens,
                                          tooltip: 'Switch Camera',
                                        ),
                                        const SizedBox(height: 8),
                                        IconButton.filledTonal(
                                          style: IconButton.styleFrom(
                                            backgroundColor: _cameraService.isTorchOn
                                                ? AppColors.primaryAccent.withValues(alpha: 0.9)
                                                : AppColors.surface.withValues(alpha: 0.8),
                                          ),
                                          icon: Icon(
                                            _cameraService.isTorchOn ? Icons.flash_on : Icons.flash_off,
                                            color: _cameraService.isTorchOn ? Colors.white : AppColors.textPrimary,
                                          ),
                                          onPressed: _cameraService.hasTorch
                                              ? () async {
                                                  await _cameraService.toggleTorch();
                                                  setState(() {});
                                                }
                                              : null,
                                          tooltip: 'Toggle Flashlight',
                                        ),
                                        const SizedBox(height: 8),
                                        IconButton.filledTonal(
                                          style: IconButton.styleFrom(
                                            backgroundColor: AppColors.surface.withValues(alpha: 0.8),
                                          ),
                                          icon: Icon(
                                            _cameraService.isMirrored ? Icons.flip : Icons.crop_free,
                                            color: AppColors.textPrimary,
                                          ),
                                          onPressed: () {
                                            _cameraService.toggleMirror();
                                            setState(() {});
                                          },
                                          tooltip: 'Toggle Mirror',
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Bottom Zoom Badge Pill
                                  Positioned(
                                    bottom: 8,
                                    left: 8,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(alpha: 0.7),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        '${_cameraService.currentZoom.toStringAsFixed(1)}x Zoom',
                                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        )
                      : Container(
                          color: AppColors.surfaceContainer,
                          child: const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                CircularProgressIndicator(color: AppColors.primaryAccent),
                                SizedBox(height: 12),
                                Text(
                                  'Switching Camera...',
                                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 12),

              // Zoom Control Bar
              if (isCameraReady && _cameraService.maxZoom > _cameraService.minZoom)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                    child: Row(
                      children: [
                        const Icon(Icons.zoom_in, size: 18, color: AppColors.primaryAccent),
                        const SizedBox(width: 8),
                        // Quick Zoom Chips
                        ...[1.0, 2.0, 3.0].where((z) => z <= _cameraService.maxZoom).map((z) {
                          final isSelected = (_cameraService.currentZoom - z).abs() < 0.2;
                          return Padding(
                            padding: const EdgeInsets.only(right: 6.0),
                            child: InkWell(
                              onTap: () {
                                _cameraService.setZoomLevel(z);
                                setState(() {});
                              },
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: isSelected ? AppColors.primaryAccent : AppColors.surfaceContainer,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '${z.toInt()}x',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: isSelected ? Colors.white : AppColors.textSecondary,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                        Expanded(
                          child: SliderTheme(
                            data: SliderThemeData(
                              trackHeight: 3,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                              activeTrackColor: AppColors.primaryAccent,
                              inactiveTrackColor: AppColors.surfaceBorder,
                              thumbColor: AppColors.primaryAccent,
                            ),
                            child: Slider(
                              value: _cameraService.currentZoom.clamp(_cameraService.minZoom, _cameraService.maxZoom),
                              min: _cameraService.minZoom,
                              max: _cameraService.maxZoom,
                              onChanged: (val) {
                                _cameraService.setZoomLevel(val);
                                setState(() {});
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 12),

              // Resolution & FPS Pickers Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Resolution', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                          DropdownButton<StreamQuality>(
                            value: _cameraService.currentQuality,
                            dropdownColor: AppColors.surfaceContainer,
                            style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.bold),
                            underline: const SizedBox(),
                            items: StreamQuality.values.map((q) {
                              return DropdownMenuItem(value: q, child: Text(q.label));
                            }).toList(),
                            onChanged: _cameraService.isInitializing
                                ? null
                                : (q) async {
                                    if (q != null) {
                                      setState(() {});
                                      await _cameraService.setQuality(q);
                                      if (mounted) setState(() {});
                                    }
                                  },
                          ),
                        ],
                      ),
                      Container(height: 30, width: 1, color: AppColors.surfaceBorder),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('FPS Target', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                          DropdownButton<int>(
                            value: _cameraService.currentFps,
                            dropdownColor: AppColors.surfaceContainer,
                            style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.bold),
                            underline: const SizedBox(),
                            items: const [
                              DropdownMenuItem(value: 24, child: Text('24 FPS')),
                              DropdownMenuItem(value: 30, child: Text('30 FPS')),
                              DropdownMenuItem(value: 60, child: Text('60 FPS')),
                            ],
                            onChanged: (fps) {
                              if (fps != null) {
                                setState(() => _cameraService.currentFps = fps);
                              }
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Connection Details Card
              Card(
                color: AppColors.surfaceContainer,
                child: Padding(
                  padding: const EdgeInsets.all(14.0),
                  child: _selectedMode == ConnectionMode.wifi
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: QrImageView(
                                data: _androidStreamer.qrPayload,
                                version: QrVersions.auto,
                                size: 88.0,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Row(
                                    children: [
                                      Icon(Icons.wifi, size: 16, color: AppColors.success),
                                      SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          'Wi-Fi Pairing',
                                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textPrimary),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'IP: ${_androidStreamer.localIp}:${_androidStreamer.port}',
                                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: AppColors.secondaryAccent.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: AppColors.secondaryAccent.withValues(alpha: 0.4)),
                                    ),
                                    child: Text(
                                      'PIN: ${_androidStreamer.pairingToken}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                        color: AppColors.secondaryAccent,
                                        letterSpacing: 0.8,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.usb, color: AppColors.primaryAccent),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'USB Connection Mode',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textPrimary),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              '1. Connect phone to PC using USB cable.\n'
                              '2. Enable USB Debugging in Developer Options.\n'
                              '3. Open PhoneCam on Windows & click "Connect using USB".',
                              style: TextStyle(fontSize: 12, height: 1.4, color: AppColors.textSecondary),
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                OutlinedButton.icon(
                                  icon: const Icon(Icons.help_outline, size: 15),
                                  label: const Text('Open Setup Guide'),
                                  onPressed: _showUsbWizardDialog,
                                ),
                                OutlinedButton.icon(
                                  icon: const Icon(Icons.settings, size: 15),
                                  label: const Text('Settings'),
                                  onPressed: _openDeveloperSettings,
                                ),
                              ],
                            ),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 16),

              // Start / Stop Stream Action Button
              SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _cameraService.isStreaming ? AppColors.error : AppColors.primaryAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: Icon(_cameraService.isStreaming ? Icons.stop_rounded : Icons.play_arrow_rounded, size: 24),
                  label: Text(
                    _cameraService.isStreaming ? 'Stop Camera Stream' : 'Start Camera Stream',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, letterSpacing: 0.3),
                  ),
                  onPressed: () {
                    if (_cameraService.isStreaming) {
                      _stopStreaming();
                    } else {
                      _startStreaming();
                    }
                  },
                ),
              ),
              const SizedBox(height: 16),

              // Live Performance Metrics
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStatTile('FPS', _androidStreamer.stats.fps.toStringAsFixed(1)),
                      _buildStatTile('Bitrate', '${_androidStreamer.stats.throughputMbps.toStringAsFixed(2)} Mbps'),
                      _buildStatTile('Connected PC', '${_androidStreamer.stats.connectedClients}'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatTile(String label, String value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
      ],
    );
  }
}
