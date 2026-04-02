import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/home_screen.dart';
import 'channels/p2p_channel.dart';
import 'providers/peer_provider.dart';

class MeshSocialApp extends StatefulWidget {
  const MeshSocialApp({super.key});

  @override
  State<MeshSocialApp> createState() => _MeshSocialAppState();
}

class _MeshSocialAppState extends State<MeshSocialApp> {
  @override
  void initState() {
    super.initState();
    // Set up the platform channel event handler
    P2PChannel.setEventHandler(_handleP2PEvent);
  }

  Future<dynamic> _handleP2PEvent(MethodCall call) async {
    switch (call.method) {
      case 'wifiP2PStateChanged':
        final bool enabled = call.arguments['enabled'];
        print('WiFi P2P enabled: $enabled');
        break;
        
      case 'discoveryStateChanged':
        final bool isDiscovering = call.arguments['isDiscovering'];
        context.read<PeerProvider>().setDiscoveryState(isDiscovering);
        break;
        
      case 'peersDiscovered':
        final List<dynamic> peersData = call.arguments['peers'];
        context.read<PeerProvider>().handlePeersDiscovered(
          peersData.map((p) => Map<String, dynamic>.from(p)).toList()
        );
        break;
        
      case 'connectionStateChanged':
        final bool isConnected = call.arguments['isConnected'];
        if (isConnected) {
          final bool isGroupOwner = call.arguments['isGroupOwner'];
          final String groupOwnerAddress = call.arguments['groupOwnerAddress'];
          print('Connected! IsGroupOwner: $isGroupOwner, GroupOwner: $groupOwnerAddress');
        } else {
          print('Disconnected');
        }
        break;
        
      case 'thisDeviceChanged':
        final String deviceName = call.arguments['deviceName'];
        final String deviceAddress = call.arguments['deviceAddress'];
        print('This device: $deviceName ($deviceAddress)');
        break;
        
      default:
        print('Unknown P2P event: ${call.method}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MeshSocial',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}