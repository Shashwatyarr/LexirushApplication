import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  // TODO: Replace with your actual backend base URL (e.g. from flutter_dotenv or config)
  static const String baseUrl = 'http://tambola-67o6.onrender.com/api'; 
  
  // Helper to get token
  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token');
  }

  // Helper to save token
  Future<void> _saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', token);
  }

  // Helper to remove token
  Future<void> _removeToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
  }

  // GET USER
  Future<Map<String, dynamic>> getUser(String id) async {
    final token = await _getToken();
    final response = await http.get(
      Uri.parse('$baseUrl/users/$id'),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception(jsonDecode(response.body)['message'] ?? 'Failed to load user');
    }
  }

  // GOOGLE LOGIN (Student)
  Future<Map<String, dynamic>> googleLogin(String googleIdToken) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/google-login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'token': googleIdToken}),
    );

    final data = jsonDecode(response.body);
    if (response.statusCode == 200) {
      if (data['token'] != null) {
        await _saveToken(data['token']);
      }
      return data;
    } else {
      throw Exception(data['message'] ?? 'Google login failed');
    }
  }

  // CHANGE NAME
  Future<Map<String, dynamic>> changeName(String newName) async {
    final token = await _getToken();
    final response = await http.put( 
      Uri.parse('$baseUrl/users/change-name'),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'name': newName}),
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
    final response = await http.post(
      Uri.parse('$baseUrl/auth/admin-login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );

    final data = jsonDecode(response.body);
    if (response.statusCode == 200) {
      if (data['token'] != null) {
        await _saveToken(data['token']);
      }
      return data;
    } else {
      throw Exception(data['message'] ?? 'Admin login failed');
    }
  }

  // CREATE ADMIN
  Future<Map<String, dynamic>> createAdmin(String username) async {
    final token = await _getToken();
    final response = await http.post(
      Uri.parse('$baseUrl/auth/create-admin'),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'username': username}),
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
    final token = await _getToken();
    final response = await http.put(
      Uri.parse('$baseUrl/users/change-password'),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'newPassword': newPassword}),
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
    final token = await _getToken();
    final response = await http.get(
      Uri.parse('$baseUrl/auth/status'),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
    );

    final data = jsonDecode(response.body);
    if (response.statusCode == 200) {
      return data;
    } else {
      throw Exception(data['message'] ?? 'Failed to check auth status');
    }
  }

  // LOGOUT
  Future<void> logout() async {
    final token = await _getToken();
    
    try {
      await http.post(
        Uri.parse('$baseUrl/auth/logout'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      );
    } catch (e) {
      // Ignored for logout if backend fails to respond
    }
    
    // Clear local token
    await _removeToken();
  }
}
