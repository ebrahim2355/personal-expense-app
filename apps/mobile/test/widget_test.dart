import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:houseexpenses/src/domain/session.dart';
import 'package:houseexpenses/src/presentation/app.dart';
import 'package:houseexpenses/src/presentation/presentation_providers.dart';

void main() {
  testWidgets('opens the sign-in screen for a signed-out member', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          sessionSnapshotProvider.overrideWith(
            (ref) => Stream<SessionSnapshot>.value(
              const SessionSnapshot(SessionStatus.signedOut),
            ),
          ),
        ],
        child: const HouseholdExpensesApp(),
      ),
    );
    await tester.pump();

    expect(find.text('Household Expenses'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
  });
}
