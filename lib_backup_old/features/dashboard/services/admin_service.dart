import 'dart:convert';
import '../../../core/network/api_client.dart';

class AdminService {
  // GET ALL ROOMS
  Future<List<dynamic>> getAllRooms() async {
    final response = await ApiClient.get('/admin/rooms');

    if (response.statusCode == 200) {
      return jsonDecode(response.body)['rooms'] ?? [];
    } else {
      throw Exception(jsonDecode(response.body)['message'] ?? 'Failed to fetch rooms');
    }
  }

  // CREATE ROOM
  Future<Map<String, dynamic>> createRoomAdmin() async {
    final response = await ApiClient.post('/admin/create-room');

    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body);
    } else {
      throw Exception(jsonDecode(response.body)['message'] ?? 'Failed to create room');
    }
  }

  // DELETE ROOM
  Future<Map<String, dynamic>> deleteRoomAdmin(String roomCode) async {
    final response = await ApiClient.delete('/admin/room/$roomCode');

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception(jsonDecode(response.body)['message'] ?? 'Failed to delete room');
    }
  }

  // CHANGE ADMIN PASSWORD
  Future<Map<String, dynamic>> changePasswordAdmin(String newPassword) async {
    final response = await ApiClient.put(
      '/admin/admin/change-password',
      body: {'newPassword': newPassword},
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception(jsonDecode(response.body)['message'] ?? 'Failed to change admin password');
    }
  }
}
