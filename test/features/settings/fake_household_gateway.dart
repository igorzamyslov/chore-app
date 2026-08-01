/// Fake [HouseholdGateway] for the Settings/Members P2b widget tests: no
/// real network calls, fully controllable success/failure per method and
/// recorded calls for assertions.
library;

import 'package:chore_app/application/household_gateway.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/household_repository.dart';

/// One recorded [FakeHouseholdGateway.createHousehold] call.
typedef CreateHouseholdCall = ({
  String householdId,
  String name,
  String memberId,
  String memberName,
  int memberColor,
});

/// One recorded [FakeHouseholdGateway.joinAsNewMember] call.
typedef JoinAsNewMemberCall = ({
  String code,
  String memberId,
  String memberName,
  int memberColor,
});

/// A controllable fake [HouseholdGateway].
///
/// Every method records its call (see the `*Calls` fields) and, unless the
/// matching `*Error` is set, succeeds with a canned/echoed result.
/// [createHousehold] additionally tracks which household ids it has
/// "created" in [_createdHouseholdIds], so a subsequent [downloadHousehold]
/// call for the same id can report it as already existing -- this is what
/// lets a test simulate `HouseholdLinkService.adopt`'s step-1
/// retry-tolerance (a second `createHousehold` call throwing, followed by
/// `downloadHousehold` reporting the household already exists).
class FakeHouseholdGateway implements HouseholdGateway {
  /// Creates a fake gateway. [inviteCode] is what [createInvite] returns by
  /// default.
  FakeHouseholdGateway({this.inviteCode = 'AB3D7XQ9'});

  /// The code [createInvite] returns unless [createInviteError] is set.
  String inviteCode;

  /// Set to make the next [createHousehold] call throw this instead of
  /// succeeding.
  Exception? createHouseholdError;

  /// Set to make the next [uploadHouseholdData] call throw this instead of
  /// succeeding.
  Exception? uploadHouseholdDataError;

  /// Set to make the next [createInvite] call throw this instead of
  /// succeeding.
  Exception? createInviteError;

  /// Set to make the next [downloadHousehold] call throw this instead of
  /// succeeding.
  Exception? downloadHouseholdError;

  /// If set, [downloadHousehold] returns this snapshot unconditionally
  /// (regardless of [_createdHouseholdIds] / the requested household id) --
  /// used by the P2c join-flow tests, which need a canned snapshot for a
  /// household this fake never "created" via [createHousehold] (join/claim
  /// never calls it). Falls back to the P2b adopt tests' original
  /// [_createdHouseholdIds]-based behavior when left `null`.
  HouseholdSnapshot? downloadSnapshotOverride;

  /// Every [createHousehold] call, in call order.
  final List<CreateHouseholdCall> createHouseholdCalls = [];

  /// Every [uploadHouseholdData] call's snapshot, in call order.
  final List<HouseholdSnapshot> uploadHouseholdDataCalls = [];

  /// Every [createInvite] call's household id, in call order.
  final List<String> createInviteCalls = [];

  /// Every [downloadHousehold] call's household id, in call order.
  final List<String> downloadHouseholdCalls = [];

  /// Every [listClaimableMembers] call's code, in call order.
  final List<String> listClaimableMembersCalls = [];

  /// Every [claimMember] call, in call order.
  final List<({String code, String memberId})> claimMemberCalls = [];

  /// Every [joinAsNewMember] call, in call order.
  final List<JoinAsNewMemberCall> joinAsNewMemberCalls = [];

  /// The list [listClaimableMembers] returns unless
  /// [listClaimableMembersError] is set.
  List<ClaimableMember> claimableMembers = const [];

  /// Set to make the next [listClaimableMembers] call throw this instead of
  /// succeeding.
  Exception? listClaimableMembersError;

  /// The household id [claimMember] returns unless [claimMemberError] is
  /// set.
  String claimResultHouseholdId = 'household-1';

  /// Set to make the next [claimMember] call throw this instead of
  /// succeeding.
  Exception? claimMemberError;

  /// The household id [joinAsNewMember] returns unless
  /// [joinAsNewMemberError] is set.
  String joinResultHouseholdId = 'household-1';

  /// Set to make the next [joinAsNewMember] call throw this instead of
  /// succeeding.
  Exception? joinAsNewMemberError;

  /// The membership [findMyMembership] returns unless
  /// [findMyMembershipError] is set; `null` (the default) means "no
  /// membership anywhere".
  MyMembership? membership;

  /// Set to make the next [findMyMembership] call throw this instead of
  /// succeeding.
  Exception? findMyMembershipError;

  /// How many times [findMyMembership] has been called -- the P2d
  /// reconnect probe (`myMembershipProvider`) is meant to be skipped
  /// entirely while signed out or under `NoopHouseholdGateway`, so tests
  /// assert this stays `0` in those cases.
  int findMyMembershipCallCount = 0;

  final Set<String> _createdHouseholdIds = {};

  @override
  Future<void> createHousehold({
    required String householdId,
    required String name,
    required String memberId,
    required String memberName,
    required int memberColor,
  }) async {
    createHouseholdCalls.add((
      householdId: householdId,
      name: name,
      memberId: memberId,
      memberName: memberName,
      memberColor: memberColor,
    ));
    final error = createHouseholdError;
    if (error != null) {
      throw error;
    }
    _createdHouseholdIds.add(householdId);
  }

  @override
  Future<void> uploadHouseholdData(HouseholdSnapshot snapshot) async {
    uploadHouseholdDataCalls.add(snapshot);
    final error = uploadHouseholdDataError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<String> createInvite(String householdId) async {
    createInviteCalls.add(householdId);
    final error = createInviteError;
    if (error != null) {
      throw error;
    }
    return inviteCode;
  }

  @override
  Future<List<ClaimableMember>> listClaimableMembers(String code) async {
    listClaimableMembersCalls.add(code);
    final error = listClaimableMembersError;
    if (error != null) {
      throw error;
    }
    return claimableMembers;
  }

  @override
  Future<String> claimMember(String code, String memberId) async {
    claimMemberCalls.add((code: code, memberId: memberId));
    final error = claimMemberError;
    if (error != null) {
      throw error;
    }
    return claimResultHouseholdId;
  }

  @override
  Future<String> joinAsNewMember({
    required String code,
    required String memberId,
    required String memberName,
    required int memberColor,
  }) async {
    joinAsNewMemberCalls.add((
      code: code,
      memberId: memberId,
      memberName: memberName,
      memberColor: memberColor,
    ));
    final error = joinAsNewMemberError;
    if (error != null) {
      throw error;
    }
    return joinResultHouseholdId;
  }

  @override
  Future<HouseholdSnapshot> downloadHousehold(String householdId) async {
    downloadHouseholdCalls.add(householdId);
    final error = downloadHouseholdError;
    if (error != null) {
      throw error;
    }
    final override = downloadSnapshotOverride;
    if (override != null) {
      return override;
    }
    if (!_createdHouseholdIds.contains(householdId)) {
      return const HouseholdSnapshot();
    }
    return HouseholdSnapshot(
      household: Household(
        id: householdId,
        name: 'Downloaded household',
        createdAt: 't0',
        updatedAt: 't0',
        syncDirty: false,
      ),
    );
  }

  @override
  Future<MyMembership?> findMyMembership() async {
    findMyMembershipCallCount++;
    final error = findMyMembershipError;
    if (error != null) {
      throw error;
    }
    return membership;
  }
}
