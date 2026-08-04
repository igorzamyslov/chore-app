import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/category_repository.dart';
import 'package:chore_app/data/repositories/household_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

class _IdGen {
  int _next = 0;
  String call() => 'id-${_next++}';
}

class _FixedClock {
  _FixedClock(this._now);
  DateTime _now;
  DateTime call() => _now;
  void advance(Duration duration) => _now = _now.add(duration);
}

void main() {
  late AppDatabase db;
  late HouseholdRepository repo;
  late _FixedClock clock;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    clock = _FixedClock(DateTime.utc(2026));
    repo = HouseholdRepository(db, newId: _IdGen().call, nowUtc: clock.call);
  });

  tearDown(() => db.close());

  test('createLocalHousehold is idempotent', () async {
    final first = await repo.createLocalHousehold('Me');
    // The second call's name argument is ignored: a household already
    // exists, so the existing row (and its member) is returned untouched.
    final second = await repo.createLocalHousehold('Someone else');

    expect(first.id, second.id);
    expect(first.name, 'My household');

    final households = await db.select(db.households).get();
    expect(households, hasLength(1));

    final members = await db.select(db.members).get();
    expect(members, hasLength(1));
    expect(members.single.name, 'Me');
    expect(members.single.role, MemberRole.admin);
    expect(members.single.color, CategoryRepository.seedColors.first);
  });

  // Ordering changed from name to creation time by
  // `docs/specs/members-management.md` §2 (stable, matches the chore-form
  // chips, the members screen, and the acting-member switcher).
  test(
    'watchMembers orders by creation time and reacts to additions',
    () async {
      final household = await repo.createLocalHousehold('Me');
      final emissions = <List<String>>[];
      final sub = repo
          .watchMembers(household.id)
          .listen(
            (members) => emissions.add([for (final m in members) m.name]),
          );
      addTearDown(sub.cancel);

      await pumpEventQueue();
      await repo.addMember(household.id, name: 'Zoe', color: 0xFF111111);
      await repo.addMember(household.id, name: 'Alice', color: 0xFF222222);
      await pumpEventQueue();

      expect(emissions.last, ['Me', 'Zoe', 'Alice']);
    },
  );

  test('addMember defaults to the member role', () async {
    final household = await repo.createLocalHousehold('Me');
    final member = await repo.addMember(
      household.id,
      name: 'Bo',
      color: 0xFF333333,
    );
    expect(member.role, MemberRole.member);
  });

  test('renameMember updates the name and bumps updated_at', () async {
    final household = await repo.createLocalHousehold('Me');
    final member = await repo.addMember(
      household.id,
      name: 'Bo',
      color: 0xFF333333,
    );
    clock.advance(const Duration(minutes: 5));

    await repo.renameMember(member.id, 'Robert');

    final updated = await (db.select(
      db.members,
    )..where((tbl) => tbl.id.equals(member.id))).getSingle();
    expect(updated.name, 'Robert');
    expect(updated.updatedAt, isNot(member.updatedAt));
  });

  test('recolorMember updates the color and bumps updated_at', () async {
    final household = await repo.createLocalHousehold('Me');
    final member = await repo.addMember(
      household.id,
      name: 'Bo',
      color: 0xFF333333,
    );
    clock.advance(const Duration(minutes: 5));

    await repo.recolorMember(member.id, 0xFF444444);

    final updated = await (db.select(
      db.members,
    )..where((tbl) => tbl.id.equals(member.id))).getSingle();
    expect(updated.color, 0xFF444444);
    expect(updated.name, 'Bo');
    expect(updated.updatedAt, isNot(member.updatedAt));
  });

  test('getHousehold returns null before any household is created', () async {
    expect(await repo.getHousehold(), isNull);
  });

  test('getHousehold returns the existing household once created', () async {
    final created = await repo.createLocalHousehold('Me');

    final found = await repo.getHousehold();

    expect(found, isNotNull);
    expect(found!.id, created.id);
  });

  test(
    'watchHouseholdOrNull emits null then the household once created',
    () async {
      final emissions = <String?>[];
      final sub = repo.watchHouseholdOrNull().listen(
        (household) => emissions.add(household?.id),
      );
      addTearDown(sub.cancel);

      await pumpEventQueue();
      expect(emissions, [null]);

      final created = await repo.createLocalHousehold('Me');
      await pumpEventQueue();

      expect(emissions.last, created.id);
    },
  );
}
