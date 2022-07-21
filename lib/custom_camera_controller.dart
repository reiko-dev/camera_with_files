import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:camera_with_files/permission_state.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gallery_saver/gallery_saver.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:photo_gallery/photo_gallery.dart';
import 'package:video_player/video_player.dart';

class InheritedCameraController extends InheritedWidget {
  const InheritedCameraController(
      {super.key, required super.child, required this.data});

  final CustomCameraController data;

  static CustomCameraController of(BuildContext context) {
    final camWithFiles =
        context.dependOnInheritedWidgetOfExactType<InheritedCameraController>();

    if (camWithFiles == null) {
      throw ("Couldn't find a CameraWithFiles on the Widgets Tree");
    }

    return camWithFiles.data;
  }

  @override
  bool updateShouldNotify(covariant InheritedWidget oldWidget) => false;
}

class CustomCameraController extends ChangeNotifier {
  CustomCameraController({
    bool isMultipleSelection = false,
    double compressionQuality = 1,
    this.cameraResolution = ResolutionPreset.max,
    this.isFullScreen = false,
    this.storeOnGallery = false,
    this.directoryName,
  }) {
    assert(
      compressionQuality > 0 && compressionQuality <= 1,
      "compressionQuality value must be bettwen 0 (exclusive) and 1 (inclusive)",
    );
    if (storeOnGallery) {
      assert(
        directoryName != null,
        "To store the file in a public folder you have pass a  directory name",
      );
    }

    this.compressionQuality = (compressionQuality * 100).toInt();
    this.isMultipleSelection.value = isMultipleSelection;

    _init();
  }

  //TODO: Allow multiple selection
  final isMultipleSelection = ValueNotifier(false);

  // Related to Gallery media listing
  var selectedIndexes = ValueNotifier<List<int>>([]);
  var imageMedium = ValueNotifier<Set<Medium>>({});
  var isExpandedPicturesPanel = ValueNotifier(false);
  var count = ValueNotifier<int>(0);
  List<Album> imageAlbums = [];
  int pageIndex = 1;
  int pageCount = 10;
  final imagesCarouselController = ScrollController();

  // Camera related
  final controller = ValueNotifier<CameraController?>(null);
  final isFlashOn = ValueNotifier(false);
  late final int compressionQuality;
  final cameras = ValueNotifier<List<CameraDescription>>([]);
  static int currentCameraIndex = 0;
  final ResolutionPreset cameraResolution;
  File? image;
  final bool isFullScreen;

  //Video related
  VideoPlayerController? videoController;
  VoidCallback? videoPlayerListener;
  File? videoFile;

  //Video Duration Related
  //Trigger the UI update
  final timeInSeconds = ValueNotifier<int?>(null);
  int currentTimeInMilliseconds = 0;
  static const timerIntervalInMilliseconds = 17;
  bool cancelTimer = false;
  Timer? timer;

  // Storage related
  /// The directory name to be used for storing the files if [storeOnGallery] is true.
  ///
  String? directoryName;

  // Permission related
  bool _isAskingPermission = false;
  bool storeOnGallery = false;
  final hasCameraPermission = ValueNotifier(false);
  var _micPermissionState = PermissionState.notAsked;
  // Required for storing media on the documents folder
  var _storagePermissionState = PermissionState.notAsked;
  var _iosPhotosPermissionState = PermissionState.notAsked;
  // This variable is necessary for avoiding errors when updating the cameraValue synchronized with the Lifecycle events
  // Because on the initialization and on the lifecycle we can have concurrent calls to the updateCamera method.
  bool _isUpdatingCamera = false;

  Future<void> _init() async {
    if (!await _loadCameras()) return;
    hasCameraPermission.value =
        await _requestPermission(Permission.camera) == PermissionState.granted;

    if (!hasCameraPermission.value) return;

    _micPermissionState = await _requestPermission(Permission.microphone);

    if (controller.value == null) {
      await _updateSelectedCamera();
    }

    _loadImages();

    imagesCarouselController.addListener(() {
      if (!imagesCarouselController.hasClients) return;

      if (imagesCarouselController.position.atEdge) {
        bool isTop = imagesCarouselController.position.pixels == 0;
        if (!isTop) {
          if (imageMedium.value.length > (pageCount * pageIndex)) {
            pageIndex++;

            if (pageCount * (pageIndex) > imageMedium.value.length) {
              count.value = imageMedium.value.length;
            } else {
              count.value = pageCount * pageIndex;
            }
          }
        }
      }
    });
  }

