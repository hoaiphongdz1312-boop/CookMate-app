import 'package:cookmate/features/cooking/voice_command_parser.dart';
import 'package:cookmate/features/cooking/voice_service.dart';
import 'package:cookmate/features/voice/voice_controller.dart';
import 'package:cookmate/features/voice/voice_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeEngine implements VoiceEngine {
  _FakeEngine(this.onResult);

  final VoiceResultCallback onResult;
  int starts = 0;
  int stops = 0;
  bool failOnStart = false;

  @override
  final status = ValueNotifier<VoiceStatus>(VoiceStatus.off);
  @override
  String? error;

  @override
  Future<void> start() async {
    starts++;
    if (failOnStart) {
      error = 'Chưa cấp quyền micro';
      status.value = VoiceStatus.unavailable;
    } else {
      status.value = VoiceStatus.listening;
    }
  }

  @override
  Future<void> stop() async {
    stops++;
    status.value = VoiceStatus.off;
  }

  @override
  Future<void> setPaused(bool paused) async {}

  @override
  Future<void> dispose() async => status.dispose();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeEngine engine;
  late VoiceController voice;

  setUp(() {
    voice = VoiceController(engineFactory: (onResult) => engine = _FakeEngine(onResult));
  });

  tearDown(() => voice.dispose());

  test('bật công tắc thì mở micro, tắt thì dừng', () async {
    await voice.enable();
    expect(voice.enabled, isTrue);
    expect(voice.status, VoiceStatus.listening);

    await voice.disable();
    expect(voice.enabled, isFalse);
    expect(engine.stops, 1);
  });

  test('màn camera giữ micro thì dừng, nhả thì nghe tiếp', () async {
    await voice.enable();
    final owner = Object();

    voice.hold(owner);
    await Future<void>.delayed(Duration.zero);
    expect(voice.status, VoiceStatus.off);

    voice.release(owner);
    await Future<void>.delayed(Duration.zero);
    expect(voice.status, VoiceStatus.listening);
    expect(voice.enabled, isTrue);
  });

  test('xuống nền thì dừng nghe, quay lại thì nghe tiếp', () async {
    await voice.enable();

    voice.didChangeAppLifecycleState(AppLifecycleState.paused);
    await Future<void>.delayed(Duration.zero);
    expect(voice.status, VoiceStatus.off);

    voice.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(Duration.zero);
    expect(voice.status, VoiceStatus.listening);
  });

  test('chưa bật công tắc thì quay lại app không tự mở micro', () async {
    voice.didChangeAppLifecycleState(AppLifecycleState.paused);
    voice.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(Duration.zero);
    expect(voice.status, VoiceStatus.off);
  });

  test('lỗi micro thì tự tắt công tắc và giữ thông báo lỗi', () async {
    voice = VoiceController(engineFactory: (onResult) => engine = _FakeEngine(onResult)..failOnStart = true);

    await voice.enable();

    expect(voice.enabled, isFalse);
    expect(voice.status, VoiceStatus.unavailable);
    expect(voice.error, 'Chưa cấp quyền micro');
  });

  test('"bếp ơi" rồi lệnh thì chuyển cho màn đang đăng ký', () async {
    final received = <VoiceCommand>[];
    voice.commandHandler = received.add;
    await voice.enable();

    engine.onResult('bếp ơi bước tiếp theo', isFinal: true);

    expect(received, [VoiceCommand.next]);
  });

  test('đang giữ micro thì lệnh không được thực thi', () async {
    final received = <VoiceCommand>[];
    voice.commandHandler = received.add;
    await voice.enable();
    voice.hold(Object());
    await Future<void>.delayed(Duration.zero);

    engine.onResult('bếp ơi bước tiếp theo', isFinal: true);

    expect(received, isEmpty);
  });

  test('lệnh nấu ăn khi không ở màn nấu thì báo, không thực thi', () async {
    await voice.enable();

    engine.onResult('bếp ơi bước tiếp theo', isFinal: true);

    expect(voice.notice, 'Hãy mở một món để dùng lệnh này');
    expect(voice.panelVisible, isTrue);
  });

  test('"bước tiếp theo" ngoài màn nấu thì nhờ cấp app mở món đang nấu', () async {
    final navigation = <VoiceCommand>[];
    voice.navigationHandler = navigation.add;
    await voice.enable();

    engine.onResult('bếp ơi bước tiếp theo', isFinal: true);
    expect(navigation, [VoiceCommand.next]);
    expect(voice.notice, isNull);

    await Future<void>.delayed(const Duration(milliseconds: 1600)); // hết cooldown
    engine.onResult('bếp ơi hẹn giờ', isFinal: true);
    expect(navigation, [VoiceCommand.next]);
    expect(voice.notice, 'Hãy mở một món để dùng lệnh này');
  });

  test('lệnh điều hướng đi tới navigationHandler kể cả khi màn nấu đang mở', () async {
    final cooking = <VoiceCommand>[];
    final navigation = <VoiceCommand>[];
    voice
      ..commandHandler = cooking.add
      ..navigationHandler = navigation.add;
    await voice.enable();

    engine.onResult('bếp ơi về trang chủ', isFinal: true);

    expect(navigation, [VoiceCommand.goHome]);
    expect(cooking, isEmpty);
    expect(voice.notice, isNull);
  });

  test('nghe "bếp ơi" thì mở bảng, nhận lệnh xong thì đóng', () async {
    voice.navigationHandler = (_) {};
    await voice.enable();

    engine.onResult('bếp ơi', isFinal: true);
    expect(voice.panelVisible, isTrue);

    engine.onResult('hôm nay ăn gì', isFinal: true);
    expect(voice.panelVisible, isFalse);
  });

  testWidgets('bảng "Bạn cần gì?" hiện khi nghe "bếp ơi", chạm thì đóng', (tester) async {
    await tester.runAsync(voice.enable);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => VoiceOverlay(voice: voice, child: child!),
      home: const Scaffold(body: Text('Trang chủ')),
    ));
    expect(find.text('Bạn cần gì?'), findsNothing);

    engine.onResult('bếp ơi', isFinal: true);
    await tester.pumpAndSettle();
    expect(find.text('Bạn cần gì?'), findsOneWidget);

    await tester.tap(find.text('Bạn cần gì?'));
    await tester.pumpAndSettle();
    expect(find.text('Bạn cần gì?'), findsNothing);
    expect(voice.armed, isFalse);
  });

  testWidgets('câu báo hiện trên bảng rồi tự ẩn', (tester) async {
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => VoiceOverlay(voice: voice, child: child!),
      home: const Scaffold(body: Text('Trang chủ')),
    ));

    voice.showNotice('Hãy mở một món để dùng lệnh này');
    await tester.pump();
    expect(find.text('Hãy mở một món để dùng lệnh này'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.text('Hãy mở một món để dùng lệnh này'), findsNothing);
  });
}
