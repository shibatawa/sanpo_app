import 'package:flutter/material.dart';
import 'package:sanpo_app/main.dart'; // Walkモデルをインポート
import 'package:intl/intl.dart'; // 日付フォーマット用
import 'package:sanpo_app/walk_detail_page.dart'; // 詳細ページをインポート
import 'package:cloud_firestore/cloud_firestore.dart'; // Cloud Firestoreをインポート

class WalkHistoryPage extends StatefulWidget {
  const WalkHistoryPage({super.key});

  @override
  State<WalkHistoryPage> createState() => _WalkHistoryPageState();
}

class _WalkHistoryPageState extends State<WalkHistoryPage> {
  List<Walk> _walks = []; // 散歩記録のリスト
  bool _isLoading = true; // データロード中かどうか

  // Firestoreインスタンスを取得
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _loadWalks(); // 画面初期化時に記録をロード
  }

  // Firestoreから散歩記録をロードする関数
  Future<void> _loadWalks() async {
    setState(() {
      _isLoading = true; // ロード開始
    });
    try {
      // 'walks'コレクションからデータを取得し、startTimeで降順にソート
      // DatabaseHelperの代わりにFirestoreからデータを取得
      final querySnapshot = await _firestore.collection('walks')
          .orderBy('startTime', descending: true) // startTimeはDateTime型なのでorderBy可能
          .get();

      // 取得したドキュメントをWalkオブジェクトのリストに変換
      _walks = querySnapshot.docs.map((doc) {
        return Walk.fromFirestore(doc, null); // fromFirestoreファクトリを使用
      }).toList();

      setState(() {
        _isLoading = false; // ロード完了
      });
      print('Firestoreから散歩記録がロードされました: ${_walks.length}件');
    } catch (e) {
      print('Firestoreからの散歩記録のロードに失敗しました: $e');
      setState(() {
        _isLoading = false; // ロード完了
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('散歩記録履歴'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator()) // ロード中はローディング表示
          : _walks.isEmpty
              ? const Center(child: Text('まだ散歩記録がありません。')) // 記録がない場合
              : ListView.builder(
                  itemCount: _walks.length,
                  itemBuilder: (context, index) {
                    final walk = _walks[index];
                    // walk.startTimeは既にDateTime型なので、直接DateFormatに渡す
                    final formattedDate = DateFormat('yyyy/MM/dd HH:mm').format(walk.startTime); 

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                      elevation: 4.0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
                      child: InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => WalkDetailPage(walk: walk),
                            ),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '日付: $formattedDate',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 8),
                              Text('時間: ${walk.duration}', style: const TextStyle(fontSize: 14)),
                              Text('距離: ${walk.distance.toStringAsFixed(2)} m', style: const TextStyle(fontSize: 14)),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _loadWalks, // FABを押すと記録を再読み込み
        child: const Icon(Icons.refresh),
      ),
    );
  }
}
