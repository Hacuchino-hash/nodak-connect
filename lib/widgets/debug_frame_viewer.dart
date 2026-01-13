import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../connector/meshcore_protocol.dart';

/// Debug widget to show the hex dump of a frame
class DebugFrameViewer {
  static void showFrameDebug(BuildContext context, Uint8List frame, String title) {
    final hexString = frame
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join(' ');

    final details = StringBuffer();
    details.writeln('Frame Length: ${frame.length} bytes\n');
    details.writeln('Command: 0x${frame[0].toRadixString(16).padLeft(2, '0')}');

    if (frame[0] == cmdSendTxtMsg && frame.length > 37) {
      details.writeln('\nText Message Frame:');
      details.writeln('- Destination PubKey: ${pubKeyToHex(frame.sublist(1, 33))}');
      details.writeln('- Timestamp: ${readUint32LE(frame, 33)}');
      details.writeln('- Flags: 0x${frame[37].toRadixString(16).padLeft(2, '0')}');
      final txtType = (frame[37] >> 2) & 0x03;
      details.writeln('- Text Type: $txtType ${txtType == txtTypeCliData ? "(CLI)" : "(Plain)"}');
      if (frame.length > 38) {
        final textBytes = frame.sublist(38);
        final nullIdx = textBytes.indexOf(0);
        final text = String.fromCharCodes(
          nullIdx >= 0 ? textBytes.sublist(0, nullIdx) : textBytes
        );
        details.writeln('- Text: "$text"');
      }
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                details.toString(),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
              const Divider(),
              const Text(
                'Hex Dump:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                hexString,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
