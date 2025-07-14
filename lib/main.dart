import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:async';
import 'dart:convert'; // JSONエンコード/デコード用
import 'package:firebase_core/firebase_core.dart'; // Firebase Coreをインポート
import 'package:cloud_firestore/cloud_firestore.dart'; // Cloud Firestoreをインポート
import 'firebase_options.dart'; // flutterfire configure で生成されたファイルをインポート
import 'package:sanpo_app/walk_history_page.dart'; // 履歴ページをインポート

void main() async {
  // Flutterのウィジェットバインディングが初期化されていることを確認
  // Firebaseの初期化は非同期なので、この行は必須です。
  WidgetsFlutterBinding.ensureInitialized(); 

  // Firebaseを初期化します。
  // flutterfire configure コマンドで生成された firebase_options.dart ファイルの
  // DefaultFirebaseOptions.currentPlatform を使用します。
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
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF222222),
          brightness: Brightness.light,
        ),
        fontFamily: 'Hiragino Sans',
        textTheme: TextTheme(
          headlineLarge: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          headlineMedium: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w500,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          headlineSmall: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w500,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          bodyLarge: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w400,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          bodyMedium: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          labelLarge: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 2,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
        ),
        appBarTheme: const AppBarTheme(
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
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
  double estimatedCalories; // 推定消費カロリー

  Walk({
    this.id,
    required this.startTime,
    required this.endTime,
    required this.duration,
    required this.distance,
    required this.routePoints,
    this.estimatedCalories = 0.0,
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
      estimatedCalories: (data?['estimatedCalories'] as num?)?.toDouble() ?? 0.0,
    );
  }

  // WalkオブジェクトをFirestoreに保存するためのMap<String, dynamic>に変換するメソッド
  Map<String, dynamic> toFirestore() {
    return {
      'startTime': Timestamp.fromDate(startTime), // DateTimeをFirestoreのTimestampに変換
      'endTime': Timestamp.fromDate(endTime),
      'duration': duration,
      'distance': distance,
      'estimatedCalories': estimatedCalories,
      // LatLngのリストをFirestoreが保存できるMapのリストに変換
      'routePoints': routePoints.map((p) => {'latitude': p.latitude, 'longitude': p.longitude}).toList(),
    };
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
  
  // 統計情報用の変数
  double _currentSpeed = 0.0; // 現在の速度 (m/s)
  double _maxSpeed = 0.0; // 最大速度 (m/s)
  double _averageSpeed = 0.0; // 平均速度 (m/s)
  double _estimatedCalories = 0.0; // 推定消費カロリー (kcal)
  DateTime? _lastPositionUpdateTime; // 最後の位置更新時刻
  Position? _lastPosition; // 最後の位置

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
      width: 40.0,
      height: 40.0,
      point: LatLng(position.latitude, position.longitude),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary,
          shape: BoxShape.circle,
          border: Border.all(
            color: Theme.of(context).colorScheme.onPrimary,
            width: 2,
          ),
        ),
        child: Icon(
          Icons.person,
          color: Theme.of(context).colorScheme.onPrimary,
          size: 20.0,
        ),
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
      // 現在地マーカーはnullにしない（地図が消える原因）
      _resetStatistics(); // 統計情報をリセット
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
        _updateStatistics(position); // 統計情報を更新
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
      _currentStatus = "散歩を終了しました。\n"
          "時間: $_elapsedTime, 距離: ${_totalDistance.toStringAsFixed(2)}m\n"
          "平均速度: ${(_averageSpeed * 3.6).toStringAsFixed(1)} km/h, "
          "最大速度: ${(_maxSpeed * 3.6).toStringAsFixed(1)} km/h\n"
          "消費カロリー: ${_estimatedCalories.toStringAsFixed(1)} kcal";
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
      estimatedCalories: _estimatedCalories,
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

  // 統計情報を計算・更新するメソッド
  void _updateStatistics(Position newPosition) {
    final now = DateTime.now();
    
    if (_lastPosition != null && _lastPositionUpdateTime != null) {
      // 距離の計算
      final distance = Geolocator.distanceBetween(
        _lastPosition!.latitude,
        _lastPosition!.longitude,
        newPosition.latitude,
        newPosition.longitude,
      );
      
      // 時間の計算 (秒)
      final timeDiff = now.difference(_lastPositionUpdateTime!).inMilliseconds / 1000.0;
      
      if (timeDiff > 0) {
        // 現在の速度を計算 (m/s)
        _currentSpeed = distance / timeDiff;
        
        // 最大速度を更新
        if (_currentSpeed > _maxSpeed) {
          _maxSpeed = _currentSpeed;
        }
        
        // 平均速度を計算 (総距離 / 総時間)
        final totalTimeInSeconds = _stopwatch.elapsed.inSeconds;
        if (totalTimeInSeconds > 0) {
          _averageSpeed = _totalDistance / totalTimeInSeconds;
        }
        
        // 消費カロリーを推定 (簡易計算: 体重60kg, 歩行速度に基づく)
        // 歩行: 約3.5 METs, 走行: 約8 METs
        final walkingSpeed = _averageSpeed * 3.6; // m/s to km/h
        final mets = walkingSpeed < 6.0 ? 3.5 : 8.0; // 6km/h以下は歩行、以上は走行
        _estimatedCalories = (mets * 60.0 * (totalTimeInSeconds / 3600.0)); // 体重60kg想定
      }
    }
    
    _lastPosition = newPosition;
    _lastPositionUpdateTime = now;
  }

  // 統計情報をリセットするメソッド
  void _resetStatistics() {
    _currentSpeed = 0.0;
    _maxSpeed = 0.0;
    _averageSpeed = 0.0;
    _estimatedCalories = 0.0;
    _lastPositionUpdateTime = null;
    _lastPosition = null;
  }

  // 統計情報カード作成ヘルパーメソッド
  Widget _buildStatCard(BuildContext context, IconData icon, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(color: color.withOpacity(0.3), width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
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
      body: SingleChildScrollView(
        child: Column(
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
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
            child: Row(
              children: [
                Expanded(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.timer, size: 20, color: Theme.of(context).colorScheme.primary),
                              const SizedBox(width: 8),
                              Text(
                                '時間',
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _elapsedTime,
                            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.straighten, size: 20, color: Theme.of(context).colorScheme.primary),
                              const SizedBox(width: 8),
                              Text(
                                '距離',
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${_totalDistance.toStringAsFixed(0)} m',
                            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 統計情報表示エリア
          if (_isWalking)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.analytics, size: 24, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 8),
                          Text(
                            'リアルタイム統計',
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          if (constraints.maxWidth < 400) {
                            // 小さな画面では縦に配置
                            return Column(
                              children: [
                                _buildStatCard(
                                  context,
                                  Icons.speed,
                                  '現在速度',
                                  '${(_currentSpeed * 3.6).toStringAsFixed(1)} km/h',
                                  Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(height: 8),
                                _buildStatCard(
                                  context,
                                  Icons.trending_up,
                                  '平均速度',
                                  '${(_averageSpeed * 3.6).toStringAsFixed(1)} km/h',
                                  Theme.of(context).colorScheme.secondary,
                                ),
                                const SizedBox(height: 8),
                                _buildStatCard(
                                  context,
                                  Icons.flash_on,
                                  '最大速度',
                                  '${(_maxSpeed * 3.6).toStringAsFixed(1)} km/h',
                                  Theme.of(context).colorScheme.tertiary,
                                ),
                              ],
                            );
                          } else {
                            // 大きな画面では横に配置
                            return Row(
                              children: [
                                Expanded(
                                  child: _buildStatCard(
                                    context,
                                    Icons.speed,
                                    '現在速度',
                                    '${(_currentSpeed * 3.6).toStringAsFixed(1)} km/h',
                                    Theme.of(context).colorScheme.primary,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _buildStatCard(
                                    context,
                                    Icons.trending_up,
                                    '平均速度',
                                    '${(_averageSpeed * 3.6).toStringAsFixed(1)} km/h',
                                    Theme.of(context).colorScheme.secondary,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _buildStatCard(
                                    context,
                                    Icons.flash_on,
                                    '最大速度',
                                    '${(_maxSpeed * 3.6).toStringAsFixed(1)} km/h',
                                    Theme.of(context).colorScheme.tertiary,
                                  ),
                                ),
                              ],
                            );
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      Center(
                        child: _buildStatCard(
                          context,
                          Icons.local_fire_department,
                          '消費カロリー',
                          '${_estimatedCalories.toStringAsFixed(1)} kcal',
                          Theme.of(context).colorScheme.secondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Container(
            height: 400, // 地図の高さを固定
            child: _currentPosition == null
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
                              strokeWidth: 5.0,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ],
                        ),
                    ],
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: _isWalking ? null : _startWalk,
                    icon: const Icon(Icons.play_arrow, size: 24),
                    label: const Text('散歩開始'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isWalking 
                          ? Theme.of(context).colorScheme.surface
                          : Theme.of(context).colorScheme.primary,
                      foregroundColor: _isWalking
                          ? Theme.of(context).colorScheme.onSurface
                          : Theme.of(context).colorScheme.onPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: _isWalking ? _stopWalk : null,
                    icon: const Icon(Icons.stop, size: 24),
                    label: const Text('散歩終了'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isWalking 
                          ? Theme.of(context).colorScheme.error
                          : Theme.of(context).colorScheme.surface,
                      foregroundColor: _isWalking
                          ? Theme.of(context).colorScheme.onError
                          : Theme.of(context).colorScheme.onSurface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        PageRouteBuilder(
                          pageBuilder: (context, animation, secondaryAnimation) => const WalkHistoryPage(),
                          transitionsBuilder: (context, animation, secondaryAnimation, child) {
                            const begin = Offset(1.0, 0.0);
                            const end = Offset.zero;
                            const curve = Curves.ease;

                            var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));

                            return SlideTransition(
                              position: animation.drive(tween),
                              child: child,
                            );
                          },
                        ),
                      );
                    },
                    icon: const Icon(Icons.history, size: 24),
                    label: const Text('記録を見る'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.primary,
                      side: BorderSide(
                        color: Theme.of(context).colorScheme.outline,
                        width: 1,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        ),
      ),
    );
  }
}
