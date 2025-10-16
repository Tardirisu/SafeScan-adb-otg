import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  bool _isScanning = false;
  bool _isReceiving = false;
  Map<String, Map<String, String>> _riskyMap = {};
  bool _isRemoteSource = false;

  // 展开状态管理
  Map<String, bool> _expansionState = {};

  @override
  void initState() {
    super.initState();
    _startScan();
    _channel.setMethodCallHandler(_handleOutput);
  }

  Future<bool> _checkConnected() async {
    try {
      final bool connected = await _channel.invokeMethod('isConnected');
      return connected;
    } on PlatformException catch (_) {
      return false;
    }
  }

  Future<void> _startScan() async {
    final isConnected = await _checkConnected();
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
      _expansionState.clear(); // 清空展开状态
    });

    await _channel.invokeMethod('sendCommand', {
      'command': 'pm list packages',
    });
  }

  Future<void> _handleOutput(MethodCall call) async {
    if (call.method != 'onOutput') return;

    final raw = (call.arguments as String);
    final lines = raw.split('\n');

    for (var line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      print('process line: "$trimmed"');

      if (trimmed.startsWith('package:')) {
        if (!_isReceiving) {
          _isReceiving = true;
          _tempBuffer.clear();
        }
        final pkg = trimmed.substring(8).trim();
        if (pkg.isNotEmpty && !_tempBuffer.contains(pkg)) {
          _tempBuffer.add(pkg);
          print('found: $pkg, current number: ${_tempBuffer.length}');

          if (mounted) {
            setState(() {
              _packages = List.from(_tempBuffer);
            });
          }
        }
      }
      else if (_isShellPromptLine(trimmed)) {
        print(' detect Shell prompt，scan finished');
        _completeScan();
      }
    }
  }

  bool _isShellPromptLine(String line) {
    final promptPatterns = [
      r'^[a-zA-Z0-9_\-]+:/ \$$',
      r'^[a-zA-Z0-9_\-]+:/ #$',
      r'^[a-zA-Z0-9_\-]+:/ \$ $',
      r'^[a-zA-Z0-9_\-]+ #$',
      r'^[a-zA-Z0-9_\-]+ \$$',
    ];

    for (var pattern in promptPatterns) {
      if (RegExp(pattern).hasMatch(line)) {
        return true;
      }
    }
    return false;
  }

  void _completeScan() {
    if (!_isReceiving) return;

    _isReceiving = false;
    _isScanning = false;

    if (mounted) {
      setState(() {
        _packages = List.from(_tempBuffer);
      });
      _loadRiskList();
      print('Scan finished！Found ${_packages.length} apps in total');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Scan finished. Found ${_packages.length} apps in total'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

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

  void _showDetailsDialog(String packageName, Map<String, String>? riskInfo) {
    final isSafe = riskInfo == null;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(riskInfo?['title'] ?? packageName),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Risk Type: ${riskInfo?['flag'] ?? 'Safe'}'),
              const SizedBox(height: 8),
              Text('Package Name: $packageName'),
              if (isSafe) ...[
                const SizedBox(height: 8),
                Text(
                  'This app is marked as safe.',
                  style: TextStyle(color: Colors.green[600]),
                ),
              ],
            ],
          ),
          actions: [
            // 所有应用都显示设置和删除按钮
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _openAppSettingsOnTarget(packageName);
              },
              child: const Text('Open Settings'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _uninstallApp(packageName);
              },
              child: const Text('Delete App'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
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
        connectionStatus.value = status;
      }
    });
  }

  // 获取所有风险类型
  Set<String> _getRiskTypes() {
    final types = <String>{};
    for (var risk in _riskyMap.values) {
      types.add(risk['flag']!);
    }
    return types;
  }

  // 获取指定风险类型的应用列表
  List<String> _getAppsByRiskType(String riskType) {
    return _packages.where((pkg) {
      final riskInfo = _riskyMap[pkg];
      return riskInfo != null && riskInfo['flag'] == riskType;
    }).toList();
  }

  // 获取安全应用列表
  List<String> _getSafeApps() {
    return _packages.where((pkg) => !_riskyMap.containsKey(pkg)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final riskTypes = _getRiskTypes();
    final safeApps = _getSafeApps();

    // 初始化展开状态
    for (var type in riskTypes) {
      _expansionState.putIfAbsent(type, () => false);
    }
    _expansionState.putIfAbsent('Safe', () => false);

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
                'Found ${_packages.length} Apps in total',
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

            // 可展开的列表
            Expanded(
              child: _packages.isEmpty
                  ? const Center(child: Text('No data available'))
                  : ListView(
                children: [
                  // 风险类型应用列表
                  ...riskTypes.map((type) {
                    final apps = _getAppsByRiskType(type);
                    return _buildRiskTypeExpansionTile(type, apps);
                  }),

                  // 安全应用列表
                  if (safeApps.isNotEmpty)
                    _buildRiskTypeExpansionTile('Safe', safeApps),
                ],
              ),
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

  Widget _buildRiskTypeExpansionTile(String riskType, List<String> apps) {
    final isSafe = riskType == 'Safe';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        key: Key(riskType),
        initiallyExpanded: _expansionState[riskType] ?? false,
        onExpansionChanged: (expanded) {
          setState(() {
            _expansionState[riskType] = expanded;
          });
        },
        title: Row(
          children: [
            Expanded(
              child: Text(
                '$riskType Apps (${apps.length})',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isSafe ? Colors.green : Colors.red,
                ),
              ),
            ),
          ],
        ),
        children: [
          if (apps.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text('No apps in this category'),
            )
          else
            ...apps.asMap().entries.map((entry) {
              final index = entry.key;
              final packageName = entry.value;
              final riskInfo = isSafe ? null : _riskyMap[packageName];

              return _buildAppListItem(
                packageName: packageName,
                riskInfo: riskInfo,
                index: index,
                isSafe: isSafe,
              );
            }),
        ],
      ),
    );
  }
  Widget _buildAppListItem({
    required String packageName,
    required Map<String, String>? riskInfo,
    required int index,
    required bool isSafe,
  }) {
    // 交替底色
    final backgroundColor = index % 2 == 0
        ? Colors.grey[50]
        : Colors.white;

    return Container(
      color: backgroundColor,
      child: ListTile(
        title: Row(
          children: [
            // 包名 - 占据主要空间
            Expanded(
              child: Text(
                packageName,
                style: const TextStyle(fontSize: 14),
              ),
            ),
            // 风险标签 - 靠右显示
            Text(
              riskInfo?['flag'] ?? 'Safe',
              style: TextStyle(
                color: isSafe ? Colors.green : Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        // 整行可点击
        onTap: () => _showDetailsDialog(packageName, riskInfo),
        // 添加点击反馈
        mouseCursor: SystemMouseCursors.click,
      ),
    );
  }
}