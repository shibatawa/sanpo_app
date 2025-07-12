import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'package:geolocator/geolocator.dart'; // geolocatorパッケージをインポート
import 'package:flutter_map/flutter_map.dart'; // OpenStreetMap表示用
import 'package:latlong2/latlong.dart'; // 緯度経度座標用
import 'dart:async'; // For StreamSubscription
import 'package:sqflite/sqflite.dart'; // sqfliteパッケージをインポート
import 'package:path_provider/path_provider.dart'; // path_providerパッケージをインポート
import 'dart:convert'; // JSONエンコード/デコード用
import 'package:sanpo_app/walk_history_page.dart'; // 新しく作成する履歴ページをインポート


import 'package:device_preview/device_preview.dart';

void main() => runApp(
  DevicePreview(
    enabled: !kReleaseMode,
    builder: (context) => MyApp(), // Wrap your app
  ),
);


//============================

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

// 散歩記録のデータモデル (変更なし)
class Walk {
  int? id;
  String startTime;
  String endTime;
  String duration;
  double distance;
  String routePointsJson;

  Walk({
    this.id,
    required this.startTime,
    required this.endTime,
    required this.duration,
    required this.distance,
    required this.routePointsJson,
  });

  factory Walk.fromMap(Map<String, dynamic> map) {
    return Walk(
      id: map['id'],
      startTime: map['startTime'],
      endTime: map['endTime'],
      duration: map['duration'],
      distance: map['distance'],
      routePointsJson: map['routePointsJson'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'startTime': startTime,
      'endTime': endTime,
      'duration': duration,
      'distance': distance,
      'routePointsJson': routePointsJson,
    };
  }
}

// データベース操作を管理するヘルパークラス (変更なし)
class DatabaseHelper {
  static Database? _database;
  static const String tableName = 'walks';

  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();
  DatabaseHelper._privateConstructor();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final path = '${documentsDirectory.path}/walks.db';

    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $tableName (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        startTime TEXT NOT NULL,
        endTime TEXT NOT NULL,
        duration TEXT NOT NULL,
        distance REAL NOT NULL,
        routePointsJson TEXT NOT NULL
      )
    ''');
  }

  Future<int> insertWalk(Walk walk) async {
    final db = await instance.database;
    return await db.insert(tableName, walk.toMap());
  }

  Future<List<Walk>> getWalks() async {
    final db = await instance.database;
    final List<Map<String, dynamic>> maps = await db.query(tableName, orderBy: 'startTime DESC');
    return List.generate(maps.length, (i) {
      return Walk.fromMap(maps[i]);
    });
  }

  Future<void> close() async {
    final db = await instance.database;
    db.close();
  }
}


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

  @override
  void initState() {
    super.initState();
    _checkLocationPermission();
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    _timer?.cancel();
    DatabaseHelper.instance.close();
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

    final routePointsJson = jsonEncode(_routePoints.map((p) => {'latitude': p.latitude, 'longitude': p.longitude}).toList());

    final walk = Walk(
      startTime: startTime.toIso8601String(),
      endTime: endTime.toIso8601String(),
      duration: _elapsedTime,
      distance: _totalDistance,
      routePointsJson: routePointsJson,
    );

    try {
      await DatabaseHelper.instance.insertWalk(walk);
      print('散歩記録が保存されました！');
    } catch (e) {
      print('散歩記録の保存に失敗しました: $e');
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
        : const LatLng(35.681236, 139.767125);

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
                const SizedBox(height: 20), // 新しいボタンとの間隔
                ElevatedButton( // 新しく追加するボタン
                  onPressed: () {
                    // 記録履歴ページへ遷移
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
