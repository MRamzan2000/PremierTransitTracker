import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:gallery_saver_plus/gallery_saver.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'package:open_file/open_file.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ✅ Initialize AdMob once before runApp
  await MobileAds.instance.initialize();
  RequestConfiguration configuration = RequestConfiguration(
    testDeviceIds: ['E2CD3EF53E9A1A8FA16ABB08CCF30865'], // from your logs
  );
  MobileAds.instance.updateRequestConfiguration(configuration);
  await _requestInitialPermissions();
  runApp(const GenieFixAIApp());
}

Future<void> _requestInitialPermissions() async {
  await [
    Permission.camera,
    Permission.microphone,
    Permission.storage,
    Permission.photos,
    Permission.videos,
    Permission.audio,
    Permission.location,
  ].request();

  if (await Permission.microphone.isDenied ||
      await Permission.microphone.isPermanentlyDenied) {
    await Permission.microphone.request();
  }
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

  // ✅ Ad variables - App Open Ad, Banner Ad, and Interstitial Ad
  AppOpenAd? _appOpenAd;
  BannerAd? _bannerAd;
  InterstitialAd? _interstitialAd;
  Timer? _bannerRetryTimer;
  int _interactionCount = 0; // Track user interactions (e.g., page loads as proxy for content views/button actions)

  @override
  void initState() {
    super.initState();
    _checkInternet();
    Connectivity().onConnectivityChanged.listen((_) => _checkInternet());

    // ✅ Load ads asynchronously to avoid main thread blocking
    _initializeAds();
  }

  // ✅ Separate method to initialize ads asynchronously
  Future<void> _initializeAds() async {
    // Load App Open Ad
    await _loadAppOpenAd();

    // Load Banner Ad
    _loadBannerAd();

    // Load Interstitial Ad
    _loadInterstitialAd();
  }

  // ✅ App Open Ad - Show only on app launch (cold start)
  Future<void> _loadAppOpenAd() async {
    await AppOpenAd.load(
      adUnitId: 'ca-app-pub-5858445367250942/8620658486', // Original ID
      request: const AdRequest(),
      adLoadCallback: AppOpenAdLoadCallback(
        onAdLoaded: (ad) {
          _appOpenAd = ad;
          // Show immediately on app launch
          if (mounted) {
            _appOpenAd!.show();
          }
        },
        onAdFailedToLoad: (error) {
          debugPrint('❌ AppOpenAd failed: $error');
          _appOpenAd = null;
        },
      ),
    );
  }

  // ✅ Banner Ad - Bottom placement (Recommended) with retry on failure
  void _loadBannerAd() {
    _bannerAd?.dispose(); // Dispose previous if exists
    _bannerAd = BannerAd(
      adUnitId: 'ca-app-pub-5858445367250942/8293872343', // Original ID
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (mounted) {
            setState(() {}); // Refresh UI to show banner
          }
          debugPrint('✅ Banner Ad Loaded');
          // Cancel retry timer on success
          _bannerRetryTimer?.cancel();
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('❌ Banner Ad Failed: $error');
          ad.dispose();
          _bannerAd = null;
          if (mounted) {
            setState(() {}); // Refresh UI
          }
          // Schedule retry after 30 seconds
          if (_bannerRetryTimer?.isActive ?? false) {
            _bannerRetryTimer?.cancel();
          }
          _bannerRetryTimer = Timer(const Duration(seconds: 30), () {
            if (mounted) {
              debugPrint('🔄 Retrying Banner Ad load...');
              _loadBannerAd();
            }
          });
        },
      ),
    );
    _bannerAd!.load();
  }

  // ✅ Interstitial Ad - Load and show after every 3 interactions (e.g., page loads/content views)
  void _loadInterstitialAd() {
    _interstitialAd?.dispose();
    InterstitialAd.load(
      adUnitId: 'ca-app-pub-5858445367250942/8688941243', // Original ID
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          debugPrint('✅ Interstitial Ad Loaded');
        },
        onAdFailedToLoad: (error) {
          debugPrint('❌ Interstitial Ad Failed: $error');
          _interstitialAd = null;
        },
      ),
    );
  }

  void _maybeShowInterstitialAd() {
    _interactionCount++; // Increment on each page load (proxy for user action/content view)
    debugPrint('👆 Interaction count: $_interactionCount');

    // Show every 3 interactions (har 3-4 button clicks/content views ke baad)
    if (_interactionCount % 3 == 0 && _interstitialAd != null) {
      _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (ad) {
          debugPrint('⏹️ Interstitial Ad Dismissed');
          ad.dispose();
          _interstitialAd = null;
          // Reload for next time
          _loadInterstitialAd();
        },
        onAdFailedToShowFullScreenContent: (ad, error) {
          debugPrint('❌ Interstitial Ad Failed to Show: $error');
          ad.dispose();
          _interstitialAd = null;
          _loadInterstitialAd();
        },
        onAdImpression: (ad) => debugPrint('📊 Interstitial Ad Impression'),
      );
      _interstitialAd!.show();
    }
  }

  Future<void> _checkInternet() async {
    final result = await Connectivity().checkConnectivity();
    if (result == ConnectivityResult.none) {
      if (mounted) setState(() => _hasInternet = false);
      return;
    }
    try {
      final lookup = await InternetAddress.lookup('google.com');
      if (mounted) setState(() => _hasInternet = lookup.isNotEmpty);
    } on SocketException {
      if (mounted) setState(() => _hasInternet = false);
    }
  }

  Future<void> _ensureMicrophonePermission() async {
    final micStatus = await Permission.microphone.status;
    if (micStatus.isDenied || micStatus.isPermanentlyDenied) {
      await Permission.microphone.request();
    }
  }

  Future<Directory?> _selectDownloadDirectory(BuildContext context) async {
    return showDialog<Directory>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Select Download Location"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _locationButton("Downloads",
                      () async => Directory("/storage/emulated/0/Download")),
              _locationButton("Documents",
                      () async => Directory("/storage/emulated/0/Documents")),
              _locationButton("Pictures",
                      () async => Directory("/storage/emulated/0/Pictures")),
            ],
          ),
        );
      },
    );
  }

  Widget _locationButton(String label, Future<Directory> Function() onSelect) {
    return ListTile(
      title: Text(label),
      onTap: () async {
        final dir = await onSelect();
        if (context.mounted) Navigator.pop(context, dir);
      },
    );
  }

  Future<void> _downloadAndSaveFile(
      Uint8List bytes, String filename, Directory directory) async {
    try {
      final filePath = '${directory.path}/$filename';
      final file = File(filePath);
      await file.writeAsBytes(bytes);

      if (filename.toLowerCase().endsWith('.jpg') ||
          filename.toLowerCase().endsWith('.jpeg') ||
          filename.toLowerCase().endsWith('.png')) {
        await GallerySaver.saveImage(file.path);
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ File saved to: ${directory.path}'),
            backgroundColor: Colors.green,
          ),
        );
      }

      OpenFile.open(file.path);
    } catch (e) {
      debugPrint('❌ Save error: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Download failed: $e')),
        );
      }
    }
  }

  Future<void> _handleDownload(
      InAppWebViewController controller, Uri uri) async {
    final url = uri.toString();
    final fileName = url.split('/').last;

    // ✅ Handle base64 data URLs
    if (url.startsWith("data:")) {
      try {
        final parts = url.split(',');
        if (parts.length != 2) return;

        final mimeType = parts.first;
        final base64Data = parts.last;
        final bytes = base64Decode(base64Data);

        String ext = ".bin";
        if (mimeType.contains("pdf")) ext = ".pdf";
        else if (mimeType.contains("jpeg") || mimeType.contains("jpg")) ext = ".jpg";
        else if (mimeType.contains("png")) ext = ".png";

        final dir = await _selectDownloadDirectory(context);
        if (dir != null) {
          final safeFileName =
              'download_${DateTime.now().millisecondsSinceEpoch}$ext';
          await _downloadAndSaveFile(bytes, safeFileName, dir);
        }
      } catch (e) {
        debugPrint('❌ Data URL decode error: $e');
      }
      return;
    }

    // ✅ Handle blob URLs using JS
    if (url.startsWith("blob:")) {
      const jsCode = """
      (async function(blobUrl) {
        try {
          const response = await fetch(blobUrl);
          const blob = await response.blob();
          const reader = new FileReader();
          reader.onloadend = function() {
            window.flutter_inappwebview.callHandler('blobDownload', reader.result);
          };
          reader.readAsDataURL(blob);
        } catch (e) {
          window.flutter_inappwebview.callHandler('blobDownload', null);
        }
      })('%s');
      """;
      await controller.evaluateJavascript(source: jsCode.replaceAll('%s', url));
      return;
    }

    // ✅ Handle normal URLs
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final dir = await _selectDownloadDirectory(context);
        if (dir != null) {
          String ext = ".bin";
          final contentType = response.headers['content-type'] ?? "";
          if (contentType.contains("pdf")) ext = ".pdf";
          else if (contentType.contains("jpeg") || contentType.contains("jpg")) ext = ".jpg";
          else if (contentType.contains("png")) ext = ".png";

          final safeFileName = fileName.contains('.')
              ? fileName
              : 'download_${DateTime.now().millisecondsSinceEpoch}$ext';
          await _downloadAndSaveFile(response.bodyBytes, safeFileName, dir);
        }
      } else {
        debugPrint('❌ HTTP download failed: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ Download error: $e');
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

  Future<bool> _onWillPop() async {
    if (webViewController != null && await webViewController!.canGoBack()) {
      await webViewController!.goBack();
      return false;
    }
    bool? exitApp = await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Exit App?"),
        content: const Text("Do you want to close GenieFixAI?"),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancel")),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Exit")),
        ],
      ),
    );
    return exitApp ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        backgroundColor: const Color(0xff1d1c36),
        // ✅ Banner Ad at bottom - only show if loaded (Recommended placement)
        bottomNavigationBar: _bannerAd != null
            ? Container(
          height: _bannerAd!.size.height.toDouble(),
          width: _bannerAd!.size.width.toDouble(),
          child: AdWidget(ad: _bannerAd!),
        )
            : const SizedBox.shrink(),
        body: !_hasInternet
            ? _buildNoInternetScreen()
            : Stack(
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 30),
              child: Column(
                children: [
                  Expanded(
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
                        clearCache: false,
                      ),
                      onWebViewCreated: (controller) async {
                        webViewController = controller;
                        await _ensureMicrophonePermission();

                        controller.addJavaScriptHandler(
                          handlerName: 'blobDownload',
                          callback: (args) async {
                            if (args.isEmpty || args.first == null) return;
                            final dataUrl = args.first as String;
                            final base64Data = dataUrl.split(',').last;
                            final mimeType = dataUrl.split(';').first;

                            final bytes = base64Decode(base64Data);

                            final dir =
                            await _selectDownloadDirectory(context);
                            if (dir != null) {
                              String fileExt = ".bin";
                              if (mimeType.contains("application/pdf"))
                                fileExt = ".pdf";
                              else if (mimeType.contains("image/jpeg") ||
                                  mimeType.contains("image/jpg"))
                                fileExt = ".jpg";
                              else if (mimeType.contains("image/png"))
                                fileExt = ".png";
                              else if (mimeType.contains("text/html"))
                                fileExt = ".html"; // ✅ invoice blob

                              final fileName =
                                  "invoice_${DateTime.now().millisecondsSinceEpoch}$fileExt";
                              await _downloadAndSaveFile(
                                  bytes, fileName, dir);
                            }
                          },
                        );

                        controller.addJavaScriptHandler(
                          handlerName: 'flutter_tts',
                          callback: (args) {
                            if (args.isNotEmpty) _speakText(args[0]);
                            return null;
                          },
                        );
                      },
                      onDownloadStartRequest:
                          (controller, request) async {
                        await _handleDownload(controller, request.url);
                      },
                      onPermissionRequest:
                          (controller, request) async {
                        await _ensureMicrophonePermission();
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
                      onLoadStart: (controller, url) =>
                          setState(() => _isLoading = true),
                      onLoadStop: (controller, url) {
                        setState(() => _isLoading = false);
                        // ✅ Trigger interstitial check after content load (proxy for user action/view)
                        _maybeShowInterstitialAd();
                      },
                    ),
                  ),
                ],
              ),
            ),
            if (_isLoading)
              const Center(
                  child: CircularProgressIndicator(color: Colors.white)),
          ],
        ),
      ),
    );
  }

  Widget _buildNoInternetScreen() => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.wifi_off, color: Colors.white, size: 80),
        const SizedBox(height: 20),
        const Text("No Internet Connection",
            style: TextStyle(color: Colors.white, fontSize: 20)),
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

  @override
  void dispose() {
    _flutterTts.stop();
    _bannerRetryTimer?.cancel();
    _appOpenAd?.dispose();
    _bannerAd?.dispose();
    _interstitialAd?.dispose();
    super.dispose();
  }
}