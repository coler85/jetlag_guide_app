import 'dart:async';

import 'package:flutter/widgets.dart';

import '../logic/jetlag_clock.dart';
import '../theme/jetlag_theme.dart';

/// Fixed cockpit strip. The instant comes from [clock], which must be UTC.
class CockpitClockBar extends StatefulWidget {
  const CockpitClockBar({
    super.key,
    required this.clock,
    required this.localIana,
    required this.homeIana,
    required this.stationLabel,
  });

  final DateTime Function() clock;
  final String localIana;
  final String homeIana;
  final String stationLabel;

  @override
  State<CockpitClockBar> createState() => _CockpitClockBarState();
}

class _CockpitClockBarState extends State<CockpitClockBar> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // A repeating timer never settles under `pumpAndSettle`.
    final binding = WidgetsBinding.instance.runtimeType.toString();
    if (!binding.contains('Test')) {
      _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final line = formatCockpitLine(
      nowUtc: widget.clock().toUtc(),
      localIana: widget.localIana,
      homeIana: widget.homeIana,
      stationLabel: widget.stationLabel,
    );
    return SizedBox(
      key: const ValueKey('jetlag-clock-bar'),
      height: 24,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: JetlagTheme.elevated,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: JetlagTheme.border),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.center,
            child: Text(
              line,
              maxLines: 1,
              style: const TextStyle(
                color: JetlagTheme.textPrimary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                fontFeatures: JetlagTheme.tabular,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
