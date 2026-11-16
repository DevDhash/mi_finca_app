import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_finca_app/app/app.dart';

void main() {
  testWidgets('long startup error scrolls and keeps retry reachable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var retried = false;
    await tester.pumpWidget(
      MaterialApp(
        home: StartupError(
          error: List.filled(
            150,
            'ProviderException: local database unavailable.',
          ).join('\n'),
          onRetry: () => retried = true,
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('Reintentar'), 500);
    await tester.tap(find.text('Reintentar'));
    expect(retried, isTrue);
    expect(tester.takeException(), isNull);
  });
}
