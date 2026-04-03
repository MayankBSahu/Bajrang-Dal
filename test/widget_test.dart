import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:meshsocial/app.dart';
import 'package:meshsocial/providers/feed_provider.dart';
import 'package:meshsocial/providers/identity_provider.dart';
import 'package:meshsocial/providers/mesh_debug_provider.dart';
import 'package:meshsocial/providers/peer_provider.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('App loads feed tab', (WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => IdentityProvider()..load()),
          ChangeNotifierProvider(create: (_) => FeedProvider()..loadPosts()),
          ChangeNotifierProvider(create: (_) => MeshDebugProvider()),
          ChangeNotifierProvider(create: (_) => PeerProvider()..loadPeers()),
        ],
        child: const MeshSocialApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('MeshSocial'), findsWidgets);
  });
}
