import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiClient {
  // Centralized backend configuration for fully synced web and mobile experience
  // Replace with localhost:5000 (e.g. 'http://192.168.x.x:5000') for local testing
  static const String serverHost = 'https://tambola-67o6.onrender.com';
  static const String socketUrl = serverHost;
  static const String baseUrl = '$serverHost/api';
  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token');
  }

  static Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', token);
  }

  static Future<void> removeToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
  }

  static Future<Map<String, String>> getHeaders({bool isMultipart = false}) async {
    final token = await getToken();
    return {
      if (!isMultipart) 'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static Future<http.Response> get(String endpoint) async {
    final headers = await getHeaders();
    return await http.get(Uri.parse('$baseUrl$endpoint'), headers: headers).timeout(const Duration(seconds: 15));
  }

  static Future<http.Response> post(String endpoint, {Map<String, dynamic>? body}) async {
    final headers = await getHeaders();
    return await http.post(
      Uri.parse('$baseUrl$endpoint'),
      headers: headers,
      body: body != null ? jsonEncode(body) : null,
    ).timeout(const Duration(seconds: 15));
  }

  static Future<http.Response> put(String endpoint, {Map<String, dynamic>? body}) async {
    final headers = await getHeaders();
    return await http.put(
      Uri.parse('$baseUrl$endpoint'),
      headers: headers,
      body: body != null ? jsonEncode(body) : null,
    ).timeout(const Duration(seconds: 15));
  }

  static Future<http.Response> delete(String endpoint) async {
    final headers = await getHeaders();
    return await http.delete(Uri.parse('$baseUrl$endpoint'), headers: headers).timeout(const Duration(seconds: 15));
  }

  static Uri getUri(String endpoint) {
    return Uri.parse('$baseUrl$endpoint');
  }
}
