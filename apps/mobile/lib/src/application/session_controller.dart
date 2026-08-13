import 'dart:async';

import '../data/security/token_store.dart';
import '../domain/session.dart';

final class SessionController {
  SessionController(this._tokenStore);

  final TokenStore _tokenStore;
  final StreamController<SessionSnapshot> _changes =
      StreamController<SessionSnapshot>.broadcast();

  SessionSnapshot _current = const SessionSnapshot(SessionStatus.unknown);

  SessionSnapshot get current => _current;
  Stream<SessionSnapshot> get changes => _changes.stream;

  Future<void> initialize() async {
    final tokens = await _tokenStore.read();
    _setStatus(
      tokens == null ? SessionStatus.signedOut : SessionStatus.signedIn,
    );
  }

  void markSignedIn() => _setStatus(SessionStatus.signedIn);

  void markSignedOut() => _setStatus(SessionStatus.signedOut);

  void _setStatus(SessionStatus status) {
    if (_current.status == status) {
      return;
    }
    _current = SessionSnapshot(status);
    _changes.add(_current);
  }

  Future<void> close() => _changes.close();
}
