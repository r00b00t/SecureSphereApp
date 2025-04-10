import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:bip39/bip39.dart' as bip39;

class SeedPhraseScreen extends StatelessWidget {
  const SeedPhraseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final seedPhrase = bip39.generateMnemonic();
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Secure Authentication'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Your Secure Seed Phrase',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                seedPhrase,
                style: const TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Write this down and keep it safe. This is your only way to recover your account.',
              style: TextStyle(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const Spacer(),
            ElevatedButton(
              onPressed: () {
                // TODO: Store seed phrase securely
                Get.offAllNamed('/home');
              },
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );
  }
}