  /// Load the list of available cameras of the device
  Future<bool> _loadCameras() async {
    cameras.value = await availableCameras();
    if (cameras.value.isEmpty) {
      _showCameraException(
          "Not found camera on this device.", "CAMERA_NOT_FOUND");
      return false;
    }
    return true;
  }

  @override
  void dispose() {
    isMultipleSelection.dispose();
    selectedIndexes.dispose();
    imageMedium.dispose();

    controller.dispose();

    isFlashOn.dispose();
    isExpandedPicturesPanel.dispose();
    count.dispose();
    cameras.dispose();

    videoController?.dispose();

    imagesCarouselController.dispose();

    //Duration Timer related
    timeInSeconds.dispose();
    timer?.cancel();
    super.dispose();
  }

  bool get isTakingPicture => controller.value?.value.isTakingPicture == true;

  void updatedLifecycle(AppLifecycleState state) async {
    if (_isAskingPermission) return;

    final CameraController? oldController = controller.value;

    // App state changed before we got the chance to initialize.
    if (oldController != null && !oldController.value.isInitialized ||
        !hasCameraPermission.value) {
      return;
    }

    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
        releaseCamera();
        break;

      case AppLifecycleState.resumed:
        _updateSelectedCamera(cameraDescription: oldController?.description);
        break;

      default:
        break;
    }
  }

  Future<void> releaseCamera() async {
    if (controller.value == null) return;

    if (_isRecordingVideo) {
      await stopVideoRecording();
    }
    //Disposing the oldCamera
    final CameraController? oldController = controller.value;
    controller.value = null;
    await oldController?.dispose();
  }

  bool get _isRecordingVideo {
    if (controller.value == null) return false;

    return controller.value!.value.isRecordingVideo;
  }

  Future<void> _updateSelectedCamera(
      {CameraDescription? cameraDescription}) async {
    if (cameras.value.isEmpty) return;

    if (_isUpdatingCamera) return;

    _isUpdatingCamera = true;
    await releaseCamera();

    //Instantiate a new camera
    final cameraController = CameraController(
      cameraDescription ?? cameras.value[currentCameraIndex],
      cameraResolution,
      imageFormatGroup: ImageFormatGroup.jpeg,
      enableAudio: _micPermissionState == PermissionState.granted,
    );

    // If the controller is updated then update the UI.
    cameraController.addListener(() {
      if (cameraController.value.hasError) {
        showInSnackBar(
          'Camera error ${cameraController.value.errorDescription}',
        );
      }
    });

    try {
      await cameraController.initialize();
      controller.value = cameraController;
      //TODO: This should be a function to update all the data like focus, resolution and so on.
      isFlashOn.value = controller.value!.value.flashMode != FlashMode.off;
      //
    } on CameraException catch (e) {
      switch (e.code) {
        case 'CameraAccessDenied':
          showInSnackBar('You have denied camera access.');
          break;
        case 'CameraAccessDeniedWithoutPrompt':
          // iOS only
          showInSnackBar('Please go to Settings app to enable camera access.');
          break;
        case 'CameraAccessRestricted':
          // iOS only
          showInSnackBar('Camera access is restricted.');
          break;
        case 'AudioAccessDenied':
          showInSnackBar('You have denied audio access.');
          break;
        case 'AudioAccessDeniedWithoutPrompt':
          // iOS only
          showInSnackBar('Please go to Settings app to enable audio access.');
          break;
        case 'AudioAccessRestricted':
          // iOS only
          showInSnackBar('Audio access is restricted.');
          break;
        case 'cameraPermission':
          // Android & web only
          showInSnackBar('Unknown permission error.');
          break;
        default:
          _showCameraException(e);
          break;
      }
    } finally {
      _isUpdatingCamera = false;
    }
  }

  void showInSnackBar(String message) {
    //TODO: add snackbar
    debugPrint("========\n$message");
  }

  // TODO: Extract to Usecase
  void _loadImages() async {
    if (kIsWeb) return;

    if (!await _canLoadImages) return;

    imageAlbums = await PhotoGallery.listAlbums(
      mediumType: MediumType.image,
    );

    for (var element in imageAlbums) {
      var data = await element.listMedia();
      imageMedium.value.addAll(data.items);
    }

    if (pageCount * (pageIndex) > imageMedium.value.length) {
      count.value = imageMedium.value.length;
    } else {
      count.value = pageCount * (pageIndex);
    }
  }

  Future<bool> get _canLoadImages async {
    bool hasPermission = false;
    if (Platform.isAndroid) {
      hasPermission = _storagePermissionState == PermissionState.granted;
    } else {
      hasPermission = _iosPhotosPermissionState == PermissionState.granted;
    }
    return hasPermission;
  }

  /// Request a permission with two conditions:
  /// 1. The permission wasn't asked before
  /// 2. There isn't another request being made at the same time.
  Future<PermissionState> _requestPermission(Permission permission) async {
    if (kIsWeb || _isAskingPermission) {
      return PermissionState.denied;
    }

    _isAskingPermission = true;

    if (await permission.isGranted) {
      _isAskingPermission = false;
      return PermissionState.granted;
    }

    try {
      return (await permission.request()).isGranted
          ? PermissionState.granted
          : PermissionState.denied;
    } catch (e) {
      debugPrint("PERMISSION_ERROR");
      debugPrint(e.toString());
      return PermissionState.denied;
    } finally {
      _isAskingPermission = false;
    }
  }

  Future<void> takePicture(double deviceAspectRatio) async {
    if (controller.value == null || controller.value!.value.isTakingPicture) {
      return;
    }

    try {
      await controller.value!.lockCaptureOrientation();
      XFile xfile = await controller.value!.takePicture();
      image = await _processImage(File(xfile.path), deviceAspectRatio);

      if (image != null) {
        _saveOnGallery(image!, isPicture: true);
      }
    } catch (e) {
      print(e);
    }

    if (kIsWeb) return;
  }

  /// This process is required to for cropping full screen pictures.
  // TODO: Extract to Usecase
  Future<File?> _processImage(
    File originalFile,
    double deviceAspectRatio,
  ) async {
    img.Image? processedImage;
    var originalImg = img.decodeJpg(await originalFile.readAsBytes());

    if (originalImg == null) return null;

    //The alternative solution here is to mirror the preview.
    if (cameras.value[currentCameraIndex].lensDirection ==
            CameraLensDirection.front &&
        Platform.isAndroid) {
      originalImg = img.flipHorizontal(originalImg);
    }

    if (isFullScreen) {
      final originalImgAspectRatio = originalImg.width / originalImg.height;

      if (originalImgAspectRatio > deviceAspectRatio) {
        //Imagem capturada é mais larga que o viewport.
        //Manter altura e cortar largura
        final newWidthScale =
            (deviceAspectRatio * originalImg.height) / originalImg.width;

        final newWidth = originalImg.width * newWidthScale;

        final cropSize = originalImg.width - newWidth;

        processedImage = img.copyCrop(
          originalImg,
          cropSize ~/ 2,
          0,
          newWidth.toInt(),
          originalImg.height,
        );
      } else {
        //Imagem capturada é mais comprida que o viewport.
        //Manter largura e cortar altura
        final newHeightScale =
            (originalImg.width / deviceAspectRatio) / originalImg.height;

        final newHeight = originalImg.height * newHeightScale;

        final cropSize = originalImg.height - newHeight;

        processedImage = img.copyCrop(
          originalImg,
          0,
          cropSize ~/ 2,
          originalImg.width,
          newHeight.toInt(),
        );
      }
    } else {
      processedImage = originalImg;
    }
    final paths = split(originalFile.path);
    final fileExtension = extension(originalFile.path, 1);
    paths.removeRange(paths.length - 2, paths.length);
    String currentTime = DateTime.now().millisecondsSinceEpoch.toString();
    final finalPath = joinAll([...paths, currentTime]) + fileExtension;
    return File(finalPath)
      ..create()
      ..writeAsBytesSync(
        img.encodeJpg(processedImage),
      );
  }

  // TODO: Extract to Usecase
  Future<File?> _saveOnGallery(File file, {bool isPicture = false}) async {
    if (!storeOnGallery) {
      return null;
    }

    late final bool hasPermission;
    if (Platform.isAndroid) {
      _storagePermissionState = await _requestPermission(Permission.storage);

      hasPermission = _storagePermissionState == PermissionState.granted;
    } else {
      _iosPhotosPermissionState = await _requestPermission(Permission.photos);
      hasPermission = _iosPhotosPermissionState == PermissionState.granted;
    }

    if (!hasPermission) {
      return null;
    }

    bool? result;
    if (isPicture) {
      result = await GallerySaver.saveImage(file.path, albumName: "sidestory");
    } else {
      result = await GallerySaver.saveVideo(file.path, albumName: "sidestory");
    }

    if (result != null && result) {
      print("success!");
    } else {
      print("Error!");
    }

    return file;
  }

  Future<Directory?> get _filesDirectory async {
    if (Platform.isAndroid &&
        _storagePermissionState == PermissionState.granted) {
      return await getExternalStorageDirectory();
    } else {
      if (_iosPhotosPermissionState == PermissionState.granted) {
        return await getApplicationDocumentsDirectory();
      }
    }
    return null;
  }

  void switchCamera() {
    if (currentCameraIndex + 1 >= cameras.value.length) {
      currentCameraIndex = 0;
    } else {
      currentCameraIndex++;
    }

    _updateSelectedCamera();
  }

  void toggleFlash() {
    if (isFlashOn.value) {
      controller.value!.setFlashMode(FlashMode.off);
    } else {
      controller.value!.setFlashMode(FlashMode.always);
    }

    isFlashOn.value = controller.value!.value.flashMode != FlashMode.off;
  }

  Future<void> startVideoRecording() async {
    final CameraController? cameraController = controller.value;

    if (cameraController == null || !cameraController.value.isInitialized) {
      debugPrint('Error: select a camera first.');
      return;
    }

    if (cameraController.value.isRecordingVideo) {
      // A recording is already started, do nothing.
      return;
    }

    try {
      await cameraController.startVideoRecording();
      _startDurationTimer();
    } on CameraException catch (e) {
      _showCameraException(e);
      return;
    }
  }

  Future<void> stopVideoRecording() async {
    final CameraController? cameraController = controller.value;

    XFile? result;
    if (cameraController == null || !cameraController.value.isRecordingVideo) {
      result = null;
    } else {
      try {
        result = await cameraController.stopVideoRecording();
      } on CameraException catch (e) {
        _showCameraException(e, "ERROR STOPPING THE RECORDING");
        result = null;
      }
    }

    _cancelDurationTimer();
    if (result != null) {
      final file = File(result.path);
      videoFile = file;
      await _saveOnGallery(file);
    }
  }

  Future<void> pauseVideoRecording() async {
    final CameraController? cameraController = controller.value;

    if (cameraController == null || !cameraController.value.isRecordingVideo) {
      return;
    }

    try {
      await cameraController.pauseVideoRecording();
    } on CameraException catch (e) {
      _showCameraException(e);
      rethrow;
    }
  }

  Future<void> resumeVideoRecording() async {
    final CameraController? cameraController = controller.value;

    if (cameraController == null || !cameraController.value.isRecordingVideo) {
      return;
    }

    try {
      await cameraController.resumeVideoRecording();
    } on CameraException catch (e) {
      _showCameraException(e);
      rethrow;
    }
  }

  void _showCameraException(dynamic e, [String? tag]) {
    if (tag != null) {
      debugPrint(tag);
    }

    //TODO: add other cases of exceptions
    switch (e.runtimeType) {
      case CameraException:
        debugPrint((e as CameraException).code);
        debugPrint(e.description);
        break;
      default:
    }
  }

  // TODO: Extract to Usecase
  /// Returns the String representation of the video duration.
  String get videoDuration {
    if (timeInSeconds.value == null) return "";

    final int minutes = (timeInSeconds.value! ~/ 60);
    final int seconds = (timeInSeconds.value! - 60 * minutes);

    String result = minutes.toString().padLeft(2, "0");
    result += ":";
    result += seconds.toString().padLeft(2, "0");
    return result;
  }

  void _startDurationTimer() {
    if (timer != null) return;

    timer = Timer.periodic(
        const Duration(milliseconds: timerIntervalInMilliseconds), (t) {
      if (cancelTimer) {
        t.cancel();
        timer = null;
      } else {
        currentTimeInMilliseconds += timerIntervalInMilliseconds;
        final currentTimeInSeconds = currentTimeInMilliseconds ~/ 1000;

        if (timeInSeconds.value == null ||
            currentTimeInSeconds > timeInSeconds.value!) {
          timeInSeconds.value = currentTimeInSeconds;
        }
      }
    });
  }

  void _cancelDurationTimer() {
    cancelTimer = true;
    timer?.cancel();
    timer = null;
    timeInSeconds.value = null;
  }

  void addToSelection(int index) async {
    if (!isMultipleSelection.value && selectedIndexes.value.isNotEmpty) {
      return;
    }

    if (selectedIndexes.value.contains(index)) {
      selectedIndexes.value.remove(index);
    } else {
      selectedIndexes.value.add(index);
    }

    selectedIndexes.notifyListeners();
  }
}
