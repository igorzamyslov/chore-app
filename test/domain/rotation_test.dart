import 'package:chore_app/domain/rotation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('nextRotationAssignee', () {
    test('wraps around from the last member to the first', () {
      expect(
        nextRotationAssignee(
          orderedMemberIds: ['a', 'b', 'c'],
          lastAssignedMemberId: 'c',
        ),
        'a',
      );
    });

    test('returns the member after the last assigned one', () {
      expect(
        nextRotationAssignee(
          orderedMemberIds: ['a', 'b', 'c'],
          lastAssignedMemberId: 'a',
        ),
        'b',
      );
    });

    test('returns the first member when lastAssignedMemberId is null', () {
      expect(
        nextRotationAssignee(
          orderedMemberIds: ['a', 'b', 'c'],
          lastAssignedMemberId: null,
        ),
        'a',
      );
    });

    test(
      'falls back to the first member when lastAssignedMemberId is no '
      'longer in the list',
      () {
        expect(
          nextRotationAssignee(
            orderedMemberIds: ['a', 'b', 'c'],
            lastAssignedMemberId: 'removed-member',
          ),
          'a',
        );
      },
    );

    test('a single-member rotation always returns that member', () {
      expect(
        nextRotationAssignee(
          orderedMemberIds: ['solo'],
          lastAssignedMemberId: 'solo',
        ),
        'solo',
      );
      expect(
        nextRotationAssignee(
          orderedMemberIds: ['solo'],
          lastAssignedMemberId: null,
        ),
        'solo',
      );
    });

    test('throws ArgumentError on an empty list', () {
      expect(
        () => nextRotationAssignee(
          orderedMemberIds: [],
          lastAssignedMemberId: null,
        ),
        throwsArgumentError,
      );
    });

    group('skipMemberId (covering for someone)', () {
      test('skips the coverer when they would be next', () {
        // Two people: A covers B's turn -> B again, not A.
        expect(
          nextRotationAssignee(
            orderedMemberIds: ['a', 'b'],
            lastAssignedMemberId: 'b',
            skipMemberId: 'a',
          ),
          'b',
        );
        // A -> B -> C: A covers C's turn -> B, not A.
        expect(
          nextRotationAssignee(
            orderedMemberIds: ['a', 'b', 'c'],
            lastAssignedMemberId: 'c',
            skipMemberId: 'a',
          ),
          'b',
        );
      });

      test('changes nothing when the coverer would not be next', () {
        expect(
          nextRotationAssignee(
            orderedMemberIds: ['a', 'b', 'c'],
            lastAssignedMemberId: 'b',
            skipMemberId: 'a',
          ),
          'c',
        );
      });

      test('changes nothing when the assignee did their own turn', () {
        expect(
          nextRotationAssignee(
            orderedMemberIds: ['a', 'b', 'c'],
            lastAssignedMemberId: 'b',
            skipMemberId: 'b',
          ),
          'c',
        );
      });

      test('also applies to the null / removed-member fallback', () {
        expect(
          nextRotationAssignee(
            orderedMemberIds: ['a', 'b', 'c'],
            lastAssignedMemberId: null,
            skipMemberId: 'a',
          ),
          'b',
        );
      });

      test('a single-member rotation still returns that member', () {
        expect(
          nextRotationAssignee(
            orderedMemberIds: ['solo'],
            lastAssignedMemberId: 'solo',
            skipMemberId: 'solo',
          ),
          'solo',
        );
      });
    });
  });
}
