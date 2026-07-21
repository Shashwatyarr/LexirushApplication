// ============================================================
// FILE: lib/features/game/spell_shooter/spell_game_screen.dart
//
// ⚠️ NEW DEPENDENCY REQUIRED — add to pubspec.yaml:
//     flutter_tts: ^4.0.2   (or latest)
// Used for the "Listen to the Winds" text-to-speech word prompt,
// same as window.speechSynthesis in the React version.
//
// NOTE: canvas-confetti (npm) has no direct Flutter equivalent
// package assumed available, so the success-celebration burst
// below is hand-rolled with a CustomPainter (no extra dependency
// needed beyond flutter_tts).
// ============================================================

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../../../core/constants/app_colors.dart';
import '../../leaderboard/screens/leaderboard_screen.dart';
import '../../auth/screens/player_login_screen.dart';
import '../../dashboard/students/student_dashboard.dart';
import '../../dashboard/admins/admin_dashboard.dart';
import '../../../routes/app_routes.dart';

// Local accent — kept consistent with spell_lobby_screen.dart
const Color _spellGold = Color(0xFFFFB020);

class SpellGameScreen extends StatefulWidget {
  final String roomCode;
  // Equivalent of React Router's location.state — pass these in
  // when you navigate here from spell_lobby_screen.dart.
  final List<Map<String, dynamic>>? fullQuestionData;
  final Map<String, dynamic>? reconnectData;

  const SpellGameScreen({
    super.key,
    required this.roomCode,
    this.fullQuestionData,
    this.reconnectData,
  });

  @override
  State<SpellGameScreen> createState() => _SpellGameScreenState();
}

