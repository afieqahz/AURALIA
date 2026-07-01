import 'package:flutter_test/flutter_test.dart';

import 'package:auralia_app/core/services/auralia_scope.dart';
import 'package:auralia_app/core/services/auralia_state.dart';
import 'package:auralia_app/main.dart';

void main() {
  testWidgets('shows splash then login screen', (WidgetTester tester) async {
    await tester.pumpWidget(
      AuraliaScope(state: AuraliaState(), child: const MyApp()),
    );

    expect(find.text('AURALIA'), findsOneWidget);
    expect(find.text('When Your Mood Finds Its Melody'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 800));

    expect(find.text('Log in'), findsOneWidget);
    expect(find.text('Welcome back!'), findsOneWidget);
  });
}
