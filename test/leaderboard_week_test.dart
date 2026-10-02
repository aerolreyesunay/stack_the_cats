import 'package:flutter_test/flutter_test.dart';
import 'package:stack_the_cats/services/leaderboard_service.dart';

void main() {
  group('LeaderboardWeek.key', () {
    test('a Thursday in October', () {
      expect(LeaderboardWeek.key(DateTime.utc(2026, 10, 1)), '2026-W40');
    });

    test('Monday and Sunday are in the same week', () {
      expect(LeaderboardWeek.key(DateTime.utc(2026, 9, 28)), '2026-W40');
      expect(
        LeaderboardWeek.key(DateTime.utc(2026, 10, 4, 23, 59)),
        '2026-W40',
      );
      expect(LeaderboardWeek.key(DateTime.utc(2026, 10, 5)), '2026-W41');
    });

    test('early January can belong to the previous year', () {
      // 1 Jan 2027 is a Friday, so it is in 2026's last week.
      expect(LeaderboardWeek.key(DateTime.utc(2027, 1, 1)), '2026-W53');
      expect(LeaderboardWeek.key(DateTime.utc(2027, 1, 4)), '2027-W01');
    });

    test('late December can belong to the next year', () {
      // 29 Dec 2025 is a Monday whose Thursday is 1 Jan 2026.
      expect(LeaderboardWeek.key(DateTime.utc(2025, 12, 29)), '2026-W01');
    });

    test('uses UTC, not local time', () {
      // Monday 7:00 AM in the Philippines is still Sunday in UTC.
      final phMondayMorning = DateTime.utc(2026, 10, 4, 23);
      expect(LeaderboardWeek.key(phMondayMorning), '2026-W40');
    });
  });

  group('LeaderboardWeek.endsAt', () {
    test('the week ends at the next Monday midnight UTC', () {
      expect(
        LeaderboardWeek.endsAt(DateTime.utc(2026, 10, 1, 15)),
        DateTime.utc(2026, 10, 5),
      );
    });

    test('on Monday it ends a week later', () {
      expect(
        LeaderboardWeek.endsAt(DateTime.utc(2026, 10, 5, 0, 1)),
        DateTime.utc(2026, 10, 12),
      );
    });
  });
}
