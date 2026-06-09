import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:aura_core/aura_core.dart';
import '../state_management/game_controller_notifier.dart';
import '../widgets/cli_history_view.dart';
import '../widgets/cli_input_bar.dart';
import '../widgets/metrics_dashboard.dart';

class TerminalScreen extends StatefulWidget {
  final GameControllerNotifier notifier;

  const TerminalScreen({
    Key key,
    required this.notifier,
  }) : super(key: key);

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> with SingleTickerProviderStateMixin {
  FragmentShader _shader;
  double _time = 0.0;
  Timer _timer;
  late AnimationController _vignetteController;

  @override
  void initState() {
    super.initState();
    _loadShader();
    
    // Timer to update time uniform in shader
    _timer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      if (mounted) {
        setState(() {
          _time += 0.016;
        });
      }
    });

    // Pulse animation controller for the critical vignette warning
    _vignetteController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  Future<void> _loadShader() async {
    try {
      final program = await FragmentProgram.fromAsset('assets/shaders/glitch.frag');
      if (mounted) {
        setState(() {
          _shader = program.fragmentShader();
        });
      }
    } catch (e) {
      // Graceful fallback to RGB painter if shader compilation is not supported on this platform
      debugPrint("[SHADER] Falling back to custom painter: $e");
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _vignetteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.notifier,
      builder: (context, _) {
        final state = widget.notifier.gameStateNotifier.value;
        final alert = state.metrics.alertLevel;
        final dissonance = state.metrics.dissonancePillar;
        
        // Glitch intensity maps to dissonance above 50
        final double glitchIntensity = dissonance > 70 
            ? ((dissonance - 50) / 50.0).clamp(0.0, 1.0)
            : 0.0;

        return Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              // Main Split Pane Layout
              LayoutBuilder(
                builder: (context, constraints) {
                  final isDesktop = constraints.maxWidth >= 700;
                  
                  if (isDesktop) {
                    return Row(
                      children: [
                        // Left chat and terminal panel (60%)
                        Expanded(
                          flex: 6,
                          child: Column(
                            children: [
                              Expanded(
                                child: _buildGlitchContainer(
                                  intensity: glitchIntensity,
                                  child: CLIHistoryView(
                                    history: state.historyCompression,
                                    isLoading: widget.notifier.isLoading,
                                    currentLoadingMessage: widget.notifier.currentStepMessage,
                                    stepStream: widget.notifier.stepStream,
                                  ),
                                ),
                              ),
                              CLIInputBar(
                                isDisabled: widget.notifier.isLoading,
                                onSubmit: (input) => widget.notifier.submitTurn(input),
                              ),
                            ],
                          ),
                        ),
                        
                        // Vertical Divider
                        Container(
                          width: 2.0,
                          color: const Color(0xFF222222),
                        ),
                        
                        // Right dashboard panel (40%)
                        Expanded(
                          flex: 4,
                          child: MetricsDashboard(metrics: state.metrics),
                        ),
                      ],
                    );
                  } else {
                    // Mobile Portrait layout (vertical split/stacked)
                    return Column(
                      children: [
                        // Small metrics header at the top
                        Container(
                          height: 120.0,
                          decoration: const BoxDecoration(
                            border: Border(
                              bottom: BorderSide(color: Color(0xFF222222), width: 2.0),
                            ),
                          ),
                          child: MetricsDashboard(metrics: state.metrics),
                        ),
                        // Terminal body
                        Expanded(
                          child: _buildGlitchContainer(
                            intensity: glitchIntensity,
                            child: CLIHistoryView(
                              history: state.historyCompression,
                              isLoading: widget.notifier.isLoading,
                              currentLoadingMessage: widget.notifier.currentStepMessage,
                              stepStream: widget.notifier.stepStream,
                            ),
                          ),
                        ),
                        CLIInputBar(
                          isDisabled: widget.notifier.isLoading,
                          onSubmit: (input) => widget.notifier.submitTurn(input),
                        ),
                      ],
                    );
                  }
                },
              ),
              
              // Pulsating Alert Vignette Overlay (when Alert level exceeds 80)
              if (alert > 80)
                IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _vignetteController,
                    builder: (context, child) {
                      final double opacity = 0.05 + (_vignetteController.value * 0.20);
                      return Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: const Color(0xFFFF003C).withOpacity(opacity),
                            width: 24.0,
                          ),
                          gradient: RadialGradient(
                            colors: [
                              Colors.transparent,
                              const Color(0xFFFF003C).withOpacity(opacity * 0.5),
                            ],
                            stops: const [0.7, 1.0],
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  // Wraps UI in FragmentShader or CustomPainter fallback
  Widget _buildGlitchContainer({required double intensity, required Widget child}) {
    if (intensity <= 0.0) return child;
    
    if (_shader != null) {
      return ShaderMask(
        shaderCallback: (rect) {
          _shader.setFloat(0, rect.width);
          _shader.setFloat(1, rect.height);
          _shader.setFloat(2, _time);
          _shader.setFloat(3, intensity);
          // Shader index 4 is the child texture, injected automatically by ShaderMask
          return _shader;
        },
        blendMode: BlendMode.dstIn,
        child: child,
      );
    } else {
      // Graceful CustomPainter RGB shift fallback
      return CustomPaint(
        foregroundPainter: _RGBShiftPainter(intensity: intensity, time: _time),
        child: child,
      );
    }
  }
}

// Fallback painter that renders scanlines and RGB offsets manually
class _RGBShiftPainter extends CustomPainter {
  final double intensity;
  final double time;

  _RGBShiftPainter({required this.intensity, required this.time});

  @override
  void paint(Canvas canvas, Size size) {
    // Draw scanline grid
    final paint = Paint()
      ..color = Colors.green.withOpacity(0.03 * intensity)
      ..strokeWidth = 1.0;

    for (double y = 0.0; y < size.height; y += 4.0) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    
    // Simulate flickering overlay
    if (time % 0.5 < 0.15) {
      final flickerPaint = Paint()
        ..color = const Color(0xFF00FF66).withOpacity(0.015 * intensity);
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), flickerPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _RGBShiftPainter oldDelegate) {
    return oldDelegate.intensity != intensity || oldDelegate.time != time;
  }
}
