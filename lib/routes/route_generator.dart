// lib/routes/route_generator.dart
import 'package:flutter/material.dart';
import 'app_routes.dart';

import '../features/auth/screens/player_login_screen.dart';
import '../features/auth/screens/admin_login_screen.dart';
import '../features/dashboard/students/student_dashboard.dart';
import '../features/dashboard/students/game_mode_detail_screen.dart';
import '../features/dashboard/admins/admin_dashboard.dart';
import '../features/game/lexirush/lobby_screen.dart';
import '../features/game/lexirush/game_screen.dart';
import '../features/game/spell_shooter/spell_lobby_screen.dart';
import '../features/game/spell_shooter/spell_game_screen.dart';
import '../features/leaderboard/screens/leaderboard_screen.dart';
import '../features/profile/screens/profile_screen.dart';
import '../features/analytics/screens/analytics_screen.dart';

class RouteGenerator {
  static Route<dynamic> generateRoute(RouteSettings settings) {
    final args = settings.arguments;

    switch (settings.name) {
      case AppRoutes.login:
        return MaterialPageRoute(builder: (_) => const PlayerLoginScreen());

      case AppRoutes.adminLogin:
        return MaterialPageRoute(builder: (_) => const AdminLoginScreen());

      case AppRoutes.studentDashboard:
        return MaterialPageRoute(builder: (_) => const StudentDashboard());

      case AppRoutes.adminDashboard:
        return MaterialPageRoute(builder: (_) => const AdminDashboard());

      case AppRoutes.profile:
        return MaterialPageRoute(builder: (_) => const ProfileScreen());

      case AppRoutes.analytics:
        return MaterialPageRoute(builder: (_) => const AnalyticsScreen());

      case AppRoutes.gameModeDetail:
        if (args is Map<String, dynamic>) {
          return MaterialPageRoute(
            builder: (_) => GameModeDetailScreen(
              gameMode: args['gameMode'] as String? ?? 'lexirush',
              title: args['title'] as String? ?? 'Game',
              description: args['description'] as String? ?? 'Join the battle',
            ),
          );
        }
        return _errorRoute('Invalid arguments for GameModeDetailScreen');

      // LexiRush
      case AppRoutes.lobby:
        if (args is Map<String, dynamic>) {
          final roomCode = args['roomCode'] as String? ?? '';
          final isAdmin = args['isAdmin'] as bool? ?? false;
          return MaterialPageRoute(
            builder: (_) => LobbyScreen(
              roomCode: roomCode,
              isAdmin: isAdmin,
            ),
          );
        }
        return _errorRoute('Invalid arguments for LobbyScreen');

      case AppRoutes.game:
        if (args is Map<String, dynamic>) {
          final roomCode = args['roomCode'] as String? ?? '';
          final isAdmin = args['isAdmin'] as bool? ?? false;
          final initialState = args['data'] as Map<String, dynamic>? ?? {};
          return MaterialPageRoute(
            builder: (_) => GameScreen(
              roomCode: roomCode,
              isAdmin: isAdmin,
              initialState: initialState,
            ),
          );
        }
        return _errorRoute('Invalid arguments for GameScreen');

      case AppRoutes.leaderboard:
      case AppRoutes.spellLeaderboard: // Since both use the same screen currently, or we can separate if needed
        if (args is Map<String, dynamic>) {
          return MaterialPageRoute(
            builder: (_) => LeaderboardScreen(
              roomCode: args['roomCode'] as String? ?? '',
              isAdmin: args['isAdmin'] as bool? ?? false,
              leaderboard: args['leaderboard'] != null ? List<Map<String, dynamic>>.from(args['leaderboard']) : [],
              roomAverage: (args['roomAverage'] as num?)?.toDouble() ?? 0.0,
              questionStats: args['questionStats'] != null ? List<Map<String, dynamic>>.from(args['questionStats']) : [],
            ),
          );
        }
        return _errorRoute('Invalid arguments for LeaderboardScreen');

      // Spell Shooter
      case AppRoutes.spellLobby:
        if (args is Map<String, dynamic>) {
          final roomCode = args['roomCode'] as String? ?? '';
          final isAdmin = args['isAdmin'] as bool? ?? false;
          return MaterialPageRoute(
            builder: (_) => SpellLobbyScreen(
              roomCode: roomCode,
              isAdmin: isAdmin,
            ),
          );
        }
        return _errorRoute('Invalid arguments for SpellLobbyScreen');

      case AppRoutes.spellGame:
        if (args is Map<String, dynamic>) {
          final roomCode = args['roomCode'] as String? ?? '';
          final fullQuestionData = args['fullQuestionData'] != null ? List<Map<String, dynamic>>.from(args['fullQuestionData']) : null;
          final reconnectData = args['reconnectData'] as Map<String, dynamic>?;
          return MaterialPageRoute(
            builder: (_) => SpellGameScreen(
              roomCode: roomCode,
              fullQuestionData: fullQuestionData,
              reconnectData: reconnectData,
            ),
          );
        }
        return _errorRoute('Invalid arguments for SpellGameScreen');

      default:
        return _errorRoute('Route not found');
    }
  }

  static Route<dynamic> _errorRoute(String message) {
    return MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('Error')),
        body: Center(child: Text(message)),
      ),
    );
  }
}
