import 'package:flutter/material.dart';
import '../core/crypto_box.dart';
import '../ui.dart';
import 'sync_service.dart';

class DevicesPage extends StatefulWidget {
  const DevicesPage({super.key, required this.service});
  final SyncService service;
  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  List<Json>? _devices;
  String? _error;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final result = await widget.service.api!.request('GET', '/devices');
      if (mounted) {
        setState(() {
          _devices = (result as List).map((d) => Json.from(d as Map)).toList();
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = '设备信息读取失败，请重试或重新登录');
    }
  }

  Future<void> _revoke(Json device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('撤销设备登录？'),
        content: const Text('该设备需要重新登录才能同步。本地加密条目会保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('撤销'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final own = device['id'] == widget.service.api!.deviceId;
      await widget.service.api!.request('DELETE', '/devices/${device['id']}');
      if (own) {
        await widget.service.disconnect(revoke: false);
        if (mounted) Navigator.pop(context);
      } else {
        await _load();
      }
    } catch (_) {
      if (mounted) message(context, '撤销失败，请重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('登录设备')),
    body: _error != null
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error!),
                TextButton(onPressed: _load, child: const Text('重试')),
              ],
            ),
          )
        : _devices == null
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final device in _devices!)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.phone_android),
                    title: Text(
                      '${device['name']}${device['id'] == widget.service.api?.deviceId ? '（本设备）' : ''}',
                    ),
                    subtitle: Text('最近使用：${device['last_seen']}'),
                    isThreeLine: true,
                    trailing: IconButton(
                      tooltip: '撤销设备',
                      onPressed: _busy ? null : () => _revoke(device),
                      icon: const Icon(Icons.logout),
                    ),
                  ),
                ),
            ],
          ),
  );
}
