import 'package:flutter_test/flutter_test.dart';
import 'package:asistencia_taller/main.dart';

void main() {
  testWidgets('AttendanceApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const AttendanceApp());
    expect(find.byType(AttendanceApp), findsOneWidget);
  });
}
