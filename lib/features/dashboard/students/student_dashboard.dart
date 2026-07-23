// ============================================================
// FILE: lib/features/dashboard/students/student_dashboard.dart
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math' as math;
import 'dart:ui' as ui;
import '../../../core/constants/app_colors.dart';
import '../../auth/services/auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../profile/screens/profile_screen.dart';
import '../../leaderboard/screens/global_ranking_screen.dart';
import '../../leaderboard/services/leaderboard_service.dart';
import '../../../routes/app_routes.dart';

class StudentDashboard extends StatefulWidget {
  const StudentDashboard({super.key});

  @override
  State<StudentDashboard> createState() => _StudentDashboardState();
}

class _StudentDashboardState extends State<StudentDashboard>
    with TickerProviderStateMixin {

  late AnimationController _particleController;
  final AuthService _authService = AuthService();
  final LeaderboardService _leaderboardService = LeaderboardService();

  String _userName = '';
  String _userAvatar = '';
  String _userRole = 'student';
  int _userLevel = 1;
  int _userXp = 0;
  
  List<dynamic> _leaderboard = [];
  bool _isLoadingLeaderboard = true;

  int _currentIndex = 0; // 0 = Arena, 1 = Global Rankings, 2 = Profile

  @override
  void initState() {
    super.initState();
    _particleController = AnimationController(
      duration: const Duration(seconds: 15),
      vsync: this,
    )..repeat();
    _loadUser();
    _fetchLeaderboard();
  }

  Future<void> _loadUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _userName = prefs.getString('username') ?? 'Guest Warrior';
        _userAvatar = prefs.getString('avatar') ?? 'https://api.dicebear.com/7.x/avataaars/svg?seed=Guest';
        _userRole = prefs.getString('role') ?? 'student';
        _userLevel = prefs.getInt('level') ?? 1;
        _userXp = prefs.getInt('xp') ?? 0;
      });
    } catch (_) {}
  }

  Future<void> _fetchLeaderboard() async {
    try {
      final data = await _leaderboardService.getLeaderboard();
      setState(() {
        _leaderboard = data;
        _isLoadingLeaderboard = false;
      });
    } catch (e) {
      debugPrint("Leaderboard fetch error: $e");
      setState(() {
        _isLoadingLeaderboard = false;
      });
    }
  }

  @override
  void dispose() {
    _particleController.dispose();
    super.dispose();
  }

  Future<void> _handleLogout() async {
    await _authService.logout();
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, AppRoutes.login);
  }

  void _onTabTapped(int index) {
    setState(() {
      _currentIndex = index;
    });
  }
  
  void _goToHome() {
    setState(() {
      _currentIndex = 0;
    });
  }

  void _showModeInfo(String mode, String title, String description) {
    Navigator.pushNamed(
      context,
      AppRoutes.gameModeDetail,
      arguments: {
        'gameMode': mode,
        'title': title,
        'description': description,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0914),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isDesktop = constraints.maxWidth > 800;
          return Stack(
            children: [
              // Background layer
              _CyberParticles(controller: _particleController),
              const _CyberGrid(),
              
              Row(
                children: [
                  if (isDesktop) _buildSidebar(),
                  Expanded(
                    child: IndexedStack(
                      index: _currentIndex,
                      children: [
                        _buildHomeTab(isDesktop),
                        GlobalRankingScreen(onBack: _goToHome),
                        ProfileScreen(onBack: _goToHome),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: MediaQuery.of(context).size.width <= 800
          ? Container(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: const Color(0xFFD946EF).withOpacity(0.2), width: 1)),
              ),
              child: BottomNavigationBar(
                backgroundColor: const Color(0xFF131022),
                selectedItemColor: Colors.cyanAccent,
                unselectedItemColor: Colors.white54,
                currentIndex: _currentIndex,
                onTap: _onTabTapped,
                items: const [
                  BottomNavigationBarItem(
                    icon: Icon(Icons.dashboard_rounded),
                    label: 'Arena',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.leaderboard_rounded),
                    label: 'Rankings',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.person_rounded),
                    label: 'Profile',
                  ),
                ],
              ),
            )
          : null,
    );
  }

  // ── SIDEBAR (DESKTOP) ─────────────────────────────────────────────
  Widget _buildSidebar() {
    return Container(
      width: 260,
      height: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF131022).withOpacity(0.9),
        border: Border(
          right: BorderSide(color: const Color(0xFFD946EF).withOpacity(0.2), width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.6),
            blurRadius: 30,
            offset: const Offset(8, 0),
          )
        ],
      ),
      child: Column(
        children: [
          // Header Logo
          Container(
            padding: const EdgeInsets.only(top: 32, bottom: 16, left: 24, right: 24),
            alignment: Alignment.centerLeft,
            child: const Text(
              'LEXIRUSH',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
                color: Colors.white,
                shadows: [
                  Shadow(
                    color: Color(0xFFD946EF),
                    blurRadius: 15,
                  ),
                  Shadow(
                    color: Colors.cyanAccent,
                    blurRadius: 15,
                  ),
                ],
              ),
            ),
          ),
          
          // Profile Mini Card
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.02),
              border: Border.all(color: Colors.white.withOpacity(0.05)),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.cyanAccent, width: 2),
                    color: const Color(0xFF251E3E),
                    boxShadow: [
                      BoxShadow(color: Colors.cyanAccent.withOpacity(0.3), blurRadius: 10),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: _userAvatar.isNotEmpty && _userAvatar.startsWith('http')
                        ? Image.network(_userAvatar, fit: BoxFit.cover, errorBuilder: (c,e,s) => const Icon(Icons.person, color: Colors.white))
                        : const Icon(Icons.person, color: Colors.white),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _userName.toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'LVL $_userLevel • ${_userRole.toUpperCase()}',
                        style: const TextStyle(
                          color: Colors.cyanAccent,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ],
                  ),
                )
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Navigation Links
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  _buildSidebarItem(
                    icon: Icons.dashboard_rounded,
                    title: 'Arena',
                    index: 0,
                  ),
                  const SizedBox(height: 12),
                  _buildSidebarItem(
                    icon: Icons.leaderboard_rounded,
                    title: 'Global Rankings',
                    index: 1,
                  ),
                  const SizedBox(height: 12),
                  _buildSidebarItem(
                    icon: Icons.person_rounded,
                    title: 'Profile',
                    index: 2,
                  ),
                ],
              ),
            ),
          ),
          
          // Logout Button
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05))),
              color: Colors.black.withOpacity(0.2),
            ),
            child: InkWell(
              onTap: _handleLogout,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.logout_rounded, color: Colors.red[400], size: 20),
                    const SizedBox(width: 12),
                    Text(
                      'Log Out',
                      style: TextStyle(
                        color: Colors.red[400],
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  ],
                ),
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildSidebarItem({required IconData icon, required String title, required int index}) {
    final isSelected = _currentIndex == index;
    return InkWell(
      onTap: () => _onTabTapped(index),
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: isSelected ? Colors.cyanAccent.withOpacity(0.1) : Colors.transparent,
          border: Border(
            left: BorderSide(
              color: isSelected ? Colors.cyanAccent : Colors.transparent,
              width: 4,
            )
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.cyanAccent : Colors.grey[500],
              size: 20,
            ),
            const SizedBox(width: 16),
            Text(
              title,
              style: TextStyle(
                color: isSelected ? Colors.cyanAccent : Colors.grey[500],
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── HOME TAB (ARENA) ─────────────────────────────────────────────
  Widget _buildHomeTab(bool isDesktop) {
    return Column(
      children: [
        // Welcome Banner
        _buildWelcomeBanner(isDesktop: isDesktop),
        
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(isDesktop ? 24 : 16, 0, isDesktop ? 24 : 16, 40),
            child: isDesktop 
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Games Section
                      Expanded(
                        child: _buildGamesSection(),
                      ),
                      const SizedBox(width: 40),
                      // Leaderboard Section
                      SizedBox(
                        width: 350,
                        child: _buildLeaderboardSidebar(isDesktop: true),
                      )
                    ],
                  )
                : Column(
                    children: [
                      _buildGamesSection(),
                      const SizedBox(height: 32),
                      _buildLeaderboardSidebar(isDesktop: false),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildWelcomeBanner({bool isDesktop = true}) {
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(minHeight: isDesktop ? 250 : 140),
      margin: EdgeInsets.only(bottom: isDesktop ? 32 : 24),
      decoration: const BoxDecoration(
        color: Color(0xFF131022),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(48),
          bottomRight: Radius.circular(48),
        ),
        image: DecorationImage(
          image: NetworkImage('https://images.unsplash.com/photo-1542751371-adc38448a05e?q=80&w=2070&auto=format&fit=crop'),
          fit: BoxFit.cover,
          colorFilter: ColorFilter.mode(Colors.black54, BlendMode.darken),
          opacity: 0.3,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 30,
            offset: Offset(0, 10),
          )
        ],
      ),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              const Color(0xFF0B0914),
              const Color(0xFF0B0914).withOpacity(0.8),
              Colors.transparent,
            ],
          ),
          borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(48),
            bottomRight: Radius.circular(48),
          ),
        ),
        alignment: Alignment.bottomLeft,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              isDesktop ? 32 : 24, 
              isDesktop ? 64 : 24, 
              isDesktop ? 32 : 24, 
              isDesktop ? 32 : 24
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // User Avatar Large
                Container(
                  width: isDesktop ? 80 : 64,
                  height: isDesktop ? 80 : 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF131022), width: 4),
                    color: const Color(0xFF251E3E),
                    boxShadow: const [
                      BoxShadow(color: Colors.black54, blurRadius: 15),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(40),
                    child: _userAvatar.isNotEmpty && _userAvatar.startsWith('http')
                        ? Image.network(_userAvatar, fit: BoxFit.cover, errorBuilder: (c,e,s) => Icon(Icons.person, color: Colors.white, size: isDesktop ? 40 : 32))
                        : Icon(Icons.person, color: Colors.white, size: isDesktop ? 40 : 32),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Welcome,',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: isDesktop ? 22 : 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _userName,
                        style: TextStyle(
                          color: Colors.cyanAccent,
                          fontSize: isDesktop ? 28 : 20,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${_userXp.toString().replaceAllMapped(RegExp(r'\\B(?=(\\d{3})+(?!\\d))'), (Match m) => ',')} XP',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGamesSection() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 600;
        
        if (isMobile) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            child: Row(
              children: [
                SizedBox(
                  width: 280,
                  child: _buildGameCard(
                    title: 'LexiRush',
                    subtitle: 'The classic vocabulary arena. Fast, competitive, brutal.',
                    imageUrl: 'https://res.cloudinary.com/dvjefysfi/image/upload/v1781770365/WhatsApp_Image_2026-06-15_at_2.11.22_PM_lexife.jpg',
                    accentColor: Colors.cyanAccent,
                    buttonText: 'Enter Arena',
                    icon: Icons.sports_esports_rounded,
                    isDesktop: false,
                    onTap: () => _showModeInfo('lexirush', 'LexiRush', 'The classic vocabulary arena.'),
                  ),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  width: 280,
                  child: _buildGameCard(
                    title: 'Spell Shooter',
                    subtitle: 'Listen, aim, and shoot the correct spelling in the sky!',
                    imageUrl: 'https://res.cloudinary.com/dvjefysfi/image/upload/v1781770365/WhatsApp_Image_2026-06-15_at_2.07.43_PM_zv1jqo.jpg',
                    accentColor: Colors.amberAccent,
                    buttonText: 'Play Now',
                    icon: Icons.track_changes_rounded,
                    isDesktop: false,
                    onTap: () => _showModeInfo('spell_shooter', 'Spell Shooter', 'Listen, aim, and shoot.'),
                  ),
                ),
              ],
            ),
          );
        }

        return Row(
          children: [
            Expanded(
              child: _buildGameCard(
                title: 'LexiRush',
                subtitle: 'The classic vocabulary arena. Fast, competitive, brutal.',
                imageUrl: 'https://res.cloudinary.com/dvjefysfi/image/upload/v1781770365/WhatsApp_Image_2026-06-15_at_2.11.22_PM_lexife.jpg',
                accentColor: Colors.cyanAccent,
                buttonText: 'Enter Arena',
                icon: Icons.sports_esports_rounded,
                isDesktop: true,
                onTap: () => _showModeInfo('lexirush', 'LexiRush', 'The classic vocabulary arena.'),
              ),
            ),
            const SizedBox(width: 32),
            Expanded(
              child: _buildGameCard(
                title: 'Spell Shooter',
                subtitle: 'Listen, aim, and shoot the correct spelling in the sky!',
                imageUrl: 'https://res.cloudinary.com/dvjefysfi/image/upload/v1781770365/WhatsApp_Image_2026-06-15_at_2.07.43_PM_zv1jqo.jpg',
                accentColor: Colors.amberAccent,
                buttonText: 'Play Now',
                icon: Icons.track_changes_rounded,
                isDesktop: true,
                onTap: () => _showModeInfo('spell_shooter', 'Spell Shooter', 'Listen, aim, and shoot.'),
              ),
            ),
          ],
        );
      }
    );
  }

  Widget _buildGameCard({
    required String title,
    required String subtitle,
    required String imageUrl,
    required Color accentColor,
    required String buttonText,
    required IconData icon,
    bool isDesktop = true,
    required VoidCallback onTap,
  }) {
    return AspectRatio(
      aspectRatio: isDesktop ? 9 / 16 : 4 / 5,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(32),
          color: const Color(0xFF1A1528),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
          boxShadow: const [
            BoxShadow(
              color: Colors.black54,
              blurRadius: 20,
              offset: Offset(0, 10),
            )
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // Background Image
            Positioned.fill(
              child: Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (c,e,s) => Container(color: const Color(0xFF2A2538)),
              ),
            ),
            // Gradient Overlay
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      const Color(0xFF0B0914).withOpacity(1.0),
                      const Color(0xFF0B0914).withOpacity(0.6),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            // Content
            Positioned(
              bottom: 32,
              left: 32,
              right: 32,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title.toUpperCase(),
                          style: TextStyle(
                            color: accentColor,
                            fontSize: isDesktop ? 24 : 20,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2,
                            shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(icon, color: accentColor, size: isDesktop ? 24 : 20),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: onTap,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      foregroundColor: const Color(0xFF0B0914),
                      elevation: 10,
                      shadowColor: accentColor.withOpacity(0.5),
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      minimumSize: const Size(double.infinity, 56),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          buttonText.toUpperCase(),
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Icon(Icons.arrow_forward_rounded, size: 18),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLeaderboardSidebar({bool isDesktop = true}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'TOP CHALLENGERS',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 16,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
            TextButton(
              onPressed: () => _onTabTapped(1),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                side: BorderSide(color: Colors.white.withOpacity(0.1)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Row(
                children: [
                  Text(
                    'FULL ROSTER',
                    style: TextStyle(color: Colors.cyanAccent, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1),
                  ),
                  Icon(Icons.chevron_right_rounded, color: Colors.cyanAccent, size: 14),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF131022).withOpacity(0.8),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withOpacity(0.05)),
            boxShadow: const [
              BoxShadow(color: Colors.black26, blurRadius: 20),
            ],
          ),
          child: Column(
            children: [
              if (_isLoadingLeaderboard)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: CircularProgressIndicator(color: Colors.cyanAccent),
                  ),
                )
              else if (_leaderboard.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: Text(
                      'NO OPERATIVES FOUND.',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                )
              else
                ..._leaderboard.take(4).toList().asMap().entries.map((entry) {
                  final index = entry.key;
                  final player = entry.value;
                  final isFirst = index == 0;
                  
                  final rankColors = [Colors.yellow[400]!, Colors.grey[300]!, Colors.orange[600]!, Colors.grey[500]!];
                  final borderColors = [Colors.yellow[400]!.withOpacity(0.3), Colors.grey[300]!.withOpacity(0.2), Colors.orange[600]!.withOpacity(0.2), Colors.white.withOpacity(0.05)];
                  final bgColors = [Colors.yellow[400]!.withOpacity(0.05), Colors.grey[300]!.withOpacity(0.05), Colors.orange[600]!.withOpacity(0.05), Colors.transparent];
                  
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: bgColors[index],
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: borderColors[index]),
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 24,
                          child: Text(
                            '${index + 1}',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: rankColors[index],
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Container(
                          width: 40, height: 40,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: isFirst ? Colors.yellow[400]! : Colors.white.withOpacity(0.1)),
                            image: DecorationImage(
                              image: NetworkImage(player['avatar'] ?? 'https://api.dicebear.com/7.x/avataaars/svg?seed=${player['name']}'),
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      player['name'] ?? 'Unknown',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (isFirst)
                                    Padding(
                                      padding: const EdgeInsets.only(left: 4),
                                      child: Icon(Icons.verified_rounded, color: Colors.yellow[400], size: 14),
                                    )
                                ],
                              ),
                              Text(
                                'Lvl ${player['level'] ?? 1} • ${(player['xp'] ?? 0).toString()} XP',
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        )
                      ],
                    ),
                  );
                }),
              
              const SizedBox(height: 20),
              Container(height: 1, color: Colors.white.withOpacity(0.1)),
              const SizedBox(height: 20),
              
              // Current User Rank Widget
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.cyan[900]!.withOpacity(0.4),
                      Colors.blue[900]!.withOpacity(0.2),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.cyanAccent.withOpacity(0.3)),
                  boxShadow: [
                    BoxShadow(color: Colors.cyanAccent.withOpacity(0.1), blurRadius: 20),
                  ],
                ),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 24,
                      child: Text(
                        '?', // My rank placeholder
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.cyanAccent,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.cyanAccent),
                        image: DecorationImage(
                          image: NetworkImage(_userAvatar.isNotEmpty ? _userAvatar : 'https://api.dicebear.com/7.x/avataaars/svg?seed=You'),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${_userName.toUpperCase()} (YOU)',
                            style: const TextStyle(
                              color: Colors.cyanAccent,
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            'LVL $_userLevel • $_userXp XP',
                            style: TextStyle(
                              color: Colors.cyanAccent.withOpacity(0.6),
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),
                    )
                  ],
                ),
              )
            ],
          ),
        ),
      ],
    );
  }
}

