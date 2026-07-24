import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/features/chores/chore_form/form_validation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('validateTitle', () {
    test('empty title returns TitleError.required', () {
      expect(validateTitle(''), TitleError.required);
    });

    test('non-empty title returns null', () {
      expect(validateTitle('Wash dishes'), isNull);
    });
  });

  group('validateInterval', () {
    test('non-numeric input returns IntervalError.tooSmall', () {
      expect(validateInterval('abc'), IntervalError.tooSmall);
    });

    test('zero returns IntervalError.tooSmall', () {
      expect(validateInterval('0'), IntervalError.tooSmall);
    });

    test('negative number returns IntervalError.tooSmall', () {
      expect(validateInterval('-1'), IntervalError.tooSmall);
    });

    test('positive integer returns null', () {
      expect(validateInterval('2'), isNull);
    });

    test('surrounding whitespace is trimmed before parsing', () {
      expect(validateInterval('  3  '), isNull);
    });
  });

  group('validateAssignment', () {
    test('fixed with zero members returns needsOneMember', () {
      expect(
        validateAssignment(
          mode: AssignmentMode.fixed,
          selectedMemberIds: const [],
        ),
        AssignmentError.needsOneMember,
      );
    });

    test('fixed with exactly one member returns null', () {
      expect(
        validateAssignment(
          mode: AssignmentMode.fixed,
          selectedMemberIds: const ['m1'],
        ),
        isNull,
      );
    });

    test('fixed with two members returns needsOneMember', () {
      expect(
        validateAssignment(
          mode: AssignmentMode.fixed,
          selectedMemberIds: const ['m1', 'm2'],
        ),
        AssignmentError.needsOneMember,
      );
    });

    test('rotation with one member returns needsTwoMembers', () {
      expect(
        validateAssignment(
          mode: AssignmentMode.rotation,
          selectedMemberIds: const ['m1'],
        ),
        AssignmentError.needsTwoMembers,
      );
    });

    test('rotation with two members returns null', () {
      expect(
        validateAssignment(
          mode: AssignmentMode.rotation,
          selectedMemberIds: const ['m1', 'm2'],
        ),
        isNull,
      );
    });

    test('anyone with zero members returns null', () {
      expect(
        validateAssignment(
          mode: AssignmentMode.anyone,
          selectedMemberIds: const [],
        ),
        isNull,
      );
    });
  });
}
