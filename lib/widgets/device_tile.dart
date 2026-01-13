import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// A reusable tile widget for displaying a MeshCore device in a list
class DeviceTile extends StatelessWidget {
  final ScanResult scanResult;
  final VoidCallback onTap;

  const DeviceTile({
    super.key,
    required this.scanResult,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final device = scanResult.device;
    final rssi = scanResult.rssi;
    final name = device.platformName.isNotEmpty 
        ? device.platformName 
        : scanResult.advertisementData.advName;

    return ListTile(
      leading: _buildSignalIcon(rssi),
      title: Text(
        name.isNotEmpty ? name : 'Unknown Device',
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
      subtitle: Text(device.remoteId.toString()),
      trailing: ElevatedButton(
        onPressed: onTap,
        child: const Text('Connect'),
      ),
      onTap: onTap,
    );
  }

  Widget _buildSignalIcon(int rssi) {
    IconData icon;
    Color color;

    if (rssi >= -60) {
      icon = Icons.signal_cellular_4_bar;
      color = Colors.green;
    } else if (rssi >= -70) {
      icon = Icons.signal_cellular_alt;
      color = Colors.lightGreen;
    } else if (rssi >= -80) {
      icon = Icons.signal_cellular_alt_2_bar;
      color = Colors.orange;
    } else {
      icon = Icons.signal_cellular_alt_1_bar;
      color = Colors.red;
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: color),
        Text(
          '$rssi dBm',
          style: TextStyle(fontSize: 10, color: color),
        ),
      ],
    );
  }
}

