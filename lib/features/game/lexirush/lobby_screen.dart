import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math' as math;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../../../core/util/pdf_generator.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_client.dart';
import 'game_screen.dart';
import '../../../routes/app_routes.dart';
import 'dart:ui';

// --- Theme Colors ---
const Color _bgMain = Color(0xFF0B0914);
const Color _bgSidebar = Color(0xFF120F1D);
const Color _bgContent = Color(0xFF0F0C1B);
const Color _bgCard = Color(0xFF131022);
const Color _fuchsia = Color(0xFFD946EF);
const Color _purpleMid = Color(0xFFA855F7);
const Color _cyan = Color(0xFF22D3EE);
const Color _emerald = Color(0xFF34D399);

class LobbyScreen extends StatefulWidget {
  final String roomCode;
  final bool isAdmin;

  const LobbyScreen({super.key, required this.roomCode, required this.isAdmin});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen>
    with TickerProviderStateMixin {
  late AnimationController _spinnerController;

  IO.Socket? _socket;

  // ── State ────────────────────────────────────────────────
  Map<String, dynamic>? _roomData;
  Map<String, dynamic>? _currentUser;
  bool _isLoading = true;
  bool _isCopied = false;
  bool _isGeneratingPDF = false;

  // Room settings (admin only)
  String _selectedBranch = 'CSE';
  String _selectedSection = 'A';
  String _selectedSemester = '1';
  String _roomName = 'CSE_SecA_1_';

  final List<String> _branchOptions = [
    'CSE',
    'IT',
    'CS',
    'CSIT',
    'CSE-AI',
    'CSE-AIML',
    'ECE',
    'ELCE',
    'EEE',
    'ME',
    'CSDS',
    'CS-CYBER-SECURITY',
  ];
  final List<String> _sectionOptions = ['A', 'B', 'C', 'D', 'E'];
  final List<String> _semesterOptions = [
    '1',
    '2',
    '3',
    '4',
    '5',
    '6',
    '7',
    '8',
  ];

  bool _isDisposing = false;

  final int maxPlayers = 100;

  @override
  void initState() {
    super.initState();

    _roomName = 'CSE_SecA_1_${widget.roomCode}';

    _spinnerController = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    )..repeat();

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
    _isDisposing = true;
    _socket?.disconnect();
    _socket?.dispose();
    _spinnerController.dispose();
    super.dispose();
  }

  // ── Init: load user → connect socket ────────────────────
  Future<void> _initLobby() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String userId = prefs.getString('userId') ?? '';
      final userName =
          prefs.getString('username') ?? prefs.getString('userName') ?? 'Admin';
      final avatar =
          prefs.getString('avatar') ??
          'https://api.dicebear.com/7.x/avataaars/png?seed=$userName';
      final role = prefs.getString('role') ?? 'student';

      if (userId.isEmpty && widget.isAdmin) {
        userId = 'admin_${DateTime.now().millisecondsSinceEpoch}';
      }

      int userLevel = 1;
      if (userId.isNotEmpty && !userId.startsWith('admin_')) {
        ApiClient.get('/auth/$userId')
            .then((res) {
              if (res.statusCode == 200) {
                // parse level and update later if needed
              }
            })
            .catchError((_) {});
      }

