import 'package:drift/drift.dart';

import '../../application/session_controller.dart';
import '../../domain/expense.dart';
import '../../domain/session.dart';
import '../local/app_database.dart';
import '../remote/api_client.dart';
import '../security/token_store.dart';

final class AuthRepository {
  const AuthRepository({
    required this._api,
    required this._tokenStore,
    required this._sessionController,
    required this._database,
  });

  final AuthenticationApi _api;
  final TokenStore _tokenStore;
  final SessionController _sessionController;
  final AppDatabase _database;

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
    _sessionController.markSignedIn();
    return identity;
  }

  Future<void> signOutLocally() async {
    await _tokenStore.clear();
    _sessionController.markSignedOut();
  }
}
