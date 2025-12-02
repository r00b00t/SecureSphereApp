import 'package:flutter/material.dart';
import 'package:decvault/common/widgets/app_drawer.dart';
import 'package:decvault/features/about/widgets/about_content.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: const Text('About'),
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF121212),
              const Color(0xFF1E1E1E),
              Theme.of(context).primaryColor.withOpacity(0.08),
            ],
          ),
        ),
        child: const SingleChildScrollView(
          padding: EdgeInsets.all(24),
          child: AboutContent(),
        ),
      ),
    );
  }
}

