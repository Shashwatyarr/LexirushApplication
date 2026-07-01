import 'dart:convert';
import '../../../core/network/api_client.dart';

class UserService {
  // GET AVATARS
  Future<Map<String, dynamic>> getAvatars() async {
    final response = await ApiClient.get('/user/avatars');

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception(jsonDecode(response.body)['message'] ?? 'Failed to load avatars');
    }
  }

  // CHANGE AVATAR
  Future<Map<String, dynamic>> changeAvatar(String avatarUrl, String avatarName) async {
    final response = await ApiClient.put(
      '/user/avatar',
      body: {'avatar': avatarUrl, 'avatarName': avatarName},
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception(jsonDecode(response.body)['message'] ?? 'Failed to change avatar');
    }
  }
}
