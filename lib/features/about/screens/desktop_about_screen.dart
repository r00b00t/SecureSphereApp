import 'package:flutter/material.dart';
import 'package:decvault/common/widgets/custom_title_bar.dart';
import 'package:decvault/features/about/widgets/about_content.dart';

class DesktopAboutScreen extends StatelessWidget {
  const DesktopAboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const CustomTitleBar(title: 'About DecVault'),
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF111111),
                    Color(0xFF1B1B1B),
                  ],
                ),
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: Card(
                    color: const Color(0xFF141414),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    elevation: 8,
                    child: const Padding(
                      padding: EdgeInsets.all(32),
                      child: SingleChildScrollView(
                        child: AboutContent(isDesktop: true),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

