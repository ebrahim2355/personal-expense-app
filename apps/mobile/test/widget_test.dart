import 'package:flutter_test/flutter_test.dart';
import 'package:houseexpenses/main.dart';

void main() {
  testWidgets('launches the development shell', (tester) async {
    await tester.pumpWidget(const HouseholdExpensesApp());

    expect(find.text('Household Expenses'), findsOneWidget);
    expect(find.text('Development shell ready'), findsOneWidget);
  });
}
