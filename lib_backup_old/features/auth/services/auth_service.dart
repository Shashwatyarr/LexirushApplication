import 'dart:convert';
import '../../../core/network/api_client.dart';
import '../../../core/models/user_model.dart';

class AuthService {
  // GET USER
  Future<UserModel> getUser(String id) async {
    final response = await ApiClient.get('/auth/$id');

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return UserModel.fromJson(data);
    } else {
      throw Exception(jsonDecode(response.body)['message'] ?? 'Failed to load user');
    }
  }

  // GET MATCH HISTORY
  Future<List<dynamic>> getHistory(String userId) async {
    final response = await ApiClient.get('/auth/history/$userId');

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['history'] ?? [];
    } else {
      throw Exception(jsonDecode(response.body)['message'] ?? 'Failed to load history');
    }
  }

  // GOOGLE LOGIN (Student)
  Future<Map<String, dynamic>> googleLogin(String googleIdToken) async {
    final response = await ApiClient.post(
      '/auth/login',
      body: {'token': googleIdToken},
    );

    final data = jsonDecode(response.body);
    if (response.statusCode == 200) {
      if (data['token'] != null) {
        await ApiClient.saveToken(data['token']);
      }
      return data;
    } else {
      throw Exception(data['message'] ?? 'Google login failed');
    }
  }

  // CHANGE NAME
  Future<Map<String, dynamic>> changeName(String newName) async {
    final response = await ApiClient.put( 
      '/auth/change-name',
      body: {'name': newName},
    );

    final data = jsonDecode(response.body);
    if (response.statusCode == 200) {
      return data;
    } else {
      throw Exception(data['message'] ?? 'Failed to change name');
    }
  }

  // ADMIN LOGIN
  Future<Map<String, dynamic>> adminLogin(String username, String password) async {
    final response = await ApiClient.post(
      '/auth/login/admin',
      body: {'username': username, 'password': password},
    );

    final data = jsonDecode(response.body);
    if (response.statusCode == 200) {
      if (data['token'] != null) {
        await ApiClient.saveToken(data['token']);
      }
      return data;
    } else {
      throw Exception(data['message'] ?? 'Admin login failed');
    }
  }

  // CREATE ADMIN
  Future<Map<String, dynamic>> createAdmin(String username) async {
    final response = await ApiClient.post(
      '/auth/admin/create',
      body: {'username': username},
    );

    final data = jsonDecode(response.body);
    if (response.statusCode == 200 || response.statusCode == 201) {
      return data;
    } else {
      throw Exception(data['message'] ?? 'Failed to create admin');
    }
  }

  // CHANGE PASSWORD
  Future<Map<String, dynamic>> changePassword(String newPassword) async {
    final response = await ApiClient.put(
      '/auth/change-password',
      body: {'newPassword': newPassword},
    );

    final data = jsonDecode(response.body);
    if (response.statusCode == 200) {
      return data;
    } else {
      throw Exception(data['message'] ?? 'Failed to change password');
    }
  }

  // CHECK AUTH STATUS
  Future<Map<String, dynamic>> checkAuthStatus() async {
    final response = await ApiClient.get('/auth/check-auth');

    final data = jsonDecode(response.body);
    if (response.statusCode == 200) {
      return data;
    } else {
      throw Exception(data['message'] ?? 'Failed to check auth status');
    }
  }

  // LOGOUT
  Future<void> logout() async {
    try {
      await ApiClient.post('/auth/logout');
    } catch (e) {
      // Ignored for logout if backend fails to respond
    }
    
    // Clear local token
    await ApiClient.removeToken();
  }
}
