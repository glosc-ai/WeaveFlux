import 'package:flutter_test/flutter_test.dart';
import 'package:weaveflux/main.dart';

void main() {
  testWidgets('WeaveFlux launches creation workspace', (tester) async {
    await tester.pumpWidget(const WeaveFluxApp());

    expect(find.text('文生视频'), findsOneWidget);
    expect(find.text('图生视频'), findsOneWidget);
    expect(find.text('开始织影'), findsOneWidget);
  });

  testWidgets('failed task expands and collapses without layout overflow',
      (tester) async {
    await tester.pumpWidget(const WeaveFluxApp());

    await tester.tap(find.text('任务'));
    await tester.pump(const Duration(milliseconds: 300));

    final failedTask = find.textContaining('aurora borealis');
    expect(failedTask, findsOneWidget);

    await tester.tap(failedTask);
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(find.textContaining('invalid_api_key'), findsOneWidget);

    await tester.tap(failedTask);
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  });
}
