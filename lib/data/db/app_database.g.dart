// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $HouseholdsTable extends Households
    with TableInfo<$HouseholdsTable, Household> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $HouseholdsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _syncDirtyMeta = const VerificationMeta(
    'syncDirty',
  );
  @override
  late final GeneratedColumn<bool> syncDirty = GeneratedColumn<bool>(
    'sync_dirty',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("sync_dirty" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<String> updatedAt = GeneratedColumn<String>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    syncDirty,
    id,
    name,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'households';
  @override
  VerificationContext validateIntegrity(
    Insertable<Household> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('sync_dirty')) {
      context.handle(
        _syncDirtyMeta,
        syncDirty.isAcceptableOrUnknown(data['sync_dirty']!, _syncDirtyMeta),
      );
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Household map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Household(
      syncDirty: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}sync_dirty'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $HouseholdsTable createAlias(String alias) {
    return $HouseholdsTable(attachedDatabase, alias);
  }
}

class Household extends DataClass implements Insertable<Household> {
  /// Whether this row has local changes not yet confirmed pushed to the
  /// server. Default `false`: a linked device's existing rows are already
  /// on the server (P2 uploaded/downloaded them), and an unlinked device
  /// never pushes anyway.
  final bool syncDirty;

  /// UUIDv4 primary key.
  final String id;

  /// Display name of the household.
  final String name;

  /// ISO-8601 UTC creation timestamp.
  final String createdAt;

  /// ISO-8601 UTC timestamp of the last update.
  final String updatedAt;
  const Household({
    required this.syncDirty,
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['sync_dirty'] = Variable<bool>(syncDirty);
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['created_at'] = Variable<String>(createdAt);
    map['updated_at'] = Variable<String>(updatedAt);
    return map;
  }

  HouseholdsCompanion toCompanion(bool nullToAbsent) {
    return HouseholdsCompanion(
      syncDirty: Value(syncDirty),
      id: Value(id),
      name: Value(name),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Household.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Household(
      syncDirty: serializer.fromJson<bool>(json['syncDirty']),
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      createdAt: serializer.fromJson<String>(json['createdAt']),
      updatedAt: serializer.fromJson<String>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'syncDirty': serializer.toJson<bool>(syncDirty),
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'createdAt': serializer.toJson<String>(createdAt),
      'updatedAt': serializer.toJson<String>(updatedAt),
    };
  }

  Household copyWith({
    bool? syncDirty,
    String? id,
    String? name,
    String? createdAt,
    String? updatedAt,
  }) => Household(
    syncDirty: syncDirty ?? this.syncDirty,
    id: id ?? this.id,
    name: name ?? this.name,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Household copyWithCompanion(HouseholdsCompanion data) {
    return Household(
      syncDirty: data.syncDirty.present ? data.syncDirty.value : this.syncDirty,
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Household(')
          ..write('syncDirty: $syncDirty, ')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(syncDirty, id, name, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Household &&
          other.syncDirty == this.syncDirty &&
          other.id == this.id &&
          other.name == this.name &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class HouseholdsCompanion extends UpdateCompanion<Household> {
  final Value<bool> syncDirty;
  final Value<String> id;
  final Value<String> name;
  final Value<String> createdAt;
  final Value<String> updatedAt;
  final Value<int> rowid;
  const HouseholdsCompanion({
    this.syncDirty = const Value.absent(),
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  HouseholdsCompanion.insert({
    this.syncDirty = const Value.absent(),
    required String id,
    required String name,
    required String createdAt,
    required String updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<Household> custom({
    Expression<bool>? syncDirty,
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? createdAt,
    Expression<String>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (syncDirty != null) 'sync_dirty': syncDirty,
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  HouseholdsCompanion copyWith({
    Value<bool>? syncDirty,
    Value<String>? id,
    Value<String>? name,
    Value<String>? createdAt,
    Value<String>? updatedAt,
    Value<int>? rowid,
  }) {
    return HouseholdsCompanion(
      syncDirty: syncDirty ?? this.syncDirty,
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (syncDirty.present) {
      map['sync_dirty'] = Variable<bool>(syncDirty.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('HouseholdsCompanion(')
          ..write('syncDirty: $syncDirty, ')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MembersTable extends Members with TableInfo<$MembersTable, Member> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MembersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _syncDirtyMeta = const VerificationMeta(
    'syncDirty',
  );
  @override
  late final GeneratedColumn<bool> syncDirty = GeneratedColumn<bool>(
    'sync_dirty',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("sync_dirty" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _householdIdMeta = const VerificationMeta(
    'householdId',
  );
  @override
  late final GeneratedColumn<String> householdId = GeneratedColumn<String>(
    'household_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES households (id)',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _colorMeta = const VerificationMeta('color');
  @override
  late final GeneratedColumn<int> color = GeneratedColumn<int>(
    'color',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<MemberRole, String> role =
      GeneratedColumn<String>(
        'role',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<MemberRole>($MembersTable.$converterrole);
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<String> updatedAt = GeneratedColumn<String>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<String> deletedAt = GeneratedColumn<String>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    syncDirty,
    id,
    householdId,
    name,
    color,
    role,
    userId,
    createdAt,
    updatedAt,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'members';
  @override
  VerificationContext validateIntegrity(
    Insertable<Member> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('sync_dirty')) {
      context.handle(
        _syncDirtyMeta,
        syncDirty.isAcceptableOrUnknown(data['sync_dirty']!, _syncDirtyMeta),
      );
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('household_id')) {
      context.handle(
        _householdIdMeta,
        householdId.isAcceptableOrUnknown(
          data['household_id']!,
          _householdIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_householdIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('color')) {
      context.handle(
        _colorMeta,
        color.isAcceptableOrUnknown(data['color']!, _colorMeta),
      );
    } else if (isInserting) {
      context.missing(_colorMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Member map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Member(
      syncDirty: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}sync_dirty'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      householdId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}household_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      color: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}color'],
      )!,
      role: $MembersTable.$converterrole.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}role'],
        )!,
      ),
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $MembersTable createAlias(String alias) {
    return $MembersTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<MemberRole, String, String> $converterrole =
      const EnumNameConverter(MemberRole.values);
}

class Member extends DataClass implements Insertable<Member> {
  /// Whether this row has local changes not yet confirmed pushed to the
  /// server. Default `false`: a linked device's existing rows are already
  /// on the server (P2 uploaded/downloaded them), and an unlinked device
  /// never pushes anyway.
  final bool syncDirty;

  /// UUIDv4 primary key.
  final String id;

  /// The household this member belongs to.
  final String householdId;

  /// Display name.
  final String name;

  /// ARGB color used to represent this member in the UI.
  final int color;

  /// This member's [MemberRole]. VESTIGIAL (D1, `docs/specs/sync-backend.md`
  /// §2): written once at creation, and gates nothing -- no RLS policy, no
  /// RPC, no widget. The household is flat by design; do not add
  /// enforcement against this column without a spec change.
  final MemberRole role;

  /// Future auth-provider user id mapping; unused in v1.
  final String? userId;

  /// ISO-8601 UTC creation timestamp.
  final String createdAt;

  /// ISO-8601 UTC timestamp of the last update.
  final String updatedAt;

  /// ISO-8601 UTC soft-delete timestamp; `NULL` means active. Added in
  /// schemaVersion 9 (spec `docs/feedback/2026-08-01-ux-audit.md` A1): the
  /// server column (`members.deleted_at`) has existed since P1 and is
  /// already UPDATE-granted -- this just catches the client up so a member
  /// can finally be removed. Roster queries (`HouseholdRepository
  /// .watchMembers` and everything built on it) exclude soft-deleted rows;
  /// history-display joins (done-today, occurrence assignee avatars,
  /// `completedBy`) deliberately keep resolving them so past attribution
  /// stays readable. See `MemberService.deleteMember`
  /// (`lib/application/member_service.dart`) for the referential cleanup
  /// that runs alongside the soft delete.
  final String? deletedAt;
  const Member({
    required this.syncDirty,
    required this.id,
    required this.householdId,
    required this.name,
    required this.color,
    required this.role,
    this.userId,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['sync_dirty'] = Variable<bool>(syncDirty);
    map['id'] = Variable<String>(id);
    map['household_id'] = Variable<String>(householdId);
    map['name'] = Variable<String>(name);
    map['color'] = Variable<int>(color);
    {
      map['role'] = Variable<String>($MembersTable.$converterrole.toSql(role));
    }
    if (!nullToAbsent || userId != null) {
      map['user_id'] = Variable<String>(userId);
    }
    map['created_at'] = Variable<String>(createdAt);
    map['updated_at'] = Variable<String>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<String>(deletedAt);
    }
    return map;
  }

  MembersCompanion toCompanion(bool nullToAbsent) {
    return MembersCompanion(
      syncDirty: Value(syncDirty),
      id: Value(id),
      householdId: Value(householdId),
      name: Value(name),
      color: Value(color),
      role: Value(role),
      userId: userId == null && nullToAbsent
          ? const Value.absent()
          : Value(userId),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory Member.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Member(
      syncDirty: serializer.fromJson<bool>(json['syncDirty']),
      id: serializer.fromJson<String>(json['id']),
      householdId: serializer.fromJson<String>(json['householdId']),
      name: serializer.fromJson<String>(json['name']),
      color: serializer.fromJson<int>(json['color']),
      role: $MembersTable.$converterrole.fromJson(
        serializer.fromJson<String>(json['role']),
      ),
      userId: serializer.fromJson<String?>(json['userId']),
      createdAt: serializer.fromJson<String>(json['createdAt']),
      updatedAt: serializer.fromJson<String>(json['updatedAt']),
      deletedAt: serializer.fromJson<String?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'syncDirty': serializer.toJson<bool>(syncDirty),
      'id': serializer.toJson<String>(id),
      'householdId': serializer.toJson<String>(householdId),
      'name': serializer.toJson<String>(name),
      'color': serializer.toJson<int>(color),
      'role': serializer.toJson<String>(
        $MembersTable.$converterrole.toJson(role),
      ),
      'userId': serializer.toJson<String?>(userId),
      'createdAt': serializer.toJson<String>(createdAt),
      'updatedAt': serializer.toJson<String>(updatedAt),
      'deletedAt': serializer.toJson<String?>(deletedAt),
    };
  }

  Member copyWith({
    bool? syncDirty,
    String? id,
    String? householdId,
    String? name,
    int? color,
    MemberRole? role,
    Value<String?> userId = const Value.absent(),
    String? createdAt,
    String? updatedAt,
    Value<String?> deletedAt = const Value.absent(),
  }) => Member(
    syncDirty: syncDirty ?? this.syncDirty,
    id: id ?? this.id,
    householdId: householdId ?? this.householdId,
    name: name ?? this.name,
    color: color ?? this.color,
    role: role ?? this.role,
    userId: userId.present ? userId.value : this.userId,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  Member copyWithCompanion(MembersCompanion data) {
    return Member(
      syncDirty: data.syncDirty.present ? data.syncDirty.value : this.syncDirty,
      id: data.id.present ? data.id.value : this.id,
      householdId: data.householdId.present
          ? data.householdId.value
          : this.householdId,
      name: data.name.present ? data.name.value : this.name,
      color: data.color.present ? data.color.value : this.color,
      role: data.role.present ? data.role.value : this.role,
      userId: data.userId.present ? data.userId.value : this.userId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Member(')
          ..write('syncDirty: $syncDirty, ')
          ..write('id: $id, ')
          ..write('householdId: $householdId, ')
          ..write('name: $name, ')
          ..write('color: $color, ')
          ..write('role: $role, ')
          ..write('userId: $userId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    syncDirty,
    id,
    householdId,
    name,
    color,
    role,
    userId,
    createdAt,
    updatedAt,
    deletedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Member &&
          other.syncDirty == this.syncDirty &&
          other.id == this.id &&
          other.householdId == this.householdId &&
          other.name == this.name &&
          other.color == this.color &&
          other.role == this.role &&
          other.userId == this.userId &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt);
}

class MembersCompanion extends UpdateCompanion<Member> {
  final Value<bool> syncDirty;
  final Value<String> id;
  final Value<String> householdId;
  final Value<String> name;
  final Value<int> color;
  final Value<MemberRole> role;
  final Value<String?> userId;
  final Value<String> createdAt;
  final Value<String> updatedAt;
  final Value<String?> deletedAt;
  final Value<int> rowid;
  const MembersCompanion({
    this.syncDirty = const Value.absent(),
    this.id = const Value.absent(),
    this.householdId = const Value.absent(),
    this.name = const Value.absent(),
    this.color = const Value.absent(),
    this.role = const Value.absent(),
    this.userId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MembersCompanion.insert({
    this.syncDirty = const Value.absent(),
    required String id,
    required String householdId,
    required String name,
    required int color,
    required MemberRole role,
    this.userId = const Value.absent(),
    required String createdAt,
    required String updatedAt,
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       householdId = Value(householdId),
       name = Value(name),
       color = Value(color),
       role = Value(role),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<Member> custom({
    Expression<bool>? syncDirty,
    Expression<String>? id,
    Expression<String>? householdId,
    Expression<String>? name,
    Expression<int>? color,
    Expression<String>? role,
    Expression<String>? userId,
    Expression<String>? createdAt,
    Expression<String>? updatedAt,
    Expression<String>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (syncDirty != null) 'sync_dirty': syncDirty,
      if (id != null) 'id': id,
      if (householdId != null) 'household_id': householdId,
      if (name != null) 'name': name,
      if (color != null) 'color': color,
      if (role != null) 'role': role,
      if (userId != null) 'user_id': userId,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MembersCompanion copyWith({
    Value<bool>? syncDirty,
    Value<String>? id,
    Value<String>? householdId,
    Value<String>? name,
    Value<int>? color,
    Value<MemberRole>? role,
    Value<String?>? userId,
    Value<String>? createdAt,
    Value<String>? updatedAt,
    Value<String?>? deletedAt,
    Value<int>? rowid,
  }) {
    return MembersCompanion(
      syncDirty: syncDirty ?? this.syncDirty,
      id: id ?? this.id,
      householdId: householdId ?? this.householdId,
      name: name ?? this.name,
      color: color ?? this.color,
      role: role ?? this.role,
      userId: userId ?? this.userId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (syncDirty.present) {
      map['sync_dirty'] = Variable<bool>(syncDirty.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (householdId.present) {
      map['household_id'] = Variable<String>(householdId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (color.present) {
      map['color'] = Variable<int>(color.value);
    }
    if (role.present) {
      map['role'] = Variable<String>(
        $MembersTable.$converterrole.toSql(role.value),
      );
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<String>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MembersCompanion(')
          ..write('syncDirty: $syncDirty, ')
          ..write('id: $id, ')
          ..write('householdId: $householdId, ')
          ..write('name: $name, ')
          ..write('color: $color, ')
          ..write('role: $role, ')
          ..write('userId: $userId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CategoriesTable extends Categories
    with TableInfo<$CategoriesTable, Category> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CategoriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _syncDirtyMeta = const VerificationMeta(
    'syncDirty',
  );
  @override
  late final GeneratedColumn<bool> syncDirty = GeneratedColumn<bool>(
    'sync_dirty',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("sync_dirty" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _householdIdMeta = const VerificationMeta(
    'householdId',
  );
  @override
  late final GeneratedColumn<String> householdId = GeneratedColumn<String>(
    'household_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES households (id)',
    ),
  );
  @override
  late final GeneratedColumnWithTypeConverter<CategoryKind, String> kind =
      GeneratedColumn<String>(
        'kind',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<CategoryKind>($CategoriesTable.$converterkind);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _iconMeta = const VerificationMeta('icon');
  @override
  late final GeneratedColumn<String> icon = GeneratedColumn<String>(
    'icon',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _colorMeta = const VerificationMeta('color');
  @override
  late final GeneratedColumn<int> color = GeneratedColumn<int>(
    'color',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<String> updatedAt = GeneratedColumn<String>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<String> deletedAt = GeneratedColumn<String>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    syncDirty,
    id,
    householdId,
    kind,
    name,
    icon,
    color,
    sortOrder,
    createdAt,
    updatedAt,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'categories';
  @override
  VerificationContext validateIntegrity(
    Insertable<Category> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('sync_dirty')) {
      context.handle(
        _syncDirtyMeta,
        syncDirty.isAcceptableOrUnknown(data['sync_dirty']!, _syncDirtyMeta),
      );
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('household_id')) {
      context.handle(
        _householdIdMeta,
        householdId.isAcceptableOrUnknown(
          data['household_id']!,
          _householdIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_householdIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('icon')) {
      context.handle(
        _iconMeta,
        icon.isAcceptableOrUnknown(data['icon']!, _iconMeta),
      );
    } else if (isInserting) {
      context.missing(_iconMeta);
    }
    if (data.containsKey('color')) {
      context.handle(
        _colorMeta,
        color.isAcceptableOrUnknown(data['color']!, _colorMeta),
      );
    } else if (isInserting) {
      context.missing(_colorMeta);
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Category map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Category(
      syncDirty: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}sync_dirty'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      householdId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}household_id'],
      )!,
      kind: $CategoriesTable.$converterkind.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}kind'],
        )!,
      ),
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      icon: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}icon'],
      )!,
      color: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}color'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $CategoriesTable createAlias(String alias) {
    return $CategoriesTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<CategoryKind, String, String> $converterkind =
      const EnumNameConverter(CategoryKind.values);
}

class Category extends DataClass implements Insertable<Category> {
  /// Whether this row has local changes not yet confirmed pushed to the
  /// server. Default `false`: a linked device's existing rows are already
  /// on the server (P2 uploaded/downloaded them), and an unlinked device
  /// never pushes anyway.
  final bool syncDirty;

  /// UUIDv4 primary key.
  final String id;

  /// The household this category belongs to.
  final String householdId;

  /// Whether this category organizes chores or shopping items.
  final CategoryKind kind;

  /// Display name.
  final String name;

  /// Material Symbols icon identifier, e.g. `cleaning_services`.
  final String icon;

  /// ARGB color used to represent this category in the UI.
  final int color;

  /// Manual ordering position among categories of the same [kind].
  final int sortOrder;

  /// ISO-8601 UTC creation timestamp.
  final String createdAt;

  /// ISO-8601 UTC timestamp of the last update.
  final String updatedAt;

  /// ISO-8601 UTC soft-delete timestamp; `NULL` means active.
  final String? deletedAt;
  const Category({
    required this.syncDirty,
    required this.id,
    required this.householdId,
    required this.kind,
    required this.name,
    required this.icon,
    required this.color,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['sync_dirty'] = Variable<bool>(syncDirty);
    map['id'] = Variable<String>(id);
    map['household_id'] = Variable<String>(householdId);
    {
      map['kind'] = Variable<String>(
        $CategoriesTable.$converterkind.toSql(kind),
      );
    }
    map['name'] = Variable<String>(name);
    map['icon'] = Variable<String>(icon);
    map['color'] = Variable<int>(color);
    map['sort_order'] = Variable<int>(sortOrder);
    map['created_at'] = Variable<String>(createdAt);
    map['updated_at'] = Variable<String>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<String>(deletedAt);
    }
    return map;
  }

  CategoriesCompanion toCompanion(bool nullToAbsent) {
    return CategoriesCompanion(
      syncDirty: Value(syncDirty),
      id: Value(id),
      householdId: Value(householdId),
      kind: Value(kind),
      name: Value(name),
      icon: Value(icon),
      color: Value(color),
      sortOrder: Value(sortOrder),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory Category.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Category(
      syncDirty: serializer.fromJson<bool>(json['syncDirty']),
      id: serializer.fromJson<String>(json['id']),
      householdId: serializer.fromJson<String>(json['householdId']),
      kind: $CategoriesTable.$converterkind.fromJson(
        serializer.fromJson<String>(json['kind']),
      ),
      name: serializer.fromJson<String>(json['name']),
      icon: serializer.fromJson<String>(json['icon']),
      color: serializer.fromJson<int>(json['color']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      createdAt: serializer.fromJson<String>(json['createdAt']),
      updatedAt: serializer.fromJson<String>(json['updatedAt']),
      deletedAt: serializer.fromJson<String?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'syncDirty': serializer.toJson<bool>(syncDirty),
      'id': serializer.toJson<String>(id),
      'householdId': serializer.toJson<String>(householdId),
      'kind': serializer.toJson<String>(
        $CategoriesTable.$converterkind.toJson(kind),
      ),
      'name': serializer.toJson<String>(name),
      'icon': serializer.toJson<String>(icon),
      'color': serializer.toJson<int>(color),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'createdAt': serializer.toJson<String>(createdAt),
      'updatedAt': serializer.toJson<String>(updatedAt),
      'deletedAt': serializer.toJson<String?>(deletedAt),
    };
  }

  Category copyWith({
    bool? syncDirty,
    String? id,
    String? householdId,
    CategoryKind? kind,
    String? name,
    String? icon,
    int? color,
    int? sortOrder,
    String? createdAt,
    String? updatedAt,
    Value<String?> deletedAt = const Value.absent(),
  }) => Category(
    syncDirty: syncDirty ?? this.syncDirty,
    id: id ?? this.id,
    householdId: householdId ?? this.householdId,
    kind: kind ?? this.kind,
    name: name ?? this.name,
    icon: icon ?? this.icon,
    color: color ?? this.color,
    sortOrder: sortOrder ?? this.sortOrder,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  Category copyWithCompanion(CategoriesCompanion data) {
    return Category(
      syncDirty: data.syncDirty.present ? data.syncDirty.value : this.syncDirty,
      id: data.id.present ? data.id.value : this.id,
      householdId: data.householdId.present
          ? data.householdId.value
          : this.householdId,
      kind: data.kind.present ? data.kind.value : this.kind,
      name: data.name.present ? data.name.value : this.name,
      icon: data.icon.present ? data.icon.value : this.icon,
      color: data.color.present ? data.color.value : this.color,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Category(')
          ..write('syncDirty: $syncDirty, ')
          ..write('id: $id, ')
          ..write('householdId: $householdId, ')
          ..write('kind: $kind, ')
          ..write('name: $name, ')
          ..write('icon: $icon, ')
          ..write('color: $color, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    syncDirty,
    id,
    householdId,
    kind,
    name,
    icon,
    color,
    sortOrder,
    createdAt,
    updatedAt,
    deletedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Category &&
          other.syncDirty == this.syncDirty &&
          other.id == this.id &&
          other.householdId == this.householdId &&
          other.kind == this.kind &&
          other.name == this.name &&
          other.icon == this.icon &&
          other.color == this.color &&
          other.sortOrder == this.sortOrder &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt);
}

class CategoriesCompanion extends UpdateCompanion<Category> {
  final Value<bool> syncDirty;
  final Value<String> id;
  final Value<String> householdId;
  final Value<CategoryKind> kind;
  final Value<String> name;
  final Value<String> icon;
  final Value<int> color;
  final Value<int> sortOrder;
  final Value<String> createdAt;
  final Value<String> updatedAt;
  final Value<String?> deletedAt;
  final Value<int> rowid;
  const CategoriesCompanion({
    this.syncDirty = const Value.absent(),
    this.id = const Value.absent(),
    this.householdId = const Value.absent(),
    this.kind = const Value.absent(),
    this.name = const Value.absent(),
    this.icon = const Value.absent(),
    this.color = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CategoriesCompanion.insert({
    this.syncDirty = const Value.absent(),
    required String id,
    required String householdId,
    required CategoryKind kind,
    required String name,
    required String icon,
    required int color,
    this.sortOrder = const Value.absent(),
    required String createdAt,
    required String updatedAt,
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       householdId = Value(householdId),
       kind = Value(kind),
       name = Value(name),
       icon = Value(icon),
       color = Value(color),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<Category> custom({
    Expression<bool>? syncDirty,
    Expression<String>? id,
    Expression<String>? householdId,
    Expression<String>? kind,
    Expression<String>? name,
    Expression<String>? icon,
    Expression<int>? color,
    Expression<int>? sortOrder,
    Expression<String>? createdAt,
    Expression<String>? updatedAt,
    Expression<String>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (syncDirty != null) 'sync_dirty': syncDirty,
      if (id != null) 'id': id,
      if (householdId != null) 'household_id': householdId,
      if (kind != null) 'kind': kind,
      if (name != null) 'name': name,
      if (icon != null) 'icon': icon,
      if (color != null) 'color': color,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CategoriesCompanion copyWith({
    Value<bool>? syncDirty,
    Value<String>? id,
    Value<String>? householdId,
    Value<CategoryKind>? kind,
    Value<String>? name,
    Value<String>? icon,
    Value<int>? color,
    Value<int>? sortOrder,
    Value<String>? createdAt,
    Value<String>? updatedAt,
    Value<String?>? deletedAt,
    Value<int>? rowid,
  }) {
    return CategoriesCompanion(
      syncDirty: syncDirty ?? this.syncDirty,
      id: id ?? this.id,
      householdId: householdId ?? this.householdId,
      kind: kind ?? this.kind,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      color: color ?? this.color,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (syncDirty.present) {
      map['sync_dirty'] = Variable<bool>(syncDirty.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (householdId.present) {
      map['household_id'] = Variable<String>(householdId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(
        $CategoriesTable.$converterkind.toSql(kind.value),
      );
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (icon.present) {
      map['icon'] = Variable<String>(icon.value);
    }
    if (color.present) {
      map['color'] = Variable<int>(color.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<String>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CategoriesCompanion(')
          ..write('syncDirty: $syncDirty, ')
          ..write('id: $id, ')
          ..write('householdId: $householdId, ')
          ..write('kind: $kind, ')
          ..write('name: $name, ')
          ..write('icon: $icon, ')
          ..write('color: $color, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ChoresTable extends Chores with TableInfo<$ChoresTable, Chore> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChoresTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _syncDirtyMeta = const VerificationMeta(
    'syncDirty',
  );
  @override
  late final GeneratedColumn<bool> syncDirty = GeneratedColumn<bool>(
    'sync_dirty',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("sync_dirty" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _householdIdMeta = const VerificationMeta(
    'householdId',
  );
  @override
  late final GeneratedColumn<String> householdId = GeneratedColumn<String>(
    'household_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES households (id)',
    ),
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _categoryIdMeta = const VerificationMeta(
    'categoryId',
  );
  @override
  late final GeneratedColumn<String> categoryId = GeneratedColumn<String>(
    'category_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES categories (id)',
    ),
  );
  @override
  late final GeneratedColumnWithTypeConverter<Recurrence?, String> recurrence =
      GeneratedColumn<String>(
        'recurrence',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<Recurrence?>($ChoresTable.$converterrecurrence);
  @override
  late final GeneratedColumnWithTypeConverter<PlainDate, String> startDate =
      GeneratedColumn<String>(
        'start_date',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<PlainDate>($ChoresTable.$converterstartDate);
  @override
  late final GeneratedColumnWithTypeConverter<AssignmentMode, String>
  assignmentMode = GeneratedColumn<String>(
    'assignment_mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  ).withConverter<AssignmentMode>($ChoresTable.$converterassignmentMode);
  static const VerificationMeta _pausedAtMeta = const VerificationMeta(
    'pausedAt',
  );
  @override
  late final GeneratedColumn<String> pausedAt = GeneratedColumn<String>(
    'paused_at',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdByMeta = const VerificationMeta(
    'createdBy',
  );
  @override
  late final GeneratedColumn<String> createdBy = GeneratedColumn<String>(
    'created_by',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES members (id)',
    ),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<String> updatedAt = GeneratedColumn<String>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<String> deletedAt = GeneratedColumn<String>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    syncDirty,
    id,
    householdId,
    title,
    notes,
    categoryId,
    recurrence,
    startDate,
    assignmentMode,
    pausedAt,
    createdBy,
    createdAt,
    updatedAt,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'chores';
  @override
  VerificationContext validateIntegrity(
    Insertable<Chore> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('sync_dirty')) {
      context.handle(
        _syncDirtyMeta,
        syncDirty.isAcceptableOrUnknown(data['sync_dirty']!, _syncDirtyMeta),
      );
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('household_id')) {
      context.handle(
        _householdIdMeta,
        householdId.isAcceptableOrUnknown(
          data['household_id']!,
          _householdIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_householdIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('category_id')) {
      context.handle(
        _categoryIdMeta,
        categoryId.isAcceptableOrUnknown(data['category_id']!, _categoryIdMeta),
      );
    }
    if (data.containsKey('paused_at')) {
      context.handle(
        _pausedAtMeta,
        pausedAt.isAcceptableOrUnknown(data['paused_at']!, _pausedAtMeta),
      );
    }
    if (data.containsKey('created_by')) {
      context.handle(
        _createdByMeta,
        createdBy.isAcceptableOrUnknown(data['created_by']!, _createdByMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Chore map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Chore(
      syncDirty: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}sync_dirty'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      householdId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}household_id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      categoryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category_id'],
      ),
      recurrence: $ChoresTable.$converterrecurrence.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}recurrence'],
        ),
      ),
      startDate: $ChoresTable.$converterstartDate.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}start_date'],
        )!,
      ),
      assignmentMode: $ChoresTable.$converterassignmentMode.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}assignment_mode'],
        )!,
      ),
      pausedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}paused_at'],
      ),
      createdBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_by'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $ChoresTable createAlias(String alias) {
    return $ChoresTable(attachedDatabase, alias);
  }

  static TypeConverter<Recurrence?, String?> $converterrecurrence =
      const NullAwareTypeConverter.wrap(RecurrenceConverter());
  static TypeConverter<PlainDate, String> $converterstartDate =
      const PlainDateConverter();
  static JsonTypeConverter2<AssignmentMode, String, String>
  $converterassignmentMode = const EnumNameConverter(AssignmentMode.values);
}

class Chore extends DataClass implements Insertable<Chore> {
  /// Whether this row has local changes not yet confirmed pushed to the
  /// server. Default `false`: a linked device's existing rows are already
  /// on the server (P2 uploaded/downloaded them), and an unlinked device
  /// never pushes anyway.
  final bool syncDirty;

  /// UUIDv4 primary key.
  final String id;

  /// The household this chore belongs to.
  final String householdId;

  /// Display title.
  final String title;

  /// Optional free-text notes.
  final String? notes;

  /// Optional category.
  final String? categoryId;

  /// The recurrence rule, or `NULL` for a one-off chore.
  final Recurrence? recurrence;

  /// The date of the first occurrence / the anchor date for recurrence
  /// math.
  final PlainDate startDate;

  /// How occurrences of this chore are assigned to members.
  final AssignmentMode assignmentMode;

  /// Timestamp at which this chore was paused; `NULL` means unpaused.
  final String? pausedAt;

  /// The member who created this chore, if known.
  final String? createdBy;

  /// ISO-8601 UTC creation timestamp.
  final String createdAt;

  /// ISO-8601 UTC timestamp of the last update.
  final String updatedAt;

  /// ISO-8601 UTC soft-delete timestamp; `NULL` means active.
  final String? deletedAt;
  const Chore({
    required this.syncDirty,
    required this.id,
    required this.householdId,
    required this.title,
    this.notes,
    this.categoryId,
    this.recurrence,
    required this.startDate,
    required this.assignmentMode,
    this.pausedAt,
    this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['sync_dirty'] = Variable<bool>(syncDirty);
    map['id'] = Variable<String>(id);
    map['household_id'] = Variable<String>(householdId);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    if (!nullToAbsent || categoryId != null) {
      map['category_id'] = Variable<String>(categoryId);
    }
    if (!nullToAbsent || recurrence != null) {
      map['recurrence'] = Variable<String>(
        $ChoresTable.$converterrecurrence.toSql(recurrence),
      );
    }
    {
      map['start_date'] = Variable<String>(
        $ChoresTable.$converterstartDate.toSql(startDate),
      );
    }
    {
      map['assignment_mode'] = Variable<String>(
        $ChoresTable.$converterassignmentMode.toSql(assignmentMode),
      );
    }
    if (!nullToAbsent || pausedAt != null) {
      map['paused_at'] = Variable<String>(pausedAt);
    }
    if (!nullToAbsent || createdBy != null) {
      map['created_by'] = Variable<String>(createdBy);
    }
    map['created_at'] = Variable<String>(createdAt);
    map['updated_at'] = Variable<String>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<String>(deletedAt);
    }
    return map;
  }

  ChoresCompanion toCompanion(bool nullToAbsent) {
    return ChoresCompanion(
      syncDirty: Value(syncDirty),
      id: Value(id),
      householdId: Value(householdId),
      title: Value(title),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
      categoryId: categoryId == null && nullToAbsent
          ? const Value.absent()
          : Value(categoryId),
      recurrence: recurrence == null && nullToAbsent
          ? const Value.absent()
          : Value(recurrence),
      startDate: Value(startDate),
      assignmentMode: Value(assignmentMode),
      pausedAt: pausedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(pausedAt),
      createdBy: createdBy == null && nullToAbsent
          ? const Value.absent()
          : Value(createdBy),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory Chore.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Chore(
      syncDirty: serializer.fromJson<bool>(json['syncDirty']),
      id: serializer.fromJson<String>(json['id']),
      householdId: serializer.fromJson<String>(json['householdId']),
      title: serializer.fromJson<String>(json['title']),
      notes: serializer.fromJson<String?>(json['notes']),
      categoryId: serializer.fromJson<String?>(json['categoryId']),
      recurrence: serializer.fromJson<Recurrence?>(json['recurrence']),
      startDate: serializer.fromJson<PlainDate>(json['startDate']),
      assignmentMode: $ChoresTable.$converterassignmentMode.fromJson(
        serializer.fromJson<String>(json['assignmentMode']),
      ),
      pausedAt: serializer.fromJson<String?>(json['pausedAt']),
      createdBy: serializer.fromJson<String?>(json['createdBy']),
      createdAt: serializer.fromJson<String>(json['createdAt']),
      updatedAt: serializer.fromJson<String>(json['updatedAt']),
      deletedAt: serializer.fromJson<String?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'syncDirty': serializer.toJson<bool>(syncDirty),
      'id': serializer.toJson<String>(id),
      'householdId': serializer.toJson<String>(householdId),
      'title': serializer.toJson<String>(title),
      'notes': serializer.toJson<String?>(notes),
      'categoryId': serializer.toJson<String?>(categoryId),
      'recurrence': serializer.toJson<Recurrence?>(recurrence),
      'startDate': serializer.toJson<PlainDate>(startDate),
      'assignmentMode': serializer.toJson<String>(
        $ChoresTable.$converterassignmentMode.toJson(assignmentMode),
      ),
      'pausedAt': serializer.toJson<String?>(pausedAt),
      'createdBy': serializer.toJson<String?>(createdBy),
      'createdAt': serializer.toJson<String>(createdAt),
      'updatedAt': serializer.toJson<String>(updatedAt),
      'deletedAt': serializer.toJson<String?>(deletedAt),
    };
  }

  Chore copyWith({
    bool? syncDirty,
    String? id,
    String? householdId,
    String? title,
    Value<String?> notes = const Value.absent(),
    Value<String?> categoryId = const Value.absent(),
    Value<Recurrence?> recurrence = const Value.absent(),
    PlainDate? startDate,
    AssignmentMode? assignmentMode,
    Value<String?> pausedAt = const Value.absent(),
    Value<String?> createdBy = const Value.absent(),
    String? createdAt,
    String? updatedAt,
    Value<String?> deletedAt = const Value.absent(),
  }) => Chore(
    syncDirty: syncDirty ?? this.syncDirty,
    id: id ?? this.id,
    householdId: householdId ?? this.householdId,
    title: title ?? this.title,
    notes: notes.present ? notes.value : this.notes,
    categoryId: categoryId.present ? categoryId.value : this.categoryId,
    recurrence: recurrence.present ? recurrence.value : this.recurrence,
    startDate: startDate ?? this.startDate,
    assignmentMode: assignmentMode ?? this.assignmentMode,
    pausedAt: pausedAt.present ? pausedAt.value : this.pausedAt,
    createdBy: createdBy.present ? createdBy.value : this.createdBy,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  Chore copyWithCompanion(ChoresCompanion data) {
    return Chore(
      syncDirty: data.syncDirty.present ? data.syncDirty.value : this.syncDirty,
      id: data.id.present ? data.id.value : this.id,
      householdId: data.householdId.present
          ? data.householdId.value
          : this.householdId,
      title: data.title.present ? data.title.value : this.title,
      notes: data.notes.present ? data.notes.value : this.notes,
      categoryId: data.categoryId.present
          ? data.categoryId.value
          : this.categoryId,
      recurrence: data.recurrence.present
          ? data.recurrence.value
          : this.recurrence,
      startDate: data.startDate.present ? data.startDate.value : this.startDate,
      assignmentMode: data.assignmentMode.present
          ? data.assignmentMode.value
          : this.assignmentMode,
      pausedAt: data.pausedAt.present ? data.pausedAt.value : this.pausedAt,
      createdBy: data.createdBy.present ? data.createdBy.value : this.createdBy,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Chore(')
          ..write('syncDirty: $syncDirty, ')
          ..write('id: $id, ')
          ..write('householdId: $householdId, ')
          ..write('title: $title, ')
          ..write('notes: $notes, ')
          ..write('categoryId: $categoryId, ')
          ..write('recurrence: $recurrence, ')
          ..write('startDate: $startDate, ')
          ..write('assignmentMode: $assignmentMode, ')
          ..write('pausedAt: $pausedAt, ')
          ..write('createdBy: $createdBy, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    syncDirty,
    id,
    householdId,
    title,
    notes,
    categoryId,
    recurrence,
    startDate,
    assignmentMode,
    pausedAt,
    createdBy,
    createdAt,
    updatedAt,
    deletedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Chore &&
          other.syncDirty == this.syncDirty &&
          other.id == this.id &&
          other.householdId == this.householdId &&
          other.title == this.title &&
          other.notes == this.notes &&
          other.categoryId == this.categoryId &&
          other.recurrence == this.recurrence &&
          other.startDate == this.startDate &&
          other.assignmentMode == this.assignmentMode &&
          other.pausedAt == this.pausedAt &&
          other.createdBy == this.createdBy &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt);
}

class ChoresCompanion extends UpdateCompanion<Chore> {
  final Value<bool> syncDirty;
  final Value<String> id;
  final Value<String> householdId;
  final Value<String> title;
  final Value<String?> notes;
  final Value<String?> categoryId;
  final Value<Recurrence?> recurrence;
  final Value<PlainDate> startDate;
  final Value<AssignmentMode> assignmentMode;
  final Value<String?> pausedAt;
  final Value<String?> createdBy;
  final Value<String> createdAt;
  final Value<String> updatedAt;
  final Value<String?> deletedAt;
  final Value<int> rowid;
  const ChoresCompanion({
    this.syncDirty = const Value.absent(),
    this.id = const Value.absent(),
    this.householdId = const Value.absent(),
    this.title = const Value.absent(),
    this.notes = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.recurrence = const Value.absent(),
    this.startDate = const Value.absent(),
    this.assignmentMode = const Value.absent(),
    this.pausedAt = const Value.absent(),
    this.createdBy = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ChoresCompanion.insert({
    this.syncDirty = const Value.absent(),
    required String id,
    required String householdId,
    required String title,
    this.notes = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.recurrence = const Value.absent(),
    required PlainDate startDate,
    required AssignmentMode assignmentMode,
    this.pausedAt = const Value.absent(),
    this.createdBy = const Value.absent(),
    required String createdAt,
    required String updatedAt,
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       householdId = Value(householdId),
       title = Value(title),
       startDate = Value(startDate),
       assignmentMode = Value(assignmentMode),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<Chore> custom({
    Expression<bool>? syncDirty,
    Expression<String>? id,
    Expression<String>? householdId,
    Expression<String>? title,
    Expression<String>? notes,
    Expression<String>? categoryId,
    Expression<String>? recurrence,
    Expression<String>? startDate,
    Expression<String>? assignmentMode,
    Expression<String>? pausedAt,
    Expression<String>? createdBy,
    Expression<String>? createdAt,
    Expression<String>? updatedAt,
    Expression<String>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (syncDirty != null) 'sync_dirty': syncDirty,
      if (id != null) 'id': id,
      if (householdId != null) 'household_id': householdId,
      if (title != null) 'title': title,
      if (notes != null) 'notes': notes,
      if (categoryId != null) 'category_id': categoryId,
      if (recurrence != null) 'recurrence': recurrence,
      if (startDate != null) 'start_date': startDate,
      if (assignmentMode != null) 'assignment_mode': assignmentMode,
      if (pausedAt != null) 'paused_at': pausedAt,
      if (createdBy != null) 'created_by': createdBy,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ChoresCompanion copyWith({
    Value<bool>? syncDirty,
    Value<String>? id,
    Value<String>? householdId,
    Value<String>? title,
    Value<String?>? notes,
    Value<String?>? categoryId,
    Value<Recurrence?>? recurrence,
    Value<PlainDate>? startDate,
    Value<AssignmentMode>? assignmentMode,
    Value<String?>? pausedAt,
    Value<String?>? createdBy,
    Value<String>? createdAt,
    Value<String>? updatedAt,
    Value<String?>? deletedAt,
    Value<int>? rowid,
  }) {
    return ChoresCompanion(
      syncDirty: syncDirty ?? this.syncDirty,
      id: id ?? this.id,
      householdId: householdId ?? this.householdId,
      title: title ?? this.title,
      notes: notes ?? this.notes,
      categoryId: categoryId ?? this.categoryId,
      recurrence: recurrence ?? this.recurrence,
      startDate: startDate ?? this.startDate,
      assignmentMode: assignmentMode ?? this.assignmentMode,
      pausedAt: pausedAt ?? this.pausedAt,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (syncDirty.present) {
      map['sync_dirty'] = Variable<bool>(syncDirty.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (householdId.present) {
      map['household_id'] = Variable<String>(householdId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (categoryId.present) {
      map['category_id'] = Variable<String>(categoryId.value);
    }
    if (recurrence.present) {
      map['recurrence'] = Variable<String>(
        $ChoresTable.$converterrecurrence.toSql(recurrence.value),
      );
    }
    if (startDate.present) {
      map['start_date'] = Variable<String>(
        $ChoresTable.$converterstartDate.toSql(startDate.value),
      );
    }
    if (assignmentMode.present) {
      map['assignment_mode'] = Variable<String>(
        $ChoresTable.$converterassignmentMode.toSql(assignmentMode.value),
      );
    }
    if (pausedAt.present) {
      map['paused_at'] = Variable<String>(pausedAt.value);
    }
    if (createdBy.present) {
      map['created_by'] = Variable<String>(createdBy.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<String>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChoresCompanion(')
          ..write('syncDirty: $syncDirty, ')
          ..write('id: $id, ')
          ..write('householdId: $householdId, ')
          ..write('title: $title, ')
          ..write('notes: $notes, ')
          ..write('categoryId: $categoryId, ')
          ..write('recurrence: $recurrence, ')
          ..write('startDate: $startDate, ')
          ..write('assignmentMode: $assignmentMode, ')
          ..write('pausedAt: $pausedAt, ')
          ..write('createdBy: $createdBy, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ChoreAssigneesTable extends ChoreAssignees
    with TableInfo<$ChoreAssigneesTable, ChoreAssignee> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChoreAssigneesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _syncDirtyMeta = const VerificationMeta(
    'syncDirty',
  );
  @override
  late final GeneratedColumn<bool> syncDirty = GeneratedColumn<bool>(
    'sync_dirty',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("sync_dirty" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _choreIdMeta = const VerificationMeta(
    'choreId',
  );
  @override
  late final GeneratedColumn<String> choreId = GeneratedColumn<String>(
    'chore_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES chores (id)',
    ),
  );
  static const VerificationMeta _memberIdMeta = const VerificationMeta(
    'memberId',
  );
  @override
  late final GeneratedColumn<String> memberId = GeneratedColumn<String>(
    'member_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES members (id)',
    ),
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    syncDirty,
    choreId,
    memberId,
    position,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'chore_assignees';
  @override
  VerificationContext validateIntegrity(
    Insertable<ChoreAssignee> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('sync_dirty')) {
      context.handle(
        _syncDirtyMeta,
        syncDirty.isAcceptableOrUnknown(data['sync_dirty']!, _syncDirtyMeta),
      );
    }
    if (data.containsKey('chore_id')) {
      context.handle(
        _choreIdMeta,
        choreId.isAcceptableOrUnknown(data['chore_id']!, _choreIdMeta),
      );
    } else if (isInserting) {
      context.missing(_choreIdMeta);
    }
    if (data.containsKey('member_id')) {
      context.handle(
        _memberIdMeta,
        memberId.isAcceptableOrUnknown(data['member_id']!, _memberIdMeta),
      );
    } else if (isInserting) {
      context.missing(_memberIdMeta);
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {choreId, memberId};
  @override
  ChoreAssignee map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ChoreAssignee(
      syncDirty: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}sync_dirty'],
      )!,
      choreId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}chore_id'],
      )!,
      memberId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}member_id'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
    );
  }

  @override
  $ChoreAssigneesTable createAlias(String alias) {
    return $ChoreAssigneesTable(attachedDatabase, alias);
  }
}

class ChoreAssignee extends DataClass implements Insertable<ChoreAssignee> {
  /// Whether this row has local changes not yet confirmed pushed to the
  /// server. Default `false`: a linked device's existing rows are already
  /// on the server (P2 uploaded/downloaded them), and an unlinked device
  /// never pushes anyway.
  final bool syncDirty;

  /// The chore being assigned.
  final String choreId;

  /// The assigned member.
  final String memberId;

  /// 0-based rotation order.
  final int position;
  const ChoreAssignee({
    required this.syncDirty,
    required this.choreId,
    required this.memberId,
    required this.position,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['sync_dirty'] = Variable<bool>(syncDirty);
    map['chore_id'] = Variable<String>(choreId);
    map['member_id'] = Variable<String>(memberId);
    map['position'] = Variable<int>(position);
    return map;
  }

  ChoreAssigneesCompanion toCompanion(bool nullToAbsent) {
    return ChoreAssigneesCompanion(
      syncDirty: Value(syncDirty),
      choreId: Value(choreId),
      memberId: Value(memberId),
      position: Value(position),
    );
  }

  factory ChoreAssignee.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ChoreAssignee(
      syncDirty: serializer.fromJson<bool>(json['syncDirty']),
      choreId: serializer.fromJson<String>(json['choreId']),
      memberId: serializer.fromJson<String>(json['memberId']),
      position: serializer.fromJson<int>(json['position']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'syncDirty': serializer.toJson<bool>(syncDirty),
      'choreId': serializer.toJson<String>(choreId),
      'memberId': serializer.toJson<String>(memberId),
      'position': serializer.toJson<int>(position),
    };
  }

  ChoreAssignee copyWith({
    bool? syncDirty,
    String? choreId,
    String? memberId,
    int? position,
  }) => ChoreAssignee(
    syncDirty: syncDirty ?? this.syncDirty,
    choreId: choreId ?? this.choreId,
    memberId: memberId ?? this.memberId,
    position: position ?? this.position,
  );
  ChoreAssignee copyWithCompanion(ChoreAssigneesCompanion data) {
    return ChoreAssignee(
      syncDirty: data.syncDirty.present ? data.syncDirty.value : this.syncDirty,
      choreId: data.choreId.present ? data.choreId.value : this.choreId,
      memberId: data.memberId.present ? data.memberId.value : this.memberId,
      position: data.position.present ? data.position.value : this.position,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ChoreAssignee(')
          ..write('syncDirty: $syncDirty, ')
          ..write('choreId: $choreId, ')
          ..write('memberId: $memberId, ')
          ..write('position: $position')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(syncDirty, choreId, memberId, position);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ChoreAssignee &&
          other.syncDirty == this.syncDirty &&
          other.choreId == this.choreId &&
          other.memberId == this.memberId &&
          other.position == this.position);
}

class ChoreAssigneesCompanion extends UpdateCompanion<ChoreAssignee> {
  final Value<bool> syncDirty;
  final Value<String> choreId;
  final Value<String> memberId;
  final Value<int> position;
  final Value<int> rowid;
  const ChoreAssigneesCompanion({
    this.syncDirty = const Value.absent(),
    this.choreId = const Value.absent(),
    this.memberId = const Value.absent(),
    this.position = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ChoreAssigneesCompanion.insert({
    this.syncDirty = const Value.absent(),
    required String choreId,
    required String memberId,
    required int position,
    this.rowid = const Value.absent(),
  }) : choreId = Value(choreId),
       memberId = Value(memberId),
       position = Value(position);
  static Insertable<ChoreAssignee> custom({
    Expression<bool>? syncDirty,
    Expression<String>? choreId,
    Expression<String>? memberId,
    Expression<int>? position,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (syncDirty != null) 'sync_dirty': syncDirty,
      if (choreId != null) 'chore_id': choreId,
      if (memberId != null) 'member_id': memberId,
      if (position != null) 'position': position,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ChoreAssigneesCompanion copyWith({
    Value<bool>? syncDirty,
    Value<String>? choreId,
    Value<String>? memberId,
    Value<int>? position,
    Value<int>? rowid,
  }) {
    return ChoreAssigneesCompanion(
      syncDirty: syncDirty ?? this.syncDirty,
      choreId: choreId ?? this.choreId,
      memberId: memberId ?? this.memberId,
      position: position ?? this.position,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (syncDirty.present) {
      map['sync_dirty'] = Variable<bool>(syncDirty.value);
    }
    if (choreId.present) {
      map['chore_id'] = Variable<String>(choreId.value);
    }
    if (memberId.present) {
      map['member_id'] = Variable<String>(memberId.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChoreAssigneesCompanion(')
          ..write('syncDirty: $syncDirty, ')
          ..write('choreId: $choreId, ')
          ..write('memberId: $memberId, ')
          ..write('position: $position, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ChoreOccurrencesTable extends ChoreOccurrences
    with TableInfo<$ChoreOccurrencesTable, ChoreOccurrence> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChoreOccurrencesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _syncDirtyMeta = const VerificationMeta(
    'syncDirty',
  );
  @override
  late final GeneratedColumn<bool> syncDirty = GeneratedColumn<bool>(
    'sync_dirty',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("sync_dirty" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _choreIdMeta = const VerificationMeta(
    'choreId',
  );
  @override
  late final GeneratedColumn<String> choreId = GeneratedColumn<String>(
    'chore_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES chores (id)',
    ),
  );
  @override
  late final GeneratedColumnWithTypeConverter<PlainDate, String> dueDate =
      GeneratedColumn<String>(
        'due_date',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<PlainDate>($ChoreOccurrencesTable.$converterdueDate);
  @override
  late final GeneratedColumnWithTypeConverter<OccurrenceStatus, String> status =
      GeneratedColumn<String>(
        'status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: Constant(OccurrenceStatus.pending.name),
      ).withConverter<OccurrenceStatus>(
        $ChoreOccurrencesTable.$converterstatus,
      );
  static const VerificationMeta _assignedMemberIdMeta = const VerificationMeta(
    'assignedMemberId',
  );
  @override
  late final GeneratedColumn<String> assignedMemberId = GeneratedColumn<String>(
    'assigned_member_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES members (id)',
    ),
  );
  static const VerificationMeta _completedByMeta = const VerificationMeta(
    'completedBy',
  );
  @override
  late final GeneratedColumn<String> completedBy = GeneratedColumn<String>(
    'completed_by',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES members (id)',
    ),
  );
  @override
  late final GeneratedColumnWithTypeConverter<PlainDate?, String> closedOn =
      GeneratedColumn<String>(
        'closed_on',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<PlainDate?>($ChoreOccurrencesTable.$converterclosedOn);
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<String> updatedAt = GeneratedColumn<String>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    syncDirty,
    id,
    choreId,
    dueDate,
    status,
    assignedMemberId,
    completedBy,
    closedOn,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'chore_occurrences';
  @override
  VerificationContext validateIntegrity(
    Insertable<ChoreOccurrence> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('sync_dirty')) {
      context.handle(
        _syncDirtyMeta,
        syncDirty.isAcceptableOrUnknown(data['sync_dirty']!, _syncDirtyMeta),
      );
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('chore_id')) {
      context.handle(
        _choreIdMeta,
        choreId.isAcceptableOrUnknown(data['chore_id']!, _choreIdMeta),
      );
    } else if (isInserting) {
      context.missing(_choreIdMeta);
    }
    if (data.containsKey('assigned_member_id')) {
      context.handle(
        _assignedMemberIdMeta,
        assignedMemberId.isAcceptableOrUnknown(
          data['assigned_member_id']!,
          _assignedMemberIdMeta,
        ),
      );
    }
    if (data.containsKey('completed_by')) {
      context.handle(
        _completedByMeta,
        completedBy.isAcceptableOrUnknown(
          data['completed_by']!,
          _completedByMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ChoreOccurrence map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ChoreOccurrence(
      syncDirty: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}sync_dirty'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      choreId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}chore_id'],
      )!,
      dueDate: $ChoreOccurrencesTable.$converterdueDate.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}due_date'],
        )!,
      ),
      status: $ChoreOccurrencesTable.$converterstatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}status'],
        )!,
      ),
      assignedMemberId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}assigned_member_id'],
      ),
      completedBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}completed_by'],
      ),
      closedOn: $ChoreOccurrencesTable.$converterclosedOn.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}closed_on'],
        ),
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ChoreOccurrencesTable createAlias(String alias) {
    return $ChoreOccurrencesTable(attachedDatabase, alias);
  }

  static TypeConverter<PlainDate, String> $converterdueDate =
      const PlainDateConverter();
  static JsonTypeConverter2<OccurrenceStatus, String, String> $converterstatus =
      const EnumNameConverter(OccurrenceStatus.values);
  static TypeConverter<PlainDate?, String?> $converterclosedOn =
      const NullAwareTypeConverter.wrap(PlainDateConverter());
}

class ChoreOccurrence extends DataClass implements Insertable<ChoreOccurrence> {
  /// Whether this row has local changes not yet confirmed pushed to the
  /// server. Default `false`: a linked device's existing rows are already
  /// on the server (P2 uploaded/downloaded them), and an unlinked device
  /// never pushes anyway.
  final bool syncDirty;

  /// UUIDv4 primary key.
  final String id;

  /// The chore this occurrence belongs to.
  final String choreId;

  /// The calendar date this occurrence is due.
  final PlainDate dueDate;

  /// The current lifecycle state.
  final OccurrenceStatus status;

  /// The member this occurrence is assigned to, if any.
  final String? assignedMemberId;

  /// The member who completed this occurrence, if any.
  final String? completedBy;

  /// The calendar date the user closed this occurrence on, if closed.
  final PlainDate? closedOn;

  /// ISO-8601 UTC creation timestamp.
  final String createdAt;

  /// ISO-8601 UTC timestamp of the last update.
  final String updatedAt;
  const ChoreOccurrence({
    required this.syncDirty,
    required this.id,
    required this.choreId,
    required this.dueDate,
    required this.status,
    this.assignedMemberId,
    this.completedBy,
    this.closedOn,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['sync_dirty'] = Variable<bool>(syncDirty);
    map['id'] = Variable<String>(id);
    map['chore_id'] = Variable<String>(choreId);
    {
      map['due_date'] = Variable<String>(
        $ChoreOccurrencesTable.$converterdueDate.toSql(dueDate),
      );
    }
    {
      map['status'] = Variable<String>(
        $ChoreOccurrencesTable.$converterstatus.toSql(status),
      );
    }
    if (!nullToAbsent || assignedMemberId != null) {
      map['assigned_member_id'] = Variable<String>(assignedMemberId);
    }
    if (!nullToAbsent || completedBy != null) {
      map['completed_by'] = Variable<String>(completedBy);
    }
    if (!nullToAbsent || closedOn != null) {
      map['closed_on'] = Variable<String>(
        $ChoreOccurrencesTable.$converterclosedOn.toSql(closedOn),
      );
    }
    map['created_at'] = Variable<String>(createdAt);
    map['updated_at'] = Variable<String>(updatedAt);
    return map;
  }

  ChoreOccurrencesCompanion toCompanion(bool nullToAbsent) {
    return ChoreOccurrencesCompanion(
      syncDirty: Value(syncDirty),
      id: Value(id),
      choreId: Value(choreId),
      dueDate: Value(dueDate),
      status: Value(status),
      assignedMemberId: assignedMemberId == null && nullToAbsent
          ? const Value.absent()
          : Value(assignedMemberId),
      completedBy: completedBy == null && nullToAbsent
          ? const Value.absent()
          : Value(completedBy),
      closedOn: closedOn == null && nullToAbsent
          ? const Value.absent()
          : Value(closedOn),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory ChoreOccurrence.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ChoreOccurrence(
      syncDirty: serializer.fromJson<bool>(json['syncDirty']),
      id: serializer.fromJson<String>(json['id']),
      choreId: serializer.fromJson<String>(json['choreId']),
      dueDate: serializer.fromJson<PlainDate>(json['dueDate']),
      status: $ChoreOccurrencesTable.$converterstatus.fromJson(
        serializer.fromJson<String>(json['status']),
      ),
      assignedMemberId: serializer.fromJson<String?>(json['assignedMemberId']),
      completedBy: serializer.fromJson<String?>(json['completedBy']),
      closedOn: serializer.fromJson<PlainDate?>(json['closedOn']),
      createdAt: serializer.fromJson<String>(json['createdAt']),
      updatedAt: serializer.fromJson<String>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'syncDirty': serializer.toJson<bool>(syncDirty),
      'id': serializer.toJson<String>(id),
      'choreId': serializer.toJson<String>(choreId),
      'dueDate': serializer.toJson<PlainDate>(dueDate),
      'status': serializer.toJson<String>(
        $ChoreOccurrencesTable.$converterstatus.toJson(status),
      ),
      'assignedMemberId': serializer.toJson<String?>(assignedMemberId),
      'completedBy': serializer.toJson<String?>(completedBy),
      'closedOn': serializer.toJson<PlainDate?>(closedOn),
      'createdAt': serializer.toJson<String>(createdAt),
      'updatedAt': serializer.toJson<String>(updatedAt),
    };
  }

  ChoreOccurrence copyWith({
    bool? syncDirty,
    String? id,
    String? choreId,
    PlainDate? dueDate,
    OccurrenceStatus? status,
    Value<String?> assignedMemberId = const Value.absent(),
    Value<String?> completedBy = const Value.absent(),
    Value<PlainDate?> closedOn = const Value.absent(),
    String? createdAt,
    String? updatedAt,
  }) => ChoreOccurrence(
    syncDirty: syncDirty ?? this.syncDirty,
    id: id ?? this.id,
    choreId: choreId ?? this.choreId,
    dueDate: dueDate ?? this.dueDate,
    status: status ?? this.status,
    assignedMemberId: assignedMemberId.present
        ? assignedMemberId.value
        : this.assignedMemberId,
    completedBy: completedBy.present ? completedBy.value : this.completedBy,
    closedOn: closedOn.present ? closedOn.value : this.closedOn,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  ChoreOccurrence copyWithCompanion(ChoreOccurrencesCompanion data) {
    return ChoreOccurrence(
      syncDirty: data.syncDirty.present ? data.syncDirty.value : this.syncDirty,
      id: data.id.present ? data.id.value : this.id,
      choreId: data.choreId.present ? data.choreId.value : this.choreId,
      dueDate: data.dueDate.present ? data.dueDate.value : this.dueDate,
      status: data.status.present ? data.status.value : this.status,
      assignedMemberId: data.assignedMemberId.present
          ? data.assignedMemberId.value
          : this.assignedMemberId,
      completedBy: data.completedBy.present
          ? data.completedBy.value
          : this.completedBy,
      closedOn: data.closedOn.present ? data.closedOn.value : this.closedOn,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ChoreOccurrence(')
          ..write('syncDirty: $syncDirty, ')
          ..write('id: $id, ')
          ..write('choreId: $choreId, ')
          ..write('dueDate: $dueDate, ')
          ..write('status: $status, ')
          ..write('assignedMemberId: $assignedMemberId, ')
          ..write('completedBy: $completedBy, ')
          ..write('closedOn: $closedOn, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    syncDirty,
    id,
    choreId,
    dueDate,
    status,
    assignedMemberId,
    completedBy,
    closedOn,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ChoreOccurrence &&
          other.syncDirty == this.syncDirty &&
          other.id == this.id &&
          other.choreId == this.choreId &&
          other.dueDate == this.dueDate &&
          other.status == this.status &&
          other.assignedMemberId == this.assignedMemberId &&
          other.completedBy == this.completedBy &&
          other.closedOn == this.closedOn &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class ChoreOccurrencesCompanion extends UpdateCompanion<ChoreOccurrence> {
  final Value<bool> syncDirty;
  final Value<String> id;
  final Value<String> choreId;
  final Value<PlainDate> dueDate;
  final Value<OccurrenceStatus> status;
  final Value<String?> assignedMemberId;
  final Value<String?> completedBy;
  final Value<PlainDate?> closedOn;
  final Value<String> createdAt;
  final Value<String> updatedAt;
  final Value<int> rowid;
  const ChoreOccurrencesCompanion({
    this.syncDirty = const Value.absent(),
    this.id = const Value.absent(),
    this.choreId = const Value.absent(),
    this.dueDate = const Value.absent(),
    this.status = const Value.absent(),
    this.assignedMemberId = const Value.absent(),
    this.completedBy = const Value.absent(),
    this.closedOn = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ChoreOccurrencesCompanion.insert({
    this.syncDirty = const Value.absent(),
    required String id,
    required String choreId,
    required PlainDate dueDate,
    this.status = const Value.absent(),
    this.assignedMemberId = const Value.absent(),
    this.completedBy = const Value.absent(),
    this.closedOn = const Value.absent(),
    required String createdAt,
    required String updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       choreId = Value(choreId),
       dueDate = Value(dueDate),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<ChoreOccurrence> custom({
    Expression<bool>? syncDirty,
    Expression<String>? id,
    Expression<String>? choreId,
    Expression<String>? dueDate,
    Expression<String>? status,
    Expression<String>? assignedMemberId,
    Expression<String>? completedBy,
    Expression<String>? closedOn,
    Expression<String>? createdAt,
    Expression<String>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (syncDirty != null) 'sync_dirty': syncDirty,
      if (id != null) 'id': id,
      if (choreId != null) 'chore_id': choreId,
      if (dueDate != null) 'due_date': dueDate,
      if (status != null) 'status': status,
      if (assignedMemberId != null) 'assigned_member_id': assignedMemberId,
      if (completedBy != null) 'completed_by': completedBy,
      if (closedOn != null) 'closed_on': closedOn,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ChoreOccurrencesCompanion copyWith({
    Value<bool>? syncDirty,
    Value<String>? id,
    Value<String>? choreId,
    Value<PlainDate>? dueDate,
    Value<OccurrenceStatus>? status,
    Value<String?>? assignedMemberId,
    Value<String?>? completedBy,
    Value<PlainDate?>? closedOn,
    Value<String>? createdAt,
    Value<String>? updatedAt,
    Value<int>? rowid,
  }) {
    return ChoreOccurrencesCompanion(
      syncDirty: syncDirty ?? this.syncDirty,
      id: id ?? this.id,
      choreId: choreId ?? this.choreId,
      dueDate: dueDate ?? this.dueDate,
      status: status ?? this.status,
      assignedMemberId: assignedMemberId ?? this.assignedMemberId,
      completedBy: completedBy ?? this.completedBy,
      closedOn: closedOn ?? this.closedOn,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (syncDirty.present) {
      map['sync_dirty'] = Variable<bool>(syncDirty.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (choreId.present) {
      map['chore_id'] = Variable<String>(choreId.value);
    }
    if (dueDate.present) {
      map['due_date'] = Variable<String>(
        $ChoreOccurrencesTable.$converterdueDate.toSql(dueDate.value),
      );
    }
    if (status.present) {
      map['status'] = Variable<String>(
        $ChoreOccurrencesTable.$converterstatus.toSql(status.value),
      );
    }
    if (assignedMemberId.present) {
      map['assigned_member_id'] = Variable<String>(assignedMemberId.value);
    }
    if (completedBy.present) {
      map['completed_by'] = Variable<String>(completedBy.value);
    }
    if (closedOn.present) {
      map['closed_on'] = Variable<String>(
        $ChoreOccurrencesTable.$converterclosedOn.toSql(closedOn.value),
      );
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChoreOccurrencesCompanion(')
          ..write('syncDirty: $syncDirty, ')
          ..write('id: $id, ')
          ..write('choreId: $choreId, ')
          ..write('dueDate: $dueDate, ')
          ..write('status: $status, ')
          ..write('assignedMemberId: $assignedMemberId, ')
          ..write('completedBy: $completedBy, ')
          ..write('closedOn: $closedOn, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ShoppingItemsTable extends ShoppingItems
    with TableInfo<$ShoppingItemsTable, ShoppingItem> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ShoppingItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _syncDirtyMeta = const VerificationMeta(
    'syncDirty',
  );
  @override
  late final GeneratedColumn<bool> syncDirty = GeneratedColumn<bool>(
    'sync_dirty',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("sync_dirty" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _householdIdMeta = const VerificationMeta(
    'householdId',
  );
  @override
  late final GeneratedColumn<String> householdId = GeneratedColumn<String>(
    'household_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES households (id)',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _quantityNoteMeta = const VerificationMeta(
    'quantityNote',
  );
  @override
  late final GeneratedColumn<String> quantityNote = GeneratedColumn<String>(
    'quantity_note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _categoryIdMeta = const VerificationMeta(
    'categoryId',
  );
  @override
  late final GeneratedColumn<String> categoryId = GeneratedColumn<String>(
    'category_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES categories (id)',
    ),
  );
  static const VerificationMeta _addedByMeta = const VerificationMeta(
    'addedBy',
  );
  @override
  late final GeneratedColumn<String> addedBy = GeneratedColumn<String>(
    'added_by',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES members (id)',
    ),
  );
  static const VerificationMeta _checkedAtMeta = const VerificationMeta(
    'checkedAt',
  );
  @override
  late final GeneratedColumn<String> checkedAt = GeneratedColumn<String>(
    'checked_at',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<String> updatedAt = GeneratedColumn<String>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<String> deletedAt = GeneratedColumn<String>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    syncDirty,
    id,
    householdId,
    name,
    quantityNote,
    categoryId,
    addedBy,
    checkedAt,
    createdAt,
    updatedAt,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'shopping_items';
  @override
  VerificationContext validateIntegrity(
    Insertable<ShoppingItem> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('sync_dirty')) {
      context.handle(
        _syncDirtyMeta,
        syncDirty.isAcceptableOrUnknown(data['sync_dirty']!, _syncDirtyMeta),
      );
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('household_id')) {
      context.handle(
        _householdIdMeta,
        householdId.isAcceptableOrUnknown(
          data['household_id']!,
          _householdIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_householdIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('quantity_note')) {
      context.handle(
        _quantityNoteMeta,
        quantityNote.isAcceptableOrUnknown(
          data['quantity_note']!,
          _quantityNoteMeta,
        ),
      );
    }
    if (data.containsKey('category_id')) {
      context.handle(
        _categoryIdMeta,
        categoryId.isAcceptableOrUnknown(data['category_id']!, _categoryIdMeta),
      );
    }
    if (data.containsKey('added_by')) {
      context.handle(
        _addedByMeta,
        addedBy.isAcceptableOrUnknown(data['added_by']!, _addedByMeta),
      );
    }
    if (data.containsKey('checked_at')) {
      context.handle(
        _checkedAtMeta,
        checkedAt.isAcceptableOrUnknown(data['checked_at']!, _checkedAtMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ShoppingItem map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ShoppingItem(
      syncDirty: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}sync_dirty'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      householdId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}household_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      quantityNote: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}quantity_note'],
      ),
      categoryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category_id'],
      ),
      addedBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}added_by'],
      ),
      checkedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}checked_at'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $ShoppingItemsTable createAlias(String alias) {
    return $ShoppingItemsTable(attachedDatabase, alias);
  }
}

class ShoppingItem extends DataClass implements Insertable<ShoppingItem> {
  /// Whether this row has local changes not yet confirmed pushed to the
  /// server. Default `false`: a linked device's existing rows are already
  /// on the server (P2 uploaded/downloaded them), and an unlinked device
  /// never pushes anyway.
  final bool syncDirty;

  /// UUIDv4 primary key.
  final String id;

  /// The household this item belongs to.
  final String householdId;

  /// Display name.
  final String name;

  /// Optional free-text quantity or note, e.g. `"2 bottles"`.
  final String? quantityNote;

  /// Optional category.
  final String? categoryId;

  /// The member who added this item, if known.
  final String? addedBy;

  /// Timestamp at which this item was checked off; `NULL` means unchecked.
  final String? checkedAt;

  /// ISO-8601 UTC creation timestamp.
  final String createdAt;

  /// ISO-8601 UTC timestamp of the last update.
  final String updatedAt;

  /// ISO-8601 UTC soft-delete timestamp; `NULL` means active.
  final String? deletedAt;
  const ShoppingItem({
    required this.syncDirty,
    required this.id,
    required this.householdId,
    required this.name,
    this.quantityNote,
    this.categoryId,
    this.addedBy,
    this.checkedAt,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['sync_dirty'] = Variable<bool>(syncDirty);
    map['id'] = Variable<String>(id);
    map['household_id'] = Variable<String>(householdId);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || quantityNote != null) {
      map['quantity_note'] = Variable<String>(quantityNote);
    }
    if (!nullToAbsent || categoryId != null) {
      map['category_id'] = Variable<String>(categoryId);
    }
    if (!nullToAbsent || addedBy != null) {
      map['added_by'] = Variable<String>(addedBy);
    }
    if (!nullToAbsent || checkedAt != null) {
      map['checked_at'] = Variable<String>(checkedAt);
    }
    map['created_at'] = Variable<String>(createdAt);
    map['updated_at'] = Variable<String>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<String>(deletedAt);
    }
    return map;
  }

  ShoppingItemsCompanion toCompanion(bool nullToAbsent) {
    return ShoppingItemsCompanion(
      syncDirty: Value(syncDirty),
      id: Value(id),
      householdId: Value(householdId),
      name: Value(name),
      quantityNote: quantityNote == null && nullToAbsent
          ? const Value.absent()
          : Value(quantityNote),
      categoryId: categoryId == null && nullToAbsent
          ? const Value.absent()
          : Value(categoryId),
      addedBy: addedBy == null && nullToAbsent
          ? const Value.absent()
          : Value(addedBy),
      checkedAt: checkedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(checkedAt),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory ShoppingItem.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ShoppingItem(
      syncDirty: serializer.fromJson<bool>(json['syncDirty']),
      id: serializer.fromJson<String>(json['id']),
      householdId: serializer.fromJson<String>(json['householdId']),
      name: serializer.fromJson<String>(json['name']),
      quantityNote: serializer.fromJson<String?>(json['quantityNote']),
      categoryId: serializer.fromJson<String?>(json['categoryId']),
      addedBy: serializer.fromJson<String?>(json['addedBy']),
      checkedAt: serializer.fromJson<String?>(json['checkedAt']),
      createdAt: serializer.fromJson<String>(json['createdAt']),
      updatedAt: serializer.fromJson<String>(json['updatedAt']),
      deletedAt: serializer.fromJson<String?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'syncDirty': serializer.toJson<bool>(syncDirty),
      'id': serializer.toJson<String>(id),
      'householdId': serializer.toJson<String>(householdId),
      'name': serializer.toJson<String>(name),
      'quantityNote': serializer.toJson<String?>(quantityNote),
      'categoryId': serializer.toJson<String?>(categoryId),
      'addedBy': serializer.toJson<String?>(addedBy),
      'checkedAt': serializer.toJson<String?>(checkedAt),
      'createdAt': serializer.toJson<String>(createdAt),
      'updatedAt': serializer.toJson<String>(updatedAt),
      'deletedAt': serializer.toJson<String?>(deletedAt),
    };
  }

  ShoppingItem copyWith({
    bool? syncDirty,
    String? id,
    String? householdId,
    String? name,
    Value<String?> quantityNote = const Value.absent(),
    Value<String?> categoryId = const Value.absent(),
    Value<String?> addedBy = const Value.absent(),
    Value<String?> checkedAt = const Value.absent(),
    String? createdAt,
    String? updatedAt,
    Value<String?> deletedAt = const Value.absent(),
  }) => ShoppingItem(
    syncDirty: syncDirty ?? this.syncDirty,
    id: id ?? this.id,
    householdId: householdId ?? this.householdId,
    name: name ?? this.name,
    quantityNote: quantityNote.present ? quantityNote.value : this.quantityNote,
    categoryId: categoryId.present ? categoryId.value : this.categoryId,
    addedBy: addedBy.present ? addedBy.value : this.addedBy,
    checkedAt: checkedAt.present ? checkedAt.value : this.checkedAt,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  ShoppingItem copyWithCompanion(ShoppingItemsCompanion data) {
    return ShoppingItem(
      syncDirty: data.syncDirty.present ? data.syncDirty.value : this.syncDirty,
      id: data.id.present ? data.id.value : this.id,
      householdId: data.householdId.present
          ? data.householdId.value
          : this.householdId,
      name: data.name.present ? data.name.value : this.name,
      quantityNote: data.quantityNote.present
          ? data.quantityNote.value
          : this.quantityNote,
      categoryId: data.categoryId.present
          ? data.categoryId.value
          : this.categoryId,
      addedBy: data.addedBy.present ? data.addedBy.value : this.addedBy,
      checkedAt: data.checkedAt.present ? data.checkedAt.value : this.checkedAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ShoppingItem(')
          ..write('syncDirty: $syncDirty, ')
          ..write('id: $id, ')
          ..write('householdId: $householdId, ')
          ..write('name: $name, ')
          ..write('quantityNote: $quantityNote, ')
          ..write('categoryId: $categoryId, ')
          ..write('addedBy: $addedBy, ')
          ..write('checkedAt: $checkedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    syncDirty,
    id,
    householdId,
    name,
    quantityNote,
    categoryId,
    addedBy,
    checkedAt,
    createdAt,
    updatedAt,
    deletedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ShoppingItem &&
          other.syncDirty == this.syncDirty &&
          other.id == this.id &&
          other.householdId == this.householdId &&
          other.name == this.name &&
          other.quantityNote == this.quantityNote &&
          other.categoryId == this.categoryId &&
          other.addedBy == this.addedBy &&
          other.checkedAt == this.checkedAt &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt);
}

class ShoppingItemsCompanion extends UpdateCompanion<ShoppingItem> {
  final Value<bool> syncDirty;
  final Value<String> id;
  final Value<String> householdId;
  final Value<String> name;
  final Value<String?> quantityNote;
  final Value<String?> categoryId;
  final Value<String?> addedBy;
  final Value<String?> checkedAt;
  final Value<String> createdAt;
  final Value<String> updatedAt;
  final Value<String?> deletedAt;
  final Value<int> rowid;
  const ShoppingItemsCompanion({
    this.syncDirty = const Value.absent(),
    this.id = const Value.absent(),
    this.householdId = const Value.absent(),
    this.name = const Value.absent(),
    this.quantityNote = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.addedBy = const Value.absent(),
    this.checkedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ShoppingItemsCompanion.insert({
    this.syncDirty = const Value.absent(),
    required String id,
    required String householdId,
    required String name,
    this.quantityNote = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.addedBy = const Value.absent(),
    this.checkedAt = const Value.absent(),
    required String createdAt,
    required String updatedAt,
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       householdId = Value(householdId),
       name = Value(name),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<ShoppingItem> custom({
    Expression<bool>? syncDirty,
    Expression<String>? id,
    Expression<String>? householdId,
    Expression<String>? name,
    Expression<String>? quantityNote,
    Expression<String>? categoryId,
    Expression<String>? addedBy,
    Expression<String>? checkedAt,
    Expression<String>? createdAt,
    Expression<String>? updatedAt,
    Expression<String>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (syncDirty != null) 'sync_dirty': syncDirty,
      if (id != null) 'id': id,
      if (householdId != null) 'household_id': householdId,
      if (name != null) 'name': name,
      if (quantityNote != null) 'quantity_note': quantityNote,
      if (categoryId != null) 'category_id': categoryId,
      if (addedBy != null) 'added_by': addedBy,
      if (checkedAt != null) 'checked_at': checkedAt,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ShoppingItemsCompanion copyWith({
    Value<bool>? syncDirty,
    Value<String>? id,
    Value<String>? householdId,
    Value<String>? name,
    Value<String?>? quantityNote,
    Value<String?>? categoryId,
    Value<String?>? addedBy,
    Value<String?>? checkedAt,
    Value<String>? createdAt,
    Value<String>? updatedAt,
    Value<String?>? deletedAt,
    Value<int>? rowid,
  }) {
    return ShoppingItemsCompanion(
      syncDirty: syncDirty ?? this.syncDirty,
      id: id ?? this.id,
      householdId: householdId ?? this.householdId,
      name: name ?? this.name,
      quantityNote: quantityNote ?? this.quantityNote,
      categoryId: categoryId ?? this.categoryId,
      addedBy: addedBy ?? this.addedBy,
      checkedAt: checkedAt ?? this.checkedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (syncDirty.present) {
      map['sync_dirty'] = Variable<bool>(syncDirty.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (householdId.present) {
      map['household_id'] = Variable<String>(householdId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (quantityNote.present) {
      map['quantity_note'] = Variable<String>(quantityNote.value);
    }
    if (categoryId.present) {
      map['category_id'] = Variable<String>(categoryId.value);
    }
    if (addedBy.present) {
      map['added_by'] = Variable<String>(addedBy.value);
    }
    if (checkedAt.present) {
      map['checked_at'] = Variable<String>(checkedAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<String>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ShoppingItemsCompanion(')
          ..write('syncDirty: $syncDirty, ')
          ..write('id: $id, ')
          ..write('householdId: $householdId, ')
          ..write('name: $name, ')
          ..write('quantityNote: $quantityNote, ')
          ..write('categoryId: $categoryId, ')
          ..write('addedBy: $addedBy, ')
          ..write('checkedAt: $checkedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SettingsTable extends Settings
    with TableInfo<$SettingsTable, DeviceSettings> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _digestEnabledMeta = const VerificationMeta(
    'digestEnabled',
  );
  @override
  late final GeneratedColumn<bool> digestEnabled = GeneratedColumn<bool>(
    'digest_enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("digest_enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _digestMinutesMeta = const VerificationMeta(
    'digestMinutes',
  );
  @override
  late final GeneratedColumn<int> digestMinutes = GeneratedColumn<int>(
    'digest_minutes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(480),
  );
  static const VerificationMeta _actingMemberIdMeta = const VerificationMeta(
    'actingMemberId',
  );
  @override
  late final GeneratedColumn<String> actingMemberId = GeneratedColumn<String>(
    'acting_member_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _localeMeta = const VerificationMeta('locale');
  @override
  late final GeneratedColumn<String> locale = GeneratedColumn<String>(
    'locale',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _onboardingNamePromptShownAtMeta =
      const VerificationMeta('onboardingNamePromptShownAt');
  @override
  late final GeneratedColumn<String> onboardingNamePromptShownAt =
      GeneratedColumn<String>(
        'onboarding_name_prompt_shown_at',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _digestPrepromptShownAtMeta =
      const VerificationMeta('digestPrepromptShownAt');
  @override
  late final GeneratedColumn<String> digestPrepromptShownAt =
      GeneratedColumn<String>(
        'digest_preprompt_shown_at',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _syncHouseholdIdMeta = const VerificationMeta(
    'syncHouseholdId',
  );
  @override
  late final GeneratedColumn<String> syncHouseholdId = GeneratedColumn<String>(
    'sync_household_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _syncLinkedAtMeta = const VerificationMeta(
    'syncLinkedAt',
  );
  @override
  late final GeneratedColumn<String> syncLinkedAt = GeneratedColumn<String>(
    'sync_linked_at',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _themeModeMeta = const VerificationMeta(
    'themeMode',
  );
  @override
  late final GeneratedColumn<String> themeMode = GeneratedColumn<String>(
    'theme_mode',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _syncLastPulledAtMeta = const VerificationMeta(
    'syncLastPulledAt',
  );
  @override
  late final GeneratedColumn<String> syncLastPulledAt = GeneratedColumn<String>(
    'sync_last_pulled_at',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _membershipRevokedMeta = const VerificationMeta(
    'membershipRevoked',
  );
  @override
  late final GeneratedColumn<bool> membershipRevoked = GeneratedColumn<bool>(
    'membership_revoked',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("membership_revoked" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<String> updatedAt = GeneratedColumn<String>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    digestEnabled,
    digestMinutes,
    actingMemberId,
    locale,
    onboardingNamePromptShownAt,
    digestPrepromptShownAt,
    syncHouseholdId,
    syncLinkedAt,
    themeMode,
    syncLastPulledAt,
    membershipRevoked,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<DeviceSettings> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('digest_enabled')) {
      context.handle(
        _digestEnabledMeta,
        digestEnabled.isAcceptableOrUnknown(
          data['digest_enabled']!,
          _digestEnabledMeta,
        ),
      );
    }
    if (data.containsKey('digest_minutes')) {
      context.handle(
        _digestMinutesMeta,
        digestMinutes.isAcceptableOrUnknown(
          data['digest_minutes']!,
          _digestMinutesMeta,
        ),
      );
    }
    if (data.containsKey('acting_member_id')) {
      context.handle(
        _actingMemberIdMeta,
        actingMemberId.isAcceptableOrUnknown(
          data['acting_member_id']!,
          _actingMemberIdMeta,
        ),
      );
    }
    if (data.containsKey('locale')) {
      context.handle(
        _localeMeta,
        locale.isAcceptableOrUnknown(data['locale']!, _localeMeta),
      );
    }
    if (data.containsKey('onboarding_name_prompt_shown_at')) {
      context.handle(
        _onboardingNamePromptShownAtMeta,
        onboardingNamePromptShownAt.isAcceptableOrUnknown(
          data['onboarding_name_prompt_shown_at']!,
          _onboardingNamePromptShownAtMeta,
        ),
      );
    }
    if (data.containsKey('digest_preprompt_shown_at')) {
      context.handle(
        _digestPrepromptShownAtMeta,
        digestPrepromptShownAt.isAcceptableOrUnknown(
          data['digest_preprompt_shown_at']!,
          _digestPrepromptShownAtMeta,
        ),
      );
    }
    if (data.containsKey('sync_household_id')) {
      context.handle(
        _syncHouseholdIdMeta,
        syncHouseholdId.isAcceptableOrUnknown(
          data['sync_household_id']!,
          _syncHouseholdIdMeta,
        ),
      );
    }
    if (data.containsKey('sync_linked_at')) {
      context.handle(
        _syncLinkedAtMeta,
        syncLinkedAt.isAcceptableOrUnknown(
          data['sync_linked_at']!,
          _syncLinkedAtMeta,
        ),
      );
    }
    if (data.containsKey('theme_mode')) {
      context.handle(
        _themeModeMeta,
        themeMode.isAcceptableOrUnknown(data['theme_mode']!, _themeModeMeta),
      );
    }
    if (data.containsKey('sync_last_pulled_at')) {
      context.handle(
        _syncLastPulledAtMeta,
        syncLastPulledAt.isAcceptableOrUnknown(
          data['sync_last_pulled_at']!,
          _syncLastPulledAtMeta,
        ),
      );
    }
    if (data.containsKey('membership_revoked')) {
      context.handle(
        _membershipRevokedMeta,
        membershipRevoked.isAcceptableOrUnknown(
          data['membership_revoked']!,
          _membershipRevokedMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DeviceSettings map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DeviceSettings(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      digestEnabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}digest_enabled'],
      )!,
      digestMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}digest_minutes'],
      )!,
      actingMemberId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}acting_member_id'],
      ),
      locale: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}locale'],
      ),
      onboardingNamePromptShownAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}onboarding_name_prompt_shown_at'],
      ),
      digestPrepromptShownAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}digest_preprompt_shown_at'],
      ),
      syncHouseholdId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_household_id'],
      ),
      syncLinkedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_linked_at'],
      ),
      themeMode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}theme_mode'],
      ),
      syncLastPulledAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_last_pulled_at'],
      ),
      membershipRevoked: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}membership_revoked'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $SettingsTable createAlias(String alias) {
    return $SettingsTable(attachedDatabase, alias);
  }
}

class DeviceSettings extends DataClass implements Insertable<DeviceSettings> {
  /// Constant primary key `'device'`; exactly one row ever exists.
  final String id;

  /// Whether the daily digest notification is enabled.
  final bool digestEnabled;

  /// The digest's fire time, as minutes since local midnight (default `480`
  /// = 08:00).
  final int digestMinutes;

  /// The household member currently "acting" for single-user attribution
  /// flows (chore completion `completedBy`, `createdBy`, shopping
  /// `addedBy`), or `NULL` for the automatic fallback (first admin, else
  /// first member) — see `actingMemberProvider` in `lib/app/providers.dart`.
  ///
  /// Deliberately no FK constraint: this is a single device-scoped row, not
  /// a per-household one, and a dangling id (referencing a member that no
  /// longer resolves) must degrade gracefully to the automatic fallback
  /// rather than fail a constraint. Added in schemaVersion 3; see
  /// `AppDatabase.migration`.
  final String? actingMemberId;

  /// The user's language override: `'en'` or `'de'`, or `NULL` to follow
  /// the OS locale — see `localeOverrideProvider` in
  /// `lib/app/providers.dart`. An unrecognized stored value (future
  /// installs storing a locale this build doesn't know) is treated the
  /// same as `NULL` by that provider, rather than enforced at the schema
  /// level. Added in schemaVersion 4; see `AppDatabase.migration`.
  final String? locale;

  /// ISO-8601 UTC moment the first-run "What's your name?" prompt was
  /// shown (spec `docs/specs/polish-round-1.md`, G2) — `NULL` means it has
  /// never been shown and should appear once. Set when the prompt is
  /// dismissed OR completed; it never shows twice either way. Added in
  /// schemaVersion 5; see `AppDatabase.migration`.
  final String? onboardingNamePromptShownAt;

  /// ISO-8601 UTC moment the digest pre-permission explainer was shown
  /// (spec `docs/specs/polish-round-1.md`, G3) — `NULL` means never. The
  /// explainer precedes the one-shot OS notification dialog, so it also
  /// only ever appears once. Added in schemaVersion 5; see
  /// `AppDatabase.migration`.
  final String? digestPrepromptShownAt;

  /// The server household this DEVICE is linked to (spec
  /// `docs/specs/sync-backend.md` §7.1), or `NULL` while unlinked --
  /// "linked" ⇔ `syncHouseholdId != null`. Always set/cleared together with
  /// [syncLinkedAt] -- see `SettingsRepository.setSyncLinked`. Added in
  /// schemaVersion 6; see `AppDatabase.migration`.
  final String? syncHouseholdId;

  /// ISO-8601 UTC moment linking completed (spec
  /// `docs/specs/sync-backend.md` §7.1) -- `NULL` while unlinked. Always
  /// set/cleared together with [syncHouseholdId]. Added in schemaVersion 6;
  /// see `AppDatabase.migration`.
  final String? syncLinkedAt;

  /// The user's manual theme override: `'light'` or `'dark'`, or `NULL` to
  /// follow the OS theme -- see `themeModeProvider` in
  /// `lib/app/providers.dart`. An unrecognized stored value (future installs
  /// storing a value this build doesn't know) is treated the same as `NULL`
  /// by that provider, rather than enforced at the schema level -- mirrors
  /// [locale]. Added in schemaVersion 7; see `AppDatabase.migration`.
  final String? themeMode;

  /// The pull cursor (spec `docs/specs/sync-backend.md` §8.1/8.3): the
  /// server-clock ISO timestamp fetched via the `server_now()` RPC in the
  /// same round trip as the last successful pull, or `NULL` before this
  /// device's first pull. NEVER the device clock -- see
  /// `SupabaseSyncEngine.pullSince`. Added in schemaVersion 8; see
  /// `AppDatabase.migration`.
  final String? syncLastPulledAt;

  /// Set when a pull discovered this device's membership was revoked
  /// server-side (spec `docs/specs/household-lifecycle.md` §3.5). Cleared
  /// when the user acknowledges the notice. Added in schemaVersion 10; see
  /// `AppDatabase.migration`.
  final bool membershipRevoked;

  /// ISO-8601 UTC creation timestamp.
  final String createdAt;

  /// ISO-8601 UTC timestamp of the last update.
  final String updatedAt;
  const DeviceSettings({
    required this.id,
    required this.digestEnabled,
    required this.digestMinutes,
    this.actingMemberId,
    this.locale,
    this.onboardingNamePromptShownAt,
    this.digestPrepromptShownAt,
    this.syncHouseholdId,
    this.syncLinkedAt,
    this.themeMode,
    this.syncLastPulledAt,
    required this.membershipRevoked,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['digest_enabled'] = Variable<bool>(digestEnabled);
    map['digest_minutes'] = Variable<int>(digestMinutes);
    if (!nullToAbsent || actingMemberId != null) {
      map['acting_member_id'] = Variable<String>(actingMemberId);
    }
    if (!nullToAbsent || locale != null) {
      map['locale'] = Variable<String>(locale);
    }
    if (!nullToAbsent || onboardingNamePromptShownAt != null) {
      map['onboarding_name_prompt_shown_at'] = Variable<String>(
        onboardingNamePromptShownAt,
      );
    }
    if (!nullToAbsent || digestPrepromptShownAt != null) {
      map['digest_preprompt_shown_at'] = Variable<String>(
        digestPrepromptShownAt,
      );
    }
    if (!nullToAbsent || syncHouseholdId != null) {
      map['sync_household_id'] = Variable<String>(syncHouseholdId);
    }
    if (!nullToAbsent || syncLinkedAt != null) {
      map['sync_linked_at'] = Variable<String>(syncLinkedAt);
    }
    if (!nullToAbsent || themeMode != null) {
      map['theme_mode'] = Variable<String>(themeMode);
    }
    if (!nullToAbsent || syncLastPulledAt != null) {
      map['sync_last_pulled_at'] = Variable<String>(syncLastPulledAt);
    }
    map['membership_revoked'] = Variable<bool>(membershipRevoked);
    map['created_at'] = Variable<String>(createdAt);
    map['updated_at'] = Variable<String>(updatedAt);
    return map;
  }

  SettingsCompanion toCompanion(bool nullToAbsent) {
    return SettingsCompanion(
      id: Value(id),
      digestEnabled: Value(digestEnabled),
      digestMinutes: Value(digestMinutes),
      actingMemberId: actingMemberId == null && nullToAbsent
          ? const Value.absent()
          : Value(actingMemberId),
      locale: locale == null && nullToAbsent
          ? const Value.absent()
          : Value(locale),
      onboardingNamePromptShownAt:
          onboardingNamePromptShownAt == null && nullToAbsent
          ? const Value.absent()
          : Value(onboardingNamePromptShownAt),
      digestPrepromptShownAt: digestPrepromptShownAt == null && nullToAbsent
          ? const Value.absent()
          : Value(digestPrepromptShownAt),
      syncHouseholdId: syncHouseholdId == null && nullToAbsent
          ? const Value.absent()
          : Value(syncHouseholdId),
      syncLinkedAt: syncLinkedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(syncLinkedAt),
      themeMode: themeMode == null && nullToAbsent
          ? const Value.absent()
          : Value(themeMode),
      syncLastPulledAt: syncLastPulledAt == null && nullToAbsent
          ? const Value.absent()
          : Value(syncLastPulledAt),
      membershipRevoked: Value(membershipRevoked),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory DeviceSettings.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DeviceSettings(
      id: serializer.fromJson<String>(json['id']),
      digestEnabled: serializer.fromJson<bool>(json['digestEnabled']),
      digestMinutes: serializer.fromJson<int>(json['digestMinutes']),
      actingMemberId: serializer.fromJson<String?>(json['actingMemberId']),
      locale: serializer.fromJson<String?>(json['locale']),
      onboardingNamePromptShownAt: serializer.fromJson<String?>(
        json['onboardingNamePromptShownAt'],
      ),
      digestPrepromptShownAt: serializer.fromJson<String?>(
        json['digestPrepromptShownAt'],
      ),
      syncHouseholdId: serializer.fromJson<String?>(json['syncHouseholdId']),
      syncLinkedAt: serializer.fromJson<String?>(json['syncLinkedAt']),
      themeMode: serializer.fromJson<String?>(json['themeMode']),
      syncLastPulledAt: serializer.fromJson<String?>(json['syncLastPulledAt']),
      membershipRevoked: serializer.fromJson<bool>(json['membershipRevoked']),
      createdAt: serializer.fromJson<String>(json['createdAt']),
      updatedAt: serializer.fromJson<String>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'digestEnabled': serializer.toJson<bool>(digestEnabled),
      'digestMinutes': serializer.toJson<int>(digestMinutes),
      'actingMemberId': serializer.toJson<String?>(actingMemberId),
      'locale': serializer.toJson<String?>(locale),
      'onboardingNamePromptShownAt': serializer.toJson<String?>(
        onboardingNamePromptShownAt,
      ),
      'digestPrepromptShownAt': serializer.toJson<String?>(
        digestPrepromptShownAt,
      ),
      'syncHouseholdId': serializer.toJson<String?>(syncHouseholdId),
      'syncLinkedAt': serializer.toJson<String?>(syncLinkedAt),
      'themeMode': serializer.toJson<String?>(themeMode),
      'syncLastPulledAt': serializer.toJson<String?>(syncLastPulledAt),
      'membershipRevoked': serializer.toJson<bool>(membershipRevoked),
      'createdAt': serializer.toJson<String>(createdAt),
      'updatedAt': serializer.toJson<String>(updatedAt),
    };
  }

  DeviceSettings copyWith({
    String? id,
    bool? digestEnabled,
    int? digestMinutes,
    Value<String?> actingMemberId = const Value.absent(),
    Value<String?> locale = const Value.absent(),
    Value<String?> onboardingNamePromptShownAt = const Value.absent(),
    Value<String?> digestPrepromptShownAt = const Value.absent(),
    Value<String?> syncHouseholdId = const Value.absent(),
    Value<String?> syncLinkedAt = const Value.absent(),
    Value<String?> themeMode = const Value.absent(),
    Value<String?> syncLastPulledAt = const Value.absent(),
    bool? membershipRevoked,
    String? createdAt,
    String? updatedAt,
  }) => DeviceSettings(
    id: id ?? this.id,
    digestEnabled: digestEnabled ?? this.digestEnabled,
    digestMinutes: digestMinutes ?? this.digestMinutes,
    actingMemberId: actingMemberId.present
        ? actingMemberId.value
        : this.actingMemberId,
    locale: locale.present ? locale.value : this.locale,
    onboardingNamePromptShownAt: onboardingNamePromptShownAt.present
        ? onboardingNamePromptShownAt.value
        : this.onboardingNamePromptShownAt,
    digestPrepromptShownAt: digestPrepromptShownAt.present
        ? digestPrepromptShownAt.value
        : this.digestPrepromptShownAt,
    syncHouseholdId: syncHouseholdId.present
        ? syncHouseholdId.value
        : this.syncHouseholdId,
    syncLinkedAt: syncLinkedAt.present ? syncLinkedAt.value : this.syncLinkedAt,
    themeMode: themeMode.present ? themeMode.value : this.themeMode,
    syncLastPulledAt: syncLastPulledAt.present
        ? syncLastPulledAt.value
        : this.syncLastPulledAt,
    membershipRevoked: membershipRevoked ?? this.membershipRevoked,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  DeviceSettings copyWithCompanion(SettingsCompanion data) {
    return DeviceSettings(
      id: data.id.present ? data.id.value : this.id,
      digestEnabled: data.digestEnabled.present
          ? data.digestEnabled.value
          : this.digestEnabled,
      digestMinutes: data.digestMinutes.present
          ? data.digestMinutes.value
          : this.digestMinutes,
      actingMemberId: data.actingMemberId.present
          ? data.actingMemberId.value
          : this.actingMemberId,
      locale: data.locale.present ? data.locale.value : this.locale,
      onboardingNamePromptShownAt: data.onboardingNamePromptShownAt.present
          ? data.onboardingNamePromptShownAt.value
          : this.onboardingNamePromptShownAt,
      digestPrepromptShownAt: data.digestPrepromptShownAt.present
          ? data.digestPrepromptShownAt.value
          : this.digestPrepromptShownAt,
      syncHouseholdId: data.syncHouseholdId.present
          ? data.syncHouseholdId.value
          : this.syncHouseholdId,
      syncLinkedAt: data.syncLinkedAt.present
          ? data.syncLinkedAt.value
          : this.syncLinkedAt,
      themeMode: data.themeMode.present ? data.themeMode.value : this.themeMode,
      syncLastPulledAt: data.syncLastPulledAt.present
          ? data.syncLastPulledAt.value
          : this.syncLastPulledAt,
      membershipRevoked: data.membershipRevoked.present
          ? data.membershipRevoked.value
          : this.membershipRevoked,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DeviceSettings(')
          ..write('id: $id, ')
          ..write('digestEnabled: $digestEnabled, ')
          ..write('digestMinutes: $digestMinutes, ')
          ..write('actingMemberId: $actingMemberId, ')
          ..write('locale: $locale, ')
          ..write('onboardingNamePromptShownAt: $onboardingNamePromptShownAt, ')
          ..write('digestPrepromptShownAt: $digestPrepromptShownAt, ')
          ..write('syncHouseholdId: $syncHouseholdId, ')
          ..write('syncLinkedAt: $syncLinkedAt, ')
          ..write('themeMode: $themeMode, ')
          ..write('syncLastPulledAt: $syncLastPulledAt, ')
          ..write('membershipRevoked: $membershipRevoked, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    digestEnabled,
    digestMinutes,
    actingMemberId,
    locale,
    onboardingNamePromptShownAt,
    digestPrepromptShownAt,
    syncHouseholdId,
    syncLinkedAt,
    themeMode,
    syncLastPulledAt,
    membershipRevoked,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DeviceSettings &&
          other.id == this.id &&
          other.digestEnabled == this.digestEnabled &&
          other.digestMinutes == this.digestMinutes &&
          other.actingMemberId == this.actingMemberId &&
          other.locale == this.locale &&
          other.onboardingNamePromptShownAt ==
              this.onboardingNamePromptShownAt &&
          other.digestPrepromptShownAt == this.digestPrepromptShownAt &&
          other.syncHouseholdId == this.syncHouseholdId &&
          other.syncLinkedAt == this.syncLinkedAt &&
          other.themeMode == this.themeMode &&
          other.syncLastPulledAt == this.syncLastPulledAt &&
          other.membershipRevoked == this.membershipRevoked &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class SettingsCompanion extends UpdateCompanion<DeviceSettings> {
  final Value<String> id;
  final Value<bool> digestEnabled;
  final Value<int> digestMinutes;
  final Value<String?> actingMemberId;
  final Value<String?> locale;
  final Value<String?> onboardingNamePromptShownAt;
  final Value<String?> digestPrepromptShownAt;
  final Value<String?> syncHouseholdId;
  final Value<String?> syncLinkedAt;
  final Value<String?> themeMode;
  final Value<String?> syncLastPulledAt;
  final Value<bool> membershipRevoked;
  final Value<String> createdAt;
  final Value<String> updatedAt;
  final Value<int> rowid;
  const SettingsCompanion({
    this.id = const Value.absent(),
    this.digestEnabled = const Value.absent(),
    this.digestMinutes = const Value.absent(),
    this.actingMemberId = const Value.absent(),
    this.locale = const Value.absent(),
    this.onboardingNamePromptShownAt = const Value.absent(),
    this.digestPrepromptShownAt = const Value.absent(),
    this.syncHouseholdId = const Value.absent(),
    this.syncLinkedAt = const Value.absent(),
    this.themeMode = const Value.absent(),
    this.syncLastPulledAt = const Value.absent(),
    this.membershipRevoked = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SettingsCompanion.insert({
    required String id,
    this.digestEnabled = const Value.absent(),
    this.digestMinutes = const Value.absent(),
    this.actingMemberId = const Value.absent(),
    this.locale = const Value.absent(),
    this.onboardingNamePromptShownAt = const Value.absent(),
    this.digestPrepromptShownAt = const Value.absent(),
    this.syncHouseholdId = const Value.absent(),
    this.syncLinkedAt = const Value.absent(),
    this.themeMode = const Value.absent(),
    this.syncLastPulledAt = const Value.absent(),
    this.membershipRevoked = const Value.absent(),
    required String createdAt,
    required String updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<DeviceSettings> custom({
    Expression<String>? id,
    Expression<bool>? digestEnabled,
    Expression<int>? digestMinutes,
    Expression<String>? actingMemberId,
    Expression<String>? locale,
    Expression<String>? onboardingNamePromptShownAt,
    Expression<String>? digestPrepromptShownAt,
    Expression<String>? syncHouseholdId,
    Expression<String>? syncLinkedAt,
    Expression<String>? themeMode,
    Expression<String>? syncLastPulledAt,
    Expression<bool>? membershipRevoked,
    Expression<String>? createdAt,
    Expression<String>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (digestEnabled != null) 'digest_enabled': digestEnabled,
      if (digestMinutes != null) 'digest_minutes': digestMinutes,
      if (actingMemberId != null) 'acting_member_id': actingMemberId,
      if (locale != null) 'locale': locale,
      if (onboardingNamePromptShownAt != null)
        'onboarding_name_prompt_shown_at': onboardingNamePromptShownAt,
      if (digestPrepromptShownAt != null)
        'digest_preprompt_shown_at': digestPrepromptShownAt,
      if (syncHouseholdId != null) 'sync_household_id': syncHouseholdId,
      if (syncLinkedAt != null) 'sync_linked_at': syncLinkedAt,
      if (themeMode != null) 'theme_mode': themeMode,
      if (syncLastPulledAt != null) 'sync_last_pulled_at': syncLastPulledAt,
      if (membershipRevoked != null) 'membership_revoked': membershipRevoked,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SettingsCompanion copyWith({
    Value<String>? id,
    Value<bool>? digestEnabled,
    Value<int>? digestMinutes,
    Value<String?>? actingMemberId,
    Value<String?>? locale,
    Value<String?>? onboardingNamePromptShownAt,
    Value<String?>? digestPrepromptShownAt,
    Value<String?>? syncHouseholdId,
    Value<String?>? syncLinkedAt,
    Value<String?>? themeMode,
    Value<String?>? syncLastPulledAt,
    Value<bool>? membershipRevoked,
    Value<String>? createdAt,
    Value<String>? updatedAt,
    Value<int>? rowid,
  }) {
    return SettingsCompanion(
      id: id ?? this.id,
      digestEnabled: digestEnabled ?? this.digestEnabled,
      digestMinutes: digestMinutes ?? this.digestMinutes,
      actingMemberId: actingMemberId ?? this.actingMemberId,
      locale: locale ?? this.locale,
      onboardingNamePromptShownAt:
          onboardingNamePromptShownAt ?? this.onboardingNamePromptShownAt,
      digestPrepromptShownAt:
          digestPrepromptShownAt ?? this.digestPrepromptShownAt,
      syncHouseholdId: syncHouseholdId ?? this.syncHouseholdId,
      syncLinkedAt: syncLinkedAt ?? this.syncLinkedAt,
      themeMode: themeMode ?? this.themeMode,
      syncLastPulledAt: syncLastPulledAt ?? this.syncLastPulledAt,
      membershipRevoked: membershipRevoked ?? this.membershipRevoked,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (digestEnabled.present) {
      map['digest_enabled'] = Variable<bool>(digestEnabled.value);
    }
    if (digestMinutes.present) {
      map['digest_minutes'] = Variable<int>(digestMinutes.value);
    }
    if (actingMemberId.present) {
      map['acting_member_id'] = Variable<String>(actingMemberId.value);
    }
    if (locale.present) {
      map['locale'] = Variable<String>(locale.value);
    }
    if (onboardingNamePromptShownAt.present) {
      map['onboarding_name_prompt_shown_at'] = Variable<String>(
        onboardingNamePromptShownAt.value,
      );
    }
    if (digestPrepromptShownAt.present) {
      map['digest_preprompt_shown_at'] = Variable<String>(
        digestPrepromptShownAt.value,
      );
    }
    if (syncHouseholdId.present) {
      map['sync_household_id'] = Variable<String>(syncHouseholdId.value);
    }
    if (syncLinkedAt.present) {
      map['sync_linked_at'] = Variable<String>(syncLinkedAt.value);
    }
    if (themeMode.present) {
      map['theme_mode'] = Variable<String>(themeMode.value);
    }
    if (syncLastPulledAt.present) {
      map['sync_last_pulled_at'] = Variable<String>(syncLastPulledAt.value);
    }
    if (membershipRevoked.present) {
      map['membership_revoked'] = Variable<bool>(membershipRevoked.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SettingsCompanion(')
          ..write('id: $id, ')
          ..write('digestEnabled: $digestEnabled, ')
          ..write('digestMinutes: $digestMinutes, ')
          ..write('actingMemberId: $actingMemberId, ')
          ..write('locale: $locale, ')
          ..write('onboardingNamePromptShownAt: $onboardingNamePromptShownAt, ')
          ..write('digestPrepromptShownAt: $digestPrepromptShownAt, ')
          ..write('syncHouseholdId: $syncHouseholdId, ')
          ..write('syncLinkedAt: $syncLinkedAt, ')
          ..write('themeMode: $themeMode, ')
          ..write('syncLastPulledAt: $syncLastPulledAt, ')
          ..write('membershipRevoked: $membershipRevoked, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $HouseholdsTable households = $HouseholdsTable(this);
  late final $MembersTable members = $MembersTable(this);
  late final $CategoriesTable categories = $CategoriesTable(this);
  late final $ChoresTable chores = $ChoresTable(this);
  late final $ChoreAssigneesTable choreAssignees = $ChoreAssigneesTable(this);
  late final $ChoreOccurrencesTable choreOccurrences = $ChoreOccurrencesTable(
    this,
  );
  late final $ShoppingItemsTable shoppingItems = $ShoppingItemsTable(this);
  late final $SettingsTable settings = $SettingsTable(this);
  late final Index choreOccurrencesChoreStatusIdx = Index(
    'chore_occurrences_chore_status_idx',
    'CREATE INDEX chore_occurrences_chore_status_idx ON chore_occurrences (chore_id, status)',
  );
  late final Index choreOccurrencesStatusDueDateIdx = Index(
    'chore_occurrences_status_due_date_idx',
    'CREATE INDEX chore_occurrences_status_due_date_idx ON chore_occurrences (status, due_date)',
  );
  late final Index choreOccurrencesStatusClosedOnIdx = Index(
    'chore_occurrences_status_closed_on_idx',
    'CREATE INDEX chore_occurrences_status_closed_on_idx ON chore_occurrences (status, closed_on)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    households,
    members,
    categories,
    chores,
    choreAssignees,
    choreOccurrences,
    shoppingItems,
    settings,
    choreOccurrencesChoreStatusIdx,
    choreOccurrencesStatusDueDateIdx,
    choreOccurrencesStatusClosedOnIdx,
  ];
}

typedef $$HouseholdsTableCreateCompanionBuilder =
    HouseholdsCompanion Function({
      Value<bool> syncDirty,
      required String id,
      required String name,
      required String createdAt,
      required String updatedAt,
      Value<int> rowid,
    });
typedef $$HouseholdsTableUpdateCompanionBuilder =
    HouseholdsCompanion Function({
      Value<bool> syncDirty,
      Value<String> id,
      Value<String> name,
      Value<String> createdAt,
      Value<String> updatedAt,
      Value<int> rowid,
    });

final class $$HouseholdsTableReferences
    extends BaseReferences<_$AppDatabase, $HouseholdsTable, Household> {
  $$HouseholdsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$MembersTable, List<Member>> _membersRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.members,
    aliasName: 'households__id__members__household_id',
  );

  $$MembersTableProcessedTableManager get membersRefs {
    final manager = $$MembersTableTableManager(
      $_db,
      $_db.members,
    ).filter((f) => f.householdId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_membersRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$CategoriesTable, List<Category>>
  _categoriesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.categories,
    aliasName: 'households__id__categories__household_id',
  );

  $$CategoriesTableProcessedTableManager get categoriesRefs {
    final manager = $$CategoriesTableTableManager(
      $_db,
      $_db.categories,
    ).filter((f) => f.householdId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_categoriesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ChoresTable, List<Chore>> _choresRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.chores,
    aliasName: 'households__id__chores__household_id',
  );

  $$ChoresTableProcessedTableManager get choresRefs {
    final manager = $$ChoresTableTableManager(
      $_db,
      $_db.chores,
    ).filter((f) => f.householdId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_choresRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ShoppingItemsTable, List<ShoppingItem>>
  _shoppingItemsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.shoppingItems,
    aliasName: 'households__id__shopping_items__household_id',
  );

  $$ShoppingItemsTableProcessedTableManager get shoppingItemsRefs {
    final manager = $$ShoppingItemsTableTableManager(
      $_db,
      $_db.shoppingItems,
    ).filter((f) => f.householdId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_shoppingItemsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$HouseholdsTableFilterComposer
    extends Composer<_$AppDatabase, $HouseholdsTable> {
  $$HouseholdsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<bool> get syncDirty => $composableBuilder(
    column: $table.syncDirty,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> membersRefs(
    Expression<bool> Function($$MembersTableFilterComposer f) f,
  ) {
    final $$MembersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.members,
      getReferencedColumn: (t) => t.householdId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MembersTableFilterComposer(
            $db: $db,
            $table: $db.members,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> categoriesRefs(
    Expression<bool> Function($$CategoriesTableFilterComposer f) f,
  ) {
    final $$CategoriesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.categories,
      getReferencedColumn: (t) => t.householdId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CategoriesTableFilterComposer(
            $db: $db,
            $table: $db.categories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> choresRefs(
    Expression<bool> Function($$ChoresTableFilterComposer f) f,
  ) {
    final $$ChoresTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.chores,
      getReferencedColumn: (t) => t.householdId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ChoresTableFilterComposer(
            $db: $db,
            $table: $db.chores,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> shoppingItemsRefs(
    Expression<bool> Function($$ShoppingItemsTableFilterComposer f) f,
  ) {
    final $$ShoppingItemsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.shoppingItems,
      getReferencedColumn: (t) => t.householdId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShoppingItemsTableFilterComposer(
            $db: $db,
            $table: $db.shoppingItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$HouseholdsTableOrderingComposer
    extends Composer<_$AppDatabase, $HouseholdsTable> {
  $$HouseholdsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<bool> get syncDirty => $composableBuilder(
    column: $table.syncDirty,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$HouseholdsTableAnnotationComposer
    extends Composer<_$AppDatabase, $HouseholdsTable> {
  $$HouseholdsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<bool> get syncDirty =>
      $composableBuilder(column: $table.syncDirty, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  Expression<T> membersRefs<T extends Object>(
    Expression<T> Function($$MembersTableAnnotationComposer a) f,
  ) {
    final $$MembersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.members,
      getReferencedColumn: (t) => t.householdId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MembersTableAnnotationComposer(
            $db: $db,
            $table: $db.members,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> categoriesRefs<T extends Object>(
    Expression<T> Function($$CategoriesTableAnnotationComposer a) f,
  ) {
    final $$CategoriesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.categories,
      getReferencedColumn: (t) => t.householdId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CategoriesTableAnnotationComposer(
            $db: $db,
            $table: $db.categories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> choresRefs<T extends Object>(
    Expression<T> Function($$ChoresTableAnnotationComposer a) f,
  ) {
    final $$ChoresTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.chores,
      getReferencedColumn: (t) => t.householdId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ChoresTableAnnotationComposer(
            $db: $db,
            $table: $db.chores,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> shoppingItemsRefs<T extends Object>(
    Expression<T> Function($$ShoppingItemsTableAnnotationComposer a) f,
  ) {
    final $$ShoppingItemsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.shoppingItems,
      getReferencedColumn: (t) => t.householdId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShoppingItemsTableAnnotationComposer(
            $db: $db,
            $table: $db.shoppingItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$HouseholdsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $HouseholdsTable,
          Household,
          $$HouseholdsTableFilterComposer,
          $$HouseholdsTableOrderingComposer,
          $$HouseholdsTableAnnotationComposer,
          $$HouseholdsTableCreateCompanionBuilder,
          $$HouseholdsTableUpdateCompanionBuilder,
          (Household, $$HouseholdsTableReferences),
          Household,
          PrefetchHooks Function({
            bool membersRefs,
            bool categoriesRefs,
            bool choresRefs,
            bool shoppingItemsRefs,
          })
        > {
  $$HouseholdsTableTableManager(_$AppDatabase db, $HouseholdsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$HouseholdsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$HouseholdsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$HouseholdsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<bool> syncDirty = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
                Value<String> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => HouseholdsCompanion(
                syncDirty: syncDirty,
                id: id,
                name: name,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<bool> syncDirty = const Value.absent(),
                required String id,
                required String name,
                required String createdAt,
                required String updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => HouseholdsCompanion.insert(
                syncDirty: syncDirty,
                id: id,
                name: name,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$HouseholdsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                membersRefs = false,
                categoriesRefs = false,
                choresRefs = false,
                shoppingItemsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (membersRefs) db.members,
                    if (categoriesRefs) db.categories,
                    if (choresRefs) db.chores,
                    if (shoppingItemsRefs) db.shoppingItems,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (membersRefs)
                        await $_getPrefetchedData<
                          Household,
                          $HouseholdsTable,
                          Member
                        >(
                          currentTable: table,
                          referencedTable: $$HouseholdsTableReferences
                              ._membersRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$HouseholdsTableReferences(
                                db,
                                table,
                                p0,
                              ).membersRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.householdId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (categoriesRefs)
                        await $_getPrefetchedData<
                          Household,
                          $HouseholdsTable,
                          Category
                        >(
                          currentTable: table,
                          referencedTable: $$HouseholdsTableReferences
                              ._categoriesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$HouseholdsTableReferences(
                                db,
                                table,
                                p0,
                              ).categoriesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.householdId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (choresRefs)
                        await $_getPrefetchedData<
                          Household,
                          $HouseholdsTable,
                          Chore
                        >(
                          currentTable: table,
                          referencedTable: $$HouseholdsTableReferences
                              ._choresRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$HouseholdsTableReferences(
                                db,
                                table,
                                p0,
                              ).choresRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.householdId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (shoppingItemsRefs)
                        await $_getPrefetchedData<
                          Household,
                          $HouseholdsTable,
                          ShoppingItem
                        >(
                          currentTable: table,
                          referencedTable: $$HouseholdsTableReferences
                              ._shoppingItemsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$HouseholdsTableReferences(
                                db,
                                table,
                                p0,
                              ).shoppingItemsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.householdId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$HouseholdsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $HouseholdsTable,
      Household,
      $$HouseholdsTableFilterComposer,
      $$HouseholdsTableOrderingComposer,
      $$HouseholdsTableAnnotationComposer,
      $$HouseholdsTableCreateCompanionBuilder,
      $$HouseholdsTableUpdateCompanionBuilder,
      (Household, $$HouseholdsTableReferences),
      Household,
      PrefetchHooks Function({
        bool membersRefs,
        bool categoriesRefs,
        bool choresRefs,
        bool shoppingItemsRefs,
      })
    >;
typedef $$MembersTableCreateCompanionBuilder =
    MembersCompanion Function({
      Value<bool> syncDirty,
      required String id,
      required String householdId,
      required String name,
      required int color,
      required MemberRole role,
      Value<String?> userId,
      required String createdAt,
      required String updatedAt,
      Value<String?> deletedAt,
      Value<int> rowid,
    });
typedef $$MembersTableUpdateCompanionBuilder =
    MembersCompanion Function({
      Value<bool> syncDirty,
      Value<String> id,
      Value<String> householdId,
      Value<String> name,
      Value<int> color,
      Value<MemberRole> role,
      Value<String?> userId,
      Value<String> createdAt,
      Value<String> updatedAt,
      Value<String?> deletedAt,
      Value<int> rowid,
    });

final class $$MembersTableReferences
    extends BaseReferences<_$AppDatabase, $MembersTable, Member> {
  $$MembersTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $HouseholdsTable _householdIdTable(_$AppDatabase db) =>
      db.households.createAlias('members__household_id__households__id');

  $$HouseholdsTableProcessedTableManager get householdId {
    final $_column = $_itemColumn<String>('household_id')!;

    final manager = $$HouseholdsTableTableManager(
      $_db,
      $_db.households,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_householdIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$ChoresTable, List<Chore>> _choresRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.chores,
    aliasName: 'members__id__chores__created_by',
  );

  $$ChoresTableProcessedTableManager get choresRefs {
    final manager = $$ChoresTableTableManager(
      $_db,
      $_db.chores,
    ).filter((f) => f.createdBy.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_choresRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ChoreAssigneesTable, List<ChoreAssignee>>
  _choreAssigneesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.choreAssignees,
    aliasName: 'members__id__chore_assignees__member_id',
  );

  $$ChoreAssigneesTableProcessedTableManager get choreAssigneesRefs {
    final manager = $$ChoreAssigneesTableTableManager(
      $_db,
      $_db.choreAssignees,
    ).filter((f) => f.memberId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_choreAssigneesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ShoppingItemsTable, List<ShoppingItem>>
  _shoppingItemsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.shoppingItems,
    aliasName: 'members__id__shopping_items__added_by',
  );

  $$ShoppingItemsTableProcessedTableManager get shoppingItemsRefs {
    final manager = $$ShoppingItemsTableTableManager(
      $_db,
      $_db.shoppingItems,
    ).filter((f) => f.addedBy.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_shoppingItemsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$MembersTableFilterComposer
    extends Composer<_$AppDatabase, $MembersTable> {
  $$MembersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<bool> get syncDirty => $composableBuilder(
    column: $table.syncDirty,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<MemberRole, MemberRole, String> get role =>
      $composableBuilder(
        column: $table.role,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$HouseholdsTableFilterComposer get householdId {
    final $$HouseholdsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.householdId,
      referencedTable: $db.households,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$HouseholdsTableFilterComposer(
            $db: $db,
            $table: $db.households,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> choresRefs(
    Expression<bool> Function($$ChoresTableFilterComposer f) f,
  ) {
    final $$ChoresTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.chores,
      getReferencedColumn: (t) => t.createdBy,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ChoresTableFilterComposer(
            $db: $db,
            $table: $db.chores,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> choreAssigneesRefs(
    Expression<bool> Function($$ChoreAssigneesTableFilterComposer f) f,
  ) {
    final $$ChoreAssigneesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.choreAssignees,
      getReferencedColumn: (t) => t.memberId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ChoreAssigneesTableFilterComposer(
            $db: $db,
            $table: $db.choreAssignees,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> shoppingItemsRefs(
    Expression<bool> Function($$ShoppingItemsTableFilterComposer f) f,
  ) {
    final $$ShoppingItemsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.shoppingItems,
      getReferencedColumn: (t) => t.addedBy,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShoppingItemsTableFilterComposer(
            $db: $db,
            $table: $db.shoppingItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$MembersTableOrderingComposer
    extends Composer<_$AppDatabase, $MembersTable> {
  $$MembersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<bool> get syncDirty => $composableBuilder(
    column: $table.syncDirty,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$HouseholdsTableOrderingComposer get householdId {
    final $$HouseholdsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.householdId,
      referencedTable: $db.households,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$HouseholdsTableOrderingComposer(
            $db: $db,
            $table: $db.households,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MembersTableAnnotationComposer
    extends Composer<_$AppDatabase, $MembersTable> {
  $$MembersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<bool> get syncDirty =>
      $composableBuilder(column: $table.syncDirty, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get color =>
      $composableBuilder(column: $table.color, builder: (column) => column);

  GeneratedColumnWithTypeConverter<MemberRole, String> get role =>
      $composableBuilder(column: $table.role, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  $$HouseholdsTableAnnotationComposer get householdId {
    final $$HouseholdsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.householdId,
      referencedTable: $db.households,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$HouseholdsTableAnnotationComposer(
            $db: $db,
            $table: $db.households,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> choresRefs<T extends Object>(
    Expression<T> Function($$ChoresTableAnnotationComposer a) f,
  ) {
    final $$ChoresTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.chores,
      getReferencedColumn: (t) => t.createdBy,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ChoresTableAnnotationComposer(
            $db: $db,
            $table: $db.chores,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> choreAssigneesRefs<T extends Object>(
    Expression<T> Function($$ChoreAssigneesTableAnnotationComposer a) f,
  ) {
    final $$ChoreAssigneesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.choreAssignees,
      getReferencedColumn: (t) => t.memberId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ChoreAssigneesTableAnnotationComposer(
            $db: $db,
            $table: $db.choreAssignees,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> shoppingItemsRefs<T extends Object>(
    Expression<T> Function($$ShoppingItemsTableAnnotationComposer a) f,
  ) {
    final $$ShoppingItemsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.shoppingItems,
      getReferencedColumn: (t) => t.addedBy,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShoppingItemsTableAnnotationComposer(
            $db: $db,
            $table: $db.shoppingItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$MembersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MembersTable,
          Member,
          $$MembersTableFilterComposer,
          $$MembersTableOrderingComposer,
          $$MembersTableAnnotationComposer,
          $$MembersTableCreateCompanionBuilder,
          $$MembersTableUpdateCompanionBuilder,
          (Member, $$MembersTableReferences),
          Member,
          PrefetchHooks Function({
            bool householdId,
            bool choresRefs,
            bool choreAssigneesRefs,
            bool shoppingItemsRefs,
          })
        > {
  $$MembersTableTableManager(_$AppDatabase db, $MembersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MembersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MembersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MembersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<bool> syncDirty = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> householdId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> color = const Value.absent(),
                Value<MemberRole> role = const Value.absent(),
                Value<String?> userId = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
                Value<String> updatedAt = const Value.absent(),
                Value<String?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MembersCompanion(
                syncDirty: syncDirty,
                id: id,
                householdId: householdId,
                name: name,
                color: color,
                role: role,
                userId: userId,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<bool> syncDirty = const Value.absent(),
                required String id,
                required String householdId,
                required String name,
                required int color,
                required MemberRole role,
                Value<String?> userId = const Value.absent(),
                required String createdAt,
                required String updatedAt,
                Value<String?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MembersCompanion.insert(
                syncDirty: syncDirty,
                id: id,
                householdId: householdId,
                name: name,
                color: color,
                role: role,
                userId: userId,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$MembersTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                householdId = false,
                choresRefs = false,
                choreAssigneesRefs = false,
                shoppingItemsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (choresRefs) db.chores,
                    if (choreAssigneesRefs) db.choreAssignees,
                    if (shoppingItemsRefs) db.shoppingItems,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (householdId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.householdId,
                                    referencedTable: $$MembersTableReferences
                                        ._householdIdTable(db),
                                    referencedColumn: $$MembersTableReferences
                                        ._householdIdTable(db)
                                        .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (choresRefs)
                        await $_getPrefetchedData<Member, $MembersTable, Chore>(
                          currentTable: table,
                          referencedTable: $$MembersTableReferences
                              ._choresRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$MembersTableReferences(
                                db,
                                table,
                                p0,
                              ).choresRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.createdBy == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (choreAssigneesRefs)
                        await $_getPrefetchedData<
                          Member,
                          $MembersTable,
                          ChoreAssignee
                        >(
                          currentTable: table,
                          referencedTable: $$MembersTableReferences
                              ._choreAssigneesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$MembersTableReferences(
                                db,
                                table,
                                p0,
                              ).choreAssigneesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.memberId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (shoppingItemsRefs)
                        await $_getPrefetchedData<
                          Member,
                          $MembersTable,
                          ShoppingItem
                        >(
                          currentTable: table,
                          referencedTable: $$MembersTableReferences
                              ._shoppingItemsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$MembersTableReferences(
                                db,
                                table,
                                p0,
                              ).shoppingItemsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.addedBy == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$MembersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MembersTable,
      Member,
      $$MembersTableFilterComposer,
      $$MembersTableOrderingComposer,
      $$MembersTableAnnotationComposer,
      $$MembersTableCreateCompanionBuilder,
      $$MembersTableUpdateCompanionBuilder,
      (Member, $$MembersTableReferences),
      Member,
      PrefetchHooks Function({
        bool householdId,
        bool choresRefs,
        bool choreAssigneesRefs,
        bool shoppingItemsRefs,
      })
    >;
typedef $$CategoriesTableCreateCompanionBuilder =
    CategoriesCompanion Function({
      Value<bool> syncDirty,
      required String id,
      required String householdId,
      required CategoryKind kind,
      required String name,
      required String icon,
      required int color,
      Value<int> sortOrder,
      required String createdAt,
      required String updatedAt,
      Value<String?> deletedAt,
      Value<int> rowid,
    });
typedef $$CategoriesTableUpdateCompanionBuilder =
    CategoriesCompanion Function({
      Value<bool> syncDirty,
      Value<String> id,
      Value<String> householdId,
      Value<CategoryKind> kind,
      Value<String> name,
      Value<String> icon,
      Value<int> color,
      Value<int> sortOrder,
      Value<String> createdAt,
      Value<String> updatedAt,
      Value<String?> deletedAt,
      Value<int> rowid,
    });

final class $$CategoriesTableReferences
    extends BaseReferences<_$AppDatabase, $CategoriesTable, Category> {
  $$CategoriesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $HouseholdsTable _householdIdTable(_$AppDatabase db) =>
      db.households.createAlias('categories__household_id__households__id');

  $$HouseholdsTableProcessedTableManager get householdId {
    final $_column = $_itemColumn<String>('household_id')!;

    final manager = $$HouseholdsTableTableManager(
      $_db,
      $_db.households,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_householdIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$ChoresTable, List<Chore>> _choresRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.chores,
    aliasName: 'categories__id__chores__category_id',
  );

  $$ChoresTableProcessedTableManager get choresRefs {
    final manager = $$ChoresTableTableManager(
      $_db,
      $_db.chores,
    ).filter((f) => f.categoryId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_choresRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ShoppingItemsTable, List<ShoppingItem>>
  _shoppingItemsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.shoppingItems,
    aliasName: 'categories__id__shopping_items__category_id',
  );

  $$ShoppingItemsTableProcessedTableManager get shoppingItemsRefs {
    final manager = $$ShoppingItemsTableTableManager(
      $_db,
      $_db.shoppingItems,
    ).filter((f) => f.categoryId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_shoppingItemsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$CategoriesTableFilterComposer
    extends Composer<_$AppDatabase, $CategoriesTable> {
  $$CategoriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<bool> get syncDirty => $composableBuilder(
    column: $table.syncDirty,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<CategoryKind, CategoryKind, String> get kind =>
      $composableBuilder(
        column: $table.kind,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get icon => $composableBuilder(
    column: $table.icon,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$HouseholdsTableFilterComposer get householdId {
    final $$HouseholdsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.householdId,
      referencedTable: $db.households,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$HouseholdsTableFilterComposer(
            $db: $db,
            $table: $db.households,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> choresRefs(
    Expression<bool> Function($$ChoresTableFilterComposer f) f,
  ) {
    final $$ChoresTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.chores,
      getReferencedColumn: (t) => t.categoryId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ChoresTableFilterComposer(
            $db: $db,
            $table: $db.chores,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> shoppingItemsRefs(
    Expression<bool> Function($$ShoppingItemsTableFilterComposer f) f,
  ) {
    final $$ShoppingItemsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.shoppingItems,
      getReferencedColumn: (t) => t.categoryId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShoppingItemsTableFilterComposer(
            $db: $db,
            $table: $db.shoppingItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$CategoriesTableOrderingComposer
    extends Composer<_$AppDatabase, $CategoriesTable> {
  $$CategoriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<bool> get syncDirty => $composableBuilder(
    column: $table.syncDirty,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get icon => $composableBuilder(
    column: $table.icon,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$HouseholdsTableOrderingComposer get householdId {
    final $$HouseholdsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.householdId,
      referencedTable: $db.households,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$HouseholdsTableOrderingComposer(
            $db: $db,
            $table: $db.households,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CategoriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $CategoriesTable> {
  $$CategoriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<bool> get syncDirty =>
      $composableBuilder(column: $table.syncDirty, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumnWithTypeConverter<CategoryKind, String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get icon =>
      $composableBuilder(column: $table.icon, builder: (column) => column);

  GeneratedColumn<int> get color =>
      $composableBuilder(column: $table.color, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  $$HouseholdsTableAnnotationComposer get householdId {
    final $$HouseholdsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.householdId,
      referencedTable: $db.households,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$HouseholdsTableAnnotationComposer(
            $db: $db,
            $table: $db.households,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> choresRefs<T extends Object>(
    Expression<T> Function($$ChoresTableAnnotationComposer a) f,
  ) {
    final $$ChoresTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.chores,
      getReferencedColumn: (t) => t.categoryId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ChoresTableAnnotationComposer(
            $db: $db,
            $table: $db.chores,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> shoppingItemsRefs<T extends Object>(
    Expression<T> Function($$ShoppingItemsTableAnnotationComposer a) f,
  ) {
    final $$ShoppingItemsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.shoppingItems,
      getReferencedColumn: (t) => t.categoryId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShoppingItemsTableAnnotationComposer(
            $db: $db,
            $table: $db.shoppingItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$CategoriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CategoriesTable,
          Category,
          $$CategoriesTableFilterComposer,
          $$CategoriesTableOrderingComposer,
          $$CategoriesTableAnnotationComposer,
          $$CategoriesTableCreateCompanionBuilder,
          $$CategoriesTableUpdateCompanionBuilder,
          (Category, $$CategoriesTableReferences),
          Category,
          PrefetchHooks Function({
            bool householdId,
            bool choresRefs,
            bool shoppingItemsRefs,
          })
        > {
  $$CategoriesTableTableManager(_$AppDatabase db, $CategoriesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CategoriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CategoriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CategoriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<bool> syncDirty = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> householdId = const Value.absent(),
                Value<CategoryKind> kind = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> icon = const Value.absent(),
                Value<int> color = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
                Value<String> updatedAt = const Value.absent(),
                Value<String?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CategoriesCompanion(
                syncDirty: syncDirty,
                id: id,
                householdId: householdId,
                kind: kind,
                name: name,
                icon: icon,
                color: color,
                sortOrder: sortOrder,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<bool> syncDirty = const Value.absent(),
                required String id,
                required String householdId,
                required CategoryKind kind,
                required String name,
                required String icon,
                required int color,
                Value<int> sortOrder = const Value.absent(),
                required String createdAt,
                required String updatedAt,
                Value<String?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CategoriesCompanion.insert(
                syncDirty: syncDirty,
                id: id,
                householdId: householdId,
                kind: kind,
                name: name,
                icon: icon,
                color: color,
                sortOrder: sortOrder,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$CategoriesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                householdId = false,
                choresRefs = false,
                shoppingItemsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (choresRefs) db.chores,
                    if (shoppingItemsRefs) db.shoppingItems,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (householdId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.householdId,
                                    referencedTable: $$CategoriesTableReferences
                                        ._householdIdTable(db),
                                    referencedColumn:
                                        $$CategoriesTableReferences
                                            ._householdIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (choresRefs)
                        await $_getPrefetchedData<
                          Category,
                          $CategoriesTable,
                          Chore
                        >(
                          currentTable: table,
                          referencedTable: $$CategoriesTableReferences
                              ._choresRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$CategoriesTableReferences(
                                db,
                                table,
                                p0,
                              ).choresRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.categoryId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (shoppingItemsRefs)
                        await $_getPrefetchedData<
                          Category,
                          $CategoriesTable,
                          ShoppingItem
                        >(
                          currentTable: table,
                          referencedTable: $$CategoriesTableReferences
                              ._shoppingItemsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$CategoriesTableReferences(
                                db,
                                table,
                                p0,
                              ).shoppingItemsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.categoryId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$CategoriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CategoriesTable,
      Category,
      $$CategoriesTableFilterComposer,
      $$CategoriesTableOrderingComposer,
      $$CategoriesTableAnnotationComposer,
      $$CategoriesTableCreateCompanionBuilder,
      $$CategoriesTableUpdateCompanionBuilder,
      (Category, $$CategoriesTableReferences),
      Category,
      PrefetchHooks Function({
        bool householdId,
        bool choresRefs,
        bool shoppingItemsRefs,
      })
    >;
typedef $$ChoresTableCreateCompanionBuilder =
    ChoresCompanion Function({
      Value<bool> syncDirty,
      required String id,
      required String householdId,
      required String title,
      Value<String?> notes,
      Value<String?> categoryId,
      Value<Recurrence?> recurrence,
      required PlainDate startDate,
      required AssignmentMode assignmentMode,
      Value<String?> pausedAt,
      Value<String?> createdBy,
      required String createdAt,
      required String updatedAt,
      Value<String?> deletedAt,
      Value<int> rowid,
    });
typedef $$ChoresTableUpdateCompanionBuilder =
    ChoresCompanion Function({
      Value<bool> syncDirty,
      Value<String> id,
      Value<String> householdId,
      Value<String> title,
      Value<String?> notes,
      Value<String?> categoryId,
      Value<Recurrence?> recurrence,
      Value<PlainDate> startDate,
      Value<AssignmentMode> assignmentMode,
      Value<String?> pausedAt,
      Value<String?> createdBy,
      Value<String> createdAt,
      Value<String> updatedAt,
      Value<String?> deletedAt,
      Value<int> rowid,
    });

final class $$ChoresTableReferences
    extends BaseReferences<_$AppDatabase, $ChoresTable, Chore> {
  $$ChoresTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $HouseholdsTable _householdIdTable(_$AppDatabase db) =>
      db.households.createAlias('chores__household_id__households__id');

  $$HouseholdsTableProcessedTableManager get householdId {
    final $_column = $_itemColumn<String>('household_id')!;

    final manager = $$HouseholdsTableTableManager(
      $_db,
      $_db.households,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_householdIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $CategoriesTable _categoryIdTable(_$AppDatabase db) =>
      db.categories.createAlias('chores__category_id__categories__id');

  $$CategoriesTableProcessedTableManager? get categoryId {
    final $_column = $_itemColumn<String>('category_id');
    if ($_column == null) return null;
    final manager = $$CategoriesTableTableManager(
      $_db,
      $_db.categories,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_categoryIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $MembersTable _createdByTable(_$AppDatabase db) =>
      db.members.createAlias('chores__created_by__members__id');

  $$MembersTableProcessedTableManager? get createdBy {
    final $_column = $_itemColumn<String>('created_by');
    if ($_column == null) return null;
    final manager = $$MembersTableTableManager(
      $_db,
      $_db.members,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_createdByTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$ChoreAssigneesTable, List<ChoreAssignee>>
  _choreAssigneesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.choreAssignees,
    aliasName: 'chores__id__chore_assignees__chore_id',
  );

  $$ChoreAssigneesTableProcessedTableManager get choreAssigneesRefs {
    final manager = $$ChoreAssigneesTableTableManager(
      $_db,
      $_db.choreAssignees,
    ).filter((f) => f.choreId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_choreAssigneesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ChoreOccurrencesTable, List<ChoreOccurrence>>
  _choreOccurrencesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.choreOccurrences,
    aliasName: 'chores__id__chore_occurrences__chore_id',
  );

  $$ChoreOccurrencesTableProcessedTableManager get choreOccurrencesRefs {
    final manager = $$ChoreOccurrencesTableTableManager(
      $_db,
      $_db.choreOccurrences,
    ).filter((f) => f.choreId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _choreOccurrencesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ChoresTableFilterComposer
    extends Composer<_$AppDatabase, $ChoresTable> {
  $$ChoresTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<bool> get syncDirty => $composableBuilder(
    column: $table.syncDirty,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<Recurrence?, Recurrence, String>
  get recurrence => $composableBuilder(
    column: $table.recurrence,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnWithTypeConverterFilters<PlainDate, PlainDate, String> get startDate =>
      $composableBuilder(
        column: $table.startDate,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<AssignmentMode, AssignmentMode, String>
  get assignmentMode => $composableBuilder(
    column: $table.assignmentMode,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<String> get pausedAt => $composableBuilder(
    column: $table.pausedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$HouseholdsTableFilterComposer get householdId {
    final $$HouseholdsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.householdId,
      referencedTable: $db.households,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$HouseholdsTableFilterComposer(
            $db: $db,
            $table: $db.households,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$CategoriesTableFilterComposer get categoryId {
    final $$CategoriesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.categoryId,
      referencedTable: $db.categories,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CategoriesTableFilterComposer(
            $db: $db,
            $table: $db.categories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$MembersTableFilterComposer get createdBy {
    final $$MembersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.createdBy,
      referencedTable: $db.members,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MembersTableFilterComposer(
            $db: $db,
            $table: $db.members,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> choreAssigneesRefs(
    Expression<bool> Function($$ChoreAssigneesTableFilterComposer f) f,
  ) {
    final $$ChoreAssigneesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.choreAssignees,
      getReferencedColumn: (t) => t.choreId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ChoreAssigneesTableFilterComposer(
            $db: $db,
            $table: $db.choreAssignees,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> choreOccurrencesRefs(
    Expression<bool> Function($$ChoreOccurrencesTableFilterComposer f) f,
  ) {
    final $$ChoreOccurrencesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.choreOccurrences,
      getReferencedColumn: (t) => t.choreId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ChoreOccurrencesTableFilterComposer(
            $db: $db,
            $table: $db.choreOccurrences,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ChoresTableOrderingComposer
    extends Composer<_$AppDatabase, $ChoresTable> {
  $$ChoresTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<bool> get syncDirty => $composableBuilder(
    column: $table.syncDirty,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get recurrence => $composableBuilder(
    column: $table.recurrence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get startDate => $composableBuilder(
    column: $table.startDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get assignmentMode => $composableBuilder(
    column: $table.assignmentMode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pausedAt => $composableBuilder(
    column: $table.pausedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$HouseholdsTableOrderingComposer get householdId {
    final $$HouseholdsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.householdId,
      referencedTable: $db.households,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$HouseholdsTableOrderingComposer(
            $db: $db,
            $table: $db.households,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$CategoriesTableOrderingComposer get categoryId {
    final $$CategoriesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.categoryId,
      referencedTable: $db.categories,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CategoriesTableOrderingComposer(
            $db: $db,
            $table: $db.categories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$MembersTableOrderingComposer get createdBy {
    final $$MembersTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.createdBy,
      referencedTable: $db.members,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MembersTableOrderingComposer(
            $db: $db,
            $table: $db.members,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ChoresTableAnnotationComposer
    extends Composer<_$AppDatabase, $ChoresTable> {
  $$ChoresTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<bool> get syncDirty =>
      $composableBuilder(column: $table.syncDirty, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumnWithTypeConverter<Recurrence?, String> get recurrence =>
      $composableBuilder(
        column: $table.recurrence,
        builder: (column) => column,
      );

  GeneratedColumnWithTypeConverter<PlainDate, String> get startDate =>
      $composableBuilder(column: $table.startDate, builder: (column) => column);

  GeneratedColumnWithTypeConverter<AssignmentMode, String> get assignmentMode =>
      $composableBuilder(
        column: $table.assignmentMode,
        builder: (column) => column,
      );

  GeneratedColumn<String> get pausedAt =>
      $composableBuilder(column: $table.pausedAt, builder: (column) => column);

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  $$HouseholdsTableAnnotationComposer get householdId {
    final $$HouseholdsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.householdId,
      referencedTable: $db.households,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$HouseholdsTableAnnotationComposer(
            $db: $db,
            $table: $db.households,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$CategoriesTableAnnotationComposer get categoryId {
    final $$CategoriesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.categoryId,
      referencedTable: $db.categories,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CategoriesTableAnnotationComposer(
            $db: $db,
            $table: $db.categories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$MembersTableAnnotationComposer get createdBy {
    final $$MembersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.createdBy,
      referencedTable: $db.members,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MembersTableAnnotationComposer(
            $db: $db,
            $table: $db.members,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> choreAssigneesRefs<T extends Object>(
    Expression<T> Function($$ChoreAssigneesTableAnnotationComposer a) f,
  ) {
    final $$ChoreAssigneesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.choreAssignees,
      getReferencedColumn: (t) => t.choreId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ChoreAssigneesTableAnnotationComposer(
            $db: $db,
            $table: $db.choreAssignees,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> choreOccurrencesRefs<T extends Object>(
    Expression<T> Function($$ChoreOccurrencesTableAnnotationComposer a) f,
  ) {
    final $$ChoreOccurrencesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.choreOccurrences,
      getReferencedColumn: (t) => t.choreId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ChoreOccurrencesTableAnnotationComposer(
            $db: $db,
            $table: $db.choreOccurrences,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ChoresTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ChoresTable,
          Chore,
          $$ChoresTableFilterComposer,
          $$ChoresTableOrderingComposer,
          $$ChoresTableAnnotationComposer,
          $$ChoresTableCreateCompanionBuilder,
          $$ChoresTableUpdateCompanionBuilder,
          (Chore, $$ChoresTableReferences),
          Chore,
          PrefetchHooks Function({
            bool householdId,
            bool categoryId,
            bool createdBy,
            bool choreAssigneesRefs,
            bool choreOccurrencesRefs,
          })
        > {
  $$ChoresTableTableManager(_$AppDatabase db, $ChoresTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ChoresTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ChoresTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ChoresTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<bool> syncDirty = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> householdId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<String?> categoryId = const Value.absent(),
                Value<Recurrence?> recurrence = const Value.absent(),
                Value<PlainDate> startDate = const Value.absent(),
                Value<AssignmentMode> assignmentMode = const Value.absent(),
                Value<String?> pausedAt = const Value.absent(),
                Value<String?> createdBy = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
                Value<String> updatedAt = const Value.absent(),
                Value<String?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ChoresCompanion(
                syncDirty: syncDirty,
                id: id,
                householdId: householdId,
                title: title,
                notes: notes,
                categoryId: categoryId,
                recurrence: recurrence,
                startDate: startDate,
                assignmentMode: assignmentMode,
                pausedAt: pausedAt,
                createdBy: createdBy,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<bool> syncDirty = const Value.absent(),
                required String id,
                required String householdId,
                required String title,
                Value<String?> notes = const Value.absent(),
                Value<String?> categoryId = const Value.absent(),
                Value<Recurrence?> recurrence = const Value.absent(),
                required PlainDate startDate,
                required AssignmentMode assignmentMode,
                Value<String?> pausedAt = const Value.absent(),
                Value<String?> createdBy = const Value.absent(),
                required String createdAt,
                required String updatedAt,
                Value<String?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ChoresCompanion.insert(
                syncDirty: syncDirty,
                id: id,
                householdId: householdId,
                title: title,
                notes: notes,
                categoryId: categoryId,
                recurrence: recurrence,
                startDate: startDate,
                assignmentMode: assignmentMode,
                pausedAt: pausedAt,
                createdBy: createdBy,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$ChoresTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                householdId = false,
                categoryId = false,
                createdBy = false,
                choreAssigneesRefs = false,
                choreOccurrencesRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (choreAssigneesRefs) db.choreAssignees,
                    if (choreOccurrencesRefs) db.choreOccurrences,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (householdId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.householdId,
                                    referencedTable: $$ChoresTableReferences
                                        ._householdIdTable(db),
                                    referencedColumn: $$ChoresTableReferences
                                        ._householdIdTable(db)
                                        .id,
                                  )
                                  as T;
                        }
                        if (categoryId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.categoryId,
                                    referencedTable: $$ChoresTableReferences
                                        ._categoryIdTable(db),
                                    referencedColumn: $$ChoresTableReferences
                                        ._categoryIdTable(db)
                                        .id,
                                  )
                                  as T;
                        }
                        if (createdBy) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.createdBy,
                                    referencedTable: $$ChoresTableReferences
                                        ._createdByTable(db),
                                    referencedColumn: $$ChoresTableReferences
                                        ._createdByTable(db)
                                        .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (choreAssigneesRefs)
                        await $_getPrefetchedData<
                          Chore,
                          $ChoresTable,
                          ChoreAssignee
                        >(
                          currentTable: table,
                          referencedTable: $$ChoresTableReferences
                              ._choreAssigneesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ChoresTableReferences(
                                db,
                                table,
                                p0,
                              ).choreAssigneesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.choreId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (choreOccurrencesRefs)
                        await $_getPrefetchedData<
                          Chore,
                          $ChoresTable,
                          ChoreOccurrence
                        >(
                          currentTable: table,
                          referencedTable: $$ChoresTableReferences
                              ._choreOccurrencesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ChoresTableReferences(
                                db,
                                table,
                                p0,
                              ).choreOccurrencesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.choreId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$ChoresTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ChoresTable,
      Chore,
      $$ChoresTableFilterComposer,
      $$ChoresTableOrderingComposer,
      $$ChoresTableAnnotationComposer,
      $$ChoresTableCreateCompanionBuilder,
      $$ChoresTableUpdateCompanionBuilder,
      (Chore, $$ChoresTableReferences),
      Chore,
      PrefetchHooks Function({
        bool householdId,
        bool categoryId,
        bool createdBy,
        bool choreAssigneesRefs,
        bool choreOccurrencesRefs,
      })
    >;
typedef $$ChoreAssigneesTableCreateCompanionBuilder =
    ChoreAssigneesCompanion Function({
      Value<bool> syncDirty,
      required String choreId,
      required String memberId,
      required int position,
      Value<int> rowid,
    });
typedef $$ChoreAssigneesTableUpdateCompanionBuilder =
    ChoreAssigneesCompanion Function({
      Value<bool> syncDirty,
      Value<String> choreId,
      Value<String> memberId,
      Value<int> position,
      Value<int> rowid,
    });

final class $$ChoreAssigneesTableReferences
    extends BaseReferences<_$AppDatabase, $ChoreAssigneesTable, ChoreAssignee> {
  $$ChoreAssigneesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ChoresTable _choreIdTable(_$AppDatabase db) =>
      db.chores.createAlias('chore_assignees__chore_id__chores__id');

  $$ChoresTableProcessedTableManager get choreId {
    final $_column = $_itemColumn<String>('chore_id')!;

    final manager = $$ChoresTableTableManager(
      $_db,
      $_db.chores,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_choreIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $MembersTable _memberIdTable(_$AppDatabase db) =>
      db.members.createAlias('chore_assignees__member_id__members__id');

  $$MembersTableProcessedTableManager get memberId {
    final $_column = $_itemColumn<String>('member_id')!;

    final manager = $$MembersTableTableManager(
      $_db,
      $_db.members,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_memberIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ChoreAssigneesTableFilterComposer
    extends Composer<_$AppDatabase, $ChoreAssigneesTable> {
  $$ChoreAssigneesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<bool> get syncDirty => $composableBuilder(
    column: $table.syncDirty,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  $$ChoresTableFilterComposer get choreId {
    final $$ChoresTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.choreId,
      referencedTable: $db.chores,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ChoresTableFilterComposer(
            $db: $db,
            $table: $db.chores,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$MembersTableFilterComposer get memberId {
    final $$MembersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.memberId,
      referencedTable: $db.members,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MembersTableFilterComposer(
            $db: $db,
            $table: $db.members,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ChoreAssigneesTableOrderingComposer
    extends Composer<_$AppDatabase, $ChoreAssigneesTable> {
  $$ChoreAssigneesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<bool> get syncDirty => $composableBuilder(
    column: $table.syncDirty,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  $$ChoresTableOrderingComposer get choreId {
    final $$ChoresTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.choreId,
      referencedTable: $db.chores,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ChoresTableOrderingComposer(
            $db: $db,
            $table: $db.chores,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$MembersTableOrderingComposer get memberId {
    final $$MembersTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.memberId,
      referencedTable: $db.members,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MembersTableOrderingComposer(
            $db: $db,
            $table: $db.members,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ChoreAssigneesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ChoreAssigneesTable> {
  $$ChoreAssigneesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<bool> get syncDirty =>
      $composableBuilder(column: $table.syncDirty, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  $$ChoresTableAnnotationComposer get choreId {
    final $$ChoresTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.choreId,
      referencedTable: $db.chores,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ChoresTableAnnotationComposer(
            $db: $db,
            $table: $db.chores,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$MembersTableAnnotationComposer get memberId {
    final $$MembersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.memberId,
      referencedTable: $db.members,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MembersTableAnnotationComposer(
            $db: $db,
            $table: $db.members,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ChoreAssigneesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ChoreAssigneesTable,
          ChoreAssignee,
          $$ChoreAssigneesTableFilterComposer,
          $$ChoreAssigneesTableOrderingComposer,
          $$ChoreAssigneesTableAnnotationComposer,
          $$ChoreAssigneesTableCreateCompanionBuilder,
          $$ChoreAssigneesTableUpdateCompanionBuilder,
          (ChoreAssignee, $$ChoreAssigneesTableReferences),
          ChoreAssignee,
          PrefetchHooks Function({bool choreId, bool memberId})
        > {
  $$ChoreAssigneesTableTableManager(
    _$AppDatabase db,
    $ChoreAssigneesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ChoreAssigneesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ChoreAssigneesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ChoreAssigneesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<bool> syncDirty = const Value.absent(),
                Value<String> choreId = const Value.absent(),
                Value<String> memberId = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ChoreAssigneesCompanion(
                syncDirty: syncDirty,
                choreId: choreId,
                memberId: memberId,
                position: position,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<bool> syncDirty = const Value.absent(),
                required String choreId,
                required String memberId,
                required int position,
                Value<int> rowid = const Value.absent(),
              }) => ChoreAssigneesCompanion.insert(
                syncDirty: syncDirty,
                choreId: choreId,
                memberId: memberId,
                position: position,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ChoreAssigneesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({choreId = false, memberId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (choreId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.choreId,
                                referencedTable: $$ChoreAssigneesTableReferences
                                    ._choreIdTable(db),
                                referencedColumn:
                                    $$ChoreAssigneesTableReferences
                                        ._choreIdTable(db)
                                        .id,
                              )
                              as T;
                    }
                    if (memberId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.memberId,
                                referencedTable: $$ChoreAssigneesTableReferences
                                    ._memberIdTable(db),
                                referencedColumn:
                                    $$ChoreAssigneesTableReferences
                                        ._memberIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ChoreAssigneesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ChoreAssigneesTable,
      ChoreAssignee,
      $$ChoreAssigneesTableFilterComposer,
      $$ChoreAssigneesTableOrderingComposer,
      $$ChoreAssigneesTableAnnotationComposer,
      $$ChoreAssigneesTableCreateCompanionBuilder,
      $$ChoreAssigneesTableUpdateCompanionBuilder,
      (ChoreAssignee, $$ChoreAssigneesTableReferences),
      ChoreAssignee,
      PrefetchHooks Function({bool choreId, bool memberId})
    >;
typedef $$ChoreOccurrencesTableCreateCompanionBuilder =
    ChoreOccurrencesCompanion Function({
      Value<bool> syncDirty,
      required String id,
      required String choreId,
      required PlainDate dueDate,
      Value<OccurrenceStatus> status,
      Value<String?> assignedMemberId,
      Value<String?> completedBy,
      Value<PlainDate?> closedOn,
      required String createdAt,
      required String updatedAt,
      Value<int> rowid,
    });
typedef $$ChoreOccurrencesTableUpdateCompanionBuilder =
    ChoreOccurrencesCompanion Function({
      Value<bool> syncDirty,
      Value<String> id,
      Value<String> choreId,
      Value<PlainDate> dueDate,
      Value<OccurrenceStatus> status,
      Value<String?> assignedMemberId,
      Value<String?> completedBy,
      Value<PlainDate?> closedOn,
      Value<String> createdAt,
      Value<String> updatedAt,
      Value<int> rowid,
    });

final class $$ChoreOccurrencesTableReferences
    extends
        BaseReferences<_$AppDatabase, $ChoreOccurrencesTable, ChoreOccurrence> {
  $$ChoreOccurrencesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ChoresTable _choreIdTable(_$AppDatabase db) =>
      db.chores.createAlias('chore_occurrences__chore_id__chores__id');

  $$ChoresTableProcessedTableManager get choreId {
    final $_column = $_itemColumn<String>('chore_id')!;

    final manager = $$ChoresTableTableManager(
      $_db,
      $_db.chores,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_choreIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $MembersTable _assignedMemberIdTable(_$AppDatabase db) => db.members
      .createAlias('chore_occurrences__assigned_member_id__members__id');

  $$MembersTableProcessedTableManager? get assignedMemberId {
    final $_column = $_itemColumn<String>('assigned_member_id');
    if ($_column == null) return null;
    final manager = $$MembersTableTableManager(
      $_db,
      $_db.members,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_assignedMemberIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $MembersTable _completedByTable(_$AppDatabase db) =>
      db.members.createAlias('chore_occurrences__completed_by__members__id');

  $$MembersTableProcessedTableManager? get completedBy {
    final $_column = $_itemColumn<String>('completed_by');
    if ($_column == null) return null;
    final manager = $$MembersTableTableManager(
      $_db,
      $_db.members,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_completedByTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ChoreOccurrencesTableFilterComposer
    extends Composer<_$AppDatabase, $ChoreOccurrencesTable> {
  $$ChoreOccurrencesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<bool> get syncDirty => $composableBuilder(
    column: $table.syncDirty,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<PlainDate, PlainDate, String> get dueDate =>
      $composableBuilder(
        column: $table.dueDate,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<OccurrenceStatus, OccurrenceStatus, String>
  get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnWithTypeConverterFilters<PlainDate?, PlainDate, String> get closedOn =>
      $composableBuilder(
        column: $table.closedOn,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$ChoresTableFilterComposer get choreId {
    final $$ChoresTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.choreId,
      referencedTable: $db.chores,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ChoresTableFilterComposer(
            $db: $db,
            $table: $db.chores,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$MembersTableFilterComposer get assignedMemberId {
    final $$MembersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.assignedMemberId,
      referencedTable: $db.members,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MembersTableFilterComposer(
            $db: $db,
            $table: $db.members,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$MembersTableFilterComposer get completedBy {
    final $$MembersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.completedBy,
      referencedTable: $db.members,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MembersTableFilterComposer(
            $db: $db,
            $table: $db.members,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ChoreOccurrencesTableOrderingComposer
    extends Composer<_$AppDatabase, $ChoreOccurrencesTable> {
  $$ChoreOccurrencesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<bool> get syncDirty => $composableBuilder(
    column: $table.syncDirty,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get dueDate => $composableBuilder(
    column: $table.dueDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get closedOn => $composableBuilder(
    column: $table.closedOn,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$ChoresTableOrderingComposer get choreId {
    final $$ChoresTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.choreId,
      referencedTable: $db.chores,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ChoresTableOrderingComposer(
            $db: $db,
            $table: $db.chores,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$MembersTableOrderingComposer get assignedMemberId {
    final $$MembersTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.assignedMemberId,
      referencedTable: $db.members,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MembersTableOrderingComposer(
            $db: $db,
            $table: $db.members,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$MembersTableOrderingComposer get completedBy {
    final $$MembersTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.completedBy,
      referencedTable: $db.members,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MembersTableOrderingComposer(
            $db: $db,
            $table: $db.members,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ChoreOccurrencesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ChoreOccurrencesTable> {
  $$ChoreOccurrencesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<bool> get syncDirty =>
      $composableBuilder(column: $table.syncDirty, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumnWithTypeConverter<PlainDate, String> get dueDate =>
      $composableBuilder(column: $table.dueDate, builder: (column) => column);

  GeneratedColumnWithTypeConverter<OccurrenceStatus, String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumnWithTypeConverter<PlainDate?, String> get closedOn =>
      $composableBuilder(column: $table.closedOn, builder: (column) => column);

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$ChoresTableAnnotationComposer get choreId {
    final $$ChoresTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.choreId,
      referencedTable: $db.chores,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ChoresTableAnnotationComposer(
            $db: $db,
            $table: $db.chores,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$MembersTableAnnotationComposer get assignedMemberId {
    final $$MembersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.assignedMemberId,
      referencedTable: $db.members,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MembersTableAnnotationComposer(
            $db: $db,
            $table: $db.members,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$MembersTableAnnotationComposer get completedBy {
    final $$MembersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.completedBy,
      referencedTable: $db.members,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MembersTableAnnotationComposer(
            $db: $db,
            $table: $db.members,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ChoreOccurrencesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ChoreOccurrencesTable,
          ChoreOccurrence,
          $$ChoreOccurrencesTableFilterComposer,
          $$ChoreOccurrencesTableOrderingComposer,
          $$ChoreOccurrencesTableAnnotationComposer,
          $$ChoreOccurrencesTableCreateCompanionBuilder,
          $$ChoreOccurrencesTableUpdateCompanionBuilder,
          (ChoreOccurrence, $$ChoreOccurrencesTableReferences),
          ChoreOccurrence,
          PrefetchHooks Function({
            bool choreId,
            bool assignedMemberId,
            bool completedBy,
          })
        > {
  $$ChoreOccurrencesTableTableManager(
    _$AppDatabase db,
    $ChoreOccurrencesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ChoreOccurrencesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ChoreOccurrencesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ChoreOccurrencesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<bool> syncDirty = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> choreId = const Value.absent(),
                Value<PlainDate> dueDate = const Value.absent(),
                Value<OccurrenceStatus> status = const Value.absent(),
                Value<String?> assignedMemberId = const Value.absent(),
                Value<String?> completedBy = const Value.absent(),
                Value<PlainDate?> closedOn = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
                Value<String> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ChoreOccurrencesCompanion(
                syncDirty: syncDirty,
                id: id,
                choreId: choreId,
                dueDate: dueDate,
                status: status,
                assignedMemberId: assignedMemberId,
                completedBy: completedBy,
                closedOn: closedOn,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<bool> syncDirty = const Value.absent(),
                required String id,
                required String choreId,
                required PlainDate dueDate,
                Value<OccurrenceStatus> status = const Value.absent(),
                Value<String?> assignedMemberId = const Value.absent(),
                Value<String?> completedBy = const Value.absent(),
                Value<PlainDate?> closedOn = const Value.absent(),
                required String createdAt,
                required String updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => ChoreOccurrencesCompanion.insert(
                syncDirty: syncDirty,
                id: id,
                choreId: choreId,
                dueDate: dueDate,
                status: status,
                assignedMemberId: assignedMemberId,
                completedBy: completedBy,
                closedOn: closedOn,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ChoreOccurrencesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                choreId = false,
                assignedMemberId = false,
                completedBy = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (choreId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.choreId,
                                    referencedTable:
                                        $$ChoreOccurrencesTableReferences
                                            ._choreIdTable(db),
                                    referencedColumn:
                                        $$ChoreOccurrencesTableReferences
                                            ._choreIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }
                        if (assignedMemberId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.assignedMemberId,
                                    referencedTable:
                                        $$ChoreOccurrencesTableReferences
                                            ._assignedMemberIdTable(db),
                                    referencedColumn:
                                        $$ChoreOccurrencesTableReferences
                                            ._assignedMemberIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }
                        if (completedBy) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.completedBy,
                                    referencedTable:
                                        $$ChoreOccurrencesTableReferences
                                            ._completedByTable(db),
                                    referencedColumn:
                                        $$ChoreOccurrencesTableReferences
                                            ._completedByTable(db)
                                            .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [];
                  },
                );
              },
        ),
      );
}

typedef $$ChoreOccurrencesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ChoreOccurrencesTable,
      ChoreOccurrence,
      $$ChoreOccurrencesTableFilterComposer,
      $$ChoreOccurrencesTableOrderingComposer,
      $$ChoreOccurrencesTableAnnotationComposer,
      $$ChoreOccurrencesTableCreateCompanionBuilder,
      $$ChoreOccurrencesTableUpdateCompanionBuilder,
      (ChoreOccurrence, $$ChoreOccurrencesTableReferences),
      ChoreOccurrence,
      PrefetchHooks Function({
        bool choreId,
        bool assignedMemberId,
        bool completedBy,
      })
    >;
typedef $$ShoppingItemsTableCreateCompanionBuilder =
    ShoppingItemsCompanion Function({
      Value<bool> syncDirty,
      required String id,
      required String householdId,
      required String name,
      Value<String?> quantityNote,
      Value<String?> categoryId,
      Value<String?> addedBy,
      Value<String?> checkedAt,
      required String createdAt,
      required String updatedAt,
      Value<String?> deletedAt,
      Value<int> rowid,
    });
typedef $$ShoppingItemsTableUpdateCompanionBuilder =
    ShoppingItemsCompanion Function({
      Value<bool> syncDirty,
      Value<String> id,
      Value<String> householdId,
      Value<String> name,
      Value<String?> quantityNote,
      Value<String?> categoryId,
      Value<String?> addedBy,
      Value<String?> checkedAt,
      Value<String> createdAt,
      Value<String> updatedAt,
      Value<String?> deletedAt,
      Value<int> rowid,
    });

final class $$ShoppingItemsTableReferences
    extends BaseReferences<_$AppDatabase, $ShoppingItemsTable, ShoppingItem> {
  $$ShoppingItemsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $HouseholdsTable _householdIdTable(_$AppDatabase db) =>
      db.households.createAlias('shopping_items__household_id__households__id');

  $$HouseholdsTableProcessedTableManager get householdId {
    final $_column = $_itemColumn<String>('household_id')!;

    final manager = $$HouseholdsTableTableManager(
      $_db,
      $_db.households,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_householdIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $CategoriesTable _categoryIdTable(_$AppDatabase db) =>
      db.categories.createAlias('shopping_items__category_id__categories__id');

  $$CategoriesTableProcessedTableManager? get categoryId {
    final $_column = $_itemColumn<String>('category_id');
    if ($_column == null) return null;
    final manager = $$CategoriesTableTableManager(
      $_db,
      $_db.categories,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_categoryIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $MembersTable _addedByTable(_$AppDatabase db) =>
      db.members.createAlias('shopping_items__added_by__members__id');

  $$MembersTableProcessedTableManager? get addedBy {
    final $_column = $_itemColumn<String>('added_by');
    if ($_column == null) return null;
    final manager = $$MembersTableTableManager(
      $_db,
      $_db.members,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_addedByTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ShoppingItemsTableFilterComposer
    extends Composer<_$AppDatabase, $ShoppingItemsTable> {
  $$ShoppingItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<bool> get syncDirty => $composableBuilder(
    column: $table.syncDirty,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get quantityNote => $composableBuilder(
    column: $table.quantityNote,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get checkedAt => $composableBuilder(
    column: $table.checkedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$HouseholdsTableFilterComposer get householdId {
    final $$HouseholdsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.householdId,
      referencedTable: $db.households,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$HouseholdsTableFilterComposer(
            $db: $db,
            $table: $db.households,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$CategoriesTableFilterComposer get categoryId {
    final $$CategoriesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.categoryId,
      referencedTable: $db.categories,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CategoriesTableFilterComposer(
            $db: $db,
            $table: $db.categories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$MembersTableFilterComposer get addedBy {
    final $$MembersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.addedBy,
      referencedTable: $db.members,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MembersTableFilterComposer(
            $db: $db,
            $table: $db.members,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ShoppingItemsTableOrderingComposer
    extends Composer<_$AppDatabase, $ShoppingItemsTable> {
  $$ShoppingItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<bool> get syncDirty => $composableBuilder(
    column: $table.syncDirty,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get quantityNote => $composableBuilder(
    column: $table.quantityNote,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get checkedAt => $composableBuilder(
    column: $table.checkedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$HouseholdsTableOrderingComposer get householdId {
    final $$HouseholdsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.householdId,
      referencedTable: $db.households,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$HouseholdsTableOrderingComposer(
            $db: $db,
            $table: $db.households,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$CategoriesTableOrderingComposer get categoryId {
    final $$CategoriesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.categoryId,
      referencedTable: $db.categories,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CategoriesTableOrderingComposer(
            $db: $db,
            $table: $db.categories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$MembersTableOrderingComposer get addedBy {
    final $$MembersTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.addedBy,
      referencedTable: $db.members,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MembersTableOrderingComposer(
            $db: $db,
            $table: $db.members,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ShoppingItemsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ShoppingItemsTable> {
  $$ShoppingItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<bool> get syncDirty =>
      $composableBuilder(column: $table.syncDirty, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get quantityNote => $composableBuilder(
    column: $table.quantityNote,
    builder: (column) => column,
  );

  GeneratedColumn<String> get checkedAt =>
      $composableBuilder(column: $table.checkedAt, builder: (column) => column);

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  $$HouseholdsTableAnnotationComposer get householdId {
    final $$HouseholdsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.householdId,
      referencedTable: $db.households,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$HouseholdsTableAnnotationComposer(
            $db: $db,
            $table: $db.households,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$CategoriesTableAnnotationComposer get categoryId {
    final $$CategoriesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.categoryId,
      referencedTable: $db.categories,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CategoriesTableAnnotationComposer(
            $db: $db,
            $table: $db.categories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$MembersTableAnnotationComposer get addedBy {
    final $$MembersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.addedBy,
      referencedTable: $db.members,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MembersTableAnnotationComposer(
            $db: $db,
            $table: $db.members,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ShoppingItemsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ShoppingItemsTable,
          ShoppingItem,
          $$ShoppingItemsTableFilterComposer,
          $$ShoppingItemsTableOrderingComposer,
          $$ShoppingItemsTableAnnotationComposer,
          $$ShoppingItemsTableCreateCompanionBuilder,
          $$ShoppingItemsTableUpdateCompanionBuilder,
          (ShoppingItem, $$ShoppingItemsTableReferences),
          ShoppingItem,
          PrefetchHooks Function({
            bool householdId,
            bool categoryId,
            bool addedBy,
          })
        > {
  $$ShoppingItemsTableTableManager(_$AppDatabase db, $ShoppingItemsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ShoppingItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ShoppingItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ShoppingItemsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<bool> syncDirty = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> householdId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> quantityNote = const Value.absent(),
                Value<String?> categoryId = const Value.absent(),
                Value<String?> addedBy = const Value.absent(),
                Value<String?> checkedAt = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
                Value<String> updatedAt = const Value.absent(),
                Value<String?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ShoppingItemsCompanion(
                syncDirty: syncDirty,
                id: id,
                householdId: householdId,
                name: name,
                quantityNote: quantityNote,
                categoryId: categoryId,
                addedBy: addedBy,
                checkedAt: checkedAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<bool> syncDirty = const Value.absent(),
                required String id,
                required String householdId,
                required String name,
                Value<String?> quantityNote = const Value.absent(),
                Value<String?> categoryId = const Value.absent(),
                Value<String?> addedBy = const Value.absent(),
                Value<String?> checkedAt = const Value.absent(),
                required String createdAt,
                required String updatedAt,
                Value<String?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ShoppingItemsCompanion.insert(
                syncDirty: syncDirty,
                id: id,
                householdId: householdId,
                name: name,
                quantityNote: quantityNote,
                categoryId: categoryId,
                addedBy: addedBy,
                checkedAt: checkedAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ShoppingItemsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({householdId = false, categoryId = false, addedBy = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (householdId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.householdId,
                                    referencedTable:
                                        $$ShoppingItemsTableReferences
                                            ._householdIdTable(db),
                                    referencedColumn:
                                        $$ShoppingItemsTableReferences
                                            ._householdIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }
                        if (categoryId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.categoryId,
                                    referencedTable:
                                        $$ShoppingItemsTableReferences
                                            ._categoryIdTable(db),
                                    referencedColumn:
                                        $$ShoppingItemsTableReferences
                                            ._categoryIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }
                        if (addedBy) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.addedBy,
                                    referencedTable:
                                        $$ShoppingItemsTableReferences
                                            ._addedByTable(db),
                                    referencedColumn:
                                        $$ShoppingItemsTableReferences
                                            ._addedByTable(db)
                                            .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [];
                  },
                );
              },
        ),
      );
}

typedef $$ShoppingItemsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ShoppingItemsTable,
      ShoppingItem,
      $$ShoppingItemsTableFilterComposer,
      $$ShoppingItemsTableOrderingComposer,
      $$ShoppingItemsTableAnnotationComposer,
      $$ShoppingItemsTableCreateCompanionBuilder,
      $$ShoppingItemsTableUpdateCompanionBuilder,
      (ShoppingItem, $$ShoppingItemsTableReferences),
      ShoppingItem,
      PrefetchHooks Function({bool householdId, bool categoryId, bool addedBy})
    >;
typedef $$SettingsTableCreateCompanionBuilder =
    SettingsCompanion Function({
      required String id,
      Value<bool> digestEnabled,
      Value<int> digestMinutes,
      Value<String?> actingMemberId,
      Value<String?> locale,
      Value<String?> onboardingNamePromptShownAt,
      Value<String?> digestPrepromptShownAt,
      Value<String?> syncHouseholdId,
      Value<String?> syncLinkedAt,
      Value<String?> themeMode,
      Value<String?> syncLastPulledAt,
      Value<bool> membershipRevoked,
      required String createdAt,
      required String updatedAt,
      Value<int> rowid,
    });
typedef $$SettingsTableUpdateCompanionBuilder =
    SettingsCompanion Function({
      Value<String> id,
      Value<bool> digestEnabled,
      Value<int> digestMinutes,
      Value<String?> actingMemberId,
      Value<String?> locale,
      Value<String?> onboardingNamePromptShownAt,
      Value<String?> digestPrepromptShownAt,
      Value<String?> syncHouseholdId,
      Value<String?> syncLinkedAt,
      Value<String?> themeMode,
      Value<String?> syncLastPulledAt,
      Value<bool> membershipRevoked,
      Value<String> createdAt,
      Value<String> updatedAt,
      Value<int> rowid,
    });

class $$SettingsTableFilterComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get digestEnabled => $composableBuilder(
    column: $table.digestEnabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get digestMinutes => $composableBuilder(
    column: $table.digestMinutes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get actingMemberId => $composableBuilder(
    column: $table.actingMemberId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get locale => $composableBuilder(
    column: $table.locale,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get onboardingNamePromptShownAt => $composableBuilder(
    column: $table.onboardingNamePromptShownAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get digestPrepromptShownAt => $composableBuilder(
    column: $table.digestPrepromptShownAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get syncHouseholdId => $composableBuilder(
    column: $table.syncHouseholdId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get syncLinkedAt => $composableBuilder(
    column: $table.syncLinkedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get themeMode => $composableBuilder(
    column: $table.themeMode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get syncLastPulledAt => $composableBuilder(
    column: $table.syncLastPulledAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get membershipRevoked => $composableBuilder(
    column: $table.membershipRevoked,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SettingsTableOrderingComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get digestEnabled => $composableBuilder(
    column: $table.digestEnabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get digestMinutes => $composableBuilder(
    column: $table.digestMinutes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get actingMemberId => $composableBuilder(
    column: $table.actingMemberId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get locale => $composableBuilder(
    column: $table.locale,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get onboardingNamePromptShownAt => $composableBuilder(
    column: $table.onboardingNamePromptShownAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get digestPrepromptShownAt => $composableBuilder(
    column: $table.digestPrepromptShownAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get syncHouseholdId => $composableBuilder(
    column: $table.syncHouseholdId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get syncLinkedAt => $composableBuilder(
    column: $table.syncLinkedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get themeMode => $composableBuilder(
    column: $table.themeMode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get syncLastPulledAt => $composableBuilder(
    column: $table.syncLastPulledAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get membershipRevoked => $composableBuilder(
    column: $table.membershipRevoked,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SettingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<bool> get digestEnabled => $composableBuilder(
    column: $table.digestEnabled,
    builder: (column) => column,
  );

  GeneratedColumn<int> get digestMinutes => $composableBuilder(
    column: $table.digestMinutes,
    builder: (column) => column,
  );

  GeneratedColumn<String> get actingMemberId => $composableBuilder(
    column: $table.actingMemberId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get locale =>
      $composableBuilder(column: $table.locale, builder: (column) => column);

  GeneratedColumn<String> get onboardingNamePromptShownAt => $composableBuilder(
    column: $table.onboardingNamePromptShownAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get digestPrepromptShownAt => $composableBuilder(
    column: $table.digestPrepromptShownAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get syncHouseholdId => $composableBuilder(
    column: $table.syncHouseholdId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get syncLinkedAt => $composableBuilder(
    column: $table.syncLinkedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get themeMode =>
      $composableBuilder(column: $table.themeMode, builder: (column) => column);

  GeneratedColumn<String> get syncLastPulledAt => $composableBuilder(
    column: $table.syncLastPulledAt,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get membershipRevoked => $composableBuilder(
    column: $table.membershipRevoked,
    builder: (column) => column,
  );

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$SettingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SettingsTable,
          DeviceSettings,
          $$SettingsTableFilterComposer,
          $$SettingsTableOrderingComposer,
          $$SettingsTableAnnotationComposer,
          $$SettingsTableCreateCompanionBuilder,
          $$SettingsTableUpdateCompanionBuilder,
          (
            DeviceSettings,
            BaseReferences<_$AppDatabase, $SettingsTable, DeviceSettings>,
          ),
          DeviceSettings,
          PrefetchHooks Function()
        > {
  $$SettingsTableTableManager(_$AppDatabase db, $SettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<bool> digestEnabled = const Value.absent(),
                Value<int> digestMinutes = const Value.absent(),
                Value<String?> actingMemberId = const Value.absent(),
                Value<String?> locale = const Value.absent(),
                Value<String?> onboardingNamePromptShownAt =
                    const Value.absent(),
                Value<String?> digestPrepromptShownAt = const Value.absent(),
                Value<String?> syncHouseholdId = const Value.absent(),
                Value<String?> syncLinkedAt = const Value.absent(),
                Value<String?> themeMode = const Value.absent(),
                Value<String?> syncLastPulledAt = const Value.absent(),
                Value<bool> membershipRevoked = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
                Value<String> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SettingsCompanion(
                id: id,
                digestEnabled: digestEnabled,
                digestMinutes: digestMinutes,
                actingMemberId: actingMemberId,
                locale: locale,
                onboardingNamePromptShownAt: onboardingNamePromptShownAt,
                digestPrepromptShownAt: digestPrepromptShownAt,
                syncHouseholdId: syncHouseholdId,
                syncLinkedAt: syncLinkedAt,
                themeMode: themeMode,
                syncLastPulledAt: syncLastPulledAt,
                membershipRevoked: membershipRevoked,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<bool> digestEnabled = const Value.absent(),
                Value<int> digestMinutes = const Value.absent(),
                Value<String?> actingMemberId = const Value.absent(),
                Value<String?> locale = const Value.absent(),
                Value<String?> onboardingNamePromptShownAt =
                    const Value.absent(),
                Value<String?> digestPrepromptShownAt = const Value.absent(),
                Value<String?> syncHouseholdId = const Value.absent(),
                Value<String?> syncLinkedAt = const Value.absent(),
                Value<String?> themeMode = const Value.absent(),
                Value<String?> syncLastPulledAt = const Value.absent(),
                Value<bool> membershipRevoked = const Value.absent(),
                required String createdAt,
                required String updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => SettingsCompanion.insert(
                id: id,
                digestEnabled: digestEnabled,
                digestMinutes: digestMinutes,
                actingMemberId: actingMemberId,
                locale: locale,
                onboardingNamePromptShownAt: onboardingNamePromptShownAt,
                digestPrepromptShownAt: digestPrepromptShownAt,
                syncHouseholdId: syncHouseholdId,
                syncLinkedAt: syncLinkedAt,
                themeMode: themeMode,
                syncLastPulledAt: syncLastPulledAt,
                membershipRevoked: membershipRevoked,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SettingsTable,
      DeviceSettings,
      $$SettingsTableFilterComposer,
      $$SettingsTableOrderingComposer,
      $$SettingsTableAnnotationComposer,
      $$SettingsTableCreateCompanionBuilder,
      $$SettingsTableUpdateCompanionBuilder,
      (
        DeviceSettings,
        BaseReferences<_$AppDatabase, $SettingsTable, DeviceSettings>,
      ),
      DeviceSettings,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$HouseholdsTableTableManager get households =>
      $$HouseholdsTableTableManager(_db, _db.households);
  $$MembersTableTableManager get members =>
      $$MembersTableTableManager(_db, _db.members);
  $$CategoriesTableTableManager get categories =>
      $$CategoriesTableTableManager(_db, _db.categories);
  $$ChoresTableTableManager get chores =>
      $$ChoresTableTableManager(_db, _db.chores);
  $$ChoreAssigneesTableTableManager get choreAssignees =>
      $$ChoreAssigneesTableTableManager(_db, _db.choreAssignees);
  $$ChoreOccurrencesTableTableManager get choreOccurrences =>
      $$ChoreOccurrencesTableTableManager(_db, _db.choreOccurrences);
  $$ShoppingItemsTableTableManager get shoppingItems =>
      $$ShoppingItemsTableTableManager(_db, _db.shoppingItems);
  $$SettingsTableTableManager get settings =>
      $$SettingsTableTableManager(_db, _db.settings);
}