// ── Background Particle Effects ───────────────────────────

class _CyberParticles extends StatelessWidget {
  final AnimationController controller;
  const _CyberParticles({required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) => CustomPaint(
        painter: _ParticlePainter(controller.value),
        size: MediaQuery.of(context).size,
      ),
    );
  }
}

class _ParticlePainter extends CustomPainter {
  final double t;
  _ParticlePainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width == 0 || size.height == 0) return;
    final rng = math.Random(42);
    for (int i = 0; i < 40; i++) {
      final x = rng.nextDouble() * size.width;
      final baseY = rng.nextDouble() * size.height;
      final speed = 0.2 + rng.nextDouble() * 0.8;
      final y = (baseY - t * size.height * speed) % size.height;
      final rad = 1.0 + rng.nextDouble() * 3.0;
      final op = 0.05 + rng.nextDouble() * 0.2;
      canvas.drawCircle(Offset(x, y), rad,
          Paint()..color = (rng.nextBool()
              ? Colors.cyanAccent : const Color(0xFFD946EF)).withOpacity(op));
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter o) => o.t != t;
}

class _CyberGrid extends StatelessWidget {
  const _CyberGrid();

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _GridPainter(),
    size: MediaQuery.of(context).size,
  );
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white.withOpacity(0.02)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 40) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (double y = 0; y < size.height; y += 40) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter o) => false;
}