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

  test('readLastTab is null before the first write', () async {
    expect(await repository.readLastTab(), isNull);
  });

  test('setLastTab round-trips through readLastTab', () async {
    await repository.setLastTab('shopping');

    expect(await repository.readLastTab(), 'shopping');
  });

  test('a second setLastTab overwrites, keeping a single row', () async {
    await repository.setLastTab('shopping');
    await repository.setLastTab('settings');

    expect(await repository.readLastTab(), 'settings');
    expect(await db.select(db.uiState).get(), hasLength(1));
  });
}
