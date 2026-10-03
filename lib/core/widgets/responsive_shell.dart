import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// ResponsiveShell wraps screens to ensure optimal layout on both mobile and web.
/// For mobile screens (User & Employee), it centers the layout in a clean phone frame
/// on desktop browsers. For Admin screens or wide layouts, it utilizes the full canvas.
class ResponsiveShell extends StatelessWidget {
  final Widget child;
  final bool allowWide;
  final double maxWidth;
  final PreferredSizeWidget? appBar;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;
  final Color? backgroundColor;
  final bool desktopPortal;

  const ResponsiveShell({
    super.key,
    required this.child,
    this.allowWide = false,
    this.maxWidth = 480,
    this.appBar,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.backgroundColor,
    this.desktopPortal = false,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth > 768;

        if (desktopPortal &&
            constraints.maxWidth >= 1000 &&
            bottomNavigationBar is NavigationBar) {
          final navigation = bottomNavigationBar! as NavigationBar;
          return Scaffold(
            backgroundColor: backgroundColor ?? AppColors.background,
            appBar: appBar,
            body: SafeArea(
              child: Row(
                children: [
                  NavigationRail(
                    extended: constraints.maxWidth >= 1200,
                    selectedIndex: navigation.selectedIndex,
                    onDestinationSelected: navigation.onDestinationSelected,
                    leading: const Padding(
                      padding: EdgeInsets.all(12),
                      child: Icon(
                        Icons.local_hospital_outlined,
                        color: AppColors.emergencyRed,
                      ),
                    ),
                    destinations: navigation.destinations
                        .whereType<NavigationDestination>()
                        .map(
                          (item) => NavigationRailDestination(
                            icon: item.icon,
                            selectedIcon: item.selectedIcon,
                            label: Text(item.label),
                          ),
                        )
                        .toList(),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: child),
                ],
              ),
            ),
            floatingActionButton: floatingActionButton,
          );
        }

        if (allowWide || !isDesktop) {
          return Scaffold(
            backgroundColor: backgroundColor ?? AppColors.background,
            appBar: appBar,
            body: child,
            bottomNavigationBar: bottomNavigationBar,
            floatingActionButton: floatingActionButton,
          );
        }

        // On desktop browser for User/Employee view, center in phone container
        return Scaffold(
          backgroundColor: const Color(0xFFEDF4F1),
          body: SafeArea(
            child: Stack(
              children: [
                Positioned(
                  top: -170,
                  right: -110,
                  child: _ambientOrb(
                    AppColors.reliefGreenMedium.withValues(alpha: 0.17),
                    390,
                  ),
                ),
                Positioned(
                  bottom: -200,
                  left: -140,
                  child: _ambientOrb(
                    AppColors.emergencyRed.withValues(alpha: 0.10),
                    420,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: Container(
                      constraints: BoxConstraints(maxWidth: maxWidth),
                      decoration: BoxDecoration(
                        color: backgroundColor ?? AppColors.background,
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x290F172A),
                            blurRadius: 38,
                            offset: Offset(0, 18),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Scaffold(
                        backgroundColor:
                            backgroundColor ?? AppColors.background,
                        appBar: appBar,
                        body: child,
                        bottomNavigationBar: bottomNavigationBar,
                        floatingActionButton: floatingActionButton,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _ambientOrb(Color color, double size) => IgnorePointer(
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    ),
  );
}
