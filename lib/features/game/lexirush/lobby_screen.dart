// ============================================================
// FILE: lib/features/game/lexirush/lobby_screen.dart
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math' as math;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:flutter_tts/flutter_tts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_client.dart';
import '../../../routes/app_routes.dart';

class LobbyScreen extends StatefulWidget {
  final String roomCode;
  final bool isAdmin;

  const LobbyScreen({
    super.key,
    required this.roomCode,
    required this.isAdmin,
  });

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen>
    with TickerProviderStateMixin {

  late AnimationController _particleController;
  late AnimationController _pulseController;

  IO.Socket? _socket;

  // ── State ────────────────────────────────────────────────
  Map<String, dynamic>? _roomData;
  Map<String, dynamic>? _currentUser;
  bool _isLoading = true;
  bool _isCopied = false;
  bool _isGeneratingPDF = false;

  // Room settings (admin only)
  String _selectedBranch   = 'CSE';
  String _selectedSection  = 'A';
  String _selectedSemester = '1';
  String _roomName         = 'CSE_SecA_1_';

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
      final userId   = prefs.getString('userId') ?? '';
      final userName = prefs.getString('userName') ?? 'Player';
      final avatar   = prefs.getString('avatar') ?? '';
      final role     = prefs.getString('role') ?? 'student';

      // Try fetching fresh user data
      int userLevel = 1;
      try {
        final res = await ApiClient.get('/auth/$userId');
        if (res.statusCode == 200) {
          // parse level if available
        }
      } catch (_) {}

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
      debugPrint('Lobby init error: $e');
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
      debugPrint('✅ Socket connected');
      _socket!.emit('joinRoom', {
        'roomCode' : widget.roomCode.toUpperCase(),
        'userId'   : userId,
        'name'     : name,
        'avatar'   : avatar,
        'level'    : level,
        'isAdmin'  : widget.isAdmin,
      });
    });

    // ── roomData — main state update ──
    _socket!.on('roomData', (data) {
      if (!mounted) return;
      final d = Map<String, dynamic>.from(data as Map);
      setState(() {
        _roomData  = d;
        _isLoading = false;
      });

      // Sync room name dropdowns
      final incomingName = d['roomName'] as String? ?? '';
      if (incomingName.isNotEmpty &&
          incomingName != widget.roomCode.toUpperCase()) {
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

      if (d['gameSettings'] != null) {
        // level/timeLimit could be applied if needed
      }
    });

    _socket!.on('gameStarted', (data) {
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, AppRoutes.game, arguments: {
        'roomCode': widget.roomCode,
        'isAdmin': widget.isAdmin,
        'data': data,
      });
    });

    // ── gamePrepared — PDF ready ──
    _socket!.on('gamePrepared', (data) {
      if (!mounted) return;
      setState(() => _isGeneratingPDF = false);
      _showSnack('PDF prepared! Download from web client.', color: AppColors.neonGreen);
    });

    // ── playerKicked ──
    _socket!.on('playerKicked', (kickedUserId) {
      if (!mounted) return;
      final myId = _currentUser?['id'] ?? '';
      if (kickedUserId == myId) {
        _showKickedDialog();
      }
    });

    // ── roomClosed ──
    _socket!.on('roomClosed', (_) {
      if (!mounted) return;
      _showRoomClosedDialog();
    });

    // ── reconnectGame ──
    _socket!.on('reconnectGame', (data) {
      if (!mounted) return;
      // TODO: Navigate to game screen with reconnect data
      debugPrint('Reconnect: $data');
    });

    // ── pdfError ──
    _socket!.on('pdfError', (msg) {
      if (!mounted) return;
      setState(() => _isGeneratingPDF = false);
      _showSnack(msg.toString(), color: AppColors.neonRed);
    });

    // ── error ──
    _socket!.on('error', (msg) {
      if (!mounted) return;
      setState(() => _isGeneratingPDF = false);
      _showSnack(msg.toString(), color: AppColors.neonRed);
    });
  }

  // ── Socket emitters ──────────────────────────────────────
  void _handleUpdateSettings() {
    _socket?.emit('updateSettings', {
      'roomCode': widget.roomCode.toUpperCase(),
      'settings': {
        'roomName'            : _roomName,
        'level'               : 1,
        'timeLimitPerQuestion': 15,
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

  void _handleGeneratePDF() {
    setState(() => _isGeneratingPDF = true);
    _handleUpdateSettings();
    _socket?.emit('prepareGame', {'roomCode': widget.roomCode.toUpperCase()});
  }

  void _handleStudentDownloadPDF() {
    setState(() => _isGeneratingPDF = true);
    _socket?.emit('requestPDFData', {'roomCode': widget.roomCode.toUpperCase()});
  }

  void _handleStartMatch() {
    _socket?.emit('startGame', {
      'roomCode': widget.roomCode.toUpperCase(),
      'adminId' : _currentUser?['id'],
      'roomName': _roomName,
    });
  }

  void _handleCopyCode() async {
    await Clipboard.setData(ClipboardData(text: widget.roomCode));
    setState(() => _isCopied = true);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _isCopied = false);
  }

  void _handleExitRoom() {
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
        title: 'Kick Player?',
        message: 'Remove this player from the arena?',
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

  void _showRoomClosedDialog() {
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
        content: const Text('This arena has been terminated by the Host.',
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

  // ── Computed ─────────────────────────────────────────────
  bool get _isMeHost {
    final actualHostId = _roomData?['host'] as String?;
    return widget.isAdmin || (actualHostId == _currentUser?['id']);
  }

  bool get _isPrepared => _roomData?['isPrepared'] == true;
  bool get _isCustom   => (_roomData?['gameSettings']?['isCustom']) == true;

  List<dynamic> get _players => (_roomData?['players'] as List?) ?? [];

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
          _CyberParticles(controller: _particleController),
          const _CyberGrid(),
          SafeArea(
            child: Column(
              children: [
                _buildTopBar(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        const SizedBox(height: 20),
                        _buildRoomHeader(),
                        const SizedBox(height: 16),
                        _buildSettingsBar(),
                        const SizedBox(height: 20),
                        _buildPlayersSection(),
                        const SizedBox(height: 30),
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
          const _CyberGrid(),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 70,
                  height: 70,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.neonPurple),
                  ),
                ),
                const SizedBox(height: 24),
                ShaderMask(
                  shaderCallback: (b) => const LinearGradient(
                    colors: [AppColors.neonPurple, AppColors.neonCyan],
                  ).createShader(b),
                  child: const Text(
                    'ENTERING ARENA...',
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
                  'Synchronizing secure data',
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
          // Logo
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: AppColors.neonPurple,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.rocket_launch_rounded,
                color: Colors.white, size: 18),
          ),
          const SizedBox(width: 8),
          const Text('LEXIRUSH',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 16,
              letterSpacing: 1.5,
            ),
          ),

          const Spacer(),

          // LIVE badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.neonPurple.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.neonPurple.withOpacity(0.4)),
            ),
            child: Row(
              children: [
                Container(
                  width: 6, height: 6,
                  decoration: BoxDecoration(
                    color: AppColors.neonPurple,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                const Text('LIVE ROOM',
                  style: TextStyle(
                    color: AppColors.neonPurple,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 10),

          // Exit button
          GestureDetector(
            onTap: _handleExitRoom,
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

  // ── ROOM HEADER ─────────────────────────────────────────
  Widget _buildRoomHeader() {
    return Column(
      children: [
        // Room name
        AnimatedBuilder(
          animation: _pulseController,
          builder: (_, child) => Opacity(
            opacity: 0.8 + 0.2 * _pulseController.value,
            child: child,
          ),
          child: Text(
            _roomName,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 20,
              letterSpacing: 1,
            ),
          ),
        ),

        const SizedBox(height: 14),

        // Copy code button
        GestureDetector(
          onTap: _handleCopyCode,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: _isCopied
                  ? AppColors.neonGreen.withOpacity(0.15)
                  : Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _isCopied
                    ? AppColors.neonGreen.withOpacity(0.5)
                    : Colors.white.withOpacity(0.1),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _isCopied ? Icons.check_circle_outline : Icons.copy_rounded,
                  color: _isCopied ? AppColors.neonGreen : Colors.white,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Text(
                  _isCopied
                      ? 'COPIED!'
                      : 'COPY CODE: ${widget.roomCode}',
                  style: TextStyle(
                    color: _isCopied ? AppColors.neonGreen : Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── SETTINGS BAR ────────────────────────────────────────
  Widget _buildSettingsBar() {
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
          // Arena designation label
          Text('Arena Designation',
            style: TextStyle(
              color: Colors.white.withOpacity(0.4),
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 10),

          // Dropdowns row
          Row(
            children: [
              // Branch
              Expanded(
                flex: 3,
                child: _buildDropdown(
                  value: _selectedBranch,
                  items: _branchOptions,
                  onChanged: _isMeHost ? _handleBranchChange : null,
                ),
              ),
              const SizedBox(width: 8),
              // Section
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
              // Semester
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

          const SizedBox(height: 14),

          // PDF + Start buttons
          Row(
            children: [
              // PDF button
              Expanded(child: _buildPDFButton()),
              const SizedBox(width: 10),
              // Start button
              Expanded(flex: 2, child: _buildStartButton()),
            ],
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
              ? AppColors.neonPurple.withOpacity(0.3)
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

  Widget _buildPDFButton() {
    if (_isMeHost) {
      return GestureDetector(
        onTap: _isGeneratingPDF ? null : _handleGeneratePDF,
        child: Container(
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.neonGreen.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.neonGreen.withOpacity(0.5)),
          ),
          child: Center(
            child: _isGeneratingPDF
                ? SizedBox(
              width: 16, height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.neonGreen),
            )
                : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.download_rounded,
                    color: AppColors.neonGreen, size: 16),
                const SizedBox(width: 4),
                Text('PDF',
                  style: TextStyle(
                    color: AppColors.neonGreen,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } else if (_isPrepared) {
      return GestureDetector(
        onTap: _isGeneratingPDF ? null : _handleStudentDownloadPDF,
        child: Container(
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.neonPurple.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.neonPurple.withOpacity(0.5)),
          ),
          child: Center(
            child: _isGeneratingPDF
                ? SizedBox(
              width: 16, height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.neonPurple),
            )
                : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.download_rounded,
                    color: AppColors.neonPurple, size: 16),
                const SizedBox(width: 4),
                Text('PDF',
                  style: TextStyle(
                    color: AppColors.neonPurple,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      return Container(
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.03),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: Center(
          child: Text('Waiting...',
            style: TextStyle(
              color: Colors.white.withOpacity(0.25),
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
        ),
      );
    }
  }

  Widget _buildStartButton() {
    final canStart = _isMeHost && (_isPrepared || _isCustom);

    return GestureDetector(
      onTap: canStart ? _handleStartMatch : null,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          gradient: canStart
              ? const LinearGradient(
            colors: [Color(0xFFD946EF), Color(0xFF7B2FE0)],
          )
              : null,
          color: canStart ? null : AppColors.bgSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: canStart
                ? Colors.transparent
                : Colors.white.withOpacity(0.06),
          ),
          boxShadow: canStart
              ? [BoxShadow(
            color: const Color(0xFFD946EF).withOpacity(0.35),
            blurRadius: 16,
            offset: const Offset(0, 4),
          )]
              : [],
        ),
        child: Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _isMeHost ? Icons.play_arrow_rounded : Icons.hourglass_empty_rounded,
                color: canStart ? Colors.white : Colors.white30,
                size: 18,
              ),
              const SizedBox(width: 6),
              Text(
                _isMeHost
                    ? (_isCustom
                    ? 'Launch Custom'
                    : (_isPrepared ? 'START MATCH' : 'Generate PDF First'))
                    : 'Waiting for Host',
                style: TextStyle(
                  color: canStart ? Colors.white : Colors.white30,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── PLAYERS SECTION ─────────────────────────────────────
  Widget _buildPlayersSection() {
    final players = _players;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Players Joined',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text('Waiting for players...',
                  style: TextStyle(
                    color: AppColors.neonPurple,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
            RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: '${players.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 28,
                    ),
                  ),
                  TextSpan(
                    text: ' / 100',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.3),
                      fontWeight: FontWeight.w700,
                      fontSize: 20,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),

        // Player grid
        players.isEmpty
            ? _buildEmptySlots()
            : GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.3,
          ),
          itemCount: players.length + 1, // +1 for open slot indicator
          itemBuilder: (context, index) {
            if (index < players.length) {
              return _buildPlayerCard(
                  Map<String, dynamic>.from(players[index] as Map));
            }
            return _buildOpenSlot();
          },
        ),
      ],
    );
  }

  Widget _buildEmptySlots() {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.3,
      children: List.generate(4, (_) => _buildOpenSlot()),
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
    final name = player['name'] as String? ?? 'Player';
    final level = player['level'] ?? 1;

    return Stack(
      children: [
        Container(
          decoration: BoxDecoration(
            gradient: isOffline
                ? null
                : LinearGradient(
              colors: [
                const Color(0xFF1a1530),
                AppColors.bgCard,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            color: isOffline ? Colors.black87 : null,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isOffline
                  ? AppColors.neonRed.withOpacity(0.3)
                  : AppColors.neonPurple.withOpacity(0.3),
            ),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Avatar
                  Container(
                    width: 42, height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.bgSurface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isOffline
                            ? AppColors.neonRed
                            : AppColors.neonPurple.withOpacity(0.5),
                        width: 1.5,
                      ),
                    ),
                    child: avatarUrl.isNotEmpty
                        ? ClipRRect(
                      borderRadius: BorderRadius.circular(9),
                      child: Image.network(avatarUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Icon(
                            Icons.person_rounded,
                            color: AppColors.neonPurple,
                            size: 24,
                          )),
                    )
                        : Icon(Icons.person_rounded,
                        color: AppColors.neonPurple, size: 24),
                  ),

                  // Level badge (not for host)
                  if (!isHost)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: isOffline
                            ? AppColors.neonRed.withOpacity(0.1)
                            : Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isOffline
                              ? AppColors.neonRed.withOpacity(0.3)
                              : Colors.white.withOpacity(0.1),
                        ),
                      ),
                      child: Text('LVL $level',
                        style: TextStyle(
                          color: isOffline
                              ? AppColors.neonRed
                              : Colors.white70,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                ],
              ),

              const Spacer(),

              // Name
              Text(name,
                style: TextStyle(
                  color: isOffline ? Colors.white30 : Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  decoration: isOffline ? TextDecoration.lineThrough : null,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),

              const SizedBox(height: 3),

              // Status
              Row(
                children: [
                  Container(
                    width: 6, height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isOffline
                          ? AppColors.neonRed
                          : (isHost ? const Color(0xFFFFC107) : AppColors.neonGreen),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    isOffline ? 'OFFLINE' : (isHost ? 'HOST' : 'READY'),
                    style: TextStyle(
                      color: isOffline
                          ? AppColors.neonRed
                          : (isHost ? const Color(0xFFFFC107) : AppColors.neonGreen),
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                    ),
                  ),
                  if (isHost) const Text(' 👑', style: TextStyle(fontSize: 10)),
                ],
              ),
            ],
          ),
        ),

        // Kick button
        if (canKick)
          Positioned(
            bottom: 8, right: 8,
            child: GestureDetector(
              onTap: () => _handleKickPlayer(player['userId'] as String),
              child: Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  color: AppColors.neonRed.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.neonRed.withOpacity(0.4)),
                ),
                child: Icon(Icons.person_remove_rounded,
                    color: AppColors.neonRed, size: 14),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildOpenSlot() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgCard.withOpacity(0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withOpacity(0.06),
          style: BorderStyle.solid,
          width: 1,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.add_circle_outline_rounded,
              color: Colors.white.withOpacity(0.15), size: 24),
          const SizedBox(height: 6),
          Text('Open Slot',
            style: TextStyle(
              color: Colors.white.withOpacity(0.15),
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
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
        side: BorderSide(color: AppColors.neonPurple.withOpacity(0.3)),
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
              style: TextStyle(color: AppColors.neonPurple, fontWeight: FontWeight.w800)),
        ),
      ],
    );
  }
}

// ============================================================
// Background Widgets
// ============================================================
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
    final rng = math.Random(99);
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
          ..color = (rng.nextBool() ? AppColors.neonCyan : AppColors.neonPurple)
              .withOpacity(op),
      );
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
      ..color = AppColors.neonPurple.withOpacity(0.035)
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