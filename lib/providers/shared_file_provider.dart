import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../db/database_helper.dart';
import '../models/shared_file.dart';

class SharedFileProvider extends ChangeNotifier {
  List<SharedFile> _files = [];
  List<SharedFile> get files => _files;

  String _activeRoomId = 'general';

  Future<void> loadFiles({String? roomId}) async {
    _activeRoomId = roomId ?? _activeRoomId;
    _files = await DatabaseHelper.instance.getFilesForRoom(_activeRoomId);
    notifyListeners();
  }

  Future<SharedFile> addOutgoingFile({
    required String roomId,
    required String roomName,
    required String senderId,
    required String senderName,
    required String sourcePath,
    required String fileName,
    required int fileSize,
    required String mimeType,
  }) async {
    final file = SharedFile(
      fileId: const Uuid().v4(),
      roomId: roomId,
      roomName: roomName,
      senderId: senderId,
      senderName: senderName,
      fileName: fileName,
      localPath: sourcePath,
      fileSize: fileSize,
      mimeType: mimeType,
      createdAt: DateTime.now(),
      isOutgoing: true,
    );
    await DatabaseHelper.instance.insertSharedFile(file);
    if (_activeRoomId == roomId) {
      _files.insert(0, file);
      notifyListeners();
    }
    return file;
  }

  Future<void> saveIncomingFile({
    required String fileId,
    required String roomId,
    required String roomName,
    required String senderId,
    required String senderName,
    required String fileName,
    required int fileSize,
    required String mimeType,
    required String base64Data,
    required DateTime createdAt,
  }) async {
    final dir = await getApplicationDocumentsDirectory();
    final filesDir = Directory(p.join(dir.path, 'shared_files', roomId));
    await filesDir.create(recursive: true);
    final safeName = fileName.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    final localPath = p.join(filesDir.path, '${fileId}_$safeName');
    await File(localPath).writeAsBytes(base64Decode(base64Data), flush: true);

    final file = SharedFile(
      fileId: fileId,
      roomId: roomId,
      roomName: roomName,
      senderId: senderId,
      senderName: senderName,
      fileName: fileName,
      localPath: localPath,
      fileSize: fileSize,
      mimeType: mimeType,
      createdAt: createdAt,
      isOutgoing: false,
    );
    await DatabaseHelper.instance.insertSharedFile(file);
    await loadFiles(roomId: _activeRoomId);
  }
}
