import 'package:cookmate/features/cooking/voice_command_parser.dart';
import 'package:cookmate/features/cooking/voice_gate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parser', () {
    test('bỏ dấu và chữ thường', () {
      expect(normalizeVoiceText('  Bếp  ƠI, Đừng '), 'bep oi, dung');
    });

    test('nhận lệnh có dấu và không dấu', () {
      expect(findVoiceCommand(normalizeVoiceText('bước tiếp theo')),
          VoiceCommand.next);
      expect(findVoiceCommand('buoc tiep theo'), VoiceCommand.next);
      expect(findVoiceCommand(normalizeVoiceText('bước trước')),
          VoiceCommand.previous);
      expect(findVoiceCommand(normalizeVoiceText('hẹn giờ')),
          VoiceCommand.startTimer);
      expect(findVoiceCommand('xin chao'), isNull);
    });

    test('"dừng hẹn giờ" không bị nhận thành "hẹn giờ"', () {
      expect(findVoiceCommand(normalizeVoiceText('dừng hẹn giờ')),
          VoiceCommand.pauseTimer);
    });

    test('nhận lệnh điều hướng toàn app', () {
      expect(findVoiceCommand(normalizeVoiceText('mở món đang nấu')),
          VoiceCommand.openCooking);
      expect(findVoiceCommand(normalizeVoiceText('Về trang chủ')),
          VoiceCommand.goHome);
      expect(findVoiceCommand(normalizeVoiceText('hôm nay ăn gì')),
          VoiceCommand.luckyMeal);
      expect(findVoiceCommand('hom nay an gi'), VoiceCommand.luckyMeal);
    });

    test('phân loại lệnh nấu ăn và lệnh điều hướng', () {
      expect(VoiceCommand.next.cooking, isTrue);
      expect(VoiceCommand.pauseTimer.cooking, isTrue);
      expect(VoiceCommand.goHome.cooking, isFalse);
      expect(VoiceCommand.luckyMeal.cooking, isFalse);
      expect(VoiceCommand.openCooking.cooking, isFalse);
    });

    test('"bếp ơi" kèm lệnh điều hướng trong một câu', () {
      final normalized = normalizeVoiceText('Bếp ơi hôm nay ăn gì');
      expect(containsWakeWord(normalized), isTrue);
      expect(findVoiceCommand(normalized), VoiceCommand.luckyMeal);
    });

    test('nhận cụm gọi', () {
      expect(containsWakeWord(normalizeVoiceText('Bếp ơi')), isTrue);
      expect(containsWakeWord('buoc tiep theo'), isFalse);
    });
  });

  group('VoiceGate', () {
    late DateTime clock;
    late List<VoiceCommand> commands;
    late int armed;
    late int disarmed;
    late VoiceGate gate;

    void advance(Duration d) => clock = clock.add(d);

    setUp(() {
      clock = DateTime(2026, 10, 31, 12);
      commands = [];
      armed = 0;
      disarmed = 0;
      gate = VoiceGate(
        onCommand: commands.add,
        onArmed: () => armed++,
        onDisarmed: () => disarmed++,
        now: () => clock,
      );
    });

    test('"bếp ơi" rồi lệnh trong 5 giây thì thực thi', () {
      gate.feed('bếp ơi', isFinal: true);
      expect(gate.state, VoiceGateState.armed);
      expect(armed, 1);
      advance(const Duration(seconds: 3));
      gate.feed('bước tiếp theo', isFinal: true);
      expect(commands, [VoiceCommand.next]);
      expect(disarmed, 1);
      expect(gate.state, VoiceGateState.cooldown);
    });

    test('không dấu cũng nhận', () {
      gate.feed('bep oi', isFinal: true);
      gate.feed('buoc truoc', isFinal: true);
      expect(commands, [VoiceCommand.previous]);
    });

    test('"bếp ơi" rồi im 5 giây thì hết hạn, lệnh sau bị bỏ', () {
      gate.feed('bếp ơi', isFinal: true);
      advance(const Duration(seconds: 6));
      gate.feed('bước tiếp theo', isFinal: true);
      expect(commands, isEmpty);
      expect(gate.state, VoiceGateState.idle);
      expect(disarmed, 1);
    });

    test('tick() báo hết hạn khi không có kết quả mới', () {
      gate.feed('bếp ơi', isFinal: false);
      advance(const Duration(seconds: 5));
      gate.tick();
      expect(gate.state, VoiceGateState.idle);
      expect(disarmed, 1);
    });

    test('lệnh khi chưa gọi "bếp ơi" bị bỏ', () {
      gate.feed('bước tiếp theo', isFinal: true);
      expect(commands, isEmpty);
    });

    test('một câu có cả hai thì thực thi luôn', () {
      gate.feed('bếp ơi bước tiếp theo', isFinal: true);
      expect(commands, [VoiceCommand.next]);
      expect(armed, 0);
    });

    test('lặp lệnh trong cooldown bị bỏ, hết cooldown thì nhận lại', () {
      gate.feed('bếp ơi bước tiếp theo', isFinal: true);
      advance(const Duration(milliseconds: 500));
      gate.feed('bếp ơi bước tiếp theo', isFinal: true);
      expect(commands.length, 1);
      advance(const Duration(seconds: 2));
      gate.feed('bếp ơi bước tiếp theo', isFinal: true);
      expect(commands.length, 2);
    });

    test('partial đủ lệnh thực thi một lần, final trùng bị bỏ', () {
      gate.feed('bếp ơi bước tiếp theo', isFinal: false);
      advance(const Duration(seconds: 3));
      gate.feed('bếp ơi bước tiếp theo', isFinal: true);
      expect(commands, [VoiceCommand.next]);
    });

    test('partial mở cổng bằng "bếp ơi"', () {
      gate.feed('bếp ơi', isFinal: false);
      expect(gate.state, VoiceGateState.armed);
    });

    test('"[unk]" và câu rỗng bị bỏ', () {
      gate.feed('[unk]', isFinal: true);
      gate.feed('', isFinal: true);
      gate.feed('   ', isFinal: false);
      expect(commands, isEmpty);
      expect(gate.state, VoiceGateState.idle);
    });

    test('"dừng hẹn giờ" không thành "hẹn giờ"', () {
      gate.feed('bếp ơi dừng hẹn giờ', isFinal: true);
      expect(commands, [VoiceCommand.pauseTimer]);
    });

    test('pause() bỏ qua mọi kết quả đến khi resume()', () {
      gate.feed('bếp ơi', isFinal: true);
      gate.pause();
      expect(gate.state, VoiceGateState.idle);
      expect(disarmed, 1);
      gate.feed('bếp ơi bước tiếp theo', isFinal: true);
      expect(commands, isEmpty);
      gate.resume();
      gate.feed('bếp ơi bước tiếp theo', isFinal: true);
      expect(commands, [VoiceCommand.next]);
    });
  });
}
