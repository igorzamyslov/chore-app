/// The `members` push payload must satisfy the server's `members_insert`
/// policy, which requires `user_id is null`.
///
/// **This is the check whose absence shipped a bug.** Both client push
/// sites -- `SupabaseSyncEngine._pushMembers` and
/// `SupabaseHouseholdGateway.uploadHouseholdData` -- send `memberRow(...)`
/// through `.upsert(..., ignoreDuplicates: true)`. That form was chosen to
/// dodge a *privilege* trap (members has a column-scoped UPDATE grant, and
/// Postgres checks UPDATE privilege on every column of an ON CONFLICT DO
/// UPDATE list at plan time). It does nothing about the *policy*:
///
/// ```sql
/// create policy members_insert on public.members
///   for insert with check (
///     public.is_household_member(household_id) and user_id is null
///   );
/// ```
///
/// Claiming a profile is the claim RPCs' job exclusively -- `user_id` is
/// not even UPDATE-granted -- so the client has no business pushing the
/// column at all. `supabase/tests/002_membership_exit_test.sql` says the
/// same in its own words, and has to `reset role` to superuser just to
/// create a claimed row in a fixture.
///
/// Observed in production 2026-09-18 as `POST /rest/v1/members -> 403`
/// on every sync once the acting member's own row was dirty. It surfaced
/// as "Couldn't reach the household" because `refreshNow()` pushes before
/// it pulls and catches everything, so a rejected members push aborts a
/// refresh whose pull would have succeeded.
///
/// Note `ON CONFLICT DO NOTHING` does NOT save it: Postgres applies the
/// INSERT `WITH CHECK` to the proposed tuple whether or not it is later
/// skipped for a conflict. Confirmed against the live project -- the row
/// was present server-side and the insert was still rejected.
library;

import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/db/tables.dart';
import 'package:chore_app/data/sync/row_mappers.dart';
import 'package:flutter_test/flutter_test.dart';

Member _member({String? userId}) => Member(
  syncDirty: true,
  id: 'member-1',
  householdId: 'household-1',
  name: 'Igor',
  color: 0xFF4E7E54,
  role: MemberRole.admin,
  userId: userId,
  createdAt: '2026-09-18T11:00:00.000Z',
  updatedAt: '2026-09-18T11:00:00.000Z',
);

void main() {
  test(
    'memberRow never carries user_id, so an insert of a CLAIMED member '
    'still satisfies the members_insert policy (user_id is null)',
    () {
      final claimed = memberRow(
        _member(userId: 'ee78bfc4-27d3-4276-8e94-b6eeef061fa4'),
      );
      expect(
        claimed.containsKey('user_id'),
        isFalse,
        reason:
            'the server rejects an insert whose user_id is non-null; the '
            'claim RPCs own that column and the client must not push it',
      );
    },
  );

  test(
    'the push shape is otherwise unchanged -- the columns the client DOES '
    'own still travel',
    () {
      final row = memberRow(_member(userId: 'some-auth-uid'));
      expect(row, {
        'id': 'member-1',
        'household_id': 'household-1',
        'name': 'Igor',
        'color': 0xFF4E7E54,
        'role': 'admin',
        'created_at': '2026-09-18T11:00:00.000Z',
        'updated_at': '2026-09-18T11:00:00.000Z',
        'deleted_at': null,
      });
    },
  );

  test('an unclaimed member produces the identical payload', () {
    expect(memberRow(_member()), memberRow(_member(userId: 'a-uid')));
  });
}
