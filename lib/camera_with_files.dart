library camera_with_files;

import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:camera_with_files/custom_camera_controller.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CameraApp extends StatefulWidget {
  const CameraApp({super.key, required this.controller});

  final CustomCameraController controller;

  @override
  State<CameraApp> createState() => _CameraAppState();
}

class _CameraAppState extends State<CameraApp> with WidgetsBindingObserver {
  late CustomCameraController controller = widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  void updateSystemUI() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: []);
  }

  @override
  void dispose() {
    controller.dispose();
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.restoreSystemUIOverlays();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    controller.updatedLifecycle(state);
    updateSystemUI();
  }

  /// Returns the current device Aspect Ratio accordingly to the camera AspectRatio
  double deviceAR(BuildContext context) {
    final deviceSize = MediaQuery.of(context).size;

    late double deviceAR;

    switch (MediaQuery.of(context).orientation) {
      case Orientation.landscape:
        deviceAR = deviceSize.aspectRatio;
        break;

      case Orientation.portrait:
        deviceAR = 1 / deviceSize.aspectRatio;
        break;
    }

    return deviceAR;
  }

  @override
  Widget build(BuildContext context) {
    return InheritedCameraController(
      data: controller,
      child: Builder(
        builder: (context) {
          controller = InheritedCameraController.of(context);
          return WillPopScope(
            onWillPop: () async {
              debugPrint("Show a dialog");
              return Future.value(true);
            },
            child: Scaffold(
              backgroundColor: const Color(0xFF8b8b8b),
              body: Stack(
                children: [
                  ValueListenableBuilder<CameraController?>(
                      valueListenable: controller.controller,
                      builder: (context, val, _) {
                        if (val == null ||
                            !val.value.isInitialized ||
                            val.value.hasError) {
                          return const SizedBox.shrink();
                        }

                        if (!controller.isFullScreen) {
                          return Center(child: CameraPreview(val));
                        }

                        final scale = deviceAR(context) / val.value.aspectRatio;

                        return Transform.scale(
                          scale: scale,
                          child: Center(child: CameraPreview(val)),
                        );
                      }),
                  ValueListenableBuilder<bool>(
                    valueListenable: controller.hasCameraPermission,
                    builder: (c, val, child) {
                      if (!val) {
                        return const Center(
                            child: Text("Camera permission not granted."));
                      }
                      return child!;
                    },
                    child: controller.isFullScreen
                        ? const FullScreenUI()
                        : const CroppedScreenUI(),
                  )
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class CroppedScreenUI extends StatelessWidget {
  const CroppedScreenUI({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Align(
          alignment: Alignment.bottomCenter,
          child: CroppedScreenBottomPanel(),
        ),
        SafeArea(
          child: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                height: 48,
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: SizedBox.square(
                          dimension: 48,
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            onPressed: Navigator.of(context).pop,
                            icon: const Icon(
                              Icons.close_rounded,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const Spacer(),
                    ],
                  ),
                ),
              )),
        ),
      ],
    );
  }
}

class CroppedScreenBottomPanel extends StatelessWidget {
  const CroppedScreenBottomPanel({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final controller = InheritedCameraController.of(context);

    return SizedBox(
      width: MediaQuery.of(context).size.width,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          DecoratedBox(
            decoration:
                BoxDecoration(color: const Color(0xFF333333).withOpacity(.34)),
            child: SizedBox(
              child: Column(
                children: [
                  const DurationCounter(
                    label: "Tap for photo, hold for video",
                    style: TextStyle(fontSize: 14),
                  ),

                  //Buttons panel
                  Padding(
                    padding: const EdgeInsets.only(
                        right: 8.0, left: 8.0, top: 12.0, bottom: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        //FLASH button
                        Expanded(
                          child: IconButton(
                            onPressed: controller.toggleFlash,
                            icon: ValueListenableBuilder<bool>(
                              valueListenable: controller.isFlashOn,
                              builder: (_, val, child) {
                                if (val) {
                                  return const Icon(
                                    Icons.flash_on,
                                    size: 30,
                                    color: Colors.white,
                                  );
                                }
                                return child!;
                              },
                              child: const Icon(
                                Icons.flash_off,
                                size: 30,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),

                        //Main action button
                        const Expanded(child: ActionButton()),

                        //Switch camera button
                        Expanded(
                          child:
                              ValueListenableBuilder<List<CameraDescription>>(
                            valueListenable: controller.cameras,
                            builder: (_, value, child) {
                              if (kIsWeb || value.length < 2) {
                                return const SizedBox.shrink();
                              }

                              return child!;
                            },
                            child: IconButton(
                              onPressed: controller.switchCamera,
                              icon: const Icon(
                                CupertinoIcons.camera_rotate_fill,
                                size: 30,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const Padding(
                    padding: EdgeInsets.only(top: 16, bottom: 16),
                    child: SizedBox(height: 18),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class FullScreenUI extends StatelessWidget {
  const FullScreenUI({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Align(
          alignment: Alignment.bottomCenter,
          child: FullScreenBottomPanel(),
        ),
        SafeArea(
          child: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: SizedBox.square(
                  dimension: 48,
                  child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF333333).withOpacity(.34),
                      ),
                      child: IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        padding: EdgeInsets.zero,
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                          size: 32,
                        ),
                      )),
                ),
              )),
        ),
      ],
    );
  }
}

class FullScreenBottomPanel extends StatelessWidget {
  const FullScreenBottomPanel({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final controller = InheritedCameraController.of(context);

    return SizedBox(
      width: MediaQuery.of(context).size.width,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          DecoratedBox(
            decoration:
                BoxDecoration(color: const Color(0xFF333333).withOpacity(.34)),
            child: SizedBox(
              child: Column(
                children: [
                  const DurationCounter(label: "Tap for photo, hold for video"),

                  //Buttons panel
                  Padding(
                    padding: const EdgeInsets.only(
                        right: 8.0, left: 8.0, top: 4.0, bottom: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        //FLASH button
                        Expanded(
                          child: IconButton(
                            onPressed: controller.toggleFlash,
                            icon: ValueListenableBuilder<bool>(
                              valueListenable: controller.isFlashOn,
                              builder: (_, val, child) {
                                if (val) {
                                  return const Icon(
                                    Icons.flash_on,
                                    size: 30,
                                    color: Colors.white,
                                  );
                                }
                                return child!;
                              },
                              child: const Icon(
                                Icons.flash_off,
                                size: 30,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),

                        //Main action button
                        const Expanded(child: ActionButton()),

                        //Switch camera button
                        Expanded(
                          child:
                              ValueListenableBuilder<List<CameraDescription>>(
                            valueListenable: controller.cameras,
                            builder: (_, value, child) {
                              if (kIsWeb || value.length < 2) {
                                return const SizedBox.shrink();
                              }

                              return child!;
                            },
                            child: IconButton(
                              onPressed: controller.switchCamera,
                              icon: const Icon(
                                CupertinoIcons.camera_rotate_fill,
                                size: 30,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
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
}

class DurationCounter extends StatelessWidget {
  const DurationCounter({Key? key, this.label, this.style}) : super(key: key);

  final TextStyle? style;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final controller = InheritedCameraController.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: ValueListenableBuilder<int?>(
        valueListenable: controller.timeInSeconds,
        builder: (c, val, _) {
          if (val == null) {
            return Text(
              label ?? "",
              style: const TextStyle(color: Colors.white, fontSize: 14)
                  .merge(style),
            );
          }

          return Text(
            controller.videoDuration,
            style:
                const TextStyle(color: Colors.white, fontSize: 14).merge(style),
          );
        },
      ),
    );
  }
}

class ActionButton extends StatefulWidget {
  const ActionButton({Key? key}) : super(key: key);

  @override
  State<ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<ActionButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController animationController;
  late final Animation<Decoration> decorationAnimation;

  @override
  void initState() {
    super.initState();
    animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      reverseDuration: const Duration(milliseconds: 60),
    );

    decorationAnimation = DecorationTween(
      begin: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [Colors.red, Colors.white],
          stops: [0, 0],
        ),
      ),
      end: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [Colors.red, Colors.white],
          stops: [1, 1],
        ),
      ),
    ).animate(animationController);
  }

  @override
  void dispose() {
    animationController.dispose();
    super.dispose();
  }

  void _stopVideo(CustomCameraController controller) async {
    animationController.reverse(from: 1);
    await controller.stopVideoRecording();

    if (controller.videoFile != null && mounted) {
      Navigator.of(context).pop(controller.videoFile as File);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = InheritedCameraController.of(context);

    return GestureDetector(
      onTap: () async {
        animationController.duration = const Duration(milliseconds: 300);
        animationController.forward();
        await controller.takePicture(MediaQuery.of(context).size.aspectRatio);

        if (mounted && !controller.isTakingPicture) {
          Navigator.of(context).pop(controller.image);
        }
      },
      onLongPress: () async {
        animationController.duration = const Duration(milliseconds: 600);
        animationController.forward(from: 0);
        await controller.startVideoRecording();
      },
      onLongPressEnd: (_) => _stopVideo(controller),
      onLongPressCancel: () => _stopVideo(controller),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white, width: 2),
          shape: BoxShape.circle,
        ),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Center(
            child: SizedBox.square(
              dimension: 52,
              child: DecoratedBoxTransition(
                decoration: decorationAnimation,
                child: const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
