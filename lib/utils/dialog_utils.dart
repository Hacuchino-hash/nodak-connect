import 'package:flutter/material.dart';
import '../connector/meshcore_connector.dart';

/// Shows a confirmation dialog before disconnecting from the device.
/// Returns true if user confirmed and disconnect completed, false otherwise.
Future<bool> showDisconnectDialog(
  BuildContext context,
  MeshCoreConnector connector,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Disconnect'),
      content: const Text(
          'Are you sure you want to disconnect from this device?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Disconnect'),
        ),
      ],
    ),
  );

  if (confirmed == true) {
    await connector.disconnect();
    return true;
  }
  return false;
}
