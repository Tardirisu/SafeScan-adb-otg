import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'pages/scan_result.dart';
import 'services/globals.dart';

void main() => runApp(const MyApp());

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ADB OTG',
      navigatorKey: navigatorKey, // 加了 key
      home: const HomePage(),     // 用一个新的页面管理界面
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  static const _channel = MethodChannel('com.htetznaing.adbotg/usb');

  void _restorePlatformCallHandler() {
    _channel.setMethodCallHandler(_platformCallHandler);
  }

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler(_platformCallHandler);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); // 清除 observer
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // debugPrint('🔄 App resumed — checking connection status...');
      _queryConnectionStatus(); // 返回页面时主动检查连接状态
    }
  }

  Future<void> _queryConnectionStatus() async {
    try {
      final bool? status = await _channel.invokeMethod<bool>('isConnected');
      connectionStatus.value = status == true ? 'connected' : 'disconnected';
    } catch (_) {
      connectionStatus.value = 'disconnected';
    }
  }

  Future<void> _platformCallHandler(MethodCall call) async {
    switch (call.method) {
      case 'onStatus':
        final status = call.arguments as String;
        // setState(() {
        //   _status = status;
        // });
        connectionStatus.value = status; // 更新全局状态
        break;
    }
  }

  Future<void> _connect() async {
    try {
      await _channel.invokeMethod('requestConnection');
      setState(() {
        connectionStatus.value = 'Permission requested…';
      });
    } on PlatformException catch (e) {
      setState(() {
        connectionStatus.value = 'Connect failed: ${e.message}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ADB OTG')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ValueListenableBuilder<String>(
          valueListenable: connectionStatus,
          builder: (context, status, _) {
            return Column(
              children: [
                Row(children: [
                  const Text('Status: ', style: TextStyle(fontWeight: FontWeight.bold)),
                  Expanded(child: Text(status)),
                ]),
                const SizedBox(height: 12),
                Wrap(spacing: 12, children: [
                  ElevatedButton(onPressed: _connect, child: const Text('Connect USB')),
                  ElevatedButton(
                    onPressed: status == 'connected'
                        ? () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ScanResultPage(),
                        ),
                      ).then((_) {
                        // 页面返回时刷新状态
                        _queryConnectionStatus();
                      });
                    }
                        : null,
                    child: const Text('Go to Scan Result'),
                  ),
                ]),
              ],
            );
          },
        ),

      ),
    );
  }
}

