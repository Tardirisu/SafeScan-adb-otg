import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// import '../main.dart';
import '../services/globals.dart';
import '../services/csv_utils.dart';

class ScanResultPage extends StatefulWidget {
  const ScanResultPage({super.key});

  @override
  State<ScanResultPage> createState() => _ScanResultPageState();
}

class _ScanResultPageState extends State<ScanResultPage> {
  static const MethodChannel _channel = MethodChannel('com.htetznaing.adbotg/usb');

  List<String> _packages = [];
  List<String> _tempBuffer = [];
  bool _isScanning = false; // 是否仍在扫描、计数
  bool _isReceiving = false; // 是否在接收output
  Map<String, Map<String, String>> _riskyMap = {}; // packageName -> {flag: ..., title: ...}
  bool _isRemoteSource = false;
  bool _showSafeApps = false;

  @override
  void initState() {
    super.initState();
    _startScan(); // 页面加载时自动开始扫描
    _channel.setMethodCallHandler(_handleOutput);
  }

  // 检查是否已连接
  Future<bool> _checkConnected() async {
    try {
      final bool connected = await _channel.invokeMethod('isConnected');
      return connected;
    } on PlatformException catch (_) {
      return false;
    }
  }

  Future<void> _startScan() async {
    final isConnected = await _checkConnected(); // 第一步：判断连接状态
    if (!isConnected) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please connect the target device')),
        );
      }
      connectionStatus.value = 'disconnected';
      return;
    }

    setState(() {
      _packages.clear();
      _tempBuffer.clear();
      _isScanning = true;
    });

    // 发送扫描命令
    await _channel.invokeMethod('sendCommand', {
      'command': 'pm list packages',
    });

  }

  Future<void> _handleOutput(MethodCall call) async {
    if (call.method != 'onOutput') return;

    final raw = (call.arguments as String);
    final lines = raw.split('\n');  // 兼容一次性多行传入

    for (var line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      // print('📥 处理拆分后行: "$trimmed"');
      if (trimmed == 'redfin:/ \$') {
        if (!_isReceiving) {
          // print('⚠️ 没有开始接收但收到了 redfin，忽略');
          return;
        }
        _isReceiving = false;
        await _loadRiskList(); // ⬅️ 下面我们定义这个函数
        Future.delayed(Duration(milliseconds: 50), () {
          if (mounted) {
            setState(() {
              _packages = List.from(_tempBuffer);
              _isScanning = false;
            });
            // print('✅ 更新 UI，展示 ${_packages.length} 个应用');
          }
        });
      } else if (trimmed.startsWith('package:')) {
        if (!_isReceiving) {
          _isReceiving = true;
          _tempBuffer.clear();
        }
        final pkg = trimmed.substring(8).trim();
        if (pkg.isNotEmpty) {
          _tempBuffer.add(pkg);
          // print('📦 加入包: $pkg, 当前数量: ${_tempBuffer.length}');
        }
      } else {
        // print('⚠️ 非 package 行被忽略: "$trimmed"');
      }
    }
  }

// 从 CSV 中获取风险字典，不管设备上有没有
  Future<void> _loadRiskList() async {
    final csvResult = await fetchCSVData();
    _isRemoteSource = csvResult.isRemote;
    final rows = csvResult.data;

    _riskyMap.clear();
    for (var row in rows.skip(1)) {
      if (row.length < 4) continue;
      final appId = row[0].toString();
      final flag = row[2].toString();
      final title = row[3].toString();
      if (flag.toLowerCase() != 'safe') {
        _riskyMap[appId] = {
          'flag': flag,
          'title': title,
        };
      }
    }
  }

  void _showDetailsDialog(String packageName, Map<String, String> riskInfo) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(riskInfo['title'] ?? 'Unknown App'),
          content: Text('Risk Type: ${riskInfo['flag']}\n\nPackage Name: $packageName'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _openAppSettingsOnTarget(packageName);
              },
              child: const Text('Open Settings On Target Device'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _uninstallApp(packageName);
              },
              child: const Text('Delete this app'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('close'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openAppSettingsOnTarget(String packageName) async {
    await _channel.invokeMethod('sendCommand', {
      'command': 'am start -a android.settings.APPLICATION_DETAILS_SETTINGS -d package:$packageName',
    });
  }

  Future<void> _uninstallApp(String packageName) async {
    await _channel.invokeMethod('sendCommand', {
      'command': 'pm uninstall $packageName',
    });
  }

  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
    _restoreMainHandler();
    super.dispose();
  }

  void _restoreMainHandler() {
    const MethodChannel _channel = MethodChannel('com.htetznaing.adbotg/usb');
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onStatus') {
        final status = call.arguments as String;
        connectionStatus.value = status; // 更新全局状态
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final riskyApps = _packages.where((pkg) => _riskyMap.containsKey(pkg)).toList();
    final safeApps = _packages.where((pkg) => !_riskyMap.containsKey(pkg)).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Scan Result')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (_isScanning)
              const CircularProgressIndicator()
            else ...[
              Text(
                'Find ${_packages.length} Apps in total',
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 4),
              Text(
                _isRemoteSource
                    ? 'Source: Online CSV file'
                    : 'Source: Local cache (fallback)',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
            const SizedBox(height: 16),

            // 风险应用显示
            Expanded(
              child: _packages.isEmpty
                  ? const Center(child: Text('No data available'))
                  : ListView(
                children: [
                  ...riskyApps.map((pkg) => _buildListItem(pkg, _riskyMap[pkg])),
                  if (_showSafeApps)
                    ...safeApps.map((pkg) => _buildListItem(pkg, null)),
                ],
              ),
            ),

            // 切换显示按钮
            if (safeApps.isNotEmpty)
              TextButton(
                onPressed: () {
                  setState(() {
                    _showSafeApps = !_showSafeApps;
                  });
                },
                child: Text(_showSafeApps ? 'Hide Safe Apps' : 'Show Safe Apps'),
              ),

            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _isScanning ? null : _startScan,
              child: const Text('Scan Again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListItem(String pkg, Map<String, String>? risk) {
    return ListTile(
      title: Row(
        children: [
          // 包名（占 3 份）
          Expanded(
            flex: 3,
            child: Text(pkg),
          ),
          // 风险标签（占 2 份）
          Expanded(
            flex: 2,
            child: Text(
              risk?['flag'] ?? 'Safe',
              style: TextStyle(
                color: risk != null ? Colors.red : Colors.green,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          // 查看详情按钮（占 2 份）
          Expanded(
            flex: 2,
            child: TextButton(
              onPressed: risk == null
                  ? null
                  : () => _showDetailsDialog(pkg, risk),
              child: const Text('View Details'),
            ),
          ),
        ],
      ),
    );
  }


}
