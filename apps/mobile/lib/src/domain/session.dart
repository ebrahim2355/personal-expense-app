import 'expense.dart';

final class MemberIdentity {
  const MemberIdentity({
    required this.id,
    required this.householdId,
    required this.member,
    required this.displayName,
  });

  final String id;
  final String householdId;
  final HouseholdMember member;
  final String displayName;
}

final class SessionTokens {
  const SessionTokens({
    required this.accessToken,
    required this.accessTokenExpiresAt,
    required this.refreshToken,
    required this.refreshTokenExpiresAt,
  });

  final String accessToken;
  final DateTime accessTokenExpiresAt;
  final String refreshToken;
  final DateTime refreshTokenExpiresAt;
}

enum SessionStatus { unknown, signedIn, signedOut }

final class SessionSnapshot {
  const SessionSnapshot(this.status, {this.member});

  final SessionStatus status;
  final MemberIdentity? member;
}
