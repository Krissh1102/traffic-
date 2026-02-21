import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// FABButton  – a styled floating action button used in the map bottom bar
// ---------------------------------------------------------------------------
class FABButton extends StatelessWidget {
  final VoidCallback? onTap;
  final bool isTablet;
  final bool active;
  final Color activeColor;
  final Color inactiveColor;
  final String tooltip;
  final Widget child;

  const FABButton({
    super.key,
    required this.onTap,
    required this.isTablet,
    required this.active,
    required this.activeColor,
    required this.inactiveColor,
    required this.tooltip,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: EdgeInsets.all(isTablet ? 20 : 16),
            decoration: BoxDecoration(
              gradient: active
                  ? LinearGradient(
                      colors: [activeColor, activeColor.withOpacity(0.8)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : null,
              color: active ? null : inactiveColor,
              borderRadius: BorderRadius.circular(16),
              border: active
                  ? null
                  : Border.all(color: Colors.grey.shade300, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: activeColor.withOpacity(active ? 0.4 : 0.1),
                  blurRadius: 15,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}