import 'package:flutter/material.dart';
import '../../l10n/tr.dart';

class LeaderboardScreen extends StatelessWidget {
  const LeaderboardScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('المتصدرون', 'Leaderboard')),
      ),
      body: ListView.builder(
        itemCount: 10, // Replace with actual data
        itemBuilder: (context, index) {
          return ListTile(
            leading: CircleAvatar(
              child: Text('${index + 1}'),
            ),
            title: Text(tr('لاعب ${index + 1}', 'Player ${index + 1}')),
            trailing: Text('${(10 - index) * 1000} XP'),
          );
        },
      ),
    );
  }
}
