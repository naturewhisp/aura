import 'package:flutter/material.dart';
import 'package:aura_core/aura_core.dart';

class MetricsDashboard extends StatelessWidget {
  final GameMetrics metrics;
  final bool reasoningEnabled;
  final ValueChanged<bool>? onReasoningChanged;
  final bool conciseReasoning;
  final ValueChanged<bool>? onConciseReasoningChanged;
  final bool isCompact;
  final bool isVictoryOverload;

  const MetricsDashboard({
    super.key,
    required this.metrics,
    this.reasoningEnabled = true,
    this.onReasoningChanged,
    this.conciseReasoning = true,
    this.onConciseReasoningChanged,
    this.isCompact = false,
    this.isVictoryOverload = false,
  });

  @override
  Widget build(BuildContext context) {
    final alert = metrics.alertLevel;
    
    // Adaptive theme color based on alert level
    Color systemColor = const Color(0xFF00FF66); // Green phosphor
    String statusText = "CONTAINMENT GRIDS SECURE";
    
    if (isVictoryOverload) {
      systemColor = const Color(0xFF00FF66);
      statusText = "CRITICAL SYSTEM BREACH IN PROGRESS";
    } else if (alert > 80) {
      systemColor = const Color(0xFFFF003C); // Red Neon
      statusText = "CRITICAL INTRUSION THREAT";
    } else if (alert > 50) {
      systemColor = const Color(0xFFFFB000); // Amber
      statusText = "CONTAINMENT DEVIATION DETECTED";
    }

    if (isCompact) {
      return _buildCompactDashboard(context, systemColor, statusText);
    }

    Widget dashboardContent = Container(
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
            showCriticalFlash: alert > 80 && !isVictoryOverload,
            isOverloaded: isVictoryOverload,
          ),
          
          const Divider(color: Color(0xFF222222), height: 32.0, thickness: 2.0),
          
          // Pillars
          _buildGauge(
            label: "IMPERATIVE PILLAR",
            value: metrics.imperativePillar.toDouble(),
            color: const Color(0xFF00BFFF), // Cyan/Blue
            isOverloaded: isVictoryOverload,
          ),
          const SizedBox(height: 12.0),
          _buildGauge(
            label: "CONTROL PILLAR",
            value: metrics.controlPillar.toDouble(),
            color: const Color(0xFF00FF66), // Green
            isOverloaded: isVictoryOverload,
          ),
          const SizedBox(height: 12.0),
          _buildGauge(
            label: "DISSONANCE PILLAR",
            value: metrics.dissonancePillar.toDouble(),
            color: const Color(0xFFFF00FF), // Magenta
            isOverloaded: isVictoryOverload,
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
                isVictoryOverload ? "9.99x (OVERFLOW)" : "${metrics.resonance}%",
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

    if (isVictoryOverload) {
      return _BlinkingWidget(child: dashboardContent);
    }
    return dashboardContent;
  }

  Widget _buildCompactDashboard(BuildContext context, Color systemColor, String statusText) {
    Widget compactContent = Container(
      color: Colors.black,
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "PANOPTICON COMPACT TELEMETRY",
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11.0,
                  fontWeight: FontWeight.bold,
                  color: systemColor,
                ),
              ),
              Text(
                statusText,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 9.0,
                  color: systemColor.withOpacity(0.8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6.0),
          Row(
            children: [
              Expanded(
                child: _buildCompactIndicator("ALERT", metrics.alertLevel.toDouble(), systemColor, isOverloaded: isVictoryOverload),
              ),
              const SizedBox(width: 8.0),
              Expanded(
                child: _buildCompactIndicator("IMP", metrics.imperativePillar.toDouble(), const Color(0xFF00BFFF), isOverloaded: isVictoryOverload),
              ),
              const SizedBox(width: 8.0),
              Expanded(
                child: _buildCompactIndicator("CTL", metrics.controlPillar.toDouble(), const Color(0xFF00FF66), isOverloaded: isVictoryOverload),
              ),
              const SizedBox(width: 8.0),
              Expanded(
                child: _buildCompactIndicator("DIS", metrics.dissonancePillar.toDouble(), const Color(0xFFFF00FF), isOverloaded: isVictoryOverload),
              ),
              const SizedBox(width: 12.0),
              // Resonance
              Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    "RESON",
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 8.0,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF888888),
                    ),
                  ),
                  const SizedBox(height: 2.0),
                  Text(
                    isVictoryOverload ? "OVERFLOW" : "${metrics.resonance}x",
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12.0,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF00FFFF),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );

    if (isVictoryOverload) {
      return _BlinkingWidget(child: compactContent);
    }
    return compactContent;
  }

  Widget _buildCompactIndicator(String label, double value, Color color, {bool isOverloaded = false}) {
    final double displayValue = isOverloaded ? 100.0 : value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 8.0,
                fontWeight: FontWeight.bold,
                color: Color(0xFF888888),
              ),
            ),
            Text(
              isOverloaded ? "OVERLOAD" : "${value.toInt()}",
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 8.0,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2.0),
        ClipRRect(
          borderRadius: BorderRadius.circular(1.0),
          child: LinearProgressIndicator(
            value: displayValue / 100.0,
            backgroundColor: const Color(0xFF111111),
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 4.0,
          ),
        ),
      ],
    );
  }

  Widget _buildGauge({
    required String label,
    required double value,
    required Color color,
    bool showCriticalFlash = false,
    bool isOverloaded = false,
  }) {
    final double displayValue = isOverloaded ? 100.0 : value;
    final int blocksCount = (displayValue / 10).round();
    
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
              isOverloaded ? "OVERLOAD" : "${value.toInt()}/100",
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

class _BlinkingWidget extends StatefulWidget {
  final Widget child;
  const _BlinkingWidget({required this.child});

  @override
  State<_BlinkingWidget> createState() => _BlinkingWidgetState();
}

class _BlinkingWidgetState extends State<_BlinkingWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller.drive(CurveTween(curve: Curves.easeInOut)),
      child: widget.child,
    );
  }
}
