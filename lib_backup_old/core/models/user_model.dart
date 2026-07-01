class UserModel {
  final String id;
  final String? name;
  final String? email;
  final String? googleId;
  final String? username;
  final String? profilePic;
  final String role;
  final String? adminCode;
  final bool isFirstLogin;
  final int xp;
  final int level;
  final String? createdBy;
  final String? avatar;
  final String? avatarName;

  UserModel({
    required this.id,
    this.name,
    this.email,
    this.googleId,
    this.username,
    this.profilePic,
    required this.role,
    this.adminCode,
    this.isFirstLogin = false,
    this.xp = 0,
    this.level = 0,
    this.createdBy,
    this.avatar,
    this.avatarName,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['_id'] ?? '',
      name: json['name'],
      email: json['email'],
      googleId: json['googleId'],
      username: json['username'],
      profilePic: json['profilePic'],
      role: json['role'] ?? 'student',
      adminCode: json['adminCode'],
      isFirstLogin: json['isFirstLogin'] ?? false,
      xp: json['xp'] ?? 0,
      level: json['level'] ?? 0,
      createdBy: json['createdBy'],
      avatar: json['avatar'],
      avatarName: json['avatarName'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      '_id': id,
      'name': name,
      'email': email,
      'googleId': googleId,
      'username': username,
      'profilePic': profilePic,
      'role': role,
      'adminCode': adminCode,
      'isFirstLogin': isFirstLogin,
      'xp': xp,
      'level': level,
      'createdBy': createdBy,
      'avatar': avatar,
      'avatarName': avatarName,
    };
  }
}
