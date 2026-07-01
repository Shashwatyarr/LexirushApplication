import 'dart:convert';
import '../../../core/network/api_client.dart';

class LeaderboardService {
  // GET LEADERBOARD
  Future<List<dynamic>> getLeaderboard() async {
    final response = await ApiClient.get('/leaderboard');

    if (response.statusCode == 200) {
      return jsonDecode(response.body)['leaderboard'] ?? [];
    } else {
      throw Exception(jsonDecode(response.body)['message'] ?? 'Failed to fetch leaderboard');
    }
  }
}