      setState(() {
        _currentUser = {
          'id': userId,
          'name': userName,
          'avatar': avatar,
          'level': userLevel,
          'role': role,
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
      ApiClient.socketUrl,
      IO.OptionBuilder()
          .setTransports(['websocket', 'polling'])
          .enableForceNew()
          .disableAutoConnect()
          .build(),
    );

    _socket!.connect();

    _socket!.onConnect((_) {
      _socket!.emit('joinRoom', {
        'roomCode': widget.roomCode.toUpperCase(),
        'userId': userId,
        'name': name,
        'avatar': avatar,
        'level': level,
        'isAdmin': widget.isAdmin,
        'role': _currentUser?['role'] ?? 'student',
      });
    });

    _socket!.onConnectError((err) {
      if (mounted && !_isDisposing) {
        setState(() => _isLoading = false);
        _showSnack('Connection failed: $err', isError: true);
      }
    });

    _socket!.onDisconnect((_) {
      if (mounted && !_isDisposing) {
        setState(() => _isLoading = false);
      }
    });

    _socket!.on('roomData', (data) {
      if (!mounted || _isDisposing) return;
      final d = Map<String, dynamic>.from(data as Map);
      setState(() {
        _roomData = d;
        _isLoading = false;
      });

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
    });

    _socket!.on('gameStarted', (data) {
      if (!mounted || _isDisposing) return;
      Navigator.pushReplacementNamed(
        context,
        AppRoutes.game,
        arguments: {
          'roomCode': widget.roomCode,
          'isAdmin': widget.isAdmin,
          'data': data,
        },
      );
    });

    _socket!.on('gamePrepared', (data) async {
      if (!mounted || _isDisposing) return;
      setState(() => _isGeneratingPDF = false);
      _showSnack('PDF prepared! Generating document...');

      try {
        final rawData = data is List ? data.first : data;
        final d = Map<String, dynamic>.from(rawData as Map);
        final pdfData = d['pdfData'] as List<dynamic>? ?? [];
        final roomName = d['pdfRoomName']?.toString() ?? widget.roomCode;
        final level = d['pdfLevel']?.toString() ?? 'Unknown';

        if (pdfData.isEmpty) {
          _showSnack('No PDF data received.', isError: true);
          return;
        }

        await PdfGenerator.generateAndDownloadPdf(
          context: context,
          pdfData: pdfData,
          roomCode: roomName,
          level: level,
        );
      } catch (e) {
        _showSnack('Failed to generate PDF', isError: true);
      }
    });

    _socket!.on('pdfError', (msg) {
      if (!mounted || _isDisposing) return;
      setState(() => _isGeneratingPDF = false);
      _showSnack(msg.toString(), isError: true);
    });

    _socket!.on('playerKicked', (kickedUserId) {
      if (!mounted || _isDisposing) return;
      final myId = _currentUser?['id'] ?? '';
      if (kickedUserId == myId) {
        _showKickedDialog();
      }
    });

    _socket!.on('roomClosed', (_) {
      if (!mounted || _isDisposing) return;
      _showRoomClosedDialog();
    });

    _socket!.on('reconnectGame', (data) {
      if (!mounted || _isDisposing) return;
      final d = Map<String, dynamic>.from(data as Map);
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => GameScreen(
            roomCode: widget.roomCode,
            isAdmin: widget.isAdmin,
            initialState: {
              'reconnectData': d,
              'gridBase': d['gridBase'],
              'fullQuestionData': d['fullQuestionData'],
            },
          ),
        ),
      );
    });

