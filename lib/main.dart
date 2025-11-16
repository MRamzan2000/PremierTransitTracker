import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:location/location.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PremierTaxiMeterApp());
}

class PremierTaxiMeterApp extends StatelessWidget {
  const PremierTaxiMeterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Premier Taxi Meter',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: Colors.black,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.yellow),
        scaffoldBackgroundColor: Colors.white,
        fontFamily: 'Roboto',
      ),
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Timer(const Duration(seconds: 2), () {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MainNavigation()),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/logo.png',
              width: 120,
              errorBuilder: (_, __, ___) =>
              const Icon(Icons.local_taxi, size: 80, color: Colors.yellow),
            ),
            const SizedBox(height: 24),
            const Text(
              'Premier Taxi Meter',
              style: TextStyle(
                  color: Colors.yellow,
                  fontSize: 24,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 40),
            const CircularProgressIndicator(color: Colors.yellow),
          ],
        ),
      ),
    );
  }
}

class InAppWebViewPage extends StatefulWidget {
  final String initialUrl;

  const InAppWebViewPage({
    super.key,
    required this.initialUrl,
  });

  @override
  State<InAppWebViewPage> createState() => _InAppWebViewPageState();
}

class _InAppWebViewPageState extends State<InAppWebViewPage>
    with SingleTickerProviderStateMixin {
  late InAppWebViewController _webViewController;
  late AnimationController _animationController;
  late Animation<double> _rotationAnimation;

  bool _isLoading = true;
  bool _showLocationError = false;

  final Location _location = Location();

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _rotationAnimation =
        Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(
          parent: _animationController,
          curve: Curves.linear,
        ));

    _requestLocationPermission();
  }

  Future<void> _requestLocationPermission() async {
    bool serviceEnabled = await _location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await _location.requestService();
      if (!serviceEnabled) {
        setState(() => _showLocationError = true);
        return;
      }
    }

    PermissionStatus permission = await _location.hasPermission();
    if (permission == PermissionStatus.denied) {
      permission = await _location.requestPermission();
      if (permission == PermissionStatus.denied) {
        setState(() => _showLocationError = true);
        return;
      }
    }

    if (permission == PermissionStatus.deniedForever) {
      setState(() => _showLocationError = true);
      return;
    }
  }

  Future<Map<String, dynamic>> _getCurrentLocation() async {
    try {
      final locData = await _location.getLocation();
      return {
        'latitude': locData.latitude,
        'longitude': locData.longitude,
        'accuracy': locData.accuracy,
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  Future<void> _refresh() async {
    _animationController.repeat();
    setState(() => _showLocationError = false);
    await _webViewController.reload();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (await _webViewController.canGoBack()) {
          await _webViewController.goBack();
          return false;
        }

        final nav = context.findAncestorStateOfType<_MainNavigationState>();
        if (nav != null && nav._currentIndex != 0) {
          nav.setState(() => nav._currentIndex = 0);
          return false;
        }

        // Show confirmation dialog before exiting the app
        final shouldExit = await showDialog<bool>(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Text('Exit App'),
              content: const Text('Do you want to exit the Premier Taxi Meter app?'),
              actions: <Widget>[
                TextButton(
                  child: const Text('No'),
                  onPressed: () => Navigator.of(context).pop(false),
                ),
                TextButton(
                  child: const Text('Yes'),
                  onPressed: () => Navigator.of(context).pop(true),
                ),
              ],
            );
          },
        );

        return shouldExit ?? false;
      },
      child: Scaffold(
        body: Stack(
          children: [
            InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(widget.initialUrl)),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                geolocationEnabled: true,
                allowsInlineMediaPlayback: true,
                mediaPlaybackRequiresUserGesture: false,
                safeBrowsingEnabled: true,
              ),
              onWebViewCreated: (controller) {
                _webViewController = controller;

                controller.addJavaScriptHandler(
                  handlerName: 'requestLocation',
                  callback: (args) async {
                    return await _getCurrentLocation();
                  },
                );
              },
              onLoadStart: (controller, url) {
                setState(() => _isLoading = true);
                _animationController.repeat();
              },
              onLoadStop: (controller, url) async {
                setState(() => _isLoading = false);
                _animationController.stop();
                _animationController.reset();
              },
              onGeolocationPermissionsShowPrompt: (controller, origin) async {
                return GeolocationPermissionShowPromptResponse(
                  origin: origin,
                  allow: true,
                  retain: true,
                );
              },
            ),

            Positioned(
              bottom: 100,
              right: 16,
              child: AnimatedBuilder(
                animation: _animationController,
                builder: (context, child) {
                  return Transform.rotate(
                    angle: _rotationAnimation.value * 2 * 3.14159,
                    child: FloatingActionButton(
                      onPressed: _refresh,
                      backgroundColor: Colors.yellow,
                      foregroundColor: Colors.black,
                      elevation: 8,
                      heroTag: "refresh_${widget.initialUrl}",
                      child: const Icon(Icons.refresh, size: 28),
                    ),
                  );
                },
              ),
            ),

            if (_showLocationError)
              Container(
                color: Colors.black87,
                child: Center(
                  child: Container(
                    margin: const EdgeInsets.all(24),
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [
                        BoxShadow(color: Colors.black26, blurRadius: 10)
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.location_off,
                            size: 60, color: Colors.red),
                        const SizedBox(height: 16),
                        const Text("GPS Error",
                            style: TextStyle(
                                fontSize: 22, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        const Text(
                          "Location access was denied. Please allow location access and refresh the page.",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                        const SizedBox(height: 24),
                        TextButton(
                            onPressed: _refresh,
                            child: const Text("Retry",
                                style: TextStyle(color: Colors.blue))),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;

  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = [
      const InAppWebViewPage(
          initialUrl: "https://taxi-db-tidesoftechnolo.replit.app/"),
      const InAppWebViewPage(
          initialUrl:
          "https://taxi-db-tidesoftechnolo.replit.app/taxi-meter"),
      const InAppWebViewPage(
          initialUrl: "https://taxi-db-tidesoftechnolo.replit.app/login"),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(child: Scaffold(
      body: IndexedStack(index: _currentIndex, children: _pages),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        backgroundColor: Colors.black,
        selectedItemColor: Colors.yellow,
        unselectedItemColor: Colors.grey,
        onTap: (i) => setState(() => _currentIndex = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: "Home"),
          BottomNavigationBarItem(
              icon: Icon(Icons.speed), label: "Launch Meter"),
          BottomNavigationBarItem(
              icon: Icon(Icons.lock), label: "Fleet Login"),
        ],
      ),
    ));
  }
}