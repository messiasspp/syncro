import 'package:flutter_test/flutter_test.dart';
import 'package:syncro/features/scheduling/domain/models/time_range.dart';
import 'package:syncro/features/scheduling/domain/services/interval_math.dart';

void main() {
  group('IntervalMath - mergeOverlapping', () {
    test('merges overlapping and adjacent intervals into a single interval', () {
      final base = DateTime(2026, 10, 19, 10, 0); // Monday 10:00

      final r1 = TimeRange(
        start: base,
        end: base.add(const Duration(minutes: 60)), // 10:00 - 11:00
      );
      final r2 = TimeRange(
        start: base.add(const Duration(minutes: 30)),
        end: base.add(const Duration(minutes: 90)), // 10:30 - 11:30
      );
      final r3 = TimeRange(
        start: base.add(const Duration(minutes: 120)),
        end: base.add(const Duration(minutes: 180)), // 12:00 - 13:00
      );

      final merged = IntervalMath.mergeOverlapping([r1, r2, r3]);

      expect(merged.length, 2);
      expect(merged[0].start, base);
      expect(merged[0].end, base.add(const Duration(minutes: 90))); // 10:00 - 11:30
      expect(merged[1].start, base.add(const Duration(minutes: 120)));
      expect(merged[1].end, base.add(const Duration(minutes: 180)));
    });

    test('merges abutting intervals (10:00-11:00 and 11:00-12:00)', () {
      final base = DateTime(2026, 10, 19, 10, 0);
      final r1 = TimeRange(start: base, end: base.add(const Duration(hours: 1)));
      final r2 = TimeRange(
        start: base.add(const Duration(hours: 1)),
        end: base.add(const Duration(hours: 2)),
      );

      final merged = IntervalMath.mergeOverlapping([r1, r2]);
      expect(merged.length, 1);
      expect(merged.first.start, base);
      expect(merged.first.end, base.add(const Duration(hours: 2)));
    });
  });

  group('IntervalMath - subtractIntervals', () {
    test('carves busy blocks out of available windows', () {
      final day = DateTime(2026, 10, 19);
      final available = [
        TimeRange(
          start: DateTime(day.year, day.month, day.day, 9, 0),
          end: DateTime(day.year, day.month, day.day, 17, 0),
        ),
      ];

      final busy = [
        TimeRange(
          start: DateTime(day.year, day.month, day.day, 11, 0),
          end: DateTime(day.year, day.month, day.day, 13, 0),
        ),
      ];

      final free = IntervalMath.subtractIntervals(
        available: available,
        busy: busy,
      );

      expect(free.length, 2);
      // First gap: 09:00 - 11:00
      expect(free[0].start, DateTime(day.year, day.month, day.day, 9, 0));
      expect(free[0].end, DateTime(day.year, day.month, day.day, 11, 0));
      // Second gap: 13:00 - 17:00
      expect(free[1].start, DateTime(day.year, day.month, day.day, 13, 0));
      expect(free[1].end, DateTime(day.year, day.month, day.day, 17, 0));
    });
  });

  group('IntervalMath - sliceIntoSlots', () {
    test('slices 2-hour window into 45-minute slots on a 15-minute grid', () {
      final day = DateTime(2026, 10, 19);
      final interval = TimeRange(
        start: DateTime(day.year, day.month, day.day, 10, 0),
        end: DateTime(day.year, day.month, day.day, 12, 0), // 120 minutes
      );

      final slots = IntervalMath.sliceIntoSlots(
        freeIntervals: [interval],
        slotDuration: const Duration(minutes: 45),
        step: const Duration(minutes: 15),
      );

      // Total duration = 120m.
      // Slices: 10:00-10:45, 10:15-11:00, 10:30-11:15, 10:45-11:30, 11:00-11:45, 11:15-12:00
      // That is 6 slots!
      expect(slots.length, 6);
      expect(slots.first.start, DateTime(day.year, day.month, day.day, 10, 0));
      expect(slots.first.end, DateTime(day.year, day.month, day.day, 10, 45));
      expect(slots.last.start, DateTime(day.year, day.month, day.day, 11, 15));
      expect(slots.last.end, DateTime(day.year, day.month, day.day, 12, 0));
    });
  });
}
