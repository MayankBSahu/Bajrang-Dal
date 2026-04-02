import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/identity.dart';
import '../db/database_helper.dart';

class IdentityProvider extends ChangeNotifier {
  Identity? _identity;
  Identity? get identity => _identity;

  Future<void> load() async {
    _identity = await DatabaseHelper.instance.getIdentity();
    if (_identity == null) await _createIdentity();
    notifyListeners();
  }

  Future<void> _createIdentity() async {
    _identity = Identity(
      peerId: const Uuid().v4(),
      displayName: 'User_${const Uuid().v4().substring(0, 5)}',
      publicKey: 'placeholder',   // Phase 3: real Ed25519 key
      createdAt: DateTime.now(),
    );
    await DatabaseHelper.instance.saveIdentity(_identity!);
  }

  Future<void> updateName(String name) async {
    if (_identity == null) return;
    _identity = Identity(
      peerId: _identity!.peerId,
      displayName: name,
      publicKey: _identity!.publicKey,
      createdAt: _identity!.createdAt,
    );
    await DatabaseHelper.instance.saveIdentity(_identity!);
    notifyListeners();
  }
}