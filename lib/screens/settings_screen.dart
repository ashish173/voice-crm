import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _apiKeyController = TextEditingController();
  bool _isSaving = false;
  String _maskedKey = '';

  @override
  void initState() {
    super.initState();
    _loadApiKey();
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  // Load API Key and mask it for security
  Future<void> _loadApiKey() async {
    final key = await StorageService.getGeminiApiKey();
    if (key != null && key.isNotEmpty) {
      setState(() {
        _apiKeyController.text = key;
        _maskedKey = key.length > 12 
            ? '${key.substring(0, 7)}...${key.substring(key.length - 5)}' 
            : 'Key Configured';
      });
    }
  }

  // Save key
  Future<void> _saveApiKey() async {
    setState(() => _isSaving = true);
    final key = _apiKeyController.text.trim();
    await StorageService.saveGeminiApiKey(key);
    await _loadApiKey();
    setState(() => _isSaving = false);
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(key.isEmpty ? "API Key removed" : "API Key saved successfully!"),
        backgroundColor: AppTheme.accentViolet,
      ),
    );
  }

  // Test URL scheme launcher helper
  void _testDeepLink() async {
    final uri = Uri.parse("whisperflow://record");
    
    // Alert the user we are testing, then try to pop and route
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Triggering test deep-link 'whisperflow://record'...")),
    );
    
    // We can launch it via url_launcher to test system scheme registration,
    // or simulate routing. Launching is more realistic!
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        // Fallback for simulators or unsupported platforms
        Navigator.pop(context); // Go back home
        // Delay and open recording manually to simulate deep link route
        Future.delayed(const Duration(milliseconds: 200), () {
          // Open recording screen
          Navigator.pushNamed(context, '/record');
        });
      }
    } catch (e) {
      print("Error testing deep link: $e");
    }
  }

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
                // 1. API Configuration Section
                _buildSectionHeader("Gemini AI Integration", Icons.auto_awesome_rounded),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: AppTheme.glassDecoration(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Configure a Gemini API Key to enable voice note transcription, action items extraction, summaries, and tone rewriters.",
                        style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.4),
                      ),
                      const SizedBox(height: 16),
                      if (_maskedKey.isNotEmpty) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text("Status:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.green.withOpacity(0.3)),
                              ),
                              child: Text(
                                _maskedKey,
                                style: const TextStyle(color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                      ],
                      TextField(
                        controller: _apiKeyController,
                        obscureText: true,
                        style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: "Enter Gemini API Key (AIzaSy...)",
                          suffixIcon: _apiKeyController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, color: AppTheme.textMuted),
                                  onPressed: () {
                                    _apiKeyController.clear();
                                    setState(() {});
                                  },
                                )
                              : null,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                                side: const BorderSide(color: AppTheme.borderLight),
                              ),
                            ),
                            onPressed: _isSaving ? null : _saveApiKey,
                            child: _isSaving
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Text("Update Key", style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // 2. iOS Shortcuts Guide Section
                _buildSectionHeader("iOS Shortcut Setup Guide", Icons.settings_input_component_rounded),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: AppTheme.glassDecoration(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "We have built and bundled a native iOS App Shortcut directly into this app. You do not need to create anything manually!",
                        style: TextStyle(color: AppTheme.accentCyan, fontWeight: FontWeight.bold, fontSize: 13, height: 1.4),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        "Follow these simple steps to map your physical side/Action button to recording:",
                        style: TextStyle(color: AppTheme.textSecondary, fontSize: 12.5, height: 1.4),
                      ),
                      const Divider(color: AppTheme.borderLight, height: 24),
                      _buildStep(1, "Map to Action Button", "Go to iOS Settings -> Action Button. Swipe to 'Shortcut', tap 'Choose a Shortcut', and select the pre-loaded 'Record Voice Note' shortcut under the 'Whisperflow' app."),
                      _buildStep(2, "Alternative: Map to Back Tap", "If your iPhone does not have a physical Action Button, go to Settings -> Accessibility -> Touch -> Back Tap -> Double Tap, and assign it to the 'Record Voice Note' shortcut under the 'Whisperflow' app."),
                      _buildStep(3, "Trigger via Siri voice command", "Alternatively, you can just say: 'Hey Siri, Record Voice Note in Whisperflow' to start capturing voice notes instantly."),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // 3. Testing Section
                _buildSectionHeader("Developer Testing Tools", Icons.construction_rounded),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: AppTheme.glassDecoration(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Test deep link configuration locally. This will invoke the app's link router and immediately open the recording interface.",
                        style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.4),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.accentCyan.withOpacity(0.15),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                              side: const BorderSide(color: AppTheme.accentCyan, width: 1),
                            ),
                          ),
                          onPressed: _testDeepLink,
                          icon: const Icon(Icons.bolt, color: AppTheme.accentCyan, size: 18),
                          label: const Text(
                            "Simulate 'whisperflow://record'",
                            style: TextStyle(color: AppTheme.accentCyan, fontWeight: FontWeight.bold),
                          ),
                        ),
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
