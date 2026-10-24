import 'package:flutter_test/flutter_test.dart';
import 'package:phonecam/core/protocol/shared_protocol.dart';

void main() {
  testWidgets('PhoneCam App smoke test', (WidgetTester tester) async {
    expect(ProtocolConstants.defaultPort, equals(8080));
    expect(ProtocolConstants.magicHeader, equals([0x50, 0x43, 0x41, 0x4D]));
  });
}
