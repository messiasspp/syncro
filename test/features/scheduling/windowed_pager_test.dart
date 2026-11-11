import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncro/core/widgets/windowed_pager.dart';

void main() {
  group('WindowedPager - Unit Tests', () {
    test('initial state has start=0 and end=pageSize', () {
      final defaultPager = WindowedPager();
      expect(defaultPager.pageSize, 12);
      expect(defaultPager.maxWindow, 36);
      expect(defaultPager.start, 0);
      expect(defaultPager.end, 12);
      expect(defaultPager.isShifted, isFalse);
      expect(defaultPager.hasEarlier, isFalse);
      expect(defaultPager.hasMore(50), isTrue);
      expect(defaultPager.remaining(50), 38);
      expect(defaultPager.visibleStart(50), 0);
      expect(defaultPager.visibleEnd(50), 12);
      expect(defaultPager.visibleCount(50), 12);

      final customPager = WindowedPager(pageSize: 8, maxWindow: 24);
      expect(customPager.pageSize, 8);
      expect(customPager.maxWindow, 24);
      expect(customPager.start, 0);
      expect(customPager.end, 8);
    });

    testWidgets('loadMore appends up to maxWindow', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      final context = tester.element(find.byType(SizedBox));

      final pager = WindowedPager(pageSize: 10, maxWindow: 30);
      expect(pager.start, 0);
      expect(pager.end, 10);

      // First loadMore: appends pageSize (10) -> end = 20
      pager.loadMore(context, 100, (fn) => fn());
      expect(pager.start, 0);
      expect(pager.end, 20);
      expect(pager.isShifted, isFalse);

      // Second loadMore: appends pageSize (10) -> end = 30 (hits maxWindow)
      pager.loadMore(context, 100, (fn) => fn());
      expect(pager.start, 0);
      expect(pager.end, 30);
      expect(pager.isShifted, isFalse);
      expect(pager.hasMore(100), isTrue);
    });

    testWidgets('loadMore trims from start when exceeding maxWindow', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      final context = tester.element(find.byType(SizedBox));

      final pager = WindowedPager(pageSize: 10, maxWindow: 30);
      // Advance to maxWindow: [0, 30)
      pager.loadMore(context, 100, (fn) => fn());
      pager.loadMore(context, 100, (fn) => fn());
      expect(pager.start, 0);
      expect(pager.end, 30);

      // Exceeds maxWindow: end becomes 40, so start trims to 40 - 30 = 10
      pager.loadMore(context, 100, (fn) => fn());
      expect(pager.start, 10);
      expect(pager.end, 40);
      expect(pager.isShifted, isTrue);
      expect(pager.hasEarlier, isTrue);

      // Exceeds maxWindow again: end becomes 50, start trims to 50 - 30 = 20
      pager.loadMore(context, 100, (fn) => fn());
      expect(pager.start, 20);
      expect(pager.end, 50);
      expect(pager.isShifted, isTrue);

      // Clamps to total if total is reached
      pager.loadMore(context, 55, (fn) => fn());
      expect(pager.end, 55);
      expect(pager.start, 25); // 55 - 30
      expect(pager.hasMore(55), isFalse);
      expect(pager.remaining(55), 0);
    });

    testWidgets('loadEarlier restores items and trims from end', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      final context = tester.element(find.byType(SizedBox));

      final pager = WindowedPager(pageSize: 10, maxWindow: 30);
      // Advance to [20, 50)
      pager.loadMore(context, 100, (fn) => fn()); // [0, 20)
      pager.loadMore(context, 100, (fn) => fn()); // [0, 30)
      pager.loadMore(context, 100, (fn) => fn()); // [10, 40)
      pager.loadMore(context, 100, (fn) => fn()); // [20, 50)
      expect(pager.start, 20);
      expect(pager.end, 50);

      // loadEarlier restores by pageSize: start becomes max(0, 20 - 10) = 10
      // 50 - 10 = 40 > 30, so end trims to 10 + 30 = 40
      pager.loadEarlier(context, (fn) => fn());
      expect(pager.start, 10);
      expect(pager.end, 40);
      expect(pager.isShifted, isTrue);

      // loadEarlier again: start becomes 0
      // 40 - 0 = 40 > 30, so end trims to 0 + 30 = 30
      pager.loadEarlier(context, (fn) => fn());
      expect(pager.start, 0);
      expect(pager.end, 30);
      expect(pager.isShifted, isFalse);
      expect(pager.hasEarlier, isFalse);

      // loadEarlier when already at start=0 stays at 0
      pager.loadEarlier(context, (fn) => fn());
      expect(pager.start, 0);
      expect(pager.end, 30);
    });

    testWidgets('reset() restores initial state', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      final context = tester.element(find.byType(SizedBox));

      final pager = WindowedPager(pageSize: 12, maxWindow: 36);
      pager.loadMore(context, 100, (fn) => fn()); // end = 24, start = 0
      pager.loadMore(context, 100, (fn) => fn()); // end = 36, start = 0
      pager.loadMore(context, 100, (fn) => fn()); // end = 48, start = 12
      pager.loadMore(context, 100, (fn) => fn()); // end = 60, start = 24
      expect(pager.start, 24);
      expect(pager.end, 60);
      expect(pager.isShifted, isTrue);

      pager.reset();
      expect(pager.start, 0);
      expect(pager.end, 12);
      expect(pager.isShifted, isFalse);
      expect(pager.hasEarlier, isFalse);
    });

    testWidgets(
      'WindowedPager.resetAllLive() resets all attached pagers and detects if any was shifted',
      (tester) async {
        await tester.pumpWidget(const MaterialApp(home: SizedBox()));
        final context = tester.element(find.byType(SizedBox));

        final pager1 = WindowedPager(pageSize: 10, maxWindow: 20);
        final pager2 = WindowedPager(pageSize: 10, maxWindow: 20);

        var pager1Calls = 0;
        var pager2Calls = 0;

        pager1.attach(() => pager1Calls++);
        pager2.attach(() => pager2Calls++);
        addTearDown(() {
          pager1.detach();
          pager2.detach();
        });

        // Step 1: None shifted, none modified -> returns false, no callback invoked
        var anyShifted = WindowedPager.resetAllLive();
        expect(anyShifted, isFalse);
        expect(pager1Calls, 0);
        expect(pager2Calls, 0);

        // Step 2: pager1 is modified but not shifted (start=0, end=20)
        pager1.loadMore(context, 50, (fn) => fn());
        expect(pager1.start, 0);
        expect(pager1.end, 20);
        expect(pager1.isShifted, isFalse);

        anyShifted = WindowedPager.resetAllLive();
        expect(anyShifted, isFalse);
        expect(pager1Calls, 1);
        expect(pager2Calls, 0);
        expect(pager1.end, 10);

        // Step 3: pager2 is shifted (start > 0)
        pager2.loadMore(context, 50, (fn) => fn()); // [0, 20)
        pager2.loadMore(context, 50, (fn) => fn()); // [10, 30) -> shifted!
        expect(pager2.isShifted, isTrue);

        anyShifted = WindowedPager.resetAllLive();
        expect(anyShifted, isTrue);
        expect(pager2Calls, 1);
        expect(pager2.start, 0);
        expect(pager2.end, 10);
        expect(pager2.isShifted, isFalse);

        // Step 4: After detach, pager is not affected by resetAllLive()
        pager1.detach();
        pager1.loadMore(context, 50, (fn) => fn());
        expect(pager1.end, 20);

        pager1Calls = 0;
        anyShifted = WindowedPager.resetAllLive();
        expect(pager1Calls, 0);
        expect(pager1.end, 20); // Not reset because it was detached
      },
    );
  });
}
