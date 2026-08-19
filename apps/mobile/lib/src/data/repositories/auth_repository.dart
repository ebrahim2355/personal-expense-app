import 'package:drift/drift.dart';

import '../../application/push_registration.dart';
import '../../application/session_controller.dart';
import '../../domain/expense.dart';
import '../../domain/session.dart';
import '../local/app_database.dart';
import '../remote/api_client.dart';
import '../security/token_store.dart';

abstract interface class MemberAuthRepository {
  Future<MemberIdentity> login(HouseholdMember member, String pin);

  Future<MemberIdentity?> restoreStoredIdentity();

  Future<void> logout();

  Future<void> signOutLocally();
}

final class AuthRepository implements MemberAuthRepository {
  const AuthRepository({
    required this._api,
    required this._tokenStore,
    required this._sessionController,
    required this._database,
    required this._deviceDeregistration,
  });

  final AuthenticationApi _api;
  final TokenStore _tokenStore;
  final SessionController _sessionController;
  final AppDatabase _database;
  final DeviceDeregistration _deviceDeregistration;

  @override
  Future<MemberIdentity> login(HouseholdMember member, String pin) async {
    if (!RegExp(r'^\d{6,12}$').hasMatch(pin)) {
      throw ArgumentError.value(pin, 'pin', 'PIN must contain 6 to 12 digits.');
    }
    final response = await _api.login(member, pin);
    await _tokenStore.write(response.tokens);
    final identity = response.member.toDomain();
    await (_database.update(
      _database.syncMetadata,
    )..where((row) => row.singletonId.equals(1))).write(
      SyncMetadataCompanion(
        householdId: Value<String>(identity.householdId),
        memberId: Value<String>(identity.id),
        memberKey: Value<String>(identity.member.wireName),
        updatedAt: Value<DateTime>(DateTime.now().toUtc()),
      ),
    );
    _sessionController.markSignedIn(identity);
    return identity;
  }

  @override
  Future<MemberIdentity?> restoreStoredIdentity() async {
    final metadata = await _database.readSyncMetadata();
    final memberId = metadata.memberId;
    final householdId = metadata.householdId;
    final memberKey = metadata.memberKey;
    if (memberId == null || householdId == null || memberKey == null) {
      return null;
    }
    final member = HouseholdMemberWire.parse(memberKey);
    final identity = MemberIdentity(
      id: memberId,
      householdId: householdId,
      member: member,
      displayName: member.displayName,
    );
    _sessionController.restoreMember(identity);
    return identity;
  }

  @override
  Future<void> logout() async {
    final tokens = await _tokenStore.read();
    if (tokens != null) {
      // Before the logout call, because giving up the push token needs an access
      // token the server still accepts, and logout is what revokes it. A phone
      // that stays registered after sign-out would be woken for a household it
      // can no longer show.
      await _deviceDeregistration.unregister();
      try {
        await _api.logout(tokens);
      } on Object {
        // Local logout must remain available while offline. Access tokens are
        // short lived; the server revocation is best effort in this case.
      }
    }
    await signOutLocally();
  }

  @override
  Future<void> signOutLocally() async {
    await _tokenStore.clear();
    _sessionController.markSignedOut();
  }
}