    _socket!.on('error', (msg) {
      if (!mounted || _isDisposing) return;
      setState(() {
        _isGeneratingPDF = false;
        _isLoading = false;
      });
      final msgStr = msg.toString();
      if (msgStr.toLowerCase().contains('not found') ||
          msgStr.toLowerCase().contains('expired')) {
        _showSnack(msgStr, isError: true);
        Navigator.pop(context);
      } else {
        _showSnack(msgStr, isError: true);
      }
    });
  }

  // ── Socket emitters ──────────────────────────────────────
  void _handleUpdateSettings() {
    _socket?.emit('updateSettings', {
      'roomCode': widget.roomCode.toUpperCase(),
      'settings': {
        'roomName': _roomName,
        'level': 1,
        'timeLimitPerQuestion': 15,
      },
    });
  }

  void _handleBranchChange(String? val) {
    if (val == null) return;
    setState(() {
      _selectedBranch = val;
      _roomName =
          '${val}_Sec${_selectedSection}_${_selectedSemester}_${widget.roomCode}';
    });
    _handleUpdateSettings();
  }

  void _handleSectionChange(String? val) {
    if (val == null) return;
    setState(() {
      _selectedSection = val;
      _roomName =
          '${_selectedBranch}_Sec${val}_${_selectedSemester}_${widget.roomCode}';
    });
    _handleUpdateSettings();
  }

  void _handleSemesterChange(String? val) {
    if (val == null) return;
    setState(() {
      _selectedSemester = val;
      _roomName =
          '${_selectedBranch}_Sec${_selectedSection}_${val}_${widget.roomCode}';
    });
    _handleUpdateSettings();
  }

  void _handleGeneratePDF() {
    setState(() => _isGeneratingPDF = true);
    _handleUpdateSettings();
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted && !_isDisposing) {
        _socket?.emit('prepareGame', {
          'roomCode': widget.roomCode.toUpperCase(),
        });
      }
    });

    Future.delayed(const Duration(seconds: 45), () {
      if (mounted && _isGeneratingPDF) {
        setState(() => _isGeneratingPDF = false);
        _showSnack(
          'PDF Generation timed out. Please try again.',
          isError: true,
        );
      }
    });
  }

  void _handleStudentDownloadPDF() {
    setState(() => _isGeneratingPDF = true);
    _socket?.emit('requestPDFData', {
      'roomCode': widget.roomCode.toUpperCase(),
    });

    Future.delayed(const Duration(seconds: 45), () {
      if (mounted && _isGeneratingPDF) {
        setState(() => _isGeneratingPDF = false);
        _showSnack('PDF Request timed out. Please try again.', isError: true);
      }
    });
  }

  void _handleStartMatch() {
    _socket?.emit('startGame', {
      'roomCode': widget.roomCode.toUpperCase(),
      'adminId': _currentUser?['id'],
      'roomName': _roomName,
    });
  }

  void _handleCopyCode() async {
    await Clipboard.setData(ClipboardData(text: widget.roomCode));
    setState(() => _isCopied = true);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted && !_isDisposing) setState(() => _isCopied = false);
  }

  void _handleExitRoom() {
    showDialog(
      context: context,
      builder: (_) => _ConfirmDialog(
        title: 'Exit Lobby?',
        message: 'Are you sure you want to exit the arena?',
        onConfirm: () {
          _socket?.emit('leaveRoom', {
            'roomCode': widget.roomCode.toUpperCase(),
          });
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
            'roomCode': widget.roomCode.toUpperCase(),
            'targetUserId': targetUserId,
            'adminId': _currentUser?['id'],
          });
          Navigator.pop(context);
        },
      ),
    );
  }

  // ── Dialogs / Snacks ─────────────────────────────────────
  void _showSnack(String msg, {bool isError = false}) {
    final color = isError ? Colors.redAccent : _emerald;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: color.withOpacity(0.15),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: color.withOpacity(0.5)),
        ),
        behavior: SnackBarBehavior.floating,
        content: Text(
          msg,
          style: TextStyle(color: color, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  void _showKickedDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: _bgCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.redAccent.withOpacity(0.5)),
        ),
        title: const Text(
          'Kicked!',
          style: TextStyle(
            color: Colors.redAccent,
            fontWeight: FontWeight.w900,
          ),
        ),
        content: const Text(
          'You have been removed from the arena by the Admin.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text('OK', style: TextStyle(color: _fuchsia)),
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
        backgroundColor: _bgCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.redAccent.withOpacity(0.5)),
        ),
        title: const Text(
          'Arena Closed',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
        ),
        content: const Text(
          'This arena has been terminated by the Host.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text('OK', style: TextStyle(color: _fuchsia)),
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
  bool get _isCustom => (_roomData?['gameSettings']?['isCustom']) == true;

  List<dynamic> get _players {
    final serverPlayers = (_roomData?['players'] as List?) ?? [];
    if (_currentUser == null) return serverPlayers;

    final myId = _currentUser!['id'];
    final bool amIThere = serverPlayers.any(
      (p) => p['userId'] == myId || p['id'] == myId,
    );

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

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 768; // md breakpoint

        return Scaffold(
          backgroundColor: _bgMain,
          drawer: !isDesktop ? _buildSidebar(isDrawer: true) : null,
          body: Row(
            children: [
              if (isDesktop) _buildSidebar(isDrawer: false),
              Expanded(
                child: Container(
                  color: _bgContent,
                  child: SafeArea(
                    child: Column(
                      children: [
                        // Header inside main content
                        _buildHeader(isDesktop),

                        // Main Scrollable Area
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 24,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                _buildRoomHeader(),
                                const SizedBox(height: 40),

                                // Max width container for contents
                                Center(
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 1280,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        _buildSettingsBar(isDesktop),
                                        const SizedBox(height: 40),
                                        _buildPlayersSection(isDesktop),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Loading ──────────────────────────────────────────────
  Widget _buildLoadingScreen() {
    return Scaffold(
      backgroundColor: _bgMain,
      body: Stack(
        children: [
          // Purple glow
          Positioned(
            top: MediaQuery.of(context).size.height * 0.2,
            left: MediaQuery.of(context).size.width * 0.2,
            child: Container(
              width: MediaQuery.of(context).size.width * 0.3,
              height: MediaQuery.of(context).size.height * 0.3,
              decoration: BoxDecoration(
                color: _purpleMid.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
            ).blurred(100),
          ),
          // Cyan glow
          Positioned(
            bottom: MediaQuery.of(context).size.height * 0.2,
            right: MediaQuery.of(context).size.width * 0.2,
            child: Container(
              width: MediaQuery.of(context).size.width * 0.3,
              height: MediaQuery.of(context).size.height * 0.3,
              decoration: BoxDecoration(
                color: _cyan.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
            ).blurred(100),
          ),

          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Custom animated spinner
                RotationTransition(
                  turns: _spinnerController,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: _bgCard, width: 4),
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: const Border(
                          top: BorderSide(color: _purpleMid, width: 4),
                          right: BorderSide(color: _cyan, width: 4),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: _purpleMid.withOpacity(0.5),
                            blurRadius: 30,
                            spreadRadius: 0,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                // Pulsing title
                ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [_purpleMid, _cyan],
                  ).createShader(bounds),
                  child: const Text(
                    'ENTERING ARENA...',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 4,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Synchronizing secure data',
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
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

  // ── SIDEBAR ─────────────────────────────────────────────
  Widget _buildSidebar({required bool isDrawer}) {
    final currentUser = _currentUser!;
    final name = currentUser['name'];
    final avatar = currentUser['avatar'];
    final level = currentUser['level'];
    final role = (currentUser['role'] as String).toUpperCase();

    Widget content = Container(
      width: isDrawer ? 280 : 256, // w-64 is 256px
      color: _bgSidebar,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Logo Area
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 32, 32, 16),
            child: Text(
              'LEXIRUSH',
              style: TextStyle(
                color: _fuchsia,
                fontSize: 24,
                fontWeight: FontWeight.w900,
                letterSpacing: 3,
                shadows: [
                  Shadow(color: _fuchsia.withOpacity(0.5), blurRadius: 15),
                ],
              ),
            ),
          ),

          // User Profile Card
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.03),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.05)),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF251E3E),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _purpleMid.withOpacity(0.5)),
                    image: DecorationImage(
                      image: NetworkImage(avatar),
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
                        name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'LVL $level • $role',
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Navigation Link (Lobby)
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1536),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFFC084FC).withOpacity(0.2),
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFC084FC).withOpacity(0.1),
                    blurRadius: 15,
                  ),
                ],
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.groups_rounded,
                    color: Color(0xFFC084FC),
                    size: 20,
                  ),
                  SizedBox(width: 16),
                  Text(
                    'Lobby',
                    style: TextStyle(
                      color: Color(0xFFC084FC),
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const Spacer(),

          // Exit Button
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: Colors.white.withOpacity(0.05)),
              ),
            ),
            child: InkWell(
              onTap: _handleExitRoom,
              borderRadius: BorderRadius.circular(12),
              hoverColor: Colors.redAccent.withOpacity(0.1),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Icon(Icons.logout_rounded, color: Colors.grey, size: 20),
                    SizedBox(width: 16),
                    Text(
                      'Exit Room',
                      style: TextStyle(
                        color: Colors.grey,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );

    if (isDrawer) {
      return Drawer(
        backgroundColor: _bgSidebar,
        child: SafeArea(child: content),
      );
    }
    return Container(
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: Colors.white.withOpacity(0.05)),
        ),
      ),
      child: content,
    );
  }

  // ── HEADER INSIDE MAIN ──────────────────────────────────
  Widget _buildHeader(bool isDesktop) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              if (!isDesktop) ...[
                IconButton(
                  icon: const Icon(Icons.menu, color: Colors.white),
                  onPressed: () => Scaffold.of(context).openDrawer(),
                ),
                const SizedBox(width: 8),
              ],
              Container(
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: _purpleMid, width: 2),
                  ),
                ),
                padding: const EdgeInsets.only(bottom: 4),
                child: const Text(
                  'LOBBY',
                  style: TextStyle(
                    color: Color(0xFFC084FC),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                  ),
                ),
              ),
            ],
          ),
          if (_currentUser != null)
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF251E3E),
                border: Border.all(color: _purpleMid),
                image: DecorationImage(
                  image: NetworkImage(_currentUser!['avatar']),
                  fit: BoxFit.cover,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── ROOM HEADER (Center) ────────────────────────────────
  Widget _buildRoomHeader() {
    return Column(
      children: [
        // Live Room Badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF4C1D95).withOpacity(0.4), // purple-900/40
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _purpleMid.withOpacity(0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Animated dot
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.5, end: 1.0),
                duration: const Duration(milliseconds: 800),
                curve: Curves.easeInOut,
                builder: (context, val, child) {
                  return Opacity(opacity: val, child: child);
                },
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Color(0xFFC084FC),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'LIVE ROOM',
                style: TextStyle(
                  color: Color(0xFFD8B4FE), // purple-300
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Room Name
        Text(
          _roomName.toUpperCase(),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: MediaQuery.of(context).size.width > 600 ? 60 : 36,
            fontWeight: FontWeight.w900,
            fontStyle: FontStyle.italic,
            letterSpacing: 3,
            shadows: [
              Shadow(color: Colors.white.withOpacity(0.2), blurRadius: 20),
            ],
          ),
        ),
        const SizedBox(height: 32),

        // Copy Code Button
        InkWell(
          onTap: _handleCopyCode,
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              color: _isCopied
                  ? _emerald.withOpacity(0.2)
                  : Colors.white.withOpacity(0.05),
              border: Border.all(
                color: _isCopied
                    ? _emerald.withOpacity(0.5)
                    : Colors.white.withOpacity(0.1),
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _isCopied ? Icons.check_circle_outline : Icons.copy_rounded,
                  color: _isCopied ? _emerald : Colors.white,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  _isCopied
                      ? 'COPIED TO CLIPBOARD!'
                      : 'COPY CODE: ${widget.roomCode}',
                  style: TextStyle(
                    color: _isCopied ? _emerald : Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
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
  Widget _buildSettingsBar(bool isDesktop) {
    Widget content = Container(
      decoration: BoxDecoration(
        color: _bgCard.withOpacity(0.8),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: isDesktop
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: _buildSettingsChildren(isDesktop),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _buildSettingsChildren(isDesktop),
            ),
    );
    return content;
  }

  List<Widget> _buildSettingsChildren(bool isDesktop) {
    return [
      // Dropdowns
      Expanded(
        flex: isDesktop ? 4 : 0,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'ARENA DESIGNATION',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  flex: 4,
                  child: _buildDropdown(
                    value: _selectedBranch,
                    items: _branchOptions,
                    onChanged: _isMeHost ? _handleBranchChange : null,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: _buildDropdown(
                    value: _selectedSection,
                    items: _sectionOptions,
                    onChanged: _isMeHost ? _handleSectionChange : null,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 4,
                  child: _buildDropdown(
                    value: _selectedSemester,
                    items: _semesterOptions,
                    prefix: 'Sem ',
                    onChanged: _isMeHost ? _handleSemesterChange : null,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      if (isDesktop) const SizedBox(width: 24) else const SizedBox(height: 24),

      // PDF Button
      Expanded(flex: isDesktop ? 3 : 0, child: _buildPDFButton()),
      if (isDesktop) const SizedBox(width: 24) else const SizedBox(height: 16),

      // Start Match Button
      Expanded(flex: isDesktop ? 4 : 0, child: _buildStartButton()),
    ];
  }

  Widget _buildDropdown({
    required String value,
    required List<String> items,
    String prefix = '',
    ValueChanged<String?>? onChanged,
  }) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          dropdownColor: _bgContent,
          icon: const Icon(
            Icons.keyboard_arrow_down,
            color: Colors.grey,
            size: 16,
          ),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
          items: items
              .map(
                (e) => DropdownMenuItem(
                  value: e,
                  child: Center(
                    child: Text('$prefix$e', overflow: TextOverflow.ellipsis),
                  ),
                ),
              )
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildPDFButton() {
    if (_isMeHost) {
      return InkWell(
        onTap: _isGeneratingPDF ? null : _handleGeneratePDF,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            color: _emerald.withOpacity(0.2),
            border: Border.all(color: _emerald),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: _isGeneratingPDF
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      color: _emerald,
                      strokeWidth: 2,
                    ),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.download_rounded, color: _emerald, size: 16),
                      SizedBox(width: 8),
                      Text(
                        'MISSION PDF',
                        style: TextStyle(
                          color: _emerald,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      );
    } else if (_isPrepared) {
      return InkWell(
        onTap: _isGeneratingPDF ? null : _handleStudentDownloadPDF,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            color: _purpleMid.withOpacity(0.2),
            border: Border.all(color: _purpleMid),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(color: _purpleMid.withOpacity(0.2), blurRadius: 15),
            ],
          ),
          child: Center(
            child: _isGeneratingPDF
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      color: _purpleMid,
                      strokeWidth: 2,
                    ),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.download_rounded, color: _purpleMid, size: 16),
                      SizedBox(width: 8),
                      Text(
                        'DOWNLOAD PDF',
                        style: TextStyle(
                          color: Color(0xFFD8B4FE),
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      );
    } else {
      return const Center(
        child: Text(
          'WAITING FOR HOST CONFIG...',
          style: TextStyle(
            color: Colors.grey,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
          ),
        ),
      );
    }
  }

  Widget _buildStartButton() {
    final canStart = _isMeHost && (_isPrepared || _isCustom);

    return InkWell(
      onTap: canStart ? _handleStartMatch : null,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 56, // Slightly taller as per React py-4
        decoration: BoxDecoration(
          color: canStart ? null : const Color(0xFF1E1536),
          gradient: canStart
              ? const LinearGradient(colors: [_fuchsia, Color(0xFF9333EA)])
              : null,
          border: Border.all(color: Colors.white.withOpacity(0.05)),
          borderRadius: BorderRadius.circular(12),
          boxShadow: canStart
              ? [BoxShadow(color: _fuchsia.withOpacity(0.4), blurRadius: 20)]
              : null,
        ),
        child: Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _isMeHost
                    ? Icons.play_arrow_rounded
                    : Icons.hourglass_empty_rounded,
                color: canStart ? Colors.white : Colors.grey,
                size: 20,
              ),
              const SizedBox(width: 12),
              Text(
                _isMeHost
                    ? (_isCustom
                          ? 'LAUNCH CUSTOM'
                          : (_isPrepared
                                ? 'START MATCH'
                                : 'GENERATE PDF FIRST'))
                    : 'WAITING FOR HOST',
                style: TextStyle(
                  color: canStart ? Colors.white : Colors.grey,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── PLAYERS SECTION ─────────────────────────────────────
  Widget _buildPlayersSection(bool isDesktop) {
    final players = _players;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Container(
          padding: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Colors.white.withOpacity(0.05)),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'PLAYERS JOINED',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'WAITING FOR PLAYERS...',
                    style: TextStyle(
                      color: _purpleMid.withOpacity(0.8),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
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
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    TextSpan(
                      text: ' / $maxPlayers',
                      style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Grid
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: isDesktop ? 4 : 2,
            crossAxisSpacing: 24,
            mainAxisSpacing: 24,
            childAspectRatio: 4 / 3,
          ),
          itemCount: maxPlayers,
          itemBuilder: (context, index) {
            if (index < players.length) {
              return _buildPlayerCard(
                Map<String, dynamic>.from(players[index]),
              );
            }
            return _buildOpenSlot();
          },
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildPlayerCard(Map<String, dynamic> player) {
    final actualHostId = _roomData?['host'] as String?;
    final isHost =
        (player['isAdmin'] == true) ||
        (player['isHost'] == true) ||
        (player['userId'] == actualHostId);
    final isOffline = player['isOnline'] == false;
    final myId = _currentUser?['id'] ?? '';
    final canKick = _isMeHost && !isHost && player['userId'] != myId;

    final avatarUrl = player['avatar'] as String? ?? '';
    final name = player['name'] as String? ?? 'Player';
    final level = player['level'] ?? 1;

    return Container(
      decoration: BoxDecoration(
        color: isOffline ? Colors.black87 : null,
        gradient: isOffline
            ? null
            : const LinearGradient(
                colors: [Color(0xFF1A1530), _bgCard],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isOffline
              ? Colors.redAccent.withOpacity(0.3)
              : _purpleMid.withOpacity(0.3),
        ),
        boxShadow: isOffline
            ? null
            : [BoxShadow(color: _purpleMid.withOpacity(0.1), blurRadius: 15)],
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Avatar
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: const Color(0xFF251E3E),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isOffline ? Colors.redAccent : _bgCard,
                          width: 2,
                        ),
                        image: DecorationImage(
                          image: NetworkImage(avatarUrl),
                          fit: BoxFit.cover,
                          colorFilter: isOffline
                              ? const ColorFilter.mode(
                                  Colors.grey,
                                  BlendMode.saturation,
                                )
                              : null,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 4,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                    ),

                    // Level Badge
                    if (!isHost)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: isOffline
                              ? Colors.redAccent.withOpacity(0.1)
                              : Colors.white.withOpacity(0.05),
                          border: Border.all(
                            color: isOffline
                                ? Colors.redAccent.withOpacity(0.3)
                                : Colors.white.withOpacity(0.1),
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'LVL $level',
                          style: TextStyle(
                            color: isOffline
                                ? Colors.redAccent
                                : Colors.grey[300],
                            fontSize: 8,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                  ],
                ),
                const Spacer(),

                // Name
                Text(
                  name,
                  style: TextStyle(
                    color: isOffline ? Colors.grey : Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                    decoration: isOffline ? TextDecoration.lineThrough : null,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),

                // Status
                Row(
                  children: [
                    if (isOffline) ...[
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: Colors.redAccent,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        'OFFLINE',
                        style: TextStyle(
                          color: Colors.redAccent,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                        ),
                      ),
                    ] else if (isHost) ...[
                      const Text('👑', style: TextStyle(fontSize: 10)),
                      const SizedBox(width: 4),
                      const Text(
                        'HOST',
                        style: TextStyle(
                          color: Colors.amber,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                        ),
                      ),
                    ] else ...[
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: _emerald,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        'READY',
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),

          if (canKick)
            Positioned(
              bottom: 12,
              right: 12,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _handleKickPlayer(player['userId']),
                  borderRadius: BorderRadius.circular(8),
                  hoverColor: Colors.redAccent,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withOpacity(0.2),
                      border: Border.all(
                        color: Colors.redAccent.withOpacity(0.3),
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.person_remove_rounded,
                      color: Colors.redAccent,
                      size: 14,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOpenSlot() {
    return Container(
      decoration: BoxDecoration(
        color: _bgCard.withOpacity(0.5),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
          style: BorderStyle.none,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: CustomPaint(
        painter: _DashedBorderPainter(color: Colors.white.withOpacity(0.1)),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.add_circle_outline_rounded,
                color: Colors.grey.withOpacity(0.5),
                size: 24,
              ),
              const SizedBox(height: 8),
              Text(
                'OPEN SLOT',
                style: TextStyle(
                  color: Colors.grey.withOpacity(0.5),
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  final Color color;
  _DashedBorderPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    const dashWidth = 5.0;
    const dashSpace = 5.0;

    // Draw rounded rect with dashes
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(16));

    Path path = Path()..addRRect(rrect);

    Path dashPath = Path();
    for (PathMetric metric in path.computeMetrics()) {
      double distance = 0.0;
      while (distance < metric.length) {
        dashPath.addPath(
          metric.extractPath(distance, distance + dashWidth),
          Offset.zero,
        );
        distance += dashWidth;
        distance += dashSpace;
      }
    }

    canvas.drawPath(dashPath, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
      backgroundColor: _bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: _purpleMid.withOpacity(0.3)),
      ),
      title: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
        ),
      ),
      content: Text(message, style: const TextStyle(color: Colors.white70)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'Cancel',
            style: TextStyle(color: Colors.white.withOpacity(0.4)),
          ),
        ),
        TextButton(
          onPressed: onConfirm,
          child: const Text(
            'Confirm',
            style: TextStyle(color: _purpleMid, fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}

// Extension for blurring
extension BlurExtension on Widget {
  Widget blurred(double sigma) {
    return ImageFilterWidget(sigma: sigma, child: this);
  }
}

class ImageFilterWidget extends StatelessWidget {
  final double sigma;
  final Widget child;
  const ImageFilterWidget({
    super.key,
    required this.sigma,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
      child: child,
    );
  }
}
