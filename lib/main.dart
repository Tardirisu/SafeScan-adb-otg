import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const MyApp());

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  static const _channel = MethodChannel('com.htetznaing.adbotg/usb');

  String _status = 'Not connected';
  List<String> _packages = [];

  @override
  void initState() {
    super.initState();
    // listen for both status updates and shell output
    _channel.setMethodCallHandler(_platformCallHandler);
  }

  Future<void> _platformCallHandler(MethodCall call) async {
    switch (call.method) {
      case 'onStatus':
        setState(() => _status = call.arguments as String);
        break;
      case 'onOutput':
        final line = (call.arguments as String).trim();
        // collect only package lines
        if (line.startsWith('package:')) {
          setState(() => _packages.add(line.substring(8)));
        }
        break;
    }
  }

  Future<void> _connect() async {
    try {
      await _channel.invokeMethod('requestConnection');
      setState(() => _status = 'Permission requested…');
    } on PlatformException catch (e) {
      setState(() => _status = 'Connect failed: ${e.message}');
    }
  }

  Future<void> _runId() async {
    try {
      final out = await _channel.invokeMethod<String>(
        'runCommand',
        {'command': 'id'},
      );
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(out ?? '')));
    } on PlatformException catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: ${e.message}')));
    }
  }

  Future<void> _listPackages() async {
    // clear previous list
    setState(() => _packages.clear());
    // send into the interactive shell
    await _channel.invokeMethod(
      'sendCommand',
      {'command': 'pm list packages'},
    );
    // now wait: as the Java reader thread sees each "package:..." line,
    // it will fire onOutput callbacks that we collect above.
  }

  @override
  Widget build(BuildContext context) {
    final bool canList = _status == 'connected';
    return MaterialApp(
      title: 'ADB OTG',
      home: Scaffold(
        appBar: AppBar(title: const Text('ADB OTG')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(children: [
                const Text('Status: ', style: TextStyle(fontWeight: FontWeight.bold)),
                Expanded(child: Text(_status)),
              ]),
              const SizedBox(height: 12),
              Wrap(spacing: 12, children: [
                ElevatedButton(onPressed: _connect, child: const Text('Connect USB')),
                ElevatedButton(onPressed: _runId,    child: const Text('Run "id"')),
                ElevatedButton(
                  onPressed: canList ? _listPackages : null,
                  child: const Text('List Packages'),
                ),
              ]),
              const SizedBox(height: 12),
              if (_packages.isNotEmpty) ...[
                const Text('Packages:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.builder(
                    itemCount: _packages.length,
                    itemBuilder: (_, i) => Text(_packages[i]),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
