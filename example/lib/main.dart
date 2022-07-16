import 'dart:io';
import 'package:camera_with_files/camera_with_files.dart';
import 'package:example/video_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  MyAppState createState() => MyAppState();
}

class MyAppState extends State<MyApp> {
  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<File> files = [];
  bool isFullScreen = false;

  @override
  void initState() {
    super.initState();
    restoreUIBars();
  }

  void restoreUIBars() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: [
      // SystemUiOverlay.top,
      // SystemUiOverlay.bottom,
    ]);
  }

  void onTap(bool isFullScreen) async {
    files.clear();
    var data = await Navigator.of(context).push(
      MaterialPageRoute<List<File>>(
        builder: (_) => CameraApp(
          compressionQuality: 1.0,
          isMultipleSelection: false,
          showGallery: false,
          showOpenGalleryButton: false,
          isFullScreen: isFullScreen,
        ),
      ),
    );
    restoreUIBars();

    setState(() {
      files = data ?? [];
      this.isFullScreen = isFullScreen;
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (files.isNotEmpty)
                ...files.map<Widget>((e) {
                  if (isVideo(e.path)) {
                    return ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: size.width,
                        maxHeight: size.height,
                      ),
                      child: VideoPlayer(
                        videoFile: e,
                        key: ValueKey(e.path),
                        isFullScreen: isFullScreen,
                      ),
                    );
                  }

                  return SizedBox.fromSize(
                    key: ValueKey(e.path),
                    size: size,
                    child: Image.file(e, fit: BoxFit.contain),
                  );
                }).toList(),
              // if (files.isEmpty)
              Column(
                children: [
                  ElevatedButton(
                    onPressed: () => onTap(true),
                    child: const Text("Full screen"),
                  ),
                  ElevatedButton(
                    onPressed: () => onTap(false),
                    child: const Text("Cropped screen"),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
