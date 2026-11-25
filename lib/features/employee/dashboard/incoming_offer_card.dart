import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_colors.dart';
import '../../../models/dispatch_offer.dart';

/// Loud, unmissable "new emergency" card with a 60-second countdown.
///
/// While visible it pulses, vibrates and plays the system alert sound every
/// second. The sound only plays while the app is open or in the background:
/// waking a fully closed phone needs server push (Firebase Blaze plan).
class IncomingOfferCard extends StatefulWidget {
  final DispatchOffer offer;
  final Future<void> Function() onAccept;
  final Future<void> Function() onDecline;
  final DateTime Function() clock;

  const IncomingOfferCard({
    super.key,
    required this.offer,
    required this.onAccept,
    required this.onDecline,
    this.clock = DateTime.now,
  });

  @override
  State<IncomingOfferCard> createState() => _IncomingOfferCardState();
}

class _IncomingOfferCardState extends State<IncomingOfferCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);
  Timer? _ticker;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _ring();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      _ring();
    });
  }

  void _ring() {
    if (widget.offer.remaining(widget.clock()) == Duration.zero) return;
    SystemSound.play(SystemSoundType.alert);
    HapticFeedback.heavyImpact();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final offer = widget.offer;
    final left = offer.remaining(widget.clock());
    final seconds = left.inSeconds;
    final fraction = (left.inMilliseconds / DispatchOffer.window.inMilliseconds)
        .clamp(0.0, 1.0);
    final urgent = seconds <= 15;
    final critical = offer.priority.contains('P1');

    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) => Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.lerp(
                AppColors.emergencyRed,
                AppColors.emergencyRedDark,
                _pulse.value,
              )!,
              AppColors.emergencyRedDark,
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.emergencyRed.withValues(
                alpha: 0.25 + 0.35 * _pulse.value,
              ),
              blurRadius: 18 + 22 * _pulse.value,
              spreadRadius: 1 + 3 * _pulse.value,
            ),
          ],
        ),
        child: child,
      ),
      child: Semantics(
        liveRegion: true,
        label:
            'New emergency offer. ${offer.emergencyType}. $seconds seconds left to accept.',
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.notifications_active_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'NEW EMERGENCY · RESPOND NOW',
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.1,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  if (critical)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'CRITICAL',
                        style: GoogleFonts.outfit(
                          color: AppColors.emergencyRedDark,
                          fontWeight: FontWeight.w900,
                          fontSize: 11,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _CountdownRing(
                    fraction: fraction,
                    seconds: seconds,
                    urgent: urgent,
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          offer.emergencyType,
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _InfoLine(
                          icon: Icons.place_rounded,
                          text: offer.address.isEmpty
                              ? 'Patient pin on map'
                              : offer.address,
                        ),
                        const SizedBox(height: 4),
                        _InfoLine(
                          icon: Icons.route_rounded,
                          text:
                              '${offer.distanceKm.toStringAsFixed(1)} km away · ${offer.priority}',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 64,
                child: FilledButton.icon(
                  key: const Key('acceptOffer'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.reliefGreenDark,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    textStyle: GoogleFonts.outfit(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  onPressed: _busy || seconds == 0
                      ? null
                      : () => _run(widget.onAccept),
                  icon: _busy
                      ? const SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 3),
                        )
                      : const Icon(Icons.check_circle_rounded, size: 28),
                  label: const Text('ACCEPT · I\'M GOING'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  key: const Key('declineOffer'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white70, width: 1.4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: _busy || seconds == 0
                      ? null
                      : () => _run(widget.onDecline),
                  icon: const Icon(Icons.close_rounded),
                  label: const Text('Can\'t go — pass to next ambulance'),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'No answer in 60 seconds counts as a missed call (penalty) and the patient is offered to the next-nearest ambulance. Declining is not a penalty.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, color: Colors.white70, size: 16),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
          text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white, fontSize: 13.5),
        ),
      ),
    ],
  );
}

class _CountdownRing extends StatelessWidget {
  final double fraction;
  final int seconds;
  final bool urgent;
  const _CountdownRing({
    required this.fraction,
    required this.seconds,
    required this.urgent,
  });

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 92,
    child: CustomPaint(
      painter: _RingPainter(fraction, urgent),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$seconds',
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 34,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
            const Text(
              'sec',
              style: TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
        ),
      ),
    ),
  );
}

class _RingPainter extends CustomPainter {
  final double fraction;
  final bool urgent;
  _RingPainter(this.fraction, this.urgent);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final track = Paint()
      ..color = Colors.white24
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8;
    final arc = Paint()
      ..color = urgent ? AppColors.amberGlow : Colors.white
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 8;
    canvas.drawArc(rect.deflate(5), 0, math.pi * 2, false, track);
    canvas.drawArc(
      rect.deflate(5),
      -math.pi / 2,
      math.pi * 2 * fraction,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fraction != fraction || old.urgent != urgent;
}
