import 'package:flutter_test/flutter_test.dart';
import 'package:todo_client/models/todo_models.dart';

void main() {
  test('03:59:59 Beijing still belongs to the preceding task day', () {
    expect(
      taskDateForInstant(DateTime.parse('2026-10-19T19:59:59Z')),
      DateTime(2026, 10, 19),
    );
  });
  test('04:00 Beijing starts the next task day', () {
    expect(
      taskDateForInstant(DateTime.parse('2026-10-19T20:00:00Z')),
      DateTime(2026, 10, 20),
    );
  });
  test('year and leap-day boundaries use the same rule', () {
    expect(
      taskDateForInstant(DateTime.parse('2026-12-31T19:59:59Z')),
      DateTime(2026, 12, 31),
    );
    expect(
      taskDateForInstant(DateTime.parse('2026-12-31T20:00:00Z')),
      DateTime(2027, 1, 1),
    );
    expect(
      taskDateForInstant(DateTime.parse('2028-02-29T20:00:00Z')),
      DateTime(2028, 3, 1),
    );
  });
}
