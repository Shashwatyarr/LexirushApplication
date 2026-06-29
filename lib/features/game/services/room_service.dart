import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../core/network/api_client.dart';

class RoomService {
  // JOIN ROOM
  Future<Map<String, dynamic>> joinRoom(String roomCode) async {
    final response = await ApiClient.post(
      '/room/join',
      body: {'roomCode': roomCode},
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception(jsonDecode(response.body)['message'] ?? 'Failed to join room');
    }
  }

  // LEAVE ROOM
  Future<Map<String, dynamic>> leaveRoom(String roomCode) async {
    final response = await ApiClient.post(
      '/room/leave',
      body: {'roomCode': roomCode},
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception(jsonDecode(response.body)['message'] ?? 'Failed to leave room');
    }
  }

  // UPLOAD CUSTOM EXCEL (Admin)
  Future<Map<String, dynamic>> uploadCustomExcel(String filePath, String fileName, List<int> fileBytes) async {
    final uri = ApiClient.getUri('/room/upload-custom');
    final request = http.MultipartRequest('POST', uri);
    
    final headers = await ApiClient.getHeaders(isMultipart: true);
    request.headers.addAll(headers);

    request.files.add(http.MultipartFile.fromBytes('excelFile', fileBytes, filename: fileName));

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception(jsonDecode(response.body)['message'] ?? 'Failed to upload excel');
    }
  }
}
