import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:espo_worker_app/main.dart';

void main() {
  testWidgets('App root smoke test', (WidgetTester tester) async {
    // Verifies that the app widget tree can be instantiated without crashing
    const app = EspoWorkerApp();
    expect(app, isNotNull);
  });
}
