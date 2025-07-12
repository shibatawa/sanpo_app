import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'package:geolocator/geolocator.dart'; // geolocatorパッケージをインポート
import 'package:flutter_map/flutter_map.dart'; // OpenStreetMap表示用
import 'package:latlong2/latlong.dart'; // 緯度経度座標用
import 'dart:async'; // For StreamSubscription
import 'dart:convert'; // JSONエンコード/デコード用 (routePointsの変換に必要)
import 'package:firebase_core/firebase_core.dart'; // Firebase Coreをインポート
import 'package:cloud_firestore/cloud_firestore.dart'; // Cloud Firestoreをインポート
import 'firebase_options.dart'; // flutterfire configure で生成されたファイルをインポート
import 'package:sanpo_app/walk_history_page.dart'; // 新しく作成する履歴ページをインポート



void main() async {
  // Flutterのウィジェットバインディングが初期化されていることを確認
  // Firebaseの初期化は非同期なので必須
  WidgetsFlutterBinding.ensureInitialized(); 

  // Firebaseを初期化
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '散歩記録アプリ',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const WalkHomePage(),
    );
  }
}

// 散歩記録のデータモデル (Firestore対応に調整)
class Walk {
  String? id; // FirestoreのドキュメントID
  DateTime startTime; // DateTime型で直接保持
  DateTime endTime;   // DateTime型で直接保持
  String duration;
  double distance;
  List<LatLng> routePoints; // LatLngのリストを直接保持 (Firestoreに保存する際はMapのリストに変換)

  Walk({
    this.id,
    required this.startTime,
    required this.endTime,
    required this.duration,
    required this.distance,
    required this.routePoints,
  });

  // FirestoreからMap<String, dynamic>を受け取り、Walkオブジェクトに変換するファクトリコンストラクタ
  factory Walk.fromFirestore(DocumentSnapshot<Map<String, dynamic>> snapshot, SnapshotOptions? options) {
    final data = snapshot.data();
    // FirestoreのTimestampをDateTimeに変換
    final startTime = (data?['startTime'] as Timestamp).toDate();
    final endTime = (data?['endTime'] as Timestamp).toDate();

    // Firestoreから取得したroutePointsをLatLngのリストに変換
    final List<dynamic>? routePointsData = data?['routePoints'];
    final List<LatLng> routePoints = routePointsData != null
        ? routePointsData.map((point) => LatLng(point['latitude'], point['longitude'])).toList()
        : [];

    return Walk(
      id: snapshot.id, // ドキュメントIDをidとして保持
      startTime: startTime,
      endTime: endTime,
      duration: data?['duration'] ?? '',
      distance: (data?['distance'] as num?)?.toDouble() ?? 0.0,
      routePoints: routePoints,
    );
  }

  // WalkオブジェクトをFirestoreに保存するためのMap<String, dynamic>に変換するメソッド
  Map<String, dynamic> toFirestore() {
    return {
      'startTime': Timestamp.fromDate(startTime), // DateTimeをFirestoreのTimestampに変換
      'endTime': Timestamp.fromDate(endTime),
      'duration': duration,
      'distance': distance,
      // LatLngのリストをFirestoreが保存できるMapのリストに変換
      'routePoints': routePoints.map((p) => {'latitude': p.latitude, 'longitude': p.longitude}).toList(),
    };
  }
}

// DatabaseHelperはFirestoreに移行するため削除します (このファイルからは完全に削除されています)


class WalkHomePage extends StatefulWidget {
  const WalkHomePage({super.key});

  @override
  State<WalkHomePage> createState() => _WalkHomePageState();
}

class _WalkHomePageState extends State<WalkHomePage> {
  String _currentStatus = "散歩を開始してください";
  Position? _currentPosition;
  final MapController _mapController = MapController();
  final List<LatLng> _routePoints = [];
  Marker? _currentLocationMarker;
  StreamSubscription<Position>? _positionStreamSubscription;
  
  bool _isWalking = false;
  final Stopwatch _stopwatch = Stopwatch();
  String _elapsedTime = '00:00:00';
  double _totalDistance = 0.0;
  Timer? _timer;

