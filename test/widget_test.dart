import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/main.dart';

void main() {
  testWidgets('App loads successfully', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MeshCoreApp());

    // Verify that the app title appears
    expect(find.text('MeshCore Open'), findsOneWidget);
  });
}
