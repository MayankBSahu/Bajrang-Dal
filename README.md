# MeshSocial

MeshSocial is an Android-first offline social app built with Flutter and native Kotlin networking.

It uses:
- Flutter for UI, local persistence, and app state
- Kotlin for Wi-Fi Direct discovery, connection management, and TCP gossip transport
- SQLite for identities, peers, rooms, and posts

## What It Does

MeshSocial lets nearby Android devices exchange posts without internet access.

Current features:
- Wi-Fi Direct peer discovery and connection
- TCP-based gossip sync over a Flutter `MethodChannel`
- delta sync instead of full database dumps
- password-protected rooms
- room-scoped feed UI
- local peer list with device search

## Architecture

Flutter side:
- UI screens in `lib/screens`
- providers in `lib/providers`
- local database in `lib/db/database_helper.dart`
- native event handling in `lib/controllers/gossip_controller.dart`

Android side:
- `P2PManager.kt` handles Wi-Fi Direct lifecycle and gossip transport orchestration
- `SocketServer.kt` manages the TCP transport
- `GossipEngine.kt` builds and parses protocol envelopes
- `MainActivity.kt` exposes native features over `MethodChannel('meshsocial/p2p')`

## Gossip Protocol

The app uses a two-way delta sync:

1. Device A sends `HELLO` with only post IDs.
2. Device B compares those IDs against its local database.
3. Device B responds with `SYNC`:
   - posts A is missing
   - request IDs for posts B is missing
4. A sends a second `SYNC` to fulfill those requested posts.

This keeps transfers smaller than bulk database sync.

## Rooms

Rooms are first-class app data and posts belong to a room.

Current room behavior:
- `General` is created automatically as the default room
- users can create rooms
- rooms can be marked locked with a password
- users can join an existing room by room name and password
- the feed only shows posts for the active room

Important limitation:
- room passwords are currently an app-level access check, not end-to-end encryption
- synced posts carry `room_id` and `room_name`, but room passwords are not used as cryptographic protection

## UI

Main tabs:
- Feed
- Nearby
- Profile

Feed:
- active room header
- room switching chips
- create room / join room actions
- improved post cards
- composer scoped to the active room

Nearby:
- Wi-Fi Direct scan / stop scan
- device search
- connect / disconnect
- debug ping and mesh debug state

## Database

SQLite tables currently include:
- `identity`
- `posts`
- `peers`
- `rooms`

Posts now store:
- `post_id`
- `room_id`
- `room_name`
- `author_id`
- `author_name`
- `content`
- `created_at`
- `hop_count`
- `synced`

## Running The App

Requirements:
- Flutter SDK
- Android SDK / Android Studio
- physical Android devices for Wi-Fi Direct testing

Run:

```bash
flutter pub get
flutter run
```

## Testing Notes

For real device testing:
- install the app on two Android phones
- open `Nearby`
- start Wi-Fi scan on both phones
- connect one device to the other
- create or join the same room
- post in the room and verify sync

## Current Limitations

- Android-only networking path
- Wi-Fi Direct still relies on the group-owner model underneath
- room passwords are not encrypted transport/security boundaries
- build/analyzer verification has not been fully rerun after the latest room changes

## Key Files

- `lib/screens/feed_screen.dart`
- `lib/screens/nearby_screen.dart`
- `lib/providers/feed_provider.dart`
- `lib/providers/room_provider.dart`
- `lib/controllers/gossip_controller.dart`
- `lib/db/database_helper.dart`
- `android/app/src/main/kotlin/com/example/meshsocial/P2PManager.kt`
- `android/app/src/main/kotlin/com/example/meshsocial/SocketServer.kt`
- `android/app/src/main/kotlin/com/example/meshsocial/GossipEngine.kt`