class _SpellGameScreenState extends State<SpellGameScreen>
    with TickerProviderStateMixin {

  IO.Socket? _socket;
  Timer? _timer;
  final FlutterTts _tts = FlutterTts();

  late AnimationController _floatController;
  late AnimationController _confettiController;
  bool _showConfetti = false;

  // ── Layout ───────────────────────────────────────────────
  String _activeTab = 'arena'; // arena | leaderboard | questions

  // ── User ─────────────────────────────────────────────────
  String _userId = '';
  String _role = 'student';
  String _localName = 'Shooter';
  String _userAvatar = '';
  bool _ready = false;

  // ── Game State ───────────────────────────────────────────
  List<Map<String, dynamic>> _liveRanks = [];
  List<Map<String, dynamic>> _fullQuestions = [];
  Map<String, dynamic>? _currentQuestion;
  int _currentQuestionIndex = 0;
  int _timeLeft = 0;
  int _score = 0;
  int _streak = 0;
  bool _isLocked = false;
  String? _selectedAnswer;
  bool _isSpeaking = false;

  int _parseInt(dynamic val, [int defaultVal = 0]) {
    if (val is int) return val;
    if (val is double) return val.toInt();
    if (val != null) {
      return int.tryParse(val.toString()) ?? double.tryParse(val.toString())?.toInt() ?? defaultVal;
    }
    return defaultVal;
  }

  @override
  void initState() {
    super.initState();

    _floatController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat();

    _confettiController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _showConfetti = false);
        _confettiController.reset();
      }
    });

    _loadUserAndConnect();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _floatController.dispose();
    _confettiController.dispose();
    _tts.stop();
    _socket?.disconnect();
    _socket?.dispose();
    super.dispose();
  }

  // ── Init: load user, apply incoming nav data, connect socket ──
  Future<void> _loadUserAndConnect() async {
    final prefs = await SharedPreferences.getInstance();
    _userId   = prefs.getString('userId') ?? '';
    _role     = prefs.getString('role') ?? 'student';
    _localName = prefs.getString('name') ??
        prefs.getString('userName') ?? 'Shooter';
    _userAvatar = prefs.getString('userAvatar') ??
        prefs.getString('avatar') ?? '';
    if (_userAvatar.isEmpty) {
      _userAvatar = 'https://api.dicebear.com/7.x/avataaars/svg?seed=$_localName';
    }

    if (_userId.isEmpty) {
      Navigator.pushReplacementNamed(context, AppRoutes.login);
      return;
    }

    // Initial questions passed from the lobby on gameStarted
    if (widget.fullQuestionData != null && widget.fullQuestionData!.isNotEmpty) {
      _fullQuestions = List<Map<String, dynamic>>.from(widget.fullQuestionData!);
      _fullQuestions.shuffle();
      _currentQuestionIndex = 0;
      _currentQuestion = _fullQuestions[_currentQuestionIndex];
      _timeLeft = _parseInt(_currentQuestion!['timeLimit'], 7);
    }

    // Reconnect snapshot
    if (widget.reconnectData != null) {
      final r = widget.reconnectData!;
      _score = _parseInt(r['score'], 0);
      final cq = r['currentQuestion'];
      if (cq != null) {
        _currentQuestion = Map<String, dynamic>.from(cq as Map);
        _timeLeft = _parseInt(_currentQuestion!['timeLimit'], 7);
        _isLocked = r['answeredCurrent'] == true;
        if (_isLocked) _selectedAnswer = _currentQuestion!['answer'] as String?;
      }
      if (r['fullQuestionData'] != null) {
        _fullQuestions = List<Map<String, dynamic>>.from(
          (r['fullQuestionData'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
        );
        // Do not shuffle on reconnect, keep same order (or shuffle but it might disrupt them). We will just keep it.
        if (_currentQuestion != null) {
          _currentQuestionIndex = _fullQuestions.indexWhere((q) => q['_id'] == _currentQuestion!['_id']);
          if (_currentQuestionIndex == -1) _currentQuestionIndex = 0;
        }
      }
    }

    setState(() => _ready = true);

    _connectSocket();

    if (_currentQuestion != null) {
      _playAudio(_currentQuestion!['word'] as String?);
      _startTimer();
    }
  }

  // ── Socket connection ────────────────────────────────────
  void _connectSocket() {
    _socket = IO.io(
      'https://tambola-67o6.onrender.com',
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .enableForceNew()
          .disableAutoConnect()
          .build(),
    );

    _socket!.connect();

    _socket!.onConnect((_) {
      debugPrint('✅ Spell game socket connected');
      _socket!.emit('joinRoom', {
        'roomCode': widget.roomCode,
        'userId'  : _userId,
        'name'    : _localName,
        'avatar'  : _userAvatar,
        'isAdmin' : _isAdminOrSuper,
      });
      _socket!.emit('requestSync', {
        'roomCode': widget.roomCode,
        'userId'  : _userId,
      });
    });

    _socket!.on('error', (msg) {
      if (!mounted) return;
      _showErrorDialog('Arena Error', msg.toString());
    });

    _socket!.on('reconnectGame', (data) {
      if (!mounted) return;
      final d = Map<String, dynamic>.from(data as Map);
      setState(() {
        _score = _parseInt(d['score'], 0);
        final cq = d['currentQuestion'];
        if (cq != null) {
          _currentQuestion = Map<String, dynamic>.from(cq as Map);
          _timeLeft = _parseInt(_currentQuestion!['timeLimit'], 0);
          _isLocked = d['answeredCurrent'] == true;
          _selectedAnswer = _isLocked ? _currentQuestion!['answer'] as String? : null;
        }
        if (d['fullQuestionData'] != null) {
          _fullQuestions = List<Map<String, dynamic>>.from(
            (d['fullQuestionData'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
          );
        }
      });
      _startTimer();
    });

    _socket!.on('newQuestion', (data) {
      // Ignored for independent local questions.
    });

    _socket!.on('answerResult', (data) {
      if (!mounted) return;
      // Completely ignore backend score to avoid negative points overriding local correct answers.
      // Final leaderboard will still depend on backend, but local UI will show optimistic score.
    });

    _socket!.on('liveLeaderboard', (data) {
      if (!mounted) return;
      setState(() {
        _liveRanks = List<Map<String, dynamic>>.from(
          (data as List).map((e) => Map<String, dynamic>.from(e as Map)),
        );
      });
    });

    _socket!.on('playerKicked', (kickedUserId) {
      if (!mounted) return;
      if (kickedUserId == _userId) {
        _showErrorDialog('Removed', 'You were removed from the arena by the Admin.',
            navigateAfter: true);
      }
    });

    _socket!.on('gameOver', (data) {
      if (!mounted) return;
      try {
        Map<String, dynamic> d = {};
        if (data is Map) {
          d = Map<String, dynamic>.from(data);
        }
        
        final leaderboard = (d['leaderboard'] as List? ?? [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
            
        final questionStats = (d['questionStats'] as List? ?? [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
            
        double avg = 0.0;
        if (d['roomAverage'] != null) {
          avg = double.tryParse(d['roomAverage'].toString()) ?? 0.0;
        }

        Navigator.pushReplacementNamed(context, AppRoutes.spellLeaderboard, arguments: {
          'roomCode': widget.roomCode,
          'isAdmin': _isAdminOrSuper,
          'leaderboard': leaderboard,
          'roomAverage': avg,
          'questionStats': questionStats,
        });
      } catch (e, st) {
        debugPrint('Error in spell gameOver: $e\n$st');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Transition error: $e'))
          );
        }
      }
    });
  }

  void _moveToNextQuestion() {
    setState(() {
      if (_currentQuestionIndex < _fullQuestions.length - 1) {
        _currentQuestionIndex++;
        _currentQuestion = _fullQuestions[_currentQuestionIndex];
        _timeLeft = _parseInt(_currentQuestion!['timeLimit'], 7);
        _isLocked = false;
        _selectedAnswer = null;
        _playAudio(_currentQuestion!['word'] as String?);
        _startTimer();
      } else {
        _currentQuestion = null;
        _timer?.cancel();
      }
    });
  }

  // ── Timer ────────────────────────────────────────────────
  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      if (_timeLeft > 0) {
        setState(() => _timeLeft -= 1);
      } else {
        t.cancel();
        if (!_isLocked) {
          _forceSubmitTimeUp();
        }
      }
    });
  }

  void _forceSubmitTimeUp() {
    setState(() {
      _isLocked = true;
      _selectedAnswer = null;
    });
    
    if (!_isAdminOrSuper) {
      _socket?.emit('submitAnswer', {
        'roomCode'   : widget.roomCode,
        'userId'     : _userId,
        'answerText' : 'TIME_UP',
        'answer'     : 'TIME_UP',
        'cellId'     : _currentQuestion?['_id'],
        'optionIndex': -1,
        'isCorrect'  : false,
      });
    }
    
    // Advance locally
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      _moveToNextQuestion();
    });
  }

  // ── TTS ──────────────────────────────────────────────────
  Future<void> _playAudio(String? word) async {
    if (word == null || word.isEmpty) return;
    
    setState(() => _isSpeaking = true);
    try {
      await _tts.setLanguage('en-IN');
      await _tts.setSpeechRate(0.42);
      _tts.setCompletionHandler(() {
        if (mounted) setState(() => _isSpeaking = false);
      });
      await _tts.speak(word);
    } catch (e) {
      debugPrint('TTS error: $e');
      if (mounted) setState(() => _isSpeaking = false);
    }
  }

  // ── Shoot Action ─────────────────────────────────────────
  void _handleShoot(String selectedSpelling) {
    if (_isAdminOrSuper) {
      _showErrorDialog('Admin Blocked', 'Admins cannot participate in the Arena. Please log in as a Student to test game progression.');
      return;
    }
    if (_isLocked) return;

    setState(() {
      _isLocked = true;
      _selectedAnswer = selectedSpelling;
    });

    final options = (_currentQuestion?['options'] as List?)?.map((e) => e.toString()).toList() ?? [];
    
    final correctAnswer = _currentQuestion?['answer']?.toString();
    final isCorrect = correctAnswer != null && selectedSpelling.toLowerCase() == correctAnswer.toLowerCase();

    _socket?.emit('submitAnswer', {
      'roomCode'   : widget.roomCode,
      'userId'     : _userId,
      'answerText' : selectedSpelling,
      'answer'     : selectedSpelling,
      'cellId'     : _currentQuestion?['_id'],
      'optionIndex': options.indexOf(selectedSpelling),
      'isCorrect'  : isCorrect,
    });

    if (isCorrect) {
      _triggerConfetti();
      // Optimistic local score update in case backend fails to grade it correctly.
      setState(() {
        _score += 10; 
      });
    }

    // Advance locally
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      _moveToNextQuestion();
    });
  }

  void _handleExit() {
    showDialog(
      context: context,
      builder: (_) => _ConfirmDialog(
        title: 'Abandon Arena?',
        message: 'You will not be able to rejoin this match.',
        onConfirm: () {
          _socket?.emit('leaveRoom', {'roomCode': widget.roomCode});
          Navigator.pop(context); // close dialog
          Navigator.pushReplacementNamed(context,
            _isAdminOrSuper ? AppRoutes.adminDashboard : AppRoutes.studentDashboard);
        },
      ),
    );
  }

  void _triggerConfetti() {
    setState(() => _showConfetti = true);
    _confettiController.forward(from: 0);
  }

  void _showErrorDialog(String title, String message, {bool navigateAfter = false}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppColors.neonRed.withOpacity(0.5)),
        ),
        title: Text(title,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
        content: Text(message, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              if (navigateAfter) {
                Navigator.pushReplacementNamed(context,
                  _isAdminOrSuper ? AppRoutes.adminDashboard : AppRoutes.studentDashboard);
              }
            },
            child: Text('OK', style: TextStyle(color: AppColors.neonPurple)),
          ),
        ],
      ),
    );
  }

  // ── Computed ─────────────────────────────────────────────
  bool get _isAdminOrSuper => _role == 'admin' || _role == 'superadmin';

  int get _myRankIndex => _liveRanks.indexWhere((p) => p['userId'] == _userId);

  Map<String, dynamic>? get _myRankData =>
      _myRankIndex != -1 ? _liveRanks[_myRankIndex] : null;

  String get _displayUserName => (_myRankData?['name'] as String?) ?? _localName;

  String _formatTime(int seconds) {
    final s = seconds < 0 ? 0 : seconds;
    final m = (s ~/ 60).toString().padLeft(2, '0');
    final r = (s % 60).toString().padLeft(2, '0');
    return '$m:$r';
  }

  // ============================================================
  // BUILD
  // ============================================================
  @override
  Widget build(BuildContext context) {
    if (!_ready || _currentQuestion == null) {
      return _buildLoadingScreen();
    }

    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      body: Stack(
        children: [
          const _SpellGameGrid(),
          Positioned.fill(
            child: Opacity(
              opacity: 0.45,
              child: Image.network(
                'https://res.cloudinary.com/dvjefysfi/image/upload/v1781768384/Gemini_Generated_Image_j04eqmj04eqmj04e_fro2w3.png',
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => const SizedBox(),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                _buildTopBar(),
                _buildStatsRow(),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: _buildActiveTab(),
                  ),
                ),
                _buildBottomNav(),
              ],
            ),
          ),
          if (_showConfetti)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _confettiController,
                  builder: (_, __) => CustomPaint(
                    painter: _ConfettiPainter(_confettiController.value),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLoadingScreen() {
    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      body: const Center(
        child: Text(
          'LOADING ARENA...',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 16,
            letterSpacing: 4,
          ),
        ),
      ),
    );
  }

  // ── TOP BAR ─────────────────────────────────────────────
  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: AppColors.bgCard,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.neonPurple.withOpacity(0.5)),
            ),
            child: ClipOval(
              child: _userAvatar.isNotEmpty
                  ? Image.network(_userAvatar, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      Icon(Icons.person_rounded, color: AppColors.neonPurple, size: 18))
                  : Icon(Icons.person_rounded, color: AppColors.neonPurple, size: 18),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_displayUserName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
                Text(_role.toUpperCase(),
                  style: const TextStyle(
                    color: AppColors.neonCyan,
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: _handleExit,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.neonRed.withOpacity(0.08),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.neonRed.withOpacity(0.4)),
              ),
              child: Row(
                children: [
                  Icon(Icons.logout_rounded, color: AppColors.neonRed, size: 13),
                  const SizedBox(width: 4),
                  Text('Exit',
                    style: TextStyle(
                      color: AppColors.neonRed,
                      fontSize: 11,
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

  // ── STATS ROW (LIVE + Timer + Rank + XP) ─────────────────
  Widget _buildStatsRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: _spellGold.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _spellGold.withOpacity(0.4)),
            ),
            child: Row(
              children: [
                Container(
                  width: 6, height: 6,
                  decoration: const BoxDecoration(color: _spellGold, shape: BoxShape.circle),
                ),
                const SizedBox(width: 5),
                Text('LIVE', style: TextStyle(
                    color: _spellGold, fontSize: 8, fontWeight: FontWeight.w800, letterSpacing: 1)),
              ],
            ),
          ),
          const Spacer(),
          _statChip('TIME', _formatTime(_timeLeft),
              color: _timeLeft <= 3 ? AppColors.neonRed : Colors.white),
          if (!_isAdminOrSuper) ...[
            const SizedBox(width: 8),
            _statChip('RANK', _myRankIndex != -1 ? '#${_myRankIndex + 1}' : '-',
                color: AppColors.neonCyan),
            const SizedBox(width: 8),
            _statChip('XP', '$_score', color: _spellGold),
          ],
        ],
      ),
    );
  }

  Widget _statChip(String label, String value, {required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        children: [
          Text(label, style: TextStyle(
              color: color.withOpacity(0.7), fontSize: 7, fontWeight: FontWeight.w800, letterSpacing: 1)),
          Text(value, style: TextStyle(
              color: color, fontSize: 14, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  // ── TAB ROUTER ────────────────────────────────────────────
  Widget _buildActiveTab() {
    switch (_activeTab) {
      case 'leaderboard':
        return _buildLeaderboardTab();
      case 'questions':
        return _isAdminOrSuper ? _buildQuestionsTab() : _buildArenaTab();
      default:
        return _buildArenaTab();
    }
  }

  // ── ARENA TAB ─────────────────────────────────────────────
  Widget _buildArenaTab() {
    final options = (_currentQuestion?['options'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final serial = _currentQuestion?['serialNo'] ?? 1;

    return Column(
      key: const ValueKey('arena'),
      children: [
        const SizedBox(height: 16),
        // ── Audio Card ──
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 460),
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 24),
          decoration: BoxDecoration(
            color: AppColors.bgCard,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFF8B733D), width: 2),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 40, offset: const Offset(0, 20)),
            ],
          ),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              // Top accents
              Positioned(top: -36, left: 20, child: Container(width: 24, height: 36, color: const Color(0xFF8B733D))),
              Positioned(top: -36, right: 20, child: Container(width: 24, height: 36, color: const Color(0xFF8B733D))),
              
              Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                      boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10)],
                    ),
                    child: Text('TARGET 0$serial',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: () => _playAudio(_currentQuestion?['word'] as String?),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: _isSpeaking ? 110 : 100,
                      height: _isSpeaking ? 110 : 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [Color(0xFFD4AF37), Color(0xFF996515)],
                          begin: Alignment.topCenter, end: Alignment.bottomCenter,
                        ),
                        border: Border.all(color: AppColors.bgCard, width: 8),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.6), blurRadius: 30, offset: const Offset(0, 15)),
                        ],
                      ),
                      child: Icon(
                        _isSpeaking ? Icons.volume_up_rounded : Icons.record_voice_over_rounded,
                        color: Colors.white,
                        size: 48,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('LISTEN TO THE WINDS',
                    style: TextStyle(
                      color: Color(0xFF8B733D),
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                      letterSpacing: 3,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // ── Answer Targets (Balloons) ──
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 16,
                runSpacing: 16,
                children: options.asMap().entries.map((e) => _buildAnswerCard(e.value, e.key)).toList(),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _buildAnswerCard(String option, int index) {
    final isSelected = _selectedAnswer == option;
    final isHidden = _isLocked && !isSelected;
    final colors = [
      [const Color(0xFFD4AF37), const Color(0xFF8B733D)], // Vintage (Gold)
      [const Color(0xFF38BDF8), const Color(0xFF0284C7)], // Blue
      [const Color(0xFFC084FC), const Color(0xFF9333EA)], // Multi (Purple)
      [const Color(0xFFFB923C), const Color(0xFFEA580C)], // Fire (Orange)
    ];
    final accentGrad = colors[index % colors.length];

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 300),
      opacity: isHidden ? 0.0 : 1.0,
      child: AnimatedScale(
        duration: const Duration(milliseconds: 300),
        scale: isHidden ? 0.0 : 1.0,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _handleShoot(option),
          child: Container(
            margin: const EdgeInsets.only(bottom: 40), // Space for string
            width: 140,
            height: 190,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: accentGrad,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.all(Radius.elliptical(140, 190)),
              boxShadow: [
                BoxShadow(color: accentGrad[1].withOpacity(0.5), blurRadius: 25, offset: const Offset(0, 15)),
              ],
            ),
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                // Balloon knot
                Positioned(
                  bottom: -8,
                  child: CustomPaint(
                    size: const Size(16, 12),
                    painter: _TrianglePainter(color: accentGrad[1]),
                  ),
                ),
                // String
                Positioned(
                  bottom: -48,
                  child: Container(width: 1.5, height: 40, color: Colors.white.withOpacity(0.4)),
                ),
                // Text Box
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  margin: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: AppColors.bgCard.withOpacity(0.95),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF8B733D).withOpacity(0.7), width: 2),
                    boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 15, offset: Offset(0, 8))],
                  ),
                  child: Text(
                    option,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── LEADERBOARD TAB ───────────────────────────────────────
  Widget _buildLeaderboardTab() {
    return Padding(
      key: const ValueKey('leaderboard'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('LIVE RANKINGS',
              style: TextStyle(
                  color: _spellGold, fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 2)),
          const SizedBox(height: 14),

          if (_myRankData != null && !_isAdminOrSuper) ...[
            Container(
              padding: const EdgeInsets.all(14),
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: _spellGold.withOpacity(0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _spellGold.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Text('#${_myRankIndex + 1}', style: TextStyle(
                      color: _spellGold, fontWeight: FontWeight.w900, fontSize: 20)),
                  const SizedBox(width: 12),
                  _avatarCircle(_myRankData!['avatar'] as String?, size: 40, accent: _spellGold),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_displayUserName, style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
                        Text('Current Position', style: TextStyle(
                            color: _spellGold, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1)),
                      ],
                    ),
                  ),
                  Text('${_myRankData!['points'] ?? 0} XP', style: TextStyle(
                      color: _spellGold, fontWeight: FontWeight.w900, fontSize: 16)),
                ],
              ),
            ),
          ],

          Expanded(
            child: _liveRanks.isEmpty
                ? Center(
              child: Text('Waiting for shooters to earn XP...',
                  style: TextStyle(color: Colors.white.withOpacity(0.3),
                      fontWeight: FontWeight.w700, fontSize: 12, letterSpacing: 1)),
            )
                : ListView.separated(
              itemCount: _liveRanks.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final p = _liveRanks[i];
                final isMe = p['userId'] == _userId;
                final isOffline = p['isOnline'] == false;
                final rankColor = i == 0
                    ? const Color(0xFFFACC15)
                    : i == 1
                    ? Colors.white70
                    : i == 2
                    ? const Color(0xFFFB923C)
                    : Colors.white38;

                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isMe ? _spellGold.withOpacity(0.08) : AppColors.bgCard,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isOffline
                          ? AppColors.neonRed.withOpacity(0.3)
                          : isMe
                          ? _spellGold.withOpacity(0.4)
                          : Colors.white.withOpacity(0.08),
                    ),
                  ),
                  child: Row(
                    children: [
                      SizedBox(width: 30, child: Text('#${i + 1}', style: TextStyle(
                          color: rankColor, fontWeight: FontWeight.w900, fontSize: 14))),
                      const SizedBox(width: 8),
                      _avatarCircle(p['avatar'] as String?, size: 36,
                          accent: isOffline ? AppColors.neonRed : Colors.white24,
                          greyedOut: isOffline),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(p['name'] as String? ?? 'Shooter',
                                    maxLines: 1, overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: isOffline ? Colors.white30 : Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12,
                                      decoration: isOffline ? TextDecoration.lineThrough : null,
                                    ),
                                  ),
                                ),
                                if (isMe)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 4),
                                    child: Text('(YOU)', style: TextStyle(
                                        color: _spellGold, fontSize: 9, fontWeight: FontWeight.w800)),
                                  ),
                              ],
                            ),
                            if (isOffline)
                              Text('OFFLINE', style: TextStyle(
                                  color: AppColors.neonRed, fontSize: 8, fontWeight: FontWeight.w800, letterSpacing: 1)),
                          ],
                        ),
                      ),
                      Text('${p['points'] ?? 0} XP', style: TextStyle(
                          color: _spellGold, fontWeight: FontWeight.w900, fontSize: 13)),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatarCircle(String? url, {required double size, required Color accent, bool greyedOut = false}) {
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        shape: BoxShape.circle,
        border: Border.all(color: accent.withOpacity(0.5)),
      ),
      child: ClipOval(
        child: (url != null && url.isNotEmpty)
            ? Opacity(
          opacity: greyedOut ? 0.5 : 1,
          child: Image.network(url, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Icon(Icons.person_rounded, color: accent, size: size * 0.5)),
        )
            : Icon(Icons.person_rounded, color: accent, size: size * 0.5),
      ),
    );
  }

  // ── MASTER KEY (ADMIN) TAB ────────────────────────────────
  Widget _buildQuestionsTab() {
    return Padding(
      key: const ValueKey('questions'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('MASTER KEY',
              style: TextStyle(
                  color: AppColors.neonGreen, fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 2)),
          const SizedBox(height: 14),
          Expanded(
            child: _fullQuestions.isEmpty
                ? Center(
              child: Text('Decrypting Master Key Data...',
                  style: TextStyle(color: Colors.white.withOpacity(0.3),
                      fontWeight: FontWeight.w700, fontSize: 12, letterSpacing: 1)),
            )
                : ListView.separated(
              itemCount: _fullQuestions.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final q = _fullQuestions[i];
                final word = q['word'] as String? ?? 'Unknown';
                final answer = q['answer'] as String? ?? 'Unknown';
                final serial = q['serialNo'] ?? i + 1;

                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.bgCard,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('Q$serial', style: const TextStyle(
                            color: Colors.white54, fontWeight: FontWeight.w800, fontSize: 11)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text.rich(TextSpan(
                          children: [
                            const TextSpan(text: 'Spoken: ',
                                style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600)),
                            TextSpan(text: word.toUpperCase(),
                                style: TextStyle(color: _spellGold, fontWeight: FontWeight.w800, fontSize: 11)),
                          ],
                        )),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.neonGreen.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.neonGreen.withOpacity(0.3)),
                        ),
                        child: Text(answer, style: TextStyle(
                            color: AppColors.neonGreen, fontWeight: FontWeight.w800,
                            fontSize: 11, letterSpacing: 1)),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── BOTTOM NAV ────────────────────────────────────────────
  Widget _buildBottomNav() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.06))),
      ),
      child: Row(
        children: [
          Expanded(child: _navItem('arena', Icons.gps_fixed_rounded, 'Arena', _spellGold)),
          Expanded(child: _navItem('leaderboard', Icons.leaderboard_rounded, 'Ranks', AppColors.neonCyan)),
          if (_isAdminOrSuper)
            Expanded(child: _navItem('questions', Icons.fact_check_rounded, 'Master Key', AppColors.neonGreen)),
        ],
      ),
    );
  }

  Widget _navItem(String tab, IconData icon, String label, Color accent) {
    final isActive = _activeTab == tab;
    return GestureDetector(
      onTap: () => setState(() => _activeTab = tab),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: isActive ? accent : Colors.white.withOpacity(0.35)),
          const SizedBox(height: 3),
          Text(label.toUpperCase(), style: TextStyle(
              color: isActive ? accent : Colors.white.withOpacity(0.35),
              fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
        ],
      ),
    );
  }
}

