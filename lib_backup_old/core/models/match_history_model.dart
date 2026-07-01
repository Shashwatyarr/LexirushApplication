class MatchHistoryModel {
  final String id;
  final String userId;
  final String? adminId;
  final String roomCode;
  final int points;
  final DateTime playedAt;
  final List<dynamic> questions; // Can map to MatchQuestionModel if needed
  final String gameMode;
  final String? branch;
  final String? section;
  final String? semester;
  final String? batch;
  final double accuracy;

  MatchHistoryModel({
    required this.id,
    required this.userId,
    this.adminId,
    required this.roomCode,
    required this.points,
    required this.playedAt,
    required this.questions,
    required this.gameMode,
    this.branch,
    this.section,
    this.semester,
    this.batch,
    required this.accuracy,
  });

  factory MatchHistoryModel.fromJson(Map<String, dynamic> json) {
    return MatchHistoryModel(
      id: json['_id'] ?? '',
      userId: json['userId'] is String ? json['userId'] : (json['userId']?['_id'] ?? ''),
      adminId: json['adminId'] is String ? json['adminId'] : (json['adminId']?['_id']),
      roomCode: json['roomCode'] ?? '',
      points: json['points'] ?? 0,
      playedAt: json['playedAt'] != null ? DateTime.parse(json['playedAt']) : DateTime.now(),
      questions: json['questions'] ?? [],
      gameMode: json['gameMode'] ?? 'lexirush',
      branch: json['branch'],
      section: json['section'],
      semester: json['semester'],
      batch: json['batch'],
      accuracy: (json['accuracy'] ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      '_id': id,
      'userId': userId,
      'adminId': adminId,
      'roomCode': roomCode,
      'points': points,
      'playedAt': playedAt.toIso8601String(),
      'questions': questions,
      'gameMode': gameMode,
      'branch': branch,
      'section': section,
      'semester': semester,
      'batch': batch,
      'accuracy': accuracy,
    };
  }
}
