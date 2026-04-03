class Room {
  final String roomId;
  final String name;
  final bool isLocked;
  final String password;
  final DateTime createdAt;
  final DateTime joinedAt;

  const Room({
    required this.roomId,
    required this.name,
    required this.isLocked,
    required this.password,
    required this.createdAt,
    required this.joinedAt,
  });

  Map<String, dynamic> toMap() => {
        'room_id': roomId,
        'name': name,
        'is_locked': isLocked ? 1 : 0,
        'password': password,
        'created_at': createdAt.toIso8601String(),
        'joined_at': joinedAt.toIso8601String(),
      };

  factory Room.fromMap(Map<String, dynamic> map) => Room(
        roomId: map['room_id'] as String,
        name: map['name'] as String,
        isLocked: map['is_locked'] == 1 || map['is_locked'] == true,
        password: map['password'] as String? ?? '',
        createdAt: DateTime.parse(map['created_at'] as String),
        joinedAt: DateTime.parse(map['joined_at'] as String),
      );
}
