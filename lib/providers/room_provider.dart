import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../db/database_helper.dart';
import '../models/room.dart';

class RoomProvider extends ChangeNotifier {
  List<Room> _rooms = [];
  List<Room> get rooms => _rooms;

  Room? _activeRoom;
  Room? get activeRoom => _activeRoom;

  Future<void> loadRooms() async {
    _rooms = await DatabaseHelper.instance.getRooms();
    _activeRoom ??= _rooms.isNotEmpty ? _rooms.first : null;
    notifyListeners();
  }

  Future<Room> createRoom({
    required String name,
    required String password,
  }) async {
    final now = DateTime.now();
    final room = Room(
      roomId: const Uuid().v4(),
      name: name,
      isLocked: password.isNotEmpty,
      password: password,
      createdAt: now,
      joinedAt: now,
    );
    await DatabaseHelper.instance.upsertRoom(room);
    await loadRooms();
    _activeRoom = _rooms.firstWhere((r) => r.roomId == room.roomId, orElse: () => room);
    notifyListeners();
    return room;
  }

  Future<Room?> joinRoom({
    required String roomName,
    required String password,
  }) async {
    final normalized = roomName.trim().toLowerCase();
    if (normalized.isEmpty) return null;

    final existing = _rooms.cast<Room?>().firstWhere(
          (room) => room != null && room.name.trim().toLowerCase() == normalized,
          orElse: () => null,
        );

    if (existing != null) {
      if (existing.isLocked && existing.password != password) {
        return null;
      }
      _activeRoom = existing;
      notifyListeners();
      return existing;
    }

    return createRoom(name: roomName.trim(), password: password);
  }

  Future<void> ensureRoomForPost({
    required String roomId,
    required String roomName,
  }) async {
    final existing = await DatabaseHelper.instance.getRoom(roomId);
    if (existing != null) return;
    final now = DateTime.now();
    await DatabaseHelper.instance.upsertRoom(
      Room(
        roomId: roomId,
        name: roomName,
        isLocked: false,
        password: '',
        createdAt: now,
        joinedAt: now,
      ),
    );
    await loadRooms();
  }

  void setActiveRoom(Room room) {
    _activeRoom = room;
    notifyListeners();
  }
}
