import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/ui_state_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late UiStateRepository repository;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repository = UiStateRepository(db);
  });

  tearDown(() => db.close());

  test('readUiState is null before the first write', () async {
    expect(await repository.readUiState(), isNull);
  });

  test('setLastTab round-trips through readUiState', () async {
    await repository.setLastTab('shopping');

    expect((await repository.readUiState())?.lastTab, 'shopping');
  });

  test('a second setLastTab overwrites, keeping a single row', () async {
    await repository.setLastTab('shopping');
    await repository.setLastTab('settings');

    expect((await repository.readUiState())?.lastTab, 'settings');
    expect(await db.select(db.uiState).get(), hasLength(1));
  });

  test('setChoresFilters round-trips both filters', () async {
    await repository.setChoresFilters(memberId: 'm1', categoryId: 'c1');

    final row = await repository.readUiState();
    expect(row?.choresMemberFilter, 'm1');
    expect(row?.choresCategoryFilter, 'c1');
  });

  test('setChoresFilters with nulls clears both filters', () async {
    await repository.setChoresFilters(memberId: 'm1', categoryId: 'c1');
    await repository.setChoresFilters(memberId: null, categoryId: null);

    final row = await repository.readUiState();
    expect(row?.choresMemberFilter, isNull);
    expect(row?.choresCategoryFilter, isNull);
    expect(await db.select(db.uiState).get(), hasLength(1));
  });

  test('the all-members sentinel round-trips verbatim', () async {
    await repository.setChoresFilters(
      memberId: UiStateRepository.allMembersFilter,
      categoryId: null,
    );

    final row = await repository.readUiState();
    expect(row?.choresMemberFilter, 'all');
  });

  test('setChoresFilters leaves last_tab alone', () async {
    await repository.setLastTab('shopping');
    await repository.setChoresFilters(memberId: 'm1', categoryId: null);

    final row = await repository.readUiState();
    expect(row?.lastTab, 'shopping');
    expect(row?.choresMemberFilter, 'm1');
  });

  test('setLastTab leaves the filters alone', () async {
    await repository.setChoresFilters(memberId: 'm1', categoryId: 'c1');
    await repository.setLastTab('settings');

    final row = await repository.readUiState();
    expect(row?.lastTab, 'settings');
    expect(row?.choresMemberFilter, 'm1');
    expect(row?.choresCategoryFilter, 'c1');
  });
}
