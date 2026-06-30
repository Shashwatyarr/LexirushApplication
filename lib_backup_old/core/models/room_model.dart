class RoomModel {
  final String id;
  final String roomCode;
  final String hostId;
  final List<dynamic> players; // Can be enhanced with PlayerModel if needed
  final int maxPlayers;
  final bool isActive;

  RoomModel({
    required this.id,
    required this.roomCode,
    required this.hostId,
    required this.players,
    required this.maxPlayers,
    required this.isActive,
  });

  factory RoomModel.fromJson(Map<String, dynamic> json) {
    return RoomModel(
      id: json['_id'] ?? '',
      roomCode: json['roomCode'] ?? '',
      hostId: json['host'] is String ? json['host'] : (json['host']?['_id'] ?? ''),
      players: json['players'] ?? [],
      maxPlayers: json['maxPlayers'] ?? 100,
      isActive: json['isActive'] ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      '_id': id,
      'roomCode': roomCode,
      'host': hostId,
      'players': players,
      'maxPlayers': maxPlayers,
      'isActive': isActive,
    };
  }
}
