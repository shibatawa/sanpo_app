import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:convert'; // JSONデコード用
import 'package:sanpo_app/main.dart'; // Walkモデルをインポート

class WalkDetailPage extends StatefulWidget {
  final Walk walk; // 表示する散歩記録データ

  const WalkDetailPage({super.key, required this.walk});

  @override
  State<WalkDetailPage> createState() => _WalkDetailPageState();
}

class _WalkDetailPageState extends State<WalkDetailPage> {
  final MapController _mapController = MapController();
  List<LatLng> _decodedRoutePoints = []; // デコードされたルート座標
  Marker? _startMarker; // 開始地点マーカー
  Marker? _endMarker; // 終了地点マーカー

  @override
  void initState() {
    super.initState();
    _decodeRoutePoints(); // ルート座標をデコード
    _setMarkers(); // マーカーを設定
  }

  // JSON文字列からルート座標をデコードする関数
  void _decodeRoutePoints() {
    try {
      final List<dynamic> jsonList = jsonDecode(widget.walk.routePointsJson);
      _decodedRoutePoints = jsonList.map((map) {
        return LatLng(map['latitude'], map['longitude']);
      }).toList();
      print('ルート座標がデコードされました: ${_decodedRoutePoints.length}点');
    } catch (e) {
      print('ルート座標のデコードに失敗しました: $e');
      _decodedRoutePoints = []; // 失敗した場合は空リスト
    }
  }

  // 開始地点と終了地点にマーカーを設定する関数
  void _setMarkers() {
    if (_decodedRoutePoints.isNotEmpty) {
      final startPoint = _decodedRoutePoints.first;
      final endPoint = _decodedRoutePoints.last;

      _startMarker = Marker(
        width: 80.0,
        height: 80.0,
        point: startPoint,
        child: const Icon(
          Icons.flag, // 開始地点のアイコン
          color: Colors.green,
          size: 40.0,
        ),
      );

      _endMarker = Marker(
        width: 80.0,
        height: 80.0,
        point: endPoint,
        child: const Icon(
          Icons.check_box, // 終了地点のアイコン
          color: Colors.red,
          size: 40.0,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // マップの中心座標をルートの中央または開始地点に設定
    LatLng initialMapCenter;
    double initialZoom = 15.0;

    if (_decodedRoutePoints.isNotEmpty) {
      // ルートがある場合はその中心に設定
      double minLat = _decodedRoutePoints.map((p) => p.latitude).reduce(min);
      double maxLat = _decodedRoutePoints.map((p) => p.latitude).reduce(max);
      double minLon = _decodedRoutePoints.map((p) => p.longitude).reduce(min);
      double maxLon = _decodedRoutePoints.map((p) => p.longitude).reduce(max);

      initialMapCenter = LatLng((minLat + maxLat) / 2, (minLon + maxLon) / 2);

      // ルートの範囲に合わせてズームレベルを調整することも可能ですが、今回は固定
      // 例: LatLngBounds bounds = LatLngBounds(LatLng(minLat, minLon), LatLng(maxLat, maxLon));
      //     _mapController.fitBounds(bounds, options: FitBoundsOptions(padding: EdgeInsets.all(50.0)));
    } else {
      // ルートがない場合はデフォルト（東京駅）
      initialMapCenter = const LatLng(35.681236, 139.767125);
      initialZoom = 10.0; // 広い範囲を表示
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('散歩詳細'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '開始時間: ${DateFormat('yyyy/MM/dd HH:mm:ss').format(DateTime.parse(widget.walk.startTime))}',
                  style: const TextStyle(fontSize: 16),
                ),
                Text(
                  '終了時間: ${DateFormat('yyyy/MM/dd HH:mm:ss').format(DateTime.parse(widget.walk.endTime))}',
                  style: const TextStyle(fontSize: 16),
                ),
                Text(
                  '経過時間: ${widget.walk.duration}',
                  style: const TextStyle(fontSize: 16),
                ),
                Text(
                  '距離: ${widget.walk.distance.toStringAsFixed(2)} m',
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 10),
                const Text('散歩ルート:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: initialMapCenter,
                initialZoom: initialZoom,
                minZoom: 3.0,
                maxZoom: 18.0,
                keepAlive: true,
                onMapReady: () {
                  // マップが準備できたら、ルート全体が表示されるように調整することも可能
                  if (_decodedRoutePoints.isNotEmpty) {
                    // ルート全体が画面に収まるようにズームと中心を調整
                    final bounds = LatLngBounds.fromPoints(_decodedRoutePoints);
                    _mapController.fitBounds(
                      bounds,
                      options: const FitBoundsOptions(
                        padding: EdgeInsets.all(50.0), // 地図の余白
                      ),
                    );
                  }
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.my_walk_app',
                ),
                // ルートのポリライン
                if (_decodedRoutePoints.isNotEmpty)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _decodedRoutePoints,
                        strokeWidth: 5.0,
                        color: Colors.blueAccent,
                      ),
                    ],
                  ),
                // 開始地点と終了地点のマーカー
                MarkerLayer(
                  markers: [
                    if (_startMarker != null) _startMarker!,
                    if (_endMarker != null) _endMarker!,
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// min, max 関数はdart:mathにあります
import 'dart:math';
