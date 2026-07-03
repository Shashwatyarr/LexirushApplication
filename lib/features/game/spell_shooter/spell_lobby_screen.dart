// ============================================================
// FILE: lib/features/game/spell_shooter/spell_lobby_screen.dart
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math' as math;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_client.dart';
import 'spell_game_screen.dart';
import '../../../routes/app_routes.dart';

// Local accent for Spell Shooter (kept out of AppColors — screen-specific,
// same pattern lobby_screen.dart uses for its own gold host badge).
const Color _spellGold = Color(0xFFFFB020);

class SpellLobbyScreen extends StatefulWidget {
  final String roomCode;
  final bool isAdmin;

  const SpellLobbyScreen({
    super.key,
    required this.roomCode,
    required this.isAdmin,
  });

  @override
  State<SpellLobbyScreen> createState() => _SpellLobbyScreenState();
}

class _SpellLobbyScreenState extends State<SpellLobbyScreen>
    with TickerProviderStateMixin {

  late AnimationController _particleController;
  late AnimationController _pulseController;

  IO.Socket? _socket;

  // ── State ────────────────────────────────────────────────
  Map<String, dynamic>? _roomData;
  Map<String, dynamic>? _currentUser;
  bool _isLoading = true;
  bool _isCopied = false;

  // Mission designation (host only)
  String _selectedBranch   = 'CSE';
  String _selectedSection  = 'A';
  String _selectedSemester = '1';
  String _roomName         = 'CSE_SecA_1_';

  // Spell Shooter defaults (fast paced)
  int _level     = 1;
  int _timeLimit = 7;

  final List<String> _branchOptions   = ['CSE','IT','CS','CSIT','CSE-AI','CSE-AIML','ECE','ELCE','EEE','ME','CSDS','CS-CYBER-SECURITY'];
  final List<String> _sectionOptions  = ['A','B','C','D','E'];
  final List<String> _semesterOptions = ['1','2','3','4','5','6','7','8'];

  @override
  void initState() {
    super.initState();

    _roomName = 'CSE_SecA_1_${widget.roomCode}';

    _particleController = AnimationController(
      duration: const Duration(seconds: 6),
      vsync: this,
    )..repeat();

    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);

    _initLobby();

    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted && _isLoading) {
        setState(() {
          _isLoading = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _socket?.disconnect();
    _socket?.dispose();
    _particleController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  // ── Init: load user → connect socket ────────────────────
  Future<void> _initLobby() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String userId   = prefs.getString('userId') ?? '';
      final userName = prefs.getString('username') ?? prefs.getString('userName') ?? 'Admin';
      final avatar   = prefs.getString('avatar') ?? '';
      final role     = prefs.getString('role') ?? 'student';

      if (userId.isEmpty && widget.isAdmin) {
        userId = 'admin_${DateTime.now().millisecondsSinceEpoch}';
      }

      // Fire-and-forget fetch to avoid blocking the lobby load
      int userLevel = 1;
      if (userId.isNotEmpty && !userId.startsWith('admin_')) {
        ApiClient.get('/auth/$userId').then((res) {
          if (res.statusCode == 200) {
            // parse level if your ApiClient response shape exposes it
          }
        }).catchError((_) {});
      }

      setState(() {
        _currentUser = {
          'id'    : userId,
          'name'  : userName,
          'avatar': avatar,
          'level' : userLevel,
          'role'  : role,
        };
      });

      _connectSocket(userId, userName, avatar, userLevel);
    } catch (e) {
      debugPrint('Spell lobby init error: $e');
    }
  }

  // ── Socket connection ────────────────────────────────────
  void _connectSocket(String userId, String name, String avatar, int level) {
    _socket = IO.io(
      'https://tambola-67o6.onrender.com',   // Same backend URL as ApiClient
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .build(),
    );

    _socket!.connect();

    _socket!.onConnect((_) {
      debugPrint('✅ Spell socket connected');
      _socket!.emit('joinRoom', {
        'roomCode' : widget.roomCode.toUpperCase(),
        'userId'   : userId,
        'name'     : name,
        'avatar'   : avatar,
        'level'    : level,
        'isAdmin'  : widget.isAdmin,
        'role'     : _currentUser?['role'] ?? 'student',
      });
    });

    _socket!.onConnectError((err) {
      debugPrint('Socket connect error: $err');
      if (mounted) {
        setState(() => _isLoading = false);
        _showSnack('Connection failed: $err', color: AppColors.neonRed);
      }
    });

    _socket!.onDisconnect((_) {
      debugPrint('Socket disconnected');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    });

    // ── roomData — main state update ──
    _socket!.on('roomData', (data) {
      if (!mounted) return;
      final d = Map<String, dynamic>.from(data as Map);
      setState(() {
        _roomData  = d;
        _isLoading = false;
      });

      final incomingName = d['roomName'] as String? ?? '';
      final rawCode = widget.roomCode.toUpperCase();

      if (incomingName.isNotEmpty && incomingName != rawCode) {
        _roomName = incomingName;
        final parts = incomingName.split('_');
        if (parts.length >= 3) {
          if (_branchOptions.contains(parts[0])) {
            setState(() => _selectedBranch = parts[0]);
          }
          if (parts[1].isNotEmpty) {
            final sec = parts[1].replaceFirst('Sec', '');
            if (_sectionOptions.contains(sec)) {
              setState(() => _selectedSection = sec);
            }
          }
          if (_semesterOptions.contains(parts[2])) {
            setState(() => _selectedSemester = parts[2]);
          }
        }
      }

      final gameSettings = d['gameSettings'] as Map?;
      if (gameSettings != null) {
        setState(() {
          _level     = gameSettings['level'] ?? 1;
          _timeLimit = gameSettings['timeLimitPerQuestion'] ?? 7;
        });
      }
    });

    // ── gameStarted — navigate to game ──
    _socket!.on('gameStarted', (data) {
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, AppRoutes.spellGame, arguments: {
        'roomCode': widget.roomCode,
        'fullQuestionData': data['fullQuestionData'],
        'reconnectData': data,
      });
      debugPrint('Spell game started: $data');
    });

    // ── reconnectGame ──
    _socket!.on('reconnectGame', (data) {
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, AppRoutes.spellGame, arguments: {
        'roomCode': widget.roomCode,
        'reconnectData': data,
        'fullQuestionData': data['fullQuestionData'],
      });
      debugPrint('Spell reconnect: $data');
    });

    // ── roomClosed ──
    _socket!.on('roomClosed', (_) {
      if (!mounted) return;
      _showRoomClosedDialog();
    });

    // ── playerKicked ──
    _socket!.on('playerKicked', (kickedUserId) {
      if (!mounted) return;
      final myId = _currentUser?['id'] ?? '';
      if (kickedUserId == myId) {
        _showKickedDialog();
      }
    });

    // ── error ──
    _socket!.on('error', (msg) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      final text = msg.toString();
      if (text.toLowerCase().contains('not found') ||
          text.toLowerCase().contains('expired')) {
        _showRoomClosedDialog(message: text);
      } else {
        _showSnack(text, color: AppColors.neonRed);
      }
    });
  }

  // ── Socket emitters ──────────────────────────────────────
  void _handleUpdateSettings() {
    _socket?.emit('updateSettings', {
      'roomCode': widget.roomCode.toUpperCase(),
      'settings': {
        'roomName'            : _roomName,
        'level'               : _level,
        'timeLimitPerQuestion': _timeLimit,
      },
    });
  }

  void _handleBranchChange(String val) {
    setState(() {
      _selectedBranch = val;
      _roomName = '${val}_Sec${_selectedSection}_${_selectedSemester}_${widget.roomCode}';
    });
    _handleUpdateSettings();
  }

  void _handleSectionChange(String val) {
    setState(() {
      _selectedSection = val;
      _roomName = '${_selectedBranch}_Sec${val}_${_selectedSemester}_${widget.roomCode}';
    });
    _handleUpdateSettings();
  }

  void _handleSemesterChange(String val) {
    setState(() {
      _selectedSemester = val;
      _roomName = '${_selectedBranch}_Sec${_selectedSection}_${val}_${widget.roomCode}';
    });
    _handleUpdateSettings();
  }

  void _handleStartGame() {
    _socket?.emit('prepareGame', {'roomCode': widget.roomCode});
    Future.delayed(const Duration(seconds: 1), () {
      _socket?.emit('startGame', {
        'roomCode': widget.roomCode.toUpperCase(),
        'adminId' : _currentUser?['id'],
        'roomName': _roomName,
      });
    });
  }

  void _handleCopyCode() async {
    await Clipboard.setData(ClipboardData(text: widget.roomCode));
    setState(() => _isCopied = true);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _isCopied = false);
  }

  void _handleLeave() {
    showDialog(
      context: context,
      builder: (_) => _ConfirmDialog(
        title: 'Exit Lobby?',
        message: 'Are you sure you want to exit the arena?',
        onConfirm: () {
          _socket?.emit('leaveRoom', {'roomCode': widget.roomCode.toUpperCase()});
          Navigator.pop(context); // close dialog
          Navigator.pop(context); // go back
        },
      ),
    );
  }

  void _handleKickPlayer(String targetUserId) {
    showDialog(
      context: context,
      builder: (_) => _ConfirmDialog(
        title: 'Kick Shooter?',
        message: 'Are you sure you want to kick this shooter?',
        onConfirm: () {
          _socket?.emit('kickPlayer', {
            'roomCode'     : widget.roomCode.toUpperCase(),
            'targetUserId' : targetUserId,
            'adminId'      : _currentUser?['id'],
          });
          Navigator.pop(context);
        },
      ),
    );
  }

  // ── Dialogs / Snacks ─────────────────────────────────────
  void _showSnack(String msg, {Color color = AppColors.neonCyan}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: color.withOpacity(0.15),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: color.withOpacity(0.5)),
      ),
      behavior: SnackBarBehavior.floating,
      content: Text(msg, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
    ));
  }

  void _showKickedDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppColors.neonRed.withOpacity(0.5)),
        ),
        title: Text('Kicked!',
            style: TextStyle(color: AppColors.neonRed, fontWeight: FontWeight.w900)),
        content: const Text('You have been removed from the arena by the Admin.',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () { Navigator.pop(context); Navigator.pop(context); },
            child: Text('OK', style: TextStyle(color: AppColors.neonPurple)),
          ),
        ],
      ),
    );
  }

  void _showRoomClosedDialog({String? message}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppColors.neonRed.withOpacity(0.5)),
        ),
        title: const Text('Arena Closed',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
        content: Text(message ?? 'This arena has been terminated by the Host.',
            style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () { Navigator.pop(context); Navigator.pop(context); },
            child: Text('OK', style: TextStyle(color: AppColors.neonPurple)),
          ),
        ],
      ),
    );
  }

  // ── Computed ─────────────────────────────────────────────
  bool get _isMeHost {
    final actualHostId = _roomData?['host'] as String?;
    return widget.isAdmin || (actualHostId == _currentUser?['id']);
  }

  List<dynamic> get _players {
    final serverPlayers = (_roomData?['players'] as List?) ?? [];
    if (_currentUser == null) return serverPlayers;

    final myId = _currentUser!['id'];
    final bool amIThere = serverPlayers.any((p) => p['userId'] == myId || p['id'] == myId);

    if (amIThere) {
      return serverPlayers;
    } else {
      final mePlayer = {
        'userId': myId,
        'name': _currentUser!['name'],
        'avatar': _currentUser!['avatar'],
        'level': _currentUser!['level'],
        'role': _currentUser!['role'],
        'isAdmin': widget.isAdmin,
        'isHost': widget.isAdmin,
        'isOnline': true,
      };
      return [mePlayer, ...serverPlayers];
    }
  }

  // ============================================================
  // BUILD
  // ============================================================
  @override
  Widget build(BuildContext context) {
    if (_isLoading || _currentUser == null) {
      return _buildLoadingScreen();
    }

    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      body: Stack(
        children: [
          _SpellParticles(controller: _particleController),
          const _SpellGrid(),
          SafeArea(
            child: Column(
              children: [
                _buildTopBar(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        const SizedBox(height: 12),
                        _buildMissionCodeHeader(),
                        const SizedBox(height: 20),
                        _buildDesignationCard(),
                        const SizedBox(height: 20),
                        _buildPlayersSection(),
                        const SizedBox(height: 24),
                        _buildBottomActions(),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Loading ──────────────────────────────────────────────
  Widget _buildLoadingScreen() {
    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      body: Stack(
        children: [
          const _SpellGrid(),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 70,
                  height: 70,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: const AlwaysStoppedAnimation<Color>(_spellGold),
                  ),
                ),
                const SizedBox(height: 24),
                ShaderMask(
                  shaderCallback: (b) => const LinearGradient(
                    colors: [_spellGold, AppColors.neonPink],
                  ).createShader(b),
                  child: const Text(
                    'LOADING CARNIVAL...',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      letterSpacing: 4,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Synchronizing mission data',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.3),
                    fontSize: 11,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── TOP BAR ─────────────────────────────────────────────
  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: _spellGold,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.gps_fixed_rounded,
                color: Colors.black, size: 18),
          ),
          const SizedBox(width: 8),
          const Text('SPELL SHOOTER',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 16,
              letterSpacing: 1.5,
            ),
          ),

          const Spacer(),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _spellGold.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _spellGold.withOpacity(0.4)),
            ),
            child: Row(
              children: [
                Container(
                  width: 6, height: 6,
                  decoration: const BoxDecoration(
                    color: _spellGold,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Text('LIVE ARENA',
                  style: TextStyle(
                    color: _spellGold,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 10),

          GestureDetector(
            onTap: _handleLeave,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.neonRed.withOpacity(0.5)),
                borderRadius: BorderRadius.circular(20),
                color: AppColors.neonRed.withOpacity(0.08),
              ),
              child: Row(
                children: [
                  Icon(Icons.logout_rounded,
                      color: AppColors.neonRed, size: 14),
                  const SizedBox(width: 4),
                  Text('Exit',
                    style: TextStyle(
                      color: AppColors.neonRed,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── MISSION CODE HEADER (replaces wooden board) ─────────
  Widget _buildMissionCodeHeader() {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (_, child) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _spellGold.withOpacity(0.25 + 0.15 * _pulseController.value),
          ),
          boxShadow: [
            BoxShadow(
              color: _spellGold.withOpacity(0.10 + 0.08 * _pulseController.value),
              blurRadius: 30,
              spreadRadius: 2,
            ),
          ],
        ),
        child: child,
      ),
      child: Column(
        children: [
          Text('MISSION CODE',
            style: TextStyle(
              color: Colors.white.withOpacity(0.4),
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 4,
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: _handleCopyCode,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.3),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.roomCode,
                    style: TextStyle(
                      color: _spellGold,
                      fontWeight: FontWeight.w900,
                      fontSize: 32,
                      letterSpacing: 6,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Icon(
                    _isCopied ? Icons.check_circle_rounded : Icons.copy_rounded,
                    color: _isCopied ? AppColors.neonGreen : Colors.white54,
                    size: 22,
                  ),
                ],
              ),
            ),
          ),
          if (_isCopied) ...[
            const SizedBox(height: 8),
            Text('Copied to clipboard!',
              style: TextStyle(
                color: AppColors.neonGreen,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── DESIGNATION CARD ─────────────────────────────────────
  Widget _buildDesignationCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Mission Designation',
            style: TextStyle(
              color: _spellGold,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: _buildDropdown(
                  value: _selectedBranch,
                  items: _branchOptions,
                  onChanged: _isMeHost ? _handleBranchChange : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: _buildDropdown(
                  value: _selectedSection,
                  items: _sectionOptions,
                  prefix: 'Sec',
                  onChanged: _isMeHost ? _handleSectionChange : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: _buildDropdown(
                  value: _selectedSemester,
                  items: _semesterOptions,
                  prefix: 'Sem ',
                  onChanged: _isMeHost ? _handleSemesterChange : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: _spellGold.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _spellGold.withOpacity(0.3)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.badge_rounded, color: _spellGold, size: 16),
                const SizedBox(width: 8),
                Text(_roomName,
                  style: TextStyle(
                    color: _spellGold,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdown({
    required String value,
    required List<String> items,
    String prefix = '',
    ValueChanged<String>? onChanged,
  }) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: onChanged != null
              ? _spellGold.withOpacity(0.3)
              : Colors.white.withOpacity(0.08),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          dropdownColor: AppColors.bgSurface,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
          icon: Icon(Icons.keyboard_arrow_down,
              color: Colors.white.withOpacity(0.4), size: 16),
          items: items.map((item) => DropdownMenuItem(
            value: item,
            child: Text('$prefix$item',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              overflow: TextOverflow.ellipsis,
            ),
          )).toList(),
          onChanged: onChanged != null
              ? (v) { if (v != null) onChanged(v); }
              : null,
        ),
      ),
    );
  }

  // ── PLAYERS SECTION ─────────────────────────────────────
  Widget _buildPlayersSection() {
    final players = _players;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.groups_rounded, color: _spellGold, size: 20),
                  const SizedBox(width: 8),
                  const Text('CONNECTED SHOOTERS',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: _spellGold.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _spellGold.withOpacity(0.3)),
                ),
                child: Text('${players.length} READY',
                  style: TextStyle(
                    color: _spellGold,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          players.isEmpty
              ? Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              children: [
                Icon(Icons.hourglass_empty_rounded,
                    color: Colors.white.withOpacity(0.2), size: 40),
                const SizedBox(height: 10),
                Text('Waiting for shooters to join...',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.3),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          )
              : GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 0.78,
            ),
            itemCount: players.length,
            itemBuilder: (context, index) => _buildPlayerCard(
                Map<String, dynamic>.from(players[index] as Map)),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayerCard(Map<String, dynamic> player) {
    final actualHostId = _roomData?['host'] as String?;
    final isHost = (player['isAdmin'] == true) ||
        (player['isHost'] == true) ||
        (player['userId'] == actualHostId);
    final isOffline = player['isOnline'] == false;
    final myId = _currentUser?['id'] ?? '';
    final canKick = _isMeHost && !isHost && player['userId'] != myId;
    final avatarUrl = player['avatar'] as String? ?? '';
    final name = player['name'] as String? ?? 'Shooter';
    final level = player['level'] ?? 1;
    final role = (player['role'] as String?)?.toLowerCase() ?? '';

    String displayRole = '';
    if (role == 'superadmin') {
      displayRole = 'SUPERADMIN';
    } else if (role == 'admin' || player['isAdmin'] == true) {
      displayRole = 'ADMIN';
    } else if (isHost) {
      displayRole = 'HOST';
    } else {
      displayRole = 'LVL $level';
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
          decoration: BoxDecoration(
            color: AppColors.bgSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isOffline
                  ? AppColors.neonRed.withOpacity(0.3)
                  : _spellGold.withOpacity(0.25),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 46, height: 46,
                    decoration: BoxDecoration(
                      color: AppColors.bgCard,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isOffline
                            ? AppColors.neonRed
                            : _spellGold.withOpacity(0.6),
                        width: 1.5,
                      ),
                    ),
                    child: ClipOval(
                      child: avatarUrl.isNotEmpty
                          ? Image.network(avatarUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Icon(
                            Icons.person_rounded,
                            color: _spellGold, size: 22),
                      )
                          : Icon(Icons.person_rounded,
                          color: _spellGold, size: 22),
                    ),
                  ),
                  if (isHost)
                    Positioned(
                      top: -4, right: -4,
                      child: Container(
                        width: 18, height: 18,
                        decoration: const BoxDecoration(
                          color: _spellGold,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.star_rounded,
                            color: Colors.black, size: 12),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(name,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isOffline ? Colors.white30 : Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                  decoration: isOffline ? TextDecoration.lineThrough : null,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isOffline
                      ? AppColors.neonRed.withOpacity(0.1)
                      : (displayRole == 'SUPERADMIN' || displayRole == 'ADMIN' || displayRole == 'HOST')
                      ? _spellGold.withOpacity(0.1)
                      : AppColors.neonGreen.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isOffline
                        ? AppColors.neonRed.withOpacity(0.2)
                        : (displayRole == 'SUPERADMIN' || displayRole == 'ADMIN' || displayRole == 'HOST')
                        ? _spellGold.withOpacity(0.2)
                        : AppColors.neonGreen.withOpacity(0.2),
                  ),
                ),
                child: Text(
                  isOffline ? 'OFFLINE' : displayRole,
                  style: TextStyle(
                    color: isOffline
                        ? AppColors.neonRed
                        : (displayRole == 'SUPERADMIN' || displayRole == 'ADMIN' || displayRole == 'HOST')
                        ? _spellGold
                        : AppColors.neonGreen,
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (canKick)
          Positioned(
            top: -6, right: -6,
            child: GestureDetector(
              onTap: () => _handleKickPlayer(player['userId'] as String),
              child: Container(
                width: 24, height: 24,
                decoration: BoxDecoration(
                  color: AppColors.neonRed.withOpacity(0.9),
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.bgDeep, width: 2),
                ),
                child: const Icon(Icons.close_rounded,
                    color: Colors.white, size: 13),
              ),
            ),
          ),
      ],
    );
  }

  // ── BOTTOM ACTIONS ───────────────────────────────────────
  Widget _buildBottomActions() {
    final canStart = _isMeHost && _players.isNotEmpty;

    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: _handleLeave,
            child: Container(
              height: 50,
              decoration: BoxDecoration(
                color: AppColors.neonRed.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.neonRed.withOpacity(0.4)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.logout_rounded, color: AppColors.neonRed, size: 16),
                  const SizedBox(width: 6),
                  Text('Leave Arena',
                    style: TextStyle(
                      color: AppColors.neonRed,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_isMeHost) ...[
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: GestureDetector(
              onTap: canStart ? _handleStartGame : null,
              child: Container(
                height: 50,
                decoration: BoxDecoration(
                  gradient: canStart
                      ? const LinearGradient(
                    colors: [_spellGold, Color(0xFFFF7A00)],
                  )
                      : null,
                  color: canStart ? null : AppColors.bgSurface,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: canStart
                      ? [BoxShadow(
                    color: _spellGold.withOpacity(0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  )]
                      : [],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.rocket_launch_rounded,
                        color: canStart ? Colors.black : Colors.white30, size: 18),
                    const SizedBox(width: 8),
                    Text('LAUNCH MISSION',
                      style: TextStyle(
                        color: canStart ? Colors.black : Colors.white30,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ============================================================
// Confirm Dialog
// ============================================================
class _ConfirmDialog extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback onConfirm;

  const _ConfirmDialog({
    required this.title,
    required this.message,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: _spellGold.withOpacity(0.3)),
      ),
      title: Text(title,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
      content: Text(message,
          style: const TextStyle(color: Colors.white70)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel',
              style: TextStyle(color: Colors.white.withOpacity(0.4))),
        ),
        TextButton(
          onPressed: onConfirm,
          child: Text('Confirm',
              style: TextStyle(color: _spellGold, fontWeight: FontWeight.w800)),
        ),
      ],
    );
  }
}

// ============================================================
// Background Widgets (self-contained, mirrors lobby_screen.dart style)
// ============================================================
class _SpellParticles extends StatelessWidget {
  final AnimationController controller;
  const _SpellParticles({required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) => CustomPaint(
        painter: _SpellParticlePainter(controller.value),
        size: MediaQuery.of(context).size,
      ),
    );
  }
}

class _SpellParticlePainter extends CustomPainter {
  final double t;
  _SpellParticlePainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width == 0 || size.height == 0) return;
    final rng = math.Random(42);
    for (int i = 0; i < 28; i++) {
      final x     = rng.nextDouble() * size.width;
      final baseY = rng.nextDouble() * size.height;
      final speed = 0.4 + rng.nextDouble() * 1.2;
      final y     = (baseY - t * size.height * speed) % size.height;
      final rad   = 1.0 + rng.nextDouble() * 2.2;
      final op    = 0.08 + rng.nextDouble() * 0.22;
      canvas.drawCircle(
        Offset(x, y), rad,
        Paint()
          ..color = (rng.nextBool() ? _spellGold : AppColors.neonPink)
              .withOpacity(op),
      );
    }
  }

  @override
  bool shouldRepaint(_SpellParticlePainter o) => o.t != t;
}

class _SpellGrid extends StatelessWidget {
  const _SpellGrid();

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _SpellGridPainter(),
    size: MediaQuery.of(context).size,
  );
}

class _SpellGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = _spellGold.withOpacity(0.03)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 38) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (double y = 0; y < size.height; y += 38) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter o) => false;
}