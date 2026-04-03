<div align="center">

# MeshSocial

**An Android-first offline social app that syncs room-based posts over Wi-Fi Direct using a lightweight gossip protocol.**

[![Flutter](https://img.shields.io/badge/Flutter-UI%20Layer-02569B?logo=flutter&logoColor=white)](https://flutter.dev/)
[![Dart](https://img.shields.io/badge/Dart-3.11%2B-0175C2?logo=dart&logoColor=white)](https://dart.dev/)
[![Kotlin](https://img.shields.io/badge/Kotlin-Native%20P2P-7F52FF?logo=kotlin&logoColor=white)](https://kotlinlang.org/)
[![Android](https://img.shields.io/badge/Android-Wi--Fi%20Direct-3DDC84?logo=android&logoColor=white)](https://developer.android.com/)
[![SQLite](https://img.shields.io/badge/SQLite-Local%20Storage-003B57?logo=sqlite&logoColor=white)](https://www.sqlite.org/index.html)

</div>

---

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Architecture](#architecture)
- [Project Structure](#project-structure)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Permissions](#permissions)
- [Usage](#usage)
- [Gossip Sync Flow](#gossip-sync-flow)
- [Data Model](#data-model)
- [Current Limitations](#current-limitations)
- [Contributing](#contributing)

---

## Overview

MeshSocial enables nearby Android devices to share posts without internet connectivity.

The app combines:
- Flutter for UI, local state management, and app-level persistence
- Native Kotlin for Wi-Fi Direct discovery, P2P session management, and TCP transport
- SQLite for offline-first storage of identities, peers, rooms, and posts

The result is a practical local mesh-style social experience where users can discover peers, connect, create/join rooms, and gossip-sync room posts across devices.

---

## Features

| Category | Details |
|---|---|
| **Offline Messaging** | Exchange posts over local Wi-Fi Direct without internet |
| **Room-Based Feeds** | Create rooms, join rooms, and scope posts to the active room |
| **Locked Rooms** | Optional room password check for controlled access |
| **Peer Discovery** | Scan nearby devices and connect/disconnect from the Nearby screen |
| **Delta Gossip Sync** | Sync only missing posts instead of full database dumps |
| **Native Bridge** | Flutter <-> Kotlin integration via MethodChannel (`meshsocial/p2p`) |
| **Local Persistence** | SQLite-backed storage for identity, rooms, posts, and peers |
| **Debug Tooling** | Debug ping + mesh status indicators to validate transport state |

---

## Architecture

### Flutter Layer

- UI screens in `lib/screens/`
- State providers in `lib/providers/`
- SQLite helper in `lib/db/database_helper.dart`
- Native event handling in `lib/controllers/gossip_controller.dart`

### Android Native Layer

- `P2PManager.kt`: Wi-Fi Direct lifecycle + orchestration
- `SocketServer.kt`: TCP socket transport and session handling
- `GossipEngine.kt`: protocol envelope building/parsing
- `MainActivity.kt`: bridge exposure over MethodChannel

---

## Project Structure

```text
Bajrang-Dal/
|- README.md
|- pubspec.yaml
|- lib/
|  |- main.dart
|  |- app.dart
|  |- channels/
|  |  |- p2p_channel.dart
|  |- controllers/
|  |  |- gossip_controller.dart
|  |- db/
|  |  |- database_helper.dart
|  |- models/
|  |  |- identity.dart
|  |  |- peer.dart
|  |  |- post.dart
|  |  |- room.dart
|  |- providers/
|  |  |- feed_provider.dart
|  |  |- identity_provider.dart
|  |  |- mesh_debug_provider.dart
|  |  |- peer_provider.dart
|  |  |- room_provider.dart
|  |- screens/
|     |- feed_screen.dart
|     |- nearby_screen.dart
|     |- profile_screen.dart
|     |- home_screen.dart
|- android/app/src/main/kotlin/com/example/meshsocial/
|  |- MainActivity.kt
|  |- P2PManager.kt
|  |- SocketServer.kt
|  |- GossipEngine.kt
|- ios/
|- macos/
|- linux/
|- windows/
|- web/
`- test/
```

---

## Prerequisites

- Flutter SDK (compatible with Dart 3.11+ as defined in `pubspec.yaml`)
- Android Studio + Android SDK
- At least 2 physical Android devices for realistic P2P validation

---

## Installation

1. Clone the repository

   ```bash
   git clone https://github.com/MayankBSahu/Bajrang-Dal.git
   cd Bajrang-Dal
   ```

2. Install dependencies

   ```bash
   flutter pub get
   ```

3. Run on a connected Android device

   ```bash
   flutter run
   ```

---

## Permissions

For Wi-Fi Direct discovery on Android, runtime permissions are required:

- Android 12 and below: location permission
- Android 13 and above: nearby Wi-Fi devices permission

The app requests these when scanning starts from the Nearby screen.

---

## Usage

1. Launch the app on two Android devices.
2. Open Nearby on both devices.
3. Start scan and connect one device to the other.
4. Create or join the same room.
5. Post in Feed and verify that the second device receives updates via gossip sync.

### Main Screens

- **Feed**: active room, room switching, compose post, sync status card
- **Nearby**: scan/stop, peer search, connect/disconnect, debug ping
- **Profile**: device identity and local post summary

---

## Gossip Sync Flow

```text
Device A                           Device B
--------                           --------
HELLO(post_ids) --------------->   Compare with local DB
                                   Build delta response
SYNC(missing_posts, request_ids) <---------------
SYNC(requested_posts) ---------->
                                   Apply new posts to room-scoped feed
```

Why this approach:
- reduces transfer size compared to full DB exchange
- improves sync speed on unstable or low-throughput local links

---

## Data Model

### SQLite Tables

- `identity`
- `posts`
- `peers`
- `rooms`

### Post Entity (Core Fields)

- `post_id`
- `room_id`
- `room_name`
- `author_id`
- `author_name`
- `content`
- `created_at`
- `hop_count`
- `synced`

---

## Current Limitations

- Native networking path is Android-focused for this build
- Wi-Fi Direct behavior depends on group-owner mechanics underneath
- Room password is an app-level access check, not end-to-end encryption
- iOS/macOS/web targets exist as Flutter scaffolding but are not the primary P2P target

---

## Contributing

Contributions are welcome. For meaningful PRs:

1. Keep Flutter and Kotlin changes isolated by layer when possible.
2. Preserve gossip protocol compatibility when modifying payload schema.
3. Test with at least two real Android devices before submitting.

---

<div align="center">

Built with Flutter + Kotlin for offline-first mesh social communication.

</div>
