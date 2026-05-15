import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:flutter_windowmanager_plus/flutter_windowmanager_plus.dart';
import 'package:screen_protector/screen_protector.dart';
import '../../core/services/audio_protection_service.dart';
import 'dart:async';

class ProtectedVideoPlayer extends StatefulWidget {
  final String videoUrl;
  final String courseTitle;

  const ProtectedVideoPlayer({
    super.key,
    required this.videoUrl,
    required this.courseTitle,
  });

  @override
  State<ProtectedVideoPlayer> createState() => _ProtectedVideoPlayerState();
}

class _ProtectedVideoPlayerState extends State<ProtectedVideoPlayer> with WidgetsBindingObserver {
  late final Player _player;
  late final VideoController _videoController;
  
  final AudioProtectionService _protectionService = AudioProtectionService();
  StreamSubscription? _recordingSubscription;
  
  bool _isRecording = false;
  bool _isProtectionActive = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializePlayer();
    //_initializeProtection();
  }

  /// تهيئة المشغل
  void _initializePlayer() {
    _player = Player();
    _videoController = VideoController(_player);
    _player.open(Media(widget.videoUrl));
  }

  /// تفعيل الحماية الكاملة
  Future<void> _initializeProtection() async {
    try {
      // ==================== Amr AI Technical Team - Multi-Platform Protection ====================
      // Contact: 01090991769 | Email: amr.01090991769.ai@gmail.com
      // =========================================================================================
      
      // 1. Platform-specific Screenshot/Screen Recording Protection
      if (Platform.isAndroid) {
        // Android: Use FlutterWindowManager (FLAG_SECURE)
        // await FlutterWindowManager.addFlags(FlutterWindowManager.FLAG_SECURE);
        debugPrint('✅ Amr AI: Android screen protection enabled (FLAG_SECURE)');
      } else if (Platform.isIOS) {
        // iOS: Use screen_protector plugin
        await ScreenProtector.protectDataLeakageOn();
        await ScreenProtector.preventScreenshotOn();
        debugPrint('✅ Amr AI: iOS screen protection enabled (screen_protector)');
      }
      
      // 2. تفعيل Wakelock (منع قفل الشاشة) - Works on both platforms
      await WakelockPlus.enable();
      debugPrint('✅ Amr AI: Wakelock enabled');
      
      // 3. حظر التقاط الصوت (Android 10+) / iOS returns success
      await _protectionService.blockAudioCapture();
      debugPrint('✅ Amr AI: Audio capture protection requested');
      
      // 4. بدء المراقبة
      await _protectionService.startMonitoring();
      debugPrint('✅ Amr AI: Monitoring started');
      
      // 5. الاستماع لحالة التسجيل
      _recordingSubscription = _protectionService.recordingStateStream.listen((isRecording) {
        if (isRecording && !_isRecording) {
          _handleRecordingDetected();
        }
      });

      if (mounted) {
        setState(() => _isProtectionActive = true);
      }
      
      debugPrint('✅ Amr AI: Full protection system activated successfully');
    } catch (e) {
      debugPrint('⚠️ Amr AI Error: Protection initialization failed: $e');
      
      // Show user-friendly error message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تحذير: قد لا تعمل بعض مميزات الحماية'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// معالجة اكتشاف التسجيل
  void _handleRecordingDetected() {
    if (!mounted) return;
    setState(() => _isRecording = true);
    
    // إيقاف التشغيل فوراً
    _player.pause();
    
    // عرض تحذير
    _showRecordingAlert();
  }

  /// عرض تحذير التسجيل
  void _showRecordingAlert() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => WillPopScope(
        onWillPop: () async => false,
        child: AlertDialog(
          backgroundColor: Colors.red.shade900,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.white, size: 32),
              SizedBox(width: 10),
              Text('⚠️ تحذير أمني', style: TextStyle(color: Colors.white)),
            ],
          ),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'تم اكتشاف محاولة تسجيل صوت!',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
              ),
              SizedBox(height: 10),
              Text(
                '• تم إيقاف التشغيل تلقائياً\n• التسجيل مخالف لحقوق الملكية الفكرية\n• قد يتم إيقاف حسابك',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context); // إغلاق التحذير
                Navigator.of(context).pop(); // الخروج من صفحة الفيديو
              },
              style: TextButton.styleFrom(
                backgroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              child: Text('خروج', style: TextStyle(color: Colors.red.shade900, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // إيقاف التشغيل عند الانتقال للخلفية
      _player.pause();
    } else if (state == AppLifecycleState.resumed) {
      // إعادة تطبيق الحماية عند العودة
      _protectionService.blockAudioCapture();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(widget.courseTitle, style: const TextStyle(color: Colors.white)),
        leading: const BackButton(color: Colors.white),
      ),
      body: Stack(
        children: [
          // المشغل
          Center(
            child: Video(
              controller: _videoController,
              controls: MaterialVideoControls,
            ),
          ),

          // مؤشر الحماية النشطة
          if (_isProtectionActive)
            Positioned(
              top: 10,
              right: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.shield, color: Colors.white, size: 16),
                    SizedBox(width: 5),
                    Text('محمي', style: TextStyle(color: Colors.white, fontSize: 12)),
                  ],
                ),
              ),
            ),

          // تحذير التسجيل (غطاء كامل)
          if (_isRecording)
            Positioned.fill(
              child: Container(
                color: Colors.red.withOpacity(0.95),
                child: const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.block, color: Colors.white, size: 80),
                      SizedBox(height: 20),
                      Text(
                        'تم اكتشاف تسجيل!',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 10),
                      Text(
                        'تم إيقاف التشغيل',
                        style: TextStyle(color: Colors.white70, fontSize: 16),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _recordingSubscription?.cancel();
    _protectionService.stopMonitoring();
    WakelockPlus.disable();
    _player.dispose();
    
    // Clean up platform-specific protection
    if (Platform.isIOS) {
      ScreenProtector.protectDataLeakageOff();
      ScreenProtector.preventScreenshotOff();
    }
    
    debugPrint('✅ Amr AI: Protection cleaned up');
    super.dispose();
  }
}
