import 'package:flutter/material.dart';
import 'package:sanpo_app/main.dart'; // WalkとDatabaseHelperをインポート
import 'package:intl/intl.dart'; // 日付フォーマット用 (pubspec.yamlに追加が必要)

// pubspec.yamlに intl パッケージを追加してください:
// dependencies:
//   intl: ^0.19.0

class WalkHistoryPage extends StatefulWidget {
  const WalkHistoryPage({super.key});

  @override
  State<WalkHistoryPage> createState() => _WalkHistoryPageState();
}

class _WalkHistoryPageState extends State<WalkHistoryPage> {
  List<Walk> _walks = []; // 散歩記録のリスト
  bool _isLoading = true; // データロード中かどうか

  @override
  void initState() {
    super.initState();
    _loadWalks(); // 画面初期化時に記録をロード
  }

  // データベースから散歩記録をロードする関数
  Future<void> _loadWalks() async {
    setState(() {
      _isLoading = true; // ロード開始
    });
    try {
      final loadedWalks = await DatabaseHelper.instance.getWalks();
      setState(() {
        _walks = loadedWalks;
        _isLoading = false; // ロード完了
      });
      print('散歩記録がロードされました: ${_walks.length}件');
    } catch (e) {
      print('散歩記録のロードに失敗しました: $e');
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
        // 履歴ページに戻ってきたときにリストを再読み込みするために、戻るボタンが押されたらリロード
        // Navigator.pop() が呼ばれた後に _loadWalks() を呼び出す
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pop(context);
            // ここでホーム画面に戻った後に、必要であればホーム画面のデータを更新する処理をトリガーすることも可能
          },
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator()) // ロード中はローディング表示
          : _walks.isEmpty
              ? const Center(child: Text('まだ散歩記録がありません。')) // 記録がない場合
              : ListView.builder(
                  itemCount: _walks.length,
                  itemBuilder: (context, index) {
                    final walk = _walks[index];
                    // 日付を整形して表示
                    final startTime = DateTime.parse(walk.startTime);
                    final formattedDate = DateFormat('yyyy/MM/dd HH:mm').format(startTime);

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                      elevation: 4.0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
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
                            // TODO: 将来的にこの記録の詳細（地図上のルートなど）を表示するボタンを追加
                          ],
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
