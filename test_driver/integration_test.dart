import 'package:integration_test/integration_test_driver.dart';

/// Driver voor Flutter integration tests.
/// Gebruik:
///   flutter drive \
///     --driver=test_driver/integration_test.dart \
///     --target=integration_test/app_test.dart
Future<void> main() => integrationDriver();
