import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text("Settings & Setup"),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppTheme.backgroundGradient,
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // iOS Shortcuts Guide Section
                _buildSectionHeader("iOS Shortcut Setup Guide", Icons.settings_input_component_rounded),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: AppTheme.glassDecoration(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "A native iOS App Shortcut is bundled directly into Peraj AI CRM. No manual setup needed!",
                        style: TextStyle(color: AppTheme.accentCyan, fontWeight: FontWeight.bold, fontSize: 13, height: 1.4),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        "Follow these simple steps to map your physical side / Action button to recording:",
                        style: TextStyle(color: AppTheme.textSecondary, fontSize: 12.5, height: 1.4),
                      ),
                      const Divider(color: AppTheme.borderLight, height: 24),
                      _buildStep(
                        1,
                        "Map to Action Button",
                        "Go to iOS Settings → Action Button. Swipe to 'Shortcut', tap 'Choose a Shortcut', and select the pre-loaded 'Record Voice Note' shortcut under the 'Peraj AI CRM' app.",
                      ),
                      _buildStep(
                        2,
                        "Alternative: Map to Back Tap",
                        "If your iPhone does not have a physical Action Button, go to Settings → Accessibility → Touch → Back Tap → Double Tap, and assign it to the 'Record Voice Note' shortcut under the 'Peraj AI CRM' app.",
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Section Header Builder
  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: AppTheme.accentMagenta, size: 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: -0.2),
        ),
      ],
    );
  }

  // Setup Step Builder
  Widget _buildStep(int stepNum, String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Step number badge
          Container(
            width: 24,
            height: 24,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: AppTheme.primaryGradient,
            ),
            child: Center(
              child: Text(
                stepNum.toString(),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Step details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textPrimary),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12.5, height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
