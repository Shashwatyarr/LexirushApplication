import 'dart:convert';
import '../../../core/network/api_client.dart';

class AnalyticsService {
  // GET STUDENT ANALYTICS
  Future<Map<String, dynamic>> getStudentAnalytics(String studentId) async {
    final response = await ApiClient.get('/analytics/student/$studentId');

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception(jsonDecode(response.body)['message'] ?? 'Failed to fetch student analytics');
    }
  }

  // GET ADVANCED ANALYTICS (Query based - Admin/Superadmin)
  Future<Map<String, dynamic>> getAdvancedAnalytics(Map<String, dynamic> filters) async {
    final response = await ApiClient.post(
      '/analytics/query',
      body: filters,
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception(jsonDecode(response.body)['message'] ?? 'Failed to fetch advanced analytics');
    }
  }

  // GET ADMIN ANALYTICS (Backward compatibility)
  Future<Map<String, dynamic>> getAdminAnalytics() async {
    final response = await ApiClient.get('/analytics/admin');

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception(jsonDecode(response.body)['message'] ?? 'Failed to fetch admin analytics');
    }
  }

  // GET SUPERADMIN ANALYTICS (Backward compatibility)
  Future<Map<String, dynamic>> getSuperAdminAnalytics() async {
    final response = await ApiClient.post('/analytics/superadmin');

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception(jsonDecode(response.body)['message'] ?? 'Failed to fetch superadmin analytics');
    }
  }
}
