import 'package:flutter_test/flutter_test.dart';
import 'package:mhd_mikylov/main.dart';

void main() {
  testWidgets('zobrazí režimy řidiče, cestujícího a administrátora',
      (tester) async {
    await tester.pumpWidget(const MikylovApp());
    expect(find.text('Řidič'), findsOneWidget);
    expect(find.text('Cestující'), findsOneWidget);
    expect(find.text('Administrátor'), findsOneWidget);
    expect(find.text('Palubní obrazovka'), findsNothing);
  });
}
