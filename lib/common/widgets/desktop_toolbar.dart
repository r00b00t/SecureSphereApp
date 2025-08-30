import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class DesktopToolbar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  final Widget? searchField;
  final VoidCallback? onBackPressed;
  final List<ToolbarAction>? customActions;

  const DesktopToolbar({
    super.key,
    required this.title,
    this.actions,
    this.searchField,
    this.onBackPressed,
    this.customActions,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: preferredSize.height,
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        border: Border(
          bottom: BorderSide(color: Color(0xFF3C4043), width: 1),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            // Back button (if provided)
            if (onBackPressed != null) ...[
              IconButton(
                onPressed: onBackPressed,
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Back',
              ),
              const SizedBox(width: 8),
            ],
            
            // Title
            Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            
            const SizedBox(width: 24),
            
            // Search field (if provided)
            if (searchField != null) ...[
              Expanded(flex: 2, child: searchField!),
              const SizedBox(width: 16),
            ] else
              const Spacer(),
            
            // Custom actions
            if (customActions != null)
              ...customActions!.map((action) => Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Tooltip(
                  message: action.tooltip ?? action.label,
                  child: action.isButton 
                      ? ElevatedButton.icon(
                          onPressed: action.onPressed,
                          icon: Icon(action.icon, size: 18),
                          label: Text(action.label),
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(120, 36),
                          ),
                        )
                      : IconButton(
                          onPressed: action.onPressed,
                          icon: Icon(action.icon),
                          tooltip: action.tooltip ?? action.label,
                        ),
                ),
              )),
            
            // Default actions
            if (actions != null) ...actions!,
          ],
        ),
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(60);
}

class ToolbarAction {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;
  final bool isButton;
  final String? shortcut;

  const ToolbarAction({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.isButton = false,
    this.shortcut,
  });
}

class DesktopSearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onClear;
  final FocusNode? focusNode;

  const DesktopSearchField({
    super.key,
    required this.controller,
    required this.hintText,
    this.onChanged,
    this.onClear,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 400),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: hintText,
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: controller.text.isNotEmpty && onClear != null
              ? IconButton(
                  onPressed: onClear,
                  icon: const Icon(Icons.clear, size: 20),
                  iconSize: 20,
                )
              : null,
          contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: const BorderSide(color: Color(0xFF3C4043)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: const BorderSide(color: Color(0xFF3C4043)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: const BorderSide(color: Color(0xFF34A853), width: 2),
          ),
          filled: true,
          fillColor: const Color(0xFF2C2C2C),
        ),
      ),
    );
  }
}

class DesktopContextMenu extends StatelessWidget {
  final List<ContextMenuItem> items;
  final Widget child;

  const DesktopContextMenu({
    super.key,
    required this.items,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onSecondaryTapDown: (details) {
        _showContextMenu(context, details.globalPosition);
      },
      child: child,
    );
  }

  void _showContextMenu(BuildContext context, Offset position) {
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 1,
        position.dy + 1,
      ),
      items: items.map((item) => PopupMenuItem(
        value: item.value,
        child: Row(
          children: [
            if (item.icon != null) ...[
              Icon(item.icon, size: 18, color: item.isDestructive ? Colors.red : null),
              const SizedBox(width: 8),
            ],
            Text(
              item.label,
              style: TextStyle(
                color: item.isDestructive ? Colors.red : null,
              ),
            ),
            if (item.shortcut != null) ...[
              const Spacer(),
              Text(
                item.shortcut!,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      )).toList(),
    ).then((value) {
      if (value != null) {
        final item = items.firstWhere((item) => item.value == value);
        item.onTap();
      }
    });
  }
}

class ContextMenuItem {
  final String value;
  final String label;
  final IconData? icon;
  final VoidCallback onTap;
  final String? shortcut;
  final bool isDestructive;

  const ContextMenuItem({
    required this.value,
    required this.label,
    required this.onTap,
    this.icon,
    this.shortcut,
    this.isDestructive = false,
  });
} 