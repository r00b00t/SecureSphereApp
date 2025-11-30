import 'package:flutter/material.dart';
import 'package:decvault/features/subscription/widgets/pro_feature_gate.dart';
import 'package:decvault/features/password/screens/breach_monitoring_screen.dart';

/// Gated version of Breach Monitoring Screen
/// This screen is only available to Pro subscribers
class BreachMonitoringScreenGated extends StatelessWidget {
  const BreachMonitoringScreenGated({super.key});

  @override
  Widget build(BuildContext context) {
    return ProFeatureGate(
      featureName: 'Advanced Breach Monitoring',
      featureDescription: 'Monitor your passwords for data breaches in real-time and get instant alerts when your credentials are compromised.',
      child: const BreachMonitoringScreen(),
    );
  }
}



