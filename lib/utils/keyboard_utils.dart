import 'package:flutter/widgets.dart';

/// Verbergt het keyboard door de focus te verwijderen.
/// Gebruik in form submission handlers en als tap-to-dismiss.
void dismissKeyboard(BuildContext context) {
  final currentFocus = FocusScope.of(context);
  if (!currentFocus.hasPrimaryFocus && currentFocus.focusedChild != null) {
    FocusManager.instance.primaryFocus?.unfocus();
  }
}

/// Widget die het keyboard verbergt bij een tap buiten een tekstveld.
/// Wrap dit om een Scaffold of body content.
class DismissKeyboardOnTap extends StatelessWidget {
  const DismissKeyboardOnTap({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => dismissKeyboard(context),
      behavior: HitTestBehavior.translucent,
      child: child,
    );
  }
}
