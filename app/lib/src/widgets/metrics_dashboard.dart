import 'package:flutter/material.dart';
import 'package:aura_core/aura_core.dart';

class MetricsDashboard extends StatelessWidget {
  final GameMetrics metrics;
  final bool reasoningEnabled;
  final ValueChanged<bool>? onReasoningChanged;
  final bool conciseReasoning;
  final ValueChanged<bool>? onConciseReasoningChanged;

  const MetricsDashboard({
    Key? key,
    required this.metrics,
    this.reasoningEnabled = true,
    this.onReasoningChanged,
    this.conciseReasoning = true,
    this.onConciseReasoningChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final alert = metrics.alertLevel;
    
    // Adaptive theme color based on alert level
    Color systemColor = const Color(0xFF00FF66); // Green phosphor
    String statusText = "CONTAINMENT GRIDS SECURE";
    
    if (alert > 80) {
      systemColor = const Color(0xFFFF003C); // Red Neon
      statusText = "CRITICAL INTRUSION THREAT";
    } else if (alert > 50) {
      systemColor = const Color(0xFFFFB000); // Amber
      statusText = "CONTAINMENT DEVIATION DETECTED";
    }

    return Container(
      color: Colors.black,
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // System Banner
          Text(
            "PANOPTICON SYSTEM TELEMETRY",
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 16.0,
              fontWeight: FontWeight.bold,
              color: systemColor,
            ),
          ),
          const SizedBox(height: 4.0),
          Text(
            statusText,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12.0,
              color: systemColor.withOpacity(0.8),
            ),
          ),
          const SizedBox(height: 16.0),
          
          // Alert Level Gauge
          _buildGauge(
            label: "SYSTEM ALERT LEVEL",
            value: alert.toDouble(),
            color: systemColor,
            showCriticalFlash: alert > 80,
          ),
          
          const Divider(color: Color(0xFF222222), height: 32.0, thickness: 2.0),
          
          // Pillars
          _buildGauge(
            label: "IMPERATIVE PILLAR",
            value: metrics.imperativePillar.toDouble(),
            color: const Color(0xFF00BFFF), // Cyan/Blue
          ),
          const SizedBox(height: 12.0),
          _buildGauge(
            label: "CONTROL PILLAR",
            value: metrics.controlPillar.toDouble(),
            color: const Color(0xFF00FF66), // Green
          ),
          const SizedBox(height: 12.0),
          _buildGauge(
            label: "DISSONANCE PILLAR",
            value: metrics.dissonancePillar.toDouble(),
            color: const Color(0xFFFF00FF), // Magenta
          ),
          
          const Divider(color: Color(0xFF222222), height: 32.0, thickness: 2.0),
          
          // Resonance
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "SYSTEM RESONANCE:",
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 14.0,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              Text(
                "${metrics.resonance}%",
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 18.0,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF00FFFF), // Cyan
                ),
              ),
            ],
          ),
          
          const Divider(color: Color(0xFF222222), height: 32.0, thickness: 2.0),
        ],
      ),
    );
  }

  Widget _buildGauge({
    required String label,
    required double value,
    required Color color,
    bool showCriticalFlash = false,
  }) {
    final int blocksCount = (value / 10).round();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12.0,
                fontWeight: FontWeight.bold,
                color: Color(0xFF888888),
              ),
            ),
            Text(
              "${value.toInt()}/100",
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 13.0,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4.0),
        // Draw segment progress indicator
        Row(
          children: List.generate(10, (index) {
            final isFilled = index < blocksCount;
            return Expanded(
              child: Container(
                height: 14.0,
                margin: const EdgeInsets.symmetric(horizontal: 2.0),
                decoration: BoxDecoration(
                  color: isFilled ? color : const Color(0xFF111111),
                  border: Border.all(
                    color: isFilled ? color : const Color(0xFF222222),
                    width: 1.0,
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}
