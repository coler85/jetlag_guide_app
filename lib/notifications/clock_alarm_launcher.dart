import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Opens the device clock app's set-alarm UI. Android only.
abstract class ClockAlarmLauncher {
  bool get isSupported;

  Future<void> setAlarm({
    required int hour,
    required int minutes,
    required String message,
  });
}

ClockAlarmLauncher defaultClockAlarmLauncher() {
  if (defaultTargetPlatform == TargetPlatform.android) {
    return AndroidClockAlarmLauncher();
  }
  return const UnsupportedClockAlarmLauncher();
}

class UnsupportedClockAlarmLauncher implements ClockAlarmLauncher {
  const UnsupportedClockAlarmLauncher();

  @override
  bool get isSupported => false;

  @override
  Future<void> setAlarm({
    required int hour,
    required int minutes,
    required String message,
  }) async {}
}

class AndroidClockAlarmLauncher implements ClockAlarmLauncher {
  AndroidClockAlarmLauncher({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  static const channelName = 'jetlag_guide/clock_alarm';

  final MethodChannel _channel;

  @override
  bool get isSupported => true;

  @override
  Future<void> setAlarm({
    required int hour,
    required int minutes,
    required String message,
  }) {
    return _channel.invokeMethod<void>('setAlarm', {
      'hour': hour,
      'minutes': minutes,
      'message': message,
    });
  }
}

/// Test double that records [setAlarm] calls.
class FakeClockAlarmLauncher implements ClockAlarmLauncher {
  FakeClockAlarmLauncher({this.isSupported = true});

  @override
  bool isSupported;

  final calls = <({int hour, int minutes, String message})>[];

  @override
  Future<void> setAlarm({
    required int hour,
    required int minutes,
    required String message,
  }) async {
    calls.add((hour: hour, minutes: minutes, message: message));
  }
}
