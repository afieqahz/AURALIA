import 'package:flutter/widgets.dart';

import 'auralia_state.dart';

class AuraliaScope extends InheritedNotifier<AuraliaState> {
  const AuraliaScope({
    super.key,
    required AuraliaState state,
    required super.child,
  }) : super(notifier: state);

  static AuraliaState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AuraliaScope>();
    assert(scope != null, 'AuraliaScope was not found in the widget tree.');
    return scope!.notifier!;
  }
}
