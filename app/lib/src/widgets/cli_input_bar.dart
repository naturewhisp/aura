import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Interactive retro-terminal input field.
class CLIInputBar extends StatefulWidget {
  final bool isDisabled;
  final bool isGameOver;
  final ValueChanged<String> onSubmit;

  const CLIInputBar({
    Key? key,
    required this.isDisabled,
    this.isGameOver = false,
    required this.onSubmit,
  }) : super(key: key);

  @override
  State<CLIInputBar> createState() => _CLIInputBarState();
}

class _CLIInputBarState extends State<CLIInputBar> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  
  // Command history buffer
  final List<String> _history = [];
  int _historyIndex = -1;

  @override
  void initState() {
    super.initState();
    // Auto-focus the input bar when created or updated
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !widget.isDisabled && !widget.isGameOver) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void didUpdateWidget(covariant CLIInputBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Auto-refocus once inference completes and the input bar is enabled again
    if (!widget.isDisabled && !widget.isGameOver && (oldWidget.isDisabled || oldWidget.isGameOver)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _focusNode.requestFocus();
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleSubmit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    // Add to history and reset index
    _history.add(text);
    _historyIndex = -1;

    _controller.clear();
    widget.onSubmit(text);
  }

  void _handleHistoryUp() {
    if (_history.isEmpty) return;
    
    setState(() {
      if (_historyIndex == -1) {
        _historyIndex = _history.length - 1;
      } else if (_historyIndex > 0) {
        _historyIndex--;
      }
      _controller.text = _history[_historyIndex];
      // Move cursor to end
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: _controller.text.length),
      );
    });
  }

  void _handleHistoryDown() {
    if (_history.isEmpty || _historyIndex == -1) return;

    setState(() {
      if (_historyIndex < _history.length - 1) {
        _historyIndex++;
        _controller.text = _history[_historyIndex];
      } else {
        _historyIndex = -1;
        _controller.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Retro Terminal styles
    final textStyle = TextStyle(
      fontFamily: 'monospace',
      fontSize: 16.0,
      fontWeight: FontWeight.bold,
      color: widget.isGameOver
          ? Colors.red.shade700
          : widget.isDisabled 
              ? Colors.orange.shade700 
              : const Color(0xFF00FF66), // Phosphor green
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      decoration: BoxDecoration(
        color: Colors.black,
        border: Border(
          top: BorderSide(
            color: widget.isGameOver
                ? Colors.red.shade900.withOpacity(0.5)
                : widget.isDisabled 
                    ? Colors.orange.shade900.withOpacity(0.5)
                    : const Color(0xFF005522),
            width: 2.0,
          ),
        ),
      ),
      child: RawKeyboardListener(
        focusNode: FocusNode(skipTraversal: true), // Catch arrow keys before they shift focus
        onKey: (RawKeyEvent event) {
          if (event is RawKeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
              _handleHistoryUp();
            } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
              _handleHistoryDown();
            }
          }
        },
        child: Row(
          children: [
            Text(
              widget.isGameOver
                  ? "AURA_DISCONNECTED> "
                  : widget.isDisabled 
                      ? "PANOPTICON_SYS> " 
                      : "AURA_USER> ",
              style: textStyle,
            ),
            Expanded(
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                enabled: !widget.isDisabled && !widget.isGameOver,
                cursorColor: const Color(0xFF00FF66),
                style: textStyle,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                onSubmitted: (_) => _handleSubmit(),
              ),
            ),
            if (widget.isDisabled)
              const SizedBox(
                width: 14.0,
                height: 14.0,
                child: CircularProgressIndicator(
                  strokeWidth: 2.0,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
