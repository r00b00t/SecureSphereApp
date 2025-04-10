import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:bip39/bip39.dart' as bip39;

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final seedPhraseController = TextEditingController();
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Login with Seed Phrase'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Enter your 12-word seed phrase',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            TextField(
              controller: seedPhraseController,
              maxLines: 3,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Enter your 12-word seed phrase here',
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                final isValid = bip39.validateMnemonic(seedPhraseController.text);
                if (isValid) {
                  // TODO: Verify seed phrase matches stored one
                  Get.offAllNamed('/home');
                } else {
                  Get.snackbar('Error', 'Invalid seed phrase');
                }
              },
              child: const Text('Login'),
            ),
            TextButton(
              onPressed: () {
                // TODO: Implement recovery flow
              },
              child: const Text('Forgot seed phrase?'),
            ),
          ],
        ),
      ),
    );
  }
}