  // Firestoreインスタンスを取得
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _checkLocationPermission();
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    _timer?.cancel();
    // SQLiteのDatabaseHelper.instance.close(); は不要になったため削除済み
    super.dispose();
  }

  Future<void> _checkLocationPermission() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() {
        _currentStatus = "位置情報サービスが無効です。有効にしてください。";
      });
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() {
          _currentStatus = "位置情報パーミッションが拒否されました。";
        });
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      setState(() {
        _currentStatus = "位置情報パーミッションが永久に拒否されています。設定から変更してください。";
      });
      return;
    }

    _getCurrentLocation();
  }

  Future<void> _getCurrentLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      setState(() {
        _currentPosition = position;
        _currentStatus = "現在地を取得しました。";
        _updateCurrentLocationMarker(position);
      });
    } catch (e) {
      setState(() {
        _currentStatus = "現在地の取得に失敗しました: $e";
      });
      print('現在地の取得エラー: $e');
    }
  }

  void _moveMapToCurrentLocation(Position position) {
    _mapController.move(LatLng(position.latitude, position.longitude), 15.0);
  }

  void _updateCurrentLocationMarker(Position position) {
    _currentLocationMarker = Marker(
      width: 80.0,
      height: 80.0,
      point: LatLng(position.latitude, position.longitude),
      child: const Icon(
        Icons.location_on,
        color: Colors.blue,
        size: 40.0,
      ),
    );
  }

  void _startWalk() {
    if (_isWalking) return;

    setState(() {
      _isWalking = true;
      _currentStatus = "散歩中...";
      _routePoints.clear();
      _totalDistance = 0.0;
      _elapsedTime = '00:00:00';
      _currentLocationMarker = null;
    });
    print('散歩開始ボタンが押されました');

    _stopwatch.reset();
    _stopwatch.start();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _elapsedTime = _formatDuration(_stopwatch.elapsed);
      });
    });

    _positionStreamSubscription?.cancel();

    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen((Position position) {
      setState(() {
        if (_currentPosition != null) {
          _totalDistance += Geolocator.distanceBetween(
            _currentPosition!.latitude,
            _currentPosition!.longitude,
            position.latitude,
            position.longitude,
          );
        }
        _currentPosition = position;
        _routePoints.add(LatLng(position.latitude, position.longitude));
        _updateCurrentLocationMarker(position);
        _moveMapToCurrentLocation(position);
      });
      print('位置情報更新: ${position.latitude}, ${position.longitude}, 距離: ${_totalDistance.toStringAsFixed(2)}m');
    }, onError: (e) {
      setState(() {
        _currentStatus = "位置情報追跡エラー: $e";
      });
      print('位置情報追跡エラー: $e');
    });
  }

  void _stopWalk() async {
    if (!_isWalking) return;

    _positionStreamSubscription?.cancel();
    _stopwatch.stop();
    _timer?.cancel();

    setState(() {
      _isWalking = false;
      _currentStatus = "散歩を終了しました。時間: $_elapsedTime, 距離: ${_totalDistance.toStringAsFixed(2)}m";
    });
    print('散歩終了ボタンが押されました');

    final now = DateTime.now();
    final startTime = now.subtract(_stopwatch.elapsed);
    final endTime = now;

    // Firestoreに保存するためのWalkオブジェクトを作成
    final walk = Walk(
      startTime: startTime,
      endTime: endTime,
      duration: _elapsedTime,
      distance: _totalDistance,
      routePoints: _routePoints, // LatLngリストを直接渡す
    );

    try {
      // Firestoreの'walks'コレクションにデータを追加
      await _firestore.collection('walks').add(walk.toFirestore());
      print('散歩記録がFirestoreに保存されました！');
    } catch (e) {
      print('散歩記録のFirestoreへの保存に失敗しました: $e');
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
  }

  @override
  Widget build(BuildContext context) {
    final LatLng initialMapCenter = _currentPosition != null
        ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
        : const LatLng(35.681236, 139.767125); // 東京駅の座標

    return Scaffold(
      appBar: AppBar(
        title: const Text('散歩記録'),
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              _currentStatus,
              style: const TextStyle(fontSize: 20),
              textAlign: TextAlign.center,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Column(
                  children: [
                    const Text('時間', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    Text(_elapsedTime, style: const TextStyle(fontSize: 24, color: Colors.green)),
                  ],
                ),
                Column(
                  children: [
                    const Text('距離', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    Text('${_totalDistance.toStringAsFixed(2)} m', style: const TextStyle(fontSize: 24, color: Colors.orange)),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: _currentPosition == null && !_isWalking
                ? const Center(child: CircularProgressIndicator())
                : FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: initialMapCenter,
                      initialZoom: 15.0,
                      minZoom: 3.0,
                      maxZoom: 18.0,
                      keepAlive: true,
                      onMapReady: () {
                        if (_currentPosition != null) {
                          _moveMapToCurrentLocation(_currentPosition!);
                        }
                      },
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.example.my_walk_app',
                      ),
                      if (_currentLocationMarker != null)
                        MarkerLayer(
                          markers: [_currentLocationMarker!],
                        ),
                      if (_routePoints.isNotEmpty)
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: _routePoints,
                              strokeWidth: 4.0,
                              color: Colors.blue,
                            ),
                          ],
                        ),
                    ],
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                ElevatedButton(
                  onPressed: _isWalking ? null : _startWalk,
                  child: const Text('散歩開始'),
                ),
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: _isWalking ? _stopWalk : null,
                  child: const Text('散歩終了'),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const WalkHistoryPage()),
                    );
                  },
                  child: const Text('記録を見る'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
