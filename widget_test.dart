import 'package:flutter_test/flutter_test.dart';
import 'package:mhd_mikylov/main.dart';

void main() {
  testWidgets('zobrazí palubní režim a první zastávku', (tester) async {
    await tester.pumpWidget(const MikylovApp());
    expect(find.text('MHD MIKYLOV • PALUBNÍ REŽIM'), findsOneWidget);
    expect(find.text('Bukovany, sídliště'), findsWidgets);
    expect(find.text('PŘÍJEZD'), findsOneWidget);
  });
}
