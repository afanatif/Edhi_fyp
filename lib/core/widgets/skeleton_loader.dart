import 'package:flutter/material.dart';

/// Sweeping shimmer light animation over placeholder skeletons
class ShimmerLoading extends StatefulWidget {
  final Widget child;
  final bool isLoading;
  final Color baseColor;
  final Color highlightColor;

  const ShimmerLoading({
    super.key,
    required this.child,
    this.isLoading = true,
    this.baseColor = const Color(0xFFE2E8F0),
    this.highlightColor = const Color(0xFFF8FAFC),
  });

  @override
  State<ShimmerLoading> createState() => _ShimmerLoadingState();
}

class _ShimmerLoadingState extends State<ShimmerLoading>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isLoading) return widget.child;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            final progress = _controller.value;
            return LinearGradient(
              begin: const Alignment(-1.5, -0.5),
              end: const Alignment(1.5, 0.5),
              colors: [
                widget.baseColor,
                widget.highlightColor,
                widget.baseColor,
              ],
              stops: [
                (progress - 0.35).clamp(0.0, 1.0),
                progress.clamp(0.0, 1.0),
                (progress + 0.35).clamp(0.0, 1.0),
              ],
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// Basic rounded rectangle skeleton block
class SkeletonBox extends StatelessWidget {
  final double? width;
  final double? height;
  final double borderRadius;
  final Color? color;

  const SkeletonBox({
    super.key,
    this.width,
    this.height,
    this.borderRadius = 8,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color ?? const Color(0xFFE2E8F0),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}

/// Circular skeleton block for avatars and action buttons
class SkeletonCircle extends StatelessWidget {
  final double radius;
  final Color? color;

  const SkeletonCircle({super.key, required this.radius, this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        color: color ?? const Color(0xFFE2E8F0),
        shape: BoxShape.circle,
      ),
    );
  }
}

/// Multi-line text placeholder skeleton
class SkeletonText extends StatelessWidget {
  final int lines;
  final double height;
  final double spacing;
  final double lastLineWidthFactor;

  const SkeletonText({
    super.key,
    this.lines = 2,
    this.height = 12,
    this.spacing = 6,
    this.lastLineWidthFactor = 0.65,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: List.generate(lines, (index) {
        final isLast = index == lines - 1;
        return Padding(
          padding: EdgeInsets.only(bottom: isLast ? 0 : spacing),
          child: FractionallySizedBox(
            widthFactor: isLast ? lastLineWidthFactor : 1.0,
            child: SkeletonBox(height: height, borderRadius: height / 2),
          ),
        );
      }),
    );
  }
}

/// Composed Skeleton Card for Emergency Incidents
class SkeletonEmergencyCard extends StatelessWidget {
  const SkeletonEmergencyCard({super.key});

  @override
  Widget build(BuildContext context) {
    return ShimmerLoading(
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SkeletonCircle(radius: 18),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBox(width: 130, height: 14, borderRadius: 4),
                      SizedBox(height: 6),
                      SkeletonBox(width: 80, height: 10, borderRadius: 4),
                    ],
                  ),
                ),
                const SkeletonBox(width: 75, height: 22, borderRadius: 6),
              ],
            ),
            const SizedBox(height: 14),
            const SkeletonBox(
              width: double.infinity,
              height: 12,
              borderRadius: 4,
            ),
            const SizedBox(height: 6),
            const SkeletonBox(width: 200, height: 12, borderRadius: 4),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const SkeletonBox(width: 110, height: 12, borderRadius: 4),
                SkeletonBox(width: 90, height: 28, borderRadius: 8),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Composed Skeleton Card for KPI Metric Tiles in Admin Dashboard
class SkeletonMetricTile extends StatelessWidget {
  const SkeletonMetricTile({super.key});

  @override
  Widget build(BuildContext context) {
    return ShimmerLoading(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: SkeletonBox(width: 70, height: 11, borderRadius: 4),
                ),
                SizedBox(width: 8),
                SkeletonCircle(radius: 14),
              ],
            ),
            SizedBox(height: 12),
            SkeletonBox(width: 50, height: 24, borderRadius: 6),
            SizedBox(height: 6),
            SkeletonBox(width: 90, height: 10, borderRadius: 4),
          ],
        ),
      ),
    );
  }
}

/// Composed Skeleton Card for Ambulance Fleet and Drivers
class SkeletonAmbulanceCard extends StatelessWidget {
  const SkeletonAmbulanceCard({super.key});

  @override
  Widget build(BuildContext context) {
    return ShimmerLoading(
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: const Row(
          children: [
            SkeletonCircle(radius: 20),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      SkeletonBox(width: 110, height: 14, borderRadius: 4),
                      SizedBox(width: 8),
                      SkeletonBox(width: 65, height: 18, borderRadius: 4),
                    ],
                  ),
                  SizedBox(height: 6),
                  SkeletonBox(width: 160, height: 11, borderRadius: 4),
                ],
              ),
            ),
            SkeletonBox(width: 60, height: 26, borderRadius: 8),
          ],
        ),
      ),
    );
  }
}

/// Composed Skeleton Card for Blood Needs & Donors
class SkeletonBloodCard extends StatelessWidget {
  const SkeletonBloodCard({super.key});

  @override
  Widget build(BuildContext context) {
    return ShimmerLoading(
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: const Row(
          children: [
            SkeletonBox(width: 44, height: 44, borderRadius: 10),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: 120, height: 14, borderRadius: 4),
                  SizedBox(height: 6),
                  SkeletonBox(width: 180, height: 11, borderRadius: 4),
                  SizedBox(height: 6),
                  SkeletonBox(width: 90, height: 10, borderRadius: 4),
                ],
              ),
            ),
            SkeletonBox(width: 70, height: 32, borderRadius: 8),
          ],
        ),
      ),
    );
  }
}

/// Composed Skeleton Card for User Profiles & Admin User Directory
class SkeletonUserCard extends StatelessWidget {
  const SkeletonUserCard({super.key});

  @override
  Widget build(BuildContext context) {
    return ShimmerLoading(
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: const Row(
          children: [
            SkeletonCircle(radius: 20),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      SkeletonBox(width: 120, height: 13, borderRadius: 4),
                      SizedBox(width: 8),
                      SkeletonBox(width: 55, height: 16, borderRadius: 4),
                      SizedBox(width: 6),
                      SkeletonBox(width: 90, height: 16, borderRadius: 4),
                    ],
                  ),
                  SizedBox(height: 6),
                  SkeletonBox(width: 180, height: 10, borderRadius: 4),
                ],
              ),
            ),
            SkeletonBox(width: 32, height: 32, borderRadius: 6),
          ],
        ),
      ),
    );
  }
}

/// List wrapper that renders multiple skeleton cards
class SkeletonListView extends StatelessWidget {
  final int count;
  final Widget Function(BuildContext, int)? itemBuilder;
  final Widget? skeleton;
  final EdgeInsetsGeometry padding;

  const SkeletonListView({
    super.key,
    this.count = 3,
    this.itemBuilder,
    this.skeleton,
    this.padding = const EdgeInsets.symmetric(vertical: 8),
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: padding,
      itemCount: count,
      itemBuilder:
          itemBuilder ??
          (ctx, idx) => skeleton ?? const SkeletonEmergencyCard(),
    );
  }
}
