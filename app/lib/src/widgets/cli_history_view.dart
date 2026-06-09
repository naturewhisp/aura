import 'dart:async';
import 'package:flutter/material.dart';
import 'package:aura_core/aura_core.dart';
import '../state_management/game_controller_notifier.dart';

class CLIHistoryView extends StatefulWidget {
  final List<MessageEnvelope> history;
  final bool isLoading;
  final String currentLoadingMessage;
  final Stream<InferenceStep> stepStream;

  const CLIHistoryView({
    Key key,
    required this.history,
    required this.isLoading,
    required this.currentLoadingMessage,
    required this.stepStream,
  }) : super(key: key);

  @override
  State<CLIHistoryView> createState() => _CLIHistoryViewState();
}

class _CLIHistoryViewState extends State<CLIHistoryView> {
  final ScrollController _scrollController = ScrollController();
  
  // Typewriter state variables
  String _typedText = "";
  Timer _typewriterTimer;
  int _charIndex = 0;
  String _lastTypewrittenMessageId = "";
  
  // Real-time loading steps stream buffer
  final List<String> _loadingLogs = [];
  StreamSubscription<InferenceStep> _stepSubscription;

  @override
  void initState() {
    super.initState();
    _stepSubscription = widget.stepStream.listen((step) {
      if (mounted) {
        setState(() {
          _loadingLogs.add("[PID ${1000 + _loadingLogs.length}] ${step.message}");
          _scrollToBottom();
        });
      }
    });
  }

  @override
  void didUpdateWidget(covariant CLIHistoryView oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // Clear loading logs once inference completes
    if (!widget.isLoading && oldWidget.isLoading) {
      _loadingLogs.clear();
    }
    
    // Check if there is a new bot message to typewrite
    if (widget.history.isNotEmpty) {
      final lastMsg = widget.history.last;
      if (lastMsg.role == 'model' && lastMsg.id != _lastTypewrittenMessageId) {
        _startTypewriter(lastMsg.content, lastMsg.id);
      }
    }
    
    _scrollToBottom();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _typewriterTimer?.cancel();
    _stepSubscription?.cancel();
    super.dispose();
  }

  void _startTypewriter(String text, String messageId) {
    _typewriterTimer?.cancel();
    _lastTypewrittenMessageId = messageId;
    _typedText = "";
    _charIndex = 0;

    _typewriterTimer = Timer.periodic(const Duration(milliseconds: 15), (timer) {
      if (_charIndex < text.length) {
        setState(() {
          _typedText += text[_charIndex];
          _charIndex++;
          _scrollToBottom();
        });
      } else {
        timer.cancel();
      }
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.all(16.0),
      child: ListView.builder(
        controller: _scrollController,
        itemCount: widget.history.length + (widget.isLoading ? 1 + _loadingLogs.length : 0),
        itemBuilder: (context, index) {
          // 1. Render standard history items
          if (index < widget.history.length) {
            final msg = widget.history[index];
            final isUser = msg.role == 'user';
            
            // If it is the last message and is currently being typewritten
            final isLastModelMsg = !isUser && index == widget.history.length - 1;
            final displayText = isLastModelMsg ? _typedText : msg.content;
            
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6.0),
              child: CrossFade(
                firstChild: _buildMessageRow(isUser, displayText),
                secondChild: _buildMessageRow(isUser, msg.content),
                crossFadeState: isLastModelMsg ? CrossFadeState.showFirst : CrossFadeState.showSecond,
                duration: Duration.zero,
              ),
            );
          }
          
          // 2. Render loading indicators (if isLoading is true)
          final loadingIndex = index - widget.history.length;
          
          if (loadingIndex < _loadingLogs.length) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4.0),
              child: Text(
                _loadingLogs[loadingIndex],
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 14.0,
                  color: Colors.orange.shade700.withOpacity(0.8),
                ),
              ),
            );
          } else {
            // Render active loading message
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6.0),
              child: Row(
                children: [
                  const SizedBox(
                    width: 12.0,
                    height: 12.0,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.0,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
                    ),
                  ),
                  const SizedBox(width: 8.0),
                  Text(
                    widget.currentLoadingMessage,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 14.0,
                      color: Colors.orange,
                    ),
                  ),
                ],
              ),
            );
          }
        },
      ),
    );
  }

  Widget _buildMessageRow(bool isUser, String text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isUser ? "AURA_USER" : "PANOPTICON",
          style: TextStyle(
            fontFamily: 'monospace',
            fontWeight: FontWeight.bold,
            fontSize: 12.0,
            color: isUser 
                ? const Color(0xFF00FFFF) // Cyan
                : const Color(0xFF00FF66), // Green
          ),
        ),
        const SizedBox(height: 2.0),
        Text(
          text,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 15.0,
            color: isUser 
                ? Colors.white 
                : const Color(0xFF00FF66), // Green
          ),
        ),
      ],
    );
  }
}