// ============================================================
// Custom Painter for Balloon Knot
// ============================================================
class _TrianglePainter extends CustomPainter {
  final Color color;
  _TrianglePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _TrianglePainter oldDelegate) => oldDelegate.color != color;
}

// ============================================================
// Confirm Dialog (self-contained, mirrors spell_lobby_screen.dart)
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
      title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
      content: Text(message, style: const TextStyle(color: Colors.white70)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.4))),
        ),
        TextButton(
          onPressed: onConfirm,
          child: Text('Confirm', style: TextStyle(color: _spellGold, fontWeight: FontWeight.w800)),
        ),
      ],
    );
  }
}

// ============================================================
// Background grid (lightweight — no particles, kept static for
// performance during fast-paced gameplay)
// ============================================================
class _SpellGameGrid extends StatelessWidget {
  const _SpellGameGrid();

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _SpellGameGridPainter(),
    size: MediaQuery.of(context).size,
  );
}

class _SpellGameGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = _spellGold.withOpacity(0.025)
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

// ============================================================
// Hand-rolled confetti burst (no extra package dependency)
// ============================================================
class _ConfettiPainter extends CustomPainter {
  final double progress; // 0.0 → 1.0
  static final List<_ConfettiParticle> _particles =
  List.generate(36, (i) => _ConfettiParticle(math.Random(i * 17)));

  _ConfettiPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    for (final particle in _particles) {
      final localT = ((progress - particle.delay).clamp(0.0, 1.0)) / (1 - particle.delay).clamp(0.01, 1.0);
      if (localT <= 0) continue;
      final x = particle.startX * size.width + (particle.driftX * localT * 60);
      final y = (size.height * 0.35) + (localT * size.height * 0.7);
      final opacity = (1 - localT).clamp(0.0, 1.0);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(localT * particle.spin);
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: particle.size, height: particle.size * 0.5),
        Paint()..color = particle.color.withOpacity(opacity),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter old) => old.progress != progress;
}

class _ConfettiParticle {
  late double startX;
  late double driftX;
  late double delay;
  late double spin;
  late double size;
  late Color color;

  _ConfettiParticle(math.Random rng) {
    const colors = [_spellGold, AppColors.neonGreen, AppColors.neonCyan, AppColors.neonPink, AppColors.neonPurple];
    startX = rng.nextDouble();
    driftX = (rng.nextDouble() - 0.5) * 2;
    delay = rng.nextDouble() * 0.3;
    spin = (rng.nextDouble() - 0.5) * 10;
    size = 6 + rng.nextDouble() * 6;
    color = colors[rng.nextInt(colors.length)];
  }
}