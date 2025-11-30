import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'dart:io' show Platform;

class CustomTitleBar extends StatelessWidget {
  final String title;
  final Color? backgroundColor;
  
  const CustomTitleBar({
    super.key,
    this.title = 'DecVault',
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    // Don't show custom title bar on non-desktop platforms
    try {
      if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) {
        return const SizedBox.shrink();
      }
    } catch (e) {
      return const SizedBox.shrink();
    }

    final bgColor = backgroundColor ?? const Color(0xFF1E1E1E);
    final isMacOS = Platform.isMacOS;

    return Container(
      height: isMacOS ? 52 : 40,
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withOpacity(0.05),
            width: 1,
          ),
        ),
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanStart: (details) {
          windowManager.startDragging();
        },
        onDoubleTap: () async {
          bool isMaximized = await windowManager.isMaximized();
          if (isMaximized) {
            windowManager.unmaximize();
          } else {
            windowManager.maximize();
          }
        },
        child: Row(
          children: [
            // Logo and title section
            if (isMacOS) const SizedBox(width: 80), // Space for macOS traffic lights
            if (!isMacOS) const SizedBox(width: 16),
            
            // App logo
            Container(
              padding: const EdgeInsets.all(8),
              child: Image.asset(
                'assets/logo/white.png',
                height: 24,
                width: 24,
                errorBuilder: (context, error, stackTrace) {
                  return const Icon(
                    Icons.shield,
                    color: Color(0xFF34A853),
                    size: 24,
                  );
                },
              ),
            ),
            
            const SizedBox(width: 8),
            
            // Title
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            
            const Spacer(),
            
            // Window controls (only for Windows and Linux)
            if (!isMacOS) ...[
              _WindowButton(
                icon: Icons.remove,
                onPressed: () => windowManager.minimize(),
                tooltip: 'Minimize',
              ),
              _WindowButton(
                icon: Icons.crop_square,
                onPressed: () async {
                  bool isMaximized = await windowManager.isMaximized();
                  if (isMaximized) {
                    windowManager.unmaximize();
                  } else {
                    windowManager.maximize();
                  }
                },
                tooltip: 'Maximize',
              ),
              _WindowButton(
                icon: Icons.close,
                onPressed: () => windowManager.close(),
                tooltip: 'Close',
                isClose: true,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _WindowButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final String tooltip;
  final bool isClose;

  const _WindowButton({
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.isClose = false,
  });

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Tooltip(
        message: widget.tooltip,
        waitDuration: const Duration(milliseconds: 500),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onPressed,
            child: Container(
              width: 46,
              height: double.infinity,
              color: _isHovered
                  ? (widget.isClose ? Colors.red.shade700 : Colors.white.withOpacity(0.1))
                  : Colors.transparent,
              child: Icon(
                widget.icon,
                color: Colors.white,
                size: 16,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

