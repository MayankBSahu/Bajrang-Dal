class SharedFile {
  final String fileId;
  final String roomId;
  final String roomName;
  final String senderId;
  final String senderName;
  final String fileName;
  final String localPath;
  final int fileSize;
  final String mimeType;
  final DateTime createdAt;
  final bool isOutgoing;

  const SharedFile({
    required this.fileId,
    required this.roomId,
    required this.roomName,
    required this.senderId,
    required this.senderName,
    required this.fileName,
    required this.localPath,
    required this.fileSize,
    required this.mimeType,
    required this.createdAt,
    required this.isOutgoing,
  });

  Map<String, dynamic> toMap() => {
        'file_id': fileId,
        'room_id': roomId,
        'room_name': roomName,
        'sender_id': senderId,
        'sender_name': senderName,
        'file_name': fileName,
        'local_path': localPath,
        'file_size': fileSize,
        'mime_type': mimeType,
        'created_at': createdAt.toIso8601String(),
        'is_outgoing': isOutgoing ? 1 : 0,
      };

  factory SharedFile.fromMap(Map<String, dynamic> map) => SharedFile(
        fileId: map['file_id'] as String,
        roomId: map['room_id'] as String? ?? 'general',
        roomName: map['room_name'] as String? ?? 'General',
        senderId: map['sender_id'] as String? ?? '',
        senderName: map['sender_name'] as String? ?? 'Unknown',
        fileName: map['file_name'] as String? ?? 'file',
        localPath: map['local_path'] as String? ?? '',
        fileSize: (map['file_size'] as num?)?.toInt() ?? 0,
        mimeType: map['mime_type'] as String? ?? 'application/octet-stream',
        createdAt: DateTime.parse(map['created_at'] as String),
        isOutgoing: map['is_outgoing'] == 1 || map['is_outgoing'] == true,
      );
}
