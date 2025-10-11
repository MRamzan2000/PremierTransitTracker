import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:gallery_saver_plus/gallery_saver.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:open_file/open_file.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_tts/flutter_tts.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Permission.storage.request();
  runApp(const GenieFixAIApp());
}

class GenieFixAIApp extends StatelessWidget {
  const GenieFixAIApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  InAppWebViewController? webViewController;
  bool _isLoading = true;
  bool _hasInternet = true;
  final FlutterTts _flutterTts = FlutterTts();

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    _checkInternet();
    Connectivity().onConnectivityChanged.listen((_) => _checkInternet());
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.camera,
      Permission.microphone,
      Permission.storage,
      Permission.photos,
      Permission.videos,
    ].request();
  }

  Future<void> _checkInternet() async {
    final result = await Connectivity().checkConnectivity();
    if (result == ConnectivityResult.none) {
      setState(() => _hasInternet = false);
      return;
    }
    try {
      final lookup = await InternetAddress.lookup('google.com');
      if (lookup.isNotEmpty && lookup[0].rawAddress.isNotEmpty) {
        setState(() => _hasInternet = true);
      } else {
        setState(() => _hasInternet = false);
      }
    } on SocketException {
      setState(() => _hasInternet = false);
    }
  }

  Future<void> _downloadAndSaveFile(Uint8List bytes, String filename) async {
    try {
      final dir = Platform.isAndroid
          ? await getExternalStorageDirectory()
          : await getApplicationDocumentsDirectory();

      final filePath = '${dir!.path}/$filename';
      final file = File(filePath);
      await file.writeAsBytes(bytes);

      if (filename.endsWith('.jpg') ||
          filename.endsWith('.jpeg') ||
          filename.endsWith('.png')) {
        await GallerySaver.saveImage(file.path);
      }

      debugPrint('✅ File saved: $filePath');
      OpenFile.open(file.path);
    } catch (e) {
      debugPrint('❌ Save error: $e');
    }
  }

  Future<void> _downloadFromUrl(String url, String filename) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        await _downloadAndSaveFile(response.bodyBytes, filename);
      } else {
        debugPrint('❌ HTTP download failed: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ Download error: $e');
    }
  }

  Future<void> _handleDownload(InAppWebViewController controller, Uri uri) async {
    final url = uri.toString();

    // 🟡 Detect blob URLs
    if (url.startsWith("blob:")) {
      debugPrint("🟡 Blob detected, injecting JS to convert to base64...");

      const jsCode = """
        (async function() {
          try {
            const blobUrl = arguments[0];
            const response = await fetch(blobUrl);
            const blob = await response.blob();
            const reader = new FileReader();
            reader.onloadend = function() {
              window.flutter_inappwebview.callHandler('blobDownload', reader.result);
            };
            reader.readAsDataURL(blob);
          } catch (e) {
            console.error("Blob convert error:", e);
            window.flutter_inappwebview.callHandler('blobDownload', null);
          }
        })();
      """;

      controller.evaluateJavascript(source: jsCode.replaceAll("arguments[0]", "'$url'"));
    } else {
      debugPrint("⬇️ Direct file URL detected: $url");
      await _downloadFromUrl(url, url.split('/').last);
    }
  }

  Future<void> _speakText(String text) async {
    try {
      await _flutterTts.setLanguage("en-US");
      await _flutterTts.setSpeechRate(0.5);
      await _flutterTts.speak(text);
    } catch (e) {
      debugPrint('🔈 TTS error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff1d1c36),
      body: !_hasInternet
          ? _buildNoInternetScreen()
          : Stack(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 30),
            child: InAppWebView(
              initialUrlRequest: URLRequest(
                url: WebUri("https://geniefixai.live/"),
              ),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                allowFileAccessFromFileURLs: true,
                allowUniversalAccessFromFileURLs: true,
                mediaPlaybackRequiresUserGesture: false,
                allowsInlineMediaPlayback: true,
                supportZoom: false,
                useOnDownloadStart: true,
                geolocationEnabled: true,
                mixedContentMode:
                MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
              ),
              onWebViewCreated: (controller) {
                webViewController = controller;

                // ✅ Add blob handler
                controller.addJavaScriptHandler(
                  handlerName: 'blobDownload',
                  callback: (args) async {
                    if (args.isEmpty || args.first == null) {
                      debugPrint('❌ Failed to get blob base64.');
                      return;
                    }

                    final dataUrl = args.first as String;
                    final base64Data = dataUrl.split(',').last;
                    final bytes = base64Decode(base64Data);
                    await _downloadAndSaveFile(
                        bytes, 'download_${DateTime.now().millisecondsSinceEpoch}.jpg');
                  },
                );

                // ✅ TTS bridge
                controller.addJavaScriptHandler(
                  handlerName: 'flutter_tts',
                  callback: (args) {
                    if (args.isNotEmpty) _speakText(args[0]);
                    return null;
                  },
                );
              },
              onDownloadStartRequest:
                  (controller, downloadStartRequest) async {
                debugPrint("onDownloadStart: ${downloadStartRequest.url}");
                await _handleDownload(
                    controller, downloadStartRequest.url);
              },
              onPermissionRequest: (controller, request) async {
                return PermissionResponse(
                  resources: request.resources,
                  action: PermissionResponseAction.GRANT,
                );
              },
              onGeolocationPermissionsShowPrompt:
                  (controller, origin) async {
                return GeolocationPermissionShowPromptResponse(
                  origin: origin,
                  allow: true,
                  retain: true,
                );
              },
              onLoadStart: (controller, url) {
                setState(() => _isLoading = true);
              },
              onLoadStop: (controller, url) {
                setState(() => _isLoading = false);
              },
              onConsoleMessage: (controller, consoleMessage) {
                debugPrint("Console: ${consoleMessage.message}");
              },
            ),
          ),
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
        ],
      ),
    );
  }

  Widget _buildNoInternetScreen() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.wifi_off, color: Colors.white, size: 80),
          const SizedBox(height: 20),
          const Text(
            "No Internet Connection",
            style: TextStyle(color: Colors.white, fontSize: 20),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () async {
              await _checkInternet();
              if (_hasInternet) webViewController?.reload();
            },
            child: const Text("Retry"),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _flutterTts.stop();
    super.dispose();
  }
}
