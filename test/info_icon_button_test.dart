import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_finca_app/app/theme/app_theme.dart';
import 'package:mi_finca_app/core/widgets/info_icon_button.dart';

void main() {
  testWidgets('help has accessible target and each dismissal preserves page', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: InfoIconButton(
            title: 'Ayuda',
            tooltip: 'Información del campo',
            content: Text('Contenido informativo'),
          ),
        ),
      ),
    );
    final button = find.byTooltip('Información del campo');
    expect(tester.getSize(button).width, greaterThanOrEqualTo(48));
    expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
    for (final dismissal in ['button', 'back', 'barrier']) {
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.text('Contenido informativo'), findsOneWidget);
      if (dismissal == 'button') {
        await tester.tap(find.text('Entendido'));
      } else if (dismissal == 'back') {
        await tester.binding.handlePopRoute();
      } else {
        await tester.tapAt(const Offset(5, 5));
      }
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(button, findsOneWidget);
    }
  });

  testWidgets('long help scrolls on small screen with enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: InfoIconButton(
            title: 'Información',
            tooltip: 'Ayuda',
            closeLabel: 'Cerrar',
            content: Text(List.filled(20, 'Un párrafo de ayuda.').join('\n')),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Ayuda'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final scrollable = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(Scrollable),
    );
    expect(
      tester.state<ScrollableState>(scrollable).position.maxScrollExtent,
      greaterThan(0),
    );
    await tester.drag(scrollable, const Offset(0, -200));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cerrar'